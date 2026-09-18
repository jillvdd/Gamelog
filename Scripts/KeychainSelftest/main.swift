// KeychainStore 自检入口（不能放进 GameLog/ 同步文件夹，否则会作为应用模块编译）。
//
// 覆盖：增 / 读 / 改 / 删 / 不存在时读返回 nil / 删不存在不抛错 / deleteAll / 值保真（含非 ASCII）/
//       真实 `ExternalCredentialKind` 全量走一遍 deleteAll（= 解绑清凭证那条路径）/ kind 数量哨兵。
//
// 运行方式（工程根目录；**本层只依赖 Foundation + Security，不需要 -sdk 加宏插件**）：
//   swiftc -o /tmp/keychain_selftest GameLog/Support/KeychainStore.swift Scripts/KeychainSelftest/main.swift && /tmp/keychain_selftest
//
// 注意：会真的写系统钥匙串（service = com.abcleg.GameLog.externalAccounts.selftest），
// 用的是独立 owner 前缀与独立的 service 后缀，跑完自行清理，不碰真实账号凭证。
import Foundation

let owner = "selftest.\(UUID().uuidString)"
let kinds = ["alpha", "beta", "gamma"]
var passed = 0
var failed = 0

func check(_ label: String, _ condition: Bool) {
    if condition { passed += 1; print("PASS \(label)") }
    else { failed += 1; print("FAIL \(label)") }
}

do {
    // ① 还没写 → get 返回 nil，has 为 false
    check("未写入时 get 返回 nil", try KeychainStore.get(owner: owner, kind: "alpha") == nil)
    check("未写入时 has 为 false", !KeychainStore.has(owner: owner, kind: "alpha"))

    // ② 增
    try KeychainStore.set("session-value-1", owner: owner, kind: "alpha")
    check("写入后可读回", try KeychainStore.get(owner: owner, kind: "alpha") == "session-value-1")
    check("写入后 has 为 true", KeychainStore.has(owner: owner, kind: "alpha"))

    // ③ 改（同 owner+kind 覆盖）
    try KeychainStore.set("session-value-2", owner: owner, kind: "alpha")
    check("覆盖写后读到新值", try KeychainStore.get(owner: owner, kind: "alpha") == "session-value-2")

    // ④ 值保真：非 ASCII + 特殊字符（NPSSO 是 base64、session_token 是长串，
    //    这里额外验证 UTF-8 往返不出错）
    let tricky = "日本語テスト|🎮|a=b&c=?d#e|\(String(repeating: "x", count: 4096))"
    try KeychainStore.set(tricky, owner: owner, kind: "beta")
    check("非 ASCII / 特殊字符 / 长串保真", try KeychainStore.get(owner: owner, kind: "beta") == tricky)

    // ⑤ kind 之间互不串味
    check("不同 kind 互相隔离", try KeychainStore.get(owner: owner, kind: "gamma") == nil)

    // ⑥ 不同 owner 之间互不串味
    let otherOwner = "selftest.\(UUID().uuidString)"
    try KeychainStore.set("other", owner: otherOwner, kind: "alpha")
    check("不同 owner 互相隔离",
          try KeychainStore.get(owner: owner, kind: "alpha") == "session-value-2"
          && (try KeychainStore.get(owner: otherOwner, kind: "alpha")) == "other")

    // ⑦ 删
    check("删除已存在条目返回 true", try KeychainStore.delete(owner: owner, kind: "alpha"))
    check("删除后 get 返回 nil", try KeychainStore.get(owner: owner, kind: "alpha") == nil)
    check("删除后 has 为 false", !KeychainStore.has(owner: owner, kind: "alpha"))
    check("删除不存在条目返回 false 且不抛错",
          try KeychainStore.delete(owner: owner, kind: "alpha") == false)

    // ⑧ deleteAll
    try KeychainStore.deleteAll(owner: owner, kinds: kinds)
    check("deleteAll 后 beta 清空", try KeychainStore.get(owner: owner, kind: "beta") == nil)
    check("deleteAll 后 gamma 仍为空", try KeychainStore.get(owner: owner, kind: "gamma") == nil)

    // ⑨ 真实 kind 集合：解绑路径的形状，以及一条有意留下的哨兵。
    //
    // 上面 ①–⑧ 验的是「这台机器上的钥匙串能不能增删改查」，用合成 kind 就够了；
    // 这一段改用**真实 kind**，因为解绑走的正是下面这行表达式
    //（`AccountCredentialStore.deleteAll` → `KeychainStore.deleteAll(kinds: allCases.map(\.rawValue))`）。
    // 真实 rawValue 有没有哪个字符会破坏查询、deleteAll 会不会漏掉某一项 —— 这两件事
    // 合成 kind 测不出来，编译期也管不着（负向实验见下）。
    let realKindValues = ExternalCredentialKind.allCases.map(\.rawValue)
    for kind in realKindValues {
        try KeychainStore.set("v-\(kind)", owner: owner, kind: kind)
    }
    check("真实 kind 全部写进且各自读回",
          realKindValues.allSatisfy { (try? KeychainStore.get(owner: owner, kind: $0)) == "v-\($0)" })
    try KeychainStore.deleteAll(owner: owner, kinds: realKindValues)
    check("deleteAll(真实 kinds) 后一个都不剩（= 解绑时凭证清干净的那条路径）",
          realKindValues.allSatisfy { (try? KeychainStore.get(owner: owner, kind: $0)) == nil })

    // 哨兵：新增 kind 时这条会响，逼一次「它要不要在解绑时被删」的有意确认。
    // （`deleteAll` 走的是 `allCases`，所以答案是自动的「要」—— 真正要确认的是
    //  **这个新 kind 是不是真该在解绑时被删**，比如未来加一条「设备级、与账号无关」的凭证就不是。）
    check("kind 数量哨兵 = 4（nintendoSessionToken / psnNPSSO / psnRefreshToken / xboxAPIKey）",
          ExternalCredentialKind.allCases.count == 4)

    // ⚠️ 两条**看起来该有、实际是废话**的断言，故意不写在这儿，但把负向实验的结论记下来，
    //    免得下一个人（或下一次的我）再补一遍：
    //    - 「每个 kind 的 rawValue 非空」：`case foo` 自动得到 "foo"，写不出空串。
    //    - 「rawValue 互不相同」：2026-09-18 实测，给两个 case 同一个 rawValue 会**编译不过**
    //      （`error: raw value for enum case is not unique`）。
    //    - 「`.xboxAPIKey` 在 allCases 里」：把 `case xboxAPIKey` 摘掉再编，也是**编译不过**
    //      （`AccountCredentialStore` 的 `case .xbox: .xboxAPIKey` 与 `ExternalSyncDriver` 的
    //      `kind: .xboxAPIKey` 两处引用直接报错）。
    //    三条都被编译器兜住了 ⇒ 写成运行时断言只会提供**虚假的覆盖感**：
    //    它们永远 PASS，而真出问题时也不会是它们先响。

    // 清理另一 owner
    try KeychainStore.deleteAll(owner: otherOwner, kinds: kinds)

    // 清理另一 owner
    try KeychainStore.deleteAll(owner: otherOwner, kinds: kinds)
} catch {
    failed += 1
    print("FAIL 抛错：\(error.localizedDescription)")
}

print("")
print("KeychainSelftest: \(passed) PASS, \(failed) FAIL")
exit(failed == 0 ? 0 : 1)
