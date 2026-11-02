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
    static func connectionStatus(endpoint: String) async -> String {
        let text = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return CredentialVault.readPersonalKey().isEmpty
                ? "個人用AIキーを登録してください。"
                : "個人用AIキーが登録されています。新しい番組を作成できます。"
        }
        guard let base = URL(string: text), base.scheme?.lowercased() == "https", base.host != nil else {
            return "専用サーバーのURLが正しくありません。"
        }
        var request = URLRequest(url: base.appendingPathComponent("health"))
        request.timeoutInterval = 12
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let status = try? JSONDecoder().decode(HealthResponse.self, from: data),
                  status.status == "ok" else { return "サーバーが応答しません。URLを確認してください。" }
            return status.aiConfigured == true
                ? "接続成功：本番のAI番組と自然音声が利用可能な設定です。"
                : "サーバー接続は成功しましたが、AI APIキーが未設定です。"
        } catch { return "接続できません。サーバーの公開状態とURLを確認してください。" }
    }
    static func generate(profile: ListenerProfile, recentTitles: [String], endpoint: String) async throws -> RadioProgram {
        let address = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return try await PersonalAIService.generate(profile: profile, recentTitles: recentTitles) }
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

private struct HealthResponse: Decodable {
    let status: String
    let aiConfigured: Bool?
}
