# GameLog — 我的游戏簿

一个 macOS 个人应用，用来记录你打通关的游戏：封面、四维评分、每次通关的平台/日期/程度/时长/内容，并生成适合发微博或推特的分享图。纯本地存储（SwiftData），数据完全属于你自己。

支持界面语言：**简体中文 / 日本語 / English**（设置里即时切换）。

## 功能

- **游戏库**：网格 / 列表视图切换；按名称 + 别名搜索；按平台筛选；左侧分组侧边栏，分组可新建 / 重命名 / 删除，同一游戏可进多个分组；按名字 / 发售日期 / 通关日期排序。库显示分 = 该游戏所有已评分通关记录平均分的均值，四舍五入到 0.5；未评分显示"未评分"。
- **游戏详情**：评价（一句话标题 + 正文）、所有通关记录、可编辑 / 追加 / 删除；头部显示平均分 + **四维彩色条形图**（剧情 / 画面 / 音乐 / 玩法各一色）；窗口拉宽时评价与通关记录自动并排双栏。
- **四维评分**：剧情 / 画面 / 音乐 / 玩法，1–10、0.1 步进滑块。首条通关记录评分必填，之后的记录可勾选"本次跳过评分"。
- **通关记录**：平台、通关日期、通关程度（主线通关 / 全支线 / 全结局 / 全收集白金 / 多周目 / 速通 / 自定义）、时长、通关内容备注。
- **日期选择**：发售日期与通关日期用三列滚轮（年 / 月 / 日）选择，自动处理闰年 2 月 29 日与月末钳位。
- **封面**：本机选图，或通过 [SteamGridDB](https://www.steamgriddb.com) API 搜索并下载（需在设置里填 API Key）。搜索为即输即搜的补全式（服务端最多返回 10 条），面板可随时关闭，不必选择封面。
- **个性化**：设置里可自定义用户名（20 字内）、用户头像与 app 图标（本机选图 → 裁切面板，支持拖拽平移 + 缩放；头像圆形 256²、图标圆角方形 1024²）。自定义图标即时反映到 Dock 并重启保持；侧边栏与分享图会带上你的头像。
- **分享图**：单选一张游戏 → 单卡（竖版 1080×1920 或横版 1920×1080）；多选 → 一张总览图（标题默认「{用户名}的游戏簿」、可自定义，随游戏数量自动换行）。单卡与总览格显示**最后一次通关日期**；左下角 / 左上角带品牌水印（用户名 + 圆形头像），随语言本地化。配色跟随系统深浅色，可保存 PNG 或调起系统分享。
- **统计**：通关总数、库平均分、按平台分布（窗口拉宽时自动排两列）。
- **备份**：整个库导出为单个 JSON（封面以 base64 内嵌），用户名 / 头像 / 图标一并导出、可整体还原，兼容旧版备份；导入带确认弹窗。

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
├── Support/                 # 评分逻辑、备份、三项自定义、语言环境、L10n、SteamGridDB 客户端
├── Share/                   # 分享卡视图 + ImageRenderer 出图管线
├── Views/                   # 侧边栏 / 库 / 详情 / 编辑 / 统计 / 设置 / 分享面板 / 封面搜索 / 日期滚轮 / 图片裁切
└── Resources/               # 三语 Localizable.strings（zh-Hans / ja / en）+ Assets.xcassets（app 图标）
Scripts/                     # 独立回归测试（不编进 app，见下）
```

## 开发验证

`Scripts/` 下有可重复运行的独立回归测试（用 `xcrun swiftc` 编译，宏插件路径见各文件头注释）：

- `Scripts/ScoreMathSelftest/` — 评分逻辑自检（四舍五入 / 均值 / 库显示分）
- `Scripts/DataSmokeTest/` — 数据层冒烟：多对多关系、级联删除、评分集成、备份往返、导入幂等与替换、日期保真、预设本地化
- `Scripts/ShareRenderTest/` — 分享卡渲染管线：真实调用 ImageRenderer 出 PNG 校验像素尺寸

新增 UI 文案时，key 必须同时进三个 `Localizable.strings`，并统一用 `L10n.tr` / `LText`（勿用 `String(localized:)`）。改完跑一次 key 覆盖检查，三语必须 0 缺失：

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

## 术语约定

项目领域术语（Game / Completion / Group / Review / Dimension Scores…）以 `CONTEXT.md` 的词表为准，开发时避免混用。

## License

本项目基于 [MIT](LICENSE) 许可证发布，详见仓库根目录的 `LICENSE` 文件。
