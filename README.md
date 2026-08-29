# 我的游戏簿（My Gamelog）

> [English](README.en.md) · [日本語](README.ja.md) · **简体中文**

一个 **macOS + iOS** 个人应用，用来记录你的游戏库与通关经历：想玩 / 在玩 / 已通关等状态、封面、六维评分、每次通关的平台 / 日期 / 程度 / 时长 / 内容、实体收藏（版本 / 数量 / 照片），并生成适合分享的图片。纯本地存储（SwiftData），数据完全属于你自己。

支持界面语言：**简体中文 / 日本語 / English**（设置里即时切换）。macOS 与 iOS 各自本地独立存储，可通过 JSON 备份互通（含 AirDrop）。

## 功能

- **游戏库**：按名称 + 别名 + 多语言名搜索；按状态 / 平台 / 分组筛选；分组管理（macOS 侧边栏 / iOS 筛选菜单），同一游戏可进多个分组；排序支持：名字 / 发售日期 / 通关日期 / 平均分（从低到高 / 从高到低）/ **最近编辑** / **价值最高**，默认按「最近编辑」。库显示分 = 该游戏所有已评分通关记录平均分的均值，取整到 0.1；未评分显示「未评分」。
- **视图（分端设计）**：**macOS** 网格 / 列表切换 + 侧边栏；**iOS** 三选一视图——网格 / **单列横向卡**（左侧方形封面满卡高上下贴边铺图，无方图时竖版封面等高居中；玻璃材质圆角卡底 + 细描边 + 投影，封面右上角液态玻璃评分胶囊，右列为标题 + 平台 + 元数据文字区）/ 列表，选择跨会话记忆并从旧偏好自动迁移。
- **游戏状态**：想玩 / 在玩 / 搁置 / 弃坑 / 已通关 / 长线游玩 六状态；非已通关状态无需通关记录与评分，流转到「已通关」或「长线游玩」时才挂记录；库按状态筛选、详情页液态玻璃滑块选择器（双平台统一在分数区下方）；未通关游戏也有游戏级平台，参与平台筛选与统计。
- **游戏详情**：评价区（一句话 tagline 引言 + 长评正文）、所有通关记录（可编辑 / 追加 / 删除）、六维彩色条形图；厂商 / 发行商 / 游戏类型三可选字段；收藏家模式开启后多一个「持有」页签。**iOS 标题词边界断行**：大标题按 NLTokenizer 分词，换行只落在词边界，不再出现「死神的遺|言」式硬折行。
- **详情页头部（分端设计）**：**macOS** 宽窗走「封面顶带 + 信息列 + 玻璃评分卡」布局，缩窗自动回落单列；可设背景图横幅（完整无裁切、顶贴页面、宽度铺满、高度随窗与源图比例联动）+ Logo（透明 PNG，大小 / 垂直 / 水平三档 ×三档按游戏微调，与封面锁死等比联动）。**iOS** 设了横版封面时改走满宽横幅版式（顶贴导航栏、按源图比例定高、上限 260pt 不裁切），没设则完全保持原版式。
- **评价（Markdown 长评）**：一句话评价（tagline）作为大号引言「题眼」展示；长评正文支持 Markdown 子集（标题 `#` / 加粗 `**` / 斜体 `*` / 列表 `-`），像排版考究的文章。**macOS = 富文本所见即所得编辑器**（独立「写字台」窗口，工具条直接改样式，存盘转回 Markdown；中文斜体在绘制层合成倾斜）；**iOS = 编辑 sheet（TextEditor）**。分端编辑、共享同一份 Markdown 渲染，双端观感一致。
- **六维评分**：玩法 / 设计 / 剧情 / 美术 / 音乐 / 性能，1–10、0.1 步进滑块。整体 = 六维均值；首条通关记录评分必填，之后的记录可勾选跳过评分。
- **通关记录**：平台、通关日期（可「无」）、通关程度（主线通关 / 全支线 / 全结局 / 全收集白金 / 多周目 / 速通 / 自定义）、时长（可「无」）、通关内容备注。
- **日期选择**：macOS 三列滚轮（年 / 月 / 日，自动处理闰年 2 月 29 日与月末钳位）；iOS 用系统日期选择器。
- **分组**：新建 / 重命名 / 删除；右键（macOS）或菜单（iOS）选择游戏加入；分组统计与分组评价（Markdown 渲染，macOS 可用「写字台」编辑）。
- **收藏家模式**（设置开关）：详情页「详情 / 持有」分段切换；每个游戏可有多个持有版本（介质 11 档 / 地区 10 档 / 品相 7 档 / 来源 11 档 / 三语价格与估值 / 购买日 / 备注 + 最多 6 张照片），构成**藏品档案**。新建游戏默认**不**建持有档案，须勾选才展开填写并建档。持有页支持网格 / 列表双视图、顶部总览（版本数 / 总数量 / 总花费 / 总估值）、胶囊式元数据展示、完整编辑弹窗；照片用系统查看器查看；随备份导出。
- **封面与图像**：本地选图（iOS 弹「相册 / 文件 / 拍照」菜单），或通过 [SteamGridDB](https://www.steamgriddb.com) API 搜索下载（需在设置里填 API Key，即输即搜）；五类图各配**自动匹配**开关（竖版封面 / 方形封面 / 横版封面 / 背景图 / Logo，输入名字停顿约 0.6 秒自动取首条命中，不覆盖已有图，失败静默；改名也会触发补抓）；方形封面只出 1:1 结果（512×512 与 1024×1024 两档都搜）；搜索面板按图类区分文案并预填当前游戏英文名；搜索结果带缩略图。
- **个性化**：用户名（20 字）、头像（圆形裁切）、macOS app 图标（圆角方形裁切）、自动匹配封面开关、隐藏上方毛玻璃（macOS 15+）、保存原图开关、平台标志开关（默认开启；关闭后各平台不显示品牌 logo 图标）。自定义图标即时反映到 Dock 并重启保持。
- **分享图（beta 2.4 全面重做）**：品牌化固定深色视觉——暖调近黑底 + 琥珀橙强调；预览面板本身跟随系统明暗（2026-08-27 调整）。三种卡型：
  - **单卡**：模糊封面垫底 + 清晰海报满框（贴合封面真实比例，SteamGridDB 竖版 2:3 无留白）；信息面板含游戏名 / 平台 / 发售年 / 通关程度胶囊 / 一句话评价（金色）/ 六维迷你条形 / 大字库分；未通关显示彩色状态大徽章。
  - **总览图**：头部汇总行与游戏格子字段均可在「样式设置」里勾选排序（汇总：款数 / 平均分 / 通关总数 / 收藏价值；格子：平台 / 评分 / 最近通关 / 发售年 / 状态标签），列数随数量自适应，画布随内容拉高。
  - **分组卡**：标题 + 一句话分组评价引言 + 统计要素（均分 / 游戏数 / 通关数 / 最高分游戏 / 收藏价值，可勾选排序）+ 平台分布条 + 组内封面格；手机 / 桌面两套布局。
  - 「样式设置」统一配置上述三个要素池，总览格与分组卡格共用同一份格子字段配置；导出格式 JPEG（默认）/ PNG 可选，文件名自动带游戏 / 分组名；iOS 点预览全屏看大图、一键保存到相册（需照片添加权限）；水印（用户名·游戏簿 + 头像）随语言本地化。
- **统计与排行榜**：通关总数、库平均分（含想玩数）、按平台分布、收藏价值（收藏家模式开启时显示版本数 / 总数量 / 总花费 / 总估值）；平均分榜 + 六维榜（各维度前 5 / 10）；「整体排名」页顶部在**分数榜 / 价值榜**之间切换——分数榜含平均分与六维共 7 个榜单，价值榜含「按游戏价值 / 按机器（平台）价值 / 按分组价值」三页，每页最多 100 条翻页、可按平台过滤。
- **备份**：整个库导出为单个 JSON（封面以 base64 内嵌），用户名 / 头像 / 图标一并导出、可整体还原，兼容旧版备份；导入带确认弹窗。iOS 导出走系统分享单（AirDrop / 存储到文件等），导出文件名带时间戳。
- **自动备份**：每次数据改动后自动在本地写完整备份（覆盖式单文件）；版本升级前自动留存旧版快照；库为空但备份有数据时启动弹窗询问恢复；恢复 / 导入前自动留快照可反悔。iOS 备份存 Documents/Backups（「文件」App 可见），签名过期等打不开 app 时也能取走文件。
- **清除缓存**：设置 → 存储与缓存 显示当前缓存占用并可一键清除（封面/图片解码缓存、网络缓存、临时文件），不影响任何游戏数据与备份。

## 平台

| 平台 | 部署目标 | 说明 |
|---|---|---|
| macOS | 14.0+ | 完整功能：侧边栏、右键菜单、窗口工具栏、自定义 Dock 图标、写字台评价编辑器等 |
| iOS | 18.0+（iPhone / iPad） | 底部 TabBar（库 / 统计 / 设置）；三态库视图、筛选菜单、加图菜单、底部 action sheet 确认等按 iOS 设计规范适配 |

## 环境要求

- macOS 14.0+；iOS 18.0+（iPhone / iPad）
- **Xcode 27 beta**（工程依赖 macOS 27 / iOS 27 SDK 与模拟器运行时，构建用 `/Users/abc/Downloads/Xcode-beta.app`）

## 构建与运行

```bash
cd /Users/abc/Documents/gamelog_program

# macOS 构建 + 启动（macOS 27 beta 必须用 beta Xcode）
DEVELOPER_DIR=/Users/abc/Downloads/Xcode-beta.app/Contents/Developer \
xcodebuild -project GameLog.xcodeproj -scheme GameLog -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/GameLogDD-mac build
open /tmp/GameLogDD-mac/Build/Products/Debug/GameLog.app

# iOS 模拟器构建 + 安装 + 启动
DEVELOPER_DIR=/Users/abc/Downloads/Xcode-beta.app/Contents/Developer \
xcodebuild -project GameLog.xcodeproj -scheme GameLog-iOS -configuration Debug \
  -destination 'platform=iOS Simulator' -derivedDataPath /tmp/GameLogDD-ios build
xcrun simctl install booted /tmp/GameLogDD-ios/Build/Products/Debug-iphonesimulator/GameLog.app
xcrun simctl launch booted com.abcleg.GameLog
```

或在 Xcode 中打开 `GameLog.xcodeproj`，选 `GameLog`（macOS）或 `GameLog-iOS`（iOS）scheme 直接 Run。

## 在 iPhone 上安装（IPA）

本仓库提供一份真机用 Release IPA（`dist/`），未签名，需自行签名（eSign 等工具）后安装：

- `GameLog-beta-2.6.ipa` — 真机 arm64 无签名包，适合用 eSign 等工具重签后装机

> 提示：模拟器与日常开发调试直接用 Xcode Run 即可，不出也不需要模拟器 IPA；macOS 直接用 DMG 安装。

## 试用 Demo 数据

仓库附带一份生成的演示数据（[GameLog-demo-backup.json](GameLog-demo-backup.json)），可用于演示本 app 的功能：50 款游戏（中 / 英 / 日名 + 发售日期）、105 条通关记录（平台分布 Nintendo Switch 2 / PS5 / Xbox Series X|S / PC，含向下兼容痕迹）、六维评分、9 个分组。

导入方法：

1. iOS：把 JSON 放进「文件」app；macOS：放到本地
2. 打开 app → 设置 → 备份 → **导入** → 选择该文件 → 确定

注意：导入会替换当前数据。

## 使用 SteamGridDB 封面搜索

1. 到 [steamgriddb.com](https://www.steamgriddb.com) 免费注册，从个人页面获取 API Key。
2. 打开 app 设置 → SteamGridDB → 填入 Key（Key 栏可显示/隐藏、一键复制、改动时自动校验「✓ 有效 / ✗ 无效」）。
3. 新建 / 编辑游戏时点对应图类的「搜索…」按钮（竖版封面 / 方形封面 / 横版封面 / 背景图 / Logo 各自入口）。

## 项目结构

```
GameLog/
├── GameLogApp.swift       # macOS 入口：WindowGroup + Settings/About/写字台 场景共享 ModelContainer
├── iOSRootView.swift      # iOS 入口：底部 TabBar（库 / 统计 / 设置）+ AirDrop 备份导入
├── Models/                # SwiftData 模型（Game / Completion / GameGroup / PhysicalCopy / Presets）
├── Support/               # 平台抽象 PlatformImage、评分逻辑 ScoreMath、备份 ExportImport/AutoBackup、
│                          #   个性化 UserCustomization、L10n、SteamGridDB、PriceFormat、
│                          #   PlatformIcon（平台图标）、PlatformButton（跨平台按钮样式）、
│                          #   PlatformConfirmDialog（底部 action sheet）、ImageSourcePicker（加图菜单）、
│                          #   DocumentPicker（iOS 文件选择）、ShareSheetPresenter（iOS 系统分享单）、
│                          #   MarkdownReview（Markdown 解析/渲染）、MarkdownRichEditor（macOS 写字台）
├── Share/                 # 分享卡视图（三种卡型 + 要素池配置）+ ImageRenderer 出图管线
├── Views/                 # 各平台视图（共享 + #if os 适配）
└── Resources/             # 三语 Localizable.strings + Assets.xcassets（macOS/iOS AppIcon）
                           #   + PlatformIcons（平台 logo 资源）+ Info-iOS.plist
Scripts/                   # 独立回归测试（不编进 app，见下）
```

## 开发验证

`Scripts/` 下有可重复运行的独立回归测试（用 beta Xcode 工具链 `swiftc` 编译，宏插件路径见各文件头注释）：

- `Scripts/ScoreMathSelftest/` — 评分逻辑自检（取整 / 均值 / 库显示分）
- `Scripts/DataSmokeTest/` — 数据层冒烟：多对多关系、级联删除、评分集成、备份往返、导入幂等与替换、持有档案迁移与备份、日期保真、预设本地化
- `Scripts/ShareRenderTest/` — 分享卡渲染管线：真实调用 ImageRenderer 出 PNG 校验尺寸 / 列数 / JPEG 编码 / 要素池配置往返
- `Scripts/RichReviewTest/` — 评价编辑器核心不变式：Markdown → 富文本 → Markdown 往返逐字守恒

新增 UI 文案时，key 必须同时进三个 `Localizable.strings`，并统一用 `L10n.tr` / `LText`（勿用 `String(localized:)`）。改完跑一次 key 覆盖检查，三语必须 0 缺失（检查命令见 HANDOVER.md §2）。

## 术语约定

项目领域术语（Game / Completion / Group / Review / Dimension Scores…）以 `CONTEXT.md` 的词表为准，开发时避免混用。

## License

本项目基于 [MIT](LICENSE) 许可证发布，详见仓库根目录的 `LICENSE` 文件。
