# GameLog — 游戏通关记录

一个 macOS 个人应用，用来记录你打通关的游戏：封面、四维评分、每次通关的平台/日期/程度/时长/内容，并生成适合发微博或推特的分享图。纯本地存储（SwiftData），数据完全属于你自己。

支持界面语言：**简体中文 / 日本語 / English**（设置里即时切换）。

## 功能

- **游戏库**：网格 / 列表视图切换；按名称 + 别名搜索；按平台筛选；自定义分组（可重命名 / 删除，同一游戏可进多个分组）；按名字 / 发售日期 / 通关日期排序。库显示分 = 该游戏所有已评分通关记录平均分的均值，四舍五入到 0.5；未评分显示"未评分"。
- **游戏详情**：评价（一句话标题 + 正文）、所有通关记录、可编辑 / 追加 / 删除。
- **四维评分**：剧情 / 画面 / 音乐 / 玩法，1–10、0.1 步进滑块。首条通关记录评分必填，之后的记录可勾选"本次跳过评分"。
- **通关记录**：平台、通关日期、通关程度（主线通关 / 全支线 / 全结局 / 全收集白金 / 多周目 / 速通 / 自定义）、时长、通关内容备注。
- **封面**：本机选图，或通过 [SteamGridDB](https://www.steamgriddb.com) API 按名字搜索并下载（需在设置里填 API Key）。
- **分享图**：单选一张游戏 → 单卡（竖版 1080×1920 或横版 1920×1080）；多选 → 一张总览图（标题可自定义，随游戏数量自动换行）。配色跟随系统深浅色，可保存 PNG 或调起系统分享。
- **统计**：通关总数、库平均分、按平台分布。
- **备份**：整个库导出为单个 JSON（封面以 base64 内嵌），可整体导入替换，带确认弹窗。

## 环境要求

- macOS 14.0 及以上
- Xcode 16+（含 SwiftData / Swift 宏支持；工程经 Xcode 26.x 验证）

## 构建与运行

```bash
cd /Users/abc/Documents/gamelog_program
# 完整构建（-derivedDataPath 用 /tmp，避免污染默认缓存）
xcodebuild -project GameLog.xcodeproj -scheme GameLog -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/GameLogDD build
# 启动
open /tmp/GameLogDD/Build/Products/Debug/GameLog.app
```

或在 Xcode 中打开 `GameLog.xcodeproj`，选 `GameLog` scheme 直接 Run。

## 使用 SteamGridDB 封面搜索

1. 到 [steamgriddb.com](https://www.steamgriddb.com) 免费注册，从个人页面获取 API Key。
2. 打开 app 设置 → SteamGridDB → 填入 Key。
3. 新建 / 编辑游戏时点"搜索封面…"。

## 项目结构

```
GameLog/
├── GameLogApp.swift         # 入口：WindowGroup + Settings 两个场景共享同一 ModelContainer
├── Models/                  # SwiftData 模型（Game / Completion / GameGroup / Presets）
├── Support/                 # 评分逻辑、备份、语言环境、L10n、SteamGridDB 客户端
├── Share/                   # 分享卡视图 + ImageRenderer 出图管线
├── Views/                   # 库 / 详情 / 编辑 / 统计 / 设置 / 分享面板 / 封面搜索
└── Resources/               # 三语 Localizable.strings（zh-Hans / ja / en）
Scripts/                     # 独立回归测试（不编进 app，见下）
```

## 开发验证

`Scripts/` 下有可重复运行的独立回归测试（用 `xcrun swiftc` 编译，宏插件路径见各文件头注释）：

- `Scripts/ScoreMathSelftest/` — 评分逻辑自检（四舍五入 / 均值 / 库显示分）
- `Scripts/DataSmokeTest/` — 数据层冒烟：多对多关系、级联删除、评分集成、备份往返、导入幂等与替换、日期保真、预设本地化
- `Scripts/ShareRenderTest/` — 分享卡渲染管线：真实调用 ImageRenderer 出 PNG 校验像素尺寸

新增 UI 文案时，key 必须同时进三个 `Localizable.strings`，并统一用 `L10n.tr` / `LText`（勿用 `String(localized:)`）。

## 术语约定

项目领域术语（Game / Completion / Group / Review / Dimension Scores…）以 `CONTEXT.md` 的词表为准，开发时避免混用。

## License

本项目基于 [MIT](LICENSE) 许可证发布，详见仓库根目录的 `LICENSE` 文件。
