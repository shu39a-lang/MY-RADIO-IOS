import Foundation

enum ProgramError: LocalizedError {
    case invalidURL
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "サーバーのURLを確認してください（https://で始まるURL）。"
        case .server(let message): return "番組の生成に失敗しました：\(message)"
        case .invalidResponse: return "サーバーから正しい番組データを受け取れませんでした。"
        }
    }
}

enum ProgramService {
    static func generate(profile: ListenerProfile, recentTitles: [String], endpoint: String) async throws -> RadioProgram {
        let address = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return DemoProgram.make(profile: profile) }
        guard let url = URL(string: address),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              let apiURL = URL(string: "api/program", relativeTo: url.appendingPathComponent("/"))?.absoluteURL
        else { throw ProgramError.invalidURL }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = CredentialVault.read()
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.timeoutInterval = 120
        request.httpBody = try JSONEncoder().encode(ProgramRequest(profile: profile, recentTitles: recentTitles))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ProgramError.invalidResponse }
        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 401 { throw ProgramError.server("認証トークンが正しくありません。") }
            throw ProgramError.server("HTTP \(response.statusCode)")
        }
        let payload = try JSONDecoder().decode(ProgramResponse.self, from: data)
        guard !payload.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProgramError.invalidResponse
        }
        return RadioProgram(title: payload.title, script: payload.script, sources: payload.sources)
    }
}

enum DemoProgram {
    static func make(profile: ListenerProfile) -> RadioProgram {
        let nickname = profile.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let greeting = nickname.isEmpty ? "おはようございます" : "\(nickname)さん、おはようございます"
        let interest = profile.interests.first ?? "最近の気になること"
        let extra = profile.detail.isEmpty ? "気になる分野を詳しく登録すると、話題の選び方が変わります。" :
            "詳しく登録していただいた『\(String(profile.detail.prefix(70)))』も番組の構成に取り入れます。"
        let script = """
        \(greeting)。マイラジオへようこそ。
        これは、音声再生と個人設定を確認するためのお試し番組です。実際のAI生成ニュースではありません。
        今日のテーマのひとつは『\(interest)』。あなたが興味を登録した分野を優先して番組を組み立てていきます。
        \(extra)
        本番のマイラジオでは、関心の強い話題を深く掘り下げ、同じ話を繰り返さないよう工夫します。必要に応じて最新の公開情報を確認し、その情報源も画面に示します。
        気になる話題を後から追加したり、聞きたくない話題を除外することもできます。
        今朝も素敵な一日になりますように。それでは、次回の放送をお楽しみに。
        """
        return RadioProgram(title: "マイラジオ・お試し放送", script: script, isSample: true)
    }
}
