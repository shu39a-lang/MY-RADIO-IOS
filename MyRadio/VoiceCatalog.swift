import Foundation

/// Real speech-provider voice IDs. Labels describe the intended listening impression;
/// listeners can preview each voice. They are not claims about a voice actor's identity.
struct RadioVoice: Identifiable, Hashable {
    let id: String
    let label: String
    let character: String
    let group: String
}

enum VoiceCatalog {
    static let all: [RadioVoice] = [
        .init(id: "cedar", label: "男性系・落ち着いた", character: "自然でゆったり", group: "男性系"),
        .init(id: "onyx", label: "男性系・低音", character: "深く落ち着いた響き", group: "男性系"),
        .init(id: "echo", label: "男性系・柔らかい", character: "親しみのある語り", group: "男性系"),
        .init(id: "ash", label: "男性系・明るい", character: "軽快なラジオDJ", group: "男性系"),
        .init(id: "marin", label: "女性系・自然", character: "滑らかなナレーション", group: "女性系"),
        .init(id: "coral", label: "女性系・親しみやすい", character: "温かみのある話し方", group: "女性系"),
        .init(id: "nova", label: "女性系・明るい", character: "軽やかな語り", group: "女性系"),
        .init(id: "shimmer", label: "女性系・優しい", character: "穏やかな語り", group: "女性系"),
        .init(id: "sage", label: "中性的・落ち着いた", character: "ゆっくり丁寧", group: "その他"),
        .init(id: "alloy", label: "中性的・標準", character: "バランスのよい語り", group: "その他")
    ]
    static func label(for id: String) -> String { all.first(where: { $0.id == id })?.label ?? "男性系・落ち着いた" }
}

/// Speech API accepts at most 4096 characters per request; keep a safe limit well below it.
enum SpokenScript {
    static func chunks(_ script: String, limit: Int = 1450) -> [String] {
        var result: [String] = []
        var part = ""
        for character in script {
            part.append(character)
            let atEndOfSentence = "。！？\n".contains(character)
            if (atEndOfSentence && part.count >= 950) || part.count >= limit {
                let t = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { result.append(t) }
                part = ""
            }
        }
        let tail = part.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(tail) }
        return result
    }
}
