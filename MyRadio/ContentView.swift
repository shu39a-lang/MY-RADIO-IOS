import SwiftUI
import WebKit
import AVFoundation
import UserNotifications

struct ContentView: View {
    var body: some View {
        MyRadioHTMLView()
            .ignoresSafeArea(.container, edges: .bottom)
            .preferredColorScheme(.dark)
    }
}

private struct MyRadioHTMLView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "radio")
        let keys = ["myradio", "myradio_played", "myradio_req", "myradio_dv", "myradio_hist"]
        let saved = keys.compactMap { key -> [String: String]? in
            guard let val = UserDefaults.standard.string(forKey: "radio.saved." + key) else { return nil }
            return ["key":key, "value":val]
        }
        if let bytes = try? JSONSerialization.data(withJSONObject: saved),
           let literal = String(data: bytes, encoding: .utf8) {
            let source = "window.__myradioSaved=Object.fromEntries(" + literal + ".map(e=>[e.key,e.value]));try{for(const e of " + literal + "){localStorage.setItem(e.key,e.value)}}catch(e){}"
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        config.userContentController = controller
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 0.13, green: 0.11, blue: 0.11, alpha: 1)
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web
        UNUserNotificationCenter.current().delegate = context.coordinator
        // All display content and articles are compiled into ContentView.swift.
        // This removes the fragile external radio.html copy-resource requirement.
        do {
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("myradio-screen-v043.html")
            try EmbeddedRadioPage.html.write(to: url, atomically: true, encoding: .utf8)
            web.loadFileURL(url, allowingReadAccessTo: folder)
        } catch {
            // Even if the file system is temporarily unavailable, the HTML itself remains in the binary.
            web.loadHTMLString(EmbeddedRadioPage.html, baseURL: nil)
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, AVSpeechSynthesizerDelegate, UNUserNotificationCenterDelegate {
        weak var web: WKWebView?
        private let speech = AVSpeechSynthesizer()
        private var currentID: Int?
        private var pendingLaunchFromNotification = false
        private let notificationID = "jp.myradio.personal.morning"

        override init() { super.init(); speech.delegate = self }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "radio", let payload = message.body as? [String: Any],
                  let type = payload["type"] as? String else { return }
            switch type {
            case "speak":
                guard let text = payload["text"] as? String, let id = payload["id"] as? Int else { return }
                speak(text, id: id, payload: payload)
            case "cancel":
                currentID = nil
                speech.stopSpeaking(at: .immediate)
            case "persist":
                guard let key = payload["key"] as? String,
                      ["myradio", "myradio_played", "myradio_req", "myradio_dv", "myradio_hist"].contains(key),
                      let value = payload["value"] as? String, value.count < 150000 else { return }
                UserDefaults.standard.set(value, forKey: "radio.saved." + key)
            case "lookup": lookupEncyclopedia(payload)
            case "schedule": scheduleAlarm(payload)
            case "cancelAlarm":
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationID])
            default: break
            }
        }

        // Free encyclopedia lookup; no AI key or per-request AI charges.
        // The retrieved content is attributed to Japanese Wikipedia in the UI.
        private func lookupEncyclopedia(_ payload: [String: Any]) {
            guard let id = payload["id"] as? Int,
                  let raw = payload["query"] as? String else { return }
            let query = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
            guard !query.isEmpty else { return }

            var components = URLComponents(string: "https://ja.wikipedia.org/w/api.php")!
            components.queryItems = [
                URLQueryItem(name: "action", value: "query"),
                URLQueryItem(name: "generator", value: "search"),
                URLQueryItem(name: "gsrsearch", value: query),
                URLQueryItem(name: "gsrlimit", value: "1"),
                URLQueryItem(name: "gsrnamespace", value: "0"),
                URLQueryItem(name: "prop", value: "extracts"),
                URLQueryItem(name: "exsectionformat", value: "plain"),
                URLQueryItem(name: "explaintext", value: "1"),
                URLQueryItem(name: "exchars", value: "2600"),
                URLQueryItem(name: "redirects", value: "1"),
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "formatversion", value: "2")
            ]
            guard let url = components.url else { lookupResponse(id: id, title: "", text: "", url: ""); return }
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue("MY-RADIO-IOS/0.4.2 (https://github.com/shu39a-lang/MY-RADIO-IOS)", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }
                guard error == nil,
                      let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode),
                      let data = data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let result = obj["query"] as? [String: Any],
                      let pages = result["pages"] as? [[String: Any]],
                      let page = pages.first,
                      let title = page["title"] as? String,
                      let extract = page["extract"] as? String else {
                    self.lookupResponse(id: id, title: "", text: "", url: "")
                    return
                }
                let description = String(extract.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2600))
                guard !description.isEmpty else {
                    self.lookupResponse(id: id, title: "", text: "", url: "")
                    return
                }
                let wikiURL = "https://ja.wikipedia.org/wiki/" + (title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")
                self.lookupResponse(id: id, title: title, text: description, url: wikiURL)
            }.resume()
        }

        private func lookupResponse(id: Int, title: String, text: String, url: String) {
            let data: [String: Any] = ["id": id, "title": title, "text": text, "url": url]
            guard let bytes = try? JSONSerialization.data(withJSONObject: data),
                  let json = String(data: bytes, encoding: .utf8) else { return }
            DispatchQueue.main.async { [weak self] in
                self?.web?.evaluateJavaScript("window.radioLookupDidFinish(" + json + ")", completionHandler: nil)
            }
        }

        private func speak(_ text: String, id: Int, payload: [String: Any]) {
            currentID = nil
            speech.stopSpeaking(at: .immediate)
            let line = AVSpeechUtterance(string: text)
            let japanese = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("ja") }
            let gender: AVSpeechSynthesisVoiceGender = (payload["gender"] as? String) == "m" ? .male : .female
            let matching = japanese.filter { $0.gender == gender }
            if let requestedID = payload["voiceID"] as? String,
               let selected = AVSpeechSynthesisVoice(identifier: requestedID), selected.language.hasPrefix("ja") {
                line.voice = selected
            } else {
                line.voice = matching.first ?? japanese.first ?? AVSpeechSynthesisVoice(language: "ja-JP")
            }
            let pitch = (payload["pitch"] as? Double) ?? 1
            let speed = (payload["rate"] as? Double) ?? 1
            line.pitchMultiplier = Float(min(2, max(0.5, pitch)))
            line.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, Float(0.5 * speed)))
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch { /* Keep speaking if session initialization is unavailable. */ }
            currentID = id
            speech.speak(line)
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            guard let id = currentID else { return }
            currentID = nil
            DispatchQueue.main.async { [weak self] in
                self?.web?.evaluateJavaScript("window.radioSpeechDidFinish(" + String(id) + ")", completionHandler: nil)
            }
        }
        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {}

        private func scheduleAlarm(_ payload: [String: Any]) {
            let time = payload["time"] as? String ?? "07:00"
            let daily = payload["daily"] as? Bool ?? false
            let seconds = max(1, (payload["delaySeconds"] as? Double) ?? 10)
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
                guard granted, let self = self else { return }
                center.removePendingNotificationRequests(withIdentifiers: [self.notificationID])
                let trigger: UNNotificationTrigger
                if daily {
                    let parts = time.split(separator: ":")
                    guard parts.count == 2, let hh = Int(parts[0]), let mm = Int(parts[1]),
                          (0...23).contains(hh), (0...59).contains(mm) else { return }
                    var date = DateComponents(); date.hour = hh; date.minute = mm
                    trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
                } else {
                    trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
                }
                let content = UNMutableNotificationContent()
                content.title = "MY RADIO"
                content.body = "世界に1つ、あなただけの放送局。ラジオを始めましょう。"
                content.sound = .default
                center.add(UNNotificationRequest(identifier: self.notificationID, content: content, trigger: trigger))
            }
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            // Foreground playback is controlled by the HTML timer.
            completionHandler([])
        }
        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                    withCompletionHandler completionHandler: @escaping () -> Void) {
            if response.notification.request.identifier == notificationID {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if self.web?.isLoading == true || self.web == nil {
                        self.pendingLaunchFromNotification = true
                    } else {
                        self.web?.evaluateJavaScript("startRadio()", completionHandler: nil)
                    }
                }
            }
            completionHandler()
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            showLoadError(in: webView)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            showLoadError(in: webView)
        }
        private func showLoadError(in webView: WKWebView) {
            webView.loadHTMLString(EmbeddedRadioPage.html, baseURL: nil)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let voices = AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.language.hasPrefix("ja") }
                .map { ["name": $0.name, "voiceURI": $0.identifier, "gender": $0.gender.rawValue == 1 ? "male" : "other"] }
            if let bytes = try? JSONSerialization.data(withJSONObject: voices),
               let literal = String(data: bytes, encoding: .utf8) {
                webView.evaluateJavaScript("window.radioNativeVoices(" + literal + ")", completionHandler: nil)
            }
            if pendingLaunchFromNotification {
                pendingLaunchFromNotification = false
                webView.evaluateJavaScript("startRadio()", completionHandler: nil)
            }
        }
    }
}

private enum EmbeddedRadioPage {
    static let html = ##"""
<!doctype html>
<html lang="ja" data-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>MY RADIO</title>
<style>
:root{--bg:#fff7ee;--card:#ffffff;--ink:#2b2118;--mute:#7a6a5a;--acc:#e8590c;--onacc:#ffffff;--soft:#fff0e0;--line:#eadbc8;box-sizing:border-box;padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#1b1511;--card:#271e18;--ink:#f6ebdd;--mute:#b8a692;--acc:#ff8a3d;--onacc:#1b1511;--soft:#3a2a1d;--line:#40322a}}
:root[data-theme="dark"]{--bg:#1b1511;--card:#271e18;--ink:#f6ebdd;--mute:#b8a692;--acc:#ff8a3d;--onacc:#1b1511;--soft:#3a2a1d;--line:#40322a}
html{scroll-padding-top:env(safe-area-inset-top,0px)}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font-family:-apple-system,"Hiragino Sans","Noto Sans JP",sans-serif;line-height:1.6}
main{max-width:480px;margin:0 auto;padding:16px 16px 40px}
h1{font-size:24px;margin:8px 0 2px}
.sub{color:var(--mute);font-size:13px;margin:0 0 16px}
.card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:14px;margin-bottom:14px}
h2{font-size:14px;margin:0 0 10px;color:var(--mute);font-weight:600}
.chips{display:flex;flex-wrap:wrap;gap:8px}
button{font:inherit;color:inherit;cursor:pointer}
.chip{border:1px solid var(--line);background:var(--card);border-radius:999px;padding:8px 14px;font-size:15px}
.chip.on{background:var(--acc);color:var(--onacc);border-color:var(--acc)}
.voices{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.voices .chip{border-radius:12px;text-align:center}
.row{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
input[type=time]{font:inherit;padding:8px 10px;border-radius:10px;border:1px solid var(--line);background:var(--card);color:var(--ink)}
.btn{border:0;border-radius:12px;padding:10px 14px;background:var(--soft);font-size:15px}
.btn.pri{background:var(--acc);color:var(--onacc);font-weight:700}
.big{width:100%;padding:18px;font-size:19px;border-radius:16px;border:0;background:var(--acc);color:var(--onacc);font-weight:700}
.status{font-size:13px;color:var(--mute);margin-top:8px}
#log{max-height:240px;overflow-y:auto;font-size:15px}
#log p{margin:0 0 8px}
#log p.now{color:var(--acc);font-weight:600}
.note{font-size:12px;color:var(--mute)}
.ch{display:block;width:100%;text-align:left;border:1px solid var(--line);background:var(--card);border-radius:12px;padding:10px 12px;margin-bottom:6px;font-size:15px}
.ch.cur{border-color:var(--acc);color:var(--acc);font-weight:600}
.ptitle{font-size:18px;font-weight:700;margin:0 0 4px}
.chk{display:flex;gap:8px;align-items:center;font-size:14px;margin-top:10px}

/* レトロ4番：元の機能・番組データを変更しない表示レイヤー */
/* 4つの見本で共通。元の番組・話題選択・音声・アラームは維持。 */
:root { font-synthesis: none; }
html { scroll-behavior: smooth; }
body { min-height: 100svh; }
main { max-width: 480px; padding: 18px 17px 56px; }
.hero { display: flex; align-items: center; gap: 16px; margin: 2px 0 19px; position: relative; overflow: hidden; }
.hero > * { position:relative; z-index:1; }
.brand-mark {flex: 0 0 auto; width: 66px; height: 66px; display: flex; align-items: center; justify-content: center;}
.hero h1 { margin: 0; line-height: 1.1; font-size: 33px; font-weight: 830; letter-spacing: .06em; white-space: nowrap; }
.hero .sub { line-height: 1.4; font-size: 13.3px; font-weight: 620; margin: 10px 0 0; letter-spacing: .008em; }
.card { border-radius:20px; padding:18px; margin-bottom:14px; }
h2 { letter-spacing:.02em; font-size: 14px; margin-bottom: 13px; }
.chip { transition: background-color .15s,transform .15s; padding: 9px 13px; font-size: 14px; }
.chip:active, .btn:active,.big:active{ transform:scale(.985); }
input, select, button { -webkit-tap-highlight-color: transparent; }
.btn,.big { transition: filter .15s ease,transform .15s ease; }
.big {box-shadow:0 6px 18px rgba(0,0,0,.09);}
button:focus-visible,input:focus-visible,select:focus-visible{outline:3px solid var(--acc);outline-offset:2px;}
@media(max-width:380px){.hero h1{font-size:29px}.hero .sub{font-size:12px}.hero{gap:12px}.brand-mark{width:56px;height:56px}.card{padding:15px}}

 :root[data-theme="dark"]{--bg:#211c1b;--card:#302723;--ink:#f7eddc;--mute:#c1aa93;--acc:#e0aa6b;--onacc:#251b17;--soft:#49392f;--line:#55453c;}
 body{background:linear-gradient(135deg,#241e1b,#211c1b 65%,#2b201d)}
 .hero{padding:30px 19px;border-radius:15px;background:repeating-linear-gradient(0deg,transparent,transparent 6px,#ffffff07 7px),linear-gradient(135deg,#5d3c2c,#352823);border:3px double #b98d5f;box-shadow:0 12px 32px #00000055;}
 .hero::before{content:"";position:absolute;top:13px;bottom:13px;left:12px;right:12px;border:1px solid #d8ac6e5e;border-radius:7px;pointer-events:none;}
 .brand-mark{background:linear-gradient(145deg,#d8b187,#8e6947);color:#38271e;border-radius:50%;border:3px double #f0d1a0;box-shadow:0 0 0 6px #e0ba8c25;}
 .hero h1{font-family:Georgia,"Times New Roman",serif;letter-spacing:.07em;color:#ffe0aa;font-weight:700;font-size:31px;}
 .hero .sub{color:#f0cba3;font-size:12px;}
 h2{color:#e0b994}.card{border-radius:12px;box-shadow:0 6px 22px #00000025;}
 .chip{border-radius:7px}.voices .chip{border-radius:7px}.big{border-radius:10px}.btn{border-radius:8px}
 

</style>
</head>
<body>
<main>
<header class="hero" aria-label="MY RADIO">
      <div class="brand-mark"><svg width="34" height="34" viewBox="0 0 48 48" role="img" aria-label="ラジオ" fill="none" xmlns="http://www.w3.org/2000/svg"><rect x="9" y="18" width="30" height="22" rx="6" stroke="currentColor" stroke-width="2.8"/><circle cx="19" cy="29" r="5" stroke="currentColor" stroke-width="2.5"/><path d="M29 26h4M29 32h4M12 18l21-8" stroke="currentColor" stroke-width="2.8" stroke-linecap="round"/><path d="M35 5c3 1.5 5 3.5 6 6" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></div>
      <div class="brand-copy"><h1>MY RADIO</h1><p class="sub">世界に1つ、あなただけの放送局</p></div>
    </header>

  <div class="card">
    <h2>聴きたい話題</h2>
    <p class="note" style="margin:-5px 0 10px">選んだ話題を1項目ずつ、約2分以上かけて詳しくお届けします。</p>
    <div class="chips" id="topics"></div>
  </div>

<div class="card">
    <h2>🎤 聴きたいことをリクエスト</h2>
    <div class="row"><input type="text" id="req" enterkeyhint="go" placeholder="例:猫の歴史、投資信託の選び方" style="flex:1;min-width:0;font:inherit;padding:10px;border-radius:10px;border:1px solid var(--line);background:var(--card);color:var(--ink)"><button class="btn pri" id="reqgo" type="button">お話しして</button></div>
    <div class="status" id="reqstatus" role="status" aria-live="polite">聞きたいことを入力して「お話しして」を押してください。</div>
    <p class="note" style="margin:5px 0 0">入力した話題を日本語版Wikipediaで検索し、できるだけ詳しく読み上げます。ネットに接続できない場合は収録済みの記事を使います。AI生成の追加料金はありません。</p>
    <div id="reqsource" class="note" style="margin-top:6px"></div>
    <div class="chips" id="reqhist" style="margin-top:10px"></div>
  </div>

  <div class="card">
    <h2>声を選ぶ</h2>
    <div class="voices" id="voices"></div>
    <div class="row" style="margin-top:10px"><button class="btn" id="sample">この声で試し聴き</button></div>
  </div>

  <div class="card">
    <h2>モーニングコール</h2>
    <div class="row">
      <input type="time" id="time" value="07:00">
      <button class="btn pri" id="arm">セットする</button>
      <button class="btn" id="test">10秒後にテスト</button>
      <button class="btn" id="disarm">解除</button>
    </div>
    <div class="status" id="astatus">未設定</div>
    <p class="note">時刻になるとチャイムが鳴り、ラジオが始まります。ブラウザ版のため、このページを開いたまま画面を点けておいてください。</p>
  </div>

  <div class="card">
    <h2>特集番組</h2>
    <p class="ptitle">🎙 やさしい経済と株の10分</p>
    <p class="note" style="margin:0 0 10px">経済の流れ、株価が動く理由、伸びる会社の見方を、章ごとにじっくりお話しします。章をタップすると、そこから始まります。</p>
    <div id="chs"></div>
    <button class="big" id="pplay" style="margin-top:6px">▶ 経済の10分番組を聴く</button>
    <label class="chk"><input type="checkbox" id="progAlarm"> モーニングコールの後にこの番組を流す</label>
  </div>

  <button class="big" id="play">▶ ラジオを始める</button>

  <div class="card" style="margin-top:14px">
    <h2>放送中のことば</h2>
    <div id="log"><p class="note">ここに読み上げた内容が表示されます。</p></div>
  </div>
  <p class="note">同じ話題を選んでも、前に聴いたお話はできるだけ避けて、まだ聴いていないお話を選びます。聴いた記録はこの端末に保存されます。</p>
</main>

<script>
const TOPICS={
 tech:{n:"テクノロジー",e:"💡",t:["最初のウェブサイトは、1991年に一般公開されました。今のインターネットは、たった1ページから始まったのです。","QRコードは、日本の企業デンソーが1994年に発明しました。","スマートフォンの中のチップには、数十億個ものトランジスタが入っています。"]},
 game:{n:"ゲーム",e:"🎮",t:["ファミリーコンピュータの発売は、1983年7月です。","テトリスは、1984年に旧ソビエト連邦で生まれました。","マインクラフトの累計販売本数は、3億本を超えています。"]},
 music:{n:"音楽",e:"🎵",t:["ピアノの鍵盤は、全部で88鍵あります。","ドレミの音名は、中世の聖歌の歌詞の頭文字から作られたといわれています。","好きな音楽を聴くと、気分が整いやすいことが多くの研究で報告されています。"]},
 movie:{n:"映画",e:"🎬",t:["お金を払って観る映画の上映は、1895年にフランスのリュミエール兄弟が行いました。","映画は、1秒間に24コマで撮影や上映をするのが標準です。"]},
 travel:{n:"旅行",e:"🧳",t:["国宝に指定されているお城は、姫路城、松本城、犬山城、彦根城、松江城の5つです。","新幹線が開業したのは1964年。東京オリンピックの直前でした。"]},
 food:{n:"グルメ",e:"🍛",t:["うま味は、1908年に日本の池田菊苗博士が発見しました。","カレーライスは、明治時代にイギリスを経由して日本に広まりました。"]},
 science:{n:"科学",e:"🔭",t:["光は、1秒間に地球を約7周半します。","月は、毎年およそ3.8センチずつ地球から遠ざかっています。"]},
 anime:{n:"アニメ",e:"✨",t:["日本初の連続テレビアニメシリーズは、1963年の鉄腕アトムです。","多くのアニメは、1秒間に8枚から12枚ほどの絵で動きを作っています。"]},
 sports:{n:"スポーツ",e:"🏅",t:["近代オリンピックの第1回大会は、1896年にアテネで開かれました。","マラソンの42.195キロは、1908年のロンドン大会の距離がもとになっています。"]},
 econ:{n:"経済",e:"📈",t:["日本の株式取引所の歴史は古く、東京株式取引所は1878年に設立されました。","日経平均株価は、1949年から算出されています。"]}
};
const STYLES=[
 {id:"f1",n:"👩 女性・標準",g:"f",pitch:1.0,rate:1.0},
 {id:"f2",n:"👩 女性・明るい",g:"f",pitch:1.35,rate:1.1},
 {id:"m1",n:"👨 男性・標準",g:"m",pitch:1.0,rate:1.0},
 {id:"m2",n:"👨 男性・落ち着き",g:"m",pitch:0.75,rate:0.9}
];
const FEM=/kyoko|haruka|ayumi|sayaka|nanami|mizuki|female|o-ren|google 日本語/i;
const MAL=/otoya|ichiro|keita|hattori|takumi|male/i;
let sel=new Set(["tech","game","travel"]),styleId="f1",playing=false,alarmAt=null,alarmDaily=false,ctx=null,wake=null;
try{const s=JSON.parse((window.__myradioSaved?.myradio ?? localStorage.getItem("myradio"))||"{}");if(s.sel)sel=new Set(s.sel);if(s.styleId)styleId=s.styleId;if(s.time)document.getElementById("time").value=s.time}catch(e){}
function save(){const v=JSON.stringify({sel:[...sel],styleId,time:document.getElementById("time").value});try{localStorage.setItem("myradio",v)}catch(e){}persistNative("myradio",v)}
const $=id=>document.getElementById(id);
const hasNative=()=>!!window.webkit?.messageHandlers?.radio;
function sendNative(msg){if(hasNative())window.webkit.messageHandlers.radio.postMessage(msg)}
function persistNative(key,value){sendNative({type:"persist",key,value})}
let nativeID=0;
const nativeDone=new Map();
window.radioSpeechDidFinish=function(id){const done=nativeDone.get(id);nativeDone.delete(id);if(done)done()};
function cancelSpeech(){
  nativeDone.clear();
  if(hasNative())sendNative({type:"cancel"});
  else speechSynthesis.cancel();
}
window.radioNativeVoices=function(list){window.nativeRadioVoiceList=list; if(typeof fillDev==="function")fillDev()};
function renderTopics(){$("topics").innerHTML="";for(const k in TOPICS){const b=document.createElement("button");b.className="chip"+(sel.has(k)?" on":"");b.textContent=TOPICS[k].e+" "+TOPICS[k].n;b.onclick=()=>{sel.has(k)?sel.delete(k):sel.add(k);save();renderTopics()};$("topics").appendChild(b)}}
function renderVoices(){$("voices").innerHTML="";STYLES.forEach(s=>{const b=document.createElement("button");b.className="chip"+(s.id===styleId?" on":"");b.textContent=s.n;b.onclick=()=>{styleId=s.id;save();renderVoices();speakOne("こんにちは。この声でお届けします。")};$("voices").appendChild(b)})}
function style(){return STYLES.find(s=>s.id===styleId)}
function pickVoice(){const vs=(speechSynthesis.getVoices()||[]).filter(v=>/^ja/i.test(v.lang));const g=style().g;return vs.find(v=>(g==="f"?FEM:MAL).test(v.name))||vs.find(v=>!(g==="f"?MAL:FEM).test(v.name))||vs[0]||null}
function utter(text,done){
 if(hasNative()){
  const s=style();const id=++nativeID;
  nativeDone.set(id,done);
  sendNative({type:"speak",id,text,gender:s.g,pitch:s.pitch,rate:Math.min(s.rate,1.0),voiceID:devVoice||""});
  return;
 }
 const u=new SpeechSynthesisUtterance(text);u.lang="ja-JP";const v=pickVoice();if(v)u.voice=v;const s=style();u.pitch=s.pitch;u.rate=Math.min(s.rate,1.0);u.onend=done;u.onerror=done;speechSynthesis.speak(u)
}
function speakOne(t){cancelSpeech();utter(t,()=>{})}
function greeting(){const d=new Date(),h=d.getHours(),m=d.getMinutes();const w="日月火水木金土"[d.getDay()];const hi=h<11?"おはようございます。":h<18?"こんにちは。":"こんばんは。";return hi+"マイラジオの時間です。"+(d.getMonth()+1)+"月"+d.getDate()+"日、"+w+"曜日、"+h+"時"+m+"分をお知らせします。"}
function buildLines(){const L=[{t:greeting()}];[...sel].forEach(k=>{const T=TOPICS[k];L.push({t:"続いて、"+T.n+"の話題です。"});pickEps(k).forEach(x=>L.push({t:x}))});L.push({t:"以上、マイラジオでした。今日も良い一日を。"});return L}
function startRadio(){stopRadio();if(!sel.size){alert("話題を1つ以上選んでください");return}playing=true;$("play").textContent="■ 停止";$("log").innerHTML="";const lines=buildLines();let i=0;lockScreen();const next=()=>{if(!playing)return;if(i>=lines.length){stopRadio();return}const l=lines[i++];document.querySelectorAll("#log p.now").forEach(p=>p.classList.remove("now"));const p=document.createElement("p");p.className="now";p.textContent=l.t;$("log").appendChild(p);$("log").scrollTop=1e6;utter(l.t,next)};next()}
function stopRadio(){playing=false;cancelSpeech();$("play").textContent="▶ ラジオを始める"}
async function lockScreen(){try{if(navigator.wakeLock&&!wake){wake=await navigator.wakeLock.request("screen");wake.addEventListener("release",()=>wake=null)}}catch(e){}}
function ensureAudio(){try{ctx=ctx||new (window.AudioContext||window.webkitAudioContext)();ctx.resume()}catch(e){}}
function chime(){if(!ctx)return 0;let t=ctx.currentTime;for(let i=0;i<6;i++){const o=ctx.createOscillator(),g=ctx.createGain();o.frequency.value=i%2?880:660;g.gain.setValueAtTime(.25,t+i*.4);g.gain.exponentialRampToValueAtTime(.001,t+i*.4+.35);o.connect(g);g.connect(ctx.destination);o.start(t+i*.4);o.stop(t+i*.4+.4)}return 2600}
function arm(ms,daily){
 ensureAudio();
 if(!hasNative()){const u=new SpeechSynthesisUtterance(" ");u.volume=0;speechSynthesis.speak(u)}
 alarmAt=Date.now()+ms;alarmDaily=daily;lockScreen();save();status();
 sendNative({type:"schedule",time:$("time").value,daily,delaySeconds:ms/1000});
}
function nextOccurrence(){const [h,m]=$("time").value.split(":").map(Number);const d=new Date();d.setHours(h,m,0,0);if(d<=new Date())d.setDate(d.getDate()+1);return d-Date.now()}
function status(){if(!alarmAt){$("astatus").textContent="未設定";return}const r=Math.max(0,alarmAt-Date.now());const h=Math.floor(r/36e5),m=Math.floor(r%36e5/6e4),s=Math.floor(r%6e4/1e3);$("astatus").textContent="セット中:あと"+(h?h+"時間":"")+(m||h?m+"分":"")+s+"秒"+(alarmDaily?"(毎日くり返し)":"")}
setInterval(()=>{if(alarmAt&&Date.now()>=alarmAt){const wait=chime();if(alarmDaily)alarmAt=Date.now()+nextOccurrence();else alarmAt=null;setTimeout(()=>$("progAlarm").checked?startProgram(0):startRadio(),wait)}status()},1000);
$("arm").onclick=()=>arm(nextOccurrence(),true);
$("test").onclick=()=>arm(10000,false);
$("disarm").onclick=()=>{alarmAt=null;sendNative({type:"cancelAlarm"});status()};
$("time").onchange=save;
$("play").onclick=()=>{playing?stopRadio():(ensureAudio(),startRadio())};
$("sample").onclick=()=>speakOne("おはようございます。マイラジオです。今日も一緒に楽しみましょう。");
if(hasNative() || "speechSynthesis" in window){if("speechSynthesis" in window)speechSynthesis.onvoiceschanged=()=>{}}else{$("play").disabled=true;$("play").textContent="このブラウザは音声読み上げに未対応です"}
const PROG={ch:[
{h:"第1章、経済の大きな流れを見る目",x:"ここからは、経済と株の特集をお届けします。まずは、経済の大きな流れを見るための、基本の考え方からお話しします。経済は、とても大きな生き物のようなものです。景気が良くなると、会社の売り上げが増え、働く人のお給料が上がり、人々がたくさんお金を使うようになります。お金が使われると、また会社の売り上げが増えます。この良い循環が続く時期を、好景気といいます。反対に、物が売れなくなると、会社は仕事を減らし、お給料も伸びにくくなり、さらに物が売れなくなります。これが不景気です。景気は、このように良い時期と悪い時期をくり返しながら、長い目で見ると少しずつ成長していきます。この景気の流れを読むときに、特に大切なものが三つあります。一つ目は、金利です。金利とは、お金を借りるときの値段のことです。金利が低いと、会社も個人もお金を借りやすくなり、投資や買い物が増えて、景気を後押しします。金利が上がると、借りるお金の負担が重くなるので、景気の熱を冷ます働きをします。二つ目は、物価です。物の値段が全体として上がっていく状態を、インフレといいます。ほどよいインフレは、経済が元気な証拠ですが、給料の伸びを超えて物価が上がると、暮らしは苦しくなります。三つ目は、為替です。円とドルなど、お金同士の交換比率のことです。円安になると、海外で稼ぐ輸出企業の利益が増えやすい一方で、輸入する原材料や燃料の値段が上がります。円高になると、その反対のことが起こります。この、金利、物価、為替の三つが、今どちらに向かっているのかを見るだけでも、ニュースで流れる経済の話が、ぐっと分かりやすくなります。経済の話が難しく感じるときは、まずこの三つに立ち返ってみてください。"},
{h:"第2章、株価はなぜ動くのか",x:"続いて、株価の話をしましょう。株とは、会社の持ち主の一人になれる権利のことです。会社が事業で利益を出せば、その一部が配当として株主に支払われますし、会社の価値が高まれば、株の値段も上がっていきます。株価は、その株を買いたい人と売りたい人の、折り合いで決まります。買いたい人が多ければ値段は上がり、売りたい人が多ければ下がります。では、人はどんなときに買いたくなり、どんなときに売りたくなるのでしょうか。一番の土台は、会社の利益です。長い目で見ると、株価は、その会社がどれだけ利益を稼ぐ力があるかに近づいていきます。ですから、利益が伸びている会社の株は、長期的には評価されやすくなります。ただし、短い期間では、利益そのものよりも、これからどうなりそうかという期待や不安で、株価は大きく動きます。良いニュースが出れば期待で買われ、悪いニュースが出れば不安で売られます。金利との関係も大切です。金利が上がると、安全な預金や債券の魅力が増すので、株から資金が移りやすくなります。さらに、将来の利益の価値が小さく見積もられるため、特に成長を期待されている会社の株は、下がりやすくなると言われています。為替も影響します。円安は輸出企業にとって追い風になりやすく、円高は向かい風になりやすい、というのが基本的な見方です。ニュースでよく聞く、日経平均株価は、日本を代表する二百二十五社の株価をもとにした指数で、日本の株式市場全体の温度計のような存在です。また、株価が割安か割高かを見る目安として、株価収益率、通称ピーイーアールがあります。株価が、一株あたりの利益の何倍になっているかを示す数字で、同じ業種の会社どうしで比べると、市場の期待の大きさが見えてきます。"},
{h:"第3章、業績を伸ばす会社の共通点",x:"第3章では、業績を伸ばしている会社には、どんな共通点があるのかを見ていきましょう。一つ目は、需要が増えている市場で戦っていることです。波に乗っている会社は、同じ努力でも成果が出やすくなります。二つ目は、他の会社にまねされにくい強みを持っていることです。独自の技術、強いブランド、たくさんの人が使うからこそ便利になるサービスなどがその例です。三つ目は、値上げができる力です。コストが上がったときに、お客さまに納得して価格を受け入れてもらえる会社は、利益を守ることができます。四つ目は、稼いだお金を、次の成長のために上手に使っていることです。新しい設備や研究、人材に投資して、次の利益の種をまいています。そして五つ目は、財務が健全であることです。借金に頼りすぎず、不況のときにも持ちこたえられる会社は、長く生き残ります。では、近年よく話題になる成長のテーマには、どんなものがあるでしょうか。人工知能の広がりに伴う、半導体やデータセンター、クラウドサービス。高齢化に伴う、医療や介護、健康関連。環境への意識の高まりによる、省エネや再生可能エネルギー。そして、海外からの旅行者の増加に支えられる、観光や宿泊、小売などです。ただし、ここで一つ注意があります。話題のテーマに乗った会社の株は、人気が集まりすぎて、すでに株価が高くなっていることがあります。良い会社であることと、今の株価が割安であることは、別の話です。人気に流されず、その会社が本当に利益を伸ばしているのか、数字で確かめる姿勢が大切です。"},
{h:"第4章、決算の読み方と、長く付き合うコツ",x:"最後の章では、会社の成績表である、決算の読み方と、投資との長い付き合い方をお話しします。上場している会社は、三か月ごとに決算を発表します。まず見るのは、三つの数字です。売上高は、会社がどれだけ商品やサービスを売ったか。営業利益は、本業でどれだけ稼いだか。純利益は、すべての費用や税金を引いた後に残った最終的な利益です。売上高も利益も前の年より増えていることを、増収増益といいます。ここで面白いのは、決算の数字が良くても、株価が下がることがあるという点です。株価は、市場の事前の予想と比べて、良かったか悪かったかで動くことが多いからです。予想より少しでも悪ければ、数字そのものが好調でも売られることがあります。ですから、決算の数字だけで、すぐに売り買いを決める必要はありません。投資との付き合い方で、よく言われる基本は三つです。一つ目は、分散です。一つの会社や一つの国にまとめて投資せず、いくつかに分けておくと、ひとつが悪くなっても、全体への影響をやわらげられます。二つ目は、続けることです。少額でも定期的に積み立てると、高いときには少なく、安いときには多く買えるので、価格の波をならす効果が期待できます。国の制度として、二千二十四年から新しいNISAが始まり、一定の範囲で、運用で得た利益に税金がかからない仕組みが広がっています。三つ目は、余裕のあるお金で行うことです。生活に必要なお金や、近いうちに使う予定のお金は、値下がりのリスクのある投資に回さないのが原則です。株価は、ときに大きく下がります。それも含めて、投資だと考えておくことが、気持ちの余裕につながります。以上、経済と株の特集でした。この番組は、一般的な情報の提供を目的としており、特定の銘柄の売買をおすすめするものではありません。投資の最終的な判断は、ご自身の責任でお願いします。"}
]};
let progOn=false;
function setProgUI(on){progOn=on;$("pplay").textContent=on?"■ 停止":"▶ 経済の10分番組を聴く";if(!on)document.querySelectorAll(".ch.cur").forEach(b=>b.classList.remove("cur"))}
function markCh(ci){document.querySelectorAll(".ch").forEach((b,i)=>b.classList.toggle("cur",i===ci))}
function renderChs(){const box=$("chs");box.innerHTML="";PROG.ch.forEach((c,i)=>{const b=document.createElement("button");b.className="ch";b.textContent=c.h+"(約"+Math.max(1,Math.round(c.x.length/350))+"分)";b.onclick=()=>{ensureAudio();startProgram(i)};box.appendChild(b)})}
function startProgram(from){stopRadio();playing=true;setProgUI(true);const L=[];PROG.ch.forEach((c,ci)=>{if(ci<from)return;L.push({t:c.h+"。",ci});c.x.split("。").filter(s=>s.trim()).forEach(s=>L.push({t:s+"。",ci}))});let i=0;lockScreen();const next=()=>{if(!playing)return;if(i>=L.length){stopRadio();return}const l=L[i++];markCh(l.ci);$("log").innerHTML="";const p=document.createElement("p");p.className="now";p.textContent=l.t;$("log").appendChild(p);utter(l.t,next)};next()}
const _sr=stopRadio;stopRadio=function(){_sr();setProgUI(false)};
$("pplay").onclick=()=>{progOn?stopRadio():(ensureAudio(),startProgram(0))};
const LONG={
tech:[
"今日の話題は、QRコードです。QRコードは、1994年に日本の企業デンソーの開発者、原昌宏さんたちが生み出しました。きっかけは、自動車の部品工場でした。当時使われていたバーコードは、入れられる情報が少なく、部品ごとに何枚も読み取る必要がありました。そこで、縦と横の両方向に情報を持たせる、碁盤の目のようなコードが考えられたのです。三つの隅にある大きな四角のマークにも工夫があります。あの形は、どの角度から読み取っても、すぐにコードの向きが分かるように選ばれました。さらに、一部が汚れたり欠けたりしても、残りの部分から元の情報を復元できる、誤り訂正という仕組みも入っています。そして、規格に沿った利用については特許の権利を行使しないと表明したため、世界中で自由に使われるようになりました。今では、支払いや切符、お店のメニューまで、暮らしのあちこちで使われています。",
"今日の話題は、スマートフォンの地図を支えるGPSです。GPSは、地球の上空を回る人工衛星の信号を使って、今いる場所を割り出します。仕組みの核心は、時間です。各衛星は、とても正確な原子時計を積んでいて、今の時刻を電波にのせて送り続けています。スマートフォンは、その電波が届くまでのほんのわずかな時間の差から、衛星までの距離を計算します。距離が一つ分かると、その衛星を中心にした球面のどこかにいることが分かり、衛星の数を増やすほど、位置が一点に絞られます。実際には、スマートフォン自身の時計のずれを直すために、四つ以上の衛星を使います。面白いのは、相対性理論による補正です。衛星は高速で動き、地上より弱い重力の中にいるため、時計の進み方が少しずれます。この補正をしないと、地図上の位置が一日で何キロもずれてしまうといわれています。",
"今日の話題は、インターネットを支える海底ケーブルです。私たちが海外のサイトを見たり、動画を送ったりするとき、データの多くは、衛星ではなく、海の底を通っています。国をまたぐ通信の大部分は、海底ケーブルが運んでいるといわれています。ケーブルの太さは、太いところでも、おおよそ庭のホースくらいです。中には、髪の毛ほどの細い光ファイバーが入っていて、光の点滅でデータを送ります。深い海の底に敷くため、船でゆっくりと繰り出しながら、何千キロも沈めていきます。浅い海では、漁の網や船のいかりで傷つかないよう、より頑丈に守られます。ときどき、地震や海底の地すべりで切れてしまうことがありますが、通信は別のルートに切り替わるよう、複数の経路が用意されています。普段は見えない、この海の底の道が、世界をつないでいるのです。"
],
game:[
"今日の話題は、テトリスの物語です。テトリスは、1984年、当時のソビエト連邦で、アレクセイ・パジトノフさんが作りました。パジトノフさんは、コンピューターの研究者で、新しい機械の性能を試すためのプログラムとして作り始めたといわれています。アイデアのもとは、五つの正方形をつなげたパズルのおもちゃでした。そのままでは複雑なので、四つの正方形に減らしたところ、ちょうどよい難しさになりました。落ちてくる形がテトロミノと呼ばれるのは、そのためです。ゲームは、まず研究者たちの間で広まり、やがて西側の国にも伝わりました。そして、1989年に、任天堂のゲームボーイと一緒に遊べるようになったことで、世界中の人が知るゲームになりました。ルールはとてもシンプルなのに、何十年たっても遊ばれ続けているのは、考え方がよくできているからです。",
"今日の話題は、ファミリーコンピュータです。通称ファミコンは、1983年7月15日に、任天堂から発売されました。価格は、14800円でした。当時、ゲームを遊べる場所といえば、ゲームセンターや喫茶店でした。それを、家のテレビにつないで、家族みんなで遊べるようにしたのが、この機械の大きな意味でした。発売と同時に遊べたソフトは、ドンキーコング、ドンキーコングジュニア、ポパイの三本です。ゲームセンターで人気だったゲームを、家で遊べるようにしたことが、人気につながりました。発売後まもなく、一部の本体に不具合が見つかり、回収と交換が行われたことも知られています。それでも、その後に出たソフトの魅力で人気は伸び続け、日本中の家庭にゲームが広がっていきました。",
"今日の話題は、スーパーマリオブラザーズです。1985年9月13日に発売されたこのゲームは、宮本茂さんたちが作りました。最大の特徴は、説明書を読まなくても、遊び方が自然に分かるように作られていることです。一番最初の場面を思い出してください。マリオの前に、ゆっくり歩いてくる敵がいます。避けにくいので、多くの人はジャンプしてしまい、踏めば倒せることを自然に覚えます。続いて、頭の上のブロックを叩くと、きのこが出てきて、体が大きくなります。やり方を言葉で教えるのではなく、遊びの中で体験させる。この考え方は、のちの多くのゲームの手本になりました。画面が横に動いていく仕組みも、先へ進みたいという気持ちを自然に引き出します。このゲームは、世界で4000万本を超える売り上げを記録しました。"
]};
for(const k in LONG)TOPICS[k].t=LONG[k].concat(TOPICS[k].t);

// Extended, original explanatory stories: one complete narrated section per selected topic.
const TOPIC_DEEP_DIVE = {
 "tech": "スマートフォンを例に、技術がどう生活を変えたのかを考えてみましょう。昔は、地図、カメラ、音楽プレーヤー、辞書は別々の道具でした。今では一つの端末で使えます。重要なのは、小型化だけでなく、通信網とソフトウェアが組み合わさったことです。情報を受け取るだけでなく、地図を共有したり、写真を編集したりできるようになりました。\n技術の面白いところは、便利さの裏側に多くの工夫が隠れていることです。例えば地図を開くとき、位置情報、道路のデータ、画面の描画、通信の処理が協力しています。どれか一つが欠けても、使い勝手は大きく変わります。私たちは目に見える画面を操作しますが、裏側では何種類もの技術が同時に働いているのです。\nそれでは、これから技術を見るときに、何を基準にすればよいでしょうか。一つは、本当に手間が減るかどうか。もう一つは、誰でも使えるかどうかです。新しい仕組みは機能が多いほど優れているとは限りません。操作の分かりやすさや、間違えたときに戻れることも、立派な技術の価値です。\n便利さと同時に、個人情報への配慮も大切です。アプリに与える権限は必要なものだけにする、知らないリンクをむやみに開かない、更新があれば内容を確認する。そんな基本を押さえるだけでも、安全性は変わります。新しい技術を遠ざけるのではなく、仕組みを少し知って、上手に付き合うことが大切なのです。\nもし身近な道具を一つ取り上げるなら、何が便利になり、どんな不便が残っているかを考えてみてください。気づいた不便こそ、次の発明の出発点かもしれません。技術は遠い研究室だけでなく、毎日の小さな困りごとからも進歩していきます。\nたとえば家族に写真を送るという一つの操作を考えても、画像の圧縮、電波を使う通信、送り先の確認といった仕組みが使われます。こうした一つ一つを意識すると、身近な技術が少し違って見えます。新しい製品が出たときも、宣伝の言葉だけでなく、手間や安全性が本当に改善されたかを見るのが大切です。便利に使うための判断力こそ、技術と付き合ううえで欠かせない力でしょう。",
 "game": "ゲームの歴史をたどると、機械の性能だけではなく、遊び方そのものの進化が見えてきます。初期のゲームは、限られた色や音、簡単な動きで楽しさを表現していました。制約が多いからこそ、ルールを分かりやすくし、少ない操作で達成感を味わえる工夫が求められたのです。\n例えば、パズルゲームは短い時間でも遊べます。決まりは単純でも、先を予想する力と、素早く判断する力が試されます。何度も挑戦したくなるのは、少しずつ上達している手応えがあるからです。最初は難しく感じたものが、練習を重ねるうちに自然にできるようになる。その感覚は、楽器やスポーツの練習にもよく似ています。\n一方、物語のあるゲームは、自分が主人公になって別の世界を歩くような楽しさがあります。映画なら場面は決められた順に進みますが、ゲームでは自分で選んだ行動が体験を変えます。同じ作品でも、人によって思い出す場面が違うのは、そのためです。\nゲームを長く楽しむコツは、勝ち負けだけにこだわりすぎないことかもしれません。好きな音楽を聴く、景色を見る、知らない遊び方を試す。そうした寄り道にも価値があります。人と一緒に遊ぶなら、上手な人だけが楽しむのではなく、初めての人にも分かる説明があると良いですね。\n遊びには、時代を越えて残る要素があります。分かりやすい目標、自分で選べる自由、少しの驚き。最新の映像表現を使ったゲームにも、昔のシンプルな作品にも、そうした楽しさは共通しています。懐かしいゲームを思い出すのも、新しい作品に触れるのも、どちらも良い体験です。\n昔の作品を今遊ぶと、画面や音は簡素に感じるかもしれません。それでも、操作を覚える楽しさや、ちょうど良い難しさには古さを感じないことがあります。なぜその作品が長く愛されてきたのか、動きや音の仕組みに注目すると分かることがあります。また、誰かとゲームの思い出を話すと、その人がどの場面を大切にしていたのかも知ることができます。ゲームは遊んでいる時間だけでなく、思い出を共有する時間にもなるのです。",
 "music": "音楽には、言葉で説明しきれない魅力があります。たった数秒の旋律を聴いただけで、昔の景色や、そのときの気持ちがよみがえることがあります。歌詞を覚えていなくても、イントロだけで分かる曲もありますね。音の高さやリズムが、私たちの記憶と深く結びついているからでしょう。\n曲を聴くときは、主役の歌声以外にも耳を向けてみてください。低い音で土台を作るベース、時間の流れを刻むドラム、伴奏を支えるギターや鍵盤。それぞれの役割に気づくと、何度も聴いた曲が違って聞こえます。一つの楽器を消してみたらどうなるだろう、と想像するだけでも面白いものです。\n楽器を弾く人なら、練習について考えてみましょう。難しい曲を最初から最後まで何度も弾くより、苦手な部分を短く区切って、ゆっくり確かめる方が良いことがあります。指の形だけでなく、音の長さや、音と音の間にある余白も大切です。急いで弾くより、気持ちよく響く速さを探すことが、演奏の楽しさにつながります。\n歌うときは、強い声を出すことだけが表現ではありません。静かな言葉ほど、聴く人の心に残ることもあります。どんな物語を伝えたいのか、どの言葉を大切にしたいのか。歌詞を一度朗読してみると、歌い方のヒントが見つかる場合があります。\n音楽の楽しみ方に正解はありません。新しい曲を探しても、好きな一曲を繰り返し聴いてもいいのです。今日は曲のどんな部分に心が動いたのか。その小さな発見を大切にすると、いつもの音楽がもっと豊かな時間になるでしょう。\n音楽を楽しむ場面も一つではありません。朝の気分を切り替える曲、仕事の後に落ち着く曲、大切な人と一緒に聴いた曲。場面によって選ぶ音楽が変わることがあります。演奏している人の呼吸や、音が消えていく余韻を聴いてみるのもおすすめです。上手さだけでなく、その人ならではの言葉の届け方や間の取り方が、音楽を特別なものにしているのかもしれません。",
 "movie": "映画を一本見ると、短い時間の中で別の人生を体験したような気持ちになることがあります。映像、俳優の表情、音楽、セリフ。その組み合わせによって、説明されなくても伝わることがあるのが映画の面白さです。たとえば、登場人物が何も言わず窓の外を見ている場面でも、光の色や音の静けさによって印象は変わります。\n映画の作り手は、見せたいものを選びながら物語を組み立てます。カメラを人物に近づければ表情が伝わり、遠くから映せば周りの景色との関係が見えてきます。場面の切り替えを速くすると緊張感が生まれ、長く映し続けるとじっくり観察する時間ができます。こうした工夫は、普段は意識しなくても私たちの感じ方を動かしています。\n同じ映画でも、見る年齢や生活経験によって受け取り方が違います。子どもの頃は冒険の場面が好きだった作品でも、大人になってから見ると、脇役の苦労や家族の気持ちに目が向くかもしれません。作品が変わったのではなく、自分の視点が変わったのです。\n映画を選ぶとき、有名な作品だけを見る必要はありません。大きな事件のない日常の物語にも、細かな発見があります。また、外国の映画を見ると、その国の町並みや食事、会話のテンポにも触れられます。知らなかった文化に興味を持つ入口にもなります。\n次に映画を観たら、好きだった場面を一つだけ思い出してみましょう。セリフが良かったのか、音楽が心に残ったのか、映像が美しかったのか。理由を考えることで、自分はどんな物語に心を動かされる人なのか、少し分かるかもしれません。\n映画を見終えたあと、感想をすぐに決めなくても構いません。翌日に思い出す場面があったり、しばらくしてから意味が分かったりすることもあります。一人で静かに味わうのもよいですし、誰かと印象の違いを話すのも楽しいものです。同じ場面を見ていても、受け取る気持ちが違うことに驚くかもしれません。映画は画面の中で終わらず、その後の会話や考えにも続いていくのです。",
 "travel": "旅行の楽しみは、遠くへ行くことだけではありません。見慣れない道を歩いたり、初めての料理を味わったりするだけでも、日常とは違う時間になります。観光名所をたくさん回る旅行もあれば、一つの町をゆっくり歩く旅行もあります。どちらが正しいということはありません。\n旅の計画を立てるときは、行きたい場所の数より、そこで何をしたいかを考えると充実しやすくなります。景色を見たいのか、歴史を知りたいのか、地元の人が食べるものを味わいたいのか。その目的が分かれば、移動を詰め込みすぎずに済みます。予定に余白があると、思いがけない店や景色に出会えるかもしれません。\n日本の町には、歩いて初めて気づく魅力がたくさんあります。古い建物と新しい建物が並ぶ通り、昔から続く市場、小さな神社、公園の季節の花。ガイドブックに大きく載らなくても、そこに住む人の日常が感じられる場所があります。\n移動の時間も旅の一部です。電車の窓から山や海を眺めたり、駅でその土地のお弁当を選んだりする時間には、目的地へ急ぐのとは別の楽しみがあります。ただし、乗り換えや歩く距離は余裕を持って計画しましょう。疲れすぎると、せっかくの景色を楽しむ余裕がなくなってしまいます。\n写真を撮ることも良い思い出になりますが、時にはカメラを置いて景色を眺めるのもおすすめです。空気の匂い、人の声、足元の感触は、写真だけでは残りません。旅から帰ってきたら、印象に残った場面を誰かに話してみる。その時間まで含めて、旅行は続いていくのだと思います。\n旅の良さは、予定どおりに進むことだけではありません。天気が変わって予定を変えた先で、思いがけない景色に出会うこともあります。ただし、危険な天候の中で無理をする必要はありません。少し予定を緩めることで、落ち着いた時間が生まれます。帰宅したら、訪れた場所の名前だけでなく、そこで何に驚き、何を感じたかをメモしてみてください。小さな記録が、次の旅を考える楽しみにもつながります。",
 "food": "食べ物の好みは人によって違いますが、おいしいと感じる理由を考えると、料理がもっと面白くなります。味には甘味、塩味、酸味、苦味、うま味といった基本的な要素があります。ところが、実際のおいしさは味だけでは決まりません。温度や食感、香り、見た目も大きく関わっています。\n例えば、焼きたてのパンの香りには、焼くことで生まれるさまざまな成分が関係しています。温かい料理と冷たい料理では、香りの立ち方も違います。食材が同じでも、焼く、蒸す、煮るといった調理法によって印象が変わるのは、そのためです。\n家庭で料理をするときは、一度にたくさんの工夫を加えなくても大丈夫です。塩を入れるタイミングを少し変える、野菜の切り方をそろえる、火を弱めてじっくり加熱する。そんな小さな違いを試して、自分の好みを見つけていくのも料理の楽しみです。\n地域の食文化に目を向けると、同じ名前の料理でも味付けや使う食材が異なることがあります。気候、保存方法、手に入る材料、昔からの暮らし方が関わっているからです。旅先で地元の料理を食べると、その土地の歴史や生活を少し味わえたような気持ちになりますね。\n食事は栄養を取るだけの行為ではありません。誰かと話しながら食べる時間や、ひとりで静かに味わう時間にも意味があります。今日は何がおいしかったのか、なぜ好きなのかを考えてみましょう。身近な一皿の中にも、たくさんの発見があります。\n料理の味を伝える言葉も豊かです。甘い、辛いだけでなく、香ばしい、さっぱりしている、ほっとする味といった表現があります。好きな料理の味を言葉にしようとすると、これまで気づかなかった特徴が見えてくるかもしれません。家族や友人と食事をするときも、「おいしい」だけでなく、どこが好きだったのかを話してみると、食卓の会話が一つ増えます。食の楽しみは料理の中だけでなく、人との時間にも広がっているのです。",
 "science": "科学の面白さは、当たり前だと思っていることに「なぜ」と問いかけるところから始まります。空が青く見えるのはなぜか。水たまりはいつの間にか消えるのか。磁石はどうして鉄を引きつけるのか。普段の暮らしの中にも、考えてみると不思議な現象がたくさんあります。\n科学では、まず観察して、考えた説明が本当に成り立つか確かめます。一度だけうまくいったからといって、すぐに正しいと決めるわけではありません。条件を変えたり、何度も試したりすることが大切です。実験で予想が外れたときも、それは失敗だけではありません。新しい疑問が見つかったということでもあります。\n私たちの体や身の回りの物は、とても小さな粒子からできています。一方、宇宙には想像するのが難しいほど大きな距離があります。小さな世界と大きな世界を、同じ自然の法則で理解しようとすることも、科学の魅力の一つです。\nニュースで科学の話題を聞くときは、発見そのものと、これから期待される応用とを分けて考えると分かりやすくなります。研究の初期段階で見つかった成果が、すぐに生活で使えるとは限りません。確かめる作業を重ねて、少しずつ信頼できる技術になっていきます。\n難しい式を知らなくても、科学を楽しむことはできます。日常で一つ疑問を見つけ、調べたり比べたりしてみるだけでも良いのです。大切なのは、分からないことを面白がる気持ちです。世界には、まだ解き明かされていない問いがたくさん残されています。\nたとえば台所でも、小さな実験ができます。水に溶けるものと溶けにくいものがある理由や、温度によって氷が溶ける速さが変わる理由を考えてみてください。結果を予想してから観察すると、いつもの現象が発見に変わります。大事なのは正解を急がず、何を見たのかをきちんと確かめることです。「なぜだろう」と思う気持ちを持ち続ければ、毎日の暮らしそのものが学びの場になるでしょう。",
 "anime": "アニメの魅力は、現実にはない世界まで自由に描けるところにあります。動物が話したり、遠い宇宙を旅したり、ほんの小さな気持ちの変化を大きな映像で見せたりできます。それでいて、登場人物の悩みや喜びには、私たちの日常と共通するものがあります。\nアニメを作る作業には、多くの人が関わっています。物語の構成、人物のデザイン、動きの設計、背景の絵、音楽、声の演技。その一つ一つが重なって、画面の中に世界が生まれます。短い場面でも、どの瞬間を強く見せるかによって、印象は大きく変わります。\n絵が動いて見えるのは、少しずつ違う絵が続けて映るからです。しかし、ただ絵をたくさん使えば良いわけではありません。止まっている時間と動く時間の組み合わせが、迫力や美しさを作ります。登場人物が振り返るまでの一瞬の間も、感情を伝える大事な表現です。\n子どもの頃に観たアニメを、大人になってから見返す人も多いでしょう。昔は主人公の冒険に夢中だったのに、今は親や先生の言葉が心に残ることもあります。作品の内容が変わらなくても、年齢や経験によって見えるものが変わるのです。\nアニメの好きな場面を思い出すとき、絵だけでなく、声や音楽も一緒に浮かぶことがあります。それほど映像と音は強く結びついています。次に一作品を観るときは、背景の色や、静かな場面の音にも注目してみてください。きっと新しい魅力に気づくはずです。\n作品を好きになる理由は、迫力のある場面だけではありません。何気ない会話や、主人公が一歩踏み出す場面に心を動かされることもあります。また、同じ声優が違う作品でまったく異なる役を演じていると、声の表現の幅に驚くかもしれません。背景の絵に季節や時代が表れていることもあります。物語だけでなく、音や色や動きまで味わうと、一つの作品を何度も楽しめるようになります。",
 "sports": "スポーツには、勝敗を超えた楽しさがあります。できなかった動きが少しできるようになること、仲間と息が合うこと、最後までやりきること。見ているだけでも、選手の工夫や努力に心を動かされることがあります。結果の数字だけでは伝わらない物語があるのです。\n運動を続けるときに大切なのは、いきなり高い目標を立てすぎないことです。自分に合った強さや時間から始め、体の反応を見ながら少しずつ工夫していく。体力や経験は人によって異なるので、誰かと同じ練習をする必要はありません。\n競技を見るときは、目立つ選手だけでなく、全体の動きにも注目してみましょう。チーム競技なら、ボールを持っていない人の走り方が大事なことがあります。個人競技でも、試合の前半と後半で作戦を変える場合があります。戦術を知ると、同じ場面の見方が変わります。\n失敗から学ぶ力も、スポーツの魅力です。うまくいかなかった原因を考え、次に試す方法を見つける。その繰り返しは、仕事や趣味にも役立ちます。ただし、痛みがあるときに無理を続けるのは良くありません。休むことも練習の一部です。\nスポーツは、年齢を重ねてからでも楽しみ方を変えられます。速く走ることだけが目標ではなく、気持ちよく歩く、体を動かす習慣を作る、仲間と交流することにも価値があります。今日の自分に合った形で続ける。それが長く楽しむための第一歩になります。\nスポーツを観戦する楽しみ方も人それぞれです。選手の技術を細かく見る人もいれば、試合全体の流れやチームの雰囲気を楽しむ人もいます。応援している側が勝つ日もあれば、負ける日もありますが、そこでしか生まれない瞬間があります。結果だけではなく、途中の工夫や選手同士の助け合いに目を向けると、次の試合も楽しみになります。体を動かす人も見る人も、自分なりの関わり方を選べるのがスポーツの良いところです。",
 "econ": "経済のニュースを理解するときは、数字だけでなく、その数字が暮らしとどうつながるかを考えると分かりやすくなります。物の値段が変われば家計に影響し、金利が変われば住宅ローンや企業の借り入れに影響します。遠い世界の話に見える経済も、実は毎日の買い物や仕事とつながっています。\n株価は、会社の現状だけで決まるわけではありません。将来どれくらい利益を生むかという期待や不安が反映されます。だから、決算が良くても事前の予想に届かなければ下がることがあります。株価の動きだけを見ていると不思議ですが、市場が何を予想していたかを考えると理解しやすくなります。\n企業を見るなら、売上高と利益の両方に注目してみましょう。売上が増えていても、材料費や人件費の増加によって利益が伸びない場合があります。反対に、売上の伸びが小さくても、効率の改善で利益が増えることもあります。一つの数字だけで会社を判断しないことが大切です。\nニュースで聞く金利、為替、物価は互いに影響し合っています。ただし、円安なら必ず株価が上がる、金利が上がれば必ず景気が悪くなる、という単純な関係ではありません。産業によって受ける影響も違います。複数の要因を分けて見ることで、ニュースを落ち着いて読むことができます。\n大切なのは、短期の値動きで慌てないことです。生活に必要なお金と投資に回すお金を分け、自分が理解できる範囲で判断する。経済を学ぶことは、特定の銘柄を買うことだけではなく、世の中の変化に気づく力を身につけることでもあります。\n経済の記事を読むときは、見出しの強い言葉だけで結論を出さないことも重要です。数字が前の月と比べて増えたのか、前年と比べて増えたのかで意味が変わることがあります。単発の変化と長い傾向を区別して見るだけでも、落ち着いた判断がしやすくなります。身近な商品の価格や、働いている会社の動きを観察することも、経済を知る入口です。難しい専門用語を一度に覚えなくても、少しずつ理解は深まっていきます。",
 "history": "歴史を学ぶ面白さは、昔の出来事が今の暮らしにつながっていると気づくことです。毎日使う言葉、町の道筋、お祭りの形、食べ物の好み。そうしたものの中には、長い時間をかけて受け継がれてきたものがあります。\n歴史を調べるとき、年号を覚えるだけでは十分ではありません。なぜ人々はその行動を選んだのか、その時代にはどんな選択肢があったのかを考えてみましょう。今なら簡単にできることでも、当時は交通や通信に時間がかかり、情報が届きにくかったはずです。時代の条件を知ると、人物の判断を別の角度から見ることができます。\n江戸時代の町を想像してみてください。遠くへの移動は今よりずっと大変でしたが、街道や宿場を通じて人や物が行き来していました。商人、職人、農民、それぞれの仕事が町や村を支えていたのです。大きな事件を起こした人物だけでなく、普通の人々の暮らしにも歴史があります。\n古い建物や博物館を訪ねるときは、展示物が何のために使われたかを考えると楽しくなります。道具の形には、使う人の工夫が表れています。小さな生活用品からでも、その時代の価値観や技術が見えてくることがあります。\n歴史の資料には、書いた人の立場による偏りがある場合もあります。一つの話だけで決めつけず、複数の資料を比べる姿勢が大切です。歴史は過去の正解を並べたものというより、人々が積み重ねた選択を理解しようとする学びなのかもしれません。\n同じ歴史上の出来事でも、住んでいた地域や立場によって経験は異なったはずです。政治を動かした人の記録だけでなく、町で働いていた人々の道具や日記が残っていれば、暮らしの様子を想像できます。史跡を訪ねたときは、なぜそこに道や建物があるのかを考えてみましょう。目の前の風景から過去の選択をたどることができます。歴史を知ることは、今の世界を違う角度から見ることにもつながります。",
 "space": "夜空を見上げると、星はすぐ近くに並んでいるように見えます。しかし、実際にはそれぞれ地球からの距離が大きく異なります。光にも進む速さがあるため、私たちが見る星の姿は、少し昔の姿です。遠い天体ほど、より過去の光を見ていることになります。\n太陽は地球にとって最も身近な恒星です。太陽からの光や熱が地球の気候や生き物の活動に大きく関わっています。昼と夜があるのは地球が自転しているからで、季節の変化には、地球の地軸の傾きと公転が関わっています。\n月の見え方が毎日変わるのも面白い現象です。月が自分で光っているわけではなく、太陽の光を反射しています。地球から見たとき、明るく見える部分の形が変化することで、満月や三日月になります。月の満ち欠けは、暦や昔の暮らしとも深いつながりがありました。\n宇宙を調べるには、望遠鏡だけでなく、電波やさまざまな種類の光を観測する装置が使われます。目に見える光では分からない現象も、別の方法で調べると新しい姿が見えてきます。私たちが宇宙について知っていることは、観測と計算の積み重ねによるものです。\n宇宙の大きさを実感するのは難しいですが、まずは今夜の月の形や星の位置を眺めることから始められます。同じ空でも、季節や時間によって見える景色が変わります。遠い世界の話が、少しだけ身近になるかもしれません。\n星空を眺めることは、昔から人々の暮らしと結びついてきました。夜空の変化から季節を感じ、方角を知る手がかりにもしてきたのです。今では観測装置が進歩し、肉眼では見えない天体の情報も集められます。それでも、空を見上げて不思議に思う気持ちは昔と変わりません。次に月を見たときは、前の日とどれくらい形が変わったかを意識してみてください。身近な観察からも宇宙の動きを感じ取れます。",
 "health": "健康を考えるときは、一つの特別な方法よりも、毎日の習慣を見直すことが大切です。食事、体を動かすこと、休むこと。そのどれか一つだけでなく、全体のバランスが体調に関わっています。人によって年齢や体力、生活環境が違うので、同じ方法が誰にでも合うとは限りません。\n睡眠は、ただ体を止めている時間ではありません。眠っている間にも体や脳は働いています。朝にすっきり起きられるか、昼間に眠気が強すぎないかなど、睡眠の質を考える目安は一つではありません。眠る前に落ち着いた時間を取ったり、起きる時刻を整えたりすることが助けになる場合があります。\n食事については、何か一つの食品だけを食べれば良いという考え方は避けたいものです。さまざまな食品を組み合わせ、無理のない形で続けることが現実的です。また、水分や活動量にも気を配りましょう。日によって体の感じ方は変わるので、その変化に気づくことも大切です。\n運動は、強い負荷だけが価値ではありません。散歩や軽い体操でも、続けやすい形で体を動かすことに意味があります。頑張りすぎて疲れをためるより、休む日も含めて生活に組み込めることが重要です。痛みや気になる症状がある場合は、無理をせず医療専門家に相談しましょう。\n健康は数字だけでは測れません。好きなことを楽しめるか、気分よく過ごせるか、人とのつながりを持てるかも、毎日の充実に関わります。今日できる小さなことを一つ選び、続けてみる。そんな積み重ねが暮らしを支えます。\n健康に関する話は、短い宣伝文句だけで判断しないようにしたいものです。ある食品や運動が話題になっても、効果の大きさや対象となる人はさまざまです。毎日の生活に無理なく取り入れられるか、続けたときに負担が大きくないかを考える必要があります。自分の体調を観察し、不安なことがあれば専門家の助けを借りる。そうした慎重さも、健康を大切にする姿勢の一つだと言えるでしょう。",
 "cooking": "料理がうまくいくかどうかは、難しい技術だけで決まるわけではありません。下ごしらえ、火加減、味見のタイミングといった基本の積み重ねが大切です。同じ材料でも、切り方や加熱する時間が違うと、食感や香りが変わります。\n例えば野菜を炒めるとき、水分が多いと蒸し焼きのようになり、香ばしさが出にくい場合があります。反対に火が強すぎると、外側だけ焦げてしまうこともあります。材料の量やフライパンの大きさに合わせて調整する必要があります。料理は小さな観察の連続なのです。\n味付けは一度に決めようとせず、少しずつ加えて味見をすると失敗しにくくなります。塩味が強いと他の味を感じにくくなることもあります。酸味や香りを少し加えると、塩を増やさなくても印象が変わる場合があります。\n料理の計画には、買い物の仕方も含まれます。使い切れる量を考え、保存が必要な食材は扱い方を確認しておく。下ごしらえを先に済ませておけば、食事の直前に慌てずにすみます。安全のため、生の肉や魚を扱った手や調理器具は、他の食材に触れる前に十分に洗いましょう。\n毎日の料理は、いつも完璧でなくて大丈夫です。前の日の料理を少しアレンジしたり、季節の野菜を一つ加えたりするだけでも変化が生まれます。食べる人が何を喜ぶかを考えながら作ることも、料理の楽しさです。今日は一つだけ、新しい工夫を試してみませんか。\n料理を覚えるには、同じメニューを少しずつ変えてみる方法もあります。前回より薄く切ってみる、火にかける時間を変える、最後の味付けを調整する。一度に全部変えると違いが分かりにくいので、一つずつ試すと発見があります。家で作る料理には、その日の気温や食べる人の体調に合わせられる良さもあります。特別な食材がなくても、手間を少しかけることで楽しい食事になります。",
 "animal": "動物を観察すると、人間とは違う体の仕組みや生活の工夫に驚くことがあります。同じ地球で暮らしていても、食べ物の探し方、周囲との連絡の取り方、子どもの育て方はさまざまです。その違いは、暮らす環境と深く関係しています。\n猫は、周りの音や動きに敏感な動物です。耳を動かして音の方向を探ったり、体の向きで気持ちを表したりします。犬は、人と長く一緒に暮らしてきた動物で、表情や動作から人の反応を読み取ることがあります。ただし、同じ種類でも性格には個体差があります。\n海の中には、陸上とはまったく違う生活を送る生き物がいます。タコは腕を器用に使い、狭い場所に入り込むことができます。魚には群れで泳ぐ種類もいれば、単独で暮らす種類もいます。生き物の姿だけでなく、行動の仕方まで見ると、その環境に合った工夫が見えてきます。\n野生動物を見かけたときは、近づきすぎたり、勝手に食べ物を与えたりしないことが大切です。人に慣れすぎると、動物自身の暮らしに影響が出ることがあります。静かに距離を保って観察することが、動物を大切にする行動につながります。\n動物の世界には、まだ知られていないことがたくさんあります。鳴き声や足跡、行動の変化からも、さまざまな情報を読み取れます。身近な鳥や虫を少し観察してみるだけでも、いつもの風景が違って見えるかもしれません。\n身近な生き物を観察するときは、何を食べているか、いつ活動しているか、どこで休んでいるかに注目してみてください。鳥なら鳴き声だけでなく、地面を歩く姿や木の枝で休む姿にも違いがあります。季節によって見かける種類が変わることもあります。動物の行動を一つ知ると、次に出会ったときの楽しみが増えます。見守る距離を保ちながら、静かに観察する時間を大切にしたいですね。",
 "nature": "自然の中で季節を感じる瞬間は、意外に身近なところにあります。春に芽が出ること、夏の夕方に風が変わること、秋に葉の色が変わること、冬に空気が澄んで見えること。どれも気温や日照時間、生き物の活動と関係しています。\n木の葉が緑色に見えるのは、光合成に関わる色素が含まれているからです。秋になると一部の木では葉の色素のバランスが変わり、黄色や赤い色が目立つようになります。紅葉の時期や色づき方は、木の種類やその年の天候によって違います。\n雨も自然の大切な循環の一部です。地面や海から蒸発した水は、空気の中で移動し、雲や雨になって戻ってきます。雨が降った後に土や草の匂いが強く感じられることもあります。普段は気づきにくい変化ですが、自然は絶えず動いているのです。\n季節の花を見るときは、咲いている花だけでなく、つぼみや葉の形にも注目してみてください。同じ道を一週間おきに歩くだけでも、景色が少しずつ変わっていることに気づくでしょう。写真を撮って比べると、小さな変化が分かりやすくなります。\n自然を楽しむときは、安全にも気を配りましょう。天候が変わりやすい場所では無理をしないこと、知らない植物やきのこを口にしないこと、野生の生き物に近づきすぎないこと。自然を守りながら自分の体も守ることが、長く楽しむために大切です。\n都会の中でも自然を感じられます。街路樹の葉の色、空を流れる雲、公園に来る鳥。毎日同じ道を歩いても、季節や天気によって風景は少しずつ変わります。写真を撮っておくと、変化に気づきやすくなります。特別な場所へ行けない日でも、窓の外を眺めるだけで発見があるかもしれません。自然の変化を感じることは、忙しい日常の中で気持ちを落ち着けるきっかけにもなるでしょう。",
 "words": "普段何気なく使っている言葉にも、長い歴史とさまざまな工夫があります。日本語には、ひらがな、カタカナ、漢字があり、同じ内容でも書き方によって印象が変わります。漢字を使うと意味が伝わりやすい場合があり、ひらがなにすると柔らかく感じられることもあります。\n会話では、話す内容だけでなく、言葉を置く順番や間の取り方も大切です。同じ一言でも、相手の話を最後まで聞いてから伝えるか、途中でさえぎるかによって受け取られ方は変わります。言葉は情報を運ぶだけでなく、人と人との関係を作る道具でもあります。\n知らない言葉に出会ったとき、意味だけでなく、どんな場面で使うかを調べると理解が深まります。辞書には似た言葉が並んでいても、使う相手や状況によって自然さが違う場合があります。例文を声に出してみると、その違いに気づきやすくなります。\n方言にも魅力があります。同じことを表していても、地域によって言い回しや音の調子が変わります。土地の言葉を聞くと、その場所の暮らしや人との距離感が感じられることがあります。違いを直すべきものとしてではなく、文化の豊かさとして楽しめるといいですね。\n相手に何かを伝えるときは、難しい言葉をたくさん使うことより、分かりやすい言葉を選ぶことが大切です。短い言葉に気持ちを込めることもできます。今日は誰かに伝えたいことを、一つだけ丁寧な言葉で表してみませんか。\n言葉を選ぶときは、相手との関係や、その場の空気も関わってきます。同じ意味でも、丁寧に伝える言い方と親しい人に使う言い方では響きが違います。言葉の細かな違いに気づくと、相手の気持ちを考えた伝え方ができるようになるかもしれません。好きな小説や歌の一節を思い出し、なぜその表現が心に残ったのかを考えるのも面白いものです。身近な日本語には、まだまだ気づいていない魅力が隠れています。",
 "book": "本を読む楽しみは、知らない世界に出会えることです。物語なら登場人物の人生を追い、歴史の本なら昔の暮らしを想像し、科学の本なら身近な不思議の理由を探れます。読む目的は人によって違いますが、ページをめくるたびに新しい視点が増えるところが魅力です。\n難しそうな本を最初から全部理解しようとすると、読むのが苦しくなることがあります。まず目次を眺め、気になる章から開いてみてもいいのです。一冊を一度で読み切る必要はありません。少しずつ読み進めたり、気になったところを何度も読み返したりするのも立派な読書です。\n物語を読むときは、自分と違う考え方を持つ登場人物に出会うことがあります。その人の行動に賛成できなくても、どうしてそう考えたのかを想像することはできます。読書は、自分以外の立場を考える練習にもなるかもしれません。\n本の選び方に正解はありません。好きな作家の作品を追いかけても、図書館で偶然見つけた一冊を手に取ってもいいのです。長編が苦手なら短編やエッセーもあります。音声で楽しむオーディオブックも、一つの読書体験と言えるでしょう。\n読んだ内容を覚えておきたいときは、心に残った一文や疑問をメモしてみてください。後から読み返すと、そのときの気持ちも思い出せることがあります。本は読み終わって終わりではなく、その後の考え方や会話につながっていきます。\n一冊の本について、何を感じたかを話し合うと、自分とは違う読み方に出会うことがあります。登場人物の行動に共感する人もいれば、違う人物の立場を気にする人もいるでしょう。正解を一つに決める必要はありません。本から受け取ったものを言葉にすると、その作品が自分の中でどう生きているのかが分かります。読み終えた本を本棚に置いておき、何年か後に読み返すのも楽しみの一つです。",
 "work": "仕事を進めるとき、忙しさと成果は必ずしも同じではありません。やることが多い日ほど、最初に何が一番大切なのかを考えると、落ち着いて取り組める場合があります。すべてを一度に片づけようとせず、優先順位を決めることが一つの工夫です。\n大きな仕事は、小さな作業に分けると始めやすくなります。例えば、資料を完成させるという目標だけでは何から手を付けるか迷いますが、見出しを作る、必要な情報を集める、最初の一段落を書く、と分ければ具体的になります。一つ終えるたびに進んでいることが分かります。\n集中する時間と休む時間を区切る方法もあります。短い時間だけ目の前の作業に集中し、その後に少し休む。こうした工夫は、作業に入りやすくする助けになることがあります。ただし、仕事の内容や体調によって向き不向きがあるので、自分に合う方法を選ぶことが大切です。\n仕事では、うまく説明することも重要です。相手に頼みごとをするときは、目的、必要なこと、期限を分けて伝えると分かりやすくなります。質問を受けたときも、答えを急ぐ前に相手が何を知りたいのかを確認すると、行き違いを減らせます。\n振り返りをするときは、できなかったことだけに注目しないでください。小さくても良かった点を見つけると、次に生かせます。毎日の仕事は完璧でなくて構いません。続けられる工夫を少しずつ増やしていくことが、長い目では大きな力になるでしょう。\n仕事のやり方を変えるときは、新しい道具を増やすだけではなく、やらなくても困らない作業がないか見直してみましょう。毎回同じ確認を繰り返しているなら、チェック項目を整理すると負担を減らせるかもしれません。道具や手順は目的のためにあります。複雑な仕組みを守ること自体が仕事にならないよう、時々立ち止まって考えることも大切です。少ない手数で確かな結果を出せる工夫を探してみたいですね。",
 "money": "お金の知識を身につけることは、難しい投資を始めることと同じではありません。毎月何にいくら使っているのかを知ることや、将来のために少しずつ備えることも、大切なお金の管理です。最初の一歩は、入ってくるお金と出ていくお金を分けて考えることです。\n家計を見るときは、毎月ほぼ同じ金額の固定費と、月によって変わる費用を区別すると分かりやすくなります。通信費や保険料、定期的なサービスなどを見直すと、日々の小さな節約より負担を減らせる場合があります。ただし、必要な保障や便利さまで無理に削らないことも大切です。\n貯金については、金額を一度に大きく増やそうとするより、無理のない額を続ける方法があります。急な出費に備えるお金と、しばらく使わない予定のお金を分けておくと、判断しやすくなります。目的と期間によって、ふさわしい管理方法は違います。\n投資には値下がりの可能性があるので、利益だけを見ないようにしましょう。仕組みを理解しないまま商品を選ぶと、想定外の値動きに驚くことがあります。手数料やリスクの説明を確認し、生活に必要なお金を無理に投資へ回さないことが基本です。\nお金の使い方には、その人の大切にしているものが表れます。何を節約し、何に使いたいのか。旅行や趣味、家族との時間など、使う目的を考えると、単なる数字以上の意味が見えてきます。お金は目的そのものではなく、暮らしを支える道具でもあるのです。\nお金について考えるとき、誰かの成功談をそのまま自分に当てはめないことも大事です。収入や生活費、将来の予定は人それぞれです。使う時期が近いお金と、長く置いておけるお金では、適した扱い方も異なります。自分に必要な備えを考えたうえで、分からない仕組みには慎重になる。そんな基本が長く役立つはずです。お金の数字だけでなく、自分が何を大切にしたいかを考えることも忘れたくありません。",
 "car": "乗り物は、人の行動範囲を大きく広げてきました。歩くことしかできなかった時代に比べ、電車や車、飛行機を使えば遠い場所へ移動できます。それぞれの乗り物には、速さだけでなく、運べる人数や荷物、走れる場所、使うエネルギーなどの違いがあります。\n自動車を見るときは、エンジンやモーターだけでなく、ブレーキ、タイヤ、操縦の仕組みにも注目してみましょう。車は動かすことだけではなく、安全に止まることが非常に大切です。便利な支援機能が付いた車でも、周囲への注意や安全な運転が欠かせません。\n電車は、一度に多くの人を運べるのが特徴です。都市では細かい時間の調整が必要で、駅での乗り降りや、別の路線との接続も重要になります。列車そのものだけでなく、駅や信号、運行管理が協力することで、移動の仕組みが成り立っています。\n電気自動車とエンジン車を比べるときは、走行中の仕組みだけでなく、充電や燃料補給の方法、使い方に合った距離なども考える必要があります。どの方式にも長所と課題があり、利用する地域や生活によって選び方は変わります。\n旅先で乗るローカル線やバスにも、日常とは違う楽しさがあります。車窓から見える景色や、駅ごとの雰囲気に地域の個性を感じられます。乗り物は単なる移動の手段ではなく、人と町をつなぎ、暮らしを支える大切な存在なのです。\n日常の移動を見直してみると、どの乗り物にも特徴があることが分かります。近い距離なら歩いた方が早い場合もありますし、遠い場所へは鉄道が便利なこともあります。車では荷物を運びやすい一方、駐車する場所が必要です。安全や周囲の人への配慮も欠かせません。目的と距離に合わせて乗り物を選ぶと、移動の時間をもっと快適にできるかもしれません。いつもの道でも、車窓の景色を眺める余裕があると違った発見があります。",
 "art": "アートを見るとき、「正しい見方」を探す必要はありません。きれいだと思うことも、少し不思議だと思うことも、心に何も浮かばないこともあります。最初の印象を大切にすると、作品との距離が近くなるかもしれません。\n絵画では、色や線、光の使い方によって雰囲気が変わります。明るい色が多い作品でも、描かれた人物の表情によって寂しく感じる場合があります。反対に、暗い背景の中に一つだけ明るい部分があると、そこへ自然に目が向きます。作り手が何を見せたいのかを考えるのも楽しみ方の一つです。\n彫刻や建築のように、立体の作品には、見る位置によって印象が変わる面白さがあります。少し離れて全体を見た後、近づいて素材や細部を眺めると、新しい発見があるかもしれません。写真や工芸にも、同じように観察する楽しみがあります。\n作品の背景を知ると理解が深まることもあります。作られた時代の出来事、使われた道具、作家が暮らしていた場所。ただし、説明を読んでから見るだけでなく、まず自分で何を感じたかを確かめるのも良いでしょう。\nアートは美術館だけにあるものではありません。町の看板、器の形、洋服の模様、公園の設計にも、人が考えた色や形の工夫があります。身の回りの何かを一つ選んで、どこが好きなのか考えてみる。そこから芸術を楽しむ時間が始まるのです。\n作品に触れるとき、作者の思いをすべて理解する必要はありません。自分がどこに目を引かれたか、どんな気分になったかを確かめてみましょう。友人と一緒に見ると、同じ作品の違う部分を見ていることに気づくかもしれません。上手に説明できなくても構いません。色が好き、形が面白い、少し懐かしい。そんな素直な印象が、アートを楽しむ入口になります。日常の中で気になる色や形を探すだけでも、小さな美術鑑賞が始まります。"
};
const TOPIC_REFLECTION = {
 "tech": "最後に、身近な技術を一つ思い浮かべてみてください。その道具がなかった頃はどうしていたのか、誰の困りごとを解決したのかを考えると、便利さの本当の意味が見えてきます。使う側の小さな気づきが、次の改善を生むきっかけになるかもしれません。",
 "game": "次に遊ぶときは、なぜその場面が楽しいのかを少し意識してみるのもおすすめです。操作が気持ちよいのか、音が心地よいのか、物語に引き込まれるのか。その理由が見つかると、ゲームの楽しさはさらに広がるでしょう。",
 "music": "次にお気に入りの曲を流したら、最初の十秒だけ一つの楽器に意識を向けてみてください。その次は歌声、その次は全体の響きへと耳を移します。何度も聴いた曲の中に、今まで気づかなかった音が見つかることがあります。",
 "movie": "次に映画を観るときは、冒頭と最後の場面を比べてみましょう。登場人物の表情、場所、流れる音楽など、何かが変わっているかもしれません。その変化を見つけると、作品が何を伝えたかったのかを考えるヒントになります。",
 "travel": "次の休日には、遠くへ出かけなくても近所の知らない道を歩いてみるのはいかがでしょうか。よく知っている町にも、初めて気づく店や古い建物があるものです。日常の中で旅のような発見を楽しむこともできます。",
 "food": "今日の食事では、最初の一口を少しゆっくり味わってみましょう。温かさ、香り、歯ごたえに意識を向けると、いつもと違う発見があるかもしれません。好きな味を見つけたら、その理由を自分の言葉で表してみるのも楽しいですね。",
 "science": "もし新しい疑問を見つけたら、すぐに答えを調べる前に、一度自分なりの予想を立ててみてください。どうしてそう考えたのかを確かめると、答えを知る喜びが大きくなります。科学はそんな小さな好奇心から始まります。",
 "anime": "好きな作品をもう一度観る機会があれば、今度は脇役や背景の動きにも注目してみてください。最初は気づかなかった細かな工夫が見つかるかもしれません。作品の楽しさは、物語の結末を知った後にも続いていくのです。",
 "sports": "次に試合を観るときは、一つだけ注目するところを決めてみませんか。守備の位置、選手の切り替えの速さ、仲間への声かけ。そこに意識を向けると、今まで見えなかった工夫が伝わってくるかもしれません。",
 "econ": "経済ニュースを一つ読んだら、数字の変化が誰の暮らしに関係するのか、どの会社に影響するのかを考えてみましょう。すぐに答えを出す必要はありません。身近な疑問を持つことが、経済を学ぶ長い道の第一歩になります。",
 "history": "古い町並みを歩く機会があれば、道がなぜ曲がっているのか、建物がどうしてそこにあるのかを考えてみると面白いものです。小さな疑問から調べ始めると、自分の暮らす場所の歴史にも新しい発見があるでしょう。",
 "space": "今夜空が晴れていたら、月や星を少し眺めてみてください。昨日と同じように見える空にも、少しずつ違いがあります。その変化に気づくことが、広い宇宙への興味を育てる小さな一歩になるかもしれません。",
 "health": "何か良い習慣を始めるなら、明日からすべてを変える必要はありません。毎日できる小さな一つを選び、体調を見ながら続けてみる。その積み重ねを大切にしましょう。無理をしないことも、健康を守る大切な工夫です。",
 "cooking": "次に料理をするときは、一つだけ工夫を決めてみてください。切る大きさをそろえる、火加減を意識する、味見を少し丁寧にする。その違いを楽しむことが、普段の食事をより豊かにしてくれます。",
 "animal": "動物の姿を見かけたら、どんな場所で何をしているのかを静かに観察してみましょう。少し距離を置くだけでも、その動きから多くのことが分かります。知らない生き物に出会う楽しみを、大切にしていきたいですね。",
 "nature": "今日は、昨日と少し違う空や木々の様子を探してみてください。小さな変化に気づくことができれば、いつもの景色も新しく感じられます。自然を楽しむ時間は、遠くの山や海に行かなくても始められるのです。",
 "words": "今日の会話で印象に残った言葉を一つ思い出してみてください。なぜその言葉が心に残ったのかを考えると、話した人の気持ちや、自分の受け取り方に気づくかもしれません。言葉は、普段の暮らしを豊かにしてくれます。",
 "book": "次に本を開くときは、気になる一節を一つだけ探してみましょう。読み終えたあとに、その言葉がなぜ心に残ったのかを考えてみると、読書の体験がさらに深まります。本との出会いは、一度きりで終わるものではありません。",
 "work": "明日の仕事を考えるときは、最初に取り組む一つだけを決めてみましょう。小さな作業を終えるだけでも、次の仕事に進みやすくなることがあります。自分に合った進め方を少しずつ育てていきたいですね。",
 "money": "お金のことを考える時間を少し取るなら、何に使ったときに満足したかを振り返るのも良い方法です。数字の増減だけでは分からない、自分にとって大切な価値が見えてくるかもしれません。",
 "car": "次に乗り物に乗ったときは、走るための仕組みだけでなく、安全に止まるための工夫にも思いを向けてみてください。普段は意識しない技術が、毎日の移動を支えていることに気づくでしょう。",
 "art": "次に町を歩くときは、気になる色や形を一つ探してみてください。特別な作品でなくても構いません。なぜそれが目に留まったのかを考えるだけで、自分なりのアートの楽しみ方が見つかるかもしれません。"
};

function splitForSpeech(text){
  return (text.match(/[^。！？]+[。！？]?/g)||[]).map(s=>s.trim()).filter(Boolean);
}
function pickEps(k){
  const topic=TOPICS[k];if(!topic)return [];
  const eps=topic.t;
  let played={};
  try{played=JSON.parse((window.__myradioSaved?.myradio_played ?? localStorage.getItem("myradio_played"))||"{}")}catch(e){}
  let done=played[k]||[];
  let pool=eps.map((_,i)=>i).filter(i=>!done.includes(i));
  if(!pool.length){done=[];pool=eps.map((_,i)=>i)}
  const sampled=[];
  // Use at least one original segment for variety and continuity with the supplied HTML.
  while(pool.length && sampled.join("").length<230){
    const n=Math.floor(Math.random()*pool.length);const index=pool.splice(n,1)[0];
    sampled.push(eps[index]);done.push(index);
  }
  played[k]=done;
  const snapshot=JSON.stringify(played);
  try{localStorage.setItem("myradio_played",snapshot);persistNative("myradio_played",snapshot)}catch(e){}
  if(window.__myradioSaved)window.__myradioSaved.myradio_played=snapshot;
  const intro=splitForSpeech(sampled.join("。"));
  const expanded=splitForSpeech(TOPIC_DEEP_DIVE[k]||"");
  const closing=splitForSpeech(TOPIC_REFLECTION[k]||"");
  // Curated paragraphs contain individual factual perspectives, not repeated padding.
  const full=["まず、この話題を少し詳しく見ていきましょう。",...intro,"ここからは、背景や身近な例を交えてお話しします。",...expanded,...closing];
  // The speaking voice affects exact duration; content is built for a relaxed ~2+ minute segment.
  return full;
}

Object.assign(TOPICS,{
history:{n:"歴史",e:"🏯",t:["江戸時代は約260年続き、世界でも珍しいほど長い平和が保たれました。"]},
space:{n:"宇宙",e:"🚀",t:["太陽の光が地球に届くまでには、約8分かかります。"]},
health:{n:"健康",e:"🌿",t:["人は眠っている間に、記憶を整理しているといわれています。"]},
cooking:{n:"料理",e:"🍳",t:["お米を研ぐときは、最初の水をすばやく捨てると、ぬかのにおいが移りにくくなります。"]},
animal:{n:"動物",e:"🐾",t:["タコには心臓が3つあります。"]},
nature:{n:"自然",e:"🌸",t:["桜は、冬の寒さを経験することで、春に目覚める仕組みを持っています。"]},
words:{n:"言葉",e:"📖",t:["ひらがなは、漢字をくずして作られた文字です。"]},
book:{n:"本",e:"📚",t:["日本最古の歴史書とされる古事記は、712年に完成しました。"]},
work:{n:"仕事術",e:"💼",t:["ポモドーロ・テクニックは、25分集中して5分休む時間管理の方法です。"]},
money:{n:"お金の知識",e:"💰",t:["複利とは、利息にさらに利息がつく仕組みのことです。"]},
car:{n:"乗り物",e:"🚗",t:["電気自動車は、エンジンの代わりにモーターで走ります。"]},
art:{n:"アート",e:"🎨",t:["ゴッホは、生きている間にほとんど絵が売れなかったといわれています。"]}
});
STYLES.length=0;STYLES.push(
{id:"f1",n:"👩 お姉さん",g:"f",pitch:1.0,rate:1.0},
{id:"f2",n:"🌟 元気な女の子",g:"f",pitch:1.75,rate:1.2},
{id:"f3",n:"🌙 おだやかな女性",g:"f",pitch:0.75,rate:0.85},
{id:"m1",n:"👨 青年",g:"m",pitch:1.0,rate:1.0},
{id:"m2",n:"🎩 渋い低音",g:"m",pitch:0.45,rate:0.85},
{id:"m3",n:"📢 アナウンサー",g:"m",pitch:0.85,rate:1.15},
{id:"m4",n:"👴 おじいさん",g:"m",pitch:0.55,rate:0.7},
{id:"k1",n:"🧒 少年",g:"m",pitch:1.85,rate:1.15}
);
let devVoice="";try{devVoice=(window.__myradioSaved?.myradio_dv ?? localStorage.getItem("myradio_dv"))||""}catch(e){}
function pickVoice(){const vs=(speechSynthesis.getVoices()||[]).filter(v=>/^ja/i.test(v.lang));if(devVoice){const d=vs.find(v=>v.voiceURI===devVoice);if(d)return d}const g=style().g;return vs.find(v=>(g==="f"?FEM:MAL).test(v.name))||vs.find(v=>!(g==="f"?MAL:FEM).test(v.name))||vs[0]||null}
function fillDev(){const sl=$("devv");if(!sl)return;const vs=hasNative() ? (window.nativeRadioVoiceList||[]) : (speechSynthesis.getVoices()||[]).filter(v=>/^ja/i.test(v.lang));sl.innerHTML="";sl.add(new Option("自動(おすすめ)",""));vs.forEach(v=>sl.add(new Option(v.name,v.voiceURI)));sl.value=devVoice||"";const hasM=vs.some(v=>v.gender==="male"||MAL.test(v.name));$("vnote").textContent=vs.length?(hasM?"":"男性の声がこの端末に見つかりません。端末の日本語音声により選択できる声が異なります。「設定」→「アクセシビリティ」→「読み上げコンテンツ」→「声」→「日本語」から男性の声を追加すると、本物の男性の声になります。"):"日本語の声を読み込み中です。"}
function renderVoices(){$("voices").innerHTML="";STYLES.forEach(s=>{const b=document.createElement("button");b.className="chip"+(s.id===styleId?" on":"");b.textContent=s.n;b.onclick=()=>{styleId=s.id;save();renderVoices();speakOne("こんにちは。この声でお届けします。")};$("voices").appendChild(b)});fillDev()}
(function(){const d=document.createElement("div");d.innerHTML='<div class="row" style="margin-top:10px"><select id="devv" style="width:100%;font:inherit;padding:10px;border-radius:10px;border:1px solid var(--line);background:var(--card);color:var(--ink)"></select></div><p class="note" id="vnote"></p>';$("voices").after(d);$("devv").onchange=e=>{devVoice=e.target.value;try{localStorage.setItem("myradio_dv",devVoice);persistNative("myradio_dv",devVoice)}catch(x){}speakOne("こんにちは。この声でお届けします。")}})();
if("speechSynthesis" in window)speechSynthesis.onvoiceschanged=fillDev;setTimeout(fillDev,1200);
let SAMPLE=null,pend=0,genDone=true;
(async()=>{try{if(window.claude&&window.claude.use)SAMPLE=await window.claude.use("sample")}catch(e){}if(!SAMPLE){const mode=$("aiMode");if(mode){mode.checked=false;mode.disabled=true}const notice=$("aino");if(notice)notice.style.display="block"}})();
const dayNo=()=>Math.floor((Date.now()-new Date(new Date().getFullYear(),0,0))/864e5);
function hist(){try{return JSON.parse((window.__myradioSaved?.myradio_hist ?? localStorage.getItem("myradio_hist"))||"{}")}catch(e){return{}}}
function addHist(k,t){const h=hist();h[k]=(h[k]||[]).concat(t).slice(-60);try{localStorage.setItem("myradio_hist",JSON.stringify(h));persistNative("myradio_hist",JSON.stringify(h))}catch(e){}}
function say(t){pend++;const u=new SpeechSynthesisUtterance(t);u.lang="ja-JP";const v=pickVoice();if(v)u.voice=v;const s=style();u.pitch=s.pitch;u.rate=s.rate;u.onstart=()=>{const L=$("log");L.querySelectorAll("p.now").forEach(p=>p.classList.remove("now"));const p=document.createElement("p");p.className="now";p.textContent=t;L.appendChild(p);while(L.children.length>8)L.removeChild(L.firstChild);L.scrollTop=1e6};const end=()=>{pend--;if(genDone&&pend<=0&&playing)stopRadio()};u.onend=end;u.onerror=end;speechSynthesis.speak(u)}
function parseEp(t){const ls=t.trim().split(/\n+/);let title="";if(/^題[::]/.test(ls[0]))title=ls.shift().replace(/^題[::]\s*/,"").trim();const body=ls.join("").replace(/[#*•]/g,"");return{title,sents:body.split("。").map(s=>s.trim()).filter(Boolean).map(s=>s+"。")}}
async function genEpisode(it){const h=(hist()[it.key]||[]).slice(-30);const d=new Date();const p="あなたは日本語のラジオパーソナリティです。次のテーマで、ラジオで読み上げるお話を書いてください。\nテーマ: "+it.q+"\n長さ: 約1000文字(3〜4分)\n条件:\n・1つの具体的な事柄を選び、背景や理由まで深く掘り下げる\n・聞き手に語りかける、です・ます調の話し言葉\n・箇条書き、記号、絵文字、括弧書きは使わない\n・確かな事実だけを書き、自信のない数字や年号は断定しない\n・今日は"+(d.getMonth()+1)+"月"+d.getDate()+"日(1年の"+dayNo()+"日目)。季節や日付にちなんだ切り口を選んでもよい\n・次の題で話した内容は避ける: "+(h.join("、")||"なし")+"\n・危険な行為の方法や、医療・投資の断定的な助言は避ける\n出力形式: 1行目は「題:」に続けて15文字以内の題名。2行目以降は本文のみ。";const r=await SAMPLE(p,{modelTier:"quick",cache:false});const e=parseEp(r.text);if(!e.sents.length)throw 0;if(e.title)addHist(it.key,e.title);return e}
async function runAI(items){stopRadio();playing=true;pend=0;genDone=false;$("play").textContent="■ 停止";$("log").innerHTML="";lockScreen();say(greeting());for(const it of items){if(!playing)return;say(it.req?"リクエストをいただいた、"+it.name+"について、お話しします。":"続いて、"+it.name+"の話題です。");const g=document.createElement("p");g.className="note";g.textContent="お話を作っています…";$("log").appendChild(g);let e=null;try{e=await genEpisode(it)}catch(x){}g.remove();if(!playing)return;if(e){if(e.title)say("今日のお話は、"+e.title+"です。");e.sents.forEach(say)}else if(TOPICS[it.key]){pickEps(it.key).forEach(say)}else say("うまくお話を作れませんでした。時間をおいて、もう一度お試しください。")}say("以上、マイラジオでした。今日も良い一日を。");genDone=true}
const _start=startRadio;startRadio=function(){if(SAMPLE&&$("aiMode")?.checked&&sel.size){runAI([...sel].map(k=>({name:TOPICS[k].n,key:k,q:TOPICS[k].n})))}else _start()};
function renderReq(){let r=[];try{r=JSON.parse((window.__myradioSaved?.myradio_req ?? localStorage.getItem("myradio_req"))||"[]")}catch(e){}const b=$("reqhist");b.innerHTML="";r.forEach(t=>{const c=document.createElement("button");c.className="chip";c.textContent=t;c.onclick=()=>{$("req").value=t};b.appendChild(c)})}
// One visible response for every tap; built-in stories work without internet.
// When the iPhone has internet, read the introduction of a related Wikipedia article.
let requestSerial=0;
function reqStatus(text){$("reqstatus").textContent=text}
function reqSource(title,url){
  const box=$("reqsource");box.textContent="";
  if(!url)return;
  const a=document.createElement("a");a.href=url;a.target="_blank";a.rel="noopener noreferrer";
  a.textContent="出典：日本語版Wikipedia「"+title+"」";
  a.style.color="var(--acc)";box.appendChild(a);
  box.appendChild(document.createTextNode(" ・ "));
  const lic=document.createElement("a");lic.href="https://creativecommons.org/licenses/by-sa/4.0/deed.ja";
  lic.target="_blank";lic.rel="noopener noreferrer";lic.textContent="CC BY-SA 4.0（抜粋・読み上げ用に整形）";
  lic.style.color="var(--acc)";box.appendChild(lic);
}
function requestLines(lines,status){
  stopRadio();
  playing=true;
  $("play").textContent="■ 停止";
  $("log").innerHTML="";
  reqStatus(status);
  let i=0;
  lockScreen();
  const next=()=>{
    if(!playing)return;
    if(i>=lines.length){stopRadio();reqStatus(status+"（読み上げ終了）");return}
    const t=lines[i++];
    const p=document.createElement("p");p.className="now";p.textContent=t;
    $("log").appendChild(p);$("log").scrollTop=1e6;
    utter(t,next);
  };
  next();
}
function matchingTopic(t){
  const q=t.toLowerCase().replace(/\s/g,"");
  const aliases=[
    ["econ",/(株式|株価|日経|投資|投資信託|nisa|金利|決算|経済|為替|円安|円高|資産)/i],
    ["tech",/(テクノロジー|スマホ|スマートフォン|技術|gps|qrコード|インターネット|通信)/i],
    ["game",/(ゲーム|ファミコン|マリオ|テトリス|マインクラフト)/i],
    ["history",/(歴史|江戸|明治|幕末|戦国)/i],
    ["travel",/(旅行|観光|新幹線|姫路城|京都|沖縄)/i],
    ["health",/(健康|睡眠|運動|ストレッチ)/i],
    ["animal",/(動物|タコ|ねこ|ネコ|猫|犬)/i],
    ["space",/(宇宙|惑星|衛星|太陽|月)/i],
    ["music",/(音楽|ピアノ|ギター|楽器|歌)/i],
    ["food",/(料理|ご飯|グルメ|カレー|食事)/i]
  ];
  for(const [k,re] of aliases)if(re.test(q))return k;
  for(const k of Object.keys(TOPICS))if(q.includes(TOPICS[k].n.toLowerCase()))return k;
  return null;
}
function localRequest(query,failedOnline){
  const known=matchingTopic(query);
  if(known){
    const title=TOPICS[known].n;
    const lines=["リクエストありがとうございます。"+title+"に関する収録済みのお話をお届けします。"];
    // A known broad category is not a tailor-made answer to every question.
    pickEps(known).forEach(x=>lines.push(x));
    lines.push("以上、収録済みのお話でした。");
    reqSource("","");
    requestLines(lines,(failedOnline?"オンライン情報を取得できなかったため、":"")+"「"+title+"」の収録済み記事を再生しています。質問そのものへの個別回答ではありません。");
    return;
  }
  const message="「"+query+"」については収録がありません。ネット接続をご確認いただくか、「株」「宇宙」「音楽」などでお試しください。";
  reqSource("","");reqStatus(message);
  $("log").textContent=message;
  stopRadio();
  speakOne("ごめんなさい。その話題はまだ収録されていません。別の話題をお試しください。");
}
window.radioLookupDidFinish=function(result){
  if(!result||result.id!==requestSerial)return;
  const query=$("req").value.trim();
  if(result.text&&result.title){
    reqSource(result.title,result.url);
    const clean=result.text.replace(/\s+/g," ").trim();
    const sentences=clean.match(/[^。！？]+[。！？]?/g)||[clean];
    const lines=["「"+query+"」に関して、日本語版ウィキペディアの「"+result.title+"」からお届けします。"];
    for(const sentence of sentences){if(sentence.trim())lines.push(sentence.trim())}
    // When Wikipedia returns only a short introduction, add the corresponding locally
    // authored explanation instead of repeating the same extract or inventing new facts.
    const topic=matchingTopic(query)||matchingTopic(result.title);
    if(lines.join("").length<800 && topic && TOPIC_DEEP_DIVE[topic]){
      lines.push("ここからは、収録済みの解説も交えてお届けします。");
      lines.push(...splitForSpeech(TOPIC_DEEP_DIVE[topic]));
    }
    lines.push("以上、お話をお届けしました。");
    requestLines(lines,"「"+result.title+"」の記事を読み上げています。声の速度により時間は前後します。（出典：日本語版Wikipedia）");
  }else localRequest(query,true);
};
function onRequest(){
  const t=$("req").value.trim();
  if(!t){reqStatus("聞きたいことを入力してください。例：猫の歴史");$("req").focus();return}
  ++requestSerial;
  // Ensure the old program does not continue playing over the requested answer.
  stopRadio();
  reqSource("","");reqStatus("「"+t+"」について探しています…");
  $("log").textContent="「"+t+"」のお話を準備しています。";
  let r=[];
  try{r=JSON.parse((window.__myradioSaved?.myradio_req ?? localStorage.getItem("myradio_req"))||"[]")}catch(e){}
  r=[t,...r.filter(x=>x!==t)].slice(0,6);
  try{localStorage.setItem("myradio_req",JSON.stringify(r));persistNative("myradio_req",JSON.stringify(r))}catch(e){}
  // Keep injected iOS persistence in sync so the recent requests refresh immediately.
  if(window.__myradioSaved)window.__myradioSaved.myradio_req=JSON.stringify(r);
  renderReq();
  if(hasNative()){
    sendNative({type:"lookup",query:t,id:requestSerial});
  }else{
    localRequest(t,false);
  }
}
$("reqgo").addEventListener("click",onRequest);
$("req").addEventListener("keydown",e=>{if(e.key==="Enter"){e.preventDefault();onRequest()}});

renderReq();
renderChs();
renderTopics();renderVoices();
</script>
</body>
</html>

"""##
}
