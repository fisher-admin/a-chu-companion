import AppKit
import ApplicationServices

@MainActor
final class TargetBridge {
    struct Target {
        let app: NSRunningApplication
        let element: AXUIElement
        let window: AXUIElement
        let value: String?
        let selection: NSRange?
        let conversation: String?
        var name: String { app.localizedName ?? "目标软件" }
    }
    enum Outcome { case inserted, sent, sendUnconfirmed, unconfirmed }
    /// Markers from nspasteboard.org: clipboard managers skip transient items and never store concealed ones.
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static var accessibilityFlags = AccessibilityFlagLedger()
    private static let optInFlags = ["AXManualAccessibility", "AXEnhancedUserInterface"]

    static var trusted: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
    static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    static func selectedRange(_ element: AXUIElement) -> NSRange? {
        guard let raw = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = raw as! AXValue
        guard AXValueGetType(value) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
    static func capture() throws -> Target {
        guard trusted else { throw BridgeError.message("请先在系统设置中允许「A畜伴侣」使用辅助功能，再回到聊天输入框按 ⌃⌥E。") }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw BridgeError.message("请先点击目标软件的聊天输入框，再按 ⌃⌥E。")
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 1)
        // Electron/Chromium expose focused controls after this accessibility opt-in.
        // Only flags we switch on are recorded, so disconnecting restores the app's own setting.
        for flag in optInFlags where accessibilityFlags.shouldEnable(pid: app.processIdentifier, flag: flag,
                                                                      currentlyOn: attribute(axApp, flag) as? Bool == true) {
            AXUIElementSetAttributeValue(axApp, flag as CFString, kCFBooleanTrue)
        }
        guard let element = elementAttribute(axApp, kAXFocusedUIElementAttribute),
              let role = attribute(element, kAXRoleAttribute) as? String,
              [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(role),
              (attribute(element, kAXSubroleAttribute) as? String) != kAXSecureTextFieldSubrole,
              (attribute(element, kAXEnabledAttribute) as? Bool) != false,
              let window = elementAttribute(element, kAXWindowAttribute) ?? elementAttribute(axApp, kAXFocusedWindowAttribute) else {
            throw BridgeError.message("尚未识别到可输入文字的对话框。请点击聊天输入框后再按 ⌃⌥E；仍不支持时可使用「仅翻译」和「复制译文」。")
        }
        return Target(app: app, element: element, window: window,
                      value: attribute(element, kAXValueAttribute) as? String, selection: selectedRange(element), conversation: conversationURL(element))
    }
    static func privateItem(_ text: String) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: transientType)
        item.setData(Data(), forType: concealedType)
        return item
    }
    /// Switches off the Chromium/Electron accessibility opt-ins this companion enabled. Full
    /// accessibility trees slow those apps down and confuse window managers.
    static func releaseAccessibility(pid: pid_t) {
        let flags = accessibilityFlags.release(pid: pid)
        guard !flags.isEmpty, NSRunningApplication(processIdentifier: pid)?.isTerminated == false else { return }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 1)
        for flag in flags { AXUIElementSetAttributeValue(axApp, flag as CFString, kCFBooleanFalse) }
    }
    static func releaseAllAccessibility() { accessibilityFlags.processes.forEach(releaseAccessibility) }
    static func conversationURL(_ element: AXUIElement) -> String? {
        var cursor: AXUIElement? = element
        for _ in 0..<30 {
            guard let item = cursor else { break }
            if attribute(item, kAXRoleAttribute) as? String == "AXWebArea",
               let raw = attribute(item, kAXURLAttribute) {
                let string = (raw as? URL)?.absoluteString ?? (raw as? String) ?? ""
                if var parts = URLComponents(string: string), parts.host == "claude.ai" {
                    parts.query = nil; parts.fragment = nil; return parts.string
                }
            }
            cursor = elementAttribute(item, kAXParentAttribute)
        }
        return nil
    }
    static func refresh(_ target: Target) throws -> Target {
        let current = try validatedConversation(target)
        return Target(app: target.app, element: target.element, window: target.window,
                      value: target.value, selection: target.selection, conversation: current)
    }
    private static func validatedConversation(_ target: Target) throws -> String? {
        guard !target.app.isTerminated else { throw BridgeError.message("目标软件已关闭，请重新选择输入框。") }
        let current = conversationURL(target.element)
        let initialTransition = target.conversation?.hasSuffix("/new") == true && current?.contains("claude.ai/chat/") == true
        guard TargetRefreshPolicy.canReuseTarget(appAlive: !target.app.isTerminated,
                                                 sameConversation: current == target.conversation,
                                                 initialNewConversationTransition: initialTransition) else {
            throw BridgeError.message("Claude 已切换到其他会话。请重新按 ⌃⌥E 连接，防止发错对话。")
        }
        return current
    }
    static func matches(_ target: Target) -> Bool {
        guard !target.app.isTerminated else { return false }
        let app = AXUIElementCreateApplication(target.app.processIdentifier)
        guard let focused = elementAttribute(app, kAXFocusedUIElementAttribute),
              let window = elementAttribute(app, kAXFocusedWindowAttribute) else { return false }
        return DeliveryPolicy.canProceed(
            sameApp: NSWorkspace.shared.frontmostApplication?.processIdentifier == target.app.processIdentifier,
            sameWindow: CFEqual(window, target.window), sameElement: CFEqual(focused, target.element))
    }
    static func key(_ code: CGKeyCode, flags: CGEventFlags = [], pid: pid_t) throws {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else {
            throw BridgeError.message("系统无法创建键盘操作，请重试。")
        }
        down.flags = flags; up.flags = flags
        down.postToPid(pid); up.postToPid(pid)
    }
    static func deliver(_ text: String, to target: Target, autoSend: Bool, commandReturn: Bool) async throws -> Outcome {
        guard trusted, !target.app.isTerminated else { throw BridgeError.message("目标软件已关闭或辅助功能权限不可用。译文已保留。") }
        guard NSApp.isActive || NSApp.keyWindow?.isKeyWindow == true else { throw BridgeError.message("你已切换到其他软件，本次没有自动填入。请重新选择目标输入框。") }
        let existing = attribute(target.element, kAXValueAttribute) as? String
        guard existing == target.value, selectedRange(target.element) == target.selection else {
            throw BridgeError.message("原输入框的内容或光标位置已改变，本次没有填入。请重新选择输入框。")
        }
        try Task.checkCancellation()
        // The companion is a persistent chat panel. Activating the destination
        // restores its input focus without dismissing the visible conversation.
        target.app.activate()
        // Activation may restore focus, but we never force a different control to become focused.
        for _ in 0..<16 {
            if matches(target) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard matches(target), attribute(target.element, kAXValueAttribute) as? String == target.value,
              selectedRange(target.element) == target.selection else {
            throw BridgeError.message("原输入框未恢复焦点，已停止填入。译文已保留，可手动复制。")
        }
        _ = try validatedConversation(target)
        let board = NSPasteboard.general
        let previous = (board.pasteboardItems ?? []).map { item in
            item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                item.data(forType: type).map { (type, $0) }
            }
        }
        board.clearContents()
        guard board.writeObjects([privateItem(text)]) else { throw BridgeError.message("无法写入剪贴板。") }
        let ownedCount = board.changeCount
        defer {
            if DeliveryPolicy.restoreClipboard(ownedCount: ownedCount, currentCount: board.changeCount) {
                board.clearContents()
                let items = previous.map { values in
                    let item = NSPasteboardItem()
                    for (type, data) in values { item.setData(data, forType: type) }
                    return item
                }
                if !items.isEmpty { board.writeObjects(items) }
            }
        }
        try Task.checkCancellation()
        guard matches(target) else { throw BridgeError.message("输入焦点已改变，未粘贴。") }
        _ = try validatedConversation(target)
        try key(9, flags: .maskCommand, pid: target.app.processIdentifier)
        func pasteConfirmed() -> Bool {
            DeliveryPolicy.pasteConfirmed(actual: attribute(target.element, kAXValueAttribute) as? String,
                                         before: target.value, range: target.selection, inserted: text,
                                         webComposer: target.conversation != nil)
        }
        var confirmed = false
        // Keep the clipboard available while the destination processes the paste.
        var stableMatches = 0
        for _ in 0..<600 {
            try await Task.sleep(for: .milliseconds(50))
            guard matches(target) else { throw BridgeError.message("粘贴后焦点改变，未自动发送。请检查原输入框。") }
            stableMatches = pasteConfirmed() ? stableMatches + 1 : 0
            if stableMatches >= 3 { confirmed = true; break }
        }
        guard confirmed, pasteConfirmed() else { return .unconfirmed }
        guard autoSend else { return .inserted }
        try Task.checkCancellation()
        guard matches(target) else { throw BridgeError.message("输入焦点已改变，未自动发送。") }
        _ = try validatedConversation(target)
        try key(36, flags: commandReturn ? .maskCommand : [], pid: target.app.processIdentifier)
        // Claude ignores the key while it is still answering; only an emptied composer proves the send.
        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(50))
            if DeliveryPolicy.sendConfirmed(actual: attribute(target.element, kAXValueAttribute) as? String, inserted: text) { return .sent }
        }
        return .sendUnconfirmed
    }
}
