import AppKit
import ApplicationServices
import OSLog

@MainActor
final class TargetBridge {
    struct ComposerIdentity: Equatable {
        let role: String
        let identifier: String?
        let description: String?
        let placeholder: String?
        var permitsRecovery: Bool { identifier != nil || description != nil || placeholder != nil }
    }
    struct Target {
        let app: NSRunningApplication
        let element: AXUIElement
        let window: AXUIElement
        let value: String?
        let selection: NSRange?
        let conversation: String?
        let identity: ComposerIdentity
        var name: String { app.localizedName ?? "目标软件" }
    }
    enum Outcome { case inserted, sendKeyPressed, unconfirmed }

    nonisolated static func nativeReplySupported(bundle: String?, conversation: String?) -> Bool {
        if bundle == "com.anthropic.claudefordesktop" || bundle == "local.achu.fixture" { return true }
        guard let conversation, let url = URLComponents(string: conversation) else { return false }
        return url.scheme == "https" && url.host == "claude.ai" && url.user == nil && url.password == nil && url.port == nil
    }

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
    private static func identity(_ element: AXUIElement) -> ComposerIdentity {
        func text(_ name: String) -> String? {
            guard let value = attribute(element, name) as? String, !value.isEmpty else { return nil }
            return value
        }
        return .init(role: text(kAXRoleAttribute) ?? "", identifier: text(kAXIdentifierAttribute),
                     description: text(kAXDescriptionAttribute), placeholder: text("AXPlaceholderValue"))
    }
    private static func editable(_ element: AXUIElement) -> Bool {
        [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(attribute(element, kAXRoleAttribute) as? String ?? "") &&
            (attribute(element, kAXSubroleAttribute) as? String) != kAXSecureTextFieldSubrole &&
            (attribute(element, kAXEnabledAttribute) as? Bool) != false
    }
    static func capture() throws -> Target {
        guard trusted else { throw BridgeError.message("请先在系统设置中允许「A畜伴侣」使用辅助功能，再回到聊天输入框按 ⌃⌥E。") }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw BridgeError.message("请先点击目标软件的聊天输入框，再按 ⌃⌥E。")
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 1)
        // Electron/Chromium expose focused controls after this accessibility opt-in.
        AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        guard let element = elementAttribute(axApp, kAXFocusedUIElementAttribute),
              let role = attribute(element, kAXRoleAttribute) as? String,
              [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(role),
              (attribute(element, kAXSubroleAttribute) as? String) != kAXSecureTextFieldSubrole,
              (attribute(element, kAXEnabledAttribute) as? Bool) != false,
              let window = elementAttribute(element, kAXWindowAttribute) ?? elementAttribute(axApp, kAXFocusedWindowAttribute) else {
            throw BridgeError.message("尚未识别到可输入文字的对话框。请点击聊天输入框后再按 ⌃⌥E；仍不支持时可使用「仅翻译」和「复制译文」。")
        }
        return Target(app: app, element: element, window: window,
                      value: attribute(element, kAXValueAttribute) as? String, selection: selectedRange(element),
                      conversation: conversationURL(element), identity: identity(element))
    }
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
        guard trusted, !target.app.isTerminated else { throw BridgeError.message("目标软件已关闭或辅助功能权限不可用。") }
        let app = AXUIElementCreateApplication(target.app.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement],
              windows.contains(where: { CFEqual($0, target.window) }) else {
            throw BridgeError.message("原输入框未能重新确认，请点击 Claude 输入框后再按 ⌃⌥E。")
        }
        AXUIElementSetMessagingTimeout(target.element, 0.2)
        func source(_ focused: AXUIElement?) -> TargetRefreshPolicy.ComposerSource {
            TargetRefreshPolicy.composerSource(
                focusedEditable: focused.map(editable) ?? false,
                focusUnavailable: focused == nil || focused.flatMap { attribute($0, kAXRoleAttribute) as? String } == "AXWebArea",
                companionActive: NSApp.isActive || NSApp.keyWindow?.isKeyWindow == true,
                capturedEditable: editable(target.element))
        }
        let focused = elementAttribute(app, kAXFocusedUIElementAttribute)
        let candidate = source(focused)
        let element: AXUIElement
        switch candidate {
        case .focused: element = focused!
        case .captured:
            // Electron may report only its page while the companion has focus.
            // Retain only the original live composer; delivery still verifies focus.
            guard elementAttribute(app, kAXFocusedWindowAttribute).map({ CFEqual($0, target.window) }) != false else {
                throw BridgeError.message("Claude 窗口已改变，请重新连接输入框。")
            }
            element = target.element
        case .none:
            throw BridgeError.message("原输入框未能重新确认，请点击 Claude 输入框后再按 ⌃⌥E。")
        }
        guard let window = elementAttribute(element, kAXWindowAttribute) ?? elementAttribute(app, kAXFocusedWindowAttribute) else {
            throw BridgeError.message("原输入框所属窗口未能重新确认，请重新连接。")
        }
        AXUIElementSetMessagingTimeout(element, 0.2)
        let current = conversationURL(element)
        let value = attribute(element, kAXValueAttribute) as? String
        let selection = selectedRange(element)
        let sameElement = CFEqual(element, target.element)
        let nextFocused = elementAttribute(app, kAXFocusedUIElementAttribute)
        let stableFocus = candidate == .focused ? nextFocused.map { CFEqual($0, element) } == true :
            source(nextFocused) == .captured &&
            elementAttribute(app, kAXFocusedWindowAttribute).map { CFEqual($0, target.window) } != false
        let stable = stableFocus && editable(element) &&
            conversationURL(element) == current && attribute(element, kAXValueAttribute) as? String == value &&
            selectedRange(element) == selection
        guard TargetRefreshPolicy.canRecapture(appAlive: !target.app.isTerminated,
                                                sameWindow: CFEqual(window, target.window),
                                                sameConversation: current == target.conversation,
                                                sameElement: sameElement,
                                                verifiedIdentity: target.identity.permitsRecovery && identity(element) == target.identity,
                                                knownConversation: current != nil, stable: stable) else {
            throw BridgeError.message("Claude 会话或输入框已改变。请点击原会话输入框后再按 ⌃⌥E，防止发错对话。")
        }
        // Each job receives a new value/caret snapshot. Delivery never migrates
        // that snapshot if the element changes while translation is running.
        return Target(app: target.app, element: element, window: window, value: value, selection: selection,
                      conversation: current, identity: target.identity)
    }
    private static func validatedConversation(_ target: Target) throws -> String? {
        guard !target.app.isTerminated else { throw BridgeError.message("目标软件已关闭，请重新选择输入框。") }
        let current = conversationURL(target.element)
        guard TargetRefreshPolicy.canReuseTarget(appAlive: !target.app.isTerminated,
                                                 sameConversation: current == target.conversation,
                                                 initialNewConversationTransition: false) else {
            throw BridgeError.message("Claude 已切换到其他会话。请重新按 ⌃⌥E 连接，防止发错对话。")
        }
        return current
    }
    static func bindingAfterOwnSend(_ target: Target) async -> Target? {
        guard let initial = target.conversation, OwnSendTransition.newKind(initial) != nil else { return target }
        // Only this immediately post-Return path can consume the new -> saved
        // route transition. An unresolved result never authorizes another send.
        var transition = OwnSendTransition(initial: initial)
        let deadline = Date().addingTimeInterval(2)
        let app = AXUIElementCreateApplication(target.app.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.1)
        while Date() < deadline, !Task.isCancelled, !target.app.isTerminated {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.app.processIdentifier else { return nil }
            if let element = elementAttribute(app, kAXFocusedUIElementAttribute), editable(element),
               let window = elementAttribute(element, kAXWindowAttribute), CFEqual(window, target.window),
               CFEqual(element, target.element) || (target.identity.permitsRecovery && identity(element) == target.identity) {
                AXUIElementSetMessagingTimeout(element, 0.1)
                switch transition.observe(conversationURL(element)) {
                case .pinned(let current):
                    return Target(app: target.app, element: element, window: window,
                                  value: attribute(element, kAXValueAttribute) as? String,
                                  selection: selectedRange(element), conversation: current, identity: target.identity)
                case .invalid: return nil
                case .waiting: break
                }
            }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return nil }
        }
        return nil
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
        guard board.setString(text, forType: .string) else { throw BridgeError.message("无法写入剪贴板。") }
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
        guard confirmed, pasteConfirmed() else {
            let actual = attribute(target.element, kAXValueAttribute) as? String
            let expected = target.value.flatMap { DeliveryPolicy.expectedValue(before: $0, range: target.selection, inserted: text) }
            // Counts and whitespace flags only. Never log the draft or translation.
            let facts: [String: Any] = ["beforeUTF16": target.value?.utf16.count ?? -1,
                                      "actualUTF16": actual?.utf16.count ?? -1,
                                      "expectedUTF16": expected?.utf16.count ?? -1,
                                      "insertedUTF16": text.utf16.count,
                                      "webComposer": target.conversation != nil,
                                      "selectionLocation": target.selection?.location ?? -1,
                                      "selectionLength": target.selection?.length ?? -1,
                                      "beforeOnlyNewlines": target.value.map { !$0.isEmpty && $0.allSatisfy { $0 == "\n" || $0 == "\r" } } ?? false,
                                      "actualEqualsInserted": actual == text,
                                      "actualHasFinalLF": actual?.hasSuffix("\n") ?? false]
            if let data = try? JSONSerialization.data(withJSONObject: facts), let metadata = String(data: data, encoding: .utf8) {
                Logger(subsystem: "local.achu.companion", category: "delivery").notice("Unconfirmed paste metadata: \(metadata, privacy: .public)")
            }
            return .unconfirmed
        }
        guard autoSend else { return .inserted }
        try Task.checkCancellation()
        guard matches(target) else { throw BridgeError.message("输入焦点已改变，未自动发送。") }
        _ = try validatedConversation(target)
        try key(36, flags: commandReturn ? .maskCommand : [], pid: target.app.processIdentifier)
        return .sendKeyPressed
    }
}
