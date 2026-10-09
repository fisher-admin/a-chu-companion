import AppKit
import SwiftUI
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var shared: AppDelegate?
    let model = TranslatorModel()
    let usage = ClaudeUsageMonitor()
    let webUsage = NativeWebUsage()
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var hotKey: EventHotKeyRef?
    var eventHandler: EventHandlerRef?
    var wakeObserver: NSObjectProtocol?
    private var panelActivation = UUID()
    func applicationDidFinishLaunching(_ notification: Notification) {
        KeychainAccess.prepare()
        Self.shared = self
        AppMenus.install()
        // Menu-bar only by default. The opt-in Dock mode makes the companion an
        // ordinary app for assistive and automation tools that list only those.
        NSApp.setActivationPolicy(CompanionPreferences.store.bool(forKey: "showDockIcon") ? .regular : .accessory)
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 610, height: 780),
                          styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "A畜伴侣 · Claude 双向翻译"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        NSApp.applicationIconImage = CompanionIcon.image(size: 256)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 610, height: 710)
        window.delegate = self
        window.contentView = NSHostingView(rootView: MainView(model: model, usage: usage, webUsage: webUsage))
        window.center()
        window.level = .floating
        (window as? NSPanel)?.hidesOnDeactivate = false
        model.replies.showPanel = { [weak self] in self?.window.orderFrontRegardless() }
        model.replies.onReplyAcquired = { [weak self] id, foreign, language in
            self?.model.recordReplyOriginal(id: id, foreign: foreign, language: language)
        }
        model.replies.onReply = { [weak self] id, foreign, chinese, language in
            self?.model.recordReply(id: id, foreign: foreign, chinese: chinese, language: language)
        }
        model.replies.onReplyCompleted = { [weak self] in self?.usage.refreshAfterReply() }
        model.bridge.onUsageAccount = { [weak self] observation in self?.usage.receiveAccount(observation) }
        model.bridge.onUsage = { [weak self] evidence in self?.usage.receive(evidence) }
        webUsage.onBound = { [weak self] binding in self?.usage.follow(channel:.web,binding:binding) }
        webUsage.onReading = { [weak self] binding in self?.usage.beginVisibleRead(binding:binding) }
        webUsage.onEvidence = { [weak self] evidence in self?.usage.receive(evidence) }
        webUsage.onInvalid = { [weak self] observation in self?.usage.receiveAccount(observation) }
        webUsage.onBusyChanged = { [weak self] busy in
            guard let self else { return }
            model.replies.setCapturePaused(busy && model.webQuotaSelection != nil)
        }
        webUsage.canRead = { [weak self] in self?.model.busy == false && self?.model.replies.isConnecting == false }
        model.onClaudeConnection = { [weak self] channel, url in
            guard let self else { return }
            if channel == .web, let selected = model.webQuotaSelection {
                webUsage.bind(selected)
            }
            else { webUsage.unbind(); usage.follow(channel:channel,pageURL:url) }
        }
        model.onNonClaudeConnection = { [weak self] name in
            self?.webUsage.unbind()
            self?.usage.awaitChatEntrance("尚未确认「\(name)」的 Claude 来源；终端请在当前 CLI 输入区按 ⌃⌥E 直接连接")
        }
        model.bridge.onUsageConnection = { [weak self] binding in
            guard let self else { return }
            guard let binding else { webUsage.unbind(); usage.stopFollowing(); usage.awaitChatEntrance(); return }
            let channel: ClaudeUsageChannel = binding.hasPrefix("web-") ? .web : .cli
            usage.follow(channel: channel, binding: binding)
            usage.acquire(channel, binding: binding)
        }
        usage.requestReport = { [weak self] channel, binding, url in
            guard let self else { throw CancellationError() }
            if channel == .web { try await webUsage.read(explicit:false); return }
            if !model.bridge.enabled { model.bridge.start() }
            guard model.bridge.enabled else { throw BridgeError.message(model.bridge.status) }
            try await UsageAcquisition.run("request-cli")
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.model.refreshHealth() }
        }
        // Quota follows the chat entrance actually connected; until then no
        // account is assumed, even if an earlier source was configured.
        usage.awaitChatEntrance()
        usage.startPeriodicRefresh()
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
        let activation = UUID(); panelActivation = activation
        if capture { model.prepareTarget() }
        model.refreshHealth()
        if capture, let selected = model.webQuotaSelection, webUsage.hasSelectedTarget {
            Task { [weak self] in
                guard let self else { return }
                for _ in 0..<30 where model.replies.isConnecting { try? await Task.sleep(for:.milliseconds(100)) }
                try? await self.webUsage.read(explicit:false)
                guard self.panelActivation == activation,
                      [selected.app.processIdentifier,getpid()].contains(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1) else { return }
                self.activatePanel()
            }
            return
        }
        activatePanel()
    }
    private func activatePanel() {
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
        if model.busy { model.cancel() }
        sender.orderOut(nil)
        return false
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show(capture: false); return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        webUsage.unbind(); model.replies.stop(); model.bridge.stop(); model.stopPermissionMonitoring(); usage.stop()
    }
}

@main struct AChuCompanionApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
