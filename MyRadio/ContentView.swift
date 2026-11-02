import SwiftUI

struct ContentView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            RadioHomeView()
                .tabItem { Label("ラジオ", systemImage: "radio") }
                .tag(0)
            ListenerSettingsView(onTryRadio: { selection = 0 })
                .tabItem { Label("好みを登録", systemImage: "slider.horizontal.3") }
                .tag(1)
            MorningSettingsView()
                .tabItem { Label("目覚まし", systemImage: "alarm") }
                .tag(2)
            ConnectionSettingsView()
                .tabItem { Label("AI接続", systemImage: "network") }
                .tag(3)
        }
        .tint(RadioTheme.gold)
    }
}

struct RadioHomeView: View {
    @EnvironmentObject private var store: RadioStore
    @EnvironmentObject private var player: SpeechPlayer

    private var focused: [ProgramFocus] { PersonalizationEngine.plannedTopics(store.profile) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [RadioTheme.gold.opacity(0.95), Color(red: 0.56, green: 0.41, blue: 0.28)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 62, height: 62)
                            Circle()
                                .stroke(RadioTheme.pale.opacity(0.85), lineWidth: 2)
                                .frame(width: 52, height: 52)
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 25, weight: .bold))
                                .foregroundStyle(RadioTheme.ink)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("MY RADIO")
                                .font(.system(size: 34, weight: .bold, design: .serif))
                                .tracking(1.2)
                                .foregroundStyle(RadioTheme.pale)
                            Text("世界に1つ、あなただけの放送局")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(RadioTheme.gold)
                        }
                        Spacer()
                    }
                    .padding(.top, 14)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 0.35, green: 0.24, blue: 0.18), Color(red: 0.20, green: 0.15, blue: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(RadioTheme.gold.opacity(0.7), lineWidth: 1.5)
                            )
                            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                    )

                    RadioPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("あなたの番組設計", systemImage: "person.crop.circle.badge.checkmark")
                                    .font(.headline)
                                Spacer()
                                Text("\(store.profile.selectedTopics.count)テーマ")
                                    .font(.caption).foregroundStyle(RadioTheme.gold)
                            }
                            let identity = [
                                store.profile.nickname.isEmpty ? "" : "お名前：\(store.profile.nickname)",
                                store.profile.ageGroup == "回答しない" ? "" : store.profile.ageGroup,
                                store.profile.gender == "回答しない" ? "" : store.profile.gender,
                                store.profile.area
                            ].filter { !$0.isEmpty }.joined(separator: " / ")
                            if !identity.isEmpty {
                                Text(identity)
                                    .font(.caption).foregroundStyle(RadioTheme.pale)
                            }
                            Text(PersonalizationEngine.previewDescription(store.profile))
                                .font(.subheadline).foregroundStyle(RadioTheme.pale)
                            if focused.isEmpty {
                                Text("好みの登録で話題を選ぶと、ここに番組の構成が表示されます。")
                                    .font(.caption).foregroundStyle(RadioTheme.gold)
                            }
                            ForEach(focused) { focus in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 9) {
                                        Text(focus.label)
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(focus.importance == 3 ? RadioTheme.ink : RadioTheme.gold)
                                            .padding(.horizontal, 8).padding(.vertical, 5)
                                            .background(focus.importance == 3 ? RadioTheme.gold : RadioTheme.gold.opacity(0.13), in: Capsule())
                                        Text(focus.topic).font(.subheadline.weight(.semibold))
                                    }
                                    if !focus.note.isEmpty {
                                        Text("詳しく：\(focus.note)")
                                            .font(.caption).foregroundStyle(RadioTheme.pale)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 3)
                            }
                            if !store.profile.favoritePeople.isEmpty {
                                Text("好きな人物・作品：\(store.profile.favoritePeople)")
                                    .font(.caption).foregroundStyle(RadioTheme.pale)
                            }
                            if !store.profile.avoid.isEmpty {
                                Text("避ける話題：\(store.profile.avoid)")
                                    .font(.caption).foregroundStyle(RadioTheme.pale)
                            }
                            if !store.profile.detail.isEmpty {
                                Text("自由入力：\(store.profile.detail)")
                                    .font(.caption).foregroundStyle(RadioTheme.pale)
                                    .lineLimit(4)
                            }
                            Text("目的：\(store.profile.listeningGoal) / ニュース：\(store.profile.includeNews ? "あり" : "なし")")
                                .font(.caption).foregroundStyle(RadioTheme.pale)
                            HStack {
                                Label("\(store.profile.validMinutes)分", systemImage: "clock")
                                Spacer()
                                Label(store.serverURL.isEmpty ? (CredentialVault.readPersonalKey().isEmpty ? "AIキー未登録" : "個人AI利用可") : "AIサーバー利用中", systemImage: "antenna.radiowaves.left.and.right")
                            }
                            .font(.caption).foregroundStyle(RadioTheme.gold)
                        }
                    }

                    RadioPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("この設定で放送を作る", systemImage: "sparkles")
                                .font(.title3.weight(.bold))
                            Text("登録した趣味と興味を使って、その場であなただけの放送を作ります。初回だけ「AI接続」で個人用APIキーを登録してください。")
                                .font(.subheadline).foregroundStyle(RadioTheme.pale)
                            Button {
                                player.stop()
                                Task { await store.generate() }
                            } label: {
                                HStack {
                                    Spacer()
                                    if store.isGenerating { ProgressView().tint(RadioTheme.ink) }
                                    else { Image(systemName: "wand.and.stars") }
                                    Text(store.isGenerating ? "放送を制作しています…" : "今の設定で放送を作成")
                                    Spacer()
                                }
                                .font(.headline)
                                .padding(15)
                                .foregroundStyle(RadioTheme.ink)
                                .background(RadioTheme.gold, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .disabled(store.isGenerating || store.profile.selectedTopics.isEmpty)
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

                                }
                                Text(program.title).font(.title2.weight(.bold))
                                Text("あなたの個人設定をもとに放送を制作し、選択した声で自然な日本語音声を再生します。")
                                    .font(.caption).foregroundStyle(RadioTheme.pale)
                                HStack(spacing: 12) {
                                    Button {
                                        if !player.isSpeaking {
                                            Task { await player.play(program, profile: store.profile, endpoint: store.serverURL) }
                                        } else { player.togglePause() }
                                    } label: {
                                        Label(player.isPreparing ? "音声を準備中…" : (!player.isSpeaking ? "AI音声で再生" : (player.isPaused ? "再開" : "一時停止")),
                                              systemImage: !player.isSpeaking ? "play.fill" : (player.isPaused ? "play.fill" : "pause.fill"))
                                            .frame(maxWidth: .infinity).padding(14)
                                            .background(RadioTheme.gold, in: RoundedRectangle(cornerRadius: 13))
                                            .foregroundStyle(RadioTheme.ink)
                                    }
                                    .disabled(player.isPreparing)
                                    .accessibilityIdentifier("playProgram")
                                    Button { player.stop() } label: {
                                        Label("停止", systemImage: "stop.fill")
                                            .padding(14)
                                            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                                    }
                                    .disabled(!player.isSpeaking && !player.isPreparing)
                                }
                                Button { store.recordLike() } label: {
                                    Label("この番組をもっと聞きたい", systemImage: "hand.thumbsup")
                                        .font(.subheadline)
                                }
                                .foregroundStyle(RadioTheme.gold)
                                Text("選択中の声：\(VoiceCatalog.label(for: store.profile.voiceID))")
                                    .font(.caption).foregroundStyle(RadioTheme.pale)
                                if player.isPreparing {
                                    ProgressView(player.preparationProgress).tint(RadioTheme.gold)
                                }
                                if let audioError = player.errorMessage {
                                    Text(audioError).font(.caption).foregroundStyle(.red)
                                }
                                DisclosureGroup("番組の原稿を読む") {
                                    Text(program.script)
                                        .font(.body).lineSpacing(6).textSelection(.enabled)
                                        .padding(.top, 10)
                                }
                                .font(.subheadline)
                                if !program.sources.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("情報源").font(.subheadline.weight(.semibold))
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
                                Label("最初の一歩", systemImage: "headphones").font(.headline)
                                Text("「好みを登録」で具体的な趣味と声を選び、AI接続を設定して本番の番組を作成してください。")
                                    .font(.subheadline).foregroundStyle(RadioTheme.pale)
                            }
                        }
                    }

                    if let message = store.errorMessage {
                        Text(message).font(.subheadline).foregroundStyle(.red)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    }
                    Text("音声はAIが生成しています。人間が収録した音声ではありません。音声の自然さは声・原稿・言語によって異なります。")
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
    @EnvironmentObject private var voicePlayer: SpeechPlayer
    let onTryRadio: () -> Void
    @State private var newTopic = ""
    @State private var addError = ""

    private func importanceBinding(_ topic: String) -> Binding<Int> {
        Binding(get: { store.profile.importance(for: topic) },
                set: { store.profile.topicImportance[topic] = $0 })
    }

    private func noteBinding(_ topic: String) -> Binding<String> {
        Binding(get: { store.profile.topicNotes[topic] ?? "" },
                set: { store.profile.topicNotes[topic] = String($0.prefix(300)) })
    }

    private func addTopic() {
        let cleaned = newTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        guard cleaned.count <= 45 else { addError = "45文字以内で入力してください。"; return }
        guard !store.profile.selectedTopics.contains(cleaned) else { addError = "すでに登録されています。"; return }
        guard store.profile.customTopics.count < 15 else { addError = "自由テーマは15件までです。"; return }
        store.profile.customTopics.append(cleaned)
        store.profile.topicImportance[cleaned] = 3
        newTopic = ""
        addError = ""
    }

    private func topicEditor(_ topic: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("興味の強さ", selection: importanceBinding(topic)) {
                Text("少し").tag(1)
                Text("好き").tag(2)
                Text("最優先").tag(3)
            }
            .pickerStyle(.segmented)
            TextField("具体的に何を聞きたい？（例：70年代のフォーク）", text: noteBinding(topic), axis: .vertical)
                .lineLimit(2...4)
                .font(.subheadline)
                .accessibilityIdentifier("topicNote-\(topic)")
        }
        .padding(.vertical, 6)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("あなた向けの番組プレビュー", systemImage: "waveform.path")
                            .font(.headline).foregroundStyle(RadioTheme.gold)
                        Text(PersonalizationEngine.previewDescription(store.profile))
                            .font(.subheadline)
                        Text("\(store.profile.selectedTopics.count)個の話題・\(store.profile.validMinutes)分・\(store.profile.depth)")
                            .font(.caption).foregroundStyle(.secondary)
                        Button {
                            store.errorMessage = nil
                            Task {
                                await store.generate()
                                if store.errorMessage == nil { onTryRadio() }
                            }
                        } label: {
                            Label(store.isGenerating ? "本番放送を制作中…" : "この設定で放送を制作", systemImage: "sparkles")
                                .font(.headline)
                        }
                        .disabled(store.isGenerating || store.profile.selectedTopics.isEmpty)
                        if let message = store.errorMessage {
                            Text(message).font(.caption).foregroundStyle(.red)
                        }
                        .foregroundStyle(RadioTheme.gold)
                    }
                    .padding(.vertical, 5)
                }
                Section {
                    TextField("呼ばれたい名前（任意）", text: $store.profile.nickname)
                    Picker("年齢層（任意）", selection: $store.profile.ageGroup) {
                        ForEach(["回答しない", "10代", "20代", "30代", "40代", "50代", "60代", "70代", "80代以上"], id: \.self) { Text($0) }
                    }
                    Picker("性別（任意）", selection: $store.profile.gender) {
                        ForEach(["回答しない", "男性", "女性", "その他"], id: \.self) { Text($0) }
                    }
                    TextField("地域（任意・例：東京都）", text: $store.profile.area)
                } header: { Text("あなたについて") }
                footer: { Text("年齢・性別は必須ではありません。番組は興味・関心を優先します。") }

                Section {
                    ForEach(ListenerProfile.interestOptions, id: \.self) { topic in
                        let selected = store.profile.interests.contains(topic)
                        Button {
                            if selected { store.profile.interests.removeAll { $0 == topic } }
                            else { store.profile.interests.append(topic) }
                        } label: {
                            HStack {
                                Text(topic).foregroundStyle(.primary)
                                Spacer()
                                if selected {
                                    if store.profile.importance(for: topic) == 3 {
                                        Text("最優先").font(.caption).foregroundStyle(RadioTheme.gold)
                                    }
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(RadioTheme.gold)
                                } else {
                                    Image(systemName: "circle").foregroundStyle(.secondary)
                                }
                            }
                        }
                        if selected { topicEditor(topic) }
                    }
                } header: { Text("興味のある分野") }
                footer: { Text("分野を選ぶと、興味の強さと具体的な内容を登録できます。「最優先」の話題から番組を組み立てます。") }

                Section {
                    HStack {
                        TextField("自分だけの話題を追加", text: $newTopic)
                            .onSubmit(addTopic)
                        Button("追加", action: addTopic).disabled(newTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if !addError.isEmpty { Text(addError).font(.caption).foregroundStyle(.red) }
                    ForEach(store.profile.customTopics, id: \.self) { topic in
                        HStack {
                            Text(topic).font(.subheadline.weight(.semibold))
                            Spacer()
                            Button(role: .destructive) {
                                store.profile.customTopics.removeAll { $0 == topic }
                                store.profile.topicNotes.removeValue(forKey: topic)
                                store.profile.topicImportance.removeValue(forKey: topic)
                            } label: { Image(systemName: "trash") }
                        }
                        topicEditor(topic)
                    }
                } header: { Text("カテゴリーにない趣味・こだわり") }
                footer: { Text("好きな歌手、車種、釣り方、特定の歴史人物など、細かいテーマも自由に登録できます。") }

                Section {
                    TextEditor(text: $store.profile.detail)
                        .frame(minHeight: 100)
                        .accessibilityLabel("趣味の詳しい希望")
                    TextField("好きな人物・作品・番組（任意）", text: $store.profile.favoritePeople, axis: .vertical)
                        .lineLimit(2...5)
                } header: { Text("自由に伝えたいこと") }
                footer: { Text("例：1970年代の日本のフォークが好き。特にアコースティックギターの弾き語りについて知りたい。") }

                Section {
                    Picker("聴く目的", selection: $store.profile.listeningGoal) {
                        ForEach(ListenerProfile.goalOptions, id: \.self) { Text($0) }
                    }
                    Picker("説明の深さ", selection: $store.profile.depth) {
                        ForEach(ListenerProfile.depthOptions, id: \.self) { Text($0) }
                    }
                    Picker("話し方", selection: $store.profile.style) {
                        ForEach(["親しみやすいDJ", "落ち着いた解説", "元気なDJ"], id: \.self) { Text($0) }
                    }
                    Picker("AIパーソナリティの声", selection: $store.profile.voiceID) {
                        ForEach(VoiceCatalog.all) { voice in
                            Text(voice.label).tag(voice.id)
                        }
                    }
                    Text("選択中：\(VoiceCatalog.label(for: store.profile.voiceID))")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        Task {
                            await voicePlayer.preview(voice: store.profile.voiceID, style: store.profile.style,
                                                      endpoint: store.serverURL)
                        }
                    } label: {
                        Label(voicePlayer.isPreparing ? "声を生成中…" : "この声を実際に試聴する", systemImage: "waveform")
                    }
                    .disabled(voicePlayer.isPreparing)
                    Button("試聴を停止") { voicePlayer.stop() }
                        .disabled(!voicePlayer.isSpeaking)
                    if let voiceError = voicePlayer.errorMessage {
                        Text(voiceError).font(.caption).foregroundStyle(.red)
                    }
                    Text("男性系・女性系は声の印象の目安です。試聴してお好みの声を選べます。音声はAI生成です。")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("番組時間", selection: $store.profile.minutes) {
                        Text("5分").tag(5)
                        Text("10分").tag(10)
                        Text("20分").tag(20)
                    }
                    Toggle("確認できた最新ニュースも聞く", isOn: $store.profile.includeNews)
                } header: { Text("番組の仕上げ") }
                footer: { Text("本物の音声を作ります。AIサーバーが接続されていない場合は声の試聴もできません。番組時間は読み上げ速度により前後します。") }

                Section {
                    TextEditor(text: $store.profile.avoid)
                        .frame(minHeight: 80)
                        .accessibilityLabel("避けたい話題")
                } header: { Text("聞きたくないこと") }
                footer: { Text("話題や単語を「、」で区切ってください。AI番組生成時にも避けるよう指示します。") }

                Section {
                    Text("入力内容は自動でiPhoneに保存されます。アプリを閉じても残ります。")
                    Text("AIサーバーが接続されている場合だけ、番組制作のために設定した情報をサーバーへ送信します。")
                } header: { Text("保存とプライバシー") }
            }
            .scrollContentBackground(.hidden)
            .background(LinearGradient(colors: [Color(red: 0.145, green: 0.118, blue: 0.110), RadioTheme.ink], startPoint: .topLeading, endPoint: .bottomTrailing))
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
                    Text("毎朝のお知らせはiPhoneの通知で行います。通知をタップしてアプリを開き、保存した番組を再生してください。")
                    Text("アプリを閉じたまま10分間の番組を自動再生する機能は、まだ実装していません。通常の目覚まし時計の代用にはしないでください。")
                }
                if let resultMessage {
                    Section("設定結果") { Text(resultMessage) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LinearGradient(colors: [Color(red: 0.145, green: 0.118, blue: 0.110), RadioTheme.ink], startPoint: .topLeading, endPoint: .bottomTrailing))
            .navigationTitle("おはようラジオ")
        }
    }
}

struct ConnectionSettingsView: View {
    @EnvironmentObject private var store: RadioStore
    @State private var token = ""
    @State private var personalKey = ""
    @State private var personalKeySaved = false
    @State private var saved = false
    @State private var connectionResult: String?
    @State private var checkingConnection = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("自分のiPhoneで実際のAIラジオを聴く方法です。ご自身のOpenAI APIキーを1回登録してください。")
                    SecureField("ご自身のOpenAI APIキー", text: $personalKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("個人用AIキーを保存") {
                        let value = personalKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty { CredentialVault.savePersonalKey(value) }
                        personalKeySaved = !CredentialVault.readPersonalKey().isEmpty
                        personalKey = ""
                    }
                    .foregroundStyle(RadioTheme.gold)
                    Text(personalKeySaved ? "APIキー登録済み。個人設定から本物のAI番組を作れます。" : "APIキーが未登録です。")
                        .font(.caption)
                    if personalKeySaved {
                        Button("個人用AIキーを消去", role: .destructive) {
                            CredentialVault.deletePersonalKey()
                            personalKeySaved = false
                        }
                    }
                    Link("OpenAI APIキーを作成・確認", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.subheadline)
                } header: { Text("個人用AIラジオ（まずはこちら）") }
                  footer: { Text("ChatGPTの契約とは別にOpenAI APIの課金設定が必要です。キーは端末のKeychainへ保存します。他人と共有せず、一般販売用アプリにはこの方式を使用しません。") }
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
                    Button(checkingConnection ? "接続を確認中…" : "AIサーバーの接続を確認") {
                        checkingConnection = true
                        Task {
                            connectionResult = await ProgramService.connectionStatus(endpoint: store.serverURL)
                            checkingConnection = false
                        }
                    }
                    .disabled(checkingConnection)
                    .foregroundStyle(RadioTheme.gold)
                    if let connectionResult {
                        Text(connectionResult).font(.caption)
                    }
                } header: {
                    Text("AI番組制作サーバー")
                } footer: {
                    Text("一般販売へ移行するときは、このHTTPSサーバー方式を使用します。URLを空欄にしておけば、上の個人用AIキーで実際の番組を作ります。サーバー用OpenAIキーはiPhoneに記録しません。")
                }
                Section("プライバシー・安全") {
                    Text("好み、年齢層、性別、地域など、入力した情報は番組生成のためサーバーとAI提供元に送信されます。不要な情報は登録しないでください。")
                    Text("AI生成のニュースには誤りが含まれる場合があります。情報源を確認してください。")
                    Text("現在の接続方式は個人向けβ版です。一般販売前にはユーザー別の認証・費用制限・課金連携が必要です。")
                    Button("保存した個人情報をすべて削除", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LinearGradient(colors: [Color(red: 0.145, green: 0.118, blue: 0.110), RadioTheme.ink], startPoint: .topLeading, endPoint: .bottomTrailing))
            .navigationTitle("AI接続とデータ")
            .onAppear {
                token = CredentialVault.read()
                personalKeySaved = !CredentialVault.readPersonalKey().isEmpty
            }
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
