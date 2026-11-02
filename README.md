# マイラジオ (MY RADIO) — 個人設定強化版 v0.2.0

## 今回の改修

- 興味分野（複数）を登録し、各分野ごとに「少し / 好き / 最優先」を選択できます。
- 分野ごとに、聞きたい話題や具体的な好みを自由入力できます。
- リストにない自由テーマも追加・優先度設定ができます。
- 好きな人物・作品、聴く目的、説明の深さ、番組時間、ニュース有無、聞きたくない話題を設定できます。
- ラジオ画面に「あなたの番組設計」を表示。重要度の高い話題が先に表示され、メモや条件も確認できます。
- **個人設定画面 →「設定を反映した番組を表示」→「ラジオ」→「再生」** で、個人設定が反映された短い音声と原稿を確認できます。
- 個人設定はiPhone内に自動保存されます。旧v0.1.0の保存データは引き継ぐように設計しました。
- AIサーバー側にも新しい優先度・具体的テーマ・希望・ニュース有無を渡すよう変更しました。

## 重要：何が実際に動くか

- **AI未接続でも**: 個人設定の登録・端末保存、内容に合わせた番組設計のプレビュー、短いオフラインお試し原稿とiOS音声読み上げが動きます。
- **AIサーバー接続後**: backend/ をクラウドで運用し、APIキーなどを安全に設定すると、登録に応じた本物のAI長文番組を生成できます。クラウド環境は本ファイルだけでは自動的に用意されません。
- 本番10分間の放送、最新ニュースの自動取得、楽曲の組み込みは、サーバー接続など別の準備が必要です。
- 目覚ましは通知方式です。通知が鳴った時に10分間の番組を自動再生するものではありません。
- 音声はiPhone標準の日本語読み上げです。著作権がある音楽を勝手に組み込むことはしません。

## 上書き対象（GitHub）

既存のGitHubリポジトリ `shu39a-lang/MY-RADIO-IOS` の **main** ブランチへ、更新ZIPを解凍した中身をフォルダー構造ごと上書きします。

- `MyRadio/ContentView.swift`
- `MyRadio/RadioModels.swift`
- `MyRadio/RadioStore.swift`
- `MyRadio/ProgramService.swift`
- `MyRadio/PersonalizationEngine.swift`（新規）
- `MyRadioTests/PersonalizationTests.swift`（新規）
- `backend/server.js`, `backend/server.test.js`, `backend/package.json`
- `project.yml` (v0.2.0、iPhone専用。エラー90474対策を保持)

**codemagic.yamlは更新ZIPには含めていません**。過去に作成済みのApple署名・TestFlight自動送信設定を壊さず残します。

## いつもの4工程

1. GitHubアップロード: https://github.com/shu39a-lang/MY-RADIO-IOS/upload/main
2. GitHub Actions: https://github.com/shu39a-lang/MY-RADIO-IOS/actions （グリーン確認）
3. Codemagic: https://codemagic.io/apps （`MY-RADIO-IOS` / `main` / **`ios-testflight`** を選んで新規ビルド）
4. App Store Connect: https://appstoreconnect.apple.com/apps/6829430684/testflight （登録済みの「マイラジオ内部テスト」に新ビルドを追加）

**既存のApple App ID、証明書、プロファイル、内部テスターを再作成する必要はありません。**

## 検査

- Swiftファイルの構文検査：`swiftc -frontend -parse MyRadio/*.swift MyRadioTests/*.swift`
- 独立したFoundationのモデル/ロジックの型検査と実行確認：成功
- Node.js API単体テスト： `cd backend && npm test` 4件成功
- macOS/Xcode上での**v0.2.0実機ビルドは未実施**。GitHub Actions/Codemagic/TestFlightで確認してください。

## プライバシー

任意のプロフィール情報は端末に保存します。AIサーバーを登録した場合、番組生成のため、その情報がサーバーとAI提供元へ送信されます。秘密のAPIキーはiPhoneコードやGitHubに書き込まないでください。公開販売前には、ユーザー認証・課金・利用上限・プライバシーポリシーの整備が必要です。
