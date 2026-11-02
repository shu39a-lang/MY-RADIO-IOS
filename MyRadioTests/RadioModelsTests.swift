import XCTest
@testable import MyRadio

final class RadioModelsTests: XCTestCase {
    func testProfileDefaultsToTenMinutes() {
        let profile = ListenerProfile()
        XCTAssertEqual(profile.validMinutes, 10)
        XCTAssertTrue(profile.interests.isEmpty)
    }

    func testInvalidDurationFallsBackToTen() {
        var profile = ListenerProfile()
        profile.minutes = 999
        XCTAssertEqual(profile.validMinutes, 10)
    }

    func testProfileCanBeSavedAndRestored() throws {
        var profile = ListenerProfile()
        profile.detail = "1970年代のフォーク"
        profile.avoid = "スポーツ"
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ListenerProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
    }
}
