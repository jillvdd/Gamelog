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

    /// 定位一条目。
    private static func query(owner: String, kind: String) -> [String: Any] {
        var q = baseQuery
        q[kSecAttrAccount as String] = "\(owner).\(kind)"
        return q
    }

    // MARK: - 增 / 改

    /// 写入（已存在则覆盖）。
    ///
    /// 先 `SecItemAdd`，撞 `errSecDuplicateItem` 再转 `SecItemUpdate` ——
    /// 比「先查再写」少一次往返，也没有查与写之间的竞态。
    static func set(_ value: String, owner: String, kind: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.invalidPayload }

        var addQuery = query(owner: owner, kind: kind)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // 已存在：只改数据。可访问性在 add 时定死，update 改不了（也不需要改）。
            let attributes: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query(owner: owner, kind: kind) as CFDictionary,
                                             attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - 读

    /// 读取；不存在返回 nil（**不抛错** —— 「没绑定」是正常状态，不是错误）。
    static func get(owner: String, kind: String) throws -> String? {
        var q = query(owner: owner, kind: kind)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidPayload
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// 是否存在（不解码内容，用于「凭证是否还在」的状态判定）。
    static func has(owner: String, kind: String) -> Bool {
        var q = query(owner: owner, kind: kind)
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - 删

    /// 删除单个；不存在返回 false（幂等，不抛错）。
    @discardableResult
    static func delete(owner: String, kind: String) throws -> Bool {
        let status = SecItemDelete(query(owner: owner, kind: kind) as CFDictionary)
        switch status {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            return false
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// 删除某 owner 下的全部 kind —— **解绑时必须调用**。
    /// 逐个 kind 删而非按 service 批量删：Keychain 不支持前缀匹配，
    /// 而 kind 是有限枚举，遍历比引入查询更可预测。
    static func deleteAll(owner: String, kinds: [String]) throws {
        for kind in kinds {
            try delete(owner: owner, kind: kind)
        }
    }
}
