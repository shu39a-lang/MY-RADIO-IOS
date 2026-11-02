import Foundation

struct ProgramFocus: Identifiable, Equatable {
    let topic: String
    let importance: Int
    let note: String
    var id: String { topic }
    var label: String {
        switch importance {
        case 3: return "最優先"
        case 1: return "少し"
        default: return "好き"
        }
    }
}

/// A transparent preview. No fabricated news, web lookups or AI claims.
/// The same prioritized topics and notes are sent to the server for genuine AI generation.
enum PersonalizationEngine {
    static func plannedTopics(_ profile: ListenerProfile) -> [ProgramFocus] {
        let banned = profile.avoid
            .components(separatedBy: CharacterSet(charactersIn: "、,，・\n;；"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
        return profile.orderedTopics
            .filter { topic in !banned.contains(where: { topic.localizedCaseInsensitiveContains($0) }) }
            .prefix(5)
            .map { topic in
                ProgramFocus(topic: topic,
                             importance: profile.importance(for: topic),
                             note: String(profile.note(for: topic).prefix(180)))
            }
    }

    static func previewDescription(_ profile: ListenerProfile) -> String {
        let topics = plannedTopics(profile)
        guard !topics.isEmpty else { return "『好みを登録』から興味のある分野を追加してください。" }
        let first = topics.prefix(3).map(\.topic).joined(separator: "・")
        return "\(first)を中心に、\(profile.depth)・\(profile.style)で構成します。"
    }
}
