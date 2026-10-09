import AppKit
import SwiftUI
import Translation

@MainActor final class ReplyMonitor: ObservableObject {
    @Published var watching = false
    @Published var translating = false
    @Published var reverseConfiguration: TranslationSession.Configuration?
    @Published private(set) var systemTaskID: UUID?
    @Published var status = ""
    @Published var original = ""
    @Published var chinese = ""
    @Published var sourceName = "Claude"
    @Published var historyChoices: [ReplyWork] = []
    /// Set after Claude's page, transcript or message markers stay unresolvable.
    @Published private(set) var readError: String?
    var structureTimeout: TimeInterval = 45
    var clock: () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
    private var structuralSince: TimeInterval?
    private var appleTail: Task<Void, Never>?
    @Published var showHistoryPicker = false
    var showPanel: () -> Void = {}
    var onReply: (String, String, String, TranslationLanguage) -> Void = { _, _, _, _ in }
    var onReplyAcquired: (String, String, TranslationLanguage) -> Void = { _, _, _ in }
    var onReplyState: (String, Bool) -> Void = { _, _ in }
    var onManualReply: (String) -> Void = { _ in }
    @Published var stagePreview = CompanionPreferences.store.object(forKey: "stagePreview") as? Bool ?? true {
        didSet { CompanionPreferences.store.set(stagePreview, forKey: "stagePreview"); resetTranslation() }
    }
    var onReplyObserved: () -> Void = {}
    /// Fires once per completed reply (the latest assistant message with the
    /// source reporting completion), never for streaming updates.
    var onReplyCompleted: () -> Void = {}
    private var lastCompletedCandidate: ReplyCandidate?
    private var completedConversation = ""
    var testTranslation: (@MainActor (String) async throws -> String)?
    var testFallback: (@MainActor (String) async throws -> String)?
    private var lastUsageCandidate: ReplyCandidate?
    private var source: ClaudeSource?
    private var polling: Task<Void, Never>?
    private var sessionID = UUID()
    private var historyRequestID: UUID?
    private var language: TranslationLanguage = .english
    private var engine = "apple"
    private var baseURL = ""
    private var model = ""
    private var errors = 0
    private(set) var readRetrySeconds: Double = 1
    private var transientReadDisplay: (before: String, display: String)?
    private var captureGeneration = UUID()
    private var capturePaused = false
    private(set) var isConnecting = false
    /// Quota temporarily overlays this same page. Keep the translation pipeline
    /// and subscription, but discard captures from either side of the overlay.
    func setCapturePaused(_ paused: Bool) {
        guard capturePaused != paused else { return }
        capturePaused = paused; captureGeneration = UUID()
        if paused { historyRequestID = nil }
    }
    private var pipeline: ReplyPipeline?
    private var retiredRecords = RetiredIDs()
    private var activeSession: TranslationSession?
    private var systemContinuation: CheckedContinuation<TranslationSession, Error>?
    var pipelineRecordCount: Int { pipeline?.recordCount ?? 0 }
    var canRetry: Bool { !translating && pipeline?.hasFailures == true }

    private func translationPipeline() -> ReplyPipeline {
        if let pipeline { return pipeline }
        // Remote services take a few slices at once; system translation shares one session.
        let concurrency = engine == "apple" && testTranslation == nil ? 1 : 3
        let pipeline = ReplyPipeline(incremental: stagePreview, concurrency: concurrency) { [weak self] text in
            guard let self else { throw CancellationError() }
            if let testTranslation { return try await testTranslation(text) }
            if engine == "apple" { return try await translateApple(text) }
            guard let provider = RemoteTranslationProvider(rawValue: engine) else { throw BridgeError.message("翻译方式无效，请重新选择。") }
            let base = baseURL, selectedModel = model, selectedLanguage = language
            let key = try await Credentials.readAsync(for: provider, baseURL: base)
            let request = try provider.request(text: text, baseURL: base, model: selectedModel, key: key, direction: .toChinese(selectedLanguage))
            let raw = try await AITranslator.translate(request, provider: provider)
            return SystemTranslationProtection.simplified(try TranslationCleanup.normalize(raw, source: text))
        }
        if engine != "apple" {
            pipeline.fallback = { [weak self] text in
                guard let self else { throw CancellationError() }
                if let testFallback { return try await testFallback(text) }
                return try await translateApple(text)
            }
        }
        pipeline.onOriginal = { [weak self] id, text, message in
            guard let self else { return }
            original = text; status = message
            onReplyAcquired(id, text, language)
        }
        pipeline.onTranslation = { [weak self] id, foreign, value, complete in
            guard let self else { return }
            chinese = value
            onReply(id, foreign, value, language); onReplyState(id, complete)
        }
        pipeline.onCompletion = { [weak self] id, complete in self?.onReplyState(id, complete) }
        pipeline.onStatus = { [weak self] message, busy in
            guard let self else { return }
            if readError == nil { status = message }
            translating = busy
        }
        pipeline.onIdle = { [weak self] in self?.translating = false }
        pipeline.retire(retiredRecords.all)
        self.pipeline = pipeline
        return pipeline
    }
    func connect(target: TargetBridge.Target, engine: String, baseURL: String, model: String, language: TranslationLanguage = .english) async {
        stop(clear: true)
        let token = UUID(); sessionID = token
        isConnecting = true
        defer { if sessionID == token { isConnecting = false } }
        self.engine = engine; self.baseURL = baseURL; self.model = model; self.language = language
        sourceName = target.name; watching = true; status = "正在连接 Claude，连接后持续读取并翻译正式回复…"
        do {
            let pid = target.app.processIdentifier; let bundle = target.app.bundleIdentifier ?? ""
            let element = target.element; let window = target.window; let name = target.name
            let source = try await Task.detached(priority: .utility) {
                try ClaudeSource.bind(pid: pid, bundle: bundle, composer: element, window: window, name: name)
            }.value
            guard sessionID == token, watching else { return }
            self.source = source; errors = 0; status = "已连接 Claude，持续读取并翻译正式回复。"
            startPolling()
        } catch { if sessionID == token { pause("读取未启动：" + error.localizedDescription) } }
    }
    func configure(engine: String, baseURL: String, model: String, language: TranslationLanguage) {
        guard self.engine != engine || self.baseURL != baseURL || self.model != model || self.language != language else { return }
        self.engine = engine; self.baseURL = baseURL; self.model = model; self.language = language
        resetTranslation(); lastUsageCandidate = nil
        if watching { status = "翻译设置已更新，继续读取并翻译当前会话…" }
    }
    func resetTranslation() { pipeline?.cancel(); pipeline = nil; cancelSystem(); translating = false }
    func ingest(_ snapshot: ReplySnapshot, now: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        guard !capturePaused else { return }
        let addresses = snapshot.messages.map(\.address)
        guard addresses == addresses.sorted(), Set(addresses).count == addresses.count else {
            handleReadFailure(ReplyReadPending(message: "消息顺序尚未完整，等待重新同步。")); return
        }
        if let transientReadDisplay, status == transientReadDisplay.display {
            status = transientReadDisplay.before
        }
        transientReadDisplay = nil
        if let latest = snapshot.messages.last(where: { $0.author == .assistant }) {
            let candidate = ReplyCandidate(ordinal: latest.ordinal, text: latest.text, segment: latest.segment)
            reportReplyObserved(candidate)
            if snapshot.responseComplete, completedConversation != snapshot.conversation || lastCompletedCandidate != candidate {
                completedConversation = snapshot.conversation; lastCompletedCandidate = candidate; onReplyCompleted()
            }
        }
        translationPipeline().observe(conversation: snapshot.conversation, messages: snapshot.messages,
                                      responseComplete: snapshot.responseComplete, now: now)
        translating = pipeline?.busy == true
        errors = 0
        readRetrySeconds = 1
        structuralSince = nil
        if readError != nil { readError = nil; status = "Claude 界面已恢复，继续读取。" }
    }
    func startPolling() {
        guard watching, let source, polling == nil else { return }
        showPanel(); let token = sessionID
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, sessionID == token, watching else { return }
                if capturePaused { try? await Task.sleep(for:.milliseconds(100)); continue }
                let captureToken = captureGeneration
                do {
                    let snapshot = try await source.capture()
                    guard sessionID == token, watching else { return }
                    if captureGeneration == captureToken { ingest(snapshot) }
                } catch {
                    guard sessionID == token else { return }
                    if captureGeneration == captureToken { handleReadFailure(error) }
                }
                try? await Task.sleep(for: .seconds(readRetrySeconds))
            }
        }
    }
    func readVisible(target: TargetBridge.Target, engine: String, baseURL: String, model: String, language: TranslationLanguage) async {
        guard !capturePaused else { status = "正在读取网页额度，恢复会话后可读取历史回复。"; return }
        configure(engine: engine, baseURL: baseURL, model: model, language: language)
        let request = UUID(); historyRequestID = request; status = "正在读取 Claude 当前可见的正式回复…"
        do {
            let pid = target.app.processIdentifier; let bundle = target.app.bundleIdentifier ?? ""
            let element = target.element; let window = target.window; let name = target.name
            let visibleSource = try await Task.detached(priority: .utility) {
                try ClaudeSource.bind(pid: pid, bundle: bundle, composer: element, window: window, name: name)
            }.value
            let snapshot = try await visibleSource.captureVisibleReplies()
            guard historyRequestID == request else { return }
            historyRequestID = nil
            historyChoices = snapshot.messages.map { ReplyWork(candidate: .init(ordinal: $0.ordinal, text: $0.text, segment: $0.segment), conversation: snapshot.conversation, manual: true) }
            if historyChoices.count == 1 { selectHistoryReply(historyChoices[0]) }
            else if historyChoices.isEmpty { status = "没有找到可见的完整正式回复，请在 Claude 中滚动到要翻译的消息。" }
            else { showHistoryPicker = true; status = "请选择当前可见的 Claude 历史回复。" }
        } catch { guard historyRequestID == request else { return }; historyRequestID = nil; status = "读取历史回复失败：" + error.localizedDescription }
    }
    func selectHistoryReply(_ work: ReplyWork) {
        guard work.manual, historyChoices.contains(work) else { return }
        retiredRecords.remove(work.id)
        showHistoryPicker = false; historyChoices = []; onManualReply(work.id); translationPipeline().submit(work)
    }
    /// Fallbacks from concurrent remote slices share one system session; run them in turn.
    private func translateApple(_ text: String) async throws -> String {
        let previous = appleTail
        let work = Task { @MainActor [weak self] () async throws -> String in
            await previous?.value
            try Task.checkCancellation()
            guard let self else { throw CancellationError() }
            return try await self.translateAppleNow(text)
        }
        appleTail = Task { _ = try? await work.value }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }
    private func translateAppleNow(_ text: String) async throws -> String {
        let session: TranslationSession
        if let activeSession { session = activeSession }
        else {
            let from = Locale.Language(identifier: language.rawValue); let to = Locale.Language(identifier: "zh-Hans")
            status = "原文已读取，正在检查翻译语言…"
            let installed = try await TextTranslation.withDeadline(timeout: .seconds(10)) { await LanguageAvailability().status(from: from, to: to) == .installed ? "yes" : "no" }
            try Task.checkCancellation()
            if installed == "yes", #available(macOS 26.0, *) { session = TranslationSession(installedSource: from, target: to) }
            else {
                let id = UUID(); systemTaskID = id
                reverseConfiguration = .init(source: from, target: to)
                status = "正在准备系统语言；原文与已有中文已保留…"
                do {
                    var prepared: TranslationSession?
                    _ = try await TextTranslation.withDeadline(timeout: .seconds(120)) {
                        prepared = try await withCheckedThrowingContinuation { self.systemContinuation = $0 }
                        return "ready"
                    }
                    guard let prepared else { throw CancellationError() }; session = prepared
                } catch { cancelSystem(); throw error }
            }
            activeSession = session
        }
        try Task.checkCancellation()
        let value = try await SystemTranslationProtection.translate(TranslationContext.systemInput(text), toChinese: true) {
            try await session.translate($0).targetText
        }
        try Task.checkCancellation()
        return value
    }
    func runSystemReply(_ session: TranslationSession, attempt: UUID, prepare: Bool = true) async {
        guard systemTaskID == attempt, systemContinuation != nil else { return }
        do {
            if prepare { _ = try await TextTranslation.withDeadline { try await session.prepareTranslation(); return "" } }
            guard systemTaskID == attempt else { return }
            let continuation = systemContinuation; systemContinuation = nil
            continuation?.resume(returning: session)
        } catch {
            guard systemTaskID == attempt else { return }
            let continuation = systemContinuation; systemContinuation = nil; continuation?.resume(throwing: error)
        }
    }
    private func cancelSystem() {
        systemContinuation?.resume(throwing: CancellationError()); systemContinuation = nil
        if #available(macOS 26.0, *) { activeSession?.cancel() }
        activeSession = nil; reverseConfiguration = nil; systemTaskID = nil
    }
    func handleReadFailure(_ error: Error) {
        guard watching, !capturePaused else { return }
        if error is CancellationError { return }
        if let stopped = error as? ReplyReadStopped { pause(stopped.localizedDescription); return }
        let before = transientReadDisplay.flatMap { status == $0.display ? $0.before : nil } ?? status
        if let pending = error as? ReplyReadPending {
            errors = 0; readRetrySeconds = 1
            if pending.structural {
                let now = clock(); let since = structuralSince ?? now; structuralSince = since
                if now - since >= structureTimeout {
                    readRetrySeconds = 3
                    if readError == nil {
                        readError = "Claude 界面结构已变化，暂时无法读取回复（" + pending.message + "）。请确认 Claude 窗口仍显示对话；Claude 更新后如仍无法读取，请重新按 ⌃⌥E 连接或更新A畜伴侣。自动读取会继续检查。"
                        showPanel()
                    }
                    transientReadDisplay = nil; status = readError ?? ""
                    return
                }
            }
            if readError != nil { return }
            status = "等待 Claude 原文，自动读取会继续检查。" + pending.localizedDescription
        } else {
            errors += 1
            readRetrySeconds = min(60, pow(2, Double(min(errors - 1, 6))))
            if readError != nil { return }
            status = "读取暂时失败，\(Int(readRetrySeconds))秒后重新检查 Claude 页面；自动读取保持开启。"
        }
        transientReadDisplay = (before, status)
    }
    func reportReplyObserved(_ candidate: ReplyCandidate) {
        if lastUsageCandidate != candidate { lastUsageCandidate = candidate; onReplyObserved() }
    }
    func tick() { pipeline?.tick(now: Date().timeIntervalSinceReferenceDate) }
    func retire(_ ids: Set<String>) { retiredRecords.formUnion(ids); pipeline?.retire(ids) }
    func cancelTranslation() { pipeline?.suspend(); cancelSystem(); translating = false; status = "回复翻译已取消，可点击重试。" }
    func retry() { pipeline?.retry() }
    private func pause(_ message: String) {
        transientReadDisplay = nil
        watching = false; cancelTranslation(); polling?.cancel(); polling = nil; status = message
    }
    func clearRecords() {
        transientReadDisplay = nil
        captureGeneration = UUID()
        pipeline?.clear(); cancelSystem(); translating = false; original = ""; chinese = ""
        historyRequestID = nil; historyChoices = []; showHistoryPicker = false
        status = watching ? "本地记录已清除，继续读取 Claude 的新回复。" : "本地记录已清除。"
    }
    func stop(clear: Bool = false) {
        isConnecting = false
        transientReadDisplay = nil
        sessionID = UUID(); watching = false; polling?.cancel(); polling = nil
        errors = 0; readRetrySeconds = 1
        pipeline?.cancel(); pipeline = nil; cancelSystem(); translating = false
        source = nil; lastUsageCandidate = nil; lastCompletedCandidate = nil; historyRequestID = nil; historyChoices = []; showHistoryPicker = false
        completedConversation = ""
        readError = nil; structuralSince = nil
        status = "自动读取已停止。"
        if clear { original = ""; chinese = "" }
    }
}
