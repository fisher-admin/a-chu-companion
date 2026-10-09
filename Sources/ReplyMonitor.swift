import AppKit
import SwiftUI
import Translation

enum ReplyReadError: LocalizedError, Equatable {
    case uiStructureChanged(String)
    var errorDescription: String? {
        switch self {
        case let .uiStructureChanged(detail):
            return "Claude 界面结构已变化，暂时无法读取回复（\(detail)）。请确认 Claude 窗口仍显示对话；Claude 更新后如仍无法读取，请重新按 ⌃⌥E 连接或更新A畜伴侣。"
        }
    }
}

@MainActor final class ReplyMonitor: ObservableObject {
    @Published var watching = false
    @Published private(set) var translating = false
    @Published var status = ""
    @Published var original = ""
    @Published var chinese = ""
    @Published var sourceName = "Claude"
    /// Set after Claude's transcript, message markers or composer stay unresolvable.
    @Published private(set) var readError: ReplyReadError?
    /// Why the latest reply used system translation instead of AI, if it did.
    @Published private(set) var fallbackNotice: String?
    @Published var historyChoices: [ReplyWork] = []
    @Published var showHistoryPicker = false
    let circuit = AICircuit()
    let systemTranslator = SystemTranslator()
    let broker = SystemSessionBroker()
    var showPanel: () -> Void = {}
    /// Partial original and in-order partial Chinese while a reply streams.
    var onReplyProgress: (String, String, String, TranslationLanguage) -> Void = { _, _, _, _ in }
    /// The finished reply and its complete translation.
    var onReply: (String, String, String, TranslationLanguage) -> Void = { _, _, _, _ in }
    /// A reply whose translation was stopped; only its original remains valid.
    var onReplyStopped: (String, String, TranslationLanguage) -> Void = { _, _, _ in }
    var onReplyObserved: () -> Void = {}
    var now: () -> Date = Date.init
    var structureTimeout: TimeInterval = 45
    /// Test hook; production builds translators from the current settings.
    var translatorFactory: (() -> FailoverTranslator)?

    private final class LiveReply {
        let id: String, ordinal: Int, conversation: String, manual: Bool
        let pipeline: StreamTranslationPipeline
        var text = ""
        /// Claude finished writing this text; the pipeline has been told so.
        var sourceComplete = false
        var done = false
        /// Stopped by the user or a session change; only an explicit retry restarts it.
        var stopped = false
        init(id: String, ordinal: Int, conversation: String, manual: Bool, pipeline: StreamTranslationPipeline) {
            self.id = id; self.ordinal = ordinal; self.conversation = conversation; self.manual = manual; self.pipeline = pipeline
        }
    }

    private var lastUsageCandidate: ReplyCandidate?
    private var source: ClaudeSource?
    private var tracker: StreamingReplyTracker?
    private var live: [String: LiveReply] = [:]
    private var latestID: String?
    private var historyRequestID: UUID?
    private var polling: Task<Void, Never>?
    private var sessionID = UUID()
    private var language: TranslationLanguage = .english
    private var engine = "apple"
    private var baseURL = ""
    private var model = ""
    private var errors = 0
    private var structuralSince: Date?

    init() {
        systemTranslator.sessionProvider = { [weak broker] direction in
            guard let broker else { throw CancellationError() }
            return try await broker.session(for: direction)
        }
        broker.onNeedsPresentation = { [weak self] in self?.showPanel() }
    }

    var canRetry: Bool {
        guard !translating, let id = latestID, let reply = live[id], reply.text.count <= ForeignTextPolicy.limit else { return false }
        return reply.stopped || (reply.done && !reply.pipeline.state.failedSegments.isEmpty)
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
            status = "已连接 Claude，边接收边翻译正式回复。"
            startPolling()
        } catch { if sessionID == token { pause("读取未启动：" + error.localizedDescription) } }
    }

    func configure(engine: String, baseURL: String, model: String, language: TranslationLanguage) {
        guard self.engine != engine || self.baseURL != baseURL || self.model != model || self.language != language else { return }
        let engineChanged = self.engine != engine || self.baseURL != baseURL || self.model != model
        self.engine = engine; self.baseURL = baseURL; self.model = model; self.language = language
        stopAll()
        // Re-reading from a fresh baseline translates the current reply again with the new settings.
        tracker = nil; lastUsageCandidate = nil; fallbackNotice = nil
        systemTranslator.reset(); broker.reset()
        if engineChanged { circuit.reset() }
        if watching { status = "翻译设置已更新，继续读取当前会话…" }
    }

    func startPolling() {
        guard watching, let source, polling == nil else { return }
        showPanel()
        let token = sessionID
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.sessionID == token, self.watching else { return }
                var interval: Duration = .seconds(1)
                do {
                    let snapshot = try await source.capture()
                    guard self.sessionID == token, self.watching else { return }
                    try self.process(snapshot)
                    // Poll faster while text is arriving so segments start translating sooner.
                    if !snapshot.responseComplete || self.translating { interval = .milliseconds(500) }
                } catch {
                    guard self.sessionID == token else { return }
                    self.handleReadFailure(error)
                }
                if self.readError != nil { interval = .seconds(3) }
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Applies one verified snapshot of the bound conversation.
    func process(_ snapshot: ReplySnapshot) throws {
        if tracker?.conversation != snapshot.conversation {
            for reply in live.values where !reply.manual && !reply.done { stop(reply) }
            lastUsageCandidate = nil
            tracker = StreamingReplyTracker(baseline: snapshot.messages, conversation: snapshot.conversation)
            status = "已跟随当前 Claude 会话，边接收边翻译正式回复。"
        }
        guard var current = tracker else { return }
        let progress = try current.observe(conversation: snapshot.conversation, messages: snapshot.messages, responseComplete: snapshot.responseComplete)
        tracker = current
        errors = 0
        if snapshot.foundComposer { recovered() } else { noteStructural("未找到 Claude 输入框") }
        for item in progress { advance(item, conversation: snapshot.conversation, manual: false) }
        updateTranslating()
        if !translating && !snapshot.responseComplete && readError == nil { status = "Claude 正在运行，等待正式回复文字…" }
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
        if let reply = live[work.id], reply.text == work.candidate.text, !reply.done, !reply.stopped {
            status = "这条回复正在翻译，请稍候。"
            return
        }
        advance(ReplyProgress(candidate: work.candidate, complete: true), conversation: work.conversation, manual: true, restart: true)
        updateTranslating()
    }

    func handleReadFailure(_ error: Error) {
        if let pending = error as? ReplyReadPending {
            // Thinking, tool use and streaming may leave the latest card unreadable for
            // minutes; that is normal. Only structural failures count toward escalation.
            errors = 0
            if pending.structural { noteStructural(pending.message) }
            else if readError == nil { status = "等待 Claude 原文，自动读取会继续检查。" + pending.localizedDescription }
        } else {
            errors += 1
            if errors >= 5 { pause(error.localizedDescription) }
            else if readError == nil { status = "正在重新检查 Claude 页面…" }
        }
    }

    func reportReplyObserved(_ candidate: ReplyCandidate) {
        if lastUsageCandidate != candidate {
            lastUsageCandidate = candidate
            onReplyObserved()
        }
    }

    func cancelTranslation() {
        guard translating else { return }
        for reply in live.values where !reply.done { stop(reply) }
        updateTranslating()
        status = "回复翻译已取消，可点击重试。"
    }

    func retry() {
        guard canRetry, let id = latestID, let reply = live[id] else { return }
        if reply.stopped {
            advance(ReplyProgress(candidate: ReplyCandidate(ordinal: reply.ordinal, text: reply.text), complete: reply.sourceComplete),
                    conversation: reply.conversation, manual: reply.manual, restart: true)
        } else {
            reply.done = false
            fallbackNotice = nil
            reply.pipeline.retryFailed()
        }
        updateTranslating()
    }

    func clearRecords() {
        stopAll()
        live = [:]; latestID = nil; original = ""; chinese = ""
        historyRequestID = nil; historyChoices = []; showHistoryPicker = false
        status = watching ? "本地记录已清除，继续读取 Claude 的新回复。" : "本地记录已清除。"
    }

    func stop(clear: Bool = false) {
        sessionID = UUID(); watching = false
        polling?.cancel(); polling = nil
        stopAll()
        source = nil; tracker = nil; lastUsageCandidate = nil
        historyRequestID = nil; historyChoices = []; showHistoryPicker = false
        readError = nil; structuralSince = nil
        broker.reset()
        status = "自动读取已停止。"
        if clear { original = ""; chinese = ""; live = [:]; latestID = nil }
    }

    // MARK: Streaming

    private func advance(_ progress: ReplyProgress, conversation: String, manual: Bool, restart: Bool = false) {
        let candidate = progress.candidate
        let id = ReplyIdentity.id(conversation: conversation, ordinal: candidate.ordinal)
        var reply = live[id]
        let changed = reply.map { $0.text != candidate.text } ?? true
        // A finished reply whose text changed (regenerated, edited, or extended after a
        // premature completion signal) starts over; a stopped one waits for an explicit retry.
        if restart || reply == nil || (changed && !reply!.stopped && (reply!.done || reply!.sourceComplete)) {
            reply?.pipeline.cancel()
            reply = start(id: id, ordinal: candidate.ordinal, conversation: conversation, manual: manual)
        }
        guard let reply else { return }
        reply.text = candidate.text
        if progress.complete { reply.sourceComplete = true }
        if reply.stopped {
            if changed { onReplyStopped(id, candidate.text, language) }
            return
        }
        guard !reply.done else { return }
        latestID = id
        original = candidate.text
        do { try ForeignTextPolicy.validate(candidate.text, incoming: true) } catch {
            reply.pipeline.cancel(); reply.stopped = true
            onReplyStopped(id, candidate.text, language)
            status = error.localizedDescription
            return
        }
        if progress.complete { reply.pipeline.finish(snapshot: candidate.text) } else { reply.pipeline.ingest(snapshot: candidate.text) }
        if !reply.done { onReplyProgress(id, candidate.text, reply.pipeline.state.translated, language) }
    }

    private func start(id: String, ordinal: Int, conversation: String, manual: Bool) -> LiveReply {
        let pipeline = StreamTranslationPipeline(translator: makeTranslator(), direction: .toChinese(language))
        let reply = LiveReply(id: id, ordinal: ordinal, conversation: conversation, manual: manual, pipeline: pipeline)
        live[id] = reply
        fallbackNotice = nil
        let language = self.language
        pipeline.onUpdate = { [weak self, weak reply] state in
            guard let self, let reply, self.live[reply.id] === reply, !reply.stopped else { return }
            if self.latestID == reply.id { self.chinese = state.translated }
            if state.complete {
                reply.done = true
                self.onReply(reply.id, reply.text, state.translated, language)
                self.reportReplyObserved(ReplyCandidate(ordinal: reply.ordinal, text: reply.text))
                if let failure = state.lastFailure, !state.failedSegments.isEmpty {
                    self.status = "\(state.failedSegments.count) 段未能翻译，已在原位置保留原文：\(failure) 可点击重试。"
                } else {
                    self.status = self.fallbackNotice.map { "中文译文已更新。" + $0 } ?? "中文译文已更新。若 Claude 继续补充，译文会随之更新。"
                }
            } else {
                self.onReplyProgress(reply.id, reply.text, state.translated, language)
                if self.readError == nil { self.status = "正在边接收边翻译… 已完成 \(state.renderedSegments) / \(state.totalSegments) 段" }
            }
            self.updateTranslating()
        }
        return reply
    }

    private func makeTranslator() -> FailoverTranslator {
        let translator: FailoverTranslator
        if let translatorFactory { translator = translatorFactory() } else {
            let useAI = engine == "ai"
            let key = useAI ? ((try? Credentials.read()) ?? "") : ""
            translator = FailoverTranslator(preferAI: useAI, circuit: circuit,
                                            ai: FailoverTranslator.openAICompatible(baseURL: baseURL, model: model, key: key),
                                            system: { [weak self] text, direction in
                                                guard let self else { throw CancellationError() }
                                                return try await self.systemTranslator.translate(text, direction: direction)
                                            })
        }
        let previous = translator.onFallback
        translator.onFallback = { [weak self] reason in
            previous(reason)
            self?.fallbackNotice = reason.message
        }
        return translator
    }

    private func stop(_ reply: LiveReply) {
        guard !reply.done, !reply.stopped else { return }
        reply.pipeline.cancel(); reply.stopped = true
        onReplyStopped(reply.id, reply.text, language)
    }

    private func stopAll() {
        for reply in live.values { stop(reply) }
        updateTranslating()
    }

    private func updateTranslating() {
        translating = live.values.contains { !$0.done && !$0.stopped }
    }

    // MARK: Structure escalation

    private func noteStructural(_ detail: String) {
        let time = now()
        let since = structuralSince ?? time
        structuralSince = since
        if time.timeIntervalSince(since) >= structureTimeout {
            if readError == nil {
                readError = .uiStructureChanged(detail)
                status = readError?.localizedDescription ?? detail
                showPanel()
            }
        } else if readError == nil {
            status = "正在等待 Claude 界面就绪：" + detail
        }
    }

    private func recovered() {
        structuralSince = nil
        if readError != nil {
            readError = nil
            status = "Claude 界面已恢复，继续读取。"
        }
    }

    private func pause(_ message: String) {
        watching = false
        polling?.cancel(); polling = nil
        stopAll()
        broker.reset()
        status = message
    }
}
