import Foundation
import SwiftUI

enum ClaudePlan: String, Sendable {
    case pro = "Pro", max = "Max", team = "Team", enterprise = "Enterprise", free = "Free", unknown = "套餐未识别"
    static let allReportedPlans: [Self] = [.pro,.max,.team,.enterprise,.free]
    static func decode(_ data: Data) throws -> Self {
        struct Organization: Decodable { let capabilities: [String] }
        guard let value = try? JSONDecoder().decode(Organization.self, from: data) else { throw ClaudeUsageError.malformed }
        let caps = Set(value.capabilities)
        if caps.contains("raven_enterprise") || caps.contains("claude_enterprise") { return .enterprise }
        if caps.contains("raven") || caps.contains("claude_team") { return .team }
        if caps.contains("claude_max") { return .max }
        if caps.contains("claude_pro") { return .pro }
        if caps.contains("chat") { return .free }
        return .unknown
    }
}

final class ClaudeUsageClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private var session: URLSession!
    init(protocolClasses: [AnyClass]? = nil) {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCache = nil; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 20
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func data(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw ClaudeUsageError.network }
            switch response.statusCode {
            case 200: guard data.count <= 1_000_000 else { throw ClaudeUsageError.malformed }; return data
            case 401: throw ClaudeUsageError.expired
            case 429: throw ServiceCooldown(seconds: ServiceCooldown.duration(response.value(forHTTPHeaderField: "Retry-After")))
            default: throw ClaudeUsageError.unavailable
            }
        } catch let error as ClaudeUsageError { throw error }
        catch let error as ServiceCooldown { throw error }
        catch is CancellationError { throw CancellationError() }
        catch { throw ClaudeUsageError.network }
    }
    func fetch(_ connection: ClaudeSession) async throws -> (ClaudeUsageSnapshot, ClaudePlan) {
        let request = try ClaudeUsageRequest.make(sessionKey: connection.key, organization: connection.organization)
        var profile = request
        profile.url = URL(string: "https://claude.ai/api/organizations/\(connection.organization)")!
        let profileRequest = profile
        async let usage = data(request)
        async let organization = data(profileRequest)
        let values = try await (usage, organization)
        return (try .decode(values.0), try ClaudePlan.decode(values.1))
    }
    func cancel() { session.invalidateAndCancel() }
}

enum ClaudeUsageChannel: String, CaseIterable, Identifiable {
    case desktop, web, cli
    var id: String { rawValue }
    var name: String { switch self { case .desktop: return "桌面端"; case .web: return "网页端"; case .cli: return "Claude Code CLI" } }
}

@MainActor final class ClaudeUsageMonitor: ObservableObject {
    enum Source: String, CaseIterable { case desktop, session, visibleAX, visiblePage, statusLine
        var name: String { switch self { case .desktop: return "Claude 桌面登录"; case .session: return "手动 session（独立账户）"; case .visibleAX: return "桌面可见 Usage"; case .visiblePage: return "网页可见 Usage"; case .statusLine: return "CLI statusLine" } }
    }
    @Published private(set) var accountDisplayName = "账户待核对"
    @Published private(set) var candidates: [UsageEvidence] = []
    private struct AccountState {
        var epoch: String
        var sequence: Int
        var fingerprint: String?
        var retiredIdentities: Set<String> = []
    }
    private var accountStates: [String: AccountState] = [:]
    private var retiredAccountEpochs: [String: Set<String>] = [:]
    @Published private(set) var snapshot: ClaudeUsageSnapshot?
    @Published private(set) var plan: ClaudePlan = .unknown
    @Published private(set) var refreshing = false
    @Published private(set) var stale = false
    @Published private(set) var status = "连接额度后自动更新"
    @Published var showConnection = false
    @Published private(set) var source: Source
    @Published private(set) var organization = ""
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var fingerprint: String?
    @Published private(set) var pendingEvidence: UsageEvidence?
    @Published private(set) var accountLabel = ""
    private var evidenceBinding = ""
    private var evidenceSignature = ""
    private var receivedAt: Date?
    private var lastSuccess = Date.distantPast
    private var failures = 0
    private var requested = false
    private var retryAfter = Date.distantPast
    private var lastFailure: String?
    private let load: @Sendable (Source, Bool) throws -> ClaudeSession
    private let fetch: @Sendable (ClaudeSession) async throws -> (ClaudeUsageSnapshot, ClaudePlan)
    private struct VisibleConnection: Codable {
        let source: String; let account: String; let binding: String; var identity: UsageAccountIdentity? = nil
        var valid: Bool {
            [Source.visibleAX.rawValue, Source.visiblePage.rawValue, Source.statusLine.rawValue].contains(source)
                && !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && account.count <= 80
                && (identity == nil || identity?.valid == true)
                && binding.range(of: #"^[A-Za-z0-9_-]{1,200}$"#, options: .regularExpression) != nil
        }
    }
    private let settings: UserDefaults
    private var visibleConnection: VisibleConnection?
    private let enabled: () -> Bool
    private var automaticRetry: Task<Void, Never>?
    private var invalidVisibleConnection = false
    private var following = false
    @Published private(set) var awaitingEntrance = false
    private var replyRefresh: Task<Void, Never>?
    private var periodic: Task<Void, Never>?
    var replyRefreshDelay: Duration = .seconds(3)
    private var followingURL: String?
    private var acquisitionTask: Task<Void, Never>?
    private var acquisitionChannel: ClaudeUsageChannel?
    private var acquisitionBinding: String?
    private var acquisitionURL: String?
    private var acquisitionBaseline: [String: Int] = [:]
    var requestReport: (ClaudeUsageChannel, String?, String?) async throws -> Void = { _, _, _ in throw ClaudeUsageError.unavailable }
    var removeSession: @Sendable () -> Bool = { ClaudeSessionStore.remove() }
    @Published private(set) var acquisitionStatus = ""
    @Published private(set) var acquiring = false

    func follow(channel: ClaudeUsageChannel, binding: String = "", pageURL: String? = nil) {
        acquisitionTask?.cancel(); acquiring = false
        following = true; followingURL = pageURL
        if channel == .desktop { configure(.desktop); refresh(); return }
        configure(channel == .web ? .visiblePage : .statusLine)
        evidenceBinding = binding; evidenceSignature = ""
        visibleConnection = .init(source: source.rawValue, account: "自动跟随聊天来源", binding: binding.isEmpty ? "awaiting-source" : binding)
        status = "聊天已连接，正在自动核对对应账户和额度"
    }
    /// No verified Claude chat entrance is connected (startup, or a composer in
    /// another application). Show no quota rather than guess another channel's
    /// account; saved source settings stay for the next real connection.
    func awaitChatEntrance(_ message: String = "连接 Claude 聊天后，显示该入口当前登录账户的额度") {
        stop(); replyRefresh?.cancel(); replyRefresh = nil
        following = false; followingURL = nil; awaitingEntrance = true
        evidenceBinding = ""; evidenceSignature = ""; accountLabel = ""
        snapshot = nil; plan = .unknown; stale = false; fingerprint = nil; organization = ""
        accountDisplayName = "账户待核对"; status = message
    }
    /// Refresh once after every completed Claude reply, bypassing the 60 s
    /// reuse window; the short delay lets the service record the reply first.
    /// CLI needs nothing here: Claude Code re-reports after each reply.
    func refreshAfterReply() {
        guard !awaitingEntrance, source == .desktop || source == .session || source == .visiblePage else { return }
        replyRefresh?.cancel()
        let delay = replyRefreshDelay
        let token = generation
        replyRefresh = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !self.awaitingEntrance, self.generation == token else { return }
            self.replyRefresh = nil
            self.refresh(force: true)
        }
    }
    /// Periodic refresh while a Desktop/session entrance is connected. Web is
    /// Web uses foreground-only native reads after replies; CLI reports through
    /// its own status-line cycle. Neither silently activates another app.
    func startPeriodicRefresh(every interval: Duration = .seconds(60)) {
        periodic?.cancel()
        periodic = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                guard let self else { return }
                if !self.awaitingEntrance, self.source == .desktop || self.source == .session { self.refresh(force: true) }
            }
        }
    }
    func stopFollowing() {
        guard following else { return }
        following = false; followingURL = nil
        disconnect(); acquisitionTask?.cancel(); acquisitionTask = nil; acquiring = false
    }
    func acquire(_ channel: ClaudeUsageChannel, binding: String? = nil, pageURL: String? = nil) {
        guard !acquiring else { return }
        if channel == .desktop { connectDesktop(); return }
        acquisitionChannel = channel; acquisitionBinding = binding; acquisitionURL = pageURL
        acquisitionBaseline = accountStates.mapValues { $0.sequence }; acquiring = true
        acquisitionStatus = channel == .cli ? "正在请求 CLI 当前报告（服务器更新时间未知）…" : "正在请求网页当前账户额度…"
        let requestReport = self.requestReport, token = generation
        acquisitionTask = Task { [weak self] in
            do {
                try await requestReport(channel, binding, pageURL)
                try await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled, let self, self.generation == token else { return }
                acquisitionStatus = channel == .cli ? "未收到新额度报告。请启动新 Claude Code 会话；首次正式回复前可能没有额度字段。" : "未读到网页额度，请在伴侣主动读取；需有可核对账户的 Claude 官方网页。"
                if channel == .web, self.channel == .web { status = acquisitionStatus }
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                acquisitionStatus = error.localizedDescription
                if channel == .web, self.channel == .web { status = acquisitionStatus }
            }
            self?.acquiring = false
        }
    }
    private func receivedReport(_ channel: ClaudeUsageChannel, observation: UsageAccountObservation, pageURL: String? = nil, quota: Bool) {
        guard acquiring, channel == acquisitionChannel,
              acquisitionBinding == nil || acquisitionBinding == observation.binding,
              acquisitionURL == nil || acquisitionURL == pageURL,
              observation.sequence > acquisitionBaseline[key(observation.source, observation.binding), default: -1] else { return }
        acquisitionTask?.cancel(); acquisitionTask = nil; acquiring = false
        acquisitionStatus = quota ? (channel == .cli ? "已收到 CLI 当前报告；服务器更新时间未知" : "已收到网页当前账户额度") : "来源已响应，但尚未提供可核对账户的额度。"
    }

    init(settings: UserDefaults = CompanionPreferences.store, load: @escaping @Sendable (Source, Bool) throws -> ClaudeSession = { source, prompt in
        try source == .desktop ? ClaudeDesktopSession.read(allowPrompt: prompt) : ClaudeSessionStore.read(allowPrompt: prompt)
    }, fetch: @escaping @Sendable (ClaudeSession) async throws -> (ClaudeUsageSnapshot, ClaudePlan) = { connection in
        let client = ClaudeUsageClient(); defer { client.cancel() }; return try await client.fetch(connection)
    }, enabled: @escaping () -> Bool = { CompanionPreferences.store.bool(forKey: "usageConnected") }) {
        self.settings = settings
        let saved = settings.data(forKey: "visibleUsageConnection")
        let decoded = saved.flatMap { try? JSONDecoder().decode(VisibleConnection.self, from: $0) }
        let restored = decoded.flatMap { $0.valid ? $0 : nil }
        invalidVisibleConnection = saved != nil && restored == nil
        if invalidVisibleConnection { settings.set(false, forKey: "usageConnected") }
        visibleConnection = restored
        source = Source(rawValue: restored?.source ?? settings.string(forKey: "usageSource") ?? "desktop") ?? .desktop
        self.load = load; self.fetch = fetch; self.enabled = enabled
        accountLabel = restored?.account ?? ""
        evidenceBinding = restored?.binding ?? ""
        if invalidVisibleConnection { status = "额度来源配置无效，请明确重新连接；未读取旧登录来源。" }
    }
    func connectDesktop() { configure(.desktop); refresh(allowPrompt: true) }
    func connectSession(key: String, organization: String) throws {
        try ClaudeSessionStore.save(key: key.trimmingCharacters(in: .whitespacesAndNewlines), organization: organization.trimmingCharacters(in: .whitespacesAndNewlines))
        configure(.session); refresh()
    }
    func connectSessionAsync(key: String, organization: String) async throws {
        stop(); let token = generation
        _ = try ClaudeUsageRequest.make(sessionKey: key, organization: organization)
        _ = try await Credentials.offMainRead(busyRetryLimit: 0) { try ClaudeSessionStore.save(key: key, organization: organization); return "" }
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        configure(.session); refresh()
    }
    func disconnectAsync() async {
        guard source == .session else { disconnect(); return }
        stop(); let token = generation; settings.set(false, forKey: "usageConnected")
        let erase = removeSession
        let removed = try? await Credentials.offMainRead(busyRetryLimit: 0) { erase() ? "removed" : "retained" }
        guard generation == token else { return }
        disconnect()
        if removed != "removed" { status = "已断开额度连接；钥匙串暂不可访问，已保存 session 保留。" }
    }
    private func configure(_ source: Source) {
        stop(); awaitingEntrance = false; self.source = source; accountDisplayName = "账户待核对"; fingerprint = nil; snapshot = nil; plan = .unknown; organization = ""; stale = false
        invalidVisibleConnection = false
        retryAfter = .distantPast
        if source == .desktop || source == .session {
            visibleConnection = nil; settings.removeObject(forKey: "visibleUsageConnection")
            settings.set(source.rawValue, forKey: "usageSource"); settings.set(true, forKey: "usageConnected")
        }
    }
    var channel: ClaudeUsageChannel {
        switch source { case .desktop, .visibleAX: return .desktop; case .session, .visiblePage: return .web; case .statusLine: return .cli }
    }
    func candidates(for channel: ClaudeUsageChannel) -> [UsageEvidence] {
        candidates.filter { channelFor($0.source) == channel && !$0.snapshot.isStale(at: Date()) }
    }
    private func channelFor(_ source: UsageEvidenceSource) -> ClaudeUsageChannel {
        switch source { case .usageAX: return .desktop; case .usagePage: return .web; case .statusLine: return .cli }
    }
    private func key(_ source: UsageEvidenceSource, _ binding: String) -> String { source.rawValue + ":" + binding }
    private func sourceFor(_ value: UsageEvidenceSource) -> Source {
        switch value { case .usageAX: return .visibleAX; case .usagePage: return .visiblePage; case .statusLine: return .statusLine }
    }
    @discardableResult private func acceptAccount(_ observation: UsageAccountObservation) -> Bool {
        let key = key(observation.source, observation.binding)
        guard !observation.epoch.isEmpty, observation.epoch.count <= 128,
              (0...1_000_000_000).contains(observation.sequence), observation.identity == nil || observation.identity?.valid == true else {
            if !awaitingEntrance, observation.binding == evidenceBinding && source == sourceFor(observation.source) { clearVisibleAccount("当前账户身份尚未核对") }
            return false
        }
        guard retiredAccountEpochs[key]?.contains(observation.epoch) != true else { return false }
        var state = accountStates[key]
        if state?.epoch != observation.epoch {
            guard accountStates.count < 16 || state != nil, (retiredAccountEpochs[key]?.count ?? 0) < 64 else { return false }
            if let old = state { retiredAccountEpochs[key, default: []].insert(old.epoch) }
            state = .init(epoch: observation.epoch, sequence: -1, fingerprint: nil)
        }
        guard var current = state, observation.sequence > current.sequence else { return false }
        let incoming = observation.identity?.fingerprint
        if let incoming, current.retiredIdentities.contains(incoming) { return false }
        if let old = current.fingerprint, let incoming, old != incoming { current.retiredIdentities.insert(old) }
        let changed = current.fingerprint != incoming
        current.fingerprint = incoming; current.sequence = observation.sequence; accountStates[key] = current
        if changed || incoming == nil {
            candidates.removeAll { self.key($0.source, $0.binding) == key }
            if pendingEvidence.map({ self.key($0.source, $0.binding) == key }) == true { pendingEvidence = nil }
            if !awaitingEntrance, observation.binding == evidenceBinding && source == sourceFor(observation.source) {
                clearVisibleAccount(incoming == nil ? "正在核对当前账户，已隐藏旧额度" : "账户已变化，正在读取当前账户额度")
            }
        }
        if !awaitingEntrance, observation.binding == evidenceBinding && source == sourceFor(observation.source), let identity = observation.identity {
            accountDisplayName = identity.displayName
            if var connection = visibleConnection {
                connection.identity = identity; visibleConnection = connection
                if let saved = try? JSONEncoder().encode(connection) { settings.set(saved, forKey: "visibleUsageConnection") }
            }
        }
        return true
    }
    private func clearVisibleAccount(_ text: String) {
        snapshot = nil; plan = .unknown; stale = false; evidenceSignature = ""; accountDisplayName = "账户待核对"; status = text
    }
    /// Hide a previous snapshot without acknowledging (and cancelling) the
    /// request whose identity sandwich is still running.
    func beginVisibleRead(binding: String) {
        guard !awaitingEntrance, source == .visiblePage, evidenceBinding == binding else { return }
        clearVisibleAccount("正在重新核对当前网页账户和额度")
    }
    func receiveAccount(_ observation: UsageAccountObservation) {
        guard acceptAccount(observation) else { return }
        receivedReport(channelFor(observation.source), observation: observation, quota: false)
        candidates.removeAll { $0.source == observation.source && $0.binding == observation.binding }
        if pendingEvidence?.source == observation.source && pendingEvidence?.binding == observation.binding { pendingEvidence = nil }
        guard !awaitingEntrance, observation.binding == evidenceBinding, source == sourceFor(observation.source) else { return }
        // An identity-only startup/refresh is not a quota report. Never retain a
        // previous window after the current provider has explicitly omitted it.
        snapshot = nil; stale = false; evidenceSignature = ""
        status = observation.identity == nil ? "正在核对当前账户，已隐藏旧额度" : "当前账户已核对，等待新的额度报告"
    }
    func receive(_ evidence: UsageEvidence) {
        guard acceptAccount(evidence.accountObservation), evidence.identity?.valid == true else { return }
        receivedReport(channelFor(evidence.source), observation: evidence.accountObservation, pageURL: evidence.pageURL, quota: true)
        if following, evidenceBinding.isEmpty, source == sourceFor(evidence.source),
           followingURL != nil, evidence.pageURL == followingURL {
            evidenceBinding = evidence.binding
            visibleConnection = .init(source: source.rawValue, account: "自动跟随聊天来源", binding: evidence.binding, identity: evidence.identity)
        }
        receivedAt = Date(); pendingEvidence = evidence
        candidates.removeAll { $0.source == evidence.source && $0.binding == evidence.binding }
        candidates.insert(evidence, at: 0); if candidates.count > 8 { candidates.removeLast(candidates.count - 8) }
        guard !awaitingEntrance, evidence.binding == evidenceBinding, source == sourceFor(evidence.source) else { return }
        accountDisplayName = evidence.identity!.displayName
        plan = evidence.snapshot.reportedPlan ?? .unknown
        if following, let connection = visibleConnection, let saved = try? JSONEncoder().encode(connection) { settings.set(saved, forKey: "visibleUsageConnection") }
        if evidence.contentSignature != evidenceSignature || snapshot == nil || evidence.source == .usagePage {
            evidenceSignature = evidence.contentSignature; snapshot = evidence.snapshot
        }
        stale = snapshot?.isStale(at: Date()) == true
        status = (stale ? "相同报告，额度证据未更新 · " : (evidence.source == .usagePage ? "最近核对 · " : "已更新 · ")) + source.name
    }
    func migrateVisible(account: String, evidence selected: UsageEvidence? = nil) throws {
        let label = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label.count <= 80, let evidence = selected ?? pendingEvidence,
              let identity = evidence.identity, identity.valid, !evidence.snapshot.isStale(at: Date()),
              let state = accountStates[key(evidence.source, evidence.binding)], state.epoch == evidence.epoch,
              state.sequence == evidence.sequence, state.fingerprint == identity.fingerprint else { throw ClaudeUsageError.connection }
        let connection = VisibleConnection(source: sourceFor(evidence.source).rawValue, account: label, binding: evidence.binding, identity: identity)
        guard connection.valid else { throw ClaudeUsageError.connection }
        let encoded = try JSONEncoder().encode(connection)
        settings.set(false, forKey: "usageConnected")
        settings.set(encoded, forKey: "visibleUsageConnection")
        visibleConnection = connection
        configure(sourceFor(evidence.source))
        accountLabel = label; accountDisplayName = identity.displayName; evidenceBinding = evidence.binding; evidenceSignature = evidence.contentSignature
        snapshot = evidence.snapshot; status = "已切换 · " + source.name
    }
    func captureVisibleUsage() async {
        do { let evidence = try await Task.detached { try VisibleUsageAccessibility.capture() }.value; receive(evidence) }
        catch { status = error.localizedDescription + "；请先打开桌面 Usage，或使用网页/CLI 可见来源。" }
    }
    func disconnect() {
        acquisitionTask?.cancel(); acquisitionTask = nil; acquiring = false; following = false; followingURL = nil
        stop(); settings.set(false, forKey: "usageConnected"); settings.removeObject(forKey: "visibleUsageConnection"); visibleConnection = nil
        snapshot = nil; plan = .unknown; fingerprint = nil; organization = ""; stale = false; accountDisplayName = "账户待核对"; evidenceBinding = ""; accountLabel = ""; status = "连接额度后自动更新"
    }
    func stop() {
        replyRefresh?.cancel(); replyRefresh = nil
        generation = UUID(); task?.cancel(); task = nil; automaticRetry?.cancel(); automaticRetry = nil; requested = false; refreshing = false
        acquisitionTask?.cancel(); acquisitionTask = nil; acquiring = false
    }
    func refresh(force: Bool = false, allowPrompt: Bool = false) {
        guard !invalidVisibleConnection, !awaitingEntrance else { return }
        guard enabled() || visibleConnection != nil else { return }
        guard source == .desktop || source == .session else {
            if force, source != .visibleAX { acquire(channel, binding: evidenceBinding.isEmpty ? nil : evidenceBinding, pageURL: followingURL); return }
            stale = snapshot?.isStale(at: Date()) == true
            status = "等待已连接可见来源的新值；不会回退登录凭据。"
            return
        }
        guard task == nil else { return }
        requested = true
        if retryAfter > Date() {
            // Keep the actionable reason (e.g. keychain authorization) visible.
            status = lastFailure.map { $0 + "（稍后自动重试）" } ?? "查询稍后重试"; stale = snapshot != nil
            if automaticRetry == nil {
                let seconds = max(0, retryAfter.timeIntervalSinceNow)
                automaticRetry = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(seconds))
                    guard !Task.isCancelled, let self else { return }
                    self.automaticRetry = nil; self.refresh()
                }
            }
            return
        }
        refreshing = true; status = "正在读取 Claude 额度…"
        let token = generation; let source = self.source; let load = self.load; let fetch = self.fetch
        task = Task { [weak self] in
            guard let self else { return }
            var prompt = allowPrompt
            repeat {
                requested = false
                do {
                    let shouldPrompt = prompt; prompt = false
                    let connection = try await Credentials.offMainRead { try load(source, shouldPrompt) }
                    guard generation == token, !Task.isCancelled else { return }
                    if fingerprint != connection.fingerprint { snapshot = nil; plan = .unknown; stale = false }
                    let identityChanged = fingerprint != connection.fingerprint
                    fingerprint = connection.fingerprint; organization = connection.organization; accountDisplayName = "当前登录账户已核对"
                    if !force && !identityChanged && snapshot != nil && Date().timeIntervalSince(lastSuccess) < 60 {
                        status = "已更新 · " + source.name; break
                    }
                    let (value, plan) = try await fetch(connection)
                    guard generation == token, !Task.isCancelled else { return }
                    // Re-read the identity after the request so an account switch cannot publish old data.
                    let current = try await Credentials.offMainRead { try load(source, false) }
                    guard generation == token, !Task.isCancelled else { return }
                    if current.fingerprint != connection.fingerprint {
                        snapshot = nil; self.plan = .unknown; fingerprint = nil; accountDisplayName = "账户待核对"; requested = true; continue
                    }
                    snapshot = value; self.plan = plan; lastSuccess = Date(); failures = 0; lastFailure = nil; stale = false; status = "已更新 · " + source.name
                } catch {
                    guard generation == token, !Task.isCancelled else { return }
                    stale = snapshot != nil; status = error.localizedDescription; lastFailure = error.localizedDescription
                    if let error = error as? ClaudeUsageError, error == .expired || error == .desktopMissing || error == .keychain || error == .connection {
                        snapshot = nil; plan = .unknown; fingerprint = nil; organization = ""; stale = false; accountDisplayName = "账户待核对"
                    }
                    failures += 1
                    retryAfter = Date().addingTimeInterval((error as? ServiceCooldown)?.seconds ?? ((error as? ClaudeUsageError) == .rateLimited ? 60 : min(300, 15 * pow(2, Double(min(failures - 1, 4))))))
                    requested = error is ServiceCooldown || (error as? ClaudeUsageError) == .rateLimited || (error as? ClaudeUsageError) == .network
                    break
                }
            } while requested && !Task.isCancelled
            guard generation == token else { return }
            task = nil; refreshing = false
            if requested { refresh() }
        }
    }
}
