import AppKit
import ApplicationServices

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
    typealias Outcome = ManualInputDelivery.Outcome

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
    static func location(_ target: Target) -> ManualInputDelivery.Location {
        .init(app: target.app, window: target.window, input: target.element)
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
        let sender = ManualInputDelivery()
        let lease = try sender.bind(location(target))
        return try await sender.deliver(text, to: lease, autoSend: autoSend, commandReturn: commandReturn, current: { true })
    }
}
