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
        PersonalizationEngine.sample(profile)
    }
}
