import AppKit
import SwiftUI
import Translation

@MainActor
final class TranslatorModel: ObservableObject {
    let replies = ReplyMonitor()
    struct ChatItem: Identifiable {
        let id: String
        let isUser: Bool
        var chinese: String
        var foreign: String
        var language: TranslationLanguage = .english
        /// Claude is still writing, or the in-order Chinese is still catching up.
        var streaming = false
    }
    @Published var history: [ChatItem] = []
    @Published var replyTextSize = ReplyTextSize(rawValue: UserDefaults.standard.integer(forKey: "replyTextSize")) ?? .medium {
        didSet { UserDefaults.standard.set(replyTextSize.rawValue, forKey: "replyTextSize") }
    }
    @Published private(set) var chatRevision = 0
    @Published private(set) var chatScrollTarget = "bottom"
    @Published private(set) var chatScrollAtTop = false
    func recordReplyOriginal(id: String, foreign: String, language: TranslationLanguage) {
        if let i = history.firstIndex(where: { $0.id == id }) {
            if history[i].foreign != foreign { history[i].chinese = "" }
            history[i].foreign = foreign; history[i].language = language
        } else {
            history.append(.init(id: id, isUser: false, chinese: "", foreign: foreign, language: language))
        }
        trimHistory()
        chatScrollTarget = id; chatScrollAtTop = true
        chatRevision += 1
    }
    func recordReply(id: String, foreign: String, chinese: String, language: TranslationLanguage) {
        // A streamed bubble finishes in place; a re-translated older reply moves to the end.
        if let i = history.firstIndex(where: { $0.id == id }), history[i].streaming {
            history[i].foreign = foreign; history[i].chinese = chinese; history[i].language = language; history[i].streaming = false
            trimHistory()
            return
        }
        history.removeAll { $0.id == id }
        history.append(.init(id: id, isUser: false, chinese: chinese, foreign: foreign, language: language))
        trimHistory()
        chatScrollTarget = id; chatScrollAtTop = true
        chatRevision += 1
    }
    /// Updates a streaming bubble without moving the reader's scroll position.
    func recordReplyProgress(id: String, foreign: String, chinese: String, language: TranslationLanguage) {
        if let i = history.firstIndex(where: { $0.id == id }) {
            history[i].foreign = foreign; history[i].chinese = chinese; history[i].language = language; history[i].streaming = true
        } else {
            history.append(.init(id: id, isUser: false, chinese: chinese, foreign: foreign, language: language, streaming: true))
            trimHistory()
            chatScrollTarget = id; chatScrollAtTop = true
            chatRevision += 1
        }
    }
    /// A stopped translation keeps only the verified original, never partial Chinese.
    func markReplyStopped(id: String, foreign: String, language: TranslationLanguage) {
        guard let i = history.firstIndex(where: { $0.id == id }) else { return }
        history[i].foreign = foreign; history[i].language = language
        if history[i].streaming { history[i].chinese = ""; history[i].streaming = false }
    }
    private func trimHistory() {
        let completed = history.filter { !$0.isUser && !$0.chinese.isEmpty && !$0.streaming }
        let removed = Set(completed.dropLast(10).map(\.id))
        history.removeAll { removed.contains($0.id) }
        // Bound drafts and untranslated replies too, without counting them as translations.
        let unfinished = history.filter { $0.isUser || $0.chinese.isEmpty || $0.streaming }
        let extras = Set(unfinished.dropLast(20).map(\.id))
        history.removeAll { extras.contains($0.id) }
    }
    func clearHistory() {
        replies.clearRecords()
        history = []; chatScrollTarget = "bottom"; chatScrollAtTop = false; chatRevision += 1
    }
    func readVisibleReply() {
        guard let target else { return }
        Task { await replies.readVisible(target: target, engine: engine, baseURL: baseURL, model: aiModel, language: language) }
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
    @Published var language = TranslationLanguage(rawValue: UserDefaults.standard.string(forKey: "targetLanguage") ?? "en") ?? .english {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language.rawValue, forKey: "targetLanguage")
            output = ""; configuration = nil
            replies.configure(engine: engine, baseURL: baseURL, model: aiModel, language: language)
            report("已选择\(language.name)，Claude 的回复将译回中文。")
        }
    }
    private var outputLanguage: TranslationLanguage = .english
    @Published var busy = false
    @Published var status = "点击聊天输入框，再按 ⌃⌥E 唤出A畜伴侣。"
    @Published var isError = false
    @Published var targetName = "未选择输入框"
    @Published var hasTarget = false
    @Published private(set) var permission: Bool
    @Published var configuration: TranslationSession.Configuration?
    @Published var showSettings = false
    @Published var engine = UserDefaults.standard.string(forKey: "engine") ?? "apple"
    @Published var baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? ""
    @Published var aiModel = UserDefaults.standard.string(forKey: "aiModel") ?? ""
    @Published var autoSend = UserDefaults.standard.bool(forKey: "autoSend") {
        didSet { UserDefaults.standard.set(autoSend, forKey: "autoSend") }
    }
    @Published var commandReturn = UserDefaults.standard.bool(forKey: "commandReturn") {
        didSet { UserDefaults.standard.set(commandReturn, forKey: "commandReturn") }
    }
    var revealWindow: () -> Void = {}
    private let permissionMonitor: AccessibilityPermissionMonitor
    private var target: TargetBridge.Target?
    private var task: Task<Void, Never>?
    private var appleSession: TranslationSession?
    private var preparationWatchdog: Task<Void, Never>?
    private let applePreparationTimeout: Duration
    private var activeID: UUID?
    private var pending: Job?
    private struct Job {
        let id: UUID
        let text: String
        let insert: Bool
        let target: TargetBridge.Target?
        let send: Bool
        let commandReturn: Bool
        let language: TranslationLanguage
    }

    init(permissionCheck: @escaping @MainActor () -> Bool = { TargetBridge.trusted },
         permissionInterval: UInt64 = 1_000_000_000,
         applePreparationTimeout: Duration = .seconds(120)) {
        self.applePreparationTimeout = applePreparationTimeout
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
        replies.onReplyProgress = { [weak self] id, foreign, chinese, language in
            self?.recordReplyProgress(id: id, foreign: foreign, chinese: chinese, language: language)
        }
        replies.onReply = { [weak self] id, foreign, chinese, language in
            self?.recordReply(id: id, foreign: foreign, chinese: chinese, language: language)
        }
        replies.onReplyStopped = { [weak self] id, foreign, language in
            self?.markReplyStopped(id: id, foreign: foreign, language: language)
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
        do {
            let previous = target
            target = try TargetBridge.capture()
            if let previous, previous.app.processIdentifier != target!.app.processIdentifier {
                TargetBridge.releaseAccessibility(pid: previous.app.processIdentifier)
            }
            targetName = target!.name
            hasTarget = true
            status = "\(language.name)译文将填入 \(targetName) 的原输入框。"
            isError = false
            startReplyReading()
        } catch {
            target = nil; hasTarget = false; targetName = "未选择输入框"
            status = error.localizedDescription; isError = false
        }
    }
    func report(_ message: String, error: Bool = false) { status = message; isError = error }
    /// Stops reading, forgets the input box and switches off accessibility opt-ins in that app.
    func disconnect() {
        if busy { cancel() }
        replies.stop()
        if let target { TargetBridge.releaseAccessibility(pid: target.app.processIdentifier) }
        target = nil; hasTarget = false; targetName = "未选择输入框"
        report("已断开 Claude。点击 Claude 输入框，再按 ⌃⌥E 重新连接。")
    }
    func saveSettings(key: String, replaceKey: Bool) throws {
        if engine == "ai" {
            _ = try AIProtocol.request(text: "测试", baseURL: baseURL, model: aiModel, key: "")
        }
        if replaceKey { try Credentials.save(key.trimmingCharacters(in: .whitespacesAndNewlines)) }
        UserDefaults.standard.set(engine, forKey: "engine")
        UserDefaults.standard.set(baseURL, forKey: "baseURL")
        UserDefaults.standard.set(aiModel, forKey: "aiModel")
        replies.configure(engine: engine, baseURL: baseURL, model: aiModel, language: language)
        report("翻译设置已保存，下一次发送或读取将使用新设置。")
    }
    func begin(insert: Bool) {
        guard !busy else { return }
        do {
            let text = try InputPolicy.validated(input)
            if insert && target == nil { throw BridgeError.message("请先点击目标聊天输入框，再按 ⌃⌥E；也可以先点「仅翻译」。") }
            let destination = insert ? try target.map { try TargetBridge.refresh($0) } : target
            let job = Job(id: UUID(), text: text, insert: insert, target: destination, send: autoSend, commandReturn: commandReturn, language: language)
            let useAI = engine == "ai"
            let key = useAI ? try Credentials.read() : ""
            let base = baseURL; let model = aiModel
            if useAI { _ = try AIProtocol.request(text: "测试", baseURL: base, model: model, key: key, direction: .fromChinese(job.language)) }
            activeID = job.id; pending = job; busy = true; output = ""
            history.append(.init(id: job.id.uuidString, isUser: true, chinese: text, foreign: "", language: job.language))
            trimHistory()
            chatScrollTarget = "bottom"; chatScrollAtTop = false
            chatRevision += 1
            report(engine == "apple" ? "正在使用系统翻译… 首次使用可能需要下载语言包。" : "正在翻译…")
            if useAI {
                // AI output is checked before it can be pasted or sent; anything rejected,
                // slow or rate-limited is translated by the system instead.
                let replies = self.replies
                let translator = FailoverTranslator(preferAI: true, circuit: replies.circuit,
                                                    ai: FailoverTranslator.openAICompatible(baseURL: base, model: model, key: key),
                                                    system: { text, direction in try await replies.systemTranslator.translate(text, direction: direction) })
                var fallback: FallbackReason?
                translator.onFallback = { reason in fallback = reason }
                task = Task {
                    do {
                        let result = try await TextTranslation.run(text, progress: { [weak self] part, total in
                            self?.report("正在翻译为\(job.language.name)… \(part) / \(total) 段")
                        }) { chunk in try await translator.translate(chunk, direction: .fromChinese(job.language)) }
                        try await finish(result, job: job, fallback: fallback)
                    } catch { failed(error, id: job.id) }
                }
            } else {
                preparationWatchdog = Task { [weak self] in
                    do {
                        try await Task.sleep(for: self?.applePreparationTimeout ?? .seconds(120))
                        self?.failed(TranslationChunkError.timedOut, id: job.id)
                    } catch { /* The system callback or cancellation ended this wait. */ }
                }
                if configuration == nil {
                    configuration = .init(source: .init(identifier: "zh-Hans"), target: .init(identifier: job.language.rawValue))
                } else { configuration?.invalidate() }
            }
        } catch { report(error.localizedDescription, error: true) }
    }
    func runApple(_ session: TranslationSession) async {
        guard let job = pending, activeID == job.id, busy else { return }
        preparationWatchdog?.cancel(); preparationWatchdog = nil
        appleSession = session
        do {
            _ = try await TextTranslation.withDeadline { try await session.prepareTranslation(); return "" }
            try Task.checkCancellation()
            let result = try await TextTranslation.run(job.text, progress: { [weak self] part, total in
                self?.report("正在翻译为\(job.language.name)… \(part) / \(total) 段")
            }) { chunk in try await session.translate(chunk).targetText }
            try await finish(result, job: job)
        } catch { failed(error, id: job.id) }
    }
    private func finish(_ translated: String, job: Job, fallback: FallbackReason? = nil) async throws {
        guard activeID == job.id, !Task.isCancelled else { return }
        guard !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BridgeError.message("翻译结果为空，请重试。") }
        try ForeignTextPolicy.validate(translated, incoming: false)
        output = translated; outputLanguage = job.language
        if let index = history.firstIndex(where: { $0.id == job.id.uuidString }) { history[index].foreign = translated }
        chatRevision += 1
        if job.insert, let target = job.target {
            report("翻译完成，正在检查原输入框…")
            let note = fallback.map { " " + $0.message } ?? ""
            let outcome = try await TargetBridge.deliver(translated, to: target, autoSend: job.send,
                                                        commandReturn: job.commandReturn)
            guard activeID == job.id else { return }
            switch outcome {
            case .inserted: report("已填入 \(target.name)，由你确认后发送。" + note)
            case .sent:
                report("已发送到 \(target.name)：输入框已清空。" + note)
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.app.processIdentifier {
                    revealWindow()
                }
            case .sendUnconfirmed:
                report("已按下发送键，但 \(target.name) 的输入框仍保留译文，可能 Claude 仍在回复。请检查后手动发送。", error: true)
                revealWindow()
            case .unconfirmed:
                report("已尝试粘贴，但目标软件未提供可核对的文字。没有自动发送，请检查输入框。", error: true)
                revealWindow()
            }
            // A captured caret is single-use; a later action must capture a fresh target.
            self.target = target
            hasTarget = true
            if input == job.text { input = "" }
        } else { report("翻译完成，可以检查或复制译文。" + (fallback.map { " " + $0.message } ?? "")) }
        busy = false; pending = nil; activeID = nil; appleSession = nil
    }
    func insertResult() {
        guard !busy, !output.isEmpty else { return }
        guard let target else { report("请先回到目标输入框，再按 ⌃⌥E，然后点击「填入译文」。", error: true); return }
        let refreshed: TargetBridge.Target
        do { refreshed = try TargetBridge.refresh(target) }
        catch { report(error.localizedDescription, error: true); return }
        let job = Job(id: UUID(), text: input, insert: true, target: refreshed, send: autoSend, commandReturn: commandReturn, language: outputLanguage)
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
        appleSession = nil; configuration = nil; busy = false
        report("已取消。若已开始粘贴，请检查原输入框。")
    }
    func startReplyReading() {
        guard !busy, let target else { report("请先点击 Claude 输入框，再按 ⌃⌥E。", error: true); return }
        Task { await replies.connect(target: target, engine: engine, baseURL: baseURL, model: aiModel, language: language) }
    }
    func copyOutput() {
        guard !output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        report("译文已复制。")
    }
}
