# GameLog beta 2.2 续作指令（直接执行，无需追问）

你接着上一会话继续做 GameLog（macOS + iOS 双平台 SwiftUI 游戏收藏 app）的 **beta 2.2**。当前所有代码已实现并通过全量验证、已部署到 `/Applications` 并重启，但**尚未 `git commit`**，且**hover 崩溃未被用户实测确认解决**。

## 必读文件（按序）
1. `/Users/abc/Documents/gamelog_program/HANDOVER_PROMPT.md` —— 会话引导（已更新为「已重建」状态，含崩溃铁律与方法）。
2. `/Users/abc/Documents/gamelog_program/HANDOVER.md` —— **§29（beta 2.2）整节已更新**：§29.1–§29.10 是已验证的实现规格，§29.11/§29.12 是测试与验证清单（已勾选通过项），**§29.13 是本会话交付物与文件清单**（最重要，列了所有改动文件）。
3. 代码已在工作区（未提交）：`git status --short` 可见 13 个 Modified + 2 个 Untracked（`GameLog/Support/EnumPickerRow.swift`、`GameLog/Support/PriceFormat.swift`）。
4. 记忆：`holdings-fixedsize-crash.md`（崩溃排查史）、`xcode-beta-required.md`（环境）、`review-markdown-design.md`（beta 2.1 设计，本轮不动）。

## 环境铁律（错一步就白干）
- **构建只用 beta Xcode**：`export DEVELOPER_DIR=/Users/abc/Downloads/Xcode-beta.app/Contents/Developer`（普通 Xcode 26.6 无法解析 iOS 27 运行时）。
- **绝不用 CLT 的 `swiftc` 做类型检查/独立测试**（与 SwiftUIMacros 宏错配，`@State` 误报）。独立测试用 `xcrun swiftc` + `-plugin-path "$PLUGIN"`，`PLUGIN=/Users/abc/Downloads/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins`。
- macOS 构建：`"$XB" -project GameLog.xcodeproj -scheme GameLog -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/GameLogDD-mac build`。
- iOS 构建：**必须用 `-destination 'generic/platform=iOS Simulator'`**（指定具体机型如 `iPhone 16 Pro` 会错误落到 My Mac 报错），`-derivedDataPath /tmp/GameLogDD-ios`。
- **别只信 BUILD SUCCEEDED**：`stat -f '%Sm' /tmp/GameLogDD-mac/Build/Products/Debug/GameLog.app/Contents/MacOS/GameLog` 核对二进制 mtime 晚于源码再 `cp -R` 到 `/Applications` 并 `pkill -x GameLog && open /Applications/GameLog.app` 重启套用（用户偏好自动重启）。
- pbxproj 用 `PBXFileSystemSynchronizedRootGroup`，**新增 `.swift` 自动进 target**，只改 build setting（版本号）才手编 pbxproj；版本号现值 `"beta 2.2"`（4 处已改好）。

## 当前已验证状态（2026-08-20 晚，勿重复跑，除非改了代码）
- macOS Debug 构建 SUCCEEDED；bin mtime 20:50:14 已部署 `/Applications` 并重启。
- iOS Simulator Debug 构建 SUCCEEDED。
- ScoreMath 15/15；DataSmoke 全过（含 §29.11 迁移断言 23 项 PASS）；ShareRender 全过；RichReview 全过（`showCGGlyphs` deprecated 仅警告）。
- L10n 三语各 **295** key 完全一致、plutil 三语 OK、0 缺失（§29 原估 291 偏低，以实际 295 为准）。

## 你的待办（按优先级，全部做完才能 commit）
### ① hover 崩溃实测（最高优先级，§29.9）
- 现象：只有「有持有数据的游戏（Halo Campaign Evolved）」打开详情页→「持有」时，鼠标 hover 卡片即崩，栈 `_postWindowNeedsUpdateConstraints`→abort SIGABRT。真实 reason（命令行抓到）：`...more Update Constraints in Window passes than there are views in the window` = macOS 27 beta SwiftUI 在 hover 时 ScrollView `requestImmediateUpdate` 无限递归。
- 已修复假设（已部署 20:50:14）：`GameDetailView` 把 holdings 分支**完全移出外层 GeometryReader**（现为 `Group { if collectorMode && tab==.holdings { HoldingsView } else { GeometryReader { ScrollView {...} } } }`），`HoldingsView` 自带独立 `ScrollView`。
- **让用户实测**：命令行带 reason 捕获启动 `NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints=YES /Applications/GameLog.app/Contents/MacOS/GameLog > ~/gamelog_run.log 2>&1 &`，复现「Halo→持有→hover」是否还崩。仍崩则读 `~/gamelog_run.log` 的 reason 二分。**崩溃未确认解决前禁止 commit/tag/推 GitHub。**
- ⚠️ 仓库里**没有** `Repro/repro.swift` 脚手架（HANDOVER_PROMPT 旧文提到的，实际不存在），别去找。

### ② 用户验收两个推断枚举（见 HANDOVER §29 头注）
- `CopyRegional`（10 档：standard/cn/hk/tw/jp/us/eu/kr/asia/asiaEn）与 `CopyCondition`（7 档：sealed/mint/excellent/good/fair/worn/damaged，**默认值 good**）是**按合理推断重建、非原会话产物**（§29.7 列了 CopyMedia、§29.8 列了 CopyAcquisition，但**规格本身漏列**这两个）。若用户验收时要调整成员或默认值，改 `GameLog/Models/PhysicalCopy.swift` 四枚举 + 三语 `GameLog/Resources/{zh-Hans,en,ja}.lproj/Localizable.strings` 的 `copy.regional.*` / `copy.condition.*`，改完重跑 L10n 一致性 + 构建。

### ③ 用户 UI 实测（收藏家模式开启后）
- 持有页网格/列表双视图切换、顶部总览四格（版本数/总数量/总花费/总估值，未填显示 —）、编辑弹窗 7 档介质 + 11 档来源 + 品相（仅实体显示）、新建游戏随游戏建持有、统计页收藏价值区块。
- 视觉微调遵循 §29.10 已定终点值（胶囊 `.title3.weight(.semibold)` 约 20pt 大于版本名 `.headline`；`WrappingLayout(spacing: 8)`；胶囊行 `.padding(.leading, -2)`；每个胶囊 `.fixedSize()` + `.lineLimit(1)` + 横 12 纵 5），**不要重新走「太小/太贴/太松」往返**，新反馈才改。

### ④ 全部通过后的收尾（需用户明确授权再执行）
- `git add` + `git commit`（消息前缀 `beta 2.2：`，参照历史 §27.5/§26.5 风格）。
- 打 tag `beta-v2.2` + `git push origin main beta-v2.2`（push 需用户凭据；main 领先远程）。
- DMG/IPA 打包命令见 HANDOVER §27.5 / §26.5（卷名 `GameLog beta 2.2`）。

## 关键陷阱速查（详版见 HANDOVER §4 / §6）
- 平台显示排序唯一源 `Presets.ordered(_:)`；状态机平台口径 `Game.platformList`（记录平台 + 游戏级平台合并去重），别用 `completions.map(\.platform)`。
- 图片/颜色走 `Support/PlatformImage.swift`（`AppImage`/`Image(appImage:)`/`Color.semantic(.xxx)`），别裸 `NSImage`/`UIImage`。
- 库模式禁用顶层语句；临时脚本 `@main` 包裹。
- 全屏毛玻璃/隐藏工具栏逻辑只在 `Support/AppToolbar.swift`，别在页面另起数值；`ToolbarGlassModifier` 整 struct 包 `#if os(macOS)`。
- 新增 UI 文案 key 三语同步（`L10n.tr`/`LText`），跑 L10n 一致性检查（三语 0 缺失）。
- `#if os(macOS/iOS)` 就地守卫；`#if os` 后直接链修饰符会报 cannot infer contextual base，用 `Group { #if ... #endif }` 包一层。
- 数据层/导入测试前先给 store 拷快照（`~/Library/Application Support/GameLog-backups/`），「数据不见了」先查 store birthtime（见 HANDOVER §25.5/§9）。

## 一句话总结
代码全在、全验证通过、已部署；你只需**推动用户实测 hover 崩溃 + 验收两个推断枚举 + UI 实测**，三者全绿后按 ④ 收尾 commit/tag/推。**崩溃未确认前严禁提交。**
