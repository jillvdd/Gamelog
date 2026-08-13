# マイゲームブック（我的游戏簿）

> [English](README.en.md) · **日本語** · [简体中文](README.md)

**macOS + iOS** 対応の個人アプリ。クリアしたゲームを記録できます：カバー画像、6 軸スコア、プレイごとのプラットフォーム / クリア日 / クリア度 / プレイ時間 / メモ、実物コレクション（エディション / 数量 / 写真）、さらに共有用画像の生成も。完全ローカル保存（SwiftData）、データはすべて自分のもの。

対応言語：**简体中文 / 日本語 / English**（設定で即時切り替え）。macOS と iOS はそれぞれローカルに独立保存し、JSON バックアップでデータを移行できます（AirDrop 対応）。

## 機能

- **ゲームライブラリ**：グリッド / リスト表示切替；名前 + 別名 + 多言語名で検索；プラットフォームで絞り込み；グループ管理（macOS サイドバー / iOS フィルターメニュー）、1 つのゲームを複数グループに入れられます；名前 / 発売日 / クリア日で並び替え。ライブラリ表示スコア = そのゲームの採点済みクリア記録の平均点の平均、0.1 に丸め；未採点は「未評価」表示。
- **ゲーム詳細**：レビュー（一言タイトル + 本文）、全クリア記録（編集 / 追加 / 削除）、6 軸カラーバーチャート；コレクターモード有効時は「所持」タブが追加。
- **6 軸スコア**：ゲームプレイ / デザイン / ストーリー / アート / ミュージック / パフォーマンス、1–10、0.1 刻みのスライダー。総合 = 6 軸の平均；最初のクリア記録では必須、以降はスキップ可能。
- **クリア記録**：プラットフォーム、クリア日（「なし」可）、クリア度（メインストーリー / 全サブクエスト / 全エンディング / 全コレクションプラチナ / マルチ周回 / スピードラン / カスタム）、プレイ時間（「なし」可）、メモ。
- **日付選択**：macOS は 3 連ホイール（年 / 月 / 日、閏日と月末の調整に対応）；iOS はシステムの日付ピッカー。
- **グループ**：作成 / 改名 / 削除；右クリック（macOS）またはメニュー（iOS）からゲームを追加；グループ統計とグループレビュー。
- **コレクターモード**（設定トグル）：詳細ページに「詳細 / 所持」のセグメント切替；各ゲームに複数のエディション（エディション名 + 数量 + 最大 6 枚の写真）を持てます；写真はシステムビューアで表示、バックアップに含まれます。
- **カバー画像**：端末から選択、または [SteamGridDB](https://www.steamgriddb.com) API で検索してダウンロード（設定で API Key が必要、入力中に自動検索）；**自動マッチカバー**を有効にすると、名前入力が約 0.6 秒止まった時点で最初の縦長ヒットを取得（既存カバーは上書きせず、失敗時は静かに無視）。iOS では画像追加時に「写真 / ファイル / 撮影」メニューが表示されます。
- **パーソナライズ**：ユーザー名（20 文字）、アバター（円形クロップ）、macOS アプリアイコン（角丸矩形クロップ）、自動マッチカバー、グループ毛ガラス非表示（macOS）、元画像保持の各トグル。カスタムアイコンは Dock に即反映され、再起動後も維持。
- **共有画像**：ゲーム 1 つ → 単体カード（縦 1080×1920 / 横 1920×1080）；複数選択 → 総合画像；グループ単位 → グループ共有カード（グループ内カバーグリッド + プラットフォーム分布）。ブランド透かし入り、言語対応、PNG 保存またはシステム共有シート。
- **統計 & ランキング**：クリア総数、ライブラリ平均点、プラットフォーム分布；平均点ランキング + 6 軸ランキング（各軸トップ 5 / 10）；「総合ランキング」ページで 7 つのランキングを切替、1 ページ最大 100 件でページング、プラットフォーム絞り込み。
- **バックアップ**：ライブラリ全体を 1 つの JSON に書き出し（カバーは base64 埋め込み）、ユーザー名 / アバター / アイコンも含めて一括復元可能、旧バージョンのバックアップにも互換；インポート時は確認ダイアログ。iOS は AirDrop / ファイル共有で転送できます。

## プラットフォーム

| プラットフォーム | 展開対象 | 備考 |
|---|---|---|
| macOS | 14.0+ | 全機能：サイドバー、コンテキストメニュー、ウィンドウツールバー、カスタム Dock アイコンなど |
| iOS | 18.0+（iPhone / iPad） | 下部 TabBar（ライブラリ / 統計 / 設定）；フィルターメニュー、画像追加メニュー、確認シートは iOS デザイン規範に準拠 |

## 環境要件

- macOS 14.0+；iOS 18.0+（iPhone / iPad）
- Xcode 16+（SwiftData / Swift マクロ対応；本プロジェクトは Xcode 27 beta で検証）

## ビルド & 実行

```bash
cd /Users/abc/Documents/gamelog_program

# macOS ビルド + 起動
xcodebuild -project GameLog.xcodeproj -scheme GameLog -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/GameLogDD build
open /tmp/GameLogDD/Build/Products/Debug/GameLog.app

# iOS シミュレータ ビルド + インストール + 起動
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -project GameLog.xcodeproj -scheme GameLog-iOS -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /tmp/GameLogDD build
xcrun simctl install booted /tmp/GameLogDD/Build/Products/Debug-iphonesimulator/GameLog.app
xcrun simctl launch booted com.abcleg.GameLog
```

または Xcode で `GameLog.xcodeproj` を開き、`GameLog`（macOS）または `GameLog-iOS`（iOS）スキームで Run します。

## SteamGridDB カバー検索

1. [steamgriddb.com](https://www.steamgriddb.com) で無料登録し、プロフィールページから API Key を取得。
2. アプリの設定 → SteamGridDB に Key を入力。
3. ゲーム作成 / 編集時に「カバーを検索…」をタップ。

## プロジェクト構成

```
GameLog/
├── GameLogApp.swift       # macOS エントリ：WindowGroup + Settings シーンが ModelContainer を共有
├── iOSRootView.swift      # iOS エントリ：下部 TabBar（ライブラリ / 統計 / 設定）+ AirDrop バックアップ取込
├── Models/                # SwiftData モデル（Game / Completion / GameGroup / PhysicalCopy / Presets）
├── Support/               # プラットフォーム抽象 PlatformImage、スコア計算、バックアップ、個人設定、L10n、
│                          #   SteamGridDB、PlatformConfirmDialog（ボトムアクションシート）、ImageSourcePicker
├── Share/                 # 共有カードビュー + ImageRenderer 出力パイプライン
├── Views/                 # 各プラットフォームのビュー（共有 + #if os 適応）
└── Resources/             # 3 言語 Localizable.strings + Assets.xcassets（macOS/iOS AppIcon）+ Info-iOS.plist
Scripts/                   # 独立リグレッションテスト（アプリには組み込まない、下記参照）
```

## 開発検証

`Scripts/` に再実行可能な独立リグレッションテストがあります（`xcrun swiftc` でコンパイル、マクロプラグインのパスは各ファイルの冒頭コメント参照）：

- `Scripts/ScoreMathSelftest/` — スコア計算のセルフテスト（丸め / 平均 / ライブラリ表示スコア）
- `Scripts/DataSmokeTest/` — データ層スモーク：多対多、カスケード削除、採点統合、バックアップ往復、インポート冪等性と置換、所持記録バックアップ、日付の忠実性、プリセットのローカライズ
- `Scripts/ShareRenderTest/` — 共有カード描画パイプライン：ImageRenderer で実際に PNG を出力し画素サイズを検証

UI 文言を追加するときは、key を 3 つの `Localizable.strings` すべてに追加し、`L10n.tr` / `LText` を使います（`String(localized:)` は不可）。変更後は key 網羅チェックを実行し、3 言語すべて 0 欠落にすること（コマンドは HANDOVER.md §2）。

## 用語

領域用語（Game / Completion / Group / Review / Dimension Scores…）は `CONTEXT.md` の用語集に従います。

## ライセンス

[MIT](LICENSE) ライセンスで公開しています。リポジトリ直下の `LICENSE` を参照してください。
