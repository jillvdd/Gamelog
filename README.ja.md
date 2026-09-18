# My Gamelog（私のゲームログ）

<p align="center">
  <img src="appcover.PNG" alt="My Gamelog Cover" width="100%" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" />
</p>

<p align="center">
  <strong>ゲームプレイヤーのために設計された、洗練された個人用ゲームライブラリ＆クリア記録管理アプリ</strong>
  <br />
  完全ローカル保存 · ネイティブ体験 · パッケージ版コレクション管理 · 外部アカウント同期 · 美麗なシェアカード
</p>

<p align="center">
  <a href="README.en.md">English</a> · <strong>日本語</strong> · <a href="README.md">简体中文</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B%20%7C%20iOS%2018.0%2B-blue?style=flat-square" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-5.10%20%2F%206.0-orange?style=flat-square" alt="Swift" />
  <img src="https://img.shields.io/badge/SwiftUI-SwiftData-purple?style=flat-square" alt="SwiftUI + SwiftData" />
  <img src="https://img.shields.io/badge/Version-beta%203.2-amber?style=flat-square" alt="Version" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License" />
</p>

---

## 🌟 主な機能

### 🎮 ゲームライブラリと快適なブラウジング
- **高機能検索と絞り込み**：原題、多言語タイトル、独自の別名によるリアルタイム検索。ステータス、プラットフォーム、グループによる多面的な絞り込みに対応。
- **多彩な並び替え**：タイトル名、発売日、クリア日、スコア順、**最近編集した順**、**コレクション価値順**で自在にソート。
- **ホームカルーセル（5 つの特集ページ）**：
  1. **パーソナライズバナー**：カスタムタイトル、モットー、背景アート、アバターを表示；
  2. **ランダムピックアップ**：全ライブラリからランダムに 1 本を横長カバーで紹介。再抽選もワンタップ；
  3. **お気に入り**：大切な作品をトップに特写表示；
  4. **ライブラリ概要**：クリア総数、平均スコア、6 つのステータス分布を可視化；
  5. **コレクター概要**：所持エディション数、総本数、総支出、現在推定価値を一目で確認。
- **選べる表示モード**：標準ポスターグリッド、コンパクトリスト、**スクエアカバーグリッド**、**ミニマル表示（純粋カバー表示）**に対応。

### 🏆 クリア記録と多角的スコア評価
- **6 つのステータス管理**：プレイ予定、プレイ中、中断、プレイ中止、クリア済み、長期プレイをシームレスに切り替え。
- **詳細なクリア記録**：周回ごとにプラットフォーム、クリア日、クリア度（メインストーリー、全エンディング、トロフィー/実績コンプリート、タイムアタック等）、プレイ時間、感想ノートを独立記録。
- **項目別スコア評価**：ゲーム性、デザイン、ストーリー、アート、音楽、パフォーマンスの 6 項目を 0.1 刻みで精密採点。総合平均スコアとカラーバーチャートを自動生成。
- **Markdown 長文レビュー**：一言キャッチコピー（タグライン）と本格的なマークダウン記事作成に対応。macOS 版には独立した専用エディタ「書き机」を搭載。

### 🔗 外部ゲームアカウント連携（実験的機能）
- **主要 3 大プラットフォーム対応**：**Nintendo Account**、**PlayStation Network**、**Xbox Live** の連携をサポート。
- **公式プレイ履歴の自動取得**：任天堂の初回/最近プレイ日とプレイ時間、PlayStation のトロフィー進捗（プラチナ/金/銀/铜）、Xbox の実績数とゲーマースコアを自動取得。
- **スマートな照合と統合**：取り込んだ記録をローカルライブラリと自動マッチング。手動関連付けや重複ゲームの統合、除外ルールにも対応。
- **詳細画面の記録カード**：ゲーム詳細ページに公式記録カード（トロフィーカード、実績カード、プレイ記録カード）を表示。

### 📦 パッケージ版コレクション管理（コレクターモード）
- **現物派プレイヤー専用設計**：詳細ページで「所持品」アーカイブを有効化。パッケージソフト、限定版、レトロゲームの収集記録に特化。
- **充実のメタデータ**：メディア形態（パッケージ通常版、限定版、スチールブック、DLコード封入等）、発売地域（日本版 CERO、北米版 ESRB、欧州版 PEGI 等）、コンディション、入手経路、購入価格、現在の推定価値を細かく記録。
- **実物フォトギャラリー**：コレクションごとに実物写真を複数枚保存可能。いつでも開封写真やパッケージを鑑賞。
- **資産価値の自動集計**：所持エディション総数、総投資額、コレクション総資産価値を自動計算。

### 🎨 洗練されたシェアカード生成
- **ダークエレガンスなビジュアル**：温かみのあるブラックを基調に、琥珀色のアクセントを効かせた高級感あふれるデザイン。
- **3 つのレイアウト**：
  - **個別ゲームカード**：映画ポスターのような構図。カバーブラー背景、クリア度バッジ、金色のタグライン、項目別バーを融合；
  - **総合概要画像**：本数に応じて列数を自動調整。表示項目や並び順を自由にカスタマイズ可能；
  - **グループ・シリーズカード**：シリーズ作品や特集向け。グループレビュー、平均スコア、プラットフォーム分布、カバー一覧を美しく凝縮。
- **自在な書き出し**：スマートフォン向け（9:16）とデスクトップ向け（16:9）に対応。JPEG / 高品質 PNG 書き出し、iOS では写真アプリへ直接保存可能。

### 🛡️ プライバシー重視の完全ローカル設計
- **外部サーバー不使用**：専用アカウント作成やクラウド送信は一切ありません。すべてのデータは SwiftData により端末内にのみ安全に保存されます。
- **キーチェーンによる安全保護**：外部サービスの認証トークンや API キーは端末の Keychain にのみ暗号化保管され、データベースやバックアップ、ログには一切出力されません。
- **堅牢な自動バックアップ**：データ変更時にローカルへ自動でバックアップを作成。単一 JSON ファイルでの書き出し/読み込み、AirDrop による macOS・iOS 間のシームレスな移行に対応。

---

## 💻 プラットフォーム別ネイティブ体験

| プラットフォーム | 最低動作環境 | ネイティブならではの特徴 |
|---|---|---|
| **macOS** | macOS 14.0+ | 3 列サイドバー、右クリックメニュー、豊富なキーボードショートカット、専用 Markdown エディタ「書き机」、独立した「連携設定」ウィンドウ（⌘⇧,）、Dock アイコンの即時カスタマイズ。 |
| **iOS** | iOS 18.0+ | ネイティブな TabBar ナビゲーション、片手操作に適した 1 列ワイドカード、自然言語解析による美しい単語境界折り返し、カメラ/写真ライブラリからの即時取り込み。 |
| **iPadOS** | iPadOS 18.0+ | 2 列ワイドカード表示、画面回転に応じた分割レイアウト、大画面を活かした Hero 横長バナー表示。 |

---

## 🚀 クイックスタート & インストール

### 1. アプリのインストール

#### macOS
- Releases より `GameLog-beta-3.2.dmg` をダウンロードし、マウント後に `GameLog.app` を `Applications` フォルダへドラッグ＆ドロップしてください。

#### iOS / iPadOS（無署名 IPA）
- `dist/` フォルダにある `GameLog-beta-3.2.ipa`（実機 arm64 用バイナリ）を取得します。
- TrollStore、eSign、AltStore、SideStore 等のお好みのツールで再署名してインストールしてください。

### 2. デモデータのインポート
リポジトリには動作確認用の公式デモデータ [GameLog-demo-backup.json](GameLog-demo-backup.json) が付属しています。50 本の名作タイトル（多言語対応）、105 件のクリア記録、項目別スコア、9 つのグループが収録されています。

- **インポート手順**：アプリを起動 → **「連携設定」**を開く（macOS ショートカット `⌘⇧,`、iOS は下部「連携」タブ）→ **データバックアップ** → **バックアップを読み込む…** → JSON ファイルを選択。

### 3. SteamGridDB カバー検索の設定
1. [steamgriddb.com](https://www.steamgriddb.com) に無料登録し、プロフィールから API Key を取得します。
2. アプリ内の**「連携設定」** → **SteamGridDB** → API Key を入力（自動検証機能付き）。
3. ゲームの追加や編集時に**「検索…」**ボタンを押すだけで、縦長ポスター、スクエア画像、横長バナー、透過ロゴをワンタップで検索・設定できます。

---

## 🛠️ 開発者向けガイド

### 開発環境
- **macOS 14.0+** / **iOS 18.0+**
- **Xcode 27 beta**（macOS 27 / iOS 27 SDK が必要）

### ビルドコマンド

```bash
cd /Users/abc/Documents/gamelog_program

# Xcode beta の開発パスを設定
export DEVELOPER_DIR=/Users/abc/Downloads/Xcode-beta.app/Contents/Developer

# ① macOS Debug ビルド
xcodebuild -project GameLog.xcodeproj -scheme GameLog -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/GameLogDD-mac build

# ② iOS Simulator Debug ビルド
xcodebuild -project GameLog.xcodeproj -scheme GameLog-iOS -configuration Debug \
  -destination 'id=9908C070-47ED-455C-8427-4ED9177591B4' -derivedDataPath /tmp/GameLogDD-ios build
```

### オフライン回帰テスト
`Scripts/` 配下にオフラインで実行可能な独立テストスイートが用意されています：

- `Scripts/ScoreMathSelftest/`：スコア算出、端数処理、ライブラリ平均の検証（16 テスト）。
- `Scripts/DataSmokeTest/`：SwiftData モデル、リレーション、外部連携取り込み、バックアップ整合性の検証（753 テスト）。
- `Scripts/KeychainSelftest/`：Keychain の安全性と連携解除時の完全消去の検証（17 テスト）。
- `Scripts/ShareRenderTest/`：ImageRenderer による画像生成サイズとレイアウト検証（25 テスト）。
- `Scripts/RichReviewTest/`：Markdown とリッチテキストエディタ間の双方向変換検証。

---

## 📖 用語の定義

本プロジェクトでは [CONTEXT.md](CONTEXT.md) にて統一されたドメイン用語（Game、Alias、Completion、Dimension Scores、Cover、Review 等）を定めています。開発時はこちらの定義に準拠してください。

---

## 📄 ライセンス

本プロジェクトは [MIT License](LICENSE) のもとで公開されています。
