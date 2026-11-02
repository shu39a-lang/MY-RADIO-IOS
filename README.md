# MY RADIO — 自分専用の実際のAIラジオ（v0.3.0）

これは**実際のAIによる番組制作と、高音質AI音声の取得・再生を行う**iPhoneアプリ一式です。前版の試聴用・端末標準のロボット読み上げを、本番の再生経路から外しました。

## 実装済みの機能

- 好みの登録：16カテゴリ＋自分だけの追加カテゴリ、優先度（少し／好き／最優先）、カテゴリごとの詳細、年齢層・性別（任意）、地域、好きな人物・作品、聞きたくない内容、ラジオの目的、説明の深さ、5・10・20分設定。端末に自動保存。
- 入力の優先度・具体的な希望から **AIがその都度新しい番組原稿を生成**し、タイトル・原稿・情報源を表示。過去の番組タイトルを避ける編集ロジックも搭載。
- **10種類の声**：男性系4、女性系4、中性的2。声を選択し、その声の実際のAI音声を取得して試聴。声の印象は目安なので日本語の実際の出力を聴いて選択。
- iPhone標準の `AVSpeechSynthesizer` の代わりに **音声生成APIが返す実際のMP3** を再生。長文は安全な長さで分割し、バックグラウンド再生に対応。原稿と音声は端末に保持（音声ファイルは端末のキャッシュ）。
- 個人用・実機テスト向けには **ユーザー本人の OpenAI API キーを Keychain に一度登録**するだけで、別サーバーを構築せず番組制作と音声生成ができる。
- 将来の一般販売向けには `backend/` に **OpenAIの番組生成＋音声配信サーバー** を同梱。さらに、より人間らしい日本語の声を選べるように **ElevenLabs v4** をサーバー側で選択可能。
- 朝の通知は従来どおり。iPhoneがロック中の完全自動10分再生は未実装（目覚まし時計の代用にはしない）。

## まず実際の声で聴くための最短手順（個人用）

1. このリポジトリをGitHubに更新し、既存の **Codemagic → `ios-testflight`** でApp Store Connectへビルドを送る。既存の Bundle ID `jp.myradio.personal` とApple登録・証明書を変えない。
2. iPhoneの TestFlight から v0.3.0 をインストールする。
3. OpenAIの開発者ページ <https://platform.openai.com/api-keys> から**自分専用のAPIキー**を取得（必要に応じてAPI課金を設定。ChatGPT Plus/Proとは別料金）。**APIキーをGitHub・チャットに貼り付けない**。
4. アプリの「AI接続」→「個人用AIラジオ」で自分のキーを登録。「AI番組」タブで好きなことを詳しく登録→声を選び「実際に試聴」→「この設定でAI番組を制作」→「AI音声で再生」。この方式ではサーバーURLを**空欄**にする。

この方式は持ち主一人での実機使用を想定。キーは本人の端末の Keychain に保存され、実際の番組制作・音声化時に OpenAI API へ直接送信されます。公開販売用アプリには、ユーザー認証と利用上限・課金を備えた専用サーバーを使用してください。

## 選択できる音声

| グループ | 声ID |
|---|---|
| 男性系の印象 | `cedar`, `onyx`, `echo`, `ash` |
| 女性系の印象 | `marin`, `coral`, `nova`, `shimmer` |
| 中性的な印象 | `sage`, `alloy` |

声の男性・女性の区分は主観的な聴感上の案内です。自然さ、抑揚、発音は音声モデル・言語・原稿に依存するため **「人間と100％同じ」は保証できません**。選択した声は実際の音声を聴いて評価してください。AI音声であることをアプリに明示しています。

## 一般販売のためのバックエンド

`backend/server.js` と `backend/voice.js` は Node.js 22 のAPI（`/health`, `/api/program`, `/api/speech`）で、`backend/Dockerfile` から Google Cloud Run などへデプロイできます。OpenAI / ElevenLabs APIキーは必ず**サーバーのSecret Manager**に設定してください。

必須の環境変数：
- `OPENAI_API_KEY` — AIが原稿を生成するキー。
- `MYRADIO_ACCESS_TOKEN` — 個人テスト時のサーバー接続トークン（アプリ内「AI接続」にも入力）。一般販売前にユーザー別認証へ変更。
- `VOICE_PROVIDER` — `openai`（標準）か `elevenlabs`（高品位・有料音声）。
- `OPENAI_TTS_MODEL` — OpenAI Speech API 利用時。v0.3.0 の標準は `gpt-4o-mini-tts`。
- `ELEVENLABS_API_KEY`, `ELEVENLABS_MODEL=eleven_v4`, `ELEVENLABS_VOICE_MAP` — ElevenLabs利用時。`ELEVENLABS_VOICE_MAP` にはアプリの10個の声IDと、ご自身が利用権を持つ日本語対応の声IDの対応をJSONで設定する。未設定の声は使えない。

`GET /health` で `aiConfigured: true` を確認してから、iPhoneの「AI接続」にCloud Runの **HTTPS URL** と接続トークンを登録する。このときiPhoneの個人用APIキーは不要。

⚠️ **重要**：OpenAIの `gpt-4o-mini-tts` など従来の Speech API 音声モデルは **2027年1月6日に提供終了予定**。長期運営する場合は `gpt-realtime-2.1-mini` への実装移行、またはこのリポジトリで用意した ElevenLabs v4 を採用してください。短期の個人実機用としては現在のSpeech APIを使用します。

⚠️ **商用リリース前**：利用者ごとの認証、鍵の非公開、サーバー側の利用上限・請求制限、履歴/音声の保存規約、プライバシーポリシー、Appleのアプリ内課金、法的な音声利用権の確認が必要です。ElevenLabs商用音声には利用権を満たす有料プラン等が必要です。ニュース・投資・健康情報はAIの誤りがあり得ます。

## ビルド・検査

- `swiftc -frontend -parse MyRadio/*.swift MyRadioTests/*.swift` （Swiftソース構文検査）
- `swiftc -typecheck MyRadio/RadioModels.swift MyRadio/PersonalizationEngine.swift MyRadio/VoiceCatalog.swift`（モデル構造）
- `cd backend && npm test`（プロフィール、音声バリデーション、実際のAPIリクエスト形式、HTTPサーバー統合テスト）
- Xcode/Codemagicで `xcodegen generate` してiOS用ビルド。**この場では実機ビルドと実際のAPIキーによる音声品質試聴は行えていません。**

既存のアプリID、GitHub Actions、Codemagic署名設定と内部テストグループを変更しません。本人が登録したデータを消さないよう、v0.1/v0.2のデータ復元コードを残しています。アプリ内の保存音声はキャッシュのため、iOSの判断で削除される場合があり、その際はAPIから再生成します（費用が発生）。
