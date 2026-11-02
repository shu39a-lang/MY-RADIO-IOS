import AVFoundation
import Foundation

/// Plays ACTUAL generated MP3 audio. AVSpeechSynthesizer is intentionally not used:
/// the listener requested human-like radio speech, never a device-robot fallback.
@MainActor
final class SpeechPlayer: ObservableObject {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var isPreparing = false
    @Published private(set) var preparationProgress = ""
    @Published var errorMessage: String?

    private var queue: AVQueuePlayer?
    private var completionObserver: NSObjectProtocol?

    func play(_ program: RadioProgram, profile: ListenerProfile, endpoint: String) async {
        guard !isPreparing else { return }
        stop()
        errorMessage = nil
        isPreparing = true
        defer { isPreparing = false }
        do {
            let pieces = SpokenScript.chunks(program.script)
            guard !pieces.isEmpty else { throw ProgramError.invalidResponse }
            var files: [URL] = []
            for (index, text) in pieces.enumerated() {
                try Task.checkCancellation()
                preparationProgress = "自然な音声を制作中（\(index + 1)/\(pieces.count)）"
                let path = try await downloadSpeech(text: text, voice: profile.voiceID,
                                                    style: profile.style, endpoint: endpoint,
                                                    cacheKey: "\(endpoint.isEmpty ? "personal" : "server")-\(program.id.uuidString)-\(profile.voiceID)-\(profile.style)-\(index)")
                files.append(path)
            }
            try configureAudio()
            let items = files.map(AVPlayerItem.init(url:))
            guard let last = items.last else { throw ProgramError.invalidResponse }
            let newQueue = AVQueuePlayer(items: items)
            completionObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: last, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.finish() }
            }
            queue = newQueue
            isSpeaking = true
            isPaused = false
            newQueue.play()
        } catch {
            errorMessage = "自然な音声の生成に失敗しました：\(error.localizedDescription)"
            finish()
        }
    }

    func preview(voice: String, style: String, endpoint: String) async {
        guard !isPreparing else { return }
        stop()
        errorMessage = nil
        isPreparing = true
        preparationProgress = "選んだ声を生成中…"
        defer { isPreparing = false }
        do {
            let snippet = "こんにちは、マイラジオへようこそ。あなたの趣味や興味に合わせて、今日の番組をお届けします。どうぞお楽しみください。"
            let url = try await downloadSpeech(text: snippet, voice: voice, style: style,
                                               endpoint: endpoint, cacheKey: "preview-\(endpoint.isEmpty ? "personal" : "server")-\(voice)-\(style)")
            try configureAudio()
            let item = AVPlayerItem(url: url)
            completionObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in Task { @MainActor in self?.finish() } }
            let newQueue = AVQueuePlayer(items: [item])
            queue = newQueue
            isSpeaking = true
            newQueue.play()
        } catch {
            errorMessage = "音声の試聴に失敗しました：\(error.localizedDescription)"
            finish()
        }
    }

    func togglePause() {
        guard isSpeaking else { return }
        if isPaused { queue?.play(); isPaused = false }
        else { queue?.pause(); isPaused = true }
    }

    func stop() { finish() }

    private func finish() {
        queue?.pause()
        queue?.removeAllItems()
        queue = nil
        if let observer = completionObserver { NotificationCenter.default.removeObserver(observer) }
        completionObserver = nil
        isSpeaking = false
        isPaused = false
        preparationProgress = ""
    }

    private func configureAudio() throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try AVAudioSession.sharedInstance().setActive(true)
    }

    private func downloadSpeech(text: String, voice: String, style: String,
                                endpoint: String, cacheKey: String) async throws -> URL {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MYRADIOAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // cacheKey is composed only of UUID/index/known voice, except style for preview;
        // replace any path punctuation with underscores to keep it in the cache folder.
        let safeKey = cacheKey.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        let fileURL = folder.appendingPathComponent(String(safeKey) + ".mp3")
        if FileManager.default.fileExists(atPath: fileURL.path) { return fileURL }

        let server = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let personal = server.isEmpty
        let apiURL: URL
        if personal {
            apiURL = URL(string: "https://api.openai.com/v1/audio/speech")!
        } else {
            guard let baseURL = URL(string: server), baseURL.scheme?.lowercased() == "https",
                  baseURL.host != nil else { throw ProgramError.invalidURL }
            apiURL = baseURL.appendingPathComponent("api/speech")
        }
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 115
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if personal {
            let key = CredentialVault.readPersonalKey()
            guard !key.isEmpty else { throw ProgramError.server("個人用AIキーが未登録です。AI接続で登録してください。") }
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model":"gpt-4o-mini-tts", "voice":voice, "input":text,
                "instructions":"自然で聞き疲れない日本語のラジオDJ。\(style)。間と柔らかな抑揚を大切に、誇張せず話してください。",
                "response_format":"mp3"
            ])
        } else {
            let token = CredentialVault.read()
            if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            request.httpBody = try JSONEncoder().encode(SpeechRequest(text: text, voice: voice, style: style))
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProgramError.invalidResponse }
        guard (200...299).contains(http.statusCode),
              http.value(forHTTPHeaderField: "Content-Type")?.contains("audio/mpeg") == true,
              data.count > 300 else {
            throw ProgramError.server(http.statusCode == 401 ? "接続トークンが正しくありません" : "音声API HTTP \(http.statusCode)")
        }
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
}

private struct SpeechRequest: Encodable {
    let text: String
    let voice: String
    let style: String
}
