import AppKit
import SwiftUI

@MainActor final class FixtureDelegate: NSObject, NSApplicationDelegate {
    let model = TranslatorModel(permissionCheck: { true }, remoteKeyRead: { _ in "" })
    let usage = ClaudeUsageMonitor(enabled: { false })
    var window: NSWindow!
    var sourceTask: Task<Void, Never>?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: ProcessInfo.processInfo.arguments.contains("--dark") ? .darkAqua : .aqua)
        model.engine = "ai"; model.baseURL = "https://simulation.invalid/v1"; model.aiModel = "synthetic"
        model.testTranslation = { "合成译文：" + $0 }
        model.replies.testTranslation = { text in
            try await Task.sleep(for: .milliseconds(100))
            if ProcessInfo.processInfo.arguments.contains("--tables") {
                return ["Students": "学生人数", "Noise SD": "噪声标准差", "Unadjusted spread": "未调整的离散程度", "Adjusted spread": "调整后的离散程度", "Variance reduction": "方差减少比例", "Synthetic results:": "合成结果：", "No real participants.": "不涉及真实参与者。"][text] ?? text
            }
            if text.contains("Stage one") { return "第一阶段已译成中文；模拟任务仍在继续。" }
            return String(repeating: "这是一段合成中文，用于检查长文滚动、字体和阶段更新，不涉及真实会话。\n", count: 8)
        }
        model.replies.watching = true; model.replies.sourceName = "本机模拟"
        window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 610, height: ProcessInfo.processInfo.arguments.contains("--short") ? 710 : 780), styleMask: [.titled,.closable,.resizable,.fullSizeContentView], backing: .buffered, defer: false)
        window.title = "A畜伴侣模拟验证 · 无真实服务"; window.minSize = NSSize(width: 610, height: 710)
        window.isReleasedWhenClosed = false; window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: MainView(model: model, usage: usage))
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        let long = String(repeating: "Synthetic paragraph for local reading tests.\n\n", count: 200)
        sourceTask = Task {
            if ProcessInfo.processInfo.arguments.contains("--tables") {
                let table = "Synthetic results:\n\n| Students | Noise SD | Unadjusted spread | Adjusted spread | Variance reduction |\n| --- | --- | --- | --- | --- |\n| 60 | 8 | 2.52 | 2.20 | 24% |\n| 60 | 5 | 1.85 | 1.38 | 45% |\n| 120 | 12 | 2.40 | 2.20 | 16% |\n\nNo real participants."
                model.replies.ingest(.init(conversation: "synthetic-ui-table", messages: [.init(ordinal: 2, author: .assistant, text: table)], foundTranscript: true, responseComplete: true), now: 0)
                return
            }
            for second in 0...38 {
                guard model.replies.watching else { return }
                var messages = [ChatMessage(ordinal: 2, author: .assistant, text: "Stage one: preparing the synthetic task.", segment: 1, completed: second >= 12)]
                if second >= 12 { messages.append(.init(ordinal: 2, author: .assistant, text: long + (second >= 22 ? "Additional stable ending.\n" : ""), segment: 2, completed: second >= 36)) }
                model.replies.ingest(.init(conversation: "synthetic-ui", messages: messages, foundTranscript: true, responseComplete: second >= 36), now: Double(second))
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    func applicationWillTerminate(_ notification: Notification) { sourceTask?.cancel(); model.replies.stop(); model.bridge.stop(); model.stopPermissionMonitoring(); usage.stop() }
}
@main struct FixtureApp {
    @MainActor static func main() {
        precondition(CompanionPreferences.simulated, "Fixture requires --simulation")
        CompanionPreferences.store.removePersistentDomain(forName: "local.achu.simulation.preferences")
        let app = NSApplication.shared; let delegate = FixtureDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
