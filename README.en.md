# My Gamelog (我的游戏簿)

> **English** · [日本語](README.ja.md) · [简体中文](README.md)

A **macOS + iOS** personal app for recording your game library and completion history: statuses (backlog / playing / completed…), cover art, six-dimension scores, per-playthrough platform / date / degree / playtime / notes, physical collections (edition / quantity / photos), and shareable images. Fully local storage (SwiftData) — your data belongs entirely to you.

Interface languages: **简体中文 / 日本語 / English** (switch instantly in Settings). macOS and iOS each store data locally and independently; you can move data between them via JSON backup (including AirDrop).

## Features

- **Game Library**: grid / list view toggle; search by name + aliases + localized names; filter by status / platform / group; group management (macOS sidebar / iOS filter menu), a game can belong to several groups; sort by name / release date / completion date / average score (low to high or high to low). The library score is the mean of the record averages of all scored completions, rounded to 0.1; unscored games show "Unrated".
- **Game Status** (beta 1.9): six statuses — Backlog / Playing / Paused / Dropped / Completed / Long-Running. Lightweight states need no completion records or scores; move to Completed to attach them. Filter the library by status, pick in the detail page; stats exclude non-completed games.
- **Game Detail**: review area (one-line tagline intro + long-form body), all completions (edit / append / delete), six-dimension colored bar chart; an extra "Holdings" tab when Collector Mode is on.
- **Review (Markdown long-form, beta 2.1)**: the one-line verdict (tagline) renders as a large lead-in "thesis"; the review body supports a Markdown subset (headings `#` / bold `**` / italic `*` / lists `-`) like a well-set article. **macOS = WYSIWYG rich-text editor** (a dedicated "writing desk" window; the toolbar applies styles directly, saved back to Markdown; CJK italics are synthesized with a shear at draw time); **iOS = editing sheet (TextEditor + preview)**. Per-platform editing share one Markdown renderer, so both platforms look consistent.
- **Six-Dimension Scoring**: Gameplay / Design / Story / Art / Music / Performance, 1–10 sliders with 0.1 steps. Overall = mean of the six; the first completion requires scores, later ones may be skipped.
- **Completions**: platform, completion date (can be "None"), completion degree (main story / all side quests / all endings / platinum / multiple playthroughs / speedrun / custom), playtime (can be "None"), and notes.
- **Date Picker**: macOS three-column wheel (year / month / day, handles Feb 29 and month-end clamping); iOS uses the system date picker.
- **Groups**: create / rename / delete; pick games to join via context menu (macOS) or menu (iOS); per-group stats and review.
- **Collector Mode** (Settings toggle): "Details / Holdings" segmented switch on the detail page; each game can have multiple physical editions (edition name + quantity + up to 6 photos); photos open in the system viewer; included in backups.
- **Cover Art**: import from your device, or search & download via the [SteamGridDB](https://www.steamgriddb.com) API (requires an API Key in Settings, searches as you type); optional **auto-match cover** (about 0.6s after you stop typing, picks the first portrait hit — never overwrites an existing cover, silent on failure). Search results show cover thumbnails. On iOS, adding an image pops a "Photos / Files / Camera" menu.
- **Personalization**: username (20 chars), avatar (circular crop), macOS app icon (rounded-square crop), auto-match cover toggle, hide top frosted glass (macOS 15+), keep-original-images toggle, platform-logos toggle (on by default; turning it off hides brand logos in platform pickers / grouping views). A custom icon reflects on the Dock immediately and persists across restarts.
- **Share Images**: single game → single card (portrait 1080×1920 or landscape 1920×1080); multi-select → one overview image; by group → a group share card (in-group cover grid + platform distribution). Branded watermark, localized per language, saveable as PNG or via the system share sheet; on iOS you can also save the image directly to the Photos album (requires add-photo permission).
- **Stats & Rankings**: total completions, library average, platform distribution; average-score leaderboard + six-dimension boards (top 5 / 10 per dimension); the "Overall Ranking" page switches between 7 boards, pages up to 100 entries per page, filters by platform.
- **Backup**: export the whole library to a single JSON (covers embedded as base64), including username / avatar / icon, restorable as a whole, compatible with older backups; import asks for confirmation. On iOS, export uses the system share sheet (AirDrop / Save to Files, etc.).
- **Auto Backup** (beta 2.0): automatically writes a full local backup (one rolling file) whenever your data changes; keeps a snapshot of the old version before upgrades; if the library is empty but a backup exists, asks on launch whether to restore; snapshots before restore / import so you can undo. On iOS, backups live in Documents/Backups (visible in the Files app), so you can still grab them if the app can't launch (e.g. expired signing cert).
- **Clear Cache** (beta 2.0): Settings → Storage & Cache shows current cache usage and clears it with one tap (cover/image decode caches, network cache, temp files) — never touches your game data or backups.

## Platforms

| Platform | Deployment target | Notes |
|---|---|---|
| macOS | 14.0+ | Full features: sidebar, context menus, window toolbar, custom Dock icon, etc. |
| iOS | 18.0+ (iPhone / iPad) | Bottom TabBar (Library / Stats / Settings); filter menu, add-image menu, confirmation sheets follow iOS design conventions |

## Requirements

- macOS 14.0+; iOS 18.0+ (iPhone / iPad)
- Xcode 16+ (SwiftData / Swift macros support; project verified with Xcode 27 beta)

## Build & Run

```bash
cd /Users/abc/Documents/gamelog_program

# macOS build + launch
xcodebuild -project GameLog.xcodeproj -scheme GameLog -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/GameLogDD build
open /tmp/GameLogDD/Build/Products/Debug/GameLog.app

# iOS simulator build + install + launch
export DEVELOPER_DIR=/Users/abc/Downloads/Xcode-beta.app/Contents/Developer
xcodebuild -project GameLog.xcodeproj -scheme GameLog-iOS -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/GameLogDD build
xcrun simctl install booted /tmp/GameLogDD/Build/Products/Debug-iphonesimulator/GameLog.app
xcrun simctl launch booted com.abcleg.GameLog
```

Or open `GameLog.xcodeproj` in Xcode and Run the `GameLog` (macOS) or `GameLog-iOS` (iOS) scheme.

## Installing on iPhone (IPA)

This repository provides a Release IPA (`dist/GameLog-beta-2.1.ipa`), unsigned — you need to sign it yourself before installing.

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
├── GameLogApp.swift       # macOS entry: WindowGroup + Settings scenes share one ModelContainer
├── iOSRootView.swift      # iOS entry: bottom TabBar (Library / Stats / Settings) + AirDrop backup import
├── Models/                # SwiftData models (Game / Completion / GameGroup / PhysicalCopy / Presets)
├── Support/               # PlatformImage abstraction, score math, backup, personalization, L10n,
│                          #   SteamGridDB, PlatformIcon (platform logos), PlatformButton (cross-platform button style),
│                          #   PlatformConfirmDialog (bottom action sheet), ImageSourcePicker,
│                          #   ShareSheetPresenter (iOS system share sheet)
├── Share/                 # Share card views + ImageRenderer output pipeline
├── Views/                 # Platform views (shared + #if os adaptations)
└── Resources/             # Tri-lingual Localizable.strings + Assets.xcassets (macOS/iOS AppIcon) + Info-iOS.plist + PlatformIcons (platform logo assets)
Scripts/                   # Standalone regression tests (not compiled into the app, see below)
```

## Development Verification

`Scripts/` holds repeatable standalone regression tests (compiled with `xcrun swiftc`; the macro-plugin path is in each file's header comment):

- `Scripts/ScoreMathSelftest/` — score logic self-test (rounding / means / library score)
- `Scripts/DataSmokeTest/` — data-layer smoke tests: many-to-many, cascade delete, scoring integration, backup round-trip, import idempotence & replace, holdings backup, date fidelity, preset localization
- `Scripts/ShareRenderTest/` — share card render pipeline: actually calls ImageRenderer to produce a PNG and validates pixel dimensions

When adding UI copy, the key must go into all three `Localizable.strings` and use `L10n.tr` / `LText` (not `String(localized:)`). After changes, run the key-coverage check — all three languages must have 0 missing (the command is in HANDOVER.md §2).

## Terminology

Domain terms (Game / Completion / Group / Review / Dimension Scores…) follow the glossary in `CONTEXT.md`.

## License

Released under the [MIT](LICENSE) license. See `LICENSE` in the repository root.
