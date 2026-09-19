# 我的游戏簿（My Gamelog）

<p align="center">
  <img src="appcover.PNG" alt="My Gamelog Cover" width="100%" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" />
</p>

<p align="center">
  <strong>专为游戏玩家打造的个人游戏库与通关历程管理应用</strong>
  <br />
  纯本地存储 · 原生交互 · 实体收藏 · 外部账号同步 · 精美分享卡
</p>

<p align="center">
  <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a> · <strong>简体中文</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B%20%7C%20iOS%2018.0%2B-blue?style=flat-square" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-5.10%20%2F%206.0-orange?style=flat-square" alt="Swift" />
  <img src="https://img.shields.io/badge/SwiftUI-SwiftData-purple?style=flat-square" alt="SwiftUI + SwiftData" />
  <img src="https://img.shields.io/badge/Version-beta%203.2-amber?style=flat-square" alt="Version" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License" />
</p>

---

## 🌟 核心特色

### 🎮 游戏库与沉浸式浏览
- **全方位检索与管理**：支持游戏原名、多语言译名及自定义别名即时搜索；可按状态、平台、分组多维度精准筛选。
- **丰富的排序规则**：支持按名称、发售日期、通关日期、评分高低、**最近编辑**及**收藏价值**自由排序。
- **首页精彩轮播（五页画卷）**：
  1. **个性化横幅**：展示自定义标题、签名、背景图与个人头像；
  2. **随机探索**：全库随机漫游一款游戏，支持全幅横屏封面与即时再随机；
  3. **我的最爱**：专属特写置顶，快速重温心头挚爱；
  4. **全库速览**：可视化展示通关总数、平均分与六种状态分布；
  5. **收藏家概览**：快速统计藏品总版本数、数量、总花费与当前估值。
- **多元视图模式**：提供标准海报网格、紧凑列表、**方形封面网格**以及**极简纯图模式**，契合不同审美偏好。

### 🏆 通关记录与多维评分
- **完整流转状态**：想玩、在玩、搁置、弃坑、已通关、长线游玩等 6 种状态自由流转。
- **详尽通关档案**：每次通关均可独立记录平台、日期、通关程度（主线、全结局、白金全收集、速通等）、游玩时长及通关内容。
- **维度评分体系**：提供玩法、设计、剧情、美术、音乐、性能六大维度的 1–10 分细致打分，自动计算综合平均分与专属彩色维度条形图。
- **Markdown 长篇评测**：支持一句话点睛评语（Tagline）与富文本评测正文（标题、加粗、斜体、列表）。macOS 端提供独立“写字台”沉浸式编辑器。

### 🔗 外部账号游玩数据同步（实验性）
- **三大主流平台互联**：支持绑定 **Nintendo Account**、**PlayStation Network** 及 **Xbox Live**。
- **自动抓取游玩事实**：自动同步任天堂首次/最近游玩日期与时长、PlayStation 奖杯进度（白金/金/银/铜）、Xbox 成就数与 Gamerscore。
- **智能关联与合并**：同步记录可自动对齐本地游戏库，支持手动关联、条目合并或设置规则忽略。
- **详情页来源卡**：游戏详情页内嵌专属来源卡（奖杯卡、成就卡、游玩记录卡），直观呈现官方游玩痕迹。

### 📦 实体藏品档案（收藏家模式）
- **专为实体玩家定制**：在游戏详情页一键开启「持有」档案，专为实体卡带、光盘、典藏版管理打造。
- **多维度版本参数**：细致记录介质类型（标准版、限定版、铁盒、兑换码等）、发行地区（日版、美版、欧版、港台等）、品相状态、购入渠道及入手价格/当前估值。
- **实物照片图鉴**：支持为每份藏品上传多张实拍照片，随时在设备上翻阅真机开箱与收藏品鉴。
- **藏品价值统计**：自动统计全库实体版本总数、藏品总支出与资产总估值。

### 🎨 典雅品牌分享卡生成
- **深色美学视觉**：采用暖调近黑底色搭配品牌琥珀橙强调，带来杂志封面般的导出质感。
- **三种分享版式**：
  - **单游戏海报卡**：电影海报级构图，融合封面虚化底色、通关程度胶囊、金色评语与维度条形图；
  - **综合总览图**：随游戏数量自适应列数排布，支持自由配置与排序表头汇总要素与格子字段；
  - **系列分组卡**：专为游戏系列或专题定制，整合分组长评、系列均分、平台分布与游戏矩阵。
- **灵活导出**：支持手机（9:16）与桌面（16:9）规格，提供 JPEG 与 PNG 无损格式，iOS 支持一键保存至系统相册。

### 🛡️ 绝对隐私与纯本地存储
- **零外部服务器**：无账号体系、无数据上传，所有游戏数据均通过 SwiftData 存储在本地设备中。
- **凭证仅进 Keychain**：第三方平台登录凭证与 Token 仅安全驻留于系统钥匙串（Keychain），严禁进入数据库、备份文件或日志。
- **完备的自动化备份**：数据变动时自动在本地保留滚动作业备份；支持单文件完整 JSON 导出导入与 AirDrop 跨端无缝迁移。

---

## 💻 跨平台原生体验

| 平台 | 最低系统 | 原生专属体验 |
|---|---|---|
| **macOS** | macOS 14.0+ | 三栏侧边栏、右键上下文菜单、快捷键系统、写字台 Markdown 编辑器、独立「关联设置」窗口（⌘⇧,）、自定义 Dock 图标即时生效。 |
| **iOS** | iOS 18.0+ | 原生 TabBar 导航、单列单手操作横向大卡、标题词边界智能断行（防止断词）、原生分享单与相机/相册即时录入。 |
| **iPadOS** | iPadOS 18.0+ | 双列宽屏大卡展示、横竖屏自适应分栏、横屏 Hero 满幅画卷布局。 |

---

## 🚀 快速上手与安装

### 1. 安装应用

#### macOS
- 从 Release 页面下载 `GameLog-beta-3.3.dmg`，打开并将 `GameLog.app` 拖入 `Applications` 文件夹即可。

#### iOS / iPadOS（无签名 IPA）
- 从 `dist/` 目录获取 `GameLog-beta-3.3.ipa`（arm64 真机包）。
- 使用自身证书及工具（如 TrollStore、eSign、AltStore、SideStore 等）重签后安装至真机。

### 2. 导入演示数据（体验 Demo）
本仓库根目录附带一份官方演示数据 [GameLog-demo-backup.json](GameLog-demo-backup.json)，包含 50 款经典游戏（涵盖中/英/日多语言）、105 条真实通关记录、维度评分及分组范例。

- **导入方式**：打开应用 → 进入**「关联设置」**（macOS 快捷键 `⌘⇧,`；iOS 底部「关联」页签）→ **数据备份** → **导入备份…** → 选择该 JSON 文件即可一键载入。

### 3. 配置 SteamGridDB 高清封面搜索
1. 前往 [steamgriddb.com](https://www.steamgriddb.com) 免费注册并从个人页面获取 API Key；
2. 打开应用内的**「关联设置」** → **SteamGridDB** → 填入 API Key（自动校验有效性）；
3. 在新建或编辑游戏时，点击封面旁边的**「搜索…」**按钮，即可即搜即用，一键匹配竖版海报、方形图标、横版横幅与游戏透明 Logo。

---

## 🛠️ 开发者指南

### 环境需求
- **macOS 14.0+** / **iOS 18.0+**
- **Xcode 27 beta**（依赖 macOS 27 / iOS 27 SDK）

### 编译与构建

```bash
cd /Users/abc/Documents/gamelog_program

# 设置 Xcode beta 开发目录
export DEVELOPER_DIR=/Users/abc/Downloads/Xcode-beta.app/Contents/Developer

# ① 构建 macOS Debug 版本
xcodebuild -project GameLog.xcodeproj -scheme GameLog -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/GameLogDD-mac build

# ② 构建 iOS 模拟器 Debug 版本
xcodebuild -project GameLog.xcodeproj -scheme GameLog-iOS -configuration Debug \
  -destination 'id=9908C070-47ED-455C-8427-4ED9177591B4' -derivedDataPath /tmp/GameLogDD-ios build
```

### 独立回归测试集
本项目内置了 5 套完备的离线自动化测试套件（位于 `Scripts/`，无需网络直连）：

- `Scripts/ScoreMathSelftest/`：评分算法、四舍五入与库均分运算自检（16 项）；
- `Scripts/DataSmokeTest/`：数据持久层、模型级联关系、外部账号导入匹配与备份解析冒烟（753 项全自动化断言）；
- `Scripts/KeychainSelftest/`：系统钥匙串安全隔离与解绑擦除自检（17 项）；
- `Scripts/ShareRenderTest/`：图片渲染器 ImageRenderer 真实出图尺寸与要素池编排校验（25 项）；
- `Scripts/RichReviewTest/`：Markdown 与富文本写字台双向互转保真度检验。

---

## 📖 术语规范

本项目遵循统一的领域模型词汇表，具体参见 [CONTEXT.md](CONTEXT.md)。编写与贡献代码时请严格遵守规范词汇（如 Game 游戏、Alias 别名、Completion 通关记录、Dimension Scores 维度评分、Cover 封面、Review 评价等）。

---

## 📄 许可证

本项目遵循 [MIT License](LICENSE) 协议开源。
