# GameLog 交接日志（HANDOVER）

> 更新：2026-08-17（beta 2.0 = 自动备份 + 清缓存，本轮提交）
> 状态：**beta 2.0 = macOS + iOS 双平台**（macOS 14.0 / iOS 18.0）。macOS + iOS Debug/Release 构建、ScoreMath/DataSmoke/ShareRender、L10n 三语全绿。**本轮已提交**；**未打 tag、未推 GitHub**。详见 §26。
> 环境：macOS 27 beta 只能用 **Xcode beta**（`/Users/abc/Downloads/Xcode-beta.app`），iOS 构建/运行一律用它。

## 1. 一句话现状

`GameLog.xcodeproj`（macOS + iOS，SwiftUI + SwiftData，纯本地，三语 zh-Hans / ja / en 即时切换）能完整构建并运行。**beta 2.0 已提交**：自动备份（每次数据改动防抖 3 秒写完整本地备份 + 版本升级前快照 + 恢复/导入前快照 + 空库检测恢复弹窗 + iOS 备份存 Documents/Backups）、设置「存储与缓存」一键清缓存（只清内存/网络/临时缓存，不动任何数据与备份）。beta 1.9 的状态机（6 状态 + 游戏级平台）、全屏毛玻璃、平台图标尺寸系统延续。**部署目标 macOS 14.0 / iOS 18.0**。DMG `dist/GameLog-beta-2.0.dmg`、IPA `dist/GameLog-beta-2.0.ipa` 已打包验证。GitHub 未推（tag 未打）。

版本号 `"beta 2.0"`（pbxproj 4 处：macOS/iOS 各 Debug/Release）。工作区干净（HANDOVER 文档与 dist/ 产物被 gitignore，不跟踪）。

## 2. 构建 / 运行 / 测试命令

```bash
cd /Users/abc/Documents/gamelog_program
export DEVELOPER_DIR=/Users/abc/Downloads/Xcode-beta.app/Contents/Developer   # macOS 27 beta 必须用 beta Xcode
XB=$DEVELOPER_DIR/usr/bin/xcodebuild

# macOS Debug 构建
"$XB" -project GameLog.xcodeproj -scheme GameLog -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/GameLogDD-mac build
# iOS Debug 构建（模拟器；beta Xcode 才能配对 27.0 运行时）
"$XB" -project GameLog.xcodeproj -scheme GameLog-iOS -configuration Debug \
  -destination 'platform=iOS Simulator' -derivedDataPath /tmp/GameLogDD-ios build

# 启动 / 重启验证（macOS）
open /tmp/GameLogDD-mac/Build/Products/Debug/GameLog.app
pkill -x GameLog && open /tmp/GameLogDD-mac/Build/Products/Debug/GameLog.app
# iOS 安装到模拟器（bundle id 是 com.abcleg.GameLog）
$DEVELOPER_DIR/usr/bin/simctl install <UDID> /tmp/GameLogDD-ios/Build/Products/Debug-iphonesimulator/GameLog.app
$DEVELOPER_DIR/usr/bin/simctl launch <UDID> com.abcleg.GameLog
```

- **重启惯例（用户已确认的偏好）**：每次改完代码、构建成功后，**自动替用户重启 app 套用最新构建**（`pkill -x GameLog` + `open` 上述 Debug 路径），不用等用户提醒。已存入记忆，新会话开场也应照做。
- Bundle ID：`com.abcleg.GameLog`；显示名：我的游戏簿 / My Gamelog；**默认图标**：`GameLog/Assets.xcassets/AppIcon.appiconset/`（由 appcover.PNG 生成）。
- 独立回归测试在 `Scripts/`（不进 app target）：
  - **评分自检**（15 项，纯逻辑，CLT swiftc 即可）：
    ```bash
    swiftc -o /tmp/sm GameLog/Support/ScoreMath.swift Scripts/ScoreMathSelftest/main.swift && /tmp/sm
    # 期望：PASS×15 + "ScoreMath self-test passed."
    ```
  - **数据层冒烟 / 分享渲染**：编译命令见 `Scripts/{DataSmokeTest,ShareRenderTest}/main.swift` 文件头注释。**两个命令都已带 `GameLog/Support/UserCustomization.swift`**（ShareRender 还需 `PlatformImage.swift`）。用 `xcrun swiftc` + `-plugin-path`，勿用 CLT swiftc。
- **L10n key 覆盖检查**（三语必须 0 缺失；别用 `comm`）：
  ```bash
  perl -0777 -ne 'while(/(?:L10n\.tr|LText)\(\s*(?:key:\s*)?"([A-Za-z0-9._]+)"/g){print "$1\n"}' GameLog/**/*.swift | sort -u > /tmp/code_keys.txt
  python3 -c "
  import re
  code = set(open('/tmp/code_keys.txt').read().split())
  for lang in ['zh-Hans','ja','en']:
      keys = set(re.findall(r'\"([A-Za-z0-9._]+)\"\s*=', open(f'GameLog/Resources/{lang}.lproj/Localizable.strings').read()))
      missing = code - keys
      print(lang, '缺', len(missing), sorted(missing) if missing else '无')
  "
  ```

## 3. 已提交基线（beta 1.1，commit 77e301e，30 文件 +709）

> beta 1.1 已 tag、已打包、已发布、已推 GitHub。以下为**基线事实**，改动相关功能前先了解，别再改回去。

### beta 1.1 功能改动

| 文件 | 改动 |
|---|---|
| `GameLog/Support/UserCustomization.swift`（新增） | 个性化项存储：用户名 `@AppStorage("customization.username")`；头像/图标 PNG 存 `~/Library/Application Support/GameLog/{avatar,icon}.png`，引用记 `customization.avatarFile/iconFile`；提供 保存/读取/移除/`applyDockIcon`/`pngData(from:)`；`usernameMaxLength = 20` |
| `GameLog/Views/ImageCropView.swift`（新增） | 上传图片裁切面板：`ImageCropSheet`（拖拽平移 + 缩放滑杆 + 遮罩实时预览，外部暗化 destinationOut 挖洞）；`CropKind`（avatar 圆形 256² / icon 圆角矩形 1024²）；`renderCropped` 静态方法做源图→遮罩区域映射。**框占比 0.85、缩放滑杆 0.8…8（整图可入框）** |
| `GameLog/Views/SettingsView.swift` | 「个性化」Section：用户名输入（20 字截断）、头像行、app 图标行；选图走 NSOpenPanel → `ImageCropSheet` → `UserCustomization.save{Avatar,Icon}PNG`；窗口 520×720 |
| `GameLog/GameLogApp.swift` | WindowGroup 加 `.onAppear { UserCustomization.applyDockIcon() }`（启动读回自定义 Dock 图标） |
| `GameLog/Views/RootView.swift` | 侧边栏底部「新建分组」按钮左侧 32pt 圆形头像（`@AppStorage(avatarFile)` 驱动刷新，未设不占位） |
| `GameLog/Share/ShareCardView.swift` | `BrandWatermark`（`{用户名}的游戏簿` + 48pt 圆头像）、`ShareDateFormat`（zh/ja「yyyy年 M月 d日」、en「MMM d, yyyy」）；单卡 footer、单卡平台-评语之间、总览格平台下**最后一次通关日期**；总览图左上角 72pt 头像 + 标题 `.minimumScaleFactor(0.5)` |
| `GameLog/Views/SharePanelView.swift` | 总览标题默认 = 设用户名?「{用户名}的游戏簿」:「我的游戏簿」；标题输入限 20 字 |
| `GameLog/Support/ExportImport.swift` | `BackupDTO` 加 `username/avatarBase64/iconBase64`（可选，旧版缺字段导入保持现状）；encode 读入，decode 写回 |
| `GameLog/Views/GameDetailView.swift` | 详情页头部平均分下方**四维彩色条形图**（`DimensionScoreBars`：剧情蓝/画面紫/音乐粉/玩法橙，长度按分/10；颜色定义在 view 内 `barColor`） |
| `GameLog/Models/Game.swift` | 新增 `dimensionAverage(for:)`：某维度在已评分记录上的均值（与 libraryScore 同一已评分口径） |
| 三个 `Localizable.strings` | 新增 11 个 key（settings.customization 系列、crop.titleAvatar/titleIcon/zoom、share.brandUser） |

### beta 1.1 收尾修复（已含在 commit 内）

- **Dock/About 图标空白**（根因 1，代码）：`applyDockIcon()` 原来 `applicationIconImage = iconImage()`，无自定义图标时置 nil 清空图标 → 改为无自定义图标时恢复 `NSImage(named: NSImage.applicationIconName)`。
- **Dock 图标空白**（根因 2，环境）：LaunchServices 按 bundle ID 解析图标，DerivedData 里 beta 1.0 无图标旧副本被当权威（见 §6.22 排查套路）。
- **裁切比框选小一圈**：预览遮罩 shape 未约束尺寸、填满画布 vs 实际出图 maskSide → 两处遮罩加 `.frame(width: maskSide, height: maskSide)`（放 `.fill/.stroke` 之后，见 §6.23）。
- **框太小 / 无法整图入框**：`maskRatio` 0.7→0.85、缩放滑杆 `1...4`→`0.8...8`（下限低于 maskRatio，见 §6.24）。
- **三处头像加大**：侧边栏 16→32、分享水印 36→48、总览 48→72。
- **详情页四维条形图**：见上表 GameDetailView/Game。

### app 默认图标改动

| 文件 | 改动 |
|---|---|
| `GameLog/Assets.xcassets/`（新增目录） | `AppIcon.appiconset/` 含 16–1024 全部 10 尺寸 PNG（sips 从 appcover.PNG 1254² 缩放）+ 两个 Contents.json |
| `GameLog.xcodeproj/project.pbxproj` | Debug/Release 两处加 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;`（**别用 `INFOPLIST_KEY_CFBundleIconFile`，无效**，见 §6.18）；`MARKETING_VERSION` 两处 `"beta 1.0"`→`"beta 1.1"` |
| `Scripts/{DataSmokeTest,ShareRenderTest}/main.swift` | 头注释编译命令补 `UserCustomization.swift` |
| `README.md` | 补 beta 1.1 功能描述 |

## 4. beta 1.2 新增改动（已提交，commit 8d2a6b2、tag beta-v1.2、已出 DMG）

> 三项功能全部作为 beta 1.2 提交，工作区已干净。以下为 beta 1.2 基线事实；**用户最终实测未完成**（走查见 §8），但已通过构建、L10n、三个测试脚本、分享卡像素采样。

### 4.1 自动匹配封面（功能①，开关默认关）

| 文件 | 改动 |
|---|---|
| `GameLog/Support/SteamGridDBClient.swift` | 新增 `autoCover(for:)`：`search` 第一条命中 → `SteamGridDBClient.sorted`（竖版优先）第一张 → 下载图片；无命中/无封面返回 nil，网络异常 throw。封面排序从 `CoverSearchSheet` 提取为 `static sorted(_:)`，手动搜索面板共用 |
| `GameLog/Views/GameEditView.swift` | 名字字段 `onChange` → 防抖 600ms → 满足条件才匹配：开关开 / `steamGridDBKey` 非空 / `coverData == nil`（**不覆盖已有封面**）/ 名字 ≥2 字 / `didFinishLoading`。匹配中封面框 overlay 小 spinner（`isAutoMatching`）；失败静默不打扰。`didFinishLoading` 关键：新建（load() 里 game==nil）与编辑都要置 true，**编辑放在字段写入之后**（避免 load() 给 name 赋值那一次 onChange 误触发匹配） |
| `GameLog/Views/SettingsView.swift` | 「个性化」Section 末尾加 Toggle「自动匹配封面」+ caption（`settings.autoMatchCoverHint` 提示需 API Key）；绑定 `autoMatchCover`（默认 false） |
| `GameLog/Support/UserCustomization.swift` | 加 `autoMatchCoverKey = "customization.autoMatchCover"` |
| 三个 `Localizable.strings` | 加 `settings.autoMatchCover` / `settings.autoMatchCoverHint` |

**状态：已随 beta 1.2 提交。测试构建过、Key 覆盖 0 缺失；用户未最终实测**。

### 4.2 封面显示重构（功能②）

**目标**：封面完整显示不裁切；分享竖卡内容条半透明叠在封面上、封面仍完整可见；字段全保留。

| 位置 | 改动 |
|---|---|
| `GameDetailView.swift` header 封面 | `scaledToFill` → `scaledToFit` + `quaternarySystemFill` 衬底；保持 160×213 框 + 圆角。2:3 封面左右留细衬底、**上下不再裁** |
| `ShareCardView.swift` 竖卡 `SingleCardVertical` | 重构：封面 `CoverImage(mode:.fit)` 按卡宽(1080)顶部对齐作**整卡背景**（`.frame(width:1080,height:1920,alignment:.top).clipped()`）；内容条贴卡底、面板高 700，半透明渐变遮罩 `.black.opacity(0.45)→(0.85)` **显式 `.frame(height:700)`** 铺满面板；标题/平台/日期/评语/四维分/总分/水印**全部字段保留、字号不变**；文字固定白系，不随深浅主题 |
| `ShareCardView.swift` 横卡 `SingleCardHorizontal` | 左栏封面 `CoverImage(mode:.fit)` 820×1080 + `theme.card` 衬底；右栏完全未动 |
| `ShareCardView.swift` 总览格 `OverviewCell` | 封面 `scaledToFit` + `theme.card` 衬底（与单卡统一不再裁切） |
| 组件 | `CoverFill` 更名 `CoverImage(mode: ContentMode = .fill)`；`BrandWatermark` 加 `tint: Color?`（竖卡传 `contentSecondary`） |

**竖卡当前可调参位置**（都在 `SingleCardVertical`）：面板高 700、渐变 0.45→0.85、字号 78/40/30/38/96、`contentText/contentSecondary/contentAccent`。

### 4.3 其他本会话事项

- **tag 命名二套未决**：本地 `beta-1.0/1.1`（未推）与 `beta-v1.0/v1.1`（已推远程）并存；是否删除本地无 v 版 / 统一命名未定（见 §9）。
- **工作流偏好已存记忆**：每次改完构建后自动重启 app（命令见 §2）。
- **未来功能调研**：自动填发售日期——SteamGridDB **不返回发售日期**；Steam 官方无 key 接口实测可行（见 §9）。

### 4.4 评分六维体系（功能③）

**决策**：六维 = 玩法/设计/剧情/美术/音乐/性能（顺序即全局显示顺序）；美术=原「画面」改名，设计、性能全新；整体 = 六维算术均值（纯派生，无第七维，标签仍「平均分」）；**已评分 = 六维中至少一项有分**（2026-08-13 修订：原「六维全齐」把旧四维记录全判未评分、统计页库平均分变「—」，用户要求按六维完全重写、不照顾老数据，遂放开）。老数据无需迁移。

| 文件 | 改动 |
|---|---|
| `Models/Game.swift` | `Dimension` 枚举四→六：`gameplay/design/story/art/music/performance` |
| `Models/Completion.swift` | 加 `scoreDesign`/`scorePerformance`，删 `scoreGraphics`；`score(for:)`/`scoreValues` 同步；`hasScores` 判 6 个 |
| `Support/ScoreMath.swift` | `recordAverage` 要求 6 个、÷6；自检加「4 items(旧四维) invalid」断言 |
| `Views/CompletionEditView.swift` + `GameEditView.swift` | 六滑块（玩法/设计/剧情/美术/音乐/性能）读写同步；`ScoreSliderRow` 标签列 64→96 |
| `Views/GameDetailView.swift` | 条形图六色：玩法橙/设计青/剧情蓝/美术紫/音乐粉/性能绿；完成记录维度行均分六列 |
| `Share/ShareCardView.swift` | 竖/横卡维度区 HStack→**LazyVGrid 3×2**；**竖卡面板 700→800** |
| `Support/ExportImport.swift` | `CompletionDTO` 六字段（去 graphics，加 design/performance） |
| 三个 `Localizable.strings` | `dimension.graphics` 删；加 `dimension.design/art/performance`；`completion.scores` 四维→六维文案 |

## 5. 已验证项

**beta 1.1 发布前全过**（保留）：Debug/Release 构建 exit 0、无 error；L10n 三语 0 缺失；ScoreMath 15/15；DataSmokeTest / ShareRenderTest 全过；裁切几何；app 默认图标；发布验证；手动 UI 走查（beta 1.1 项用户已实测确认）。

**beta 1.3 已验证**（保留）：Debug/Release 构建 exit 0；L10n 三语 0 缺失；ScoreMath 15/15、DataSmoke（含分组评价往返/平台限定评分/多语言名/无日期断言）、ShareRender（含分组卡/拉高卡）全过；像素采样（深色主题分组卡、拉高卡 4 行游戏全显示）；DMG 发布验证；真实 store 迁移成功。

**beta 1.5 已验证**（保留）：Debug 构建 exit 0；L10n 三语 0 缺失；ScoreMath 15/15；DataSmoke（含持有记录备份往返 7 项断言）、ShareRender 全过。收藏家模式：构建/测试全过；用户实测确认数量控件、缩略图规整、Quick Look 看图、排名页点击进详情均已修复。**全量用户走查完成（2026-08-13 晚，全部区块）**：beta 1.5、1.4、1.2/1.3、1.1 回归全部通过。走查期间追加 2 处修复（照片删除确认、备份默认文件名带日期时间）。

**beta 1.4 已验证**（保留）：Debug 构建 exit 0；L10n 三语 0 缺失；ScoreMath 15/15；DataSmoke 75 项 PASS。全屏工具栏遮挡修复：程序化测量确认窗口/全屏内容顶部安全区都是 52pt，被遮挡的是玻璃视觉多延伸约 24pt；方案 A（全屏 `safeAreaPadding(.top, 24)`）用户实测确认。方案 B（无标题无玻璃开关）观感可接受；开关切全屏稳定不挂。

**beta 1.8.1 已验证**（保留）：macOS/iOS Debug + Release 构建 exit 0；ScoreMath 15/15、DataSmoke、ShareRender 全过；L10n 三语 0 缺失；DMG/IPA 挂载/解压验证过。

**beta 1.9 已验证（本轮）**：macOS/iOS Debug 构建 exit 0（含 AppToolbar iOS 编译修复，见 §25.3）；ScoreMath 15/15、DataSmoke（含状态机 8 项新断言）、ShareRender 全过；L10n 三语 0 缺失；状态机走查（详情滑块/卡片状态/库筛选/统计想玩数/新建流程）用户实测确认；全局毛玻璃 + 「隐藏上方毛玻璃」开关用户实测确认。

**像素采样验证法（本会话实践，值得沿用）**：ImageRenderer 出 PNG → `NSBitmapImageRep.colorAt(x:y:)` 做亮度剖面 / 采样点 + alpha 检查。命令行渲染用 `xcrun swiftc` + `ShareCardView` 全家 + `-plugin-path` + `-framework SwiftData`，脚本 `@MainActor` 包渲染。

## 6. 编译陷阱（重要，别踩）

1. **macOS 26 SDK：`Slider(value:in:step:)` 会渲染刻度点点**，无公开 API 隐藏。要 0.1 步进就去掉 `step:`，用自定义 Binding 在 setter 里取整。
2. **NSViewRepresentable 托管进 SwiftUI 后，NSView 的 layer 属性不可靠**。圆角背景 + 描边放 SwiftUI 层。
3. **SwiftUI `TextEditor` 在 macOS 的坑**：`.padding()` 不垫开文本容器、无溢出也显示空滚动条、`.frame(minHeight:)` 无限拉长。→ 用自绘 `BorderedTextEditor`（NSTextView）。
4. **自增长 NSTextView 配置**：`isVerticallyResizable` + `minSize/maxSize` + `containerSize.height = .greatestFiniteMagnitude` + `widthTracksTextView`。`.greatestFiniteMagnitude` 必须显式 `CGFloat.`。
5. **CLT 的 swiftc 不能做本项目类型检查/独立测试**：与 SwiftUIMacros 宏错配，`@State` 误报。用 `xcodebuild` 或 `xcrun swiftc` + `-plugin-path`。
6. **库模式禁止顶层语句**，`#if` 豁免无效；含顶层自检代码必须放 `Scripts/` 用 `@main` 包裹。
7. **pbxproj 手写**（objectVersion 77 + PBXFileSystemSynchronizedRootGroup）：增删文件放同步文件夹自动进 target；**改 build setting（图标、版本号）才需手动编辑 pbxproj**。
8. **macOS 无原生滚轮样式**；SwiftUI ScrollView 做滚轮不可靠 → 滚轮用原生 `NSScrollView` + 自绘 `WheelDocumentView`（`DateMenuPicker`）。
9. **NSScrollView 滚轮要点**：`hasVerticalScroller=false`；吸附观察 `didEndLiveScrollNotification`；滚轮独占 = 子类 override `scrollWheel` 边界 `return`；`postsBoundsChangedNotifications = true`；documentView 高度 = 行数×行高 + 上下 2 行空白。
10. **`.scrollPosition(id:anchor:)` 的 id 是 `Binding<some Hashable?>`**，传 `Binding<Int>` 报错，要包 `Binding<Int?>`。
11. **NSViewRepresentable 里 static 成员外部用 `类型名.成员` 访问报错**：常量提到文件级顶层 `private let`。
12. **响应式双列**：`GeometryReader` 包 `ScrollView` 外层读宽度；≥阈值 `HStack` 两栏否则单栏。
13. **Picker 菜单陷阱**：嵌套 `Menu` 子菜单项半透明不可选；用 `Menu` 组件重写（每项 `Button` action + checkmark）。
14. **平台显示排序唯一源是 `Presets.ordered(_:)`**（beta 1.4 抽取）：预设按 `Presets.platforms` 世代倒序、预设外自定义按 canonical 字典序排最后。各 View 直接用，别重新 `.sorted()`。
15. **`@Query` 不监听实体关系属性变化**；要关系实时变化直接访问 @Model 对象关系属性。
16. **`NSWorkspace.icon(for: URL)` 在 macOS 26 SDK 不存在**；取 app 图标用 `icon(forFile: Bundle.main.bundlePath)`。
17. **版本号在 pbxproj `MARKETING_VERSION`**（macOS/iOS 各 Debug/Release，共 4 处），现值 `"beta 2.0"`。部署目标 `MACOSX_DEPLOYMENT_TARGET` 也是两处，现值 `14.0`（iOS 为 `IPHONEOS_DEPLOYMENT_TARGET`，现值 `18.0`）。
18. **macOS app 图标：`INFOPLIST_KEY_CFBundleIconFile` 不被 Xcode 的 `GENERATE_INFOPLIST_FILE` 注入支持**。必须用 asset catalog + pbxproj 设 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;`。
19. **`some Shape` 的 switch 分支不能返回不同类型**；`any Shape` 又不能对存在性类型调 `.fill`/`.stroke`（macOS 26 existential-member-access-limitations）→ 用 **`AnyShape`** 包装。
20. **Form 里给行加说明文字用 `LabeledContent(label) { ... }`**，左右布局符合 macOS 惯例。
21. **`NSApplication.shared.applicationIconImage = nil` 会把 Dock 与 About 的图标清空成空白**。无自定义图标时用 `NSImage(named: NSImage.applicationIconName)` 恢复。
22. **Dock 图标显示旧副本的环境坑**：LaunchServices 按 bundle ID 解析图标；系统里有更早的旧图标副本会被当权威。处理：`lsregister -f <app>` + 删 `~/Library/Caches/com.apple.iconservices.store` + `launchctl kickstart -k gui/$(id -u)/com.apple.Dock.agent`。**（2026-08-13 新增：旧副本还会导致启动崩溃）**——旧版 app 被解析成权威后，启动的是旧版，旧版打不开新版迁移过的 store → `ModelContainer(for:)` 抛错 → fatalError 崩溃。此时 DMG 挂载卷里能开、复制到 /Applications 后报错，正是新旧副本并存。处理：注册正确副本 + 删旧副本 + 清缓存重启 Dock。
23. **SwiftUI 的 Shape 没有固有尺寸，会填满父级提案尺寸**；按固定尺寸画必须 `.frame(width:height:)`；且 **`.frame` 要放在 `.fill`/`.stroke` 之后**。
24. **裁切「整图入框」**：缩放滑杆**下限必须 < maskRatio**（当前 0.8...8）。
25. **嵌套 ZStack 里的 `LinearGradient`/遮罩层要显式 `.frame(height:)`**：无显式尺寸在嵌套布局/ImageRenderer 里会坍缩或渲染到错误位置。
26. **`.frame(maxWidth:.infinity, alignment:.bottom)` 不能竖直贴底**：`alignment` 只在该 frame **有剩余尺度的轴**上生效；要贴底必须 `.frame(maxHeight:.infinity, alignment:.bottom)`。
27. **（2026-08-13）macOS SwiftUI：TextField 在父视图重渲染时会丢尾随空格**——可靠修法：`BorderedTextField`（NSTextField 封装），`updateNSView` 只在 `stringValue != text` 时才回写。已把全 app 单行 SwiftUI `TextField` 全部替换为它。
28. **（2026-08-13 beta 1.4 新增）SwiftUI 里 `.onReceive(NotificationCenter.publisher(...))` 回调中同步改 `@State` 会踩「视图更新期间发布变更」的未定义行为，表现是 UI 挂死/全黑/像调试窗口。** 可靠写法：状态变更包 `DispatchQueue.main.async { }` 推迟到下一轮 runloop。本会话 `isFullScreen` 检测已这么写。
29. **（2026-08-13 beta 1.4 新增）macOS 26 全屏下窗口工具栏毛玻璃会比工具栏布局（`contentLayoutRect`/safeArea 都返回 52）多延伸约一行（约 24pt）盖住内容顶端。** 这是系统渲染行为，`contentLayoutRect`/safeArea 不反映、无法用 API 压缩玻璃高度。修法：玻璃/标题恒在 + 全屏 `safeAreaPadding(.top, 24)` 把内容推到玻璃下沿之下。相关 API：`.safeAreaPadding(_:edges:)` 是 macOS 14+。**（beta 1.9：这套处理已全局化，见 §25.2 的 `AppToolbarModifier`；各顶层页面统一挂 `.appToolbar()`，数值只在 `Support/AppToolbar.swift` 一处）**
30. **（2026-08-13 beta 1.4 新增，beta 1.9 移动位置）要隐藏窗口工具栏毛玻璃只能用 `.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)`（macOS 15+）**；macOS 14 无对应 API（`.toolbarBackground(Color.clear, for: .windowToolbar)` 未必生效）。部署目标 14 时用 `#available(macOS 15.0, *)` 兼容——封装在 `Support/AppToolbar.swift` 的 `ToolbarGlassModifier`（原在 `LibraryView.swift`）。**`for: .windowToolbar` 是 macOS 专属 API，iOS 编译不过：`ToolbarGlassModifier` 整个 struct 必须包 `#if os(macOS)`**（beta 1.9 踩过）。全屏检测用 `NSWindow.willEnter/willExitFullScreenNotification`（在过渡开始前触发，配合异步更新让 `safeAreaPadding` 的 24pt 位移融入动画，避免过渡结束后内容硬跳）。
31. **（2026-08-13 beta 1.5 新增）网格缩略图别让图片自带尺寸**：`Image.resizable().scaledToFill()` 包 `Group` 直接 `.aspectRatio(1)` 会按原图天然尺寸撑爆网格。可靠写法：`Color.clear.aspectRatio(1, contentMode: .fit).overlay { Image...scaledToFill() }` 先占方格、图片裁剪填充（`HoldingsView.ThumbnailView` 已这么写）。
32. **（2026-08-13 beta 1.5 新增）看图用系统 Quick Look（`QLPreviewPanel`，`import Quartz`）**：图片数据写临时文件 → 协调器（`NSObject` 实现 `QLPreviewPanelDataSource/Delegate`）→ 设 `panel.dataSource/delegate` + `reloadData()` + `makeKeyAndOrderFront(nil)`。要点：协调器要持强引用防止面板使用期间被释放（`deinit` 里删临时文件）；`beginPreviewPanelControl/endPreviewPanelControl` 是 NSObject 已有方法需 `override`。比自绘缩放/平移看图器省事且原生（滚轮缩放/旋转/全屏）。
33. **（2026-08-13 beta 1.5 新增）SwiftUI 里用 `navigationDestination(isPresented:)` 推入的视图，其内部 `NavigationLink(value:)` 找不到父级根视图注册的 `navigationDestination(for:)`**；在推入视图内再注册 `for:` 也不可靠（本会话实测无效）。可靠写法：游戏名改 `Button` + 父视图 `@State selectedGame` + `.navigationDestination(item: $selectedGame)` 编程式 push（`StatsView`/`OverallRankingView` 已这么写）。
34. **（2026-08-13 beta 1.5.1 新增）自绘 `BorderedTextField`（NSTextField 封装）的提交回调必须传自定义 `onSubmit:` 参数**；SwiftUI 链式 `.onSubmit` 对 NSViewRepresentable 不触发（`BorderedTextField` 只在 `onSubmit` 参数非 nil 时才挂 `target/action`）。`GameEditView` 别名框曾用链式 `.onSubmit` 导致「添加别名」功能整体失效（见 §20.2）。
35. **（2026-08-13 beta 1.5.1 新增）展示「最近通关日期」用 `Game.latestCompletionDate`（最大通关日期），别用 `sortedCompletions.last.date`**（后者是最后添加的记录，补记老通关时与库排序口径不一致）。`GameCardView` 与 `ShareCardView` 竖/横/总览均已改用（见 §20.3）。
36. **（2026-08-13 beta 1.5.1 新增）备份导入顺序：先恢复用户名/头像/图标，再清空重建 store**。若先删 store、后写头像/图标（唯一可抛错步骤），写盘失败后 autosave 会把旧库永久删掉（见 §20.1）。
37. **（2026-08-17 beta 1.9 新增）状态机里「平台」是游戏级属性 + 通关记录平台合并去重**：`Game.platformList`（`completions.map(\.platform) + game.platform`，经 `Presets.ordered` 去重排序）。**任何要列「库里出现过的平台」或按平台筛选/计数的地方，都要用 `platformList` 而不是 `completions.map(\.platform)`**——否则未通关游戏（无记录但有游戏级平台）会从平台筛选/统计条/分享卡平台分布里消失。本轮已把 `GroupGamePickerView`、`ShareCardView`、`GroupFooter` 统计、`StatsView` 改过来（见 §25.4）。
38. **（2026-08-17 beta 1.9 新增）详情页状态滑块用内部 `@State sliderIndex` 驱动偏移 + `.animation(.spring(response:0.3,dampingFraction:0.78), value: sliderIndex)`**：不能用 `matchedGeometryEffect`（实测「无法使用、不是滑块样式」）、不能用父视图外部驱动的 offset（父视图重算时滑块会抖/缩）。滑块本身是 accent 半透明圆角条，盖在按钮网格上，offset = `sliderIndex × cellWidth`。iOS 要文字标签（仅图标用户会困惑），`compact` 模式只显图标。见 §25.1。

## 7. 项目约定（延续 CONTEXT.md）

- 术语一律用 CONTEXT.md 词表（Game/Completion/Group/Review…）。
- 新增 UI 文案：key 必须同时进三个 lproj，用 `L10n.tr` / `LText`，**不要用 `String(localized:)`**；跑 §2 的 key 覆盖检查（三语 0 缺失）。
- 个性化项存储约定：用户名/头像/图标/自动匹配封面/隐藏上方毛玻璃/**收藏家模式/保存原图/平台标志**都走 `UserCustomization`（AppStorage + Application Support 文件；`collectorModeKey`/`keepOriginalImagesKey`/`platformIconsKey`，备份/导入走同一层，别直接散落 UserDefaults key）。
- **平台显示排序唯一源是 `Presets.ordered(_:)`**（§6.14）。
- 四维条形图颜色在 `GameDetailView` 内 `barColor`，view 局部定义。
- 竖卡内容条白系文案常量 / 面板高 812 / 渐变三色 0.45→0.80→0.95 / 内容条 top padding 36 都在 `SingleCardVertical` 内定义。
- **全屏毛玻璃约定（beta 1.9 全局化）**：默认（方案 A）玻璃+标题恒在、全屏 `safeAreaPadding(.top, 24)`；设置「隐藏上方毛玻璃」（方案 B）关标题关玻璃、全屏不下推。逻辑全部集中在 **`Support/AppToolbar.swift`**（`AppToolbarModifier` + `ToolbarGlassModifier` + `.appToolbar()`），四个带工具栏顶层页面（LibraryView / GameDetailView / StatsView / OverallRankingView）统一挂 `.appToolbar()`。改观感先动这一处，别在页面里另起数值。
- **平台图标尺寸约定（beta 1.9）**：非白底图标默认放大（PS 系 ×1.2、其余 ×1.5），白底宽字标保持原尺寸；`PlatformIcon(enlarge:)` 默认 true，密集行（统计条）传 false。放大只影响图标本身宽度，`displayWidth` 同步放大用于「能否同行」判断。别在调用点手写 1.2/1.5 魔法数。

## 8. 手动 UI 走查

### 8.1 beta 1.1 回归参考（已实测过，改动相关后重测）

1. 设置「个性化」：用户名 20 字截断；头像/图标裁切面板与框选一致；移除/恢复禁用态正确。
2. 裁切面板：拖拽方向、缩放 0.8–8x、圆形/圆角矩形遮罩、整图入框、输出清晰。
3. Dock 图标：换图标即时变、重启保持、「恢复默认」回 appcover。
4. 分享图：水印、单卡/总览通关日期、总览头像+标题缩字号；三语。
5. 详情页：平均分 + 条形图；未评分不显示。
6. 备份：导出 JSON → 改数据 → 导入 → 用户名/头像/图标还原；旧版 JSON 导入不覆盖新三项。
7. 四维滑块无刻度、0.1 步进；`BorderedTextEditor` 行为；日期滚轮三语联动；封面搜索即输即搜；分享三尺寸、响应式双列、切语言即时跟随。

### 8.2 beta 1.2/1.3 实测（已提交发布，**2026-08-13 晚用户全量通过**）

> beta 1.2 的自动匹配封面、封面显示重构、六维评分；beta 1.3 的分组统计/评价、分组分享卡双模式、平台改名、排行榜、None 开关、0.1 舍入、多语言名——按 §4 与 §10–16 描述逐项实测。改动相关后再测。

### 8.3 beta 1.4 待实测（**2026-08-13 晚用户全量通过**）

1. **侧边栏平台区**：点平台行右侧显示该平台全部游戏、标题=平台显示名；自定义平台出现；数量徽标 = 去重游戏数；「全部游戏」清除过滤；预设世代倒序 + 自定义字母排后。
2. **分组右键「选择游戏…」**：右键分组 → 菜单项 → Popover（3 列封面网格，组内封面右上角 ✓）；点封面/标题整块切换即时保存；搜索框 + 平台下拉；空分组正常。
3. **平台筛选状态驱动**：全部游戏/平台页无工具栏平台菜单；分组页菜单只列本组内平台、切换分组重置；分组统计仍反映整个分组。
4. **全屏毛玻璃**（默认方案 A）：进出全屏内容不闪不跳、封面不被遮、标题在玻璃里不悬浮。
5. **「隐藏分组毛玻璃」开关**（beta 1.9 改名「隐藏上方毛玻璃」）：开启 = 无标题无玻璃（方案 B）、全屏也不下推；macOS 15+ 真隐藏，14 尽力；切换即时生效。

### 8.4 beta 1.5 待实测（**2026-08-13 晚用户全量通过**）

1. **收藏家模式开关**（设置个性化）：开启后详情页出现「详情/持有」分段切换；关闭恢复现状；「保存原图」只在收藏家模式开启时显示。
2. **详情页「持有」页签**：分段切换器在分数下方；持有页版本卡片按添加顺序排列；新增版本弹窗预填「版本 N」、数量默认 1；改名/删除走弹窗/确认。
3. **数量控件**：− ×N + 三段式，数字清晰、最少 1 份、即时保存。
4. **收藏照片**：每个版本最多 6 张；「添加图片」NSOpenPanel 多选 → 按「保存原图」开关压缩/原样；缩略图方格规整、悬停 × 删除、点击调起系统 Quick Look；满 6 张禁用。
5. **备份**：导出/导入含持有记录，旧备份缺字段不覆盖；删游戏级联删版本与照片。
6. **排名页进详情**：统计页榜单行与整体排名页榜单行点击游戏名都能进详情。

### 8.5 beta 1.9 新增待实测（用户已走查确认）

1. **详情页状态滑块**：六个状态按钮 + 液态玻璃滑块滑动；滑块动画流畅（spring）；iOS 显示图标+文字标签；点按钮滑块平滑移到对应位置；切状态即时保存。
2. **新建/编辑状态选择**：新建游戏可选想玩/在玩/搁置/弃坑/长线游玩/已通关；轻量状态（想玩等）不需要通关记录与评分（首条记录区不显示）；游戏级平台选择器对非通关状态可用。
3. **卡片/列表状态显示**：未通关卡片右上角显示状态胶囊（颜色区分，长线游玩=紫色 infinity）；已通关/长线游玩显示评分；列表行右侧同口径。
4. **库筛选加状态维度**：macOS 侧边栏状态区（6 状态，点选过滤）；iOS 筛选菜单加状态段（三向互斥：状态/分组/平台互斥单选）；切换状态/分组/平台清除其他过滤。
5. **统计页想玩数**：新增「想玩」计数块（backlogCount）。
6. **全屏毛玻璃全局**：库/详情/统计/排名四个页面全屏下封面/内容都不被玻璃遮挡；「隐藏上方毛玻璃」开关全局生效。
7. **平台图标尺寸**：库/筛选/统计条各接入点非白底图标放大（PS 1.2x、其余 1.5x）、白底字标原尺寸；统计条图标放大后排版不重叠（PlatformBarRow 修过）。

## 9. 若后续接手

- **当前最重要的下一步**：① **beta 1.9 已提交**（状态机 + 全局毛玻璃 + 图标尺寸，见 §25）；② **iOS 真机 iPhone 16 Pro 实测未完成**（拍照/相机、AirDrop 备份导入、QLPreviewController、PhotosPicker、TabBar 全流程——只有真机能完整验证）；③ **问用户是否推 GitHub**：main 领先远程多次提交，**本轮未打 tag**。要推：`git push origin main`（若要打 tag：`git tag beta-v1.9 && git push origin beta-v1.9`，远程 tag 命名是 `beta-v1.x` 格式）。⚠️ push 因 HTTPS 无交互凭据失败（`could not read Username`），需用户执行 push 时输入凭据或先 `gh auth login`/配置凭据。
- **数据迁移注意（2026-08-17 事件，务必读）**：某次构建后 app 显示空库（UserDefaults 的 SteamGridDB key 还在），用户通过导入旧备份恢复。**已用独立 swiftc 测试验证：旧 schema store（无 ZSTATUS/ZPLATFORM 列）→ 新 schema 的轻量迁移是成功的**（29 条数据 + 新增列正确）；所以不能简单归因于「schema 不兼容」。排查发现 app 正在用的 `~/Library/Application Support/default.store` 文件 birthtime 是 2026-08-13 22:09（beta 1.8 导入测试那晚），即真实 store 曾被替换/清空，原始数据只存在于备份快照里。**教训：涉及数据层/导入测试前，先把 store 拷到 `~/Library/Application Support/GameLog-backups/` 留快照；任何「数据不见了」先按 §25.5 排查 store 文件、对照备份 JSON，别急着怀疑迁移代码。** 用户已确认本轮修复后迁移/读取正常。
- **下次发版流程**：改 pbxproj `MARKETING_VERSION` 四处（macOS/iOS 各 Debug/Release）→ Release 构建 → `dist/` 出 DMG：暂存 `GameLog.app` + `ln -s /Applications Applications` → `hdiutil create -volname "GameLog beta X" -srcfolder <staging> -ov -format UDZO dist/GameLog-beta-X.dmg`。IPA：iOS Release 构建 → `xcrun --sdk iphoneos PackageApplication`（或 archive + export）→ 验证 arm64/Info.plist/AppIcon。改完跑一遍 §2 基线。
- **发布验证套路**：挂载 DMG 检查卷结构/版本号、`NSWorkspace.icon(forFile:)` 确认图标（正确=封面黄 251,221,3）、从挂载卷启动一次。
- **tag 命名二套未决**：本地 `beta-1.0/1.1`（旧版无 v，未推）与 `beta-v1.0/v1.1`（已推远程）并存，内容相同；是否删除本地无 v 版或统一命名，用户未定。
- **`appcover.PNG`（根目录，1254²）**：已作为图标源图提交进仓库，保留；删了也能从 Assets 里 1024px 取回。
- **图标环境坑**：改图标后 Dock 不更新，先按 §6.22 排查。
- **数据层/渲染管线改动后**重跑 §2 基线测试（含 DataSmoke / ShareRender）。
- **未来功能：自动填发售日期**（用户曾要求评估、决定"先做封面、日期后议"）：SteamGridDB 不返回发售日期；Steam 官方无 key 接口实测可行（`store.steampowered.com/api/appdetails?appids=<id>&filters=release_date`；`storesearch/?term=<名>` 中文名也能搜到如「巫师3」→292030；非 Steam 平台搜不到需手动兜底）。风险：无 key 端点偶被风控；大陆直连通常需代理。
- **工作流偏好**：每次改完构建后自动重启 app（§2 命令），用户已确认。

## 10. 分组统计 + 分组评价（2026-08-13 beta 1.3，commit 6c2bbc4）

分组视图底部两块：**分组统计** + **分组评价**（仅 `groupFilter != nil` 显示；「全部游戏」不加）。平均分按游戏聚合、评价只展示+弹窗编辑、不加计数块、空分组也显示、统计不受搜索/平台筛选影响。

| 位置 | 改动 |
|---|---|
| `Models/GameGroup.swift` | 加 `review: String`（默认 ""，SwiftData 增量迁移已验证） |
| `Support/ExportImport.swift` | `GroupDTO` 加 `review: String?` |
| `Views/GroupFooter.swift`（新增） | `GroupStatsSection`（平均分按游戏 `libraryScore` 聚合 round 0.5）；`GroupReviewSection` + `GroupReviewEditSheet`；`PlatformBarRow` 共享平台条 |
| `Views/StatsView.swift` | 平台条改用共享 `PlatformBarRow` |
| `Views/LibraryView.swift` | 分组模式改 `ScrollView + VStack`；`gameCard/gameRow/cardMenu` 提取 builder；列表模式 `LazyVStack` |
| 三个 `Localizable.strings` | 加 `group.stats/avgScore/review/reviewEmpty/reviewEdit` |

## 11. 分组分享卡 + 分享面板双模式 + 竖卡渐变微调（2026-08-13 beta 1.3，commit 6c2bbc4）

**分组分享卡单选**（一次一张，含分组名 + 平均分 + 游戏数 + 通关数 + 平台分布 + **组内游戏封面格**，不含评价）；入口为**分享面板双模式**（左栏「按游戏/按分组」分段滑块）；两种尺寸沿用 phone(1080×1920)/desktop(1920×1080)；空分组可分享；**画布按内容拉高**（`ShareCardLayout.groupSize`）。

| 位置 | 改动 |
|---|---|
| `Share/ShareCardView.swift` | `ShareCardContent` 加 `.group(GameGroup, title:size:)`；`GroupShareCard`、`GroupGameTile`、`ShareStatTile`、`SharePlatformBarRow`；**竖卡渐变微调**：面板高 800→**812**、内容条 top padding 24→36、渐变两色→**三色 `0.45→0.80→0.95`** |
| `Views/SharePanelView.swift` | 左栏顶部加 `ShareMode` 分段滑块；分组模式单选 `selectedGroupID`；文件名 `GameLog-group-{size}.png` |
| 三个 `Localizable.strings` | 加 `share.byGames/byGroups/groupTitle/noneSelectedGroup`、`group.gameCount/completionCount` |
| `Scripts/ShareRenderTest` | 加分组卡竖/横尺寸断言（含 10 款拉高至 2471 用例） |

## 12. 平台改名：Switch → Nintendo Switch（2026-08-13 beta 1.3，commit 6c2bbc4）

canonical 存储值也改 + 启动一次性迁移 + 保留旧名展示兜底。

| 位置 | 改动 |
|---|---|
| `Models/Presets.swift` | `Presets.platforms`：`Switch 2`→`Nintendo Switch 2`、`Switch`→`Nintendo Switch`；`localized[.platform]` 加旧名兜底映射（三语同文案） |
| `Support/PlatformMigration.swift`（新增） | `renames` 旧名→新名；`migrate(in:)` 幂等更新库内 `Completion.platform`（**beta 1.4 已删掉对 `libraryPlatformFilter` 持久化值的同步**，见 §18③） |
| `GameLogApp.swift` | 容器创建后、UI 展示前调用 `PlatformMigration.migrate(in:)` |
| `Scripts/DataSmokeTest` | 平台显示断言更新 |

## 13. 统计页排行榜 + 整体排名页（2026-08-13 beta 1.3，commit 6c2bbc4）

统计页底部「榜单」区：**平均分榜整行前 10** + **六维榜 2 列 × 3 行各前 5**；游戏名可点进详情；「整体排名」按钮 push 整页，**顶部滑块切换榜单**（平均分+六维 7 段）+ **每页最多 100 条翻页** + **工具栏平台切换**（分数按该平台记录算）；榜单行**隔行斑马纹**。

| 位置 | 改动 |
|---|---|
| `Models/Game.swift` | `libraryScore`/`dimensionAverage(for:)` 加 `platform:` 参数版本 |
| `Views/StatsRankings.swift`（新增） | `RankingEntry`/`Rankings.byAverage/byDimension`/`RankingBoard`/`OverallRankingView` |
| `Views/StatsView.swift` | 包 `NavigationStack`；底部 `rankingsSection(width:)` |
| 三个 `Localizable.strings` | 加 `stats.rankings/overallRanking/prevPage/nextPage` |

## 14. 通关日期/时长「无」开关（2026-08-13 beta 1.3，commit 6c2bbc4）

`Completion.date: Date?`（nil=无）；时长加显式 None 开关；None 日期在分享卡/库卡片/详情页隐藏日期行；按通关日期排序取最近非 None 日期。

| 位置 | 改动 |
|---|---|
| `Models/Completion.swift` | `date: Date` → `Date?`（SwiftData 增量迁移已验证） |
| `Models/Game.swift` | `latestCompletionDate` 改 `compactMap(\.date).max()` |
| `Views/CompletionEditView.swift` + `GameEditView.swift` | 通关日期/时长各加 None 开关 |
| `Share/ShareCardView.swift` | 日期行 `guard latest.date` |

## 15. 平均分舍入 0.5 → 0.1（2026-08-13 beta 1.3，commit 6c2bbc4）

`ScoreMath.roundToHalf` → `roundScore`（`(x*10).rounded()/10`）；排行榜按原始均值排序、显示取整到 0.1。

| 位置 | 改动 |
|---|---|
| `Support/ScoreMath.swift` | `roundToHalf` 改名 `roundScore`（0.1）；自检断言改 0.1 语义 |
| `Models/Game.swift` | 新增 `rawLibraryScore(platform:)`（排行榜排序用原始均值） |
| `Views/StatsRankings.swift` | `RankingEntry` 加 `sortScore` |
| `Scripts/DataSmokeTest` | 库显示分往返断言 9.083：9.0 → **9.1** |

## 16. 多语言游戏名（2026-08-13 beta 1.3，commit 6c2bbc4）

`name` = 英文名（必须、canonical），`nameZh`/`nameJa` 可选；`displayName(for:)` 按语言回退；全场景用显示名；库列表按显示名排序；搜索匹配全部名字+别名；详情页主名下方其他语言名小字。

| 位置 | 改动 |
|---|---|
| `Models/Game.swift` | 加 `nameZh`/`nameJa` + `displayName(for:)` + `searchableText` 含中/日文名 |
| `Support/ExportImport.swift` | `GameDTO` 加 nameZh/nameJa |
| `Views/GameEditView.swift` | 名称区三个字段 |
| `Views/GameDetailView.swift` | 头部主名 = 显示名 + `LocalizedNamesSubtitle` |
| 各视图显示点 | `game.name` 全部改 `displayName(for: language)` |
| 三个 `Localizable.strings` | 加 `game.nameEn/nameZh/nameJa` |

## 17. beta 1.3 发布记录（2026-08-13）

- **commit** `6c2bbc4`「beta 1.3：分组统计/分享 + 排行榜 + 平台改名 + None + 0.1 舍入 + 多语言名」（28 文件，+1602/−267）；**tag** `beta-v1.3`（本地，未推）；**DMG** `dist/GameLog-beta-1.3.dmg`。
- 版本号 `"beta 1.3"`（pbxproj Debug/Release 两处）。
- **发布验证已过**：Debug/Release 构建 exit 0；ScoreMath 15/15、DataSmoke、ShareRender 全过；L10n 三语 0 缺失；DMG 挂载卷结构、版本号、图标采样封面黄、从挂载卷启动成功；已恢复 Debug app 运行。
- **GitHub 未推**：main 领先远程三次提交，tag `beta-v1.3` 本地未推。

## 18. beta 1.4 发布记录（2026-08-13）

- **commit** `5d14580`「beta 1.4：侧边栏平台区 + 分组选择游戏 + 平台筛选重构 + 全屏毛玻璃修复 + 隐藏毛玻璃开关」；**tag** `beta-v1.4`（本地，未推）；**DMG** `dist/GameLog-beta-1.4.dmg`。
- 版本号 `"beta 1.4"`（pbxproj Debug/Release 两处）；部署目标保持 **macOS 14.0**（两处）。
- **六项新内容**：
  1. **① 侧边栏平台区**：`RootView`「全部游戏」与「游戏分组」间新增「平台」section，列出库里出现过的平台（`gamecontroller` 图标 + 去重游戏数 badge），预设世代倒序 + 自定义按 canonical 字母排后；`SidebarItem` 加 `case platform(String)`；点选 → 右侧该平台全部游戏、标题 = 平台显示名（`LibraryView` 加 `platform: String?` 参数）。L10n：`library.platforms`。
  2. **② 分组右键「选择游戏…」**：`RootView` 分组 contextMenu 加菜单项 + 每行 `.popover(item:)` 锚定；新增 `Views/GroupGamePickerView.swift`——3 列紧凑封面网格（约 130×173）+ 标题，组内游戏封面右上角蓝底白 ✓，点封面/标题整块切换加入/移出即时 `context.save()`；顶部 `BorderedTextField` 搜索（复用 `game.matches`，英/中/日名+别名）+ 平台下拉（整库平台 `Presets.ordered`，含「全部平台」重置）；标题「分组名 · N 款游戏」；空状态 `library.noResult`；面板宽 460、ScrollView maxHeight 460。L10n：`group.pickGames/pickSearch/memberCount`。
  3. **③ 平台筛选改状态驱动**：非分组视图（全部游戏/平台页）过滤来自侧边栏 `platform` 参数，切换页面即重置，工具栏平台菜单删除；分组页保留工具栏菜单但只列本组内平台（`groupPlatforms`），用局部 `@State groupPlatformFilter`，`onChange(of: groupFilter?.persistentModelID)` 切换分组重置；`libraryPlatformFilter` AppStorage 停止使用，`PlatformMigration` 里对它的写入删除。分组统计区块仍反映整个分组。
  4. **④ 共享平台排序**：`Presets.ordered(_:)` 成为平台展示排序唯一源（预设世代倒序 + 自定义字母排后），`Game.platformList` 委托它，`RootView`/`GroupGamePickerView` 共用。
  5. **⑤ 全屏工具栏毛玻璃遮挡修复**：macOS 26 全屏下工具栏毛玻璃比工具栏布局多延伸约一行（24pt）盖住内容顶端（§6.29）。方案 A（默认）：玻璃+标题恒在，全屏 `safeAreaPadding(.top, 24)` 下推内容；`isFullScreen` 用 `willEnter/willExitFullScreenNotification` + `DispatchQueue.main.async` 异步更新（§6.28 避坑）。**（beta 1.9 全局化为 `appToolbar()`，见 §25.2）**
  6. **⑥ 「隐藏分组毛玻璃」设置开关**：`UserCustomization.hideToolbarGlassKey`（默认关）；`SettingsView` 个性化 section 加 Toggle + hint（注明「macOS 15 及以上可启用」）；`LibraryView` 开启 = 方案 B（`.navigationTitle("")` 无标题 + `ToolbarGlassModifier` 隐藏玻璃 + 全屏不下推）。**（beta 1.9 改名「隐藏上方毛玻璃」并全局应用，见 §25.2）**
- **验证**：Debug 构建 exit 0；ScoreMath 15/15、DataSmoke 75 PASS 无 FAIL；L10n 三语 0 缺失；全屏遮挡程序化测量（§5）；用户实测确认方案 A/B 观感、开关切全屏稳定不挂。
- **GitHub 未推**：main 领先远程四次提交，tag `beta-v1.4` 本地未推。

## 19. beta 1.5 发布记录（2026-08-13）

- **commit** `ce007ec`「beta 1.5：收藏家模式（持有记录/版本/照片）+ 排名页导航修复」；**tag** `beta-v1.5`（本地，未推）；**DMG** `dist/GameLog-beta-1.5.dmg`。
- 版本号 `"beta 1.5"`（pbxproj Debug/Release 两处）；部署目标保持 **macOS 14.0**（两处）。
- **收藏家模式（新功能，默认关）**：
  1. **数据模型**：新增 `Models/PhysicalCopy.swift`（`@Model`：`version` 版本名必填、`count` 数量≥1、`images: [Data]` 最多 6 张、`createdAt` 排序）；`Game` 加 `copies` 1—* cascade（删游戏级联删版本与照片）。`images: [Data]` 在 SwiftData 里可用（已验证）。
  2. **设置**：`SettingsView` 个性化加「收藏家模式」（`UserCustomization.collectorModeKey` 默认关）+ 开启后显示「保存原图」（`keepOriginalImagesKey`，关=导入时压缩 JPEG 最长边≤1600/0.8，开=原样；只影响之后新增）。
  3. **详情页**：`GameDetailView` 分数下方加 `Picker(.segmented)`「详情/持有」（`DetailTab`）；收藏家模式关时整个隐藏。详情页签 = 原内容（`detailsContent(width:)` 提取），持有页签 = `HoldingsView`。
  4. **持有视图**（新增 `Views/HoldingsView.swift`）：版本卡片按 `createdAt` 排序；数量控件 **− ×N +**（修复原 Stepper `.labelsHidden()` 把数字藏掉的 bug）；3 列缩略图网格（`Color.clear.aspectRatio(1).overlay(scaledToFill)` 定方格，§6.31）；「添加图片」NSOpenPanel 多选 → 压缩/原样 → 追加（满 6 禁用）；悬停 × 删除；新增/改名/删除版本走弹窗。
  5. **看图 = 系统 Quick Look**（`QLPreviewPanel`，§6.32）：点缩略图 → 图片写临时文件 → `QuickLookCoordinator`（`QLPreviewPanelDataSource/Delegate`，`begin/endPreviewPanelControl` 需 `override`）→ `makeKeyAndOrderFront`；协调器持强引用、deinit 删临时文件。原生滚轮缩放/旋转/全屏/Esc。自绘看图器因黑边/缩放问题被弃用。
  6. **备份**：`GameDTO` 加 `copies: [CopyDTO]?`（版本/数量/图片 base64），旧备份缺字段不覆盖；DataSmoke 加「持有记录备份往返」7 项断言。
- **修复（排名页导航）**：统计页榜单与整体排名页点击游戏名进详情。根因：`navigationDestination(isPresented:)` 推入的视图内部 `NavigationLink(value:)` 找不到父级 `navigationDestination(for:)`，在推入视图内再注册 `for:` 也无效（§6.33）。改为 `RankingBoard` 行用 `Button` + `onSelect` 回调，`StatsView`/`OverallRankingView` 各自 `@State selectedGame` + `.navigationDestination(item: $selectedGame)` 编程式 push。
- **L10n 新增 key**：`settings.collectorMode/collectorModeHint`、`settings.keepOriginalImages/keepOriginalImagesHint`、`detail.details/detail.holdings`、`copy.*`（addVersion/noCopies/deleteConfirm/count/addImage/viewImage/rename/version/versionPlaceholder/versionAuto）。`copy.zoomFit` 曾随自绘看图器添加、弃用后已删。
- **验证**：Debug 构建 exit 0；ScoreMath 15/15、DataSmoke（含持有往返）、ShareRender 全过；L10n 三语 0 缺失。**用户最终实测已完成**（§8.4 六项全过）；走查期间追加 2 处修复（照片删除确认、备份文件名带时间，已随 `4bd4900` 提交）。
- **GitHub 未推**：main 领先远程五次提交，tag `beta-v1.5` 本地未推。

## 20. beta 1.5.1 发布记录（2026-08-13）

- **commit** `e1b5011`「beta 1.5.1：代码审查修复 8 项（导入安全/别名/日期口径/封面竞态等）」（13 文件 +68/−33）；**DMG** `dist/GameLog-beta-1.5.1.dmg`（已打包 + 挂载验证）；**未打 tag**（是否打 tag 未定）。
- 版本号 `"beta 1.5.1"`（pbxproj Debug/Release 两处）；部署目标保持 **macOS 14.0**。
- **全量代码审查（核心层亲自 + 视图层双子代理并行）后修复 8 项**：
  1. **高 · 导入安全**：`BackupManager.decodeAndReplace` 改为**先恢复用户名/头像/图标、再清空重建 store**。原顺序先删库、后写头像/图标（唯一可抛错步骤），写盘失败后 autosave 会把旧库永久删掉；新顺序写盘失败时原库完好。
  2. **中 · 别名功能失效**：`GameEditView` 别名框原来用 SwiftUI 链式 `.onSubmit`，对自绘 `BorderedTextField` 不触发；改为传 `onSubmit:` 参数（§6.34）。
  3. **中 · 最近通关日期口径**：`GameCardView` + `ShareCardView` 竖/横/总览 3 处原来用 `sortedCompletions.last.date`（最后创建），与库排序的 `latestCompletionDate`（最大日期）不一致；全部改用 `latestCompletionDate`（§6.35）。分享卡六维分仍取最后创建记录（设计点，未改）。
  4. **低 · 导出失败文案**：`SettingsView.export` catch 原来误用 `backup.importFailed`；新增 `backup.exportFailed` 三语 key 并改用。
  5. **低 · 封面下载竞态**：`CoverSearchSheet` 下载 Task 加 `downloadGeneration` 代际守卫；返回/关闭/换游戏/新下载都会使在途结果失效（原来下载完成后仍会应用封面并自动关面板）。
  6. **低 · 分享按钮**：`SharePanelView` 临时文件写失败时保持 `shareURL=nil`（原来无条件启用，分享可能指向缺失/陈旧文件）。
  7. **低 · 照片数上限**：备份导入 `images.prefix(6)` 截断（原来可导入 7+ 张破坏「最多 6 张」不变量）；DataSmoke 新增「持有：导入照片上限 6 张」断言。
  8. **文档**：`Game.libraryScore` 注释 0.5 → 0.1。
- **验证**：Debug 构建 exit 0；ScoreMath 15/15、DataSmoke（含新增照片上限断言）、ShareRender 全过；L10n 三语 0 缺失。用户手动实测：#2 别名添加、#3 最近通关日期、#5 封面竞态 全部通过。
- **未改设计点**：分享卡六维分仍取最后创建记录（非最大日期记录）；导入后持有记录 `createdAt` 重置为导入时刻（顺序靠数组保序往返一致，改动需扩备份格式）。
- **GitHub 未推**：main 领先远程六次提交，tag `beta-v1.5` 本地未推。

## 21. beta 1.6 发布记录（2026-08-14，多平台移植 macOS + iOS）

- **版本号 `"beta 1.6"`**（pbxproj 4 处：macOS/iOS 各 Debug/Release）。**DMG** `dist/GameLog-beta-1.6.dmg`（已挂载验证）。并入 beta 1.7 提交。
- **用户决策（grilling 三轮）**：iOS 18.0 起步、iPhone 优先 + iPad 附带；两平台本地独立数据、备份/导入互通、AirDrop 为 v1 通道（USB/蓝牙/iCloud 留未来）；iOS 功能全对齐；单目录 + 就地 `#if os()` 守卫；Bundle ID 沿用 `com.abcleg.GameLog`；版本同步；真机模拟器万无一失前不动、分发用户自理。
- **工程**：新增 iOS target `GameLog-iOS`（iOS 18.0、iPhone+iPad、SUPPORTED_PLATFORMS iphoneos+iphonesimulator、SDKROOT iphoneos）；iOS AppIcon `AppIcon-iOS.appiconset`（单张 1024 通用图标，源图 appcover.PNG）；iOS scheme `GameLog-iOS.xcscheme`；`Info-iOS.plist`（CFBundleDocumentTypes 声明 public.json）作为 `INFOPLIST_FILE` 与生成 Info.plist 合并。同步文件夹两个 target 共享同一 `GameLog` 组。
- **平台抽象层** `Support/PlatformImage.swift`：`AppImage`/`AppColor` 类型别名；`Image(appImage:)`；`Color.semantic(_:)`（quaternarySystemFill/separator/controlBackground/textBackground）；`compressedJPEGData`/`pngData`/`loadAppImage(from:)`/`cgImageValue`/`fromCGImage`。替代 33 处 `Color(nsColor:)` + 17 处 `Image(nsImage:)`。`ShareCardRenderer` 跨平台（`renderer.nsImage/uiImage` + `NSApp.effectiveAppearance`/`UITraitCollection`）。
- **macOS 专属件隔离**（`#if os(macOS)`）：`DateMenuPicker` 滚轮 → 改名 `DateMenuPickerMac` + 共享分发器（iOS 用系统 `DatePicker`）；`BorderedTextField/BorderedTextEditor` → 抽到 `Views/PlatformTextFields.swift` 共享分发器 + macOS NSTextField/NSTextView 实现（iOS 用 TextField/TextEditor）；QuickLook（`QLPreviewPanel`→macOS 分支，iOS 用 `QLPreviewController`）；`applyDockIcon`；LibraryView 全屏毛玻璃子系统（**beta 1.9 已抽到 `Support/AppToolbar.swift` 全局化**）；App 场景（Settings/Commands/About 窗口）；设置页与分享面板的 NSOpenPanel/NSSavePanel。
- **iOS 专属 UI** `Views/iOSRootView.swift`（整体 `#if os(iOS)`）：底部 TabBar 库/统计/设置；`iOSLibraryTab`（分组/平台两个工具栏筛选菜单 + 新建分组 + 分组管理 sheet `iOSGroupManagerSheet`；**beta 1.9 加状态段，三向互斥**）；库页平台过滤改为 `platform` 参数在分组/非分组两种模式都生效；设置页隐藏 macOS 专属项（app 图标、隐藏毛玻璃）；持有照片 PhotosPicker 多选（`collectionImageData(from data:)`）；封面 fileImporter；备份导出 ShareLink（含 AirDrop）/导入 fileImporter；AirDrop 接收备份 = `onOpenURL` + 确认导入（替换整库）。
- **验证**：macOS/iOS Debug 构建 exit 0；ScoreMath 15/15、DataSmoke、ShareRender 全过；L10n 三语 0 缺失；macOS Release + DMG 验证过；iOS 模拟器启动、TabBar 渲染、空库状态正常。**真机交互走查未做**。
- **环境**：macOS 27 beta 只能配 Xcode beta（`/Users/abc/Downloads/Xcode-beta.app`，27.0 SDK）；模拟器运行时 27.0。

## 22. beta 1.7 发布记录（2026-08-14，iOS 布局与交互适配，已提交）

- **commit** `afb331d`「beta 1.7：iOS 移植 + 全视图布局适配（双导航栏/工具栏折叠/底部 action sheet/统一加图菜单/文件共享）」；**DMG** `dist/GameLog-beta-1.7.dmg`、**IPA** `dist/GameLog-beta-1.7.ipa`（已挂载/解压验证）。**未打 tag、未推 GitHub**。
- **版本号 `"beta 1.7"`**（pbxproj 4 处）。
- **背景**：beta 1.6 移植后 iOS 上沿用 macOS 布局大量不适配（固定窗口宽、双导航栏、居中带尖角弹窗、工具栏折叠失效等）。三个并行 agent 彻查全部视图后，逐个做 iOS 单独适配（macOS 布局一律不动）。
- **iOS 布局适配**（`#if os()` 分支，macOS 不变）：
  1. **GameDetailView**：边距 28→16；头部 macOS 横排/iOS 竖排（封面 160×213 在上、信息在下）；「详情/持有」分段撑满；通关卡头部 iOS 拆两行（日期/时长/分数/按钮一行、平台/程度标签一行）。
  2. **LibraryView**：消除 iOS 双导航栏——iOS 复用外层栈（iOSLibraryTab 的 NavigationStack），详情改 `navigationDestination(item:)` 编程式 push（`selectedGame`），macOS 保留自建栈（`path`）。
  3. **iOS 工具栏精简防折叠**：原 7 个按钮触发 iOS 26 系统折叠「…」（点击无响应）。改为 leading 一个「筛选」菜单（分组/平台两段 + 管理），trailing「新建游戏」+ 自定义「更多」菜单（排序/网格/分享）。新建分组入口移至筛选→管理。新增 `library.filter` key。
  4. **确认弹窗改底部 action sheet**：iOS 26 液态玻璃下 `confirmationDialog` 居中带尖角。新增 `Support/PlatformConfirmDialog.swift`（`platformConfirmDialog`）：macOS 走 confirmationDialog，iOS 走 `UIAlertController(.actionSheet)`（底部、删除红色、液态玻璃）。替换 7 处（删通关/删游戏/删版本/删照片/删分组/两处导入确认）。
  5. **统一加图入口**：新增 `Support/ImageSourcePicker.swift`（`imageSourcePicker`）：点加图弹底部菜单「相册/文件/拍照」；相册走 PhotosPicker（可多选）、文件走 fileImporter、拍照走相机（`UIImagePickerController`，模拟器不可用时点击提示「当前设备不支持拍照」）。应用到游戏封面（GameEditView）、收藏照片（HoldingsView，含压缩与 6 张上限）、头像（SettingsView，仍走圆形裁切）。`Info-iOS.plist` 加 `NSCameraUsageDescription`。新增 `image.*` 5 个 key。
  6. **文件共享**：`Info-iOS.plist` 加 `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` → 模拟器「文件」app 可见 GameLog 的 Documents，可直接拖备份 JSON 进模拟器做导入测试。
  7. **其他固定宽度适配**：GameEditView/CompletionEditView 固定 minWidth 只限 macOS + iOS sheet 包 NavigationStack（保存/取消按钮生效）；CoverSearchSheet/GroupGamePickerView/ImageCropView/GroupFooter 评价编辑/StatsView/StatsRankings 的固定宽、大 padding、双栏阈值、平台名 160pt 等均 iOS 单独处理；GameCardView/HoldingsView 各弹窗固定 360 iOS 撑满；HoldingsView 缩略图删除角标 iOS 常显（onHover 不触发）。
- **验证**：macOS/iOS Debug + Release 构建 exit 0；ScoreMath 15/15、DataSmoke、ShareRender 全过；L10n 三语 0 缺失；DMG/IPA 验证过。**iOS 布局/交互用户模拟器实测进行中**（详情页竖排、底部 action sheet、加图菜单、文件共享导入已确认；真机拍照/相机、AirDrop 待真机）。
- **已知未做**：拍照真机未实测；iPad 布局未单独验证；AirDrop 备份导入模拟器不可测（无 AirDrop）。
- **GitHub 未推**：main 领先远程 4 次提交，tag 未打。

## 23. beta 1.8 发布记录（2026-08-14，平台图标系统 + iOS 交互优化与修复，已提交）

- **commit** `fd400b1`「beta 1.8：平台图标系统 + iOS 交互优化与修复（备份导出/保存相册/别名按钮/平均分排序/筛选单选/按钮样式/API Key 校验/封面缩略图/侧边栏毛玻璃）」；**DMG** `dist/GameLog-beta-1.8.dmg`、**IPA** `dist/GameLog-beta-1.8.ipa`（已打包验证）。**未打 tag、未推 GitHub**。
- **版本号 `"beta 1.8"`**（pbxproj 4 处）。

### 23.1 平台图标系统（大项）

- **资源**：`GameLog/Resources/PlatformIcons/` 25 个平台 PNG（源在 `svg icons/`，sips 缩放 ≤512px 打进包；同步组会把 PNG 平铺到 bundle 资源根，故 `Bundle.main.url(forResource:)` 不带 subdirectory）。**8 个稀疏字标**（SFC/SNES、3DS、NDS、N64、FC/NES、GBA、Game Boy、Game Boy Color）已把「白圆角块」烘焙进图（`Scripts` 外的临时脚本，成品直接入库，白底是像素级、深浅色下都显形）。
- **组件** `Support/PlatformIcon.swift`：`PlatformIcon`（+`@AppStorage` 平台标志开关）、`PlatformIconImage`、`PlatformIconLoader`。
  - **beta 1.9 尺寸系统**：`PlatformIcon(enlarge:)` 默认 true；白底图按烘焙后比例显示（宽 = size × 图比例）保持原尺寸；**非白底（方形 logo / Xbox 透明 / SF Symbol 兜底）默认放大：PS 系 ×1.2、其余 ×1.5**；`displayWidth` 同步按同一缩放系数。`enlarge=false`（统计条等密集行）不放大。`Xbox-Series-X-S.png` 已换新图标（源图 `svg icons/新图标.png`）。
  - **模板图标**（灰阶 PS/Xbox/Apple/NDS/Wii 等）渲染时按 `@Environment(\.colorScheme)` 烘焙主题色（深色=白、浅色=黑）——macOS 菜单忽略 SwiftUI `template` 着色，只能像素级烘焙。勿用动态 `NSColor.labelColor`（渲染上下文解析不稳定）。
  - **macOS 菜单按自然尺寸渲染图片**（`Image.frame` 被忽略）→ 用 `NSImage(cgImage:size:)` 把逻辑尺寸设为显示尺寸。iOS 液态玻璃菜单同样忽略 Image frame（白底能显示、宽度偏窄，用户接受）。
  - `PlatformIconLoader`：`isTemplate`（灰阶判定）、`aspect`（读 PNG 文件头宽高，**用 `as? NSNumber`**，`as? CGFloat` 对 CFNumber 返回 nil 会读不到）、`whiteBackgroundIcons` 白底集合、`tint`（像素重染保持 alpha）。
- **映射**：`Presets.platformIconFile(for:)` / `platformIconSymbol(for:)`（PC/其他/自定义平台 → `gamecontroller` SF Symbol 兜底）。
- **接入点**：平台选择器（`PresetOrCustomPicker` label + 选项，仅 platform 类别）、筛选菜单（macOS 侧边栏、iOS 筛选菜单、macOS 分组工具栏、分组选游戏、排名页）、统计条 `PlatformBarRow`、卡片/列表行/详情头部（`GamePlatformIcons`，名字优先、`ViewThatFits` 换行防省略）。分享卡按 Q9 决策不放图标。
- **设置开关**：「平台标志」（`customization.platformIcons`，默认开，双端；关掉后所有 `PlatformIcon` 渲染 EmptyView）。
- **已知限制**：iOS 26 液态玻璃菜单/选择器里图标宽度偏窄（Liquid Glass 忽略 Image frame，尝试过 ZStack/overlay/原生 UIImageView 均不理想，已接受现状）；分享卡不放图标。

### 23.2 iOS 交互优化与修复

1. **备份导出**：SwiftUI sheet 内嵌 ShareLink 在 iOS 26 静默失败（先弹其他窗可「预热」）→ 改 UIKit 直接 `present(UIActivityViewController)`（`topPresentedViewController` 锚点，iPad popover 处理）。设置页导出按钮不再挂 `.sheet`。
2. **分享面板「保存到相册」**：`PHPhotoLibrary` addOnly 权限 + `Info-iOS.plist` 加 `NSPhotoLibraryAddUsageDescription`；成功/失败/权限拒绝都有提示。
3. **别名「添加」按钮**（macOS+iOS）：输入框旁显式按钮，回车快加保留，共用 `addAlias()`。
4. **库排序新增平均分正序/倒序**：用 `rawLibraryScore(platform: nil)`（原始均值防并列错序），未评分沉底。
5. **iOS 分享面板布局**：预览在上、选择/滑块/导出在下（`previewColumn` 高度 240–340 封顶）。
6. **iOS 筛选菜单单选互斥**：分组与平台互斥，选一个清另一个，顶部「全部游戏」重置；后用 `ViewThatFits`/测量做名字防省略，侧边栏与统计条图标换行。
7. **iOS 按钮标准化**：`Support/PlatformButton.swift` 的 `appStandardButton()`（iOS=bordered、macOS 保持原样）；平台/程度选择器 iOS 用 `.menuStyle(.button)`。
8. **SteamGridDB key UI**：显示/隐藏（眼睛）、复制、改动时防抖校验 ✓/✗；`SteamGridDBClient.sanitizedKey` 取第一个空白分隔 token——修复「从网页复制 key 带进『Revoke API Key』文本导致 401」。
9. **封面搜索缩略图**：搜索命中后逐条抓第一张封面当缩略图（按序、复用 2 次/秒节流、最多 10 条、代际守卫取消）。
10. **封面按钮点击误触修复**：封面区三按钮 borderless，避免 iOS 26 Form 里 destructive 按钮抢占相邻点击。
11. **macOS 侧边栏底部毛玻璃**：`safeAreaInset(edge:.bottom)` 底条加 `.ultraThinMaterial` + 顶部 Divider，滚动内容被模糊遮罩。

### 23.3 验证

- macOS/iOS Debug + Release 构建 exit 0；ScoreMath 15/15、DataSmoke、ShareRender 全过；L10n 三语 0 缺失；DMG/IPA 挂载/解压验证过。
- 用户实测确认：平台图标各接入点、深浅色切换、平台标志开关、侧边栏毛玻璃、别名按钮、平均分排序、备份导出/保存相册；iOS 菜单宽度限制接受。
- **已知未做**：iOS 菜单图标宽度偏窄（已接受）；拍照真机、AirDrop 备份导入、iPad 布局待真机验证。
- **GitHub 未推**：tag 未打。

## 24. beta 1.8.1 发布记录（2026-08-14，全量代码审查修复 13 项，已提交）

- **commit** `787a89c`「beta 1.8.1：全量代码审查修复 13 项（iOS 删筛选分组崩溃/首条无分记录静默 7.0/封面搜索竞态/iOS 分享面板/iOS 导入权限/筛选切换残留等）」（15 文件 +138/−62）；**DMG** `dist/GameLog-beta-1.8.1.dmg`、**IPA** `dist/GameLog-beta-1.8.1.ipa`（已挂载/解压验证）。**未打 tag、未推 GitHub**。
- **版本号 `"beta 1.8.1"`**（pbxproj 4 处）。

### 24.1 全量代码审查方式

- 核心数据层 / 平台抽象层 / 分享渲染（约 3200 行）由主流程亲自通读；视图层（约 6200 行）拆成 3 个并行 agent 各自完整通读（编辑与持有组 / 导航与设置组 / 工具与统计组），每个发现由主流程逐行核验调用点后才接受或否决。基线先行（构建/ScoreMath/DataSmoke/ShareRender/L10n 全绿）再审查，修复后重跑全绿。

### 24.2 修复的 13 项

1. **高 · iOS 删当前筛选分组崩溃**：`iOSGroupManagerSheet` 删分组后 `iOSLibraryTab.groupFilter` 仍持已删对象，`LibraryView.visibleGames` 继续访问 `groupFilter.games` → SwiftData 访问已删模型崩溃（macOS 删除前先 `selection = .all` 清选中态，iOS 缺防护）。→ `iOSLibraryTab` 加 `onChange(of: groups)`：groupFilter 不在新列表时置 nil（与 platformFilter 无关，互斥由菜单保证）。
2. **高 · 首条无分记录编辑被静默写 6×7.0**：删掉唯一有分记录后，剩余无分记录成为首条；编辑时 `isFirst` 令 `save()` 的 `effectiveSkip = false`，但 `load()` 把 `skipScores` 置 true → 滑块隐藏、Toggle 禁用，保存把六个滑块默认值 7.0 全写入，用户无法输入期望分。→ `skipScores = !completion.hasScores && !isFirst`，首条无分时显示滑块让用户显式评分。
3. **中 · 封面搜索换游戏竞态**：`CoverSearchSheet.loadGrids` 的 Task 无代际校验，返回/换游戏后 A 的 grids 在途结果覆盖 B 的网格，此时点任一封面会把 A 的图下载进 B 的 `coverData`。→ 与 `download(_:)` 一致，Task 内 `guard gen == downloadGeneration`。
4. **中 · iOS 分享面板 ShareLink 静默失效**：iOS 26 sheet 内嵌 ShareLink 已知 bug（SettingsView 备份导出已改 UIKit，分享面板漏改）。→ 新增 `Support/ShareSheetPresenter.swift`（全局 `presentShareSheet`/`topPresentedViewController`），SharePanelView 与 SettingsView 共用；SettingsView 原私有实现删除。
5. **中 · iOS onOpenURL 备份导入权限失败**：`importIncomingBackup` 读取前未调 `startAccessingSecurityScopedResource`（「文件」App 打开方式发来的 URL 无权限，AirDrop 已拷入沙盒可读）。→ 读取前 start + `defer` stop。
6. **中 · 切平台/分组后详情页残留**：`RootView` 的 switch 在同一 case 分支内切换（平台 A→B、分组 A→B）时 `LibraryView` 视图身份不变，`@State path`（iOS `selectedGame`）与 `searchText` 残留，切平台后详情页仍停留。→ 新增 `resetNavigationContext()`，在 `platform`/`groupFilter` 变化时清 path/selectedGame/searchText。
7. **低 · 整体排名页翻页越界不回收**：数据收缩（删除/改分）后 `page` 越界 → 空白榜 + 错页码（如「3 / 1」）。→ `onChange(of: pageCount)` 钳位 `page`。
8. **低 · 排名页平台排序不统一**：`OverallRankingView.platforms` 用 `Set().sorted()` 字典序，与全 app 唯一源 `Presets.ordered(_:)`（世代倒序）不一致。→ 改用 `Presets.ordered`。
9. **低 · `dimensionAverage` 缺 1–10 范围校验**：与 `recordAverage`/`libraryScore` 口径不一致，越界分（仅导入路径可达）进维度榜、`DimensionScoreBars` 条形负/超长宽。→ 求均值前 `filter { (1...10).contains($0) }`。
10. **低 · `LocalizedNamesSubtitle` 重复 id**：nameZh==nameJa 且都 ≠ 主名时 `ForEach(id: \.self)` duplicate-id 运行期警告。→ `enumerated()`。
11. **低 · 备份导入分组名不 trim + 用户名先写不可回滚**：带空格分组名造成视觉重名/与 `groupNames` 引用错位；用户名（UserDefaults 写盘不可回滚）先于可能抛错的头像/图标文件写盘，文件写盘失败时用户名已变。→ 分组名与匹配都 trim；自定义三项改「先写文件、最后写 UserDefaults」顺序。
12. **低 · `LibraryView.safeAreaPadding` iOS 冗余**：iOS 恒 0（`isFullScreen` 恒 false、`hideToolbarGlass` 无 iOS 存储）。→ 收进 `topSafeAreaPadding`（macOS-only 计算属性）。**（beta 1.9 随全局化删除，见 §25.2）**
13. **低 · `SettingsView.validateKey` Task 未随视图消失取消**：加 `.onDisappear { keyValidationTask?.cancel() }`。

### 24.3 核验为非 bug / 暂不修

- **核验非 bug**：SwiftData to-many 关系数组顺序（独立实测=插入顺序，导出→导入往返顺序靠数组保序一致）、Localizable.strings 字面 `%`（全为合法占位符，无 `String(format:)` 崩溃）、`Schema` 未显式列 PhysicalCopy（SwiftData 自动纳入关系可达模型，实测容器创建正常）、`OverallRankingView` 内 `navigationDestination(item:)`（HANDOVER §6.33 已验证的可靠写法）、`BorderedTextField` placeholder（所有调用点均传常量）。
- **暂不修（记录在案）**：① macOS Quick Look 预览面板打开时切「持有」页签 → HoldingsView 移出视图树，`QuickLookCoordinator` deinit 删临时文件 → 面板空白（QL 生命周期复杂，改错易引崩溃）；② 导入的部分维度评分记录编辑后缺失维度被填 7.0（触发仅限导入路径，需滑块 dirty 跟踪，改动大）；③ iOS action sheet present 竞态（低概率）；④ `SteamGridDBClient.search` 用 `.urlPathAllowed` 不编码 `/`（含 `/` 标题极罕见）。

### 24.4 验证

- macOS/iOS Debug + Release 构建 exit 0；ScoreMath 15/15、DataSmoke、ShareRender 全过；L10n 三语 0 缺失；DMG/IPA 挂载/解压验证过；已用修复后构建重启 app。
- **GitHub 未推**：tag 未打。

## 25. beta 1.9 发布记录（2026-08-17，状态机 + 全局全屏毛玻璃 + 平台图标尺寸系统，本轮提交）

- **commit** 本轮提交（见 git log）；**DMG** `dist/GameLog-beta-1.9.dmg`、**IPA** `dist/GameLog-beta-1.9.ipa`（已打包验证）。**未打 tag、未推 GitHub**。
- **版本号 `"beta 1.9"`**（pbxproj 4 处：macOS/iOS 各 Debug/Release）。

### 25.1 状态机（大项，用户 ROADMAP 第 1 阶段）

**决策**：6 状态 = 想玩 / 在玩 / 搁置 / 弃坑 / **长线游玩** / 已通关。想玩/在玩/搁置/弃坑是轻量状态：不挂通关记录（详情页隐藏记录区）、卡片显示状态标签（不显示评分）；流转到 `completed` 或 `longRunning` 才挂记录。**长线游玩对应已通关**：挂通关记录、卡片显示评分（而非标签），用于长期运营游戏。未通关游戏也有**游戏级平台**（右上角显示，对应评分位）。

| 文件 | 改动 |
|---|---|
| `Models/Game.swift` | `GameStatus` 枚举（6 状态 + `labelKey`）；`Game` 加 `platform: String = ""`（游戏级平台）、`status: String = GameStatus.completed.rawValue`（存储 rawValue）；`statusValue`（未知值兜底 completed）、`isCompletedOrLongRunning`、`platformList`（记录平台 + 游戏平台合并去重，`Presets.ordered` 排序） |
| `Support/ExportImport.swift` | `GameDTO` 加 `platform: String?`/`status: String?`（可选，旧备份缺 status → 默认已通关） |
| `Views/GameDetailView.swift` | 头部状态选择器 `DetailStatusPicker`（私有 struct）：**内部 `@State sliderIndex` 驱动 offset 滑块 + `.animation(.spring(response:0.3,dampingFraction:0.78), value: sliderIndex)`**（§6.38）；accent 半透明圆角条盖在按钮网格上；iOS 显示图标+文字标签（仅图标用户会困惑）；`detailStatus` @State + `.onAppear` 从 `game.statusValue` 同步；非 completed/longRunning 隐藏记录区与分数 |
| `Views/GameEditView.swift` | 状态选择区（六状态横排）+ `game.statusHint`；平台选择器提到游戏级（所有状态可用）；首条记录区仅新建且 status==completed/longRunning 时显示；保存写 `game.statusValue` + `game.platform` |
| `Views/GameCardView.swift` | 卡片/列表右上角：completed/longRunning 显示评分（`libraryScore`），否则状态标签（胶囊 + `statusColor`）；`coverImage` NSCache（数据哈希作 key，避免重复解码） |
| `Views/LibraryView.swift` | `statusFilter: GameStatus?` 参数 + `visibleGames` 过滤；筛选菜单加状态段 |
| `Views/RootView.swift` | 侧边栏加状态 section（`GameStatus.allCases`，`sidebarIcon`：backlog=bookmark、longRunning=infinity 等）；`SidebarItem` 加 `case status(GameStatus)` |
| `Views/iOSRootView.swift` | 筛选菜单加状态段；状态/分组/平台**三向互斥单选**（选一个清另外两个，顶部「全部游戏」重置） |
| `Views/StatsView.swift` | 加「想玩」计数块（`backlogCount` = statusValue==.backlog 数）；平台计数改 `game.platformList` |
| `Scripts/DataSmokeTest` | 加状态机 8 项断言：默认已通关、想玩存储/无记录/无评分、状态备份往返、想玩带游戏级平台、已通关合并平台去重（PS5 预设序在前）、想玩平台备份往返、长线游玩 isCompletedOrLongRunning |
| 三个 `Localizable.strings` | 加 `game.status`/`game.statusHint`/`status.backlog/playing/paused/dropped/completed/longRunning`/`stats.backlogCount` |

**状态机走查（§8.5）用户已确认**：详情滑块、新建流程、卡片显示、库筛选、统计想玩数。

### 25.2 全屏毛玻璃全局化（「隐藏上方毛玻璃」）

**背景**：beta 1.4 起 LibraryView 单独处理全屏工具栏玻璃遮挡；用户实测发现详情页/统计页同样问题 → 要求全局化 + 设置项改名「隐藏上方毛玻璃」并全面应用。

| 文件 | 改动 |
|---|---|
| `Support/AppToolbar.swift`（新增） | `AppToolbarModifier`（`@AppStorage(hideToolbarGlassKey)` + macOS 全屏检测 `willEnter/willExitFullScreenNotification` + `DispatchQueue.main.async` 异步更新 + 全屏 `safeAreaPadding(.top, 24)` 下推）+ `ToolbarGlassModifier`（**整个 struct 包 `#if os(macOS)`**，`for: .windowToolbar` 是 macOS 专属 API，iOS 编译不过）+ `.appToolbar()` 扩展 |
| `Views/LibraryView.swift` | 删除本地 isFullScreen/windowIsFullScreen/setFullScreen/ToolbarGlassModifier/safeAreaPadding，改挂 `.appToolbar()`；保留 `hideToolbarGlass` 驱动 `navigationTitle("")` |
| `Views/GameDetailView.swift` | 删除本地全屏逻辑，改挂 `.appToolbar()` |
| `Views/StatsView.swift` | 挂 `.appToolbar()` |
| `Views/StatsRankings.swift` | 挂 `.appToolbar()` |
| 三个 `Localizable.strings` | `settings.hideToolbarGlass` 文案改为「隐藏上方毛玻璃」、Hint 改「所有页面（库/详情/统计）」 |

**iOS 编译坑**：`ToolbarGlassModifier` 里的 `for: .windowToolbar` 在 iOS 编译报 `'windowToolbar' is unavailable in iOS`。虽然应用点在 macOS 分支内，但 struct 定义本身 iOS 也会编译 → 必须把 struct 整体 `#if os(macOS)` 包住（本轮踩过，已修，§6.30 更新）。

### 25.3 平台图标尺寸系统 + 新 Xbox 图标

| 文件 | 改动 |
|---|---|
| `Resources/PlatformIcons/Xbox-Series-X-S.png` | 换新图标（源图 `svg icons/新图标.png`，1MB+ 原始 PNG） |
| `Support/PlatformIcon.swift` | `PlatformIcon` 加 `enlarge: Bool = true`：**非白底图标统一放大（PS 系 ×1.2、其余 ×1.5），白底宽字标保持原尺寸**；`displayWidth` 加 `enlarge` 参数按同一系数；SF Symbol 兜底按放大后宽度估算 |
| `Views/GroupFooter.swift` | `PlatformBarRow` 重构：去掉嵌套 GeometryReader，图标固定宽度区域 + 名字 flex + `minimumScaleFactor` 防省略 + 条形 minWidth 30；名字号 13→14（图标放大后视觉协调） |

**用户反馈驱动**：Xbox 图标反复 6 轮（白底太跳→深绿→噪点→描边粗→2x 去底太大→1.5 透明）；PS 系图标观感偏大 → 单独 1.2x；最终「所有非白底图标 1.5x、PS 1.2x、白底字标原尺寸」。

### 25.4 平台口径统一（未通关游戏也有平台）

状态机引入游戏级平台后，**所有「平台」展示/筛选/计数必须用 `Game.platformList`**（记录平台 + 游戏平台合并），否则未通关游戏会从平台相关 UI 消失：

| 文件 | 改动 |
|---|---|
| `Views/GroupGamePickerView.swift` | `platforms` 与 `visibleGames` 过滤改用 `game.platformList` |
| `Views/StatsView.swift` | 平台计数改 `game.platformList` |
| `Share/ShareCardView.swift` | 单卡竖/横平台行、分组卡平台分布、分组卡尺寸估算全部改用 `game.platformList` |
| `Models/Game.swift` | `platformList` 成为唯一平台来源（§6.37） |

### 25.5 数据迁移事件（2026-08-17，重要）

- **现象**：某次构建后 app 显示空库（UserDefaults 的 SteamGridDB key 还在，说明 SwiftData store 与 UserDefaults 分离存储，只有 store 空了）。用户导入旧备份 JSON（`~/Downloads/GameLog-backup-2026-08-13-22-02.json`，29 游戏）成功恢复。
- **排查结论**：
  1. **旧 schema → 新 schema 迁移是成功的**：用独立 swiftc 测试（`/tmp/migtest`，编译 Game/Completion/GameGroup/PhysicalCopy/Presets/ScoreMath + 一个 `@main` 打开旧 store 的容器）打开 `real-store-restore-2202` 的旧 store（无 ZSTATUS 列），29 条数据 + 新增列全部正确读回。**不能归因于 schema 不兼容**。
  2. **app 正在读的 `~/Library/Application Support/default.store` 文件 birthtime = 2026-08-13 22:09**（beta 1.8 导入测试那晚），即真实 store 在 13 号晚已被替换/清空；原始数据只存在于 `~/Library/Application Support/GameLog-backups/2026-08-13/` 的快照（`default.store`/`preimport-2202`/`real-store-restore-2202`/`copy-swap-discarded`，都是旧 schema 29 游戏）与 Downloads 备份 JSON。
  3. 当前 store（导入后）29 游戏 createdAt 全部 = 2026-08-17 14:37（导入时刻），行 Z_PK 也重排——确认是导入重建，非原库迁移。
- **教训（§9 已记）**：涉及数据层/导入测试前先把 store 拷快照；「数据不见了」先查 store 文件 birthtime / 对照备份 JSON，别急着怀疑迁移代码。
- **验证**：修复后构建重启 app，读取正常（用户确认）。

### 25.6 其他

- **iOS 构建命令**：`-destination 'platform=iOS Simulator'`（generic 或指定机型都行；iPadOS 27 iPad mini + iOS 18 iPhone 16 模拟器已验证）。
- **验证**：macOS/iOS Debug 构建 exit 0；ScoreMath 15/15、DataSmoke（含状态机断言）、ShareRender 全过；L10n 三语 0 缺失；状态机 + 全局毛玻璃走查用户确认。
- **GitHub 未推**：tag 未打。

## 26. beta 2.0 发布记录（2026-08-17，自动备份 + 清缓存，本轮提交）

> 起因：用户此前在清缓存/版本更新时遭遇「除 SteamGridDB key 外数据全丢」（即 §25.5）。本次按 grill 会话逐项确认后实施（Q1–Q11 全确认，无遗留决策）。

### 26.1 自动备份（两版共用 `Support/AutoBackup.swift`）

- **触发**：挂 `ModelContext.didSave`，任何 `context.save()` 后防抖 3 秒写一次完整备份（覆盖式单文件 `GameLog-autobackup.json`）。退出兜底：macOS `willTerminate`、iOS `didEnterBackground`（`MainActor.assumeIsolated` + `flushNow`，仅 `needsWrite` 时写）。
- **空库保护**（防 §25.5 类事故复发核心）：库为空时不写滚动备份——避免把上一份好备份覆盖成空。版本升级 / 启动 / 恢复各环节都套这层。
- **版本升级前快照**：启动时检测 `backup.lastVersion` 变化 → **先把上次会话留下的滚动备份（升级前数据）复制为 `GameLog-autobackup-pre-<旧版本>.json`**，再刷新启动备份。顺序不能反（先覆盖再复制会把 pre 快照也变成迁移后内容）。保留最近 3 份。
- **恢复/导入前快照**：`AutoBackup.shared.writeSnapshot(context:)` 写带时间戳的 `GameLog-autobackup-snapshot-<yyyyMMdd-HHmmss>.json`（不参与滚动覆盖，可反悔）。手动恢复、手动导入、AirDrop 导入前都调用。
- **空库检测弹窗**：启动时库空 + 备份非空 → `emptyRestoreInfo` 驱动根视图 `AutoBackupContainer` 的 `platformConfirmDialog` 询问「从自动备份恢复 / 保持空库」。
- **文件位置**：macOS = `UserCustomization.supportDirectory`（`~/Library/Application Support/GameLog/`，私有）；**iOS = `Documents/Backups/`**（「文件」App 可见——签名证书过期打不开 app 时仍可取走文件，用户明确要求）。`Info-iOS.plist` 已含 `UIFileSharingEnabled`/`LSSupportsOpeningDocumentsInPlace`。
- **设置页**：备份 section 加「自动备份」开关 + hint、「最后备份：时间/大小」、「立即备份」、「从自动备份恢复…」（带确认弹窗）。元数据存 UserDefaults：`backup.lastBackupDate` / `backup.lastBackupSize` / `backup.lastVersion`。
- **接入**：`GameLogApp` 的 `WindowGroup` 最外层包 `AutoBackupContainer`（`.task` 里 `setup(container:)` + `performStartupCheck`），macOS/iOS 共用。

### 26.2 清缓存（`Support/CacheCleaner.swift` + 设置页「存储与缓存」）

- 显示当前占用 = `URLCache.shared.currentDiskUsage` + 临时目录（`FileManager.enumerator` 按 allocated size 累加）；清除 = `URLCache.removeAllCachedResponses` + `GameCardView.clearCoverCache()`（NSCache）+ `PlatformIconLoader.clearCaches()` + 清空 `temporaryDirectory`。
- **明确不碰**：SwiftData store、封面/照片数据（存模型/独立目录，非缓存）、自动备份文件、UserDefaults（含 API Key）。清除后显示释放字节数。

### 26.3 已验证（本轮）

- macOS/iOS Debug + **Release** 构建 exit 0；ScoreMath 15/15、DataSmoke（96 PASS）、ShareRender 全过；L10n 三语 0 缺失。
- **运行时实测（macOS）**：重启后启动检查落盘 `GameLog-autobackup.json`（28.7MB 含封面照片），`backup.lastBackupDate/Size/Version` 三 key 正确。
- **iOS 模拟器实测（iPhone 16 Pro iOS 27）**：安装新版后启动即写 `Documents/Backups/GameLog-autobackup.json`（28.7MB，21:24 生成）——证明备份代码已随新版安装并运行。
- **⚠️ 模拟器「文件」App 不显示 app Documents**：这是模拟器系统限制（任何 app 都一样），不是配置问题。模拟器取备份走 Finder 路径 `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Data/Application/<container>/Documents/Backups/` 或 `xcrun simctl get_app_container <UDID> com.abcleg.GameLog data`。真机（`UIFileSharingEnabled=true`）正常显示。

### 26.4 本次顺手修复

- `Scripts/DataSmokeTest/main.swift` 与 `Scripts/ShareRenderTest/main.swift` 头注释的编译命令都缺 `GameLog/Support/PlatformImage.swift`（`UserCustomization.swift` 用到 `AppImage`，beta 1.6 后加入），当前代码编译不过。已补上并实测跑通。
- L10n 新增 key（三语全补）：`settings.autoBackup/autoBackupHint`、`backup.lastBackup/backupNow/autobackupRestore/autobackupRestoreConfirm/restoreDone/restoreFailed/snapshotSaved/emptyRestoreTitle/emptyRestoreMessage/restoreNow/keepEmpty/nowDone/noBackupYet`、`settings.storage/cacheSize/cacheClear/cacheClearConfirm/cacheCleared/cacheClearFailed`。

### 26.5 发布记录

- **commit** 见 git log（消息前缀 `beta 2.0：`）；**版本号 `"beta 2.0"`**（pbxproj 4 处）；**DMG** `dist/GameLog-beta-2.0.dmg`（卷名 `GameLog beta 2.0`，含 GameLog.app + Applications 链接，6.8MB，挂载验证版本号 beta 2.0）；**IPA** `dist/GameLog-beta-2.0.ipa`（Release-iphonesimulator universal x86_64+arm64 adhoc，解压验证版本号 beta 2.0 + `_CodeSignature/CodeResources`）。
- **GitHub 未推**：tag 未打。要推：`git tag beta-v2.0 && git push origin main beta-v2.0`（push 需用户凭据，见 §9）。
- **遗留**：iOS 真机（拍照 / AirDrop 导入 / QLPreviewController / PhotosPicker / TabBar）仍未实测——见 §9 ②。
