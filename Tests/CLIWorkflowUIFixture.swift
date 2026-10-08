import AppKit
import SwiftUI
import ApplicationServices

@MainActor final class CLIWorkflowFixture: NSObject, NSApplicationDelegate {
    let model = TranslatorModel(permissionCheck: { true }, remoteKeyRead: { _ in "synthetic-workflow" })
    let usage = ClaudeUsageMonitor()
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppMenus.install()
        model.engine = "gemini"; model.language = .english
        model.replyTextSize = .medium
        model.testTranslation = { _ in "Hello." }
        model.cliEntryRequest = { _ in }
        model.input = "你好"
        model.bridge.start()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 850), styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false)
        window.title = "A畜伴侣 CLI 流程模拟"
        window.contentView = NSHostingView(rootView: VStack(spacing: 0) {
            Button("模拟终端连接快捷键") {
                let own = NSRunningApplication.current, element = AXUIElementCreateApplication(own.processIdentifier)
                self.model.connectCapturedTarget(.init(app: own, element: element, window: element, value: nil, selection: nil, conversation: nil,
                                                  identity: .init(role: "AXGroup", identifier: nil, description: nil, placeholder: nil)))
            }.padding(6)
            MainView(model: model, usage: usage)
        })
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        Task {
            let path = model.bridge.connectionPath
            let root = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            _ = try? await Task.detached {
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                process.currentDirectoryURL = root
                process.arguments = ["Tests/ConnectionRoutingClient.py",path]
                try process.run(); process.waitUntilExit()
            }.value
        }
    }
    func applicationWillTerminate(_ notification: Notification) { model.bridge.stop(); model.cancel(); model.stopPermissionMonitoring(); usage.stop() }
}

@main struct CLIWorkflowFixtureApp {
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let delegate = CLIWorkflowFixture(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
