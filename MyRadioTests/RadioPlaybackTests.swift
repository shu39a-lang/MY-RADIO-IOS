import XCTest
import WebKit
@testable import MyRadio

// Runs the shipped page in WebKit. Speech callbacks and unavailable online services
// are simulated; this tests playback control, not speaker output or voice quality.
@MainActor
final class RadioPlaybackTests: XCTestCase, WKNavigationDelegate, WKScriptMessageHandler {
    private var web: WKWebView!
    private var loaded: XCTestExpectation!
    private var finished: XCTestExpectation!
    private var spoken: [String] = []
    private var saved: [String] = []

    private func openPage(initialScript: String = "") async throws {
        spoken = []; saved = []
        loaded = expectation(description: "Radio page loaded")
        finished = expectation(description: "Program completed")
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: "radio")
        configuration.userContentController.addUserScript(WKUserScript(
            source: initialScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 820, height: 1180), configuration: configuration)
        web.navigationDelegate = self
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("radio.html")
        try EmbeddedRadioPage.html.write(to: file, atomically: true, encoding: .utf8)
        web.loadFileURL(file, allowingReadAccessTo: folder)
        await fulfillment(of: [loaded], timeout: 15)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let payload = message.body as? [String: Any], let type = payload["type"] as? String else { return }
        let id = payload["id"] as? Int ?? 0
        var callback: String?
        switch type {
        case "persistHistory":
            saved.append(payload["value"] as? String ?? "")
            callback = "window.radioHistorySaved({id:\(id),ok:true})"
        case "aiStatus": callback = "window.radioAIStatus({available:false,message:'unavailable'})"
        case "dailyLookup": callback = "window.radioDailyDidFinish({id:\(id),ok:false})"
        case "newsLookup": callback = "window.radioNewsDidFinish({id:\(id),ok:false})"
        case "speak":
            let text = payload["text"] as? String ?? ""
            spoken.append(text)
            if text.contains("今日はこれまで") { finished.fulfill() }
            callback = "window.radioSpeechDidFinish(\(id))"
        default: break
        }
        if let callback = callback {
            DispatchQueue.main.async { [weak self] in
                self?.web?.evaluateJavaScript(callback, completionHandler: nil)
            }
        }
    }

    private func verifyProgram(initialScript: String = "") async throws {
        try await openPage(initialScript: initialScript)
        defer { web.configuration.userContentController.removeScriptMessageHandler(forName: "radio"); web = nil }
        _ = try await web.evaluateJavaScript("document.getElementById('play').click(); true")
        await fulfillment(of: [finished], timeout: 20)
        XCTAssertGreaterThan(spoken.count, 3, "The program must include content after its greeting")
        XCTAssertTrue(spoken.first?.contains("ラジオの時間") == true)
        XCTAssertEqual(spoken.filter { $0.contains("今日はこれまで") }.count, 1)
        XCTAssertFalse(saved.isEmpty)
        let log = try await web.evaluateJavaScript("document.getElementById('log').textContent") as? String ?? ""
        XCTAssertFalse(log.contains("保存できません"))
    }

    func testFreshInstallPlaysWithoutNewsOrAI() async throws { try await verifyProgram() }

    func testUnavailableWebStorageUsesNativeHistory() async throws {
        try await verifyProgram(initialScript: "Storage.prototype.setItem=function(){throw new Error('QuotaExceededError')};")
    }

    func testUpgradeWithInvalidSettingsStillPlays() async throws {
        try await verifyProgram(initialScript: """
        window.__myradioSaved={
          myradio:JSON.stringify({sel:['tech','removed-topic'],styleId:'removed-voice'}),
          myradio_unique_v1:JSON.stringify({seen:{already:1},newsTitles:7,queues:{tech:'invalid'},editorialHistory:[null]})
        };
        """)
    }
}
