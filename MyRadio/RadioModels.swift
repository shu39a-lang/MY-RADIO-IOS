import Foundation

struct ListenerProfile: Codable, Equatable {
    var nickname = ""
    var ageGroup = "回答しない"
    var gender = "回答しない"
    var area = ""
    var interests: [String] = ["音楽・楽器", "健康・運動"]
    var detail = ""
    var avoid = ""
    var style = "親しみやすいDJ"
    var minutes = 10
    var preferredTopics: [String] = []
    var reminderEnabled = false
    var reminderMinutes = 7 * 60

    static let interestOptions = [
        "音楽・楽器", "株式・経済", "健康・運動", "旅行・観光", "スポーツ", "歴史・文化",
        "科学・AI", "政治・社会", "映画・芸能", "料理・グルメ", "自然・動物", "暮らし",
        "読書・文学", "趣味・DIY", "人生・生き方", "その他"
    ]

    var validMinutes: Int { [5, 10, 20].contains(minutes) ? minutes : 10 }
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
