import Foundation

/// 账号凭证的类型化门面 —— **全项目唯一**该被外部调用的凭证出入口。
///
/// 存在的理由：`KeychainStore` 只认 `owner` / `kind` 两个字符串。如果让每个 provider
/// 各自拼 owner，格式一旦不一致（少个分隔符、大小写不同），**解绑时就会删不掉凭证** ——
/// 那是最糟的失败模式：用户以为解绑了，凭证还躺在钥匙串里。
/// 所以 owner 的拼法只在这里定义一次，所有调用点走这里。
///
/// 凭证种类与用途见 `ExternalCredentialKind`；安全保证与平台差异见 `KeychainStore` 头部。
enum AccountCredentialStore {
    /// owner 键的唯一来源：`<providerRaw>.<localId>`。
    static func owner(for provider: AccountProvider, localId: UUID) -> String {
        "\(provider.rawValue).\(localId.uuidString)"
    }

    // MARK: - 增 / 读 / 查 / 删

    static func set(_ value: String, kind: ExternalCredentialKind,
                    provider: AccountProvider, localId: UUID) throws {
        try KeychainStore.set(value, owner: owner(for: provider, localId: localId), kind: kind.rawValue)
    }

    static func get(kind: ExternalCredentialKind,
                    provider: AccountProvider, localId: UUID) throws -> String? {
        try KeychainStore.get(owner: owner(for: provider, localId: localId), kind: kind.rawValue)
    }

    static func has(kind: ExternalCredentialKind,
                    provider: AccountProvider, localId: UUID) -> Bool {
        KeychainStore.has(owner: owner(for: provider, localId: localId), kind: kind.rawValue)
    }

    @discardableResult
    static func delete(kind: ExternalCredentialKind,
                       provider: AccountProvider, localId: UUID) throws -> Bool {
        try KeychainStore.delete(owner: owner(for: provider, localId: localId), kind: kind.rawValue)
    }

    /// 解绑：删除该账号**全部**凭证。**解绑流程必须调用本方法**，之后才允许删 `LinkedAccount` 对象
    /// （对象一删就再也拿不到 `localId`，凭证会永久残留）。
    static func deleteAll(provider: AccountProvider, localId: UUID) throws {
        try KeychainStore.deleteAll(owner: owner(for: provider, localId: localId),
                                    kinds: ExternalCredentialKind.allCases.map(\.rawValue))
    }

    // MARK: - 状态校正

    /// 依据 Keychain 实况校正账号的凭证状态。
    ///
    /// 为什么需要：用户抹掉设备、手动清理钥匙串、或从备份恢复出 `LinkedAccount` 行时，
    /// 库里还留着 `active`，界面会显示「已绑定」但同步必然失败。
    /// 校验规则刻意保守 —— 只做「在 → 不在」和「不在 → 在」的翻转，
    /// **不改写 `.expired`**（那是「试过且失败了」的结论，凭证还在也仍然失效）。
    static func refreshCredentialState(of account: LinkedAccount) {
        guard account.credentialState != .none else { return }   // 绑定未完成的账号不动

        let provider = account.provider
        let present = has(kind: provider.primaryCredentialKind,
                          provider: provider, localId: account.localId)

        if !present {
            account.credentialState = .missing
        } else if account.credentialState == .missing {
            account.credentialState = .active
        }
    }
}

extension AccountProvider {
    /// 该 provider 的「主凭证」—— 判定「这个账号还能不能用」就看它在不在。
    /// Nintendo 用长期 session token（access token 由它派生）；PSN 用 NPSSO
    /// （refresh token 不轮换、会过期，NPSSO 才是可长期依赖的那个）；
    /// Xbox 用 OpenXBL 的 Personal API Key（整套鉴权就只有它，没有可派生的短期 token）。
    var primaryCredentialKind: ExternalCredentialKind {
        switch self {
        case .nintendo: .nintendoSessionToken
        case .playstation: .psnNPSSO
        case .xbox: .xboxAPIKey
        }
    }
}
