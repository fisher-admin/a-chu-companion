import AppKit
import SwiftUI
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var shared: AppDelegate?
    let model = TranslatorModel()
    let usage = ClaudeUsageMonitor()
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var hotKey: EventHotKeyRef?
    var eventHandler: EventHandlerRef?
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        AppMenus.install()
        NSApp.setActivationPolicy(.accessory)
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 670, height: 780),
                          styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "A畜伴侣 · Claude 双向翻译"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        NSApp.applicationIconImage = CompanionIcon.image(size: 256)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 630, height: 710)
        window.delegate = self
        window.contentView = NSHostingView(rootView: MainView(model: model, usage: usage))
        window.center()
        window.level = .floating
        (window as? NSPanel)?.hidesOnDeactivate = false
        model.replies.showPanel = { [weak self] in self?.window.orderFrontRegardless() }
        model.replies.onReply = { [weak self] id, foreign, chinese, language in
            self?.model.recordReply(id: id, foreign: foreign, chinese: chinese, language: language)
        }
        model.replies.onReplyObserved = { [weak self] in self?.usage.refresh() }
        usage.refresh()
        model.hideWindow = { [weak self] in self?.window.orderOut(nil) }
        model.revealWindow = { [weak self] in self?.show(capture: false) }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = CompanionIcon.image(size: 20, template: true)
        statusItem.button?.title = ""
        statusItem.button?.toolTip = "A畜伴侣"
        let menu = NSMenu()
        let open = NSMenuItem(title: "打开A畜伴侣    ⌃⌥E", action: #selector(openPanel), keyEquivalent: "")
        open.target = self; menu.addItem(open)
        let settings = NSMenuItem(title: "翻译设置…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self; menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出A畜伴侣", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self; menu.addItem(quit)
        statusItem.menu = menu
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in AppDelegate.shared?.togglePanel() }
            return noErr
        }, 1, &spec, nil, &eventHandler)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_E), UInt32(controlKey | optionKey),
                                        EventHotKeyID(signature: 0x41434855, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        show(capture: false)
        if status != noErr { model.report("⌃⌥E 已被其他软件占用，请使用菜单栏打开A畜伴侣。", error: true) }
    }
    func show(capture: Bool) {
        if capture { model.prepareTarget() }
        model.refreshPermission()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, let view = Self.findDraft(in: self.window.contentView) else { return }
            self.window.makeFirstResponder(view)
        }
    }
    static func findDraft(in view: NSView?) -> DraftTextView? {
        guard let view else { return nil }
        if let draft = view as? DraftTextView { return draft }
        for child in view.subviews { if let found = findDraft(in: child) { return found } }
        return nil
    }
    func togglePanel() {
        if window.isVisible && NSApp.isActive {
            if model.busy { model.cancel() }
            window.orderOut(nil)
        } else { show(capture: true) }
    }
    @objc func openPanel() { show(capture: true) }
    @objc func openSettings() { show(capture: false); model.showSettings = true }
    @objc func quitApp() { model.cancel(); NSApp.terminate(nil) }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.replies.stop(clear: true)
        if model.busy { model.cancel() }
        sender.orderOut(nil)
        return false
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show(capture: false); return true
    }
    func applicationWillTerminate(_ notification: Notification) { model.stopPermissionMonitoring(); usage.stop() }
}

@main struct AChuCompanionApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
