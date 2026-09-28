import Foundation
import Security

/// 外部账号凭证的种类。
///
/// **只收「值得持久化」的凭证**：短期 access token 一律只放内存（Nintendo 15 分钟、
/// PSN 1 小时，落盘毫无收益却扩大了暴露面）。这里每一条都是跨进程仍需要的东西。
enum ExternalCredentialKind: String, CaseIterable {
    /// Nintendo Account 会话令牌（`session_token`）：约 2 年有效，
    /// **唯一需要持久化的 Nintendo 凭证**，15 分钟的 access token 由它派生。
    case nintendoSessionToken
    /// PSN 的 NPSSO（64 字符）：**等效于密码**。除了换 code，还承担
    /// 「refresh_token 失效后自动重登」的职责 —— PSN 的 refresh_token 不轮换、
    /// 不续期，会话有硬寿命上限，所以 NPSSO 必须留下。
    case psnNPSSO
    /// PSN 的 refresh_token：换 access token 用（不轮换，用一次少一次寿命）。
    case psnRefreshToken
    /// OpenXBL 的 Personal API Key：**长期有效、不轮换、没有刷新机制**，
    /// 所以它是 Xbox 侧唯一需要持久化的凭证（整套鉴权就是「把它放进 `X-Authorization` 头」，
    /// 没有 OAuth、没有短期 token 要派）。⚠️ 它同时是**计费与配额的身份**，
    /// 泄露的后果是别人用你的额度，处置方式与密码同级：只进 Keychain。
    case xboxAPIKey
}

/// Keychain 存取失败。**注意：任何分支都不得把凭证内容带进错误描述或日志。**
enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            // 只报状态码，绝不带数据。
            let detail = SecCopyErrorMessageString(status, nil) as? String ?? "unknown"
            return "Keychain error \(status): \(detail)"
        case .invalidPayload:
            return "Keychain payload is not valid UTF-8"
        }
    }
}

/// 通用 Keychain 存取层（`kSecClassGenericPassword`）。
///
/// **本层刻意不认识 provider / 账号模型**：条目身份 = `owner` + `kind` 两个字符串，
/// 由调用方按约定组合。这样它只依赖 Foundation + Security，可以脱离模型层独立自检
/// （见 `Scripts/KeychainSelftest`），而类型化的账号门面在 `AccountCredentialStore`。
///
/// 硬性约束（HANDOVER §53）：
/// 1. 凭证只存 Keychain。**绝不**写进 SwiftData 字段、`BackupDTO`、`UserDefaults`、日志或崩溃报告。
/// 2. 可访问性 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`。**`ThisDeviceOnly` 是关键**：
///    不加它条目会随 iCloud 钥匙串同步到用户其他设备，等于把凭证送上云 —— 正是本项目
///    「不做云同步、凭证不出本机」红线的反面。用 `AfterFirstUnlock` 而非 `WhenUnlocked`，
///    是为了让开机后未解锁窗口内的后台同步仍能读到。
/// 3. 解绑必须 `deleteAll(owner:kinds:)` 清干净。
/// 4. 凭证值只在内存中以 `String` 短暂存在，不进任何持久化路径。
///
/// ⚠️ **平台差异（2026-09-15 实测所得，不是推断）**：
/// `ThisDeviceOnly` 只在 data-protection keychain 上生效。
/// - **iOS**：系统只有 data-protection keychain → 该保证**完整成立**，凭证既不同步到
///   iCloud 钥匙串，也不进 iCloud/iTunes 备份。这是本功能的主战场。
/// - **macOS**：本项目是 **adhoc 签名、无 TeamIdentifier**（`codesign -dv` 实测
///   `Signature=adhoc` / `TeamIdentifier=not set`），**用不了 data-protection keychain**：
///   实测 `SecItemAdd` 带 `kSecUseDataProtectionKeychain` → `-34018 missing entitlement`；
///   补 `keychain-access-groups` / `application-identifier` entitlement 后二进制被内核
///   SIGKILL（受限 entitlement 需要真实签名身份）。因此 macOS 落到**文件式登录钥匙串**，
///   那里 `kSecAttrAccessible` 被静默忽略（实测带它写入仍返回 0，但回读不到该属性）——
///   **即 macOS 上「不同步 iCloud / 只在本机」给不出机制保证**。
///   要补齐：取得签名身份后在 target 上加 `keychain-access-groups` entitlement，
///   届时把 `#if os(macOS)` 那行放开即可自动升级为强保证。
///   （注：macOS 没有 iOS 意义上的整机 iCloud 备份，此项风险限于 iCloud 钥匙串同步。）
enum KeychainStore {
    /// 统一 service（同一 app 内按用途隔离条目）。
    static let service = "com.abcleg.GameLog.externalAccounts"

    /// 基础 query。
    ///
    /// 刻意**不**在 macOS 上设 `kSecUseDataProtectionKeychain` —— 实测该 flag 在无签名
    /// 身份时会直接 `-34018` 失败，且失败在整个流程里是「凭证写不进去」的硬故障。
    /// 宁可退到 legacy 钥匙串（能工作）也不要想当然。
    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
    }

    /// 定位一条目（2026-09-23 起仅用于旧条目探测/迁移；常规读写走 bundleQuery）。
    private static func query(owner: String, kind: String) -> [String: Any] {
        var q = baseQuery
        q[kSecAttrAccount as String] = "\(owner).\(kind)"
        return q
    }

    // MARK: - 单条目 bundle（每账号一条 Keychain 条目）
    //
    // 历史上每个 (owner, kind) 各占一条目。macOS 侧本应用是 adhoc/本地签名，钥匙串 ACL
    // 绑定 cdhash —— 每次更新重装，旧条目首次读取都会重新弹密码确认，PSN 一类双凭证账号
    // 就是两次。合并为每账号一条（payload = {kind: value} 的 JSON）后弹窗减半再减半；
    // 旧散条目在首次触达该 owner 时自动迁入 bundle 并删除（迁移读取本身会各弹一次，
    // 属一次性成本，迁完即绝）。
    //
    // ⚠️ 对外 API 签名（set/get/has/delete/deleteAll，owner+kind 两字符串）保持不变，
    // 门面层与 KeychainSelftest 无需感知本改造。
    private static let bundleLock = NSLock()

    private static func bundleQuery(owner: String) -> [String: Any] {
        var q = baseQuery
        q[kSecAttrAccount as String] = owner
        return q
    }

    /// 读 bundle；不存在返回 nil。
    private static func readBundle(owner: String) throws -> [String: String]? {
        var q = bundleQuery(owner: owner)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let map = try? JSONDecoder().decode([String: String].self, from: data) else {
                throw KeychainError.invalidPayload
            }
            return map
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// 写 bundle（新增或整体覆盖）。可访问性只在 add 时定死，update 改不了也不需要改。
    private static func writeBundle(_ map: [String: String], owner: String) throws {
        guard let data = try? JSONEncoder().encode(map) else { throw KeychainError.invalidPayload }
        var add = bundleQuery(owner: owner)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecDuplicateItem else {
            guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
            return
        }
        let updateStatus = SecItemUpdate(bundleQuery(owner: owner) as CFDictionary,
                                         [kSecValueData as String: data] as CFDictionary)
        guard updateStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    /// 旧 (owner, kind) 散条目 → bundle，并逐条删除。返回 nil = 无任何旧条目。
    /// 按 `ExternalCredentialKind` 全量逐个探测（该枚举本就定义于本文件）：macOS 传统文件
    /// 钥匙串不支持 `kSecMatchLimitAll` 连数据枚举（实测返回不了条目），逐 kind 精确查询才可靠。
    private static func migrateLegacy(owner: String) -> [String: String]? {
        var bundle: [String: String] = [:]
        for kind in ExternalCredentialKind.allCases.map(\.rawValue) {
            var q = query(owner: owner, kind: kind)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data,
                  let value = String(data: data, encoding: .utf8) else { continue }
            bundle[kind] = value
            // 直删旧散条目（不经 delete()——它走 bundle 路径，会递归回本函数）。
            SecItemDelete(query(owner: owner, kind: kind) as CFDictionary)
        }
        return bundle.isEmpty ? nil : bundle
    }

    /// bundle 读-改-写临界区（`change` 返回是否有实际变更；无变更不落盘）。
    /// 清空全部 kind 时连条目一起删，不留空 JSON。
    private static func mutateBundle(owner: String, _ change: (inout [String: String]) -> Bool) throws -> Bool {
        bundleLock.lock()
        defer { bundleLock.unlock() }
        var bundle = try readBundle(owner: owner) ?? [:]
        if bundle.isEmpty, let legacy = migrateLegacy(owner: owner) {
            bundle = legacy
        }
        guard change(&bundle) else { return false }
        if bundle.isEmpty {
            SecItemDelete(bundleQuery(owner: owner) as CFDictionary)
        } else {
            try writeBundle(bundle, owner: owner)
        }
        return true
    }

    // MARK: - 增 / 改

    /// 写入（已存在则覆盖）。
    static func set(_ value: String, owner: String, kind: String) throws {
        _ = try mutateBundle(owner: owner) { $0[kind] = value; return true }
    }

    // MARK: - 读

    /// 读取；不存在返回 nil（**不抛错** —— 「没绑定」是正常状态，不是错误）。
    static func get(owner: String, kind: String) throws -> String? {
        bundleLock.lock()
        defer { bundleLock.unlock() }
        if let bundle = try readBundle(owner: owner) { return bundle[kind] }
        if let legacy = migrateLegacy(owner: owner) {
            try writeBundle(legacy, owner: owner)
            return legacy[kind]
        }
        return nil
    }

    /// 是否存在（不解码内容，用于「凭证是否还在」的状态判定）。
    static func has(owner: String, kind: String) -> Bool {
        var q = bundleQuery(owner: owner)
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        if SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess {
            // bundle 在，但要看具体 kind；bundle 存在时以解码内容为准。
            return ((try? get(owner: owner, kind: kind)) ?? nil) != nil
        }
        // bundle 不在：旧散条目可能还在（尚未迁移），按旧格式探测。
        var legacy = query(owner: owner, kind: kind)
        legacy[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(legacy as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - 删

    /// 删除单个；不存在返回 false（幂等，不抛错）。
    @discardableResult
    static func delete(owner: String, kind: String) throws -> Bool {
        // 先按 bundle 删；bundle 不存在时兜底直删旧散条目（幂等）。
        let touched = try mutateBundle(owner: owner) { bundle in
            guard bundle[kind] != nil else { return false }
            bundle[kind] = nil
            return true
        }
        if touched { return true }
        let status = SecItemDelete(query(owner: owner, kind: kind) as CFDictionary)
        return status == errSecSuccess
    }

    /// 删除某 owner 下的全部凭证 —— **解绑时必须调用**。
    /// bundle 化后是单条目整体删除；旧散条目一并探测清理，防迁移前解绑留孤儿。
    static func deleteAll(owner: String, kinds: [String]) throws {
        _ = try mutateBundle(owner: owner) { bundle in
            let had = !bundle.isEmpty
            bundle.removeAll()
            return had
        }
        for kind in kinds {
            let status = SecItemDelete(query(owner: owner, kind: kind) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.unexpectedStatus(status)
            }
        }
    }
}
