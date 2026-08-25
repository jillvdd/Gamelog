# My Gamelog (我的游戏簿)

> **English** · [日本語](README.ja.md) · [简体中文](README.md)

A **macOS + iOS** personal app for recording your game library and completion history: statuses (backlog / playing / completed…), cover art, six-dimension scores, per-playthrough platform / date / degree / playtime / notes, physical collections (edition / quantity / photos), and shareable images. Fully local storage (SwiftData) — your data belongs entirely to you.

Interface languages: **简体中文 / 日本語 / English** (switch instantly in Settings). macOS and iOS each store data locally and independently; you can move data between them via JSON backup (including AirDrop).

## Features

- **Game Library**: grid / list view toggle; search by name + aliases + localized names; filter by status / platform / group; group management (macOS sidebar / iOS filter menu), a game can belong to several groups; sort by name / release date / completion date / average score (low to high or high to low) / **recently edited** / **highest value**, defaulting to "recently edited". The library score is the mean of the record averages of all scored completions, rounded to 0.1; unscored games show "Unrated".
- **Game Status**: six statuses — Backlog / Playing / Paused / Dropped / Completed / Long-Running. Lightweight states need no completion records or scores; records attach when a game moves to Completed or Long-Running. Filter the library by status, pick via a liquid-glass slider on the detail page; non-completed games still carry a game-level platform and join platform filters and stats.
- **Game Detail**: review area (one-line tagline intro + long-form body), all completions (edit / append / delete), six-dimension colored bar chart; an extra "Holdings" tab when Collector Mode is on.
- **Review (Markdown long-form)**: the one-line verdict (tagline) renders as a large lead-in "thesis"; the review body supports a Markdown subset (headings `#` / bold `**` / italic `*` / lists `-`) like a well-set article. **macOS = WYSIWYG rich-text editor** (a dedicated "writing desk" window; the toolbar applies styles directly, saved back to Markdown; CJK italics are synthesized with a shear at draw time); **iOS = editing sheet (TextEditor)**. Per-platform editing shares one Markdown renderer, so both platforms look consistent.
- **Six-Dimension Scoring**: Gameplay / Design / Story / Art / Music / Performance, 1–10 sliders with 0.1 steps. Overall = mean of the six; the first completion requires scores, later ones may be skipped.
- **Completions**: platform, completion date (can be "None"), completion degree (main story / all side quests / all endings / platinum / multiple playthroughs / speedrun / custom), playtime (can be "None"), and notes.
- **Date Picker**: macOS three-column wheel (year / month / day, handles Feb 29 and month-end clamping); iOS uses the system date picker.
- **Groups**: create / rename / delete; pick games to join via context menu (macOS) or menu (iOS); per-group stats and review (rendered as Markdown; editable in the writing desk on macOS).
- **Collector Mode** (Settings toggle): "Details / Holdings" segmented switch on the detail page; each game can have multiple holdings (11 media types / 10 regions / 7 conditions / 11 acquisition sources / per-language price & estimated value / purchase date / notes + up to 6 photos), forming a **collection archive**. New games do **not** get a holding by default — you must toggle "I own this (create holding)" to expand the fields and build the archive. The Holdings view offers grid / list layouts, a top overview (edition count / total quantity / total spent / total estimated value), capsule-style metadata, and a full edit sheet; photos open in the system viewer; included in backups.
- **Cover Art**: import from your device, or search & download via the [SteamGridDB](https://www.steamgriddb.com) API (requires an API Key in Settings, searches as you type); optional **auto-match cover** (about 0.6s after you stop typing, picks the first portrait hit — never overwrites an existing cover, silent on failure). Search results show cover thumbnails. On iOS, adding an image pops a "Photos / Files / Camera" menu.
- **Personalization**: username (20 chars), avatar (circular crop), macOS app icon (rounded-square crop), auto-match cover toggle, hide top frosted glass (macOS 15+), keep-original-images toggle, platform-logos toggle (on by default; turning it off hides brand logos in platform pickers / grouping views). A custom icon reflects on the Dock immediately and persists across restarts.
- **Share Images (fully reworked in beta 2.4)**: a branded, fixed dark look — warm near-black background with an amber accent, no longer following the system appearance. Three card types:
  - **Single card**: blurred cover backdrop + a crisp poster filling its frame (matched to the cover's true aspect ratio — no letterboxing for SteamGridDB 2:3 portraits); the info panel carries the game name / platforms / release year / completion-degree pill / one-line verdict (gold) / six mini dimension bars / a large library score; non-completed games show a colored status badge instead.
  - **Overview image**: the header summary line and per-game tile fields are both configurable and reorderable in "Style Settings" (summary: game count / average score / total completions / collection value; tiles: platform / score / latest completion / release year / status label); column count adapts to the number of games and the canvas grows with content.
  - **Group card**: title + one-line group-review quote + stat items (average / game count / completions / top game / collection value, toggleable and reorderable) + platform distribution bars + in-group cover grid; separate phone / desktop layouts.
  - "Style Settings" configures all three pools in one place; overview tiles and group tiles share one field configuration. Export as JPEG (default) or PNG with the game / group name in the file name; on iOS, tap the preview for fullscreen and save straight to the Photos album (requires add-photo permission). The watermark (username's gamelog + avatar) is localized per language.
- **Stats & Rankings**: total completions, library average (plus backlog count), platform distribution, and collection value (when Collector Mode is on: edition count / total quantity / total spent / total estimated value); average-score leaderboard + six-dimension boards (top 5 / 10 per dimension); the "Overall Ranking" page switches between **Score Boards** and **Value Boards** at the top — Score Boards hold 7 boards (average + six dimensions), Value Boards hold three pages (by game value / by platform (machine) value / by group value), each paging up to 100 entries and filterable by platform.
- **Backup**: export the whole library to a single JSON (covers embedded as base64), including username / avatar / icon, restorable as a whole, compatible with older backups; import asks for confirmation. On iOS, export uses the system share sheet (AirDrop / Save to Files, etc.) with a timestamped file name.
- **Auto Backup**: automatically writes a full local backup (one rolling file) whenever your data changes; keeps a snapshot of the old version before upgrades; if the library is empty but a backup exists, asks on launch whether to restore; snapshots before restore / import so you can undo. On iOS, backups live in Documents/Backups (visible in the Files app), so you can still grab them if the app can't launch (e.g. expired signing cert).
- **Clear Cache**: Settings → Storage & Cache shows current cache usage and clears it with one tap (cover/image decode caches, network cache, temp files) — never touches your game data or backups.

## Platforms

| Platform | Deployment target | Notes |
|---|---|---|
| macOS | 14.0+ | Full features: sidebar, context menus, window toolbar, custom Dock icon, the writing-desk review editor, etc. |
| iOS | 18.0+ (iPhone / iPad) | Bottom TabBar (Library / Stats / Settings); filter menu, add-image menu, bottom action-sheet confirmations follow iOS design conventions |

## Requirements

- macOS 14.0+; iOS 18.0+ (iPhone / iPad)
- **Xcode 27 beta** (the project requires the macOS 27 / iOS 27 SDK and simulator runtime — build with `/Users/abc/Downloads/Xcode-beta.app`)

## Build & Run

```bash
cd /Users/abc/Documents/gamelog_program

# macOS build + launch (macOS 27 beta requires the beta Xcode)
DEVELOPER_DIR=/Users/abc/Downloads/Xcode-beta.app/Contents/Developer \
xcodebuild -project GameLog.xcodeproj -scheme GameLog -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/GameLogDD-mac build
open /tmp/GameLogDD-mac/Build/Products/Debug/GameLog.app

# iOS simulator build + install + launch
DEVELOPER_DIR=/Users/abc/Downloads/Xcode-beta.app/Contents/Developer \
xcodebuild -project GameLog.xcodeproj -scheme GameLog-iOS -configuration Debug \
  -destination 'platform=iOS Simulator' -derivedDataPath /tmp/GameLogDD-ios build
xcrun simctl install booted /tmp/GameLogDD-ios/Build/Products/Debug-iphonesimulator/GameLog.app
xcrun simctl launch booted com.abcleg.GameLog
```

Or open `GameLog.xcodeproj` in Xcode and Run the `GameLog` (macOS) or `GameLog-iOS` (iOS) scheme.

## Installing on iPhone (IPA)

The repository provides two Release IPAs under `dist/`, both unsigned — sign them yourself before installing:

- `GameLog-beta-2.5.ipa` — simulator universal slice (x86_64 + arm64)
- `GameLog-beta-2.5-device.ipa` — device arm64 slice (unsigned), suited for re-signing with eSign or similar tools

> Tip: for simulator or daily development debugging, just Run from Xcode — no IPA needed.

## Try the Demo Data

The repository includes a generated demo dataset ([GameLog-demo-backup.json](GameLog-demo-backup.json)) for demonstrating this app's features: 50 games (Chinese / English / Japanese names + release dates), 105 completions (platforms spread across Nintendo Switch 2 / PS5 / Xbox Series X|S / PC, with backward-compatibility traces), six-dimension scores, and 9 groups.

To import:

1. iOS: put the JSON into the Files app; macOS: place it locally
2. Open the app → Settings → Backup → **Import** → pick the file → Confirm

Note: importing replaces the current data.

## SteamGridDB Cover Search

1. Register for free at [steamgriddb.com](https://www.steamgriddb.com) and get an API Key from your profile page.
2. Open Settings → SteamGridDB → enter the Key. The key field supports show/hide, copy, and auto-validation on change (✓ valid / ✗ invalid).
3. When creating / editing a game, tap "Search Cover…".

## Project Structure

```
GameLog/
├── GameLogApp.swift       # macOS entry: WindowGroup + Settings/About/writing-desk scenes share one ModelContainer
├── iOSRootView.swift      # iOS entry: bottom TabBar (Library / Stats / Settings) + AirDrop backup import
├── Models/                # SwiftData models (Game / Completion / GameGroup / PhysicalCopy / Presets)
├── Support/               # PlatformImage abstraction, ScoreMath, ExportImport/AutoBackup, UserCustomization, L10n,
│                          #   SteamGridDB, PriceFormat, PlatformIcon (platform logos), PlatformButton,
│                          #   PlatformConfirmDialog (bottom action sheet), ImageSourcePicker,
│                          #   DocumentPicker (iOS file picking), ShareSheetPresenter (iOS share sheet),
│                          #   MarkdownReview (parse/render), MarkdownRichEditor (macOS writing desk)
├── Share/                 # Share card views (three card types + style pools) + ImageRenderer output pipeline
├── Views/                 # Platform views (shared + #if os adaptations)
└── Resources/             # Tri-lingual Localizable.strings + Assets.xcassets (macOS/iOS AppIcon) + Info-iOS.plist + PlatformIcons (platform logo assets)
Scripts/                   # Standalone regression tests (not compiled into the app, see below)
```

## Development Verification

`Scripts/` holds repeatable standalone regression tests (compiled with `xcrun swiftc`; the macro-plugin path is in each file's header comment):

- `Scripts/ScoreMathSelftest/` — score logic self-test (rounding / means / library score)
- `Scripts/DataSmokeTest/` — data-layer smoke tests: many-to-many, cascade delete, scoring integration, backup round-trip, import idempotence & replace, collection-archive migration & backup, date fidelity, preset localization
- `Scripts/ShareRenderTest/` — share card render pipeline: actually calls ImageRenderer to produce PNGs, validating sizes / column counts / JPEG encoding / style-pool round-trips
- `Scripts/RichReviewTest/` — review editor core invariant: Markdown → rich text → Markdown round-trip is character-exact

When adding UI copy, the key must go into all three `Localizable.strings` and use `L10n.tr` / `LText` (not `String(localized:)`). After changes, run the key-coverage check — all three languages must have 0 missing (the command is in HANDOVER.md §2).

## Terminology

Domain terms (Game / Completion / Group / Review / Dimension Scores…) follow the glossary in `CONTEXT.md`.

## License

Released under the [MIT](LICENSE) license. See `LICENSE` in the repository root.
