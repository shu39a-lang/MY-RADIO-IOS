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
            let url = folder.appendingPathComponent("myradio-screen-v041.html")
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
            case "schedule": scheduleAlarm(payload)
            case "cancelAlarm":
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationID])
            default: break
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
    <div class="chips" id="topics"></div>
  </div>

<div class="card">
    <h2>🎤 聴きたいことをリクエスト</h2>
    <div class="row"><input type="text" id="req" placeholder="例:猫の歴史、投資信託の選び方" style="flex:1;min-width:0;font:inherit;padding:10px;border-radius:10px;border:1px solid var(--line);background:var(--card);color:var(--ink)"><button class="btn pri" id="reqgo">お話しして</button></div>
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
  sendNative({type:"speak",id,text,gender:s.g,pitch:s.pitch,rate:s.rate,voiceID:devVoice||""});
  return;
 }
 const u=new SpeechSynthesisUtterance(text);u.lang="ja-JP";const v=pickVoice();if(v)u.voice=v;const s=style();u.pitch=s.pitch;u.rate=s.rate;u.onend=done;u.onerror=done;speechSynthesis.speak(u)
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
function pickEps(k){const eps=TOPICS[k].t;let played={};try{played=JSON.parse((window.__myradioSaved?.myradio_played ?? localStorage.getItem("myradio_played"))||"{}")}catch(e){played={}}let done=played[k]||[];let pool=eps.map((_,i)=>i).filter(i=>!done.includes(i));if(!pool.length){done=[];pool=eps.map((_,i)=>i)}pool.sort(()=>Math.random()-.5);const out=[];let len=0;for(const i of pool){out.push(i);len+=eps[i].length;if(len>=700)break}played[k]=done.concat(out);try{localStorage.setItem("myradio_played",JSON.stringify(played));persistNative("myradio_played",JSON.stringify(played))}catch(e){}const L=[];out.forEach((i,n)=>{if(n>0)L.push("では、もう一つ。");eps[i].split("。").filter(s=>s.trim()).forEach(s=>L.push(s+"。"))});return L}
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
$("reqgo").onclick=()=>{const t=$("req").value.trim();if(!t)return;ensureAudio();let r=[];try{r=JSON.parse((window.__myradioSaved?.myradio_req ?? localStorage.getItem("myradio_req"))||"[]")}catch(e){}r=[t,...r.filter(x=>x!==t)].slice(0,6);try{localStorage.setItem("myradio_req",JSON.stringify(r));persistNative("myradio_req",JSON.stringify(r))}catch(e){}renderReq();
 if(SAMPLE){runAI([{name:t,key:"req:"+t,q:t,req:true}]);return}
 const known=Object.keys(TOPICS).find(k=>t.toLowerCase().includes(TOPICS[k].n.toLowerCase()))
   || (/(株|投資|nisa|金利|決算)/i.test(t)?"econ":null)
   || (/(スマホ|技術|gps|qrコード)/i.test(t)?"tech":null)
   || (/(ファミコン|マリオ|テトリス)/i.test(t)?"game":null)
   || (/(睡眠|健康)/i.test(t)?"health":null)
   || (/(歴史|江戸)/i.test(t)?"history":null)
   || (/(宇宙|衛星|太陽)/i.test(t)?"space":null)
   || (/(旅行|観光|新幹線)/i.test(t)?"travel":null)
   || (/(ピアノ|ギター|楽器)/i.test(t)?"music":null);
 if(!known){$("log").innerHTML='<p class="note">このリクエストは収録されていません。現在は用意された話題の中からお届けします。</p>';return;}
 if(/(最新|今日の|現在の|速報)/.test(t)) alert("最新情報は取得せず、収録済みのお話を再生します。");
 const prev=sel;sel=new Set([known]);startRadio();sel=prev;
};
renderReq();
renderChs();
renderTopics();renderVoices();
</script>
</body>
</html>

"""##
}
