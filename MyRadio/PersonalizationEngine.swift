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

    static func sample(_ profile: ListenerProfile) -> RadioProgram {
        let name = profile.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let greeting = name.isEmpty ? "おはようございます" : "\(String(name.prefix(30)))さん、おはようございます"
        let focuses = plannedTopics(profile)
        let mood: String
        switch profile.listeningGoal {
        case "朝から元気を出したい": mood = "今日も無理のない一歩から始めてみましょう。"
        case "リラックスして聴きたい": mood = "肩の力を抜いて、ゆっくりお楽しみください。"
        default: mood = "あなたの気になる世界を、少しずつ広げていきましょう。"
        }

        var paragraphs = [
            "\(greeting)。マイラジオへようこそ。これは登録内容を実際の声と文章で確認できる、短いお試し放送です。最新ニュースや10分間の本番番組ではありません。",
            "本日の番組は、\(profile.listeningGoal)。\(profile.depth)を基本に、\(profile.style)でお届けします。\(mood)"
        ]
        if focuses.isEmpty {
            paragraphs.append("まず、好みの登録画面で興味のある分野を選んでください。特に好きなものには最優先を付けると、話す順番を変えられます。")
        }
        for (index, focus) in focuses.enumerated() {
            var segment = "\(index + 1)つ目の話題は、\(focus.topic)です。"
            if focus.importance == 3 { segment += "特に関心が高いテーマとして選びました。" }
            if !focus.note.isEmpty {
                segment += "あなたが大切にしている具体的なテーマは、\(focus.note)。その点を中心に深掘りする構成です。"
            } else {
                segment += example(for: focus.topic)
            }
            paragraphs.append(segment)
        }
        let details = profile.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !details.isEmpty { paragraphs.append("さらに詳しい希望として、\(String(details.prefix(180)))。この内容も次の番組の編集方針に反映します。") }
        let people = profile.favoritePeople.trimmingCharacters(in: .whitespacesAndNewlines)
        if !people.isEmpty { paragraphs.append("好きな人物や作品として、\(String(people.prefix(120)))も登録されています。関連する話題を選ぶときの参考にします。") }
        if profile.includeNews {
            paragraphs.append("最新のニュースは、AIサーバーにつながっている場合だけ、確認できた情報源に基づいてお届けします。")
        } else {
            paragraphs.append("ニュースよりも、趣味や知識の特集を中心にしています。")
        }
        paragraphs.append("以上が現在の設定を反映した番組見本です。好きなテーマを増やしたり、興味の強さを変えると、このお試し放送の内容と順番も変わります。\(mood)それでは、またお会いしましょう。")
        return RadioProgram(title: "あなた専用の番組・試聴版", script: paragraphs.joined(separator: "\n\n"), isSample: true)
    }

    private static func example(for topic: String) -> String {
        if topic.contains("音楽") { return "演奏の工夫や好きな音色、懐かしい曲の時代背景などから特集を組み立てます。" }
        if topic.contains("株式") { return "企業の成長や市場の仕組みをわかりやすく考える特集ができます。個別の売買を勧めるものではありません。" }
        if topic.contains("旅行") { return "行きたい場所の文化、季節、移動の楽しみなどから話題を広げます。" }
        if topic.contains("健康") { return "毎日の運動や生活習慣について、一般的な知識を整理する内容にできます。" }
        if topic.contains("歴史") { return "人物や出来事の背景を、物語のように紹介する特集を用意できます。" }
        if topic.contains("科学") { return "身近な技術の仕組みと新しい発見を、難しい言葉を減らして解説できます。" }
        return "好きな理由や特に知りたい部分を登録すると、その点を中心に番組が変わります。"
    }
}
