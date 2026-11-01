import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            RadioHomeView()
                .tabItem { Label("ラジオ", systemImage: "radio") }
            ListenerSettingsView()
                .tabItem { Label("好みを登録", systemImage: "slider.horizontal.3") }
            MorningSettingsView()
                .tabItem { Label("目覚まし", systemImage: "alarm") }
            ConnectionSettingsView()
                .tabItem { Label("AI接続", systemImage: "network") }
        }
        .tint(RadioTheme.gold)
    }
}

struct RadioHomeView: View {
    @EnvironmentObject private var store: RadioStore
    @EnvironmentObject private var player: SpeechPlayer

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("GOOD MORNING RADIO")
                                .font(.caption2.weight(.bold)).tracking(2.4).foregroundStyle(RadioTheme.gold)
                            Text("MY RADIO")
                                .font(.system(size: 40, weight: .black, design: .rounded))
                            Text("世界にひとつ、あなただけの放送局。")
                                .font(.subheadline).foregroundStyle(RadioTheme.pale)
                        }
                        Spacer()
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 53)).foregroundStyle(RadioTheme.gold)
                    }
                    .padding(.top, 14)

                    RadioPanel {
                        VStack(alignment: .leading, spacing: 15) {
                            Label("今日の番組をつくる", systemImage: "sparkles")
                                .font(.title3.weight(.bold))
                            Text("登録した関心や好みから、番組を組み立てます。")
                                .font(.subheadline).foregroundStyle(RadioTheme.pale)
                            HStack {
                                Label("\(store.profile.validMinutes)分番組", systemImage: "clock")
                                Spacer()
                                Text(store.serverURL.isEmpty ? "お試しモード" : "AI生成モード")
                            }
                            .font(.caption).foregroundStyle(RadioTheme.gold)
                            Button {
                                player.stop()
                                Task { await store.generate() }
                            } label: {
                                HStack {
                                    Spacer()
                                    if store.isGenerating { ProgressView().tint(RadioTheme.ink) }
                                    else { Image(systemName: "wand.and.stars") }
                                    Text(store.isGenerating ? "番組を制作しています…" : "新しい番組をつくる")
                                    Spacer()
                                }
                                .font(.headline)
                                .padding(15)
                                .foregroundStyle(RadioTheme.ink)
                                .background(RadioTheme.gold, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .disabled(store.isGenerating)
                            .accessibilityIdentifier("generateProgram")
                        }
                    }

                    if let program = store.lastProgram {
                        RadioPanel {
                            VStack(alignment: .leading, spacing: 13) {
                                HStack {
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                        .foregroundStyle(RadioTheme.gold)
                                    Text("NOW ON AIR").font(.caption.weight(.bold)).tracking(2)
                                    Spacer()
                                    if program.isSample {
                                        Text("お試し音声")
                                            .font(.caption2).padding(.horizontal, 9).padding(.vertical, 5)
                                            .background(.white.opacity(0.1), in: Capsule())
                                    }
                                }
                                Text(program.title).font(.title2.weight(.bold))
                                if program.isSample {
                                    Text("これは短い操作確認用の原稿です。AIニュースや10分番組ではありません。")
                                        .font(.caption).foregroundStyle(RadioTheme.pale)
                                } else {
                                    Text("AIが作成した番組・音声は端末の日本語読み上げを使用")
                                        .font(.caption).foregroundStyle(RadioTheme.pale)
                                }
                                HStack(spacing: 12) {
                                    Button {
                                        if !player.isSpeaking { player.play(program, style: store.profile.style) }
                                        else { player.togglePause() }
                                    } label: {
                                        Label(!player.isSpeaking ? "再生" : (player.isPaused ? "再開" : "一時停止"),
                                              systemImage: !player.isSpeaking ? "play.fill" : (player.isPaused ? "play.fill" : "pause.fill"))
                                        .frame(maxWidth: .infinity).padding(14)
                                        .background(RadioTheme.gold, in: RoundedRectangle(cornerRadius: 13))
                                        .foregroundStyle(RadioTheme.ink)
                                    }
                                    .accessibilityIdentifier("playProgram")
                                    Button { player.stop() } label: {
                                        Label("停止", systemImage: "stop.fill")
                                            .padding(14)
                                            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                                    }
                                    .disabled(!player.isSpeaking)
                                }
                                Button {
                                    store.recordLike()
                                } label: {
                                    Label("この話題をもっと聞きたい", systemImage: "hand.thumbsup")
                                        .font(.subheadline)
                                }
                                .disabled(program.isSample)
                                .foregroundStyle(RadioTheme.gold)
                                DisclosureGroup("番組の原稿を読む") {
                                    Text(program.script)
                                        .font(.body).lineSpacing(6).textSelection(.enabled)
                                        .padding(.top, 10)
                                }
                                .font(.subheadline)
                                if !program.sources.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("ニュースの情報源")
                                            .font(.subheadline.weight(.semibold))
                                        ForEach(program.sources) { source in
                                            if let url = URL(string: source.url), url.scheme == "https" {
                                                Link(destination: url) {
                                                    Label(source.title, systemImage: "arrow.up.right.square")
                                                        .font(.caption).multilineTextAlignment(.leading)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        RadioPanel {
                            VStack(alignment: .leading, spacing: 9) {
                                Label("最初の一歩", systemImage: "headphones")
                                    .font(.headline)
                                Text("「好みを登録」で好きな分野を設定し、番組を作ってみましょう。AIを接続しなくても、短いお試し放送を聞けます。")
                                    .font(.subheadline).foregroundStyle(RadioTheme.pale)
                            }
                        }
                    }

                    if let message = store.errorMessage {
                        Text(message)
                            .font(.subheadline).foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    }
                    Text("読み上げ音声はAI・音声合成技術によるもので、人間の生放送ではありません。")
                        .font(.caption2).foregroundStyle(RadioTheme.pale)
                }
                .padding(20)
            }
            .background(RadioTheme.ink.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct ListenerSettingsView: View {
    @EnvironmentObject private var store: RadioStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("呼ばれたい名前（任意）", text: $store.profile.nickname)
                    Picker("年齢層（任意）", selection: $store.profile.ageGroup) {
                        ForEach(["回答しない", "10代", "20代", "30代", "40代", "50代", "60代", "70代", "80代以上"], id: \.self) { Text($0) }
                    }
                    Picker("性別（任意）", selection: $store.profile.gender) {
                        ForEach(["回答しない", "男性", "女性", "その他"], id: \.self) { Text($0) }
                    }
                    TextField("地域（任意・例：東京都）", text: $store.profile.area)
                } header: {
                    Text("あなたについて")
                } footer: {
                    Text("年齢・性別は空欄でも使えます。興味・関心を優先して番組を作ります。")
                }

                Section("興味のある分野（複数選択可）") {
                    ForEach(ListenerProfile.interestOptions, id: \.self) { item in
                        Button {
                            if store.profile.interests.contains(item) {
                                store.profile.interests.removeAll { $0 == item }
                            } else {
                                store.profile.interests.append(item)
                            }
                        } label: {
                            HStack {
                                Text(item).foregroundStyle(.primary)
                                Spacer()
                                if store.profile.interests.contains(item) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(RadioTheme.gold)
                                }
                            }
                        }
                    }
                }
                Section {
                    TextEditor(text: $store.profile.detail)
                        .frame(minHeight: 110)
                        .accessibilityLabel("詳しい興味や好きなこと")
                } header: {
                    Text("具体的な趣味・好み（最重要）")
                } footer: {
                    Text("例：1970年代のフォーク、アコースティックギター、成長株の分析、歴史的な街並み。具体的に書くほど番組に反映しやすくなります。")
                }
                Section {
                    TextEditor(text: $store.profile.avoid)
                        .frame(minHeight: 75)
                        .accessibilityLabel("聞きたくない話題")
                } header: {
                    Text("聞きたくない話題")
                } footer: {
                    Text("個人情報は端末に保存され、AI番組生成時のみ接続先サーバーへ送信します。")
                }
                Section("番組スタイル") {
                    Picker("話し方", selection: $store.profile.style) {
                        ForEach(["親しみやすいDJ", "落ち着いた解説", "元気なDJ"], id: \.self) { Text($0) }
                    }
                    Picker("番組時間", selection: $store.profile.minutes) {
                        Text("5分").tag(5)
                        Text("10分").tag(10)
                        Text("20分").tag(20)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(RadioTheme.ink)
            .navigationTitle("あなたの好み")
        }
    }
}

struct MorningSettingsView: View {
    @EnvironmentObject private var store: RadioStore
    @State private var resultMessage: String?

    private var reminderDate: Binding<Date> {
        Binding(get: {
            Calendar.current.startOfDay(for: Date())
                .addingTimeInterval(TimeInterval(store.profile.reminderMinutes * 60))
        }, set: { newValue in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            store.profile.reminderMinutes = (components.hour ?? 7) * 60 + (components.minute ?? 0)
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("朝のマイラジオ") {
                    Toggle("毎朝お知らせする", isOn: $store.profile.reminderEnabled)
                    DatePicker("お知らせ時刻", selection: reminderDate, displayedComponents: .hourAndMinute)
                    Button("この時刻で通知を設定") {
                        Task {
                            if store.profile.reminderEnabled {
                                do {
                                    try await NotificationService.schedule(minutes: store.profile.reminderMinutes)
                                    resultMessage = "毎朝の通知を登録しました。通知をタップするとアプリを開けます。"
                                } catch {
                                    resultMessage = error.localizedDescription
                                }
                            } else {
                                NotificationService.cancel()
                                resultMessage = "毎朝の通知を解除しました。"
                            }
                        }
                    }
                    .foregroundStyle(RadioTheme.gold)
                }
                Section("目覚ましについて") {
                    Text("この初期版はiPhoneの通知音で起床時刻を知らせます。通知をタップしてアプリを開き、番組を再生してください。")
                    Text("アプリを閉じたまま10分間の番組を自動再生する機能は、まだ実装していません。通常の目覚まし時計の代用にはしないでください。")
                }
                if let resultMessage {
                    Section("設定結果") { Text(resultMessage) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(RadioTheme.ink)
            .navigationTitle("おはようラジオ")
        }
    }
}

struct ConnectionSettingsView: View {
    @EnvironmentObject private var store: RadioStore
    @State private var token = ""
    @State private var saved = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://your-server.example", text: $store.serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)
                    SecureField("試作用アクセス・トークン", text: $token)
                        .textContentType(.password)
                    Button("接続情報を保存") {
                        CredentialVault.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
                        saved = true
                    }
                    .foregroundStyle(RadioTheme.gold)
                    if saved { Text("接続設定を端末内に保存しました。").font(.caption) }
                } header: {
                    Text("AI番組制作サーバー")
                } footer: {
                    Text("URL未設定ならお試し原稿を再生します。OpenAIのAPIキーはiPhoneに入力せず、サーバーの環境変数に設定してください。")
                }
                Section("プライバシー・安全") {
                    Text("好み、年齢層、性別、地域など、入力した情報は番組生成のためサーバーとAI提供元に送信されます。不要な情報は登録しないでください。")
                    Text("AI生成のニュースには誤りが含まれる場合があります。情報源を確認してください。")
                    Text("この接続方式は個人試作専用です。一般販売前にユーザー認証と利用制限が必要です。")
                    Button("保存した個人情報をすべて削除", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(RadioTheme.ink)
            .navigationTitle("AI接続とデータ")
            .onAppear { token = CredentialVault.read() }
            .confirmationDialog("番組・設定・接続情報を削除しますか？", isPresented: $showDeleteConfirmation) {
                Button("すべて削除", role: .destructive) {
                    store.erasePersonalData()
                    token = ""
                    saved = false
                }
                Button("キャンセル", role: .cancel) { }
            }
        }
    }
}
