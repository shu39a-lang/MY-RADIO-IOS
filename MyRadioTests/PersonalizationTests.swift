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
        let preview = PersonalizationEngine.previewDescription(profile)
        XCTAssertTrue(preview.contains("旅行・観光"))
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
        XCTAssertEqual(outline.first(where: { $0.topic == "盆栽" })?.note, "黒松の剪定")
    }
}

final class RealRadioVoiceTests: XCTestCase {
    func testVoiceCatalogAndSpeechChunks() {
        XCTAssertGreaterThanOrEqual(VoiceCatalog.all.count, 8)
        XCTAssertTrue(VoiceCatalog.all.contains(where: { $0.id == "cedar" }))
        let chunks = SpokenScript.chunks(String(repeating: "今日は好きな音楽の話です。", count: 500))
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 1450 })
    }
    func testExistingProfileWithoutVoiceDecodes() throws {
        let old = #"{"nickname":"ラジオ好き","interests":["音楽・楽器"]}"#.data(using: .utf8)!
        let profile = try JSONDecoder().decode(ListenerProfile.self, from: old)
        XCTAssertEqual(profile.nickname, "ラジオ好き")
        XCTAssertEqual(profile.voiceID, "cedar")
    }
}
