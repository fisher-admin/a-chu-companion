import AppKit
import WebKit

@MainActor final class Fixture: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
    var window: NSWindow!
    var web: WKWebView!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); AppMenus.install()
        window = NSWindow(contentRect: NSRect(x: 80, y: 150, width: 720, height: 600), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "A畜伴侣测试输入框 · 仅本机测试"
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "fixture")
        web = WKWebView(frame: window.contentView!.bounds, configuration: configuration)
        web.autoresizingMask = [.width, .height]
        window.contentView = web
        let htmlPath = Bundle.main.path(forResource: "fixture", ofType: "html")!
        let html = try! String(contentsOfFile: htmlPath, encoding: .utf8)
        web.loadHTMLString(html, baseURL: URL(string: "https://claude.ai/chat/achu-local-fixture"))
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard JSONSerialization.isValidJSONObject(message.body), let data = try? JSONSerialization.data(withJSONObject: message.body, options: .prettyPrinted) else { return }
        try? data.write(to: URL(fileURLWithPath: "/private/tmp/achu-fixture.json"), options: .atomic)
    }
}
@main struct Main {
    @MainActor static func main() {
        let app = NSApplication.shared; let delegate = Fixture(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
