# 我的游戏簿（My Gamelog）

> [English](README.en.md) · [日本語](README.ja.md) · **简体中文**

一个 **macOS + iOS** 个人应用，用来记录你打通关的游戏：封面、六维评分、每次通关的平台 / 日期 / 程度 / 时长 / 内容、实体收藏（版本 / 数量 / 照片），并生成适合分享的图片。纯本地存储（SwiftData），数据完全属于你自己。

支持界面语言：**简体中文 / 日本語 / English**（设置里即时切换）。macOS 与 iOS 各自本地独立存储，可通过 JSON 备份互通（含 AirDrop）。

## 功能

- **游戏库**：网格 / 列表视图切换；按名称 + 别名 + 多语言名搜索；按平台筛选；分组管理（macOS 侧边栏 / iOS 筛选菜单），同一游戏可进多个分组；按名字 / 发售日期 / 通关日期 / 平均分（从低到高 / 从高到低）排序。库显示分 = 该游戏所有已评分通关记录平均分的均值，取整到 0.1；未评分显示「未评分」。
- **游戏详情**：评价（一句话标题 + 正文）、所有通关记录（可编辑 / 追加 / 删除）、六维彩色条形图；收藏家模式开启后多一个「持有」页签。
- **六维评分**：玩法 / 设计 / 剧情 / 美术 / 音乐 / 性能，1–10、0.1 步进滑块。整体 = 六维均值；首条通关记录评分必填，之后的记录可勾选跳过评分。
- **通关记录**：平台、通关日期（可「无」）、通关程度（主线通关 / 全支线 / 全结局 / 全收集白金 / 多周目 / 速通 / 自定义）、时长（可「无」）、通关内容备注。
- **日期选择**：macOS 三列滚轮（年 / 月 / 日，自动处理闰年 2 月 29 日与月末钳位）；iOS 用系统日期选择器。
- **分组**：新建 / 重命名 / 删除；右键（macOS）或菜单（iOS）选择游戏加入；分组统计与分组评价。
- **收藏家模式**（设置开关）：详情页「详情 / 持有」分段切换；每个游戏可有多个持有版本（版本名 + 数量 + 最多 6 张照片）；照片用系统查看器查看；随备份导出。
- **封面**：本地选图，或通过 [SteamGridDB](https://www.steamgriddb.com) API 搜索下载（需在设置里填 API Key，即输即搜）；可开启**自动匹配封面**（输入名字停顿约 0.6 秒自动取第一条命中的竖版封面，不覆盖已有封面，失败静默）；搜索结果带封面缩略图。iOS 上选图弹出「相册 / 文件 / 拍照」菜单。
- **个性化**：用户名（20 字）、头像（圆形裁切）、macOS app 图标（圆角方形裁切）、自动匹配封面开关、隐藏分组毛玻璃（macOS）、保存原图开关、平台标志开关（默认开启；关闭后各平台不显示品牌 logo 图标）。自定义图标即时反映到 Dock 并重启保持。
- **分享图**：单选游戏 → 单卡（竖版 1080×1920 或横版 1920×1080）；多选 → 一张总览图；按分组 → 分组分享卡（含组内游戏封面格与平台分布）。带品牌水印，随语言本地化，可保存 PNG 或调起系统分享；iOS 上可一键「保存到相册」（需照片添加权限）。
- **统计与排行榜**：通关总数、库平均分、按平台分布；平均分榜 + 六维榜（各维度前 5 / 10）；「整体排名」页顶部切换 7 个榜单、每页最多 100 条翻页、按平台过滤。
- **备份**：整个库导出为单个 JSON（封面以 base64 内嵌），用户名 / 头像 / 图标一并导出、可整体还原，兼容旧版备份；导入带确认弹窗。iOS 导出走系统分享单（AirDrop / 存储到文件等）。

## 平台

| 平台 | 部署目标 | 说明 |
|---|---|---|
| macOS | 14.0+ | 完整功能：侧边栏、右键菜单、窗口工具栏、自定义 Dock 图标等 |
| iOS | 18.0+（iPhone / iPad） | 底部 TabBar（库 / 统计 / 设置）；筛选菜单、加图菜单、确认弹窗等按 iOS 设计规范适配 |

## 环境要求

- macOS 14.0+；iOS 18.0+（iPhone / iPad）
- Xcode 16+（含 SwiftData / Swift 宏支持；工程经 Xcode 27 beta 验证）

## 构建与运行

```bash
cd /Users/abc/Documents/gamelog_program

# macOS 构建 + 启动
xcodebuild -project GameLog.xcodeproj -scheme GameLog -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/GameLogDD build
open /tmp/GameLogDD/Build/Products/Debug/GameLog.app

# iOS 模拟器构建 + 安装 + 启动
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -project GameLog.xcodeproj -scheme GameLog-iOS -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /tmp/GameLogDD build
xcrun simctl install booted /tmp/GameLogDD/Build/Products/Debug-iphonesimulator/GameLog.app
xcrun simctl launch booted com.abcleg.GameLog
```

或在 Xcode 中打开 `GameLog.xcodeproj`，选 `GameLog`（macOS）或 `GameLog-iOS`（iOS）scheme 直接 Run。

## 在 iPhone 上安装（IPA）

本仓库提供 Release 版 IPA（`dist/GameLog-beta-1.8.ipa`），未签名，需自行签名后安装。

> 提示：模拟器或日常开发调试直接用 Xcode Run 即可，不需要 IPA。

## 试用 Demo 数据

仓库附带一份生成的演示数据（[GameLog-demo-backup.json](GameLog-demo-backup.json)），可用于演示本 app 的功能：50 款游戏（中 / 英 / 日名 + 发售日期）、105 条通关记录（平台分布 Nintendo Switch 2 / PS5 / Xbox Series X|S / PC，含向下兼容痕迹）、六维评分、9 个分组。

导入方法：

1. iOS：把 JSON 放进「文件」app；macOS：放到本地
2. 打开 app → 设置 → 备份 → **导入** → 选择该文件 → 确定

注意：导入会替换当前数据。

## 使用 SteamGridDB 封面搜索

1. 到 [steamgriddb.com](https://www.steamgriddb.com) 免费注册，从个人页面获取 API Key。
2. 打开 app 设置 → SteamGridDB → 填入 Key（Key 栏可显示/隐藏、一键复制、改动时自动校验「✓ 有效 / ✗ 无效」）。
3. 新建 / 编辑游戏时点「搜索封面…」。

## 项目结构

```
GameLog/
├── GameLogApp.swift       # macOS 入口：WindowGroup + Settings 场景共享 ModelContainer
├── iOSRootView.swift      # iOS 入口：底部 TabBar（库 / 统计 / 设置）+ AirDrop 备份导入
├── Models/                # SwiftData 模型（Game / Completion / GameGroup / PhysicalCopy / Presets）
├── Support/               # 平台抽象 PlatformImage、评分逻辑、备份、个性化、L10n、SteamGridDB、
│                          #   PlatformIcon（平台图标）、PlatformButton（跨平台按钮样式）、
│                          #   PlatformConfirmDialog（底部 action sheet）、ImageSourcePicker（加图菜单）
├── Share/                 # 分享卡视图 + ImageRenderer 出图管线
├── Views/                 # 各平台视图（共享 + #if os 适配）
└── Resources/             # 三语 Localizable.strings + Assets.xcassets（macOS/iOS AppIcon）
                           #   + PlatformIcons（平台 logo 资源）+ Info-iOS.plist
Scripts/                   # 独立回归测试（不编进 app，见下）
```

## 开发验证

`Scripts/` 下有可重复运行的独立回归测试（用 `xcrun swiftc` 编译，宏插件路径见各文件头注释）：

- `Scripts/ScoreMathSelftest/` — 评分逻辑自检（取整 / 均值 / 库显示分）
- `Scripts/DataSmokeTest/` — 数据层冒烟：多对多关系、级联删除、评分集成、备份往返、导入幂等与替换、持有记录备份、日期保真、预设本地化
- `Scripts/ShareRenderTest/` — 分享卡渲染管线：真实调用 ImageRenderer 出 PNG 校验像素尺寸

新增 UI 文案时，key 必须同时进三个 `Localizable.strings`，并统一用 `L10n.tr` / `LText`（勿用 `String(localized:)`）。改完跑一次 key 覆盖检查，三语必须 0 缺失（检查命令见 HANDOVER.md §2）。

## 术语约定

项目领域术语（Game / Completion / Group / Review / Dimension Scores…）以 `CONTEXT.md` 的词表为准，开发时避免混用。

## License

本项目基于 [MIT](LICENSE) 许可证发布，详见仓库根目录的 `LICENSE` 文件。
