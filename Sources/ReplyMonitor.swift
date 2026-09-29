import AppKit
import SwiftUI
import Translation

@MainActor final class ReplyMonitor: ObservableObject {
    @Published var enabled = UserDefaults.standard.object(forKey: "monitorReplies") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "monitorReplies"); if !enabled { stop() } }
    }
    @Published var watching = false
    @Published var translating = false
    @Published var reverseConfiguration: TranslationSession.Configuration?
    private var systemJob: (candidate: ReplyCandidate, session: UUID, attempt: UUID)?
    @Published var status = "通过A畜伴侣填入 Claude 后，自动等待并翻译新回复。"
    @Published var original = ""
    @Published var chinese = ""
    @Published var sourceName = "Claude"
    var showPanel: () -> Void = {}
    var onReply: (String, String, String) -> Void = { _, _, _ in }
    private var source: ClaudeSource?
    private var tracker: ReplyTracker?
    private var polling: Task<Void, Never>?
    private var translation: Task<Void, Never>?
    private var replyTimeout: Task<Void, Never>?
    private var replyLifecycle = ReplyTranslationLifecycle()
    private var sessionID = UUID()
    private var version: ReplyCandidate?
    private var engine = "apple"
    private var baseURL = ""
    private var model = ""
    private var errors = 0
    private var armedAt = Date()
    var canRetry: Bool {
        guard !translating, !original.isEmpty, let latest = tracker?.latest else { return false }
        return version == latest
    }

    func arm(target: TargetBridge.Target, outbound: String, engine: String, baseURL: String, model: String) async {
        guard enabled else { return }
        stop(clear: true)
        let token = UUID(); sessionID = token
        self.engine = engine; self.baseURL = baseURL; self.model = model
        status = "正在绑定 Claude 对话…"
        do {
            let pid = target.app.processIdentifier
            let bundle = target.app.bundleIdentifier ?? ""
            let element = target.element; let window = target.window; let name = target.name
            let source = try await Task.detached(priority: .utility) {
                try ClaudeSource.bind(pid: pid, bundle: bundle, composer: element, window: window, name: name)
            }.value
            let snapshot = try await Task.detached(priority: .utility) { try source.snapshot() }.value
            guard sessionID == token else { return }
            self.source = source
            tracker = ReplyTracker(baseline: snapshot.messages, outbound: outbound, conversation: snapshot.conversation)
            sourceName = name; armedAt = Date(); errors = 0
            watching = true; status = "等待你发送消息，然后自动翻译 Claude 的新回复。"
        } catch { if sessionID == token { status = "自动读取未启动：" + error.localizedDescription } }
    }
    func followExisting(target: TargetBridge.Target, engine: String, baseURL: String, model: String) async {
        stop(clear: true)
        let token = UUID(); sessionID = token
        self.engine = engine; self.baseURL = baseURL; self.model = model
        sourceName = target.name; status = "正在读取当前 Claude 会话…"; showPanel()
        do {
            let pid = target.app.processIdentifier; let bundle = target.app.bundleIdentifier ?? ""
            let element = target.element; let window = target.window; let name = target.name
            let source = try await Task.detached(priority: .utility) {
                try ClaudeSource.bind(pid: pid, bundle: bundle, composer: element, window: window, name: name)
            }.value
            let snapshot = try await Task.detached(priority: .utility) { try source.snapshot() }.value
            guard sessionID == token else { return }
            guard let index = snapshot.messages.lastIndex(where: { $0.author == .user }) else {
                throw BridgeError.message("当前会话还没有消息。通过A畜伴侣填入并发送后会自动开始读取。")
            }
            self.source = source
            tracker = ReplyTracker(baseline: Array(snapshot.messages.prefix(index)), outbound: snapshot.messages[index].text,
                                   conversation: snapshot.conversation)
            watching = true; armedAt = Date(); errors = 0
            status = "已绑定当前会话，正在检查最新回复…"
            startPolling()
        } catch { if sessionID == token { status = error.localizedDescription } }
    }
    func startPolling() {
        guard watching, let source, polling == nil else { return }
        showPanel()
        let token = sessionID
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.sessionID == token, self.watching else { return }
                do {
                    let snapshot = try await Task.detached(priority: .utility) { try source.snapshot() }.value
                    guard self.sessionID == token, self.watching else { return }
                    let candidate = try self.tracker?.observe(conversation: snapshot.conversation, messages: snapshot.messages,
                                                             now: Date().timeIntervalSinceReferenceDate)
                    self.errors = 0
                    if let current = self.version, self.tracker?.latest != current {
                        self.cancelReplyTranslation(resetSystemSession: true)
                    }
                    if let candidate { self.translate(candidate, token: token) }
                    else if self.tracker?.bound != true && Date().timeIntervalSince(self.armedAt) > 180 {
                        self.pause("三分钟内未识别到发送的消息，已停止等待。请重新唤出A畜伴侣。")
                    } else if self.tracker?.bound == true && self.tracker?.latest == nil {
                        self.status = "已识别你的消息，等待 Claude 回复…"
                    } else if self.tracker?.latest != nil && !self.translating && self.version != self.tracker?.latest {
                        self.status = "Claude 正在回复，等待文字稳定…"
                    }
                } catch {
                    guard self.sessionID == token else { return }
                    self.errors += 1
                    // One transient Chromium accessibility refresh is recoverable.
                    if self.errors >= 2 { self.pause(error.localizedDescription) }
                    else { self.status = "正在重新检查 Claude 页面…" }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    private func translate(_ candidate: ReplyCandidate, token: UUID) {
        cancelReplyTranslation(resetSystemSession: false)
        let attempt = replyLifecycle.begin()
        version = candidate; original = candidate.text; chinese = ""; translating = replyLifecycle.isTranslating
        if engine == "apple" {
            status = "正在准备系统翻译…"
            systemJob = (candidate: candidate, session: token, attempt: attempt)
            armReplyTimeout(candidate, token: token, attempt: attempt, stage: "系统翻译准备", after: .seconds(120))
            if reverseConfiguration == nil {
                reverseConfiguration = .init(source: .init(identifier: "en"), target: .init(identifier: "zh-Hans"))
            } else { reverseConfiguration?.invalidate() }
            return
        }
        status = "正在把 Claude 的回复翻译成中文…"
        armReplyTimeout(candidate, token: token, attempt: attempt, stage: "回复翻译", after: .seconds(120))
        let base = baseURL; let model = self.model
        translation = Task {
            do {
                guard candidate.text.count <= 60_000 else { throw BridgeError.message("回复过长，请复制需要的部分进行翻译。") }
                var translated: [String] = []
                let key = try Credentials.read()
                for chunk in ClaudeDecoder.chunks(candidate.text) {
                    try Task.checkCancellation()
                    let request = try AIProtocol.request(text: chunk, baseURL: base, model: model, key: key, direction: .toChinese)
                    translated.append(try await AITranslator.translate(request))
                }
                commit(translated.joined(separator: "\n\n"), candidate: candidate, token: token, attempt: attempt)
            } catch { translationFailed(error, candidate: candidate, token: token, attempt: attempt) }
        }
    }
    func runSystemReply(_ session: TranslationSession) async {
        guard let job = systemJob, isCurrent(job) else { return }
        do {
            guard job.candidate.text.count <= 60_000 else { throw BridgeError.message("回复过长，请复制需要的部分进行翻译。") }
            armReplyTimeout(job.candidate, token: job.session, attempt: job.attempt, stage: "语言包准备", after: .seconds(120))
            try await session.prepareTranslation()
            guard isCurrent(job) else { return }
            status = "正在把 Claude 的回复翻译成中文…"
            armReplyTimeout(job.candidate, token: job.session, attempt: job.attempt, stage: "回复翻译", after: .seconds(120))
            var translated: [String] = []
            for chunk in ClaudeDecoder.chunks(job.candidate.text) {
                try Task.checkCancellation()
                guard isCurrent(job) else { return }
                translated.append(try await session.translate(chunk).targetText)
                guard isCurrent(job) else { return }
            }
            commit(translated.joined(separator: "\n\n"), candidate: job.candidate, token: job.session, attempt: job.attempt)
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
        replyTimeout = nil
        translation?.cancel(); translation = nil
        let timedOutSystemJob = systemJob?.attempt == attempt
        systemJob = nil
        if timedOutSystemJob { reverseConfiguration = nil }
        translating = replyLifecycle.isTranslating
        if tracker?.latest != candidate {
            status = "Claude 正在回复，等待文字稳定…"
        } else {
            status = "回复翻译超时（\(stage)），可点击重试。"
        }
    }
    private func commit(_ result: String, candidate: ReplyCandidate, token: UUID, attempt: UUID) {
        guard sessionID == token, version == candidate, replyLifecycle.finish(attempt) else { return }
        replyTimeout?.cancel(); replyTimeout = nil
        if systemJob?.attempt == attempt { systemJob = nil }
        translation = nil
        translating = replyLifecycle.isTranslating
        guard tracker?.latest == candidate else {
            status = "Claude 正在回复，等待文字稳定…"
            return
        }
        guard !Task.isCancelled else {
            status = "回复翻译已取消，可点击重试。"
            return
        }
        chinese = result
        onReply(token.uuidString + ":" + String(candidate.ordinal), candidate.text, result)
        status = "中文译文已更新。若 Claude 继续补充，译文会随之更新。"
    }
    private func translationFailed(_ error: Error, candidate: ReplyCandidate, token: UUID, attempt: UUID) {
        guard sessionID == token, version == candidate, replyLifecycle.finish(attempt) else { return }
        replyTimeout?.cancel(); replyTimeout = nil
        if systemJob?.attempt == attempt { systemJob = nil }
        translation = nil
        translating = replyLifecycle.isTranslating
        guard tracker?.latest == candidate else {
            status = "Claude 正在回复，等待文字稳定…"
            return
        }
        if Task.isCancelled || error is CancellationError {
            status = "回复翻译已取消，可点击重试。"
        } else {
            status = "回复翻译失败：" + error.localizedDescription + "；可点击重试。"
        }
    }
    private func cancelReplyTranslation(resetSystemSession: Bool) {
        let hadSystemJob = systemJob != nil
        replyTimeout?.cancel(); replyTimeout = nil
        translation?.cancel(); translation = nil
        if let attempt = replyLifecycle.activeID { _ = replyLifecycle.cancel(attempt) }
        systemJob = nil
        translating = replyLifecycle.isTranslating
        if resetSystemSession && hadSystemJob { reverseConfiguration = nil }
    }
    func cancelTranslation() {
        guard translating else { return }
        cancelReplyTranslation(resetSystemSession: true)
        status = "回复翻译已取消，可点击重试。"
    }
    func retry() {
        guard canRetry, let candidate = tracker?.latest else { return }
        translate(candidate, token: sessionID)
    }
    private func pause(_ message: String) {
        watching = false; cancelReplyTranslation(resetSystemSession: true); polling?.cancel(); polling = nil
        reverseConfiguration = nil
        status = message
    }
    func stop(clear: Bool = false) {
        sessionID = UUID(); watching = false
        polling?.cancel(); polling = nil; cancelReplyTranslation(resetSystemSession: true)
        source = nil; tracker = nil; version = nil
        reverseConfiguration = nil
        status = "自动读取已停止。"
        if clear { original = ""; chinese = "" }
    }
}
