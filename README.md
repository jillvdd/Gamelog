# 我的游戏簿（My Gamelog）

<p align="center">
  <img src="appcover.PNG" alt="My Gamelog Cover" width="100%" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" />
</p>

<p align="center">
  <strong>专为游戏玩家打造的个人游戏库与通关历程管理应用</strong>
  <br />
  纯本地存储 · 原生交互 · 实体收藏 · 外部账号同步 · 精美分享卡 · 数据统计看板
</p>

<p align="center">
  <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a> · <strong>简体中文</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B%20%7C%20iOS%2018.0%2B-blue?style=flat-square" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-5.10%20%2F%206.0-orange?style=flat-square" alt="Swift" />
  <img src="https://img.shields.io/badge/SwiftUI-SwiftData-purple?style=flat-square" alt="SwiftUI + SwiftData" />
  <img src="https://img.shields.io/badge/Version-beta%203.5-amber?style=flat-square" alt="Version" />
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
- **Markdown 长篇评测**：支持一句话点睛评语（Tagline）与富文本评测正文（标题、加粗、斜体、列表）。macOS 端提供独立"写字台"沉浸式编辑器。

### 📊 高级数据统计看板（beta 3.3 新增）

- **Apple Fitness 风格 Bento 四格指标**：已通关总数、累计游玩时长、库均分、在玩/想玩数一览无余。
- **Swift Charts 时长分布柱图**：五个时长梯队（＜10h / 10–30h / 30–60h / 60–100h / 100h+）琥珀金可视化，防撞标签自动避位。
- **六状态流动胶囊**：想玩、在玩、搁置、弃坑、长线、已通关六色状态分布直观呈现。
- **跨平台成就聚合**：整合 PSN 白金/金/银/铜奖杯数与 Xbox Gamerscore，与本地通关数据协同展示。
- **常玩厂商 Top 5**：按游戏数量统计最常游玩的开发/发行商排行。
- **实体金库统计**：藏品总数、总花费、总估值三项资产数据汇总。
- **双模式微质感排行榜**：分数榜、时长榜、价值榜三维度 100 条/页分页浏览，封面微缩图 + 金银铜专属徽标，整行可点进入详情。

### 🎨 典雅品牌分享卡生成（beta 3.3 全面重塑）

- **双主题美学视觉**：**暗金黑曜**（经典深底琥珀橙强调）与**雪岭纯白**（明亮编辑风格）两种质感主题随心切换。
- **四种画幅比例**：手机竖版（9:16）、桌面横版（16:9）、方形（1:1）、肖像（4:5），覆盖全平台分享场景。
- **三种分享版式**：
  - **单游戏海报卡**：电影海报级构图，融合封面虚化底色、1.5px 微高光描边、通关程度胶囊、金色评语与维度条形图；
  - **综合总览图**：随游戏数量自适应列数排布，支持 5 维智能排序（手动/评分/日期/发售年/标题）与快捷平台过滤，自由配置表头汇总要素与格子字段；
  - **系列分组卡**：专为游戏系列或专题定制，整合分组长评、统计要素（均分/款数/通关数/最高分游戏/收藏价值）、平台分布条形图与游戏矩阵。
- **智能 UI 分流**：
  - **iPhone**：单游戏纯净流（彻底剔除长列表噪音）+ 多游戏双 Tab 分流（预览 / 挑选）；
  - **iPad / macOS**：双栏宽屏工作台，实时预览与配置并排呈现。
- **灵活导出**：支持 JPEG 与 PNG，iOS 一键保存至系统相册，通过原生系统分享单分发。

### 🔗 外部账号游玩数据同步（实验性）

- **三大主流平台互联**：支持绑定 **Nintendo Account**、**PlayStation Network** 及 **Xbox Live**。
- **自动抓取游玩事实**：自动同步任天堂首次/最近游玩日期与时长、PlayStation 奖杯进度（白金/金/银/铜）、Xbox 成就数与 Gamerscore。
- **智能关联与合并**：同步记录可自动对齐本地游戏库，支持手动关联、条目合并或设置规则忽略；Xbox「仅 PC 端」记录自动归入已忽略。
- **详情页来源卡**：游戏详情页内嵌专属来源卡（奖杯卡、成就卡、游玩记录卡），直观呈现官方游玩痕迹。

### 📦 实体藏品档案（收藏家模式）

- **专为实体玩家定制**：在游戏详情页一键开启「持有」档案，专为实体卡带、光盘、典藏版管理打造。
- **多维度版本参数**：细致记录介质类型（标准版、限定版、铁盒、兑换码等）、发行地区（日版、美版、欧版、港台等）、品相状态、购入渠道及入手价格/当前估值。
- **实物照片图鉴**：支持为每份藏品上传多张实拍照片，随时在设备上翻阅真机开箱与收藏品鉴。
- **藏品价值统计**：自动统计全库实体版本总数、藏品总支出与资产总估值。

### 🛡️ 绝对隐私与纯本地存储

- **零外部服务器**：无账号体系、无数据上传，所有游戏数据均通过 SwiftData 存储在本地设备中。
- **凭证仅进 Keychain**：第三方平台登录凭证与 Token 仅安全驻留于系统钥匙串（Keychain），严禁进入数据库、备份文件或日志。
- **完备的自动化备份**：数据变动时自动在本地保留滚动作业备份；支持单文件完整 JSON 导出导入与 AirDrop 跨端无缝迁移。
- **底层数据自愈**：启动时自动检测并修复 SQLite 层的 NULL 值异常，杜绝历史脏数据导致的启动崩溃。

---

## 💻 跨平台原生体验

| 平台 | 最低系统 | 原生专属体验 |
|---|---|---|
| **macOS** | macOS 14.0+ | 三栏侧边栏、右键上下文菜单、快捷键系统（⌘⇧, 关联设置）、写字台 Markdown 编辑器、独立「关联设置」窗口、自定义 Dock 图标即时生效。 |
| **iOS** | iOS 18.0+ | 原生 TabBar 导航、单列单手操作横向大卡、标题词边界智能断行、原生系统分享单与相机/相册即时录入。 |
| **iPadOS** | iPadOS 18.0+ | 双列宽屏大卡展示、横竖屏自适应分栏、横屏 Hero 满幅画卷布局、宽屏分享工作台。 |

---

## 🚀 快速上手与安装

### 1. 安装应用

#### macOS
- 从 Release 页面下载 `GameLog-beta-3.5.dmg`，打开并将 `GameLog.app` 拖入 `Applications` 文件夹即可。

#### iOS / iPadOS（无签名 IPA）
- 从 `dist/` 目录获取 `GameLog-beta-3.5.ipa`（arm64 真机包）。
- 使用自身证书及工具（如 TrollStore、eSign、AltStore、SideStore 等）重签后安装至真机。

### 2. 导入演示数据（体验 Demo）

本仓库根目录附带一份官方演示数据 [GameLog-demo-backup.json](GameLog-demo-backup.json)，包含 50 款经典游戏（涵盖中/英/日多语言）、105 条真实通关记录、维度评分及分组范例。

- **导入方式**：打开应用 → 进入**「关联设置」**（macOS 快捷键 `⌘⇧,`；iOS 底部「关联」页签）→ **数据备份** → **导入备份…** → 选择该 JSON 文件即可一键载入。

### 3. 配置 SteamGridDB 高清封面搜索

1. 前往 [steamgriddb.com](https://www.steamgriddb.com) 免费注册并从个人页面获取 API Key；
2. 打开应用内的**「关联设置」** → **SteamGridDB** → 填入 API Key（自动校验有效性）；
3. 在新建或编辑游戏时，点击封面旁边的**「搜索…」**按钮，即可即搜即用，一键匹配竖版海报、方形图标、横版横幅与游戏透明 Logo。

---

## 📋 版本历史亮点

| 版本 | 核心内容 |
|---|---|
| **beta 3.5**（当前）| 分享卡导出分辨率提升至 FHD/UHD 双档（每种画幅可选，排版零变化）；iOS 启动屏改用小尺寸图标。 |
| **beta 3.4** | 分组分享标题串位 Bug 修复；版本构建基线稳定。 |
| **beta 3.3** | 统计页现代看板（Fitness 风格 Bento + Swift Charts + 排行榜）；分享系统三端全面重塑（双主题 / 四画幅 / iPhone 纯净流 / iPad-macOS 双栏工作台）。 |
| **beta 3.2** | 「关联设置」独立页；iOS 真机启动与 1GB+ 导入 OOM 根治；全应用三语文案重写。 |
| **beta 3.1** | 外部账号游玩记录导入（Nintendo / PlayStation / Xbox）；三张来源卡；详情页「游戏记录」折叠区。 |
| **beta 3.0** | 导入恢复崩溃根治；批量整库替换后台化与上锁门机制。 |
| **beta 2.x** | 藏品档案化（收藏家模式）；首页五页轮播；大库性能根治；分享大改；Markdown 长评与写字台。 |
| **beta 1.x** | 分组与评价；多语言名；自动封面匹配；六维评分；平台图标系统；自动备份；实体持有档案。 |

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
- `Scripts/ShareRenderTest/`：图片渲染器 ImageRenderer 真实出图尺寸与要素池编排校验（28 项）；
- `Scripts/RichReviewTest/`：Markdown 与富文本写字台双向互转保真度检验（15 项）。

---

## 📖 术语规范

本项目遵循统一的领域模型词汇表，具体参见 [CONTEXT.md](CONTEXT.md)。编写与贡献代码时请严格遵守规范词汇（如 Game 游戏、Alias 别名、Completion 通关记录、Dimension Scores 维度评分、Cover 封面、Review 评价等）。

---

## 📄 许可证

本项目遵循 [MIT License](LICENSE) 协议开源。
