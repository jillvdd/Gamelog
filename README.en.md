# My Gamelog

<p align="center">
  <img src="appcover.PNG" alt="My Gamelog Cover" width="100%" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" />
</p>

<p align="center">
  <strong>A modern, local-first game library and completion tracker for macOS and iOS.</strong>
  <br />
  Native Experience · Physical Collector Archive · External Account Sync · Editorial Share Cards · Advanced Statistics
</p>

<p align="center">
  <strong>English</strong> · <a href="README.ja.md">日本語</a> · <a href="README.md">简体中文</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B%20%7C%20iOS%2018.0%2B-blue?style=flat-square" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-5.10%20%2F%206.0-orange?style=flat-square" alt="Swift" />
  <img src="https://img.shields.io/badge/SwiftUI-SwiftData-purple?style=flat-square" alt="SwiftUI + SwiftData" />
  <img src="https://img.shields.io/badge/Version-beta%203.4-amber?style=flat-square" alt="Version" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License" />
</p>

---

## 🌟 Highlights

### 🎮 Game Library & Immersive Browsing

- **Comprehensive Search & Filter**: Instant search across titles, localized aliases, and multi-language names. Filter by status, platform, or user-defined groups.
- **Flexible Sorting**: Sort by title, release date, completion date, score, **recently edited**, or **estimated collection value**.
- **Home Carousel (Five Editorial Pages)**:
  1. **Personalized Banner**: Custom title, motto, backdrop art, and avatar.
  2. **Spotlight Game**: Randomly features a title with full-bleed landscape art and quick re-roll.
  3. **Favorites**: Highlighted showcase of your top favorite titles.
  4. **Library at a Glance**: Visual breakdown of total completions, average rating, and backlog distribution.
  5. **Collector Overview**: Instant metrics on physical editions, total copies, spent budget, and valuation.
- **Versatile Views**: Switch between Poster Grid, Compact List, **Square Cover Grid**, and **Minimalist Mode**.

### 🏆 Completion Tracking & Multi-Dimensional Scoring

- **Full Lifecycle Statuses**: Seamlessly transition games through Backlog, Playing, Paused, Dropped, Completed, and Long-Running.
- **Detailed Playthrough Logs**: Record platform, clear date, completion degree (Main Story, Platinum / 100%, Speedrun, etc.), playtime, and personal notes.
- **Dimension Scoring**: Rate Gameplay, Design, Story, Art, Music, and Performance (1–10, 0.1 increments) with automated averages and colored bar charts.
- **Long-Form Markdown Reviews**: Craft articles with one-line tagline hooks and full Markdown formatting. Includes a dedicated "Writing Desk" editor on macOS.

### 📊 Advanced Statistics Dashboard (New in beta 3.3)

- **Apple Fitness-Style Bento Grid**: Four key metrics — total completions, cumulative playtime, library average score, and in-progress/backlog count — at a glance.
- **Swift Charts Playtime Distribution**: Five playtime tiers (< 10h / 10–30h / 30–60h / 60–100h / 100h+) rendered as an amber-gold bar chart with smart anti-collision labels.
- **Six-Status Flow Capsules**: Color-coded pills showing the distribution across all six game states.
- **Cross-Platform Achievement Aggregation**: Combines PSN trophy counts (Platinum/Gold/Silver/Bronze) and Xbox Gamerscore with local completion data.
- **Top 5 Developers / Publishers**: Ranked by number of titles in your library.
- **Collector Vault Summary**: Total physical copies, cumulative expenditure, and total estimated portfolio value.
- **Dual-Mode Rankings**: Three leaderboards (Score / Playtime / Value) with 100 entries per page, paginated browsing, platform filter, cover thumbnails, and gold/silver/bronze rank badges. Each row taps into the game's detail view.

### 🎨 Editorial Share Cards (Fully Rebuilt in beta 3.3)

- **Two Premium Themes**: **Dark Gold** (deep warm black with amber accents) and **Editorial Light** (crisp white magazine aesthetic) — switch at any time.
- **Four Aspect Ratios**: Mobile portrait (9:16), desktop landscape (16:9), square (1:1), and portrait (4:5) for every sharing scenario.
- **Three Card Layouts**:
  - **Single Game Poster**: Cinematic composition with blurred cover backdrop, 1.5px micro-highlight border, status capsule, tagline, and dimension score bars.
  - **Overview Summary**: Adaptive multi-column grid with 5-mode intelligent sorting (Manual / Score / Date / Release Year / Title) and quick platform filter; fully configurable header stats and tile fields.
  - **Franchise Group Card**: Tailored for game series or themed collections — includes group review excerpt, stat tiles (avg score / game count / completions / top game / collection value), platform distribution bar chart, and a cover matrix grid.
- **Smart UI Routing**:
  - **iPhone**: Clean single-game flow (zero list noise) + dual-tab multi-game flow (Preview / Select Games).
  - **iPad / macOS**: Side-by-side split workspace — live preview on one side, full configuration on the other.
- **Flexible Export**: JPEG or PNG, one-tap save to iOS Photos, native system share sheet on iOS/iPadOS.

### 🔗 External Account Sync (Experimental)

- **Direct Gaming Platform Integration**: Connect your **Nintendo Account**, **PlayStation Network**, and **Xbox Live** accounts.
- **Automated History Fetching**: Sync play dates and playtime from Nintendo, trophy progress from PlayStation (Platinum/Gold/Silver/Bronze), and achievements / Gamerscore from Xbox.
- **Intelligent Linking & Merging**: Auto-match external records to library items, with manual linking, merging, and customizable ignore rules. Xbox PC-only records are automatically skipped.
- **Dedicated Record Cards**: Rich source cards (trophy card, achievement card, play log card) integrated directly into the game detail view.

### 📦 Physical Edition Archive (Collector Mode)

- **Built for Physical Game Collectors**: Dedicated "Holdings" archive for cartridges, discs, collector's boxes, and retro releases.
- **Comprehensive Metadata**: Track media types (standard, steelbook, limited collector's edition), regional editions (JP, US, EU, Asia), condition, acquisition source, and purchase price vs. current valuation.
- **High-Res Unboxing Gallery**: Store multiple real-world photos for each physical copy.
- **Asset Valuation**: Automated statistics for total physical copies, cumulative expenditure, and portfolio value.

### 🛡️ Local-First & Absolute Privacy

- **Zero Proprietary Servers**: No accounts, no analytics, no cloud tracking. All data lives on your device via SwiftData.
- **Keychain-Only Security**: All external account tokens and API keys are stored exclusively in the system Keychain — never written to the database, backups, or logs.
- **Automated Backup & AirDrop Migration**: Rolling local backups on every modification. Full JSON export/import and direct AirDrop transfer between macOS and iOS.
- **SQLite Self-Healing**: On each launch, the app automatically detects and repairs any NULL-value anomalies in the underlying SQLite store, preventing startup crashes from legacy data corruption.

---

## 💻 Native Platform Experience

| Platform | Min OS | Highlights |
|---|---|---|
| **macOS** | macOS 14.0+ | 3-column sidebar, context menus, keyboard shortcuts (⌘⇧, for Link Settings), dedicated Markdown Writing Desk, standalone Link Settings window, and live Dock icon customization. |
| **iOS** | iOS 18.0+ | Native TabBar navigation, ergonomic single-column wide cards, word-boundary line breaking, system share sheet, and direct camera/album photo import. |
| **iPadOS** | iPadOS 18.0+ | Adaptive two-column wide cards, responsive landscape/portrait split views, full-width Hero artwork banners, and wide-screen share workspace. |

---

## 🚀 Getting Started

### 1. Installation

#### macOS
- Download `GameLog-beta-3.4.dmg` from the Releases page, open it, and drag `GameLog.app` to your `Applications` folder.

#### iOS / iPadOS (Unsigned IPA)
- Grab `GameLog-beta-3.4.ipa` from the `dist/` directory.
- Re-sign and install using your preferred method (TrollStore, eSign, AltStore, SideStore, etc.).

### 2. Quick Demo Dataset

The repository includes a curated demo backup file: [GameLog-demo-backup.json](GameLog-demo-backup.json). It features 50 games (multi-language titles), 105 playthrough records, dimension scores, and 9 groups.

- **To Import**: Open app → Go to **Link Settings** (macOS shortcut `⌘⇧,`; iOS "Links" tab) → **Data Backup** → **Import Backup…** → Select the JSON file.

### 3. SteamGridDB Artwork Integration

1. Register for free at [steamgriddb.com](https://www.steamgriddb.com) and copy your API Key from your profile preferences.
2. Open **Link Settings** → **SteamGridDB** → Enter your API Key.
3. Tap **Search…** when adding or editing games to search and fetch portrait covers, square icons, landscape banners, and transparent logos.

---

## 📋 Release History

| Version | Highlights |
|---|---|
| **beta 3.4** (current) | Group share card title carry-over bug fix; stable build baseline. |
| **beta 3.3** | Modern statistics dashboard (Fitness-style Bento + Swift Charts + Rankings); Share system fully rebuilt across all three platforms (dual themes / four aspect ratios / iPhone clean flow / iPad-macOS split workspace). |
| **beta 3.2** | Dedicated Link Settings page (macOS ⌘⇧, + iOS tab); iOS startup & 1GB+ import OOM fix; full three-language copy rewrite. |
| **beta 3.1** | External account sync (Nintendo / PlayStation / Xbox); three source cards; game record collapsible section. |
| **beta 3.0** | Import/restore crash elimination; library replacement backgrounding with mutex gate. |
| **beta 2.x** | Physical edition archive (Collector Mode); home five-page carousel; large-library performance overhaul; share card overhaul; Markdown long-form reviews with Writing Desk. |
| **beta 1.x** | Game groups & reviews; multi-language titles; auto cover matching; six-dimension scoring; platform icon system; auto backup; physical holdings archive. |

---

## 🛠️ Development & Building

### Requirements

- **macOS 14.0+** / **iOS 18.0+**
- **Xcode 27 beta** (requires macOS 27 / iOS 27 SDKs)

### Build Commands

```bash
cd /Users/abc/Documents/gamelog_program

# Set Xcode beta toolchain path
export DEVELOPER_DIR=/Users/abc/Downloads/Xcode-beta.app/Contents/Developer

# ① Build macOS Debug
xcodebuild -project GameLog.xcodeproj -scheme GameLog -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/GameLogDD-mac build

# ② Build iOS Simulator Debug
xcodebuild -project GameLog.xcodeproj -scheme GameLog-iOS -configuration Debug \
  -destination 'id=9908C070-47ED-455C-8427-4ED9177591B4' -derivedDataPath /tmp/GameLogDD-ios build
```

### Offline Regression Test Suites

The project includes five offline self-tests under `Scripts/`:

- `Scripts/ScoreMathSelftest/`: Scoring calculations, rounding, and library averages (16 tests).
- `Scripts/DataSmokeTest/`: SwiftData models, cascades, account import, and backup serialization (753 tests).
- `Scripts/KeychainSelftest/`: Keychain isolation and secure credential erasure (17 tests).
- `Scripts/ShareRenderTest/`: ImageRenderer layout pipeline and card sizing (28 tests).
- `Scripts/RichReviewTest/`: Bidirectional Markdown-to-RichText editor fidelity verification (15 tests).

---

## 📖 Domain Vocabulary

This project adheres to a strict domain vocabulary defined in [CONTEXT.md](CONTEXT.md) (e.g. Game, Alias, Completion, Dimension Scores, Cover, Review). Please refer to it when contributing.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
