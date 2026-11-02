import Foundation

/// Local-first listener profile. New keys decode with defaults so existing TestFlight
/// installations keep their saved preferences when updating from version 0.1.
struct ListenerProfile: Codable, Equatable {
    var nickname = ""
    var ageGroup = "回答しない"
    var gender = "回答しない"
    var area = ""
    var interests: [String] = []
    var detail = ""
    var avoid = ""
    var style = "親しみやすいDJ"
    var minutes = 10
    var preferredTopics: [String] = []
    var reminderEnabled = false
    var reminderMinutes = 7 * 60

    // v0.2: an explicit, independently editable preference for every topic.
    var customTopics: [String] = []
    var topicImportance: [String: Int] = [:] // 1: 少し, 2: 好き, 3: 最優先
    var topicNotes: [String: String] = [:]
    var favoritePeople = ""
    var listeningGoal = "楽しく知識を増やしたい"
    var depth = "わかりやすく"
    var includeNews = true
    var voiceID = "cedar"

    init() {}

    enum CodingKeys: String, CodingKey {
        case nickname, ageGroup, gender, area, interests, detail, avoid, style, minutes
        case preferredTopics, reminderEnabled, reminderMinutes
        case customTopics, topicImportance, topicNotes, favoritePeople, listeningGoal, depth, includeNews, voiceID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname) ?? ""
        ageGroup = try c.decodeIfPresent(String.self, forKey: .ageGroup) ?? "回答しない"
        gender = try c.decodeIfPresent(String.self, forKey: .gender) ?? "回答しない"
        area = try c.decodeIfPresent(String.self, forKey: .area) ?? ""
        interests = try c.decodeIfPresent([String].self, forKey: .interests) ?? []
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        avoid = try c.decodeIfPresent(String.self, forKey: .avoid) ?? ""
        style = try c.decodeIfPresent(String.self, forKey: .style) ?? "親しみやすいDJ"
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 10
        preferredTopics = try c.decodeIfPresent([String].self, forKey: .preferredTopics) ?? []
        reminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? false
        reminderMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderMinutes) ?? 7 * 60
        customTopics = try c.decodeIfPresent([String].self, forKey: .customTopics) ?? []
        topicImportance = try c.decodeIfPresent([String: Int].self, forKey: .topicImportance) ?? [:]
        topicNotes = try c.decodeIfPresent([String: String].self, forKey: .topicNotes) ?? [:]
        favoritePeople = try c.decodeIfPresent(String.self, forKey: .favoritePeople) ?? ""
        listeningGoal = try c.decodeIfPresent(String.self, forKey: .listeningGoal) ?? "楽しく知識を増やしたい"
        depth = try c.decodeIfPresent(String.self, forKey: .depth) ?? "わかりやすく"
        includeNews = try c.decodeIfPresent(Bool.self, forKey: .includeNews) ?? true
        voiceID = try c.decodeIfPresent(String.self, forKey: .voiceID) ?? "cedar"
    }

    static let interestOptions = [
        "音楽・楽器", "株式・経済", "健康・運動", "旅行・観光", "スポーツ", "歴史・文化",
        "科学・AI", "政治・社会", "映画・芸能", "料理・グルメ", "自然・動物", "暮らし",
        "読書・文学", "趣味・DIY", "人生・生き方", "その他"
    ]

    static let goalOptions = ["楽しく知識を増やしたい", "今日のニュースを知りたい", "趣味を深く楽しみたい", "朝から元気を出したい", "リラックスして聴きたい"]
    static let depthOptions = ["やさしく短く", "わかりやすく", "詳しく深掘り"]

    var validMinutes: Int { [5, 10, 20].contains(minutes) ? minutes : 10 }

    var selectedTopics: [String] {
        var seen = Set<String>()
        return (interests + customTopics)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func importance(for topic: String) -> Int {
        max(1, min(3, topicImportance[topic] ?? 2))
    }

    func note(for topic: String) -> String {
        (topicNotes[topic] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var orderedTopics: [String] {
        selectedTopics.enumerated()
            .sorted { left, right in
                let a = importance(for: left.element)
                let b = importance(for: right.element)
                return a == b ? left.offset < right.offset : a > b
            }
            .map(\.element)
    }

    var personalizationCount: Int {
        selectedTopics.count + (detail.isEmpty ? 0 : 1) +
        (favoritePeople.isEmpty ? 0 : 1) + topicNotes.values.filter { !$0.isEmpty }.count
    }
}

struct RadioSource: Codable, Identifiable, Equatable {
    var title: String
    var url: String
    var id: String { url }
}

struct RadioProgram: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var script: String
    var sources: [RadioSource] = []
    var isSample: Bool = false
    var createdAt = Date()
}

struct ProgramRequest: Encodable {
    var profile: ListenerProfile
    var recentTitles: [String]
}

struct ProgramResponse: Decodable {
    var title: String
    var script: String
    var sources: [RadioSource]
}

struct SavedConnection: Codable {
    var serverURL: String = ""
}
