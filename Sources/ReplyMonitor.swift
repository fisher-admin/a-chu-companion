import AppKit
import SwiftUI
import Translation

@MainActor final class ReplyMonitor: ObservableObject {
    @Published var watching = false
    @Published var translating = false
    @Published var reverseConfiguration: TranslationSession.Configuration?
    @Published private(set) var systemTaskID: UUID?
    private var systemJob: (candidate: ReplyCandidate, session: UUID, attempt: UUID)?
    @Published var status = ""
    @Published var original = ""
    @Published var chinese = ""
    @Published var sourceName = "Claude"
    var showPanel: () -> Void = {}
    var onReply: (String, String, String, TranslationLanguage) -> Void = { _, _, _, _ in }
    var onReplyAcquired: (String, String, TranslationLanguage) -> Void = { _, _, _ in }
    var onReplyObserved: () -> Void = {}
    private var lastUsageCandidate: ReplyCandidate?
    private var source: ClaudeSource?
    private var tracker: ConversationReplyTracker?
    private var queue = ReplyWorkQueue()
    @Published var historyChoices: [ReplyWork] = []
    @Published var showHistoryPicker = false
    private var historyRequestID: UUID?
    private var versionConversation = ""
    private var manualVersion = false
    private var polling: Task<Void, Never>?
    private var translation: Task<Void, Never>?
    private var replyTimeout: Task<Void, Never>?
    private var replyLifecycle = ReplyTranslationLifecycle()
    private var sessionID = UUID()
    private var version: ReplyCandidate?
    private var language: TranslationLanguage = .english
    private var activeSession: TranslationSession?
    private var engine = "apple"
    private var baseURL = ""
    private var model = ""
    private var errors = 0
    var canRetry: Bool {
        guard !translating, chinese.isEmpty, !original.isEmpty, original.count <= ForeignTextPolicy.limit, let version else { return false }
        return isReplyCurrent(version)
    }

    func connect(target: TargetBridge.Target, engine: String, baseURL: String, model: String, language: TranslationLanguage = .english) async {
        stop(clear: true)
        let token = UUID(); sessionID = token
        self.engine = engine; self.baseURL = baseURL; self.model = model; self.language = language
        sourceName = target.name; watching = true
        status = "正在连接 Claude，连接后持续读取正式回复…"
        do {
            let pid = target.app.processIdentifier
            let bundle = target.app.bundleIdentifier ?? ""
            let element = target.element; let window = target.window; let name = target.name
            let source = try await Task.detached(priority: .utility) {
                try ClaudeSource.bind(pid: pid, bundle: bundle, composer: element, window: window, name: name)
            }.value
            guard sessionID == token, watching else { return }
            self.source = source
            errors = 0
            status = "已连接 Claude，持续读取正式回复。"
            startPolling()
        } catch { if sessionID == token { pause("读取未启动：" + error.localizedDescription) } }
    }
    func configure(engine: String, baseURL: String, model: String, language: TranslationLanguage) {
        guard self.engine != engine || self.baseURL != baseURL || self.model != model || self.language != language else { return }
        self.engine = engine; self.baseURL = baseURL; self.model = model; self.language = language
        cancelReplyTranslation(resetSystemSession: true)
        tracker = nil; queue.clear(); version = nil; lastUsageCandidate = nil
        if watching { status = "翻译设置已更新，继续读取当前会话…" }
    }
    func startPolling() {
        guard watching, let source, polling == nil else { return }
        showPanel()
        let token = sessionID
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.sessionID == token, self.watching else { return }
                do {
                    let snapshot = try await source.capture()
                    guard self.sessionID == token, self.watching else { return }
                    if self.tracker?.conversation != snapshot.conversation {
                        if !self.manualVersion {
                            self.cancelReplyTranslation(resetSystemSession: true)
                            self.version = nil
                        }
                        self.queue.removeAutomatic(); self.lastUsageCandidate = nil
                        self.tracker = ConversationReplyTracker(baseline: snapshot.messages, conversation: snapshot.conversation)
                        self.status = "已跟随当前 Claude 会话，持续读取正式回复。"
                    }
                    let candidates = try self.tracker?.observe(conversation: snapshot.conversation, messages: snapshot.messages,
                                                              responseComplete: snapshot.responseComplete,
                                                              now: Date().timeIntervalSinceReferenceDate) ?? []
                    self.errors = 0
                    if let current = self.version, !self.manualVersion, self.translating, !self.isReplyCurrent(current) {
                        self.cancelReplyTranslation(resetSystemSession: true)
                    }
                    for candidate in candidates {
                        if self.version == candidate && self.versionConversation == snapshot.conversation { continue }
                        self.queue.add(ReplyWork(candidate: candidate, conversation: snapshot.conversation))
                    }
                    self.continueReplies()
                    if !self.translating && !snapshot.responseComplete {
                        self.status = "Claude 正在运行，等待完整正式回复…"
                    }
                } catch {
                    guard self.sessionID == token else { return }
                    self.handleReadFailure(error)
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    func readVisible(target: TargetBridge.Target, engine: String, baseURL: String, model: String, language: TranslationLanguage) async {
        configure(engine: engine, baseURL: baseURL, model: model, language: language)
        let request = UUID(); historyRequestID = request
        status = "正在读取 Claude 当前可见的正式回复…"
        do {
            let pid = target.app.processIdentifier; let bundle = target.app.bundleIdentifier ?? ""
            let element = target.element; let window = target.window; let name = target.name
            let visibleSource = try await Task.detached(priority: .utility) {
                try ClaudeSource.bind(pid: pid, bundle: bundle, composer: element, window: window, name: name)
            }.value
            let snapshot = try await visibleSource.captureVisibleReplies()
            guard historyRequestID == request else { return }
            historyRequestID = nil
            historyChoices = snapshot.messages.map {
                ReplyWork(candidate: ReplyCandidate(ordinal: $0.ordinal, text: $0.text), conversation: snapshot.conversation, manual: true)
            }
            if historyChoices.count == 1 { selectHistoryReply(historyChoices[0]) }
            else if historyChoices.isEmpty { status = "没有找到可见的完整正式回复，请在 Claude 中滚动到要翻译的消息。" }
            else { showHistoryPicker = true; status = "请选择当前可见的 Claude 历史回复。" }
        } catch {
            guard historyRequestID == request else { return }
            historyRequestID = nil
            status = "读取当前回复失败：" + error.localizedDescription
        }
    }
    func selectHistoryReply(_ work: ReplyWork) {
        guard work.manual, historyChoices.contains(work) else { return }
        showHistoryPicker = false; historyChoices = []
        if translating && version == work.candidate && versionConversation == work.conversation {
            status = "这条回复正在翻译，请稍候。"
            return
        }
        queue.add(work)
        continueReplies()
    }
    private func continueReplies() {
        guard !translating else { return }
        while let work = queue.pop() {
            guard work.manual || (watching && tracker?.conversation == work.conversation && tracker?.isCurrent(work.candidate) == true) else { continue }
            translate(work.candidate, conversation: work.conversation, manual: work.manual, token: sessionID)
            return
        }
    }
    private func isReplyCurrent(_ candidate: ReplyCandidate) -> Bool {
        guard version == candidate else { return false }
        return manualVersion || (tracker?.conversation == versionConversation && tracker?.isCurrent(candidate) == true)
    }
    private func replyID(_ candidate: ReplyCandidate) -> String {
        ReplyIdentity.id(conversation: versionConversation, ordinal: candidate.ordinal)
    }
    func handleReadFailure(_ error: Error) {
        if let pending = error as? ReplyReadPending {
            // Thinking, tool use and streaming may leave the latest card
            // unreadable for minutes. Preserve the verified baseline and
            // never feed a partial snapshot to the tracker.
            errors = 0
            status = "等待 Claude 原文，自动读取会继续检查。" + pending.localizedDescription
        } else {
            errors += 1
            if errors >= 5 { pause(error.localizedDescription) }
            else { status = "正在重新检查 Claude 页面…" }
        }
    }
    func reportReplyObserved(_ candidate: ReplyCandidate) {
        if lastUsageCandidate != candidate {
            lastUsageCandidate = candidate
            onReplyObserved()
        }
    }
    private func translate(_ candidate: ReplyCandidate, conversation: String, manual: Bool, token: UUID) {
        reportReplyObserved(candidate)
        cancelReplyTranslation(resetSystemSession: false)
        let attempt = replyLifecycle.begin()
        version = candidate; versionConversation = conversation; manualVersion = manual; original = candidate.text; chinese = ""; translating = replyLifecycle.isTranslating
        onReplyAcquired(replyID(candidate), candidate.text, language)
        do { try ForeignTextPolicy.validate(candidate.text, incoming: true) }
        catch { cancelReplyTranslation(resetSystemSession: true); status = error.localizedDescription; continueReplies(); return }
        if engine == "apple" {
            status = "原文已读取，正在检查翻译语言…"
            let job = (candidate: candidate, session: token, attempt: attempt)
            systemJob = job
            reverseConfiguration = nil; systemTaskID = nil
            let from = Locale.Language(identifier: language.rawValue)
            let to = Locale.Language(identifier: "zh-Hans")
            translation = Task {
                do {
                    let installed = try await TextTranslation.withDeadline(timeout: .seconds(10)) {
                        await LanguageAvailability().status(from: from, to: to) == .installed ? "installed" : "download"
                    }
                    guard isCurrent(job), !Task.isCancelled else { return }
                    if installed == "installed", #available(macOS 26.0, *) {
                        // Installed packs do not need a view-provided session or a download prompt.
                        let session = TranslationSession(installedSource: from, target: to)
                        await runSystemReply(session, attempt: attempt, prepare: false)
                    } else {
                        status = "原文已读取，正在启动系统翻译…"
                        systemTaskID = attempt
                        reverseConfiguration = .init(source: from, target: to)
                        armReplyTimeout(candidate, token: token, attempt: attempt, stage: "翻译任务启动", after: .seconds(20))
                    }
                } catch { translationFailed(error, candidate: candidate, token: token, attempt: attempt) }
            }
            return
        }
        status = "正在把 Claude 的回复翻译成中文…"
        let base = baseURL; let model = self.model
        translation = Task {
            do {
                let key = try Credentials.read(); let language = self.language
                let translated = try await TextTranslation.run(candidate.text, progress: { [weak self] part, total in
                    self?.status = "正在把回复译回中文… \(part) / \(total) 段"
                }) { chunk in
                    let request = try AIProtocol.request(text: chunk, baseURL: base, model: model, key: key, direction: .toChinese(language))
                    return try await AITranslator.translate(request)
                }
                commit(translated, candidate: candidate, token: token, attempt: attempt)
            } catch { translationFailed(error, candidate: candidate, token: token, attempt: attempt) }
        }
    }
    func runSystemReply(_ session: TranslationSession, attempt: UUID, prepare: Bool = true) async {
        guard let job = systemJob, job.attempt == attempt, isCurrent(job) else { return }
        do {
            activeSession = session
            replyTimeout?.cancel(); replyTimeout = nil
            if prepare {
                status = "原文已读取，正在准备翻译语言…"
                _ = try await TextTranslation.withDeadline { try await session.prepareTranslation(); return "" }
            }
            guard isCurrent(job) else { return }
            let translated = try await TextTranslation.run(job.candidate.text, progress: { [weak self] part, total in
                self?.status = "正在把回复译回中文… \(part) / \(total) 段"
            }) { chunk in
                guard self.isCurrent(job) else { throw CancellationError() }
                let value = try await session.translate(chunk).targetText
                guard self.isCurrent(job) else { throw CancellationError() }
                return value
            }
            commit(translated, candidate: job.candidate, token: job.session, attempt: job.attempt)
        } catch { translationFailed(error, candidate: job.candidate, token: job.session, attempt: job.attempt) }
    }
    private func isCurrent(_ job: (candidate: ReplyCandidate, session: UUID, attempt: UUID)) -> Bool {
        sessionID == job.session && version == job.candidate && replyLifecycle.isCurrent(job.attempt)
    }
    private func armReplyTimeout(_ candidate: ReplyCandidate, token: UUID, attempt: UUID, stage: String, after duration: Duration) {
        replyTimeout?.cancel()
        replyTimeout = Task { [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            self?.replyTranslationTimedOut(candidate, token: token, attempt: attempt, stage: stage)
        }
    }
    private func replyTranslationTimedOut(_ candidate: ReplyCandidate, token: UUID, attempt: UUID, stage: String) {
        guard sessionID == token, version == candidate, replyLifecycle.finish(attempt) else { return }
        defer { continueReplies() }
        replyTimeout = nil
        translation?.cancel(); translation = nil
        let timedOutSystemJob = systemJob?.attempt == attempt
        systemJob = nil
        if timedOutSystemJob { reverseConfiguration = nil; systemTaskID = nil }
        translating = replyLifecycle.isTranslating
        if !isReplyCurrent(candidate) {
            status = "Claude 正在回复，等待文字稳定…"
        } else {
            status = "回复翻译超时（\(stage)），可点击重试。"
        }
    }
    private func commit(_ result: String, candidate: ReplyCandidate, token: UUID, attempt: UUID) {
        guard sessionID == token, version == candidate, replyLifecycle.finish(attempt) else { return }
        defer { continueReplies() }
        activeSession = nil
        replyTimeout?.cancel(); replyTimeout = nil
        if systemJob?.attempt == attempt { systemJob = nil }
        translation = nil
        translating = replyLifecycle.isTranslating
        guard isReplyCurrent(candidate) else {
            status = "Claude 正在回复，等待文字稳定…"
            return
        }
        guard !Task.isCancelled else {
            status = "回复翻译已取消，可点击重试。"
            return
        }
        chinese = result
        onReply(replyID(candidate), candidate.text, result, language)
        status = "中文译文已更新。若 Claude 继续补充，译文会随之更新。"
    }
    private func translationFailed(_ error: Error, candidate: ReplyCandidate, token: UUID, attempt: UUID) {
        guard sessionID == token, version == candidate, replyLifecycle.finish(attempt) else { return }
        defer { continueReplies() }
        if #available(macOS 26.0, *) { activeSession?.cancel() }
        activeSession = nil
        replyTimeout?.cancel(); replyTimeout = nil
        if systemJob?.attempt == attempt { systemJob = nil }
        translation = nil
        translating = replyLifecycle.isTranslating
        guard isReplyCurrent(candidate) else {
            status = "Claude 正在回复，等待文字稳定…"
            return
        }
        if Task.isCancelled || error is CancellationError {
            status = "回复翻译已取消，可点击重试。"
        } else {
            status = "回复翻译失败：" + error.localizedDescription
                + (original.count <= ForeignTextPolicy.limit ? "；可点击重试。" : "")
        }
    }
    private func cancelReplyTranslation(resetSystemSession: Bool) {
        let hadSystemJob = systemJob != nil
        if #available(macOS 26.0, *) { activeSession?.cancel() }
        activeSession = nil
        replyTimeout?.cancel(); replyTimeout = nil
        translation?.cancel(); translation = nil
        if let attempt = replyLifecycle.activeID { _ = replyLifecycle.cancel(attempt) }
        systemJob = nil
        translating = replyLifecycle.isTranslating
        if resetSystemSession && hadSystemJob { reverseConfiguration = nil; systemTaskID = nil }
    }
    func cancelTranslation() {
        guard translating else { return }
        cancelReplyTranslation(resetSystemSession: true)
        status = "回复翻译已取消，可点击重试。"
    }
    func retry() {
        guard canRetry, let candidate = version else { return }
        translate(candidate, conversation: versionConversation, manual: manualVersion, token: sessionID)
    }
    private func pause(_ message: String) {
        watching = false; cancelReplyTranslation(resetSystemSession: true); polling?.cancel(); polling = nil
        reverseConfiguration = nil
        systemTaskID = nil
        status = message
    }
    func clearRecords() {
        cancelReplyTranslation(resetSystemSession: true)
        queue.clear(); version = nil; original = ""; chinese = ""
        historyRequestID = nil; historyChoices = []; showHistoryPicker = false
        status = watching ? "本地记录已清除，继续读取 Claude 的新回复。" : "本地记录已清除。"
    }
    func stop(clear: Bool = false) {
        sessionID = UUID(); watching = false
        polling?.cancel(); polling = nil; cancelReplyTranslation(resetSystemSession: true)
        source = nil; tracker = nil; queue.clear(); version = nil; lastUsageCandidate = nil
        historyRequestID = nil; historyChoices = []; showHistoryPicker = false
        reverseConfiguration = nil
        systemTaskID = nil
        status = "自动读取已停止。"
        if clear { original = ""; chinese = "" }
    }
}
