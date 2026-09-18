# My Gamelog (我的游戏簿)

> **English** · [日本語](README.ja.md) · [简体中文](README.md)

A **macOS + iOS** personal app for recording your game library and completion history: statuses (backlog / playing / completed…), cover art, six-dimension scores, per-playthrough platform / date / degree / playtime / notes, physical collections (edition / quantity / photos), and shareable images. Fully local storage (SwiftData) — your data belongs entirely to you.

Interface languages: **简体中文 / 日本語 / English** (switch instantly in Settings). macOS and iOS each store data locally and independently; you can move data between them via JSON backup (including AirDrop).

## Features

- **Game Library**: search by name + aliases + localized names; filter by status / platform / group; group management (macOS sidebar / iOS filter menu), a game can belong to several groups; sort by name / release date / completion date / average score (low to high or high to low) / **recently edited** / **highest value**, defaulting to "recently edited". The library score is the mean of the record averages of all scored completions, rounded to 0.1; unscored games show "Unrated".
- **Favorites**: mark any game via the heart in the card context menu (right-click / long-press) or the detail toolbar — one tap to favorite / unfavorite, with an on-card heart badge showing the state (macOS menu uses filled ♥ / hollow ♡). A **Favorites** virtual group sits at the top of the sidebar's group section (first in the iOS filter menu's group section), aggregates every favorite with its own stats block, and coexists with real groups.
- **Library Home Carousel** (top of "All Games" — five swipeable pages + tappable dots): ① home banner (personalized title / subtitle / background + big avatar) ② random game (on each visit, one random game from the whole library — wide cover as a full-bleed backdrop, a prominent "Average Score" capsule, and the review title; if the game has no wide cover it falls back to a grid-size 2:3 cover with text on the right; re-roll button top-right; the backdrop can be set to Auto (landscape first) / hero only / landscape cover only in Settings, with separate settings for iPad landscape and portrait) ③ favorites (a rotating featured favorite with a 1:1 cover, the rest listed below) ④ library at a glance (game count / average score / backlog / completed·long-running + a six-status distribution) ⑤ collector overview (editions / quantity / spent / estimated value). Cards fill the window and scale their content responsively; macOS pages snap with a gap between pages, iOS pages turn natively; on iPad landscape the cards flatten automatically without runaway scaling. On iOS the "All Games" title is inlined below the carousel, scrolling with the content.
- **Views (per-platform)**: **macOS** grid / list toggle + sidebar; **iPhone** three view modes — grid / **single-column wide cards** (a square cover fills the full card height edge-to-edge; without one, the portrait cover scales to fit height and centers; glass-material rounded card background with a hairline border and shadow, liquid-glass score capsule overlaid on the cover's top-right, right column dedicated to title + platforms + metadata text) / list. The choice persists across launches and migrates from the old preference automatically. **iPad** upgrades the wide card to a **two-column layout** (landscape: horizontal card, image left / text right with upgraded card height and font sizes; portrait: vertical card, cover on top full column width, all five metadata fields visible). **Minimal Grid Mode** (all platforms): the grid shows only covers and the score/status capsule — names, platforms, and dates are hidden.
- **Game Status**: six statuses — Backlog / Playing / Paused / Dropped / Completed / Long-Running. Lightweight states need no completion records or scores; records attach when a game moves to Completed or Long-Running. Filter the library by status, pick via a liquid-glass slider on the detail page (below the score section on both platforms); non-completed games still carry a game-level platform and join platform filters and stats.
- **Game Detail**: review area (one-line tagline intro + long-form body), all completions (edit / append / delete), six-dimension colored bar chart; three optional fields for developer / publisher / genre; an extra "Holdings" tab when Collector Mode is on. **iOS word-boundary title wrapping**: the large title is tokenized with NLTokenizer so line breaks only fall on word boundaries — no more mid-word breaks like "遺|言".
- **Detail Header (per-platform)**: **macOS** wide windows use a "cover band + info column + glass score card" layout, falling back to the single column when the window narrows; an optional hero banner (full image with no cropping, flush with the top, full width, height linked to the window and the image's aspect ratio) plus a Logo (transparent PNG; size / vertical / horizontal each in three steps per game, locked to the cover's aspect ratio). **iPad** landscape uses the macOS hero layout (hero banner + Logo foreground + 28pt margins); portrait shows the landscape cover at full width (height cap raised to 560pt, no white bars); for scored games the glass score card sits to the right of the info column in both orientations (macOS-style two columns). **iPhone** switches to a full-width banner layout when a landscape cover is set (flush under the nav bar, height from the image's aspect ratio, capped at 260pt, never cropped); without one the original layout is kept unchanged.
- **Review (Markdown long-form)**: the one-line verdict (tagline) renders as a large lead-in "thesis"; the review body supports a Markdown subset (headings `#` / bold `**` / italic `*` / lists `-`) like a well-set article. **macOS = WYSIWYG rich-text editor** (a dedicated "writing desk" window; the toolbar applies styles directly, saved back to Markdown; CJK italics are synthesized with a shear at draw time); **iOS = editing sheet (TextEditor)**. Per-platform editing shares one Markdown renderer, so both platforms look consistent.
- **Six-Dimension Scoring**: Gameplay / Design / Story / Art / Music / Performance, 1–10 sliders with 0.1 steps. Overall = mean of the six; the first completion requires scores, later ones may be skipped.
- **Completions**: platform, completion date (can be "None"), completion degree (main story / all side quests / all endings / platinum / multiple playthroughs / speedrun / custom), playtime (can be "None"), and notes.
- **Date Picker**: macOS three-column wheel (year / month / day, handles Feb 29 and month-end clamping; spring-loaded snapping aligned with the system wheel feel); iOS uses the system date picker.
- **Groups**: create / rename / delete; pick games to join via context menu (macOS) or menu (iOS); per-group stats and review (rendered as Markdown; editable in the writing desk on macOS).
- **Collector Mode** (Settings toggle): "Details / Holdings" segmented switch on the detail page; each game can have multiple holdings (11 media types / 10 regions / 7 conditions / 11 acquisition sources / per-language price & estimated value / purchase date / notes + up to 6 photos), forming a **collection archive**. New games do **not** get a holding by default — you must toggle "I own this (create holding)" to expand the fields and build the archive. The Holdings view offers grid / list layouts, a top overview (edition count / total quantity / total spent / total estimated value), capsule-style metadata, and a full edit sheet; photos open in the system viewer; included in backups.
- **Cover Art & Images**: import from your device (iOS pops a "Photos / Files / Camera" menu), or search & download via the [SteamGridDB](https://www.steamgriddb.com) API (requires an API Key in Link Settings, searches as you type); each of the five image kinds has an **auto-match** toggle (portrait cover / square cover / landscape cover / hero background / logo — about 0.6s after you stop typing it picks the first hit, never overwrites an existing image, silent on failure; renaming a game also triggers a re-fetch); square covers return 1:1 results only (both 512×512 and 1024×1024 tiers are queried); the search sheet's copy follows the image kind and pre-fills the game's English name; results show thumbnails.
- **Personalization**: username (20 chars), avatar (circular crop), macOS app icon (rounded-square crop), auto-match cover toggle, hide top frosted glass (macOS 15+), keep-original-images toggle, platform-logos toggle (on by default; turning it off hides brand logos in platform pickers / grouping views). A custom icon reflects on the Dock immediately and persists across restarts.
- **Share Images (fully reworked in beta 2.4)**: a branded, fixed dark look — warm near-black background with an amber accent; the preview panel itself now follows the system appearance (adjusted 2026-08-27). Three card types:
  - **Single card**: blurred cover backdrop + a crisp poster filling its frame (matched to the cover's true aspect ratio — no letterboxing for SteamGridDB 2:3 portraits); the info panel carries the game name / platforms / release year / completion-degree pill / one-line verdict (gold) / six mini dimension bars / a large library score; non-completed games show a colored status badge instead.
  - **Overview image**: the header summary line and per-game tile fields are both configurable and reorderable in "Style Settings" (summary: game count / average score / total completions / collection value; tiles: platform / score / latest completion / release year / status label); column count adapts to the number of games and the canvas grows with content.
  - **Group card**: title + one-line group-review quote + stat items (average / game count / completions / top game / collection value, toggleable and reorderable) + platform distribution bars + in-group cover grid; separate phone / desktop layouts.
  - "Style Settings" configures all three pools in one place; overview tiles and group tiles share one field configuration. Export as JPEG (default) or PNG with the game / group name in the file name; on iOS, tap the preview for fullscreen and save straight to the Photos album (requires add-photo permission). The watermark (username's gamelog + avatar) is localized per language.
- **Stats & Rankings**: total completions, library average (plus backlog count), platform distribution, and collection value (when Collector Mode is on: edition count / total quantity / total spent / total estimated value); average-score leaderboard + six-dimension boards (top 5 / 10 per dimension); the "Overall Ranking" page switches between **Score Boards** and **Value Boards** at the top — Score Boards hold 7 boards (average + six dimensions), Value Boards hold three pages (by game value / by platform (machine) value / by group value), each paging up to 100 entries and filterable by platform.
- **Link Settings (its own entry point)**: brings the three things that aren't local preferences — SteamGridDB API Key, game accounts, and data backup — into one place, separate from Settings (language / personalization / storage & cache). **macOS**: App menu → Link Settings… (⌘⇧,), directly below Settings…, opening a dedicated window; **iOS / iPadOS**: a new Links tab in the bottom tab bar (between Stats and Settings). Game accounts are no longer a sub-page: the account list and per-row sync buttons sit right on the page, and only tapping a row pushes to its detail page.
- **Game accounts (experimental)**: link your **Nintendo Account / PlayStation Network / Xbox Live** account and read your play history from those services — playtime plus first/last-played dates (Nintendo), trophies (PSN: platinum / gold / silver / bronze + percentage), achievements and Gamerscore (Xbox) — then auto-match, manually link or merge them into your local library (the account page supports searching and status filtering). **Credentials are stored only in the local Keychain — never in SwiftData, never in backups, never logged, never uploaded**; unbinding deletes them. The game detail page gains a collapsible **Game Records** section with one source card per linked record (PSN trophy card / Xbox achievement card / Nintendo play-activity card); games with no linked records don't show it at all.
  > Three things stated plainly: ① **Xbox goes through [OpenXBL](https://xbl.io), a public third-party API — not an official Microsoft endpoint** — so your API key and request contents pass through that service. Nintendo and PlayStation connect directly to the official services from your machine, with no relay. ② The feature adds no backend of its own (no server, no account system); data only ever lands in your local library. ③ It is still experimental — the entry point is labelled as such in the app.
- **Backup**: export the whole library to a single JSON (covers embedded as base64), including username / avatar / icon, restorable as a whole, compatible with older backups; import asks for confirmation and runs in the background with progress (large libraries no longer freeze), the UI locks during import and the current library stays untouched on failure. On iOS, export uses the system share sheet (AirDrop / Save to Files, etc.) with a timestamped file name.
- **Auto Backup**: automatically writes a full local backup (one rolling file) whenever your data changes; keeps a snapshot of the old version before upgrades; if the library is empty but a backup exists, asks on launch whether to restore; snapshots before restore / import so you can undo. On iOS, backups live in Documents/Backups (visible in the Files app), so you can still grab them if the app can't launch (e.g. expired signing cert).
- **Clear Cache**: Settings → Storage & Cache shows current cache usage and clears it with one tap (cover/image decode caches, network cache, temp files) — never touches your game data or backups.
- **Launch Screen**: a branded splash (icon + app name + progress) shows immediately at startup and fades into the main UI; iOS additionally has a same-colored static system launch screen.
- **Large-library performance**: images are stored as external files and lazy-loaded (hundreds-of-MB libraries no longer stutter on edits or page switches); backups are written in the background as a streaming per-game encode — the main thread is never blocked.

## Platforms

| Platform | Deployment target | Notes |
|---|---|---|
| macOS | 14.0+ | Full features: sidebar, context menus, window toolbar, custom Dock icon, the writing-desk review editor, etc. |
| iOS | 18.0+ (iPhone / iPad) | Bottom TabBar (Library / Stats / Links / Settings); three library view modes, filter menu, add-image menu, bottom action-sheet confirmations follow iOS design conventions |

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

The repository provides one device Release IPA under `dist/`, unsigned — sign it yourself (eSign or similar) before installing:

- `GameLog-beta-3.2.ipa` — unsigned device arm64 build, suited for re-signing with eSign or similar tools

> Tip: for simulator or daily development debugging, just Run from Xcode — no simulator IPA is produced or needed; on macOS install straight from the DMG.

## Try the Demo Data

The repository includes a generated demo dataset ([GameLog-demo-backup.json](GameLog-demo-backup.json)) for demonstrating this app's features: 50 games (Chinese / English / Japanese names + release dates), 105 completions (platforms spread across Nintendo Switch 2 / PS5 / Xbox Series X|S / PC, with backward-compatibility traces), six-dimension scores, and 9 groups.

To import:

1. iOS: put the JSON into the Files app; macOS: place it locally
2. Open the app → Link Settings → Backup → **Import** → pick the file → Confirm

Note: importing replaces the current data.

## SteamGridDB Cover Search

1. Register for free at [steamgriddb.com](https://www.steamgriddb.com) and get an API Key from your profile page.
2. Open **Link Settings** (macOS: the app menu at the far left of the menu bar → Link Settings…, shortcut ⌘⇧,; iOS: the Links tab at the bottom) → SteamGridDB → enter the Key. The key field supports show/hide, copy, and auto-validation on change (✓ valid / ✗ invalid).
3. When creating / editing a game, tap the search button for the image kind you want (portrait cover / square cover / landscape cover / hero background / logo).

## Project Structure

```
GameLog/
├── GameLogApp.swift       # macOS entry: WindowGroup + Settings/About/writing-desk/link-settings scenes share one ModelContainer
├── iOSRootView.swift      # iOS entry: bottom TabBar (Library / Stats / Links / Settings) + AirDrop backup import
├── Models/                # SwiftData models (Game / Completion / GameGroup / PhysicalCopy / Presets)
├── Support/               # PlatformImage abstraction, ScoreMath, ExportImport/BackupWriter/BackupImporter/AutoBackup,
│                          #   Game+Backup (single Game↔DTO mapping), UserCustomization, L10n, SteamGridDB, PriceFormat,
│                          #   ImageImport (image import pipeline), LibraryStats (library aggregates),
│                          #   LibraryQuery (filter + stable sort + sort menu), StatusStyle (status colors/badges),
│                          #   ImageDecodeCache, LaunchGate (splash), PlatformIcon, PlatformButton,
│                          #   PlatformConfirmDialog (bottom action sheet), ImageSourcePicker,
│                          #   DocumentPicker (iOS file picking), ShareSheetPresenter (iOS share sheet),
│                          #   MarkdownReview (parse/render), MarkdownRichEditor (macOS writing desk)
├── Share/                 # Share card views (three card types + style pools) + ImageRenderer output pipeline
├── Views/                 # Platform views (shared + #if os adaptations)
└── Resources/             # Tri-lingual Localizable.strings + Assets.xcassets (macOS/iOS AppIcon) + Info-iOS.plist + PlatformIcons (platform logo assets)
Scripts/                   # Standalone regression tests (not compiled into the app, see below)
```

## Development Verification

`Scripts/` holds repeatable standalone regression tests (compiled with the beta Xcode toolchain `swiftc`; the macro-plugin path is in each file's header comment):

- `Scripts/ScoreMathSelftest/` — score logic self-test (rounding / means / library score)
- `Scripts/DataSmokeTest/` — data-layer smoke tests (700+ assertions): many-to-many, cascade delete, scoring integration, backup round-trip, import idempotence & replace, collection-archive migration & backup, date fidelity, preset localization, external-account record import & merge
- `Scripts/KeychainSelftest/` — keychain self-test: add / read / update / delete / clear-by-type (the path behind "unbinding deletes the credential")
- `Scripts/ShareRenderTest/` — share card render pipeline: actually calls ImageRenderer to produce PNGs, validating sizes / column counts / JPEG encoding / style-pool round-trips
- `Scripts/RichReviewTest/` — review editor core invariant: Markdown → rich text → Markdown round-trip is character-exact

When adding UI copy, the key must go into all three `Localizable.strings` and use `L10n.tr` / `LText` (not `String(localized:)`). After changes, run the key-coverage check — all three languages must have 0 missing (the command is in HANDOVER.md §2).

## Terminology

Domain terms (Game / Completion / Group / Review / Dimension Scores…) follow the glossary in `CONTEXT.md`.

## License

Released under the [MIT](LICENSE) license. See `LICENSE` in the repository root.
