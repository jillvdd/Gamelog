#!/bin/zsh
#
# 把 macOS 版「我的游戏簿」的本机数据整包搬进 iOS 模拟器（iPhone 16 Pro / iPad mini）。
#
# ## 为什么需要这个脚本
#
# 模拟器和 macOS 是两套完全独立的容器。模拟器里那份是陈旧的小库（124 个游戏、**0 个外部
# 账号**），拿它测外部账号、奖杯区块、385 个游戏的滚动性能都不成立。手工搬一次要动四类文件、
# 还得先把设备关掉再改偏好（否则 cfprefsd 会用内存里的旧值覆盖回去），很容易漏掉某一类 ——
# 这里是那个「搬一次」的固化。
#
# ## 搬什么（四类，缺一不可）
#
# 1. **SwiftData 库** `Application Support/default.store`（连同 `-wal` / `-shm`）。
# 2. ⚠️ **图片外置目录** `Application Support/.default_SUPPORT/_EXTERNAL_DATA/`。
#    五类封面与持有照片都是 `@Attribute(.externalStorage)` —— **数据不在 store 里**，
#    落在同级的 `.default_SUPPORT` 目录。只搬 store 会得到一个「所有游戏都没封面」的库，
#    而且不会报任何错。这是本脚本最容易漏的一步，也是它存在的首要理由。
# 3. **偏好** `Preferences/com.abcleg.GameLog.plist`（用户名 / 语言 / 横幅文案 / SteamGridDB
#    密钥等）。合并规则见 `merge_prefs`：照搬 macOS，但**剔除 macOS 窗口专属的键**
#    （`NS*` 前缀）与 `backup.*`（各端的备份状态应当各管各的），并**保留模拟器自己的
#    版式类偏好**（库视图 / 聚光灯背景 / 精简网格）——那些是用户在那一端已经选过的。
# 4. **用户图片** `Application Support/GameLog/{avatar,icon,bannerBackground}.png`。
#
# ## 不搬什么（其中之一是搬不了）
#
# - **凭证（Keychain）搬不了**。iOS 只有 data-protection keychain，模拟器的那本
#   （`data/Library/Keychains/keychain-2.db`）与 macOS 的文件式登录钥匙串**格式不同、无法
#   互拷**。所以搬过去的两个账号**没有凭证**：账号行、330 条来源记录、全部关联关系都在，
#   界面照常浏览，但**点「同步」会要求重新绑定**。
#   重新绑定时 `ExternalAccountBinder.resolveAccount` 按 `(provider, externalAccountId)`
#   找到既有账号行 → **原地更新、不会新增重复账号**，历史记录与关联关系原样保留。
#   （这是设计使然，不是缺陷：凭证只存 Keychain、不进 store、不进备份 —— 见 HANDOVER §53。）
# - **自动备份 JSON**（每个约 900 MB）、`Caches`（可重建）、`Documents/Backups`。
#
# ## 覆盖行为
#
# 模拟器里**已有的库与图片目录会被整个替换**。替换前自动快照到
# `~/Library/Application Support/GameLog-sim-backups/<设备>-<时间戳>/`。
# 商店与图片都用 APFS clonefile（`cp -c`）拷贝：**同一卷上不占额外磁盘**，4 GB 也是秒级。
#
# ## 用法
#
#     Scripts/SyncMacToSim.sh            # 两台都搬
#     Scripts/SyncMacToSim.sh iphone     # 只搬 iPhone 16 Pro
#     Scripts/SyncMacToSim.sh ipad       # 只搬 iPad mini
#     SKIP_INSTALL=1 Scripts/SyncMacToSim.sh   # 只搬数据，不重装 app
#
# 运行前会 `pkill -x GameLog`（拿 store 的一致副本必须没有写者），结束后自动重启它。
# 模拟器在搬运期间会被关机，结束后重新开机并启动 app。

set -euo pipefail
emulate -L zsh

readonly BUNDLE_ID="com.abcleg.GameLog"
readonly MAC_HOME="$HOME/Library"
readonly MAC_SUPPORT="$MAC_HOME/Application Support"
readonly MAC_STORE="$MAC_SUPPORT/default.store"
readonly MAC_BLOBS="$MAC_SUPPORT/.default_SUPPORT/_EXTERNAL_DATA"
readonly MAC_PREFS="$MAC_HOME/Preferences/$BUNDLE_ID.plist"
readonly MAC_ASSETS="$MAC_SUPPORT/GameLog"
readonly MAC_APP="/tmp/GameLogDD-mac/Build/Products/Debug/GameLog.app"
readonly IOS_BUILD_IPHONE="/tmp/GameLogDD-ios/Build/Products/Debug-iphonesimulator/GameLog.app"
readonly IOS_BUILD_IPAD="/tmp/GameLogDD-ipad/Build/Products/Debug-iphonesimulator/GameLog.app"
readonly SNAPSHOT_ROOT="$MAC_SUPPORT/GameLog-sim-backups"

# UDID 是稳定的，设备名不是（Xcode 升级会改名）。这里以 UDID 为准。
typeset -A UDIDS NAMES BUILDS
UDIDS[iphone]="9908C070-47ED-455C-8427-4ED9177591B4"
UDIDS[ipad]="3586EB31-94FB-4E18-96AC-8F7A6032BFEF"
NAMES[iphone]="iPhone 16 Pro"
NAMES[ipad]="iPad mini (A17 Pro)"
BUILDS[iphone]="$IOS_BUILD_IPHONE"
BUILDS[ipad]="$IOS_BUILD_IPAD"

say() { print -r -- "▸ $*" }
die() { print -r -- "✗ $*" >&2; exit 1 }

# MARK: - 取容器路径

# 设备**关机时也能用**的容器查找：直接读容器目录里的元数据 plist。
# （`simctl get_app_container` 要求设备已启动，而我们必须先关机再写数据 —— 见文件头。）
sim_container() {
  local dir base="$HOME/Library/Developer/CoreSimulator/Devices/$1/data/Containers/Data/Application"
  local id
  [[ -d "$base" ]] || return 1
  for dir in "$base"/*(N/); do
    [[ -f "$dir/.com.apple.mobile_container_manager.metadata.plist" ]] || continue
    id=$(plutil -extract MCMMetadataIdentifier raw \
           "$dir/.com.apple.mobile_container_manager.metadata.plist" 2>/dev/null) || continue
    [[ "$id" == "$BUNDLE_ID" ]] && { print -r -- "$dir"; return 0 }
  done
  return 1
}

# MARK: - 偏好合并

# 照搬 macOS 的偏好，除了三类：
#   · `NS*`（`NSSplitView Subview Frames…` / `NSNavPanelExpandedSizeForOpenMode` 等）——
#     macOS 窗口几何，在 iOS 上是纯噪音（且占了 plist 的一大半体积）。
#   · `backup.*`（上次备份日期 / 大小 / 版本）—— 那是**各端自己的备份状态**，搬过去会让
#     模拟器显示一个本机上并不存在的备份文件。
#   · 版式类偏好：保留**模拟器自己**的值（连「原本没有这个键」也保留为没有）——
#     这些是用户在那一端选过的东西，不是内容。
merge_prefs() {
  local sim_prefs=$1 out=$2
  /usr/bin/python3 - "$MAC_PREFS" "$sim_prefs" "$out" <<'PY'
import plistlib, sys

mac_path, sim_path, out_path = sys.argv[1:4]

# 端内版式偏好：以模拟器现有值为准，**不在 macOS plist 里就删掉**（而不是留 macOS 的值），
# 这样「iOS 上没设过 → 走 iOS 默认」这一层语义不会被搬过来的值改写。
KEEP_LOCAL = [
    "customization.libraryViewMode",
    "customization.iosLibraryViewMode",
    "customization.minimalGrid",
    "customization.spotlightBackdrop",
    "customization.spotlightBackdropPadLandscape",
    "customization.useHoldingsGridView",
    "holdingsGridView",
    "useGridView",
]

with open(mac_path, "rb") as f:
    mac = plistlib.load(f)

sim = {}
try:
    with open(sim_path, "rb") as f:
        sim = plistlib.load(f)
except Exception:
    pass

merged = {k: v for k, v in mac.items()
          if not k.startswith("NS") and not k.startswith("backup.")}

for k in KEEP_LOCAL:
    if k in sim:
        merged[k] = sim[k]
    else:
        merged.pop(k, None)

with open(out_path, "wb") as f:
    plistlib.dump(merged, f, fmt=plistlib.FMT_BINARY)

print(f"  偏好：{len(merged)} 个键（macOS {len(mac)} → 剔除 {len(mac) - len(merged)}）")
PY
}

# MARK: - 单台设备

sync_device() {
  local key=$1 udid=${UDIDS[$1]} name=${NAMES[$1]} build=${BUILDS[$1]}
  local container data_dir app_support prefs_dir stamp snap

  say "【$name】$udid"

  # ① 开机 —— `simctl install` 在关机的设备上会报 405 "Unable to lookup in current state"，
  #    所以「先装后写」的代价就是这一次多余的开关机（装完立刻关掉，见 ③）。
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true

  # ② 重装当前构建（模拟器里那份是旧的，不认识 LinkedAccount / 奖杯字段）。
  if [[ "${SKIP_INSTALL:-0}" != "1" && -d "$build" ]]; then
    xcrun simctl install "$udid" "$build" >/dev/null || die "安装失败：$build"
    say "  已安装当前构建（$(plutil -extract CFBundleShortVersionString raw "$build/Info.plist")）"
  else
    say "  跳过安装（SKIP_INSTALL=1 或构建产物不存在）"
  fi

  # ③ 关机：既让 app 松手 store，也让 cfprefsd 丢掉内存里的偏好缓存 ——
  #    否则 ⑧ 写完 plist 会被它按缓存覆盖回去，而那是**静默**的。
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true

  # ④ 找数据容器（关机状态下走元数据 plist，见 `sim_container`）。
  container=$(sim_container "$udid") || die "在 $name 上找不到 $BUNDLE_ID 的数据容器 —— 先把它装到这个模拟器上"
  app_support="$container/Library/Application Support"
  prefs_dir="$container/Library/Preferences"
  [[ -d "$app_support" ]] || die "容器结构异常：$app_support 不存在"

  # ⑤ 快照模拟器现有数据（clonefile，不占额外磁盘）。
  stamp=$(date +%Y%m%d-%H%M%S)
  snap="$SNAPSHOT_ROOT/$key-$stamp"
  mkdir -p "$snap"
  if [[ -f "$app_support/default.store" ]]; then
    cp -c "$app_support/default.store" "$snap/" 2>/dev/null || cp "$app_support/default.store" "$snap/"
    for ext in wal shm; do
      [[ -f "$app_support/default.store-$ext" ]] && cp -c "$app_support/default.store-$ext" "$snap/" 2>/dev/null || true
    done
    [[ -d "$app_support/.default_SUPPORT" ]] && \
      cp -Rc "$app_support/.default_SUPPORT" "$snap/" 2>/dev/null || true
    [[ -f "$prefs_dir/$BUNDLE_ID.plist" ]] && \
      cp -c "$prefs_dir/$BUNDLE_ID.plist" "$snap/sim-prefs.plist" 2>/dev/null || true
    say "  已快照原数据 → $snap"
  else
    rmdir "$snap" 2>/dev/null || true
    say "  原数据为空，无需快照"
  fi

  # ⑥ 库：store 三件套。
  rm -f "$app_support/default.store" "$app_support/default.store-wal" "$app_support/default.store-shm"
  for f in default.store default.store-wal default.store-shm; do
    [[ -f "$MAC_SUPPORT/$f" ]] || continue
    cp -c "$MAC_SUPPORT/$f" "$app_support/$f" 2>/dev/null || cp "$MAC_SUPPORT/$f" "$app_support/$f"
  done
  say "  库：$(du -h "$app_support/default.store" | cut -f1)"

  # ⑦ 图片外置目录（封面大头的真正所在 —— 漏了它游戏会全部没封面）。
  rm -rf "$app_support/.default_SUPPORT"
  mkdir -p "$app_support/.default_SUPPORT"
  cp -Rc "$MAC_BLOBS" "$app_support/.default_SUPPORT/_EXTERNAL_DATA"
  say "  图片：$(ls "$app_support/.default_SUPPORT/_EXTERNAL_DATA" | wc -l | tr -d ' ') 个文件 / $(du -sh "$MAC_BLOBS" | cut -f1)（clonefile，未额外占盘）"

  # ⑧ 偏好。
  mkdir -p "$prefs_dir"
  merge_prefs "$prefs_dir/$BUNDLE_ID.plist" "$prefs_dir/$BUNDLE_ID.plist"

  # ⑨ 用户图片（头像 / app 图标 / 横幅背景）。
  mkdir -p "$app_support/GameLog"
  local f n=0
  for f in "$MAC_ASSETS"/*.png(N); do
    cp -c "$f" "$app_support/GameLog/" 2>/dev/null || cp "$f" "$app_support/GameLog/"
    n=$(( n + 1 ))   # 不用 `(( n++ ))`：n 为 0 时它返回退出码 1，`set -e` 会当场终止脚本
  done
  say "  用户图片：$n 张"

  # ⑩ 开机并启动。
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  xcrun simctl launch "$udid" "$BUNDLE_ID" >/dev/null || say "  ⚠️ 启动失败，请手动打开"
  say "  已开机并启动"
}

# MARK: - main

[[ -f "$MAC_STORE" ]] || die "找不到 macOS 库：$MAC_STORE"
[[ -d "$MAC_BLOBS" ]] || die "找不到图片目录：$MAC_BLOBS（库里的封面都在这里）"

# ⚠️ zsh **不会**对未加引号的参数展开做分词，所以 `${1:-iphone ipad}` 会整体变成一个元素。
# 默认值必须分开写。
if [[ -n "${1:-}" ]]; then
  targets=("$1")
else
  targets=(iphone ipad)
fi
for t in "${targets[@]}"; do
  [[ -n "${UDIDS[$t]:-}" ]] || die "未知目标「$t」—— 可用：iphone / ipad"
done

# 拿 store 的一致副本必须没有写者：先退 app（脚本末尾会重新拉起）。
if pgrep -x GameLog >/dev/null; then
  say "退出 macOS GameLog（结束后自动重启）"
  pkill -x GameLog || true
  sleep 2
fi

say "源：$MAC_SUPPORT"
mkdir -p "$SNAPSHOT_ROOT"

for t in "${targets[@]}"; do
  sync_device "$t"
done

if [[ -d "$MAC_APP" ]]; then
  open "$MAC_APP"
  say "已重启 macOS GameLog"
fi

cat <<'EOF'

✅ 搬完了。两点必须知道：

 · **凭证没有搬过去**（Keychain 跨平台搬不了，见脚本头部）。两台模拟器上的账号、330 条
   来源记录、全部关联关系都在，浏览一切正常；但点「同步」会要求重新绑定。
   重新绑定**不会**产生重复账号 —— 按 (provider, externalAccountId) 原地更新。
 · 版式类偏好（库视图 / 聚光灯背景 / 精简网格）**保留模拟器自己原有的**，没有被 macOS 的
   覆盖 —— 那是端内选择，不是内容。想连这个也照搬，改脚本里的 KEEP_LOCAL 即可。
EOF
