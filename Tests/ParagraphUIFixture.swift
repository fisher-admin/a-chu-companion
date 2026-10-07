import AppKit
import SwiftUI

@MainActor final class ParagraphFixtureDelegate: NSObject, NSApplicationDelegate {
    let model = TranslatorModel(permissionCheck: { true }, remoteKeyRead: { _ in "" })
    let usage = ClaudeUsageMonitor(enabled: { false })
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        model.engine = "ai"; model.baseURL = "https://simulation.invalid/v1"; model.aiModel = "synthetic"
        model.testTranslation = { "合成外文：" + $0 }
        model.replies.testTranslation = { source in
            if source.contains("Results are in") {
                return "\n这些结果来自 simulation.py 脚本及 results.json 文件。\n\n文件名称保留在同一段中，界面只在到达窗口边缘时自然折行。\n这一段用于核对译文连续显示，所有内容都来自本机模拟。\n"
            }
            return "第一段是真正的独立段落。\n\n第二段也保留原有段落间隔，方便连续阅读。"
        }
        model.replies.watching = true; model.replies.sourceName = "本机段落模拟"
        window = NSWindow(contentRect: NSRect(x: 120, y: 100, width: 610, height: 780),
                          styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "段落排版模拟 · 无真实服务"; window.minSize = NSSize(width: 610, height: 710)
        window.isReleasedWhenClosed = false; window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: MainView(model: model, usage: usage))
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        let original = ClaudeDecoder.codeSegments(.init(role: "AXGroup", label: "Message 2", children: [
            .init(role: "AXHeading", label: "Claude responded: Results"),
            .init(role: "AXGroup", children: [
                .init(role: "AXStaticText", text: "Results are in "),
                .init(role: "AXButton", label: "simulation.py"),
                .init(role: "AXStaticText", text: " and "),
                .init(role: "AXButton", label: "results.json"),
                .init(role: "AXStaticText", text: ". These are synthetic local fixtures.")
            ])
        ]), responseComplete: true)[0].text
        model.replies.ingest(.init(conversation: "synthetic-paragraph-ui", messages: [
            .init(ordinal: 2, author: .assistant, text: original, segment: 1, completed: true),
            .init(ordinal: 2, author: .assistant, text: "A separate paragraph.\n\nAnother separate paragraph.", segment: 2, completed: true)
        ], foundTranscript: true, responseComplete: true), now: 0)
    }
    func applicationWillTerminate(_ notification: Notification) {
        model.replies.stop(); model.bridge.stop(); model.stopPermissionMonitoring(); usage.stop()
    }
}
@main struct ParagraphFixtureApp {
    @MainActor static func main() {
        precondition(CompanionPreferences.simulated, "This fixture only runs with --simulation")
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let delegate = ParagraphFixtureDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
