import SwiftUI
import SwiftData
import AuthenticationServices
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 添加（或重新绑定）一个外部账号。
///
/// 三个 provider 的绑定方式不同，**原因写在界面上而不是藏进文档**：
/// - Nintendo：走**系统登录会话**（`ASWebAuthenticationSession`）。浏览器里登的是任天堂自己的
///   页面，我们既看不到也不经手密码，只能拿到最后那一次跳转。
/// - PlayStation：Sony 的登录回调挂在 Android PS App 的 scheme 上，系统登录会话收不到那个
///   跳转，所以只能请用户从 Sony 自己的页面复制 NPSSO。**同样不要求、也拿不到 Sony 密码。**
/// - Xbox：用户从 `xbl.io/dashboard` 自己建一把 Personal API Key 再粘进来。
///   ⚠️ **这一家与另外两家的性质不同**：key 与请求内容会经过 OpenXBL 这台**第三方服务器**
///   （微软官方那条链对个人微软账号走不通，见 `XboxAPI` 文件头）。所以这里的文案必须
///   **把这件事说出来**，而不是含糊地写成「官方接口」—— 用户有权在按下按钮前知道。
///
/// ⚠️ 用户填进来的凭证（NPSSO / OpenXBL key / 回调原文）只活在 `@State` 里，用完即随视图释放；
/// 不落 UserDefaults、不进日志、不进备份。
struct AddExternalAccountView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appLanguageCode) private var language
    @Environment(\.dismiss) private var dismiss
    /// 打开浏览器取凭证（PSN 那两个按钮）。用系统默认浏览器而**不是**应用内
    /// `SFSafariViewController` —— 这一点是功能性的，见 `playStationBrowserSection`。
    @Environment(\.openURL) private var openURL

    /// 绑定成功后回调（列表页据此立刻发起一次同步）。
    private let onLinked: ((LinkedAccount) -> Void)?

    @State private var provider: AccountProvider
    @State private var busy = false
    @State private var errorKey: String?

    /// PSN：用户粘贴的 NPSSO 原文。
    @State private var npsso = ""
    /// Xbox：用户粘贴的 OpenXBL Personal API Key 原文。
    @State private var xboxAPIKey = ""
    /// Nintendo：手工粘贴的跳转链接原文。
    @State private var pastedCallback = ""
    /// Nintendo：标题与封面语言（**在绑定前就定下来**，这样第一次同步拿回的就是用户要的语言，
    /// 而不是先拿一次 App 语言的、再让用户去改）。
    @State private var titleLocale: ExternalTitleLocale = .followApp
    /// 本次登录请求（含只在内存里活着的 `codeVerifier`）。
    @State private var loginRequest: NintendoLoginRequest?
    /// 系统登录会话必须被强引用持有，否则会被立刻释放、回调永不回来。
    @State private var authSession: NintendoWebAuthSession?

    init(initialProvider: AccountProvider = .nintendo,
         onLinked: ((LinkedAccount) -> Void)? = nil) {
        self.onLinked = onLinked
        _provider = State(initialValue: initialProvider)
    }

    var body: some View {
        // macOS 上 sheet 自带窗口工具栏，再包 `NavigationStack` 会多出一条空导航栏
        //（与 `GameEditView` / `BannerSearchSheet` / 库页各 sheet 同一口径）。
        #if os(macOS)
        form
            // 表单型 sheet 用 min 尺寸（与 `GameEditView` 同口径）：内容多时窗口可拉大，
            // 而固定 width/height 会把它锁死。
            .frame(minWidth: 520, minHeight: 560)
        #else
        NavigationStack { form }
        #endif
    }

    private var form: some View {
        Form {
            // 只把表单内容禁用掉，**不能**把 `.disabled(busy)` 套到 `.toolbar` 外层：
            // 那样连「取消」也会一起变灰，一次慢速联网的绑定会让用户连退出的按钮都按不到。
            // （修饰符自外向内生效，`.toolbar` 的内容会继承它外层环境里的 isEnabled。）
            Group {
                Section(L10n.tr("account.add.platform", lang: language)) {
                    Picker(L10n.tr("account.add.platform", lang: language), selection: $provider) {
                        ForEach(AccountProvider.allCases) { provider in
                            // 短名而不是 `brandName`：三段平分一行，全名在 iPhone 上会被截断
                            //（见 `AccountProvider.shortBrandName`）。
                            Text(verbatim: provider.shortBrandName).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // 语言选择器摆在最前：它决定**第一次同步**就抓回什么语言的标题与封面，
                // 绑完再改就得整库重来一遍。两家的机制不同但选择是同一个，所以这一段
                // 不分 provider —— 具体差异写在 footer 与各自的分区里。
                Section {
                    Picker(L10n.tr("account.titleLocale.title", lang: language), selection: $titleLocale) {
                        ForEach(ExternalTitleLocale.allCases) { locale in
                            Text(verbatim: L10n.tr(locale.labelKey, lang: language))
                                .tag(locale)
                        }
                    }
                } header: {
                    Text(verbatim: L10n.tr("account.titleLocale.header", lang: language))
                } footer: {
                    LText("account.add.titleLocaleHint")
                }

                switch provider {
                case .nintendo: nintendoSections
                case .playstation: playStationSection
                case .xbox: xboxSection
                }

                if let errorKey {
                    Section {
                        LText(errorKey)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }
            .disabled(busy)
        }
        .formStyle(.grouped)
        .navigationTitle(L10n.tr("account.add.title", lang: language))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.tr("common.cancel", lang: language)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .overlay {
            if busy {
                ProgressView(L10n.tr("account.add.connecting", lang: language))
                    .padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    // MARK: - Nintendo

    @ViewBuilder
    private var nintendoSections: some View {
        Section {
            Button { startNintendoLogin() } label: {
                Label(L10n.tr("account.add.nintendoSignIn", lang: language), systemImage: "safari")
            }
            .appStandardButton()
        } footer: {
            LText("account.add.nintendoSignInHint")
        }

        Section {
            // 用 `axis: .vertical` 的多行输入：粘进来的是完整 URL，单行框会把它藏掉大半。
            TextField(L10n.tr("account.add.nintendoPastePlaceholder", lang: language),
                      text: $pastedCallback, axis: .vertical)
                .lineLimit(2...4)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Button { completeNintendo(callback: pastedCallback) } label: {
                Label(L10n.tr("account.add.nintendoPasteConfirm", lang: language),
                      systemImage: "checkmark.circle")
            }
            .appStandardButton()
            .disabled(!canSubmitPastedCallback)
        } header: {
            // 带 footer 的分区只能把标题写在 header 闭包里（`Section(_:content:footer:)` 只吃
            // LocalizedStringKey，我们的标题是运行时查出来的 String）。同 SettingsView。
            Text(verbatim: L10n.tr("account.add.nintendoPasteLabel", lang: language))
        } footer: {
            LText("account.add.nintendoPasteHint")
        }
    }

    /// 手工粘贴只在**已经起过一次登录**之后才有意义 —— `codeVerifier` 与 `state` 都活在那次请求里，
    /// 没有它就没法完成换取。按钮 disabled 而不是弹错，是因为这纯粹是操作顺序问题。
    private var canSubmitPastedCallback: Bool {
        loginRequest != nil
            && !pastedCallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !busy
    }

    // MARK: - PlayStation

    @ViewBuilder
    private var playStationSection: some View {
        // 把「登录 Sony」与「取 NPSSO」做成两个按钮，用户不必自己记、自己敲那两个 URL。
        //
        // ⚠️ 必须用 `openURL`（走**系统默认浏览器**）而不是应用内 `SFSafariViewController`：
        // NPSSO 是**浏览器会话 cookie 的产物**，而 Sony 的登录把会话种在 `sony.com` 域上、
        // 取 NPSSO 的页面在 `ca.account.sony.com`，两个域要共享同一份 cookie jar。
        // 应用内视图有自己独立的 cookie 容器 —— 用户在它里面登了录，第二个页面照样是未登录。
        //
        // 两个按钮都**不禁用**（外层 `Group` 的 `.disabled(busy)` 已经覆盖了忙碌态，与既有口径一致）。
        Section {
            if let signInURL = PSNAPI.signInURL {
                Button {
                    openURL(signInURL)
                } label: {
                    Label(L10n.tr("account.add.psnSignIn", lang: language),
                          systemImage: "person.crop.circle.badge.checkmark")
                }
                .appStandardButton()
            }
            if let npssoURL = PSNAPI.npsscoCookieURL {
                Button {
                    openURL(npssoURL)
                } label: {
                    Label(L10n.tr("account.add.psnNpssoPage", lang: language),
                          systemImage: "doc.on.clipboard")
                }
                .appStandardButton()
            }
        } footer: {
            LText("account.add.psnBrowserHint")
        }

        Section {
            // SecureField：NPSSO 是货真价实的凭证，不该明晃晃摆在屏幕上。
            // 长度门（满 64 位才放行）兼作「粘对了吗」的即时反馈。
            SecureField(L10n.tr("account.add.npssoPlaceholder", lang: language), text: $npsso)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Button { linkPlayStation() } label: {
                Label(L10n.tr("account.add.npssoConfirm", lang: language), systemImage: "link")
            }
            .appStandardButton()
            .disabled(!canSubmitNPSSO)
        } header: {
            Text(verbatim: "NPSSO")
        } footer: {
            LText("account.add.npssoHint")
        }
    }

    private var canSubmitNPSSO: Bool {
        npsso.trimmingCharacters(in: .whitespacesAndNewlines).count == 64 && !busy
    }

    // MARK: - Xbox

    @ViewBuilder
    private var xboxSection: some View {
        // 与 PSN 那两个按钮同一性质：把用户送到**服务方自己的**页面去拿码，
        // 我们不代收密码、不代注册、也不碰用户的微软账号。
        //
        // ⚠️ 只有**一个**按钮，不像 PSN 要「先登录、再取码」两步 —— 因为 OpenXBL 的 key 是
        //    用户在自己的 dashboard 上建的，与微软账号的登录状态无关（严格说用户得先在
        //    xbl.io 上登一次自己的微软账号，但那一步发生在我们送过去的那个页面上）。
        Section {
            if let dashboardURL = XboxAPI.dashboardURL {
                Button {
                    openURL(dashboardURL)
                } label: {
                    Label(L10n.tr("account.add.xboxDashboard", lang: language),
                          systemImage: "key")
                }
                .appStandardButton()
            }
        } footer: {
            // 这段脚注是本次里唯一一处**必须**说清第三方中转的地方 ——
            // 它不是免责声明，是用户做决定需要的事实（见本视图头部）。
            LText("account.add.xboxBrowserHint")
        }

        Section {
            // SecureField：这把 key 既是凭证又是**配额身份**（泄露 = 别人用你的额度），
            // 与 NPSSO 同级，不该明晃晃摆在屏幕上。
            SecureField(L10n.tr("account.add.xboxKeyPlaceholder", lang: language), text: $xboxAPIKey)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Button { linkXbox() } label: {
                Label(L10n.tr("account.add.xboxKeyConfirm", lang: language), systemImage: "link")
            }
            .appStandardButton()
            .disabled(!canSubmitXboxKey)
        } header: {
            // 走 L10n 而不是 `Text(verbatim:)`：隔壁 PSN 那个 `"NPSSO"` 是纯缩写（哪个语言都一样），
            // 这一条不是 —— 「API Key」在日中两语里是有写法的（对等审计 GAP 3）。
            Text(verbatim: L10n.tr("account.add.xboxKeyHeader", lang: language))
        } footer: {
            LText("account.add.xboxKeyHint")
        }
    }

    /// ⚠️ 与 NPSSO 那个「满 64 位才放行」不同，这里**只有「非空」**一道门。
    ///
    /// OpenXBL 的 key 是一串不透明字符串，长度与字符集**没有任何可靠资料** —— 编一条规则
    /// 出来最可能的结局是在某天误伤一把真 key，而用户完全不知道为什么按钮是灰的。
    /// 真伪交给服务端判（`resolveIdentity()` 打一次 `GET /v2/account`），
    /// 理由详见 `ExternalAccountBinder.linkXbox`。
    private var canSubmitXboxKey: Bool {
        !xboxAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy
    }

    // MARK: - 动作

    private func startNintendoLogin() {
        errorKey = nil
        do {
            let request = try ExternalAccountBinder.makeNintendoLoginRequest()
            loginRequest = request
            let session = NintendoWebAuthSession()
            authSession = session
            busy = true
            Task { @MainActor in
                let callback = await session.start(url: request.url,
                                                   callbackURLScheme: NintendoAPI.callbackURLScheme)
                busy = false
                authSession = nil
                // nil = 用户取消 / 会话没起来。两种情况都不该报错刷屏：
                // 取消是用户的正当选择，而没起来时手工粘贴那条路仍然可用。
                guard let callback else { return }
                completeNintendo(callback: callback)
            }
        } catch let error as ExternalAPIError {
            errorKey = error.messageKey
        } catch {
            errorKey = "account.syncError.unknown"
        }
    }

    private func completeNintendo(callback: String) {
        guard let request = loginRequest else { return }
        let raw = callback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        errorKey = nil
        busy = true
        Task { @MainActor in
            do {
                let outcome = try await ExternalAccountBinder.completeNintendoLogin(
                    callback: raw, request: request, in: context,
                    language: AppLanguage(localeCode: language),
                    titleLocale: titleLocale)
                finish(with: outcome)
            } catch let error as AccountLinkError {
                busy = false
                errorKey = error.messageKey
            } catch {
                busy = false
                errorKey = "account.syncError.unknown"
            }
        }
    }

    private func linkPlayStation() {
        let raw = npsso.trimmingCharacters(in: .whitespacesAndNewlines)
        errorKey = nil
        busy = true
        Task { @MainActor in
            do {
                let outcome = try await ExternalAccountBinder.linkPlayStation(
                    npsso: raw, in: context, language: AppLanguage(localeCode: language),
                    titleLocale: titleLocale)
                finish(with: outcome)
            } catch let error as AccountLinkError {
                busy = false
                errorKey = error.messageKey
            } catch {
                busy = false
                errorKey = "account.syncError.unknown"
            }
        }
    }

    private func linkXbox() {
        let raw = xboxAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        errorKey = nil
        busy = true
        Task { @MainActor in
            do {
                let outcome = try await ExternalAccountBinder.linkXbox(
                    apiKey: raw, in: context, language: AppLanguage(localeCode: language),
                    titleLocale: titleLocale)
                finish(with: outcome)
            } catch let error as AccountLinkError {
                busy = false
                errorKey = error.messageKey
            } catch {
                busy = false
                errorKey = "account.syncError.unknown"
            }
        }
    }

    /// 绑定成功：先把手里的凭证原料擦掉，再交回给上层。
    private func finish(with outcome: ExternalAccountBinder.LinkOutcome) {
        npsso = ""
        xboxAPIKey = ""
        pastedCallback = ""
        loginRequest = nil
        authSession = nil
        busy = false
        if let onLinked {
            onLinked(outcome.account)
        } else {
            dismiss()
        }
    }
}

// MARK: - 系统登录会话

/// `ASWebAuthenticationSession` 的薄包装：把闭包回调改写成 async。
///
/// 为什么用系统会话而不是自建 `WKWebView`：会话跑在浏览器进程里，
/// **用户在任天堂页面输入的任何东西我们都看不到**，只能拿到最后那一次跳转。
/// 自建 WebView 反而会让我们有能力去读页面内容 —— 那正是要避免的。
///
/// ⚠️ 本类只往下传**回调 URL 原文**，不解析、不打印、不落盘（解析在 `NintendoAPI.parseCallback`）。
///
/// ⚠️ 未知项（见 HANDOVER §53）：`ASWebAuthenticationSession` 是否需要把回调 scheme 注册进
/// `CFBundleURLTypes` 才能回跳，本次未能从一手资料确认。按「不需要」实现，
/// 因此**手工粘贴那条路不是装饰**：万一系统会话收不到回跳，用户仍能完成绑定。
@MainActor
final class NintendoWebAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func start(url: URL, callbackURLScheme: String) async -> String? {
        await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url,
                                                     callbackURLScheme: callbackURLScheme) { callback, _ in
                // 用户取消时走 error 分支、callback 为 nil —— 与「会话没起来」同一种收场。
                continuation.resume(returning: callback?.absoluteString)
            }
            session.presentationContextProvider = self
            // 与浏览器共用 cookie：已经登过任天堂账号的用户不必再登一次。
            // 共用的是**浏览器的** cookie，不是我们的 —— 任天堂密码从头到尾没进过本应用。
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
        #else
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        #endif
    }
}
