import XCTest
@testable import MyRadio

final class PersonalizationTests: XCTestCase {
    func testLegacyProfileLoadsWithoutErasingSavedInterests() throws {
        let old = #"{"nickname":"テスト","interests":["音楽・楽器"],"detail":"70年代フォーク","minutes":10}"#
        let profile = try JSONDecoder().decode(ListenerProfile.self, from: Data(old.utf8))
        XCTAssertEqual(profile.nickname, "テスト")
        XCTAssertEqual(profile.interests, ["音楽・楽器"])
        XCTAssertEqual(profile.detail, "70年代フォーク")
        XCTAssertTrue(profile.customTopics.isEmpty)
        XCTAssertEqual(profile.importance(for: "音楽・楽器"), 2)
    }

    func testPriorityChangesPreviewOrderAndScript() {
        var profile = ListenerProfile()
        profile.interests = ["健康・運動", "音楽・楽器", "旅行・観光"]
        profile.topicImportance["旅行・観光"] = 3
        profile.topicImportance["健康・運動"] = 1
        profile.topicNotes["旅行・観光"] = "京都の寺社や古い町並み"
        let outline = PersonalizationEngine.plannedTopics(profile)
        XCTAssertEqual(outline.first?.topic, "旅行・観光")
        XCTAssertEqual(outline.first?.note, "京都の寺社や古い町並み")
        let script = PersonalizationEngine.sample(profile).script
        XCTAssertTrue(script.contains("京都の寺社や古い町並み"))
        XCTAssertTrue(script.contains("旅行・観光"))
    }

    func testCustomTopicAndExcludedCategory() {
        var profile = ListenerProfile()
        profile.interests = ["スポーツ", "音楽・楽器"]
        profile.customTopics = ["盆栽"]
        profile.topicNotes["盆栽"] = "黒松の剪定"
        profile.avoid = "スポーツ"
        let outline = PersonalizationEngine.plannedTopics(profile)
        XCTAssertFalse(outline.map(\.topic).contains("スポーツ"))
        XCTAssertTrue(outline.map(\.topic).contains("盆栽"))
        XCTAssertTrue(PersonalizationEngine.sample(profile).script.contains("黒松の剪定"))
    }
}
