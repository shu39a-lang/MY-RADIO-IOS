# MY RADIO（マイラジオ）— iPhoneアプリ初期版 v0.1.0

「世界にひとつ、自分専用のAIラジオ」を目指す、実装済みのiOS試作プロジェクトです。

## 初期版で使えること
- **好みの登録**：興味ジャンル複数選択、具体的な趣味の自由入力、避けたいテーマ、地域・年齢層・性別（いずれも任意）、話し方、5/10/20分設定。
- **お試し番組**：AI接続前でも、入力した好みに応じた短いデモ原稿を端末の音声合成で読み上げ。
- **AI番組生成**：別途サーバーに接続すると、最新情報をウェブ検索し、関心に合わせた長い日本語番組原稿を生成。情報源をアプリ上に表示。
- **音声プレーヤー**：AVSpeechSynthesizerで再生、一時停止、再開、停止。音声を生成するAI音声モデルは未使用で、iOS標準の音声合成を使用。
- **朝の通知**：時刻を登録すると、通知音と案内を毎朝表示。通知タップ後、アプリ内で再生。
- **保存**：設定と最後の番組はiPhone内に保存（UserDefaults）。試作用のサーバー接続トークンはKeychainに保存。
- **データ削除**：保存した好み・番組・接続設定を初期化。

## 重要な制約
- 現時点では**バックグラウンドから番組を10分間全自動再生する目覚まし機能はありません**。iOS通知を利用しています。時計アプリのアラームの代用にはしないでください。
- AIサーバーのURLが空のときは**短いお試し原稿**のみ。ニュースを生成するわけではありません。
- AIサーバーは実装済みですが、**OpenAI APIキーが未設定で、クラウドへのデプロイもまだ行っていません**。AI生成は接続後に動作します。
- 10分/20分はAIへの原稿文字数目標です。端末の読み上げ速度で実際の再生時間が変動します。
- 番組原稿は音声ファイルとして保存していません。AIによる自然なナレーションや音楽挿入は後の段階です。
- AIニュースの正確性を100%保証できません。URL出典を確認してください。
- 既存アプリとは完全に別のバンドルIDです。**公開前に固有のバンドルIDへ変更**してください。

## Macで開く（Xcode）
1. MacにXcode 16以上と[Homebrew](https://brew.sh/)を用意。
2. ターミナルで `brew install xcodegen` を一度実行。
3. このフォルダーで `xcodegen generate` を実行すると `MyRadio.xcodeproj` が作成されます。
4. Xcodeで `MyRadio.xcodeproj` を開き、Signing & Capabilitiesで自分のApple Developer Teamと固有のBundle Identifierを選択。
5. 実機またはシミュレーターで Run を実行。

## GitHub Actions / Codemagic
- `.github/workflows/ios-check.yml` はXcodeGenをインストールし、コード署名なしのiOSシミュレータービルドを検査します。
- `codemagic.yaml` の `ios-compile-check` は署名なしでコンパイル検査可能。
- `codemagic.yaml` の `ios-testflight` は**Apple Developerの署名証明書、プロビジョニングプロファイル、App Store Connectで作成したアプリ**が必要。署名前にBundle IDを変更してください。
- 現時点ではGitHub、Codemagic、App Store Connectへの公開・ビルド・審査申請は実行していません。

## AI番組生成サーバー
`backend/` はNode.js 20以上で起動可能なAPIです。Cloud RunのDockerfileを同梱。

### ローカル（開発者向け）
```bash
cd backend
export OPENAI_API_KEY='（サーバー側の秘密鍵）'
export MYRADIO_ACCESS_TOKEN='（長いランダムな試作用トークン）'
node server.js
```
- `GET /health` はヘルスチェック。
- `POST /api/program` はBearer認証必須。入力された趣味・除外項目・直近番組などを基にOpenAI Responses APIとweb_searchで原稿生成。
- iPhoneアプリの「AI接続」には **HTTPSのサーバーURL** を入力。ローカルのhttp://接続は許可しません。
- OpenAIキーは**絶対にiOSコードやGitHubへ記録しない**でください。

### Cloud Runデプロイに向けて
1. Google Cloudでサービスの権限・API・請求先を準備。
2. Secret Managerに `OPENAI_API_KEY` と `MYRADIO_ACCESS_TOKEN` を登録し、Cloud Runのサービスアカウントにアクセス権を付与。
3. `backend/` のDockerfileを使ってCloud Runサービスを作成し、環境変数を設定。
4. サービスのHTTPS URLをiPhoneの「AI接続」に登録。

**警告：これは個人試作専用の共有トークン式です。一般販売前にはFirebase Authentication等のユーザー認証、App Check、ユーザー別の回数制限、課金連動、プライバシーポリシー、保存期間・削除への対応が必要です。**

## 品質検証
- `swiftc -frontend -parse MyRadio/*.swift MyRadioTests/*.swift` によるSwiftソースの構文検査。
- `cd backend && npm test` によるAPI単体試験。
- macOS/Xcode/iPhoneでの実機ビルド・実再生テストは未実施。署名済みIPAの作成は未実施。

## 次に実装したい機能
1. Cloud Run接続と実際のAI番組生成の確認。
2. 長さの推定・調整、長時間音声のプリ生成、BGM、オフライン番組保存。
3. AlarmKit（iOS 26以降）を利用できる環境での目覚ましとの連携検証。
4. Firebase認証、課金、クォータ・監視、プライバシー整備。
5. UIの動作確認、アクセシビリティ、TestFlight、App Store審査。

著作権保護のある楽曲は無断で組み込みません。
