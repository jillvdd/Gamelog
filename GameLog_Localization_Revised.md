# GameLog 本地化对照表（三语全量 UI 文案）

> 用途：人工重新优化本地化内容时的**对照底稿**。三语并列，含每个 key 的使用位置，
> 方便你在改某一种语言时知道自己动了哪里、会不会影响其它语言或代码。
>
> **代码结构**：本地化在 `GameLog/Resources/{zh-Hans,en,ja}.lproj/Localizable.strings`
> 三个文件里，运行时由 `GameLog/Support/L10n.swift` 按用户选中的语言（`appLanguageCode`）
> 手动查表，不依赖系统 locale。代码里统一用 `L10n.tr("key", lang:)` 或 `LText("key")`。

## ⚠️ 修改前必读（重要陷阱）

1. **每一行只有一条**：格式必须是 `"key" = "value";` 一一行一条。目前中文文件第 88 行
   存在 `"share.count" = "共 %d 款";"share.preview" = "预览";` **两条挤在一行**的问题——
   这会导致 `share.preview` 在 zh 里解析异常。重写时务必拆成两行。
2. **格式占位符必须与其它语言一致**：`%@`（字符串）、`%d`（整数）、`%lld`（64 位整数）、
   `%.1f`（带 1 位小数的浮点）。占位符**个数和种类**改动后，运行时会崩（String(format:) 越界）。
   加粗词、省略号 `…`、换行都随意，但**占位符不能少/多/错**。
3. **别删 key**：有些 key 代码里用字符串拼接动态查询（如 `status.*` = `"status." + rawValue`），
   grep 不到字面引用，但删了会显示空白。不确定的 key 不要动。
4. **双引号与反斜杠**：value 里若需引号用 `\"`，反斜杠用 `\\`；不支持换行（写成一行）。
5. **只改一种语言**时，请只动对应 `.lproj` 文件，保持其它两种不动；提交前可跑一次 grep
   确认未破坏格式。


## `about.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `about.developer` | 开发者 | Developer | Developer | Views/AboutView |
| `about.menu` | 关于我的游戏簿 | About My Gamelog | Gamelogについて | GameLogApp |
| `about.version` | 版本 | Version | バージョン | Views/AboutView |

## `app.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `app.menu` | 我的游戏簿 | My Gamelog | My Gamelog | GameLogApp,Views/AboutView,Views/SharePanelView,Share/ShareCardView |

## `backup.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `backup.autobackupRestore` | 从自动备份恢复… | Restore from Auto Backup… | 自動バックアップから復元… | Views/SettingsView |
| `backup.autobackupRestoreConfirm` | 将用自动备份替换当前全部数据，确定继续吗？ | This will replace all current data with the auto backup. Continue? | 自動バックアップで現在のデータをすべて置き換えます。続けますか？ | Views/SettingsView |
| `backup.backupNow` | 立即备份 | Back Up Now | 今すぐバックアップ | Views/SettingsView |
| `backup.emptyRestoreMessage` | 当前库为空，但本地自动备份包含 %lld 款游戏。是否从自动备份恢复？（取消将保留空库） | Your library is empty, but the local auto backup contains %lld games. Restore it? (Cancel keeps the library empty) | ライブラリは空ですが、ローカルの自動バックアップには %lld 本のゲームがあります。自動バックアップから復元しますか？（キャンセルすると空のままになります） | Support/AutoBackup |
| `backup.emptyRestoreTitle` | 检测到库为空 | Empty Library Detected | 空のライブラリが見つかりました | Support/AutoBackup |
| `backup.export` | 导出备份… | Export Backup… | バックアップを書き出す… | Views/SettingsView |
| `backup.exportDone` | 备份已导出 | Backup Exported | バックアップを書き出しました | Views/SettingsView |
| `backup.exportFailed` | 导出失败 | Export Failed | 書き出しに失敗しました | Views/SettingsView |
| `backup.import` | 导入备份… | Import Backup… | バックアップを読み込む… | Views/SettingsView |
| `backup.importConfirm` | 导入将替换当前全部数据，确定继续吗？ | Importing will replace all current data. Continue? | 読み込むと現在のデータがすべて置き換えられます。続けますか？ | Views/SettingsView,Views/iOSRootView |
| `backup.importDone` | 备份已导入 | Backup Imported | バックアップを読み込みました | Views/SettingsView |
| `backup.importFailed` | 导入失败，请检查文件是否为有效备份 | Import failed. Check that the file is a valid backup. | 読み込みに失敗しました。有効なバックアップファイルか確認してください | Views/SettingsView |
| `backup.keepEmpty` | 保留空库 | Keep Empty | 空のままにする | Support/AutoBackup |
| `backup.lastBackup` | 上次备份：%@ | Last backup: %@ | 前回のバックアップ：%@ | Views/SettingsView |
| `backup.noBackupYet` | 尚未备份 | No Backup Yet | まだバックアップはありません | Views/SettingsView |
| `backup.nowDone` | 已保存备份 | Backup Saved | バックアップを保存しました | Views/SettingsView |
| `backup.restoreDone` | 已从自动备份恢复 | Restored from Auto Backup | 自動バックアップから復元しました | Views/SettingsView |
| `backup.restoreFailed` | 恢复失败，自动备份文件可能已损坏 | Restore failed. The auto backup file may be corrupted. | 復元に失敗しました。自動バックアップファイルが破損している可能性があります | Views/SettingsView |
| `backup.restoreNow` | 从备份恢复 | Restore from Backup | バックアップから復元 | Support/AutoBackup |
| `backup.snapshotSaved` | 恢复前快照已保留 | Pre-restore snapshot saved | 復元前のスナップショットを保存しました | <未使用>*(动态/未命中)* |

## `common.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `common.back` | 返回 | Back | 戻る | Support/L10n,Views/CoverSearchSheet,Views/GameEditView |
| `common.cancel` | 取消 | Cancel | キャンセル | Views/ReviewEditSheet,Support/ImageSourcePicker,Views/CompletionEditView,Views/iOSRootView,Views/GameDetailView,Views/SettingsView,Views/HoldingsView,Views/RootView,Views/GameCardView,Views/LibraryView,Views/GameEditView,Views/GroupFooter,Views/ImageCropView,Views/ReviewEditorView |
| `common.confirm` | 确定 | OK | OK | Support/ImageSourcePicker,Views/CompletionEditView,Views/SettingsView,Views/iOSRootView,Views/GameEditView |
| `common.confirmDelete` | 删除 | Delete | 削除 | Views/GameDetailView,Views/HoldingsView,Views/LibraryView |
| `common.custom` | 自定义… | Custom… | カスタム… | Views/GameEditView |
| `common.delete` | 删除 | Delete | 削除 | Views/GameDetailView,Views/iOSRootView,Views/RootView,Views/LibraryView,Views/HoldingsView,Views/GameEditView |
| `common.done` | 完成 | Done | 完了 | Views/iOSRootView,Views/GroupPickerSheet |
| `common.edit` | 编辑 | Edit | 編集 | Views/GameDetailView,Views/HoldingsView,Views/LibraryView,Views/GroupFooter |
| `common.save` | 保存 | Save | 保存 | Views/CompletionEditView,Views/GameCardView,Views/RootView,Views/HoldingsView,Views/GameEditView,Views/GroupFooter,Views/ImageCropView |

## `completion.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `completion.add` | 追加通关记录 | Add Completion | クリア記録を追加 | Views/GameDetailView |
| `completion.date` | 通关日期 | Completion date | クリア日 | Views/CompletionEditView,Views/GameEditView |
| `completion.degree` | 通关程度 | Completion level | クリア度 | Views/CompletionEditView,Views/GameEditView |
| `completion.delete` | 删除 | Delete | 削除 | Views/GameDetailView |
| `completion.edit` | 编辑 | Edit | 編集 | <未使用>*(动态/未命中)* |
| `completion.noDate` | 无通关日期 | No completion date | クリア日なし | Views/CompletionEditView,Views/GameEditView |
| `completion.noPlaytime` | 无时长 | No playtime | プレイ時間なし | Views/CompletionEditView,Views/GameEditView |
| `completion.notes` | 通关备注 | Completion notes | クリアメモ | <未使用>*(动态/未命中)* |
| `completion.notesPlaceholder` | 这次的游玩感受、趣事… | Thoughts and highlights from this run… | 今回の感想や出来事… | <未使用>*(动态/未命中)* |
| `completion.platform` | 平台 | Platform | プラットフォーム | Views/CompletionEditView,Views/GameEditView |
| `completion.playtime` | 游戏时长（小时） | Playtime (hours) | プレイ時間（時間） | Views/CompletionEditView,Views/GameEditView |
| `completion.playtimeFormat` | %.1f 小时 | %.1f hours | %.1f時間 | Views/GameDetailView |
| `completion.scores` | 六维评分 | Dimension Scores | 6項目のスコア | Views/CompletionEditView,Views/GameEditView |
| `completion.skipScores` | 本次跳过评分 | Skip scoring this run | 今回はスコアを付けない | Views/CompletionEditView |

## `copy.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `copy.addImage` | 添加图片 | Add Photos | 写真を追加 | Views/HoldingsView |
| `copy.addVersion` | 新增版本 | Add Edition | エディションを追加 | Views/HoldingsView |
| `copy.count` | 数量 | Quantity | 数量 | Views/HoldingsView |
| `copy.deleteConfirm` | 确定删除版本「%@」？该版本的照片也会被删除。 | Delete edition "%@"? Photos for this edition will also be deleted. | エディション「%@」を削除しますか？このエディションの写真も削除されます。 | Views/HoldingsView |
| `copy.deleteImageConfirm` | 确定删除这张照片吗？此操作无法撤销。 | Delete this photo? This action cannot be undone. | この写真を削除しますか？この操作は取り消せません。 | Views/HoldingsView |
| `copy.noCopies` | 还没有持有记录 | No Holdings Yet | 所持品はまだありません | Views/HoldingsView |
| `copy.rename` | 重命名版本 | Rename Edition | エディション名を変更 | Views/HoldingsView |
| `copy.version` | 版本 | Edition | エディション | Views/HoldingsView |
| `copy.versionAuto` | 版本 %d | Edition %d | エディション %d | Views/HoldingsView |
| `copy.versionPlaceholder` | 如「日版初版」 | e.g. JP first edition | 例：日本版・初版 | Views/HoldingsView |
| `copy.viewImage` | 查看大图 | View Full Image | 画像を拡大表示 | Views/HoldingsView |

## `cover.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `cover.close` | 关闭 | Close | 閉じる | Views/CoverSearchSheet |
| `cover.noGrids` | 未找到该游戏的封面 | No Covers Found for This Game | このゲームのカバーが見つかりません | Views/CoverSearchSheet |
| `cover.searchFailed` | 封面获取失败，请检查网络或 API Key | Couldn't fetch covers. Check your network connection or API key. | カバーを取得できませんでした。ネットワーク接続または API Key を確認してください | Views/CoverSearchSheet |
| `cover.title` | 搜索封面 | Search Covers | カバーを検索 | Views/CoverSearchSheet |

## `crop.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `crop.titleAvatar` | 裁切头像 | Crop Avatar | アバターをトリミング | Views/ImageCropView |
| `crop.titleIcon` | 裁切图标 | Crop Icon | アイコンをトリミング | Views/ImageCropView |
| `crop.zoom` | 缩放 | Zoom | ズーム | Views/ImageCropView |

## `date.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `date.day` | 日 | Day | 日 | Views/DateMenuPicker |
| `date.earlierYears` | 更早年份… | Earlier Years… | それ以前の年… | <未使用>*(动态/未命中)* |
| `date.year` | 年 | Year | 年 | Views/DateMenuPicker |

## `delete.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `delete.confirmGame` | 确定删除「%@」？该游戏的所有通关记录也会被删除。 | Delete “%@”? All of its completion records will also be deleted. | 「%@」を削除しますか？このゲームのすべてのクリア記録も削除されます。 | Views/GameDetailView,Views/LibraryView |

## `detail.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `detail.details` | 详情 | Details | 詳細 | Views/GameDetailView |
| `detail.holdings` | 持有 | Owned | 所持 | Views/GameDetailView,Views/HoldingsView |

## `dimension.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `dimension.art` | 美术 | Art | アート | Views/CompletionEditView,Views/GameEditView |
| `dimension.design` | 设计 | Design | デザイン | Views/CompletionEditView,Views/GameEditView |
| `dimension.gameplay` | 玩法 | Gameplay | ゲーム性 | Views/CompletionEditView,Views/GameEditView |
| `dimension.music` | 音乐 | Music | 音楽 | Views/CompletionEditView,Views/GameEditView |
| `dimension.performance` | 性能 | Performance | パフォーマンス | Views/CompletionEditView,Views/GameEditView |
| `dimension.story` | 剧情 | Story | ストーリー | Views/CompletionEditView,Views/GameEditView |

## `game.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `game.aliasAdd` | 添加 | Add | 追加 | Views/GameEditView |
| `game.aliases` | 别名（用于搜索） | Aliases (for search) | 別名（検索用） | Views/GameEditView |
| `game.aliasPlaceholder` | 输入别名 | Enter an alias | 別名を入力 | Views/GameEditView |
| `game.chooseCover` | 选择图片… | Choose Image… | 画像を選択… | Views/GameEditView |
| `game.completions` | 通关记录 | Completion Records | クリア記録 | Views/GameDetailView |
| `game.cover` | 封面 | Cover | カバー | <未使用>*(动态/未命中)* |
| `game.firstCompletion` | 首条通关记录 | First Completion | 初回クリア記録 | Views/GameEditView |
| `game.groups` | 所属分组 | Groups | 所属グループ | Views/RootView,Views/GroupPickerSheet,Views/LibraryView,Views/GameEditView |
| `game.name` | 游戏名称 | Title | タイトル | Views/GameEditView |
| `game.nameEn` | 英文名 | English Title | 英語タイトル | Views/GameEditView |
| `game.nameJa` | 日文名 | Japanese Title | 日本語タイトル | Views/GameEditView |
| `game.nameZh` | 中文名 | Chinese Title | 中国語タイトル | Views/GameEditView |
| `game.noCover` | 未设置封面 | No Cover Set | カバー未設定 | <未使用>*(动态/未命中)* |
| `game.releaseDate` | 发售日期 | Release Date | 発売日 | Views/GameEditView |
| `game.reviewBody` | 评价正文 | Review | レビュー本文 | <未使用>*(动态/未命中)* |
| `game.reviewTitle` | 评价标题 | Review Title | レビュータイトル | Views/GameEditView |
| `game.reviewTitlePlaceholder` | 一句话评价（分享图会用到） | One-line verdict (shown on share cards) | 一言レビュー（共有カードに表示） | Views/ReviewEditSheet,Views/GameEditView |
| `game.searchCover` | 搜索封面… | Search Covers… | カバーを検索… | Views/GameEditView |
| `game.status` | 状态 | Status | ステータス | Views/RootView,Views/iOSRootView,Views/LibraryView,Views/GameEditView |
| `game.statusHint` | 想玩/在玩/搁置/弃坑无需通关记录与评分，流转到「已通关」时再补。 | Lightweight statuses (Backlog, Playing, etc.) don't require completion records or scores. Add them when you mark the game as Completed. | プレイ予定・プレイ中などの軽量な状態では、クリア記録やスコアは不要です。「クリア済み」にしたときに記録します。 | Views/GameEditView |

## `group.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `group.avgScore` | 平均分 | Average Score | 平均スコア | Views/StatsView,Views/StatsRankings,Views/GroupFooter,Share/ShareCardView |
| `group.completionCount` | 通关数 | Completions | クリア数 | Share/ShareCardView |
| `group.deleteConfirm` | 确定删除分组「%@」？分组中的游戏不会被删除。 | Delete group “%@”? Games in it will not be deleted. | グループ「%@」を削除しますか？グループ内のゲームは削除されません。 | Views/iOSRootView,Views/RootView |
| `group.deleteTitle` | 删除分组 | Delete Group | グループを削除 | Views/iOSRootView,Views/RootView |
| `group.gameCount` | 游戏数 | Games | ゲーム数 | Share/ShareCardView |
| `group.manage` | 管理分组 | Manage Groups | グループを管理 | Views/iOSRootView |
| `group.memberCount` | %d 款游戏 | %d games | %dタイトル | Views/GroupGamePickerView |
| `group.name` | 分组名称 | Group Name | グループ名 | Views/GameCardView,Views/RootView |
| `group.nameExists` | 该分组名已存在 | A group with this name already exists | 同じ名前のグループがすでにあります | Views/RootView,Views/GameCardView |
| `group.newGroup` | 新建分组 | New Group | 新しいグループ | Views/iOSRootView,Views/RootView,Views/GameCardView |
| `group.pickGames` | 选择游戏… | Select Games… | ゲームを選択… | Views/RootView |
| `group.pickSearch` | 搜索游戏… | Search Games… | ゲームを検索… | Views/GroupGamePickerView |
| `group.rename` | 重命名分组 | Rename Group | グループ名を変更 | Views/RootView |
| `group.review` | 分组评价 | Group Review | グループのレビュー | Views/GroupFooter |
| `group.reviewEdit` | 编辑分组评价 | Edit Group Review | グループのレビューを編集 | Views/GroupFooter |
| `group.reviewEmpty` | 还没有评价 | No Review Yet | レビューはまだありません | Views/GroupFooter |
| `group.stats` | 分组统计 | Group Stats | グループ統計 | Views/GroupFooter |

## `image.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `image.cameraUnavailable` | 当前设备不支持拍照 | Camera isn't available on this device | このデバイスではカメラを使用できません | Support/ImageSourcePicker |
| `image.fromFiles` | 从文件选择 | Choose from Files | ファイルから選択 | Support/ImageSourcePicker |
| `image.fromPhotos` | 从相册选择 | Choose from Photo Library | 写真ライブラリから選択 | Support/ImageSourcePicker |
| `image.pickSource` | 添加图片 | Add Image | 画像を追加 | Support/ImageSourcePicker |
| `image.takePhoto` | 拍照 | Take Photo | 写真を撮る | Support/ImageSourcePicker |

## `library.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `library.addGame` | 新建游戏 | Add Game | ゲームを追加 | Views/LibraryView |
| `library.all` | 全部游戏 | All Games | すべてのゲーム | Views/iOSRootView,Views/RootView,Views/LibraryView |
| `library.allGroups` | 全部分组 | All Groups | すべてのグループ | <未使用>*(动态/未命中)* |
| `library.allPlatforms` | 全部平台 | All Platforms | すべてのプラットフォーム | Views/LibraryView,Views/GroupGamePickerView,Views/StatsRankings |
| `library.filter` | 筛选 | Filter | 絞り込み | Views/iOSRootView |
| `library.filterGroup` | 按分组筛选 | Filter by Group | グループで絞り込む | Views/iOSRootView |
| `library.filterPlatform` | 平台筛选 | Filter by Platform | プラットフォームで絞り込む | Views/iOSRootView,Views/LibraryView,Views/GroupGamePickerView,Views/StatsRankings |
| `library.gridView` | 网格视图 | Grid View | グリッド表示 | Views/LibraryView |
| `library.listView` | 列表视图 | List View | リスト表示 | Views/LibraryView |
| `library.noGames` | 还没有游戏，点击右上角「新建游戏」开始记录 | No games yet. Click “Add Game” in the top-right to get started. | まだゲームがありません。右上の「ゲームを追加」から始めましょう | Views/LibraryView |
| `library.noResult` | 没有匹配的游戏 | No Matching Games | 該当するゲームがありません | Views/GameDetailView,Views/CoverSearchSheet,Views/GroupGamePickerView,Views/GroupPickerSheet,Views/LibraryView |
| `library.platforms` | 平台 | Platforms | プラットフォーム | Views/RootView |
| `library.search` | 搜索游戏… | Search Games… | ゲームを検索… | Views/CoverSearchSheet,Views/SharePanelView,Views/LibraryView |
| `library.share` | 分享 | Share | 共有 | Views/GameDetailView,Views/LibraryView |
| `library.sort` | 排序 | Sort | 並び替え | Views/LibraryView |
| `library.sortByCompletion` | 按通关日期 | Completion Date | クリア日順 | Views/LibraryView |
| `library.sortByName` | 按名字 | Name | 名前順 | Views/LibraryView |
| `library.sortByRelease` | 按发售日期 | Release Date | 発売日順 | Views/LibraryView |
| `library.sortByScoreAsc` | 平均分（从低到高） | Average Score (Low to High) | 平均スコア（低い順） | Views/LibraryView |
| `library.sortByScoreDesc` | 平均分（从高到低） | Average Score (High to Low) | 平均スコア（高い順） | Views/LibraryView |
| `library.stats` | 统计 | Stats | 統計 | Views/RootView,Views/iOSRootView,Views/StatsView |

## `preset.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `preset.allPlatforms` | 所有平台… | All Platforms… | すべてのプラットフォーム… | Views/GameEditView |

## `review.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `review.bodyHint` | 支持 Markdown：标题用 #，加粗用 **文字**，斜体用 *文字*，列表用 - 项 | Markdown supported: # heading, **bold**, *italic*, - list item | Markdown 対応：# 見出し、**太字**、*斜体*、- リスト項目 | Views/GameEditView |
| `review.bold` | 加粗 | Bold | 太字 | Views/ReviewEditorView |
| `review.edit` | 编辑评价 | Edit Review | レビューを編集 | Views/GameDetailView,Views/ReviewEditSheet |
| `review.editor` | 编辑评价 | Edit Review | レビューを編集 | GameLogApp |
| `review.header` | 评价 | Review | レビュー | Views/GameDetailView |
| `review.italic` | 斜体 | Italic | 斜体 | Views/ReviewEditorView |
| `review.list` | 列表 | List | リスト | Views/ReviewEditorView |
| `review.main` | 正文 | Body | 本文 | Views/ReviewEditorView |
| `review.save` | 保存 | Save | 保存 | Views/ReviewEditSheet,Views/ReviewEditorView |
| `review.source` | Markdown 源码 | Markdown Source | Markdown ソース | <未使用>*(动态/未命中)* |
| `review.subtitle` | 副标题 | Subheading | 小見出し | Views/ReviewEditorView |
| `review.title` | 大标题 | Heading | 見出し | Views/ReviewEditorView |

## `score.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `score.average` | 平均分 | Average Score | 平均スコア | Views/GameDetailView |
| `score.unrated` | 未评分 | Unrated | 未評価 | Views/GameDetailView,Views/GameCardView,Share/ShareCardView |

## `settings.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `settings.autoBackup` | 自动备份 | Auto Backup | 自動バックアップ | Views/SettingsView |
| `settings.autoBackupHint` | 每次数据改动后自动在本地保存完整备份，可在设置中随时恢复。 | Automatically saves a full backup locally whenever your data changes. Restore anytime from Settings. | データを変更するたびに完全なバックアップを自動でローカルに保存します。設定からいつでも復元できます。 | Views/SettingsView |
| `settings.autoMatchCover` | 自动匹配封面 | Automatically Match Cover | カバーを自動取得 | Views/SettingsView |
| `settings.autoMatchCoverHint` | 输入游戏名后，自动搜索 SteamGridDB 并填入第一张封面（需在下方配置 API Key）。 | When you enter a game name, automatically searches SteamGridDB and sets the first cover found (requires an API key below). | ゲーム名を入力すると SteamGridDB を検索し、最初に見つかったカバーを自動設定します（下で API Key の設定が必要です）。 | Views/SettingsView |
| `settings.avatar` | 头像 | Avatar | アバター | Views/SettingsView |
| `settings.backup` | 数据备份 | Backup | データバックアップ | Views/SettingsView |
| `settings.cacheClear` | 清除缓存 | Clear Cache | キャッシュを削除 | Views/SettingsView |
| `settings.cacheClearConfirm` | 清除缓存？缓存仅为可自动重建的临时数据（封面搜索下载、图片解码缓存、临时文件），不会影响游戏数据与备份。 | Clear Caches? Caches are temporary data that can be rebuilt automatically (cover search downloads, image decoding cache, and temporary files). Your game data and backups are not affected. | キャッシュを削除しますか？キャッシュは自動で再生成できる一時データ（カバー検索のダウンロード、画像デコードキャッシュ、一時ファイル）です。ゲームデータとバックアップには影響しません。 | Views/SettingsView |
| `settings.cacheCleared` | 已清除缓存（释放 %@） | Cache Cleared (%@ Freed) | キャッシュを削除しました（%@ を解放） | Views/SettingsView |
| `settings.cacheClearFailed` | 清除失败 | Clear Failed | 削除に失敗しました | <未使用>*(动态/未命中)* |
| `settings.cacheSize` | 当前缓存占用：%@ | Cache Size: %@ | キャッシュ容量：%@ | Views/SettingsView |
| `settings.chooseImage` | 选择图片… | Choose Image… | 画像を選択… | Views/SettingsView |
| `settings.collectorMode` | 收藏家模式 | Collector Mode | コレクターモード | Views/SettingsView |
| `settings.collectorModeHint` | 在游戏详情页启用「持有」页签，记录实体游戏的版本与收藏照片。 | Adds an “Owned” tab to game details for recording physical game editions and collection photos. | ゲーム詳細に「所持」タブを追加し、現物ゲームのエディションとコレクション写真を記録します。 | Views/SettingsView |
| `settings.copyKey` | 复制 | Copy | コピー | Views/SettingsView |
| `settings.customization` | 个性化 | Personalization | カスタマイズ | Views/SettingsView |
| `settings.hideKey` | 隐藏 | Hide | 隠す | Views/SettingsView |
| `settings.hideToolbarGlass` | 隐藏上方毛玻璃 | Hide Top Toolbar Background | 上部ツールバーの背景を隠す | Views/SettingsView |
| `settings.hideToolbarGlassHint` | 隐藏所有页面（库/详情/统计）顶部工具栏的毛玻璃背景，界面更简洁。（macOS 15 及以上可启用） | Hides the frosted-glass background of the top toolbar on all pages (Library / Detail / Stats) for a cleaner look. (macOS 15 and later) | すべてのページ（ライブラリ / 詳細 / 統計）の上部ツールバーにあるすりガラスの背景を隠し、すっきりした表示にします。（macOS 15 以降） | Views/SettingsView |
| `settings.icon` | App 图标 | App Icon | App アイコン | Views/SettingsView |
| `settings.keepOriginalImages` | 保存原图 | Keep Original Images | 元画像を保存 | Views/SettingsView |
| `settings.keepOriginalImagesHint` | 收藏照片按原样保存、不压缩（默认压缩以节省空间；只影响之后新增的图）。 | Saves collection photos unmodified instead of compressing them (only affects photos added from now on). | コレクション写真を圧縮せず元のまま保存します（今後追加する写真にのみ適用されます）。 | Views/SettingsView |
| `settings.keyInvalid` | API Key 无效，请检查 | Invalid API Key. Please check. | API Key が無効です。確認してください | Views/SettingsView |
| `settings.keyValid` | API Key 有效 | API Key is valid | API Key は有効です | Views/SettingsView |
| `settings.language` | 界面语言 | Language | 表示言語 | Views/SettingsView |
| `settings.platformIcons` | 平台图标 | Platform Logos | プラットフォームロゴ | Views/SettingsView |
| `settings.platformIconsHint` | 在各平台选择与分组中显示品牌标志图标。 | Show platform brand logos in platform pickers and group views. | プラットフォーム選択画面とグループ表示でブランドロゴを表示します。 | Views/SettingsView |
| `settings.removeAvatar` | 移除头像 | Remove Avatar | アバターを削除 | Views/SettingsView |
| `settings.restoreIcon` | 恢复默认图标 | Restore Default Icon | デフォルトアイコンに戻す | Views/SettingsView |
| `settings.showKey` | 显示 | Show | 表示 | Views/SettingsView |
| `settings.steamgriddb` | SteamGridDB | SteamGridDB | SteamGridDB | Views/SettingsView |
| `settings.steamGridDBHint` | 在 steamgriddb.com 免费注册后，从个人页面获取 | Register for free at steamgriddb.com, then get the key from your profile. | steamgriddb.com に無料登録し、プロフィールからキーを取得してください | Views/SettingsView |
| `settings.steamGridDBKey` | API Key | API Key | API Key | Views/SettingsView |
| `settings.storage` | 存储与缓存 | Storage & Cache | ストレージとキャッシュ | Views/SettingsView |
| `settings.username` | 用户名 | Username | ユーザー名 | Views/SettingsView |

## `share.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `share.brandUser` | %@的游戏簿 | %@'s Gamelog | %@のGamelog | Views/SharePanelView,Share/ShareCardView |
| `share.byGames` | 按游戏分享 | By Game | ゲーム別 | Views/SharePanelView |
| `share.byGroups` | 按分组分享 | By Group | グループ別 | Views/SharePanelView |
| `share.count` | 共 %d 款 | %d games | 合計 %dタイトル | Share/ShareCardView |
| `share.desktop` | 电脑 (16:9) | Desktop (16:9) | デスクトップ (16:9) | Views/SharePanelView |
| `share.groupTitle` | 分组标题 | Group Title | グループタイトル | Views/SharePanelView |
| `share.multiNote` | 分享多个游戏：生成一张总览图 | Multiple selected: creates one overview image | 複数選択：1枚の概要画像を生成 | <未使用>*(动态/未命中)* |
| `share.noneSelected` | 请至少选择一个游戏 | Select at least one game | ゲームを1つ以上選択してください | Views/SharePanelView |
| `share.noneSelectedGroup` | 请至少选择一个分组 | Select at least one group | グループを1つ以上選択してください | Views/SharePanelView |
| `share.openShareSheet` | 分享… | Share… | 共有… | Views/SharePanelView |
| `share.overviewTitle` | 总览标题 | Overview Title | 概要タイトル | Views/SharePanelView |
| `share.overviewTitleDefault` | 我的游戏簿 | My Gamelog | My Gamelog | <未使用>*(动态/未命中)* |
| `share.phone` | 手机 (9:16) | Phone (9:16) | スマートフォン (9:16) | Views/SharePanelView |
| `share.photoPermissionDenied` | 未获得照片权限，请在系统设置中允许 | Photo access is not allowed. Enable it in Settings. | 写真へのアクセスが許可されていません。設定で許可してください | Views/SharePanelView |
| `share.preview` | 预览 | Preview | プレビュー | <未使用>*(动态/未命中)* |
| `share.savedToAlbum` | 已保存到相册 | Saved to Photos | 写真に保存しました | Views/SharePanelView |
| `share.saveFailed` | 保存失败 | Save Failed | 保存に失敗しました | Views/SharePanelView |
| `share.saveImage` | 保存图片… | Save Image… | 画像を保存… | Views/SharePanelView |
| `share.saveToAlbum` | 保存到相册 | Save to Photos | 写真に保存 | Views/SharePanelView |
| `share.selectGames` | 选择要分享的游戏 | Select Games to Share | 共有するゲームを選択 | Views/SharePanelView |
| `share.singleNote` | 分享一个游戏：生成该游戏的一张卡片 | One game selected: creates a card for it | ゲームを1つ選択：そのゲームのカード画像を生成 | <未使用>*(动态/未命中)* |
| `share.size` | 图片尺寸 | Image Size | 画像サイズ | Views/SharePanelView |

## `stats.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `stats.avgScore` | 库平均分 | Library Average Score | ライブラリ平均スコア | Views/StatsView |
| `stats.backlogCount` | 想玩 | Backlog | プレイ予定 | Views/StatsView |
| `stats.byPlatform` | 按平台分布 | By Platform | プラットフォーム別 | Views/StatsView,Views/GroupFooter,Share/ShareCardView |
| `stats.nextPage` | 下一页 | Next | 次へ | Views/StatsRankings |
| `stats.noData` | 暂无数据 | No Data | データなし | Views/StatsRankings,Views/StatsView |
| `stats.overallRanking` | 整体排名 | Overall Ranking | 総合ランキング | Views/StatsView,Views/StatsRankings |
| `stats.prevPage` | 上一页 | Previous | 前へ | Views/StatsRankings |
| `stats.rankings` | 榜单 | Rankings | ランキング | Views/StatsView |
| `stats.totalGames` | 通关总数 | Games Cleared | クリア済みゲーム数 | Views/StatsView |

## `status.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `status.backlog` | 想玩 | Backlog | プレイ予定 | <未使用>*(动态/未命中)* |
| `status.completed` | 已通关 | Completed | クリア済み | <未使用>*(动态/未命中)* |
| `status.dropped` | 弃坑 | Dropped | プレイ中止 | <未使用>*(动态/未命中)* |
| `status.longRunning` | 长线游玩 | Long-Running | 長期プレイ | <未使用>*(动态/未命中)* |
| `status.paused` | 搁置 | Paused | 中断 | <未使用>*(动态/未命中)* |
| `status.playing` | 在玩 | Playing | プレイ中 | <未使用>*(动态/未命中)* |

## `tab.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `tab.library` | 库 | Library | ライブラリ | Views/iOSRootView |
| `tab.settings` | 设置 | Settings | 設定 | Views/iOSRootView |

## `title.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `title.addCompletion` | 追加通关记录 | Add Completion | クリア記録を追加 | Views/CompletionEditView |
| `title.editCompletion` | 编辑通关记录 | Edit Completion | クリア記録を編集 | Views/CompletionEditView |
| `title.editGame` | 编辑游戏 | Edit Game | ゲームを編集 | Views/GameEditView |
| `title.newGame` | 新建游戏 | New Game | 新規ゲーム | Views/GameEditView |

## `validation.*` 组

| key | 简体中文 | English | 日本語 | 使用位置 |
|-----|---------|---------|--------|---------|
| `validation.nameRequired` | 请输入游戏名称 | Enter a game name | ゲーム名を入力してください | Views/GameEditView |
| `validation.playtimeInvalid` | 游戏时长请输入非负数字（小时） | Playtime must be a non-negative number (hours) | プレイ時間は0以上の数値（時間）で入力してください | Views/CompletionEditView,Views/GameEditView |
| `validation.reviewTitleRequired` | 评价标题必填 | Review title is required | レビュータイトルは必須です | Views/GameEditView |
| `validation.scoresRequired` | 首条记录需要完成四项评分 | The first completion requires all four scores | 初回記録には4項目のスコアが必要です | <未使用>*(动态/未命中)* |
