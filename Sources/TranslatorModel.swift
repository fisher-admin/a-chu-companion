import AppKit
import SwiftUI
import Translation

@MainActor
final class TranslatorModel: ObservableObject {
    let replies = ReplyMonitor()
    let cliNotices = CLINoticeMonitor()
    let health = HealthCenter()
    let bridge = BridgeCoordinator()
    var testTranslation: (@MainActor (String) async throws -> String)?
    var testFallback: (@MainActor (String) async throws -> String)?
    func refreshHealth() {
        refreshPermission()
        let key = "\(self.permission):\(hasTarget):\(self.engine):\(self.baseURL):\(self.activeAIModel):\(self.language.rawValue):\(self.replies.watching):\(self.bridge.enabled):\(self.bridge.selected)"
        Task { [weak self] in
            guard let self else { return }
            await self.health.check(key: key) { [self] in
                var items = [HealthItem(name: "辅助功能", state: self.permission ? .ready : .unavailable, detail: self.permission ? "已开启" : "桌面连接需要权限"),
                             HealthItem(name: "回复来源", state: self.replies.watching ? .ready : .unconfigured, detail: self.replies.watching ? self.replies.sourceName : "尚未开始读取")]
                if self.engine == "apple" {
                    var state: HealthState = .unknown
                    var detail = "语言状态未确认；自检不下载语言包"
                    if !CompanionPreferences.simulated {
                        do {
                            let pair = self.language.rawValue
                            let value = try await TextTranslation.withDeadline(timeout: .seconds(5)) {
                                let status = await LanguageAvailability().status(from: Locale.Language(identifier: "zh-Hans"), to: Locale.Language(identifier: pair))
                                switch status { case .installed: return "installed"; case .supported: return "supported"; case .unsupported: return "unsupported"; @unknown default: return "unknown" }
                            }
                            if value == "installed" { state = .ready; detail = "语言包已安装" }
                            else if value == "supported" { state = .waiting; detail = "支持该语言；首次翻译由系统确认准备" }
                            else if value == "unsupported" { state = .unavailable; detail = "系统不支持该语言组合" }
                        } catch { detail = "语言检查暂不可用；不影响显示原文" }
                    }
                    items.append(.init(name: "系统翻译", state: state, detail: detail))
                }
                else {
                    let configured = !self.activeAIModel.isEmpty && (self.engine == "gemini" || (try? AIProtocol.endpoint(self.baseURL)) != nil)
                    items.append(.init(name: "云翻译", state: configured ? .unknown : .unconfigured, detail: configured ? "配置已填写，连接测试需手动触发；自检不发送文字" : "请填写地址和模型"))
                    if let provider = RemoteTranslationProvider(rawValue:self.engine) {
                        let inspect = self.credentialPresence, base = self.baseURL
                        let presence = await Task.detached(priority: .utility) { inspect(provider, base) }.value
                        switch presence {
                        case .present: items.append(.init(name:"API 密钥",state:.ready,detail:"本机已保存；有效性须手动测试，不读取密钥正文"))
                        case .missing: items.append(.init(name:"API 密钥",state:.unconfigured,detail:"此接口未配置密钥"))
                        case .unknown: items.append(.init(name:"API 密钥",state:.unknown,detail:"未能无弹窗确认；不代表密钥缺失"))
                        }
                    }
                }
                items.append(.init(name:"CLI / Chrome",state:self.bridge.enabled ? .waiting : .unconfigured,detail:self.bridge.enabled ? self.bridge.status : "可选只读入口尚未启用，不影响当前翻译"))
                items.append(TranslationPolicy.item(engine:self.engine,baseURL:self.baseURL))
                return items
            }
        }
    }
    func markReply(id: String, complete: Bool) {
        if let i = history.firstIndex(where: { $0.id == id }), history[i].updating != !complete { history[i].updating = !complete }
    }
    struct ChatItem: Identifiable {
        let id: String
        let isUser: Bool
        var chinese: String
        var foreign: String
        var language: TranslationLanguage = .english
        var updating = false
    }
    @Published var history: [ChatItem] = []
    @Published var replyTextSize = ReplyTextSize(rawValue: CompanionPreferences.store.integer(forKey: "replyTextSize")) ?? .medium {
        didSet { CompanionPreferences.store.set(replyTextSize.rawValue, forKey: "replyTextSize") }
    }
    @Published private(set) var chatRevision = 0
    @Published private(set) var chatScrollTarget = "bottom"
    @Published private(set) var chatScrollAtTop = false
    func recordReplyOriginal(id: String, foreign: String, language: TranslationLanguage) {
        if let i = history.firstIndex(where: { $0.id == id }) {
            if history[i].foreign != foreign { history[i].updating = !history[i].chinese.isEmpty }
            history[i].foreign = foreign; history[i].language = language
        } else {
            guard !retiredReplies.contains(id) else { return }
            history.append(.init(id: id, isUser: false, chinese: "", foreign: foreign, language: language))
            requestReplyScroll(id)
        }
        trimHistory()
    }
    func recordReply(id: String, foreign: String, chinese: String, language: TranslationLanguage) {
        if let i = history.firstIndex(where: { $0.id == id }) {
            history[i].chinese = chinese; history[i].foreign = foreign
            history[i].language = language; history[i].updating = false
        } else {
            guard !retiredReplies.contains(id) else { return }
            history.append(.init(id: id, isUser: false, chinese: chinese, foreign: foreign, language: language))
            requestReplyScroll(id)
        }
        trimHistory()
    }
    private var retiredReplies: Set<String> = []
    @Published var readingHistory = false
    @Published var hasNewContent = false
    func resumeFollowing() {
        readingHistory = false; hasNewContent = false
        chatScrollTarget = "bottom"; chatScrollAtTop = false; chatRevision += 1
    }
    private func requestReplyScroll(_ id: String) {
        if readingHistory { hasNewContent = true; return }
        chatScrollTarget = id; chatScrollAtTop = true; chatRevision += 1
    }
    private func trimHistory() {
        let completed = history.filter { !$0.isUser && !$0.chinese.isEmpty }
        let removed = Set(completed.dropLast(10).map(\.id))
        retiredReplies.formUnion(removed)
        history.removeAll { removed.contains($0.id) }
        replies.retire(removed)
        // Bound drafts and untranslated replies too, without counting them as translations.
        let unfinished = history.filter { $0.isUser || $0.chinese.isEmpty }
        let extras = Set(unfinished.dropLast(20).map(\.id))
        history.removeAll { extras.contains($0.id) }
        retiredReplies.formUnion(extras); replies.retire(extras)
    }
    func clearHistory() {
        let removed = Set(history.filter { !$0.isUser }.map(\.id))
        retiredReplies.formUnion(removed)
        replies.retire(removed)
        replies.clearRecords()
        history = []; resumeFollowing()
    }
    func readVisibleReply() {
        guard let target else {
            replies.historyChoices = bridge.visibleHistory
            replies.showHistoryPicker = !replies.historyChoices.isEmpty
            if replies.historyChoices.isEmpty { report("桥接中没有已完成的可见历史回复。") }
            return
        }
        Task { await replies.readVisible(target: target, engine: engine, baseURL: baseURL, model: activeAIModel, language: language) }
    }
    @Published var input = "" {
        didSet {
            if input != oldValue && !busy {
                output = ""
                if input.count > InputPolicy.limit { report("中文内容超过 10,000 字符，请缩短后提交。草稿已完整保留。", error: true) }
                else if oldValue.count > InputPolicy.limit { report("字数已符合要求，可以提交。") }
            }
        }
    }
    @Published var output = ""
    @Published var language = TranslationLanguage(rawValue: CompanionPreferences.store.string(forKey: "targetLanguage") ?? "en") ?? .english {
        didSet {
            guard language != oldValue else { return }
            CompanionPreferences.store.set(language.rawValue, forKey: "targetLanguage")
            output = ""; configuration = nil
            replies.configure(engine: engine, baseURL: baseURL, model: activeAIModel, language: language)
            report("已选择\(language.name)，Claude 的回复将译回中文。")
        }
    }
    private var outputLanguage: TranslationLanguage = .english
    private var outputSource = ""
    @Published var busy = false
    @Published var status = "点击聊天输入框，再按 ⌃⌥E 唤出A畜伴侣。"
    @Published var isError = false
    @Published var targetName = "未选择输入框"
    @Published var hasTarget = false
    @Published private(set) var permission: Bool
    @Published var configuration: TranslationSession.Configuration?
    @Published private(set) var systemTaskID: UUID?
    @Published var showSettings = false
    @Published var showCLIPicker = false
    @Published private(set) var cliConnectionHint = ""
    private var cliCaptureFailed = false
    var isCLIConnection: Bool { pendingCLISurface != nil || (bridge.enabled && bridge.selected.hasPrefix("cli-")) }
    var showsOutgoingStatus: Bool { busy || isError || replies.status.isEmpty || !output.isEmpty }
    @Published var engine = CompanionPreferences.store.string(forKey: "engine") ?? "apple"
    @Published var baseURL = CompanionPreferences.store.string(forKey: "baseURL") ?? ""
    @Published var aiModel = CompanionPreferences.store.string(forKey: "aiModel") ?? ""
    @Published var geminiModel = CompanionPreferences.store.string(forKey: "geminiModel") ?? GeminiProtocol.defaultModel
    var activeAIModel: String { engine == "gemini" ? geminiModel : aiModel }
    @Published var autoSend = CompanionPreferences.store.bool(forKey: "autoSend") {
        didSet { CompanionPreferences.store.set(autoSend, forKey: "autoSend") }
    }
    @Published var commandReturn = CompanionPreferences.store.bool(forKey: "commandReturn") {
        didSet { CompanionPreferences.store.set(commandReturn, forKey: "commandReturn") }
    }
    var revealWindow: () -> Void = {}
    var onClaudeConnection: (ClaudeUsageChannel, String?) -> Void = { _, _ in }
    var onNonClaudeConnection: (String) -> Void = { _ in }
    private let permissionMonitor: AccessibilityPermissionMonitor
    private var target: TargetBridge.Target?
    var webInputBundle: String? {
        guard let target, target.app.bundleIdentifier != "com.anthropic.claudefordesktop" else { return nil }
        return target.app.bundleIdentifier
    }
    /// Returns to the input already selected by the user. No text, clipboard,
    /// draft inspection or alternative-window search is involved.
    func restoreSelectedWebForQuota() async throws -> (url: String, browser: String?) {
        guard let target, target.app.bundleIdentifier != "com.anthropic.claudefordesktop",
              let location = outgoingTarget?.location else { throw BridgeError.message("请先在 Claude 网页输入区按 ⌃⌥E 指定窗口。") }
        try inputDelivery.validate(location)
        ManualInputDelivery.restore(location)
        for _ in 0..<16 {
            if ManualInputDelivery.focused(location) { break }
            try await Task.sleep(for:.milliseconds(50))
        }
        guard ManualInputDelivery.focused(location), let url = TargetBridge.conversationURL(location.input) else {
            throw BridgeError.message("此前指定的网页输入区暂不可用，请在该输入区重新连接。")
        }
        return (url, target.app.bundleIdentifier)
    }
    private var outgoingTarget: ManualInputDelivery.Lease?
    private var inputDelivery: ManualInputDelivery { cliDelivery.inputDelivery }
    private var cliReadAssociation: CLITargetBridge.Binding?
    private var pendingCLISurface: CLITargetBridge.Surface?
    private let cliDelivery: CLITargetBridge
    var cliCapture: () throws -> CLITargetBridge.Surface = { try CLITargetBridge.capture() }
    private var task: Task<Void, Never>?
    private var appleSession: TranslationSession?
    private var preparationWatchdog: Task<Void, Never>?
    private let applePreparationTimeout: Duration
    private let remoteKeyRead: ((RemoteTranslationProvider) throws -> String)?
    private let credentialPresence: (RemoteTranslationProvider, String) -> CredentialPresence
    private var activeID: UUID?
    private var connectionRequestID: UUID?
    private var connectionTask: Task<Void, Never>?
    private var cliBindingTask: Task<Void, Never>?
    var cliEntryRequest: @MainActor (String) async throws -> Void = { path in
        try await UsageAcquisition.run("install-cli", connection: path)
        try Task.checkCancellation()
        try await UsageAcquisition.run("request-cli")
    }
    private var pending: Job?
    private struct Job {
        let id: UUID
        let text: String
        let insert: Bool
        let destination: ManualInputDelivery.Lease?
        let send: Bool
        let commandReturn: Bool
        let language: TranslationLanguage
        /// Set when the system translation replaces a failed remote result.
        /// Retain the cause without changing the original delivery choices.
        var fallbackReason: String? = nil
        var allowEmptyDraft = false
    }

    init(permissionCheck: @escaping @MainActor () -> Bool = { TargetBridge.trusted },
         permissionInterval: UInt64 = 1_000_000_000,
         applePreparationTimeout: Duration = .seconds(120),
         remoteKeyRead: ((RemoteTranslationProvider) throws -> String)? = nil,
         cliDelivery: CLITargetBridge? = nil,
         credentialPresence: @escaping (RemoteTranslationProvider, String) -> CredentialPresence = { Credentials.presence(provider:$0,baseURL:$1) }) {
        Credentials.bindLegacyConfiguration(settings: CompanionPreferences.store)
        self.applePreparationTimeout = applePreparationTimeout
        self.remoteKeyRead = remoteKeyRead
        self.cliDelivery = cliDelivery ?? CLITargetBridge()
        self.credentialPresence = credentialPresence
        permission = permissionCheck()
        permissionMonitor = AccessibilityPermissionMonitor(check: permissionCheck, interval: permissionInterval)
        permissionMonitor.onChange = { [weak self] granted in
            guard let self, self.permission != granted else { return }
            self.permission = granted
            if granted && !self.busy && !self.hasTarget {
                self.report("辅助功能已开启。请点击 Claude 输入框，再按 ⌃⌥E 连接。")
            }
        }
        permissionMonitor.start()
        replies.onManualReply = { [weak self] id in
            guard let self else { return }
            retiredReplies.remove(id)
            readingHistory = true; hasNewContent = false
            chatScrollTarget = id; chatScrollAtTop = true; chatRevision += 1
        }
        replies.onReplyAcquired = { [weak self] id, foreign, language in self?.recordReplyOriginal(id: id, foreign: foreign, language: language) }
        replies.onReply = { [weak self] id, foreign, chinese, language in self?.recordReply(id: id, foreign: foreign, chinese: chinese, language: language) }
        replies.onReplyState = { [weak self] id, complete in self?.markReply(id: id, complete: complete) }
        bridge.onStop = { [weak self] in
            guard let self else { return }
            cliNotices.stop(); replies.stop(); retireConnectionRequest()
            cliReadAssociation = nil
            hasTarget = outgoingTarget != nil
        }
        bridge.onTick = { [weak self] in self?.replies.tick() }
        bridge.onSelection = { [weak self] in
            guard let self else { return }
            cliNotices.stop(); connectionRequestID = nil; connectionTask?.cancel(); connectionTask = nil
            replies.stop(); cliReadAssociation = nil
            hasTarget = outgoingTarget != nil
            if !bridge.selected.isEmpty {
                showCLIPicker = false; replies.watching = true
                replies.sourceName = bridge.selectedName
                replies.status = "正在读取所选 CLI 会话，输入连接独立保持。"
                if outgoingTarget == nil { targetName = replies.sourceName }
                bindSelectedCLI()
            }
        }
        bridge.onCLIReport = { [weak self] in
            guard let self else { return }
            // Reports may change or arrive late. They affect reading only.
            if let previous = cliReadAssociation,
               let next = bridge.cliChoices.first(where: { $0.id == previous.session })?.delivery,
               next != previous.origin {
                cliReadAssociation = nil; bridge.clearSelection(); replies.stop()
            }
            matchCapturedCLI()
        }
        bridge.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            hasTarget = outgoingTarget != nil
            replies.watching = true; replies.sourceName = bridge.selectedName
            replies.configure(engine: engine, baseURL: baseURL, model: activeAIModel, language: language)
            replies.ingest(snapshot)
        }
    }

    func refreshPermission() { permissionMonitor.refresh() }
    func requestPermission() {
        TargetBridge.requestPermission()
        refreshPermission()
    }
    func stopPermissionMonitoring() { permissionMonitor.stop() }

    func prepareTarget() {
        guard !busy else { return }
        refreshPermission()
        if CompanionPreferences.simulated { report("本机模拟不连接真实 Claude。"); return }
        do {
            connectCapturedTarget(try TargetBridge.capture())
        } catch {
            handleCaptureFailure(error, bundle: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        }
    }
    func handleCaptureFailure(_ error: Error, bundle: String?) {
        guard bundle == "com.anthropic.claudefordesktop" || busy else {
            connectCapturedCLI()
            return
        }
        retireConnectionRequest(); target = nil; outgoingTarget = nil; cliReadAssociation = nil; pendingCLISurface = nil; hasTarget = false; targetName = "未选择输入框"
        cliConnectionHint = ""; cliCaptureFailed = false
        if bridge.enabled { bridge.clearSelection() } else { replies.stop() }
        showCLIPicker = false
        report(error.localizedDescription, error: true)
    }
    func connectCapturedTarget(_ captured: TargetBridge.Target) {
        retireConnectionRequest()
        outgoingTarget = nil; hasTarget = false
        guard TargetBridge.nativeReplySupported(bundle: captured.app.bundleIdentifier, conversation: captured.conversation) else {
            onNonClaudeConnection(captured.name); connectCapturedCLI(); return
        }
        do { outgoingTarget = try inputDelivery.bind(TargetBridge.location(captured)) }
        catch { report(error.localizedDescription, error: true); return }
        target = captured; cliReadAssociation = nil; pendingCLISurface = nil
        cliConnectionHint = ""; cliCaptureFailed = false
        targetName = captured.name; hasTarget = true
        bridge.stop(); startReplyReading()
        report("已连接你选定的输入区；译文将按发送设置填入。")
    }
    private func retireConnectionRequest() {
        connectionRequestID = nil; connectionTask?.cancel(); connectionTask = nil
        cliBindingTask?.cancel(); cliBindingTask = nil
    }
    private func connectCapturedCLI() {
        let capture = Result { try cliCapture() }
        outgoingTarget = nil; hasTarget = false
        connectCLI()
        switch capture {
        case .success(let surface):
            do { outgoingTarget = try inputDelivery.bind(surface.location) }
            catch { report(error.localizedDescription, error: true); return }
            pendingCLISurface = surface; hasTarget = true; targetName = surface.name
            cliConnectionHint = ""; cliCaptureFailed = false
            report("已连接你选定的 CLI 输入区；回复与额度正在独立获取，发送可立即使用。")
            startCLINotices(surface)
            awaitCLIFooter()
        case .failure(let error):
            cliCaptureFailed = true; cliConnectionHint = "CLI 输入未连接：" + error.localizedDescription
            report(cliConnectionHint, error: true)
        }
    }
    private func matchCapturedCLI() {
        guard let surface = pendingCLISurface, outgoingTarget != nil else { return }
        let matches = bridge.cliChoices.filter { choice in
            guard let origin = choice.delivery else { return false }
            return cliDelivery.readMatches(surface: surface, session: choice.id, origin: origin)
        }
        if matches.count == 1 {
            if bridge.selected != matches[0].id { bridge.select(matches[0].id) }
            else { bindSelectedCLI() }
        }
    }
    private func awaitCLIFooter() {
        guard pendingCLISurface != nil, let lease = outgoingTarget else { return }
        matchCapturedCLI()
        cliBindingTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard let self, self.bridge.enabled, self.outgoingTarget?.id == lease.id, self.pendingCLISurface != nil else { return }
                self.matchCapturedCLI()
            }
        }
    }
    private func startCLINotices(_ surface: CLITargetBridge.Surface) {
        guard let lease = outgoingTarget else { return }
        cliNotices.start(read: { [weak self] in self?.cliDelivery.passiveScreen(surface) ?? (nil, false) }, current: { [weak self] in
            self?.outgoingTarget?.id == lease.id && self?.bridge.enabled == true
        })
    }
    func connectCLI(releaseSelection: Bool = true, showPicker: Bool = false) {
        guard !busy else { return }
        retireConnectionRequest(); target = nil
        if releaseSelection { cliReadAssociation = nil; pendingCLISurface = nil; cliConnectionHint = ""; cliCaptureFailed = false }
        hasTarget = outgoingTarget != nil
        if !bridge.enabled { bridge.start() }
        guard bridge.enabled else { report(bridge.status, error: true); return }
        if releaseSelection { bridge.clearSelection(); replies.status = "" }
        showCLIPicker = showPicker
        if cliReadAssociation == nil && pendingCLISurface == nil { cliConnectionHint = "请在正在使用的 CLI 输入区按 ⌃⌥E，直接连接当前窗口，无需选择会话。" }
        report("正在获取 Claude Code CLI 会话，请保持已登录的终端打开…")
        let id = UUID(), path = bridge.connectionPath
        connectionRequestID = id
        connectionTask = Task {
            do {
                try Task.checkCancellation()
                try await cliEntryRequest(path)
                guard connectionRequestID == id, bridge.enabled, !Task.isCancelled else { return }
                report(showPicker ? "CLI 入口已准备；选择来源只开启补充读取，不绑定输入窗口。" : (cliConnectionHint.isEmpty ? "CLI 入口已准备，请在当前终端输入区按 ⌃⌥E 直接连接。" : cliConnectionHint), error: cliCaptureFailed)
            } catch {
                guard connectionRequestID == id, !Task.isCancelled else { return }
                report("CLI 回复／额度获取暂不可用：" + error.localizedDescription + (hasTarget ? "；输入连接保持，可继续发送。" : ""), error: !hasTarget)
            }
            if connectionRequestID == id { connectionRequestID = nil; connectionTask = nil }
            refreshHealth()
        }
    }
    private func bindSelectedCLI() {
        guard let surface = pendingCLISurface, let choice = bridge.cliChoices.first(where: { $0.id == bridge.selected }),
              let origin = choice.delivery,
              cliDelivery.readMatches(surface: surface, session: choice.id, origin: origin) else { return }
        do {
            if cliReadAssociation?.session == choice.id && cliReadAssociation?.origin == origin { return }
            cliReadAssociation = try cliDelivery.bind(surface: surface, session: choice.id, origin: origin)
            if outgoingTarget == nil { targetName = choice.name }
            startCLINotices(surface)
            replies.status = "正在读取当前 CLI 会话的正式回复…"
        } catch { replies.status = "CLI 读取关联暂不可用；输入连接保持。" }
    }
    func report(_ message: String, error: Bool = false) { status = message; isError = error }
    func saveSettings(key: String, replaceKey: Bool) throws {
        if engine == "ai" {
            _ = try AIProtocol.request(text: "测试", baseURL: baseURL, model: aiModel, key: "")
        } else if engine == "gemini" {
            _ = try GeminiProtocol.endpoint(model: geminiModel)
        } else if engine != "apple" {
            throw BridgeError.message("翻译方式无效，请重新选择。")
        }
        if replaceKey, let provider = RemoteTranslationProvider(rawValue: engine) {
            try Credentials.save(key.trimmingCharacters(in: .whitespacesAndNewlines), for: provider, baseURL: baseURL)
        }
        replies.resetTranslation()
        if engine == "ai" { try TranslationProfileMetadata.save(baseURL: baseURL, model: aiModel) }
        CompanionPreferences.store.set(engine, forKey: "engine")
        CompanionPreferences.store.set(baseURL, forKey: "baseURL")
        CompanionPreferences.store.set(aiModel, forKey: "aiModel")
        CompanionPreferences.store.set(geminiModel, forKey: "geminiModel")
        replies.configure(engine: engine, baseURL: baseURL, model: activeAIModel, language: language)
        health.invalidate(); refreshHealth()
        report("翻译设置已保存，下一次发送或读取将使用新设置。")
    }
    func begin(insert: Bool) {
        guard !busy else { return }
        do {
            let text = try InputPolicy.validated(input)
            if insert && outgoingTarget == nil { throw BridgeError.message("请先点击目标聊天输入框，再按 ⌃⌥E；也可以先点「仅翻译」。") }
            if insert, let destination = outgoingTarget { try inputDelivery.validate(destination.location) }
            let job = Job(id: UUID(), text: text, insert: insert, destination: outgoingTarget, send: autoSend, commandReturn: commandReturn, language: language)
            let provider = RemoteTranslationProvider(rawValue: engine)
            guard engine == "apple" || provider != nil else { throw BridgeError.message("翻译方式无效，请重新选择。") }
            // Injected reads are local test callbacks. Real Keychain reads
            // begin only inside the cancellable background operation below.
            let verifiedKey = try provider.flatMap { try remoteKeyRead?($0) }
            let base = baseURL; let model = activeAIModel
            if let provider, let key = verifiedKey { _ = try provider.request(text: "测试", baseURL: base, model: model, key: key, direction: .fromChinese(job.language)) }
            activeID = job.id; pending = job; busy = true; output = ""
            let row = ChatItem(id: job.id.uuidString, isUser: true, chinese: text, foreign: "", language: job.language)
            if let previous = history.last, previous.isUser, previous.foreign.isEmpty,
               previous.chinese == text, previous.language == job.language {
                // Retain a fresh job identity so the failed attempt cannot publish later.
                history[history.count - 1] = row
            } else { history.append(row) }
            trimHistory()
            chatScrollTarget = "bottom"; chatScrollAtTop = false
            chatRevision += 1
            report(engine == "apple" ? "正在使用系统翻译… 首次使用可能需要下载语言包。" : "正在翻译…")
            if let provider {
                task = Task {
                    do {
                        let key: String
                        if let verifiedKey { key = verifiedKey }
                        else { key = try await TextTranslation.withDeadline(timeout: .seconds(10)) { try await Credentials.readAsync(for: provider, baseURL: base) } }
                        try Task.checkCancellation()
                        guard activeID == job.id else { throw CancellationError() }
                        _ = try provider.request(text: "测试", baseURL: base, model: model, key: key, direction: .fromChinese(job.language))
                        let result = try await TextTranslation.runProtected(text) { chunk in
                            if let testTranslation = self.testTranslation { return try await testTranslation(chunk) }
                            let request = try provider.request(text: chunk, baseURL: base, model: model, key: key, direction: .fromChinese(job.language))
                            return try await AITranslator.translate(request, provider: provider)
                        }
                        // Translation failures may use the system fallback;
                        // delivery failures must retain this result and their own cause.
                        do { try await finish(result, job: job) }
                        catch { failed(error, id: job.id) }
                    } catch let error where !(error is CancellationError) && !Task.isCancelled && activeID == job.id {
                        startSystemFallback(job, reason: error, provider: provider)
                    } catch { failed(error, id: job.id) }
                }
            } else {
                preparationWatchdog = Task { [weak self] in
                    do {
                        try await Task.sleep(for: self?.applePreparationTimeout ?? .seconds(120))
                        self?.failed(TranslationChunkError.timedOut, id: job.id)
                    } catch { /* The system callback or cancellation ended this wait. */ }
                }
                prepareSystemTask(job)
            }
        } catch { report(error.localizedDescription, error: true) }
    }
    private func prepareSystemTask(_ job: Job) {
        // Equal language configurations can be coalesced by SwiftUI when a
        // cancelled task is immediately replaced. Key the view by this job,
        // and reject callbacks from every earlier job explicitly.
        systemTaskID = job.id
        configuration = .init(source: .init(identifier: "zh-Hans"), target: .init(identifier: job.language.rawValue))
    }
    func runApple(_ session: TranslationSession, attempt: UUID) async {
        guard let job = pending, activeID == job.id, busy, systemTaskID == attempt, job.id == attempt else { return }
        preparationWatchdog?.cancel(); preparationWatchdog = nil
        appleSession = session
        do {
            _ = try await TextTranslation.withDeadline { try await session.prepareTranslation(); return "" }
            try Task.checkCancellation()
            let result = try await TextTranslation.runProtected(job.text) { chunk in
                try await SystemTranslationProtection.translate(TranslationContext.systemInput(chunk), toChinese: false) {
                    try await session.translate($0).targetText
                }
            }
            try await finish(result, job: job)
        } catch { failed(error, id: job.id) }
    }
    private func finish(_ translated: String, job: Job) async throws {
        guard activeID == job.id, !Task.isCancelled else { return }
        guard !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BridgeError.message("翻译结果为空，请重试。") }
        try ForeignTextPolicy.validate(translated, incoming: false)
        output = translated; outputLanguage = job.language
        outputSource = job.text
        if let index = history.firstIndex(where: { $0.id == job.id.uuidString }) { history[index].foreign = translated }
        chatRevision += 1
        if job.insert && input != job.text && !(job.allowEmptyDraft && input.isEmpty) {
            report("中文草稿在翻译期间已改变，旧译文已保留，未自动填入或发送。请重新翻译当前草稿。")
        } else if job.insert, let destination = job.destination {
            report("翻译完成，正在填入你选定的输入区…")
            let outcome = try await inputDelivery.deliver(translated, to: destination, autoSend: job.send, commandReturn: job.commandReturn) { [weak self] in
                self?.activeID == job.id && self?.outgoingTarget?.id == destination.id
            }
            guard activeID == job.id else { return }
            switch outcome {
            case .inserted:
                report("已向你选定的输入区发送粘贴按键，按你的设置未自动回车。")
                if input == job.text { input = "" }
            case .sendKeyPressed:
                report("已向你选定的输入区发送粘贴和回车按键，请以 Claude 的显示为准。")
                if input == job.text { input = "" }
                revealWindow()
            case .submitFailed(let reason): report(reason, error: true); revealWindow()
            }
        } else { report("翻译完成，可复制译文。") }
        if let reason = job.fallbackReason {
            report("已改用系统翻译（" + reason + "）。" + status, error: isError)
        }
        busy = false; pending = nil; activeID = nil; appleSession = nil
        systemTaskID = nil; configuration = nil
    }
    private func startSystemFallback(_ job: Job, reason: Error, provider: RemoteTranslationProvider) {
        let service = provider == .gemini ? "Gemini" : "AI 翻译服务"
        var fallback = job
        fallback.fallbackReason = service + "：" + reason.localizedDescription
        pending = fallback
        report(service + " 未能提供可用译文，正在改用系统翻译；完成后继续原操作。")
        if let testFallback {
            task = Task {
                do {
                    let result = try await TextTranslation.runProtected(job.text, translate: testFallback)
                    try await finish(result, job: fallback)
                } catch { failed(error, id: job.id) }
            }
            return
        }
        preparationWatchdog = Task { [weak self] in
            do {
                try await Task.sleep(for: self?.applePreparationTimeout ?? .seconds(120))
                self?.failed(TranslationChunkError.timedOut, id: job.id)
            } catch { /* The system callback or cancellation ended this wait. */ }
        }
        prepareSystemTask(fallback)
    }
    func insertResult() {
        guard !busy, !output.isEmpty else { return }
        guard let destination = outgoingTarget else { report("请先回到目标输入区按 ⌃⌥E 连接。", error: true); return }
        do { try inputDelivery.validate(destination.location) }
        catch { report(error.localizedDescription, error: true); return }
        guard input.isEmpty || input == outputSource else { report("中文草稿已改变，请重新翻译后再填入。", error: true); return }
        let job = Job(id: UUID(), text: outputSource, insert: true, destination: destination, send: autoSend, commandReturn: commandReturn, language: outputLanguage, allowEmptyDraft: true)
        let result = output
        activeID = job.id; busy = true
        task = Task {
            do { try await finish(result, job: job) }
            catch { failed(error, id: job.id) }
        }
    }
    private func failed(_ error: Error, id: UUID) {
        guard activeID == id else { return }
        preparationWatchdog?.cancel(); preparationWatchdog = nil
        if #available(macOS 26.0, *) { appleSession?.cancel() }
        busy = false; pending = nil; activeID = nil; appleSession = nil
        configuration = nil
        systemTaskID = nil
        if error is CancellationError { report("已取消，中文内容已保留。") }
        else {
            report(error.localizedDescription + (output.isEmpty ? "" : " 译文已保留，可复制使用。"), error: true)
            if !NSApp.isActive { revealWindow() }
        }
    }
    func cancel() {
        preparationWatchdog?.cancel(); preparationWatchdog = nil
        activeID = nil; pending = nil; task?.cancel(); task = nil
        if #available(macOS 26.0, *) { appleSession?.cancel() }
        appleSession = nil; configuration = nil; systemTaskID = nil; busy = false
        report("已取消。若已开始粘贴，请检查原输入框。")
    }
    func startReplyReading() {
        if isCLIConnection {
            if !bridge.enabled { bridge.start() }
            if let surface = pendingCLISurface { startCLINotices(surface); awaitCLIFooter() }
            if !bridge.selected.isEmpty { bridge.select(bridge.selected) }
            else { report("输入已连接；等待读取当前 CLI 的回复与额度，不影响发送。") }
            return
        }
        guard !busy, let target else { report("请先点击 Claude 输入框，再按 ⌃⌥E。", error: true); return }
        Task { await replies.connect(target: target, engine: engine, baseURL: baseURL, model: activeAIModel, language: language) }
        announceEntrance(target)
    }
    /// Usage follows the entrance actually connected, on first connection and
    /// whenever reading resumes (stopping reading hides usage).
    private func announceEntrance(_ target: TargetBridge.Target) {
        if target.app.bundleIdentifier == "com.anthropic.claudefordesktop" {
            onClaudeConnection(.desktop, nil)
        } else if let url = target.conversation {
            onClaudeConnection(.web, url)
        } else {
            // Translation still works, but this composer is not a verified
            // Claude entrance, so no account's quota may be shown for it.
            onNonClaudeConnection(target.name)
        }
    }
    @discardableResult func copyOutput(to board: NSPasteboard = .general) -> Bool {
        guard !busy, !output.isEmpty else { return false }
        return copyTranslationText(output, to: board)
    }
    @discardableResult func copyTranslation(id: String, to board: NSPasteboard = .general) -> Bool {
        guard let item = history.first(where: { $0.id == id && $0.isUser }), !item.foreign.isEmpty else { return false }
        return copyTranslationText(item.foreign, to: board)
    }
    private func copyTranslationText(_ text: String, to board: NSPasteboard) -> Bool {
        board.clearContents()
        guard board.setString(text, forType: .string) else { report("复制失败，译文已保留。", error: true); return false }
        report(isCLIConnection ? "译文已复制；回到 Claude Code 按 ⌘V 粘贴，再确认发送。" : "译文已复制。")
        return true
    }
}
