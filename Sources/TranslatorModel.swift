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
        var english: String
    }
    @Published var history: [ChatItem] = []
    func recordReply(id: String, english: String, chinese: String) {
        if let i = history.firstIndex(where: { $0.id == id }) { history[i].english = english; history[i].chinese = chinese }
        else { history.append(.init(id: id, isUser: false, chinese: chinese, english: english)) }
        if history.count > 40 { history.removeFirst(history.count - 40) }
    }
    func clearHistory() { history = []; input = ""; output = ""; replies.stop(clear: true) }
    @Published var input = "" { didSet { if input != oldValue && !busy { output = "" } } }
    @Published var output = ""
    @Published var busy = false
    @Published var status = "点击聊天输入框，再按 ⌃⌥E 唤出A畜伴侣。"
    @Published var isError = false
    @Published var targetName = "未选择输入框"
    @Published var hasTarget = false
    @Published var permission = TargetBridge.trusted
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
    var hideWindow: () -> Void = {}
    var revealWindow: () -> Void = {}
    private var target: TargetBridge.Target?
    private var task: Task<Void, Never>?
    private var appleSession: TranslationSession?
    private var activeID: UUID?
    private var pending: Job?
    private struct Job {
        let id: UUID
        let text: String
        let insert: Bool
        let target: TargetBridge.Target?
        let send: Bool
        let commandReturn: Bool
    }

    func prepareTarget() {
        guard !busy else { return }
        permission = TargetBridge.trusted
        do {
            target = try TargetBridge.capture()
            targetName = target!.name
            hasTarget = true
            status = "英文将填入 \(targetName) 的原输入框。"
            isError = false
        } catch {
            target = nil; hasTarget = false; targetName = "未选择输入框"
            status = error.localizedDescription; isError = false
        }
    }
    func report(_ message: String, error: Bool = false) { status = message; isError = error }
    func saveSettings(key: String, replaceKey: Bool) throws {
        if engine == "ai" {
            _ = try AIProtocol.request(text: "测试", baseURL: baseURL, model: aiModel, key: "")
        }
        if replaceKey { try Credentials.save(key.trimmingCharacters(in: .whitespacesAndNewlines)) }
        UserDefaults.standard.set(engine, forKey: "engine")
        UserDefaults.standard.set(baseURL, forKey: "baseURL")
        UserDefaults.standard.set(aiModel, forKey: "aiModel")
        report("翻译设置已保存。")
    }
    func begin(insert: Bool) {
        guard !busy else { return }
        do {
            let text = try InputPolicy.validated(input)
            if insert && target == nil { throw BridgeError.message("请先点击目标聊天输入框，再按 ⌃⌥E；也可以先点「仅翻译」。") }
            let destination = insert ? try target.map { try TargetBridge.refresh($0) } : target
            let job = Job(id: UUID(), text: text, insert: insert, target: destination, send: autoSend, commandReturn: commandReturn)
            var request: URLRequest?
            if engine == "ai" { request = try AIProtocol.request(text: text, baseURL: baseURL, model: aiModel, key: Credentials.read()) }
            activeID = job.id; pending = job; busy = true; output = ""
            history.append(.init(id: job.id.uuidString, isUser: true, chinese: text, english: ""))
            if history.count > 40 { history.removeFirst(history.count - 40) }
            report(engine == "apple" ? "正在使用系统翻译… 首次使用可能需要下载语言包。" : "正在翻译…")
            if let request {
                task = Task {
                    do { try await finish(try await AITranslator.translate(request), job: job) }
                    catch { failed(error, id: job.id) }
                }
            } else {
                if configuration == nil {
                    configuration = .init(source: .init(identifier: "zh-Hans"), target: .init(identifier: "en"))
                } else { configuration?.invalidate() }
            }
        } catch { report(error.localizedDescription, error: true) }
    }
    func runApple(_ session: TranslationSession) async {
        guard let job = pending, activeID == job.id, busy else { return }
        appleSession = session
        do {
            try await session.prepareTranslation()
            try Task.checkCancellation()
            let result = try await session.translate(job.text)
            try await finish(result.targetText, job: job)
        } catch { failed(error, id: job.id) }
    }
    private func finish(_ translated: String, job: Job) async throws {
        guard activeID == job.id, !Task.isCancelled else { return }
        guard !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BridgeError.message("翻译结果为空，请重试。") }
        output = translated
        if let index = history.firstIndex(where: { $0.id == job.id.uuidString }) { history[index].english = translated }
        if job.insert, let target = job.target {
            report("翻译完成，正在检查原输入框…")
            await replies.arm(target: target, outbound: translated, engine: engine, baseURL: baseURL, model: aiModel)
            guard activeID == job.id, !Task.isCancelled else { return }
            let outcome = try await TargetBridge.deliver(translated, to: target, autoSend: job.send,
                                                        commandReturn: job.commandReturn, hide: hideWindow)
            guard activeID == job.id else { return }
            switch outcome {
            case .inserted: report("已填入 \(target.name)，由你确认后发送。")
            case .sendKeyPressed: report("已填入 \(target.name) 并按下发送快捷键，请以目标软件的显示为准。")
            case .unconfirmed:
                report("已尝试粘贴，但目标软件未提供可核对的文字。没有自动发送，请检查输入框。", error: true)
                revealWindow()
            }
            replies.startPolling()
            // A captured caret is single-use; a later action must capture a fresh target.
            self.target = target
            hasTarget = true
            if input == job.text { input = "" }
        } else { report("翻译完成，可以检查或复制英文。") }
        busy = false; pending = nil; activeID = nil; appleSession = nil
    }
    func insertResult() {
        guard !busy, !output.isEmpty else { return }
        guard let target else { report("请先回到目标输入框，再按 ⌃⌥E，然后点击「填入英文」。", error: true); return }
        let refreshed: TargetBridge.Target
        do { refreshed = try TargetBridge.refresh(target) }
        catch { report(error.localizedDescription, error: true); return }
        let job = Job(id: UUID(), text: input, insert: true, target: refreshed, send: autoSend, commandReturn: commandReturn)
        let result = output
        activeID = job.id; busy = true
        task = Task {
            do { try await finish(result, job: job) }
            catch { failed(error, id: job.id) }
        }
    }
    private func failed(_ error: Error, id: UUID) {
        guard activeID == id else { return }
        busy = false; pending = nil; activeID = nil; appleSession = nil
        replies.stop()
        if error is CancellationError { report("已取消，中文内容已保留。") }
        else {
            report(error.localizedDescription + (output.isEmpty ? "" : " 英文已保留，可复制使用。"), error: true)
            if !NSApp.isActive { revealWindow() }
        }
    }
    func cancel() {
        replies.stop()
        activeID = nil; pending = nil; task?.cancel(); task = nil
        if #available(macOS 26.0, *) { appleSession?.cancel() }
        appleSession = nil; configuration = nil; busy = false
        report("已取消。若已开始粘贴，请检查原输入框。")
    }
    func readCurrentReply() {
        guard !busy, let target else { report("请先点击 Claude 输入框，再按 ⌃⌥E。", error: true); return }
        Task { await replies.followExisting(target: target, engine: engine, baseURL: baseURL, model: aiModel) }
    }
    func copyOutput() {
        guard !output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        report("英文已复制。")
    }
}
