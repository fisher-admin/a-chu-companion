import AppKit
import ApplicationServices

/// A physical shortcut pins the user's chosen input. Reading identities and
/// rendered contents are deliberately absent from this sending interface.
@MainActor final class ManualInputDelivery {
    struct Location {
        let app: NSRunningApplication
        let window: AXUIElement
        let input: AXUIElement
        var name: String { app.localizedName ?? "目标软件" }
    }
    struct Lease {
        let id: UUID
        let location: Location
        init(id: UUID = UUID(), location: Location) { self.id = id; self.location = location }
    }
    enum Outcome: Equatable { case inserted, sendKeyPressed, submitFailed(String) }
    /// nspasteboard.org markers: clipboard managers skip transient items and never store concealed ones.
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static func privateItem(_ text: String) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: transientType)
        item.setData(Data(), forType: concealedType)
        return item
    }
    struct Environment {
        var trusted: @MainActor () -> Bool = { TargetBridge.trusted }
        var available: @MainActor (Location) -> Bool = ManualInputDelivery.available
        var restore: @MainActor (Location) -> Void = ManualInputDelivery.restore
        var focused: @MainActor (Location) -> Bool = ManualInputDelivery.focused
        var key: @MainActor (CGKeyCode, CGEventFlags, pid_t) throws -> Void = { try TargetBridge.key($0, flags: $1, pid: $2) }
        var board: NSPasteboard = .general
    }
    private let environment: Environment
    init(environment: Environment = .init()) { self.environment = environment }
    static func available(_ location: Location) -> Bool {
        guard !location.app.isTerminated else { return false }
        let app = AXUIElementCreateApplication(location.app.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let windows = TargetBridge.attribute(app, kAXWindowsAttribute) as? [AXUIElement],
              windows.contains(where: { CFEqual($0, location.window) }),
              TargetBridge.attribute(location.input, kAXRoleAttribute) != nil else { return false }
        let window = TargetBridge.elementAttribute(location.input, kAXWindowAttribute)
        return window.map { CFEqual($0, location.window) } ?? true
    }
    static func restore(_ location: Location) {
        location.app.activate()
        AXUIElementPerformAction(location.window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(location.window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(location.window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(location.input, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }
    static func focused(_ location: Location) -> Bool {
        guard !location.app.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == location.app.processIdentifier else { return false }
        let app = AXUIElementCreateApplication(location.app.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let window = TargetBridge.elementAttribute(app, kAXFocusedWindowAttribute), CFEqual(window, location.window),
              let input = TargetBridge.elementAttribute(app, kAXFocusedUIElementAttribute), CFEqual(input, location.input) else { return false }
        return true
    }
    func bind(_ location: Location) throws -> Lease {
        try validate(location)
        return Lease(location: location)
    }
    func validate(_ location: Location) throws {
        guard environment.trusted() else { throw BridgeError.message("辅助功能权限当前不可用，译文已保留。") }
        guard environment.available(location) else { throw BridgeError.message("你选定的窗口或输入位置已关闭或失效，请在需要的输入区按 ⌃⌥E 重新连接。") }
    }
    func deliver(_ text: String, to lease: Lease, autoSend: Bool, commandReturn: Bool = false,
                 current: () -> Bool) async throws -> Outcome {
        try Task.checkCancellation()
        guard current() else { throw BridgeError.message("输入连接已更换，旧译文已保留，没有填入。") }
        try validate(lease.location)
        environment.restore(lease.location)
        for _ in 0..<16 {
            try Task.checkCancellation()
            guard current() else { throw BridgeError.message("输入连接已更换，没有填入旧译文。") }
            if environment.focused(lease.location) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try validate(lease.location)
        guard environment.focused(lease.location) else { throw BridgeError.message("无法恢复你选定的输入位置，译文已保留。请在原输入区重新连接。") }
        let board = environment.board
        let previous = (board.pasteboardItems ?? []).map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } }
        board.clearContents()
        guard board.writeObjects([Self.privateItem(text)]) else { throw BridgeError.message("无法写入剪贴板，译文已保留。") }
        let owned = board.changeCount
        defer {
            if board.changeCount == owned {
                board.clearContents()
                let items = previous.map { values in let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: type) }; return item }
                if !items.isEmpty { board.writeObjects(items) }
            }
        }
        try Task.checkCancellation()
        guard current(), environment.focused(lease.location) else { throw BridgeError.message("输入连接或焦点已改变，没有粘贴。") }
        try environment.key(9, .maskCommand, lease.location.app.processIdentifier)
        // Give the target's normal paste handler a brief turn. Never read the
        // text back, interpret its layout, or retry a paste automatically.
        do { try await Task.sleep(for: .milliseconds(200)); try Task.checkCancellation() }
        catch { return .submitFailed("已发送粘贴按键，随后操作已取消；请查看原输入区，不要重复填入。") }
        guard autoSend else { return .inserted }
        guard current(), environment.trusted(), environment.available(lease.location), environment.focused(lease.location) else {
            return .submitFailed("已发送粘贴按键，但输入位置随后变化，未按回车；请查看原输入区，不要重复填入。")
        }
        do { try environment.key(36, commandReturn ? .maskCommand : [], lease.location.app.processIdentifier) }
        catch { return .submitFailed("已发送粘贴按键，但回车失败：" + error.localizedDescription + "；请在原输入区发送，不要重复填入。") }
        return .sendKeyPressed
    }
}
