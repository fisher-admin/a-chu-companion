import AppKit
import ApplicationServices
import CryptoKit

struct CLIDeliveryOrigin: Equatable {
    let pid: Int32
    let tty: String
    let started: String
    let tag: String
    func valid(for binding: String) -> Bool {
        guard pid > 1, tty.range(of: "^ttys[0-9]{1,6}$", options: .regularExpression) != nil,
              !started.isEmpty, started.count <= 32,
              !started.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              tag.range(of: "^[a-f0-9]{20}$", options: .regularExpression) != nil,
              binding.range(of: "^cli-[a-f0-9]{64}$", options: .regularExpression) != nil else { return false }
        let digest = SHA256.hash(data: Data((binding + "\0" + String(pid) + "\0" + started).utf8))
            .map { String(format: "%02x", $0) }.joined()
        return tag == String(digest.prefix(20))
    }
}

struct CLIProcessRecord {
    var pid: Int32
    var parent: Int32
    var group: Int32
    var foreground: Int32
    var tty: String
    var uid: uid_t
    var started: String
    var command: String
    var isClaude: Bool { URL(fileURLWithPath: command).lastPathComponent.lowercased() == "claude" || command.contains("/claude/versions/") }
    func matches(_ origin: CLIDeliveryOrigin) -> Bool {
        pid == origin.pid && uid == getuid() && tty == origin.tty && started == origin.started &&
            isClaude && group > 0 && foreground == group
    }
    static func read(_ pid: Int32) -> CLIProcessRecord? {
        // Metadata only: no arguments, credentials, transcript or terminal read.
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "pid=,ppid=,pgid=,tpgid=,tty=,uid=,lstart=,comm=", "-p", String(pid)]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(0.3)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.005) }
        if process.isRunning { process.terminate(); return nil }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard data.count <= 4096, let text = String(data: data, encoding: .utf8) else { return nil }
        let fields = text.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 12, let actual = Int32(fields[0]), let parent = Int32(fields[1]),
              let group = Int32(fields[2]), let foreground = Int32(fields[3]), let uid = UInt32(fields[5]) else { return nil }
        return .init(pid: actual, parent: parent, group: group, foreground: foreground, tty: String(fields[4]), uid: uid,
                     started: fields[6...10].joined(separator: " "), command: fields[11...].joined(separator: " "))
    }
}

enum CLIPromptPolicy {
    enum Receipt { case confirmed, collapsed, mismatch }
    struct Prompt {
        let lines: [String]
        var text: String { lines.joined(separator: "\n") }
        var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    static func prompt(screen: String, binding: String, origin: CLIDeliveryOrigin) -> Prompt? {
        guard screen.utf16.count <= 500_000 else { return nil }
        // A suffix only; a tag elsewhere in scrollback never selects a pane.
        let lines = Array(screen.suffix(32_768).components(separatedBy: .newlines).suffix(200))
        let tail = Array(lines.suffix(12))
        let footerPrefix = "A畜伴侣 CLI · " + String(binding.suffix(6))
        let matching = tail.indices.filter {
            let line = tail[$0].trimmingCharacters(in: .whitespaces)
            return line.hasPrefix(footerPrefix + " · ") && line.hasSuffix(" · 输入 " + origin.tag)
        }
        guard matching.count == 1, let footer = matching.first,
              !tail.joined(separator: "\n").contains("-- NORMAL --") else { return nil }
        let following = tail.suffix(from: footer + 1).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard following.count <= 3, following.allSatisfy({ line in
            line == "? for shortcuts" || line.hasPrefix("⏵") || line.hasPrefix("shift+tab") || line == "-- INSERT --"
        }) else { return nil }
        let prompts = tail.prefix(footer).indices.filter { tail[$0].trimmingCharacters(in: .whitespaces).hasPrefix("❯") }
        guard prompts.count == 1, let start = prompts.first else { return nil }
        let first = tail[start].trimmingCharacters(in: .whitespaces)
        var draft = String(first.dropFirst())
        if draft.hasPrefix(" ") { draft.removeFirst() }
        var body = [draft]
        for line in tail[(start + 1)..<footer] {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if !stripped.isEmpty && stripped.allSatisfy({ "─━═".contains($0) }) { break }
            // Continuation gutter belongs to the TUI, not to the translated text.
            body.append(line.hasPrefix("  ") ? String(line.dropFirst(2)) : line)
        }
        while body.count > 1 && body.last?.isEmpty == true { body.removeLast() }
        return .init(lines: body)
    }
    static func receipt(screen: String, binding: String, origin: CLIDeliveryOrigin, text: String) -> Receipt {
        guard let prompt = prompt(screen: screen, binding: binding, origin: origin) else { return .mismatch }
        if prompt.text == text || (!text.contains("\n") && prompt.lines.joined() == text) { return .confirmed }
        if prompt.text.range(of: "^\\[Pasted text #[0-9]+ \\+[0-9]+ lines?\\]$", options: .regularExpression) != nil { return .collapsed }
        return .mismatch
    }
    static func maySend(_ text: String, receipt: Receipt) -> Bool {
        // Multiline/table pastes are filled, but native CLI renderers can hide
        // hard breaks and Enter modes. Exact single-line receipt is required.
        receipt == .confirmed && !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}

@MainActor final class CLITargetBridge {
    struct Surface {
        let app: NSRunningApplication
        let window: AXUIElement
        let focus: AXUIElement
        let element: AXUIElement
        var name: String { app.localizedName ?? "终端" }
    }
    struct Binding {
        let id = UUID()
        let session: String
        let origin: CLIDeliveryOrigin
        let surface: Surface
    }
    enum Outcome { case inserted, sendKeyPressed, collapsed, unconfirmed }
    @MainActor struct Environment {
        var trusted: @MainActor () -> Bool = { TargetBridge.trusted }
        var alive: @MainActor (Surface) -> Bool = { !$0.app.isTerminated }
        var screen: @MainActor (Surface) -> String? = CLITargetBridge.screen
        var live: @MainActor (CLIDeliveryOrigin) -> Bool = { CLIProcessRecord.read($0.pid)?.matches($0) == true }
        var focused: @MainActor (Surface, Bool) -> Bool = CLITargetBridge.focused
        var companionActive: @MainActor () -> Bool = { NSApp.isActive || NSApp.keyWindow?.isKeyWindow == true }
        var activate: @MainActor (Surface) -> Void = { $0.app.activate() }
        var key: @MainActor (CGKeyCode, CGEventFlags, pid_t) throws -> Void = { try TargetBridge.key($0, flags: $1, pid: $2) }
        var board: NSPasteboard = .general
    }
    private let environment: Environment
    init(environment: Environment? = nil) { self.environment = environment ?? .init() }
    static func capture() throws -> Surface {
        guard TargetBridge.trusted, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid() else { throw BridgeError.message("请先点击 Claude Code 终端输入区，再按 ⌃⌥E。") }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.2)
        guard let focus = TargetBridge.elementAttribute(ax, kAXFocusedUIElementAttribute),
              TargetBridge.attribute(focus, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
              let window = TargetBridge.elementAttribute(focus, kAXWindowAttribute) ?? TargetBridge.elementAttribute(ax, kAXFocusedWindowAttribute) else {
            throw BridgeError.message("终端未提供可核对的输入位置，可继续只读和复制。")
        }
        // Only the focused subtree. Never search other windows/tabs/panes.
        var queue = [focus], candidates: [AXUIElement] = [], visited: Set<CFHashCode> = []
        while !queue.isEmpty && visited.count < 64 {
            let item = queue.removeFirst(); guard visited.insert(CFHash(item)).inserted else { continue }
            if TargetBridge.attribute(item, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole { continue }
            if let value = TargetBridge.attribute(item, kAXValueAttribute) as? String, value.contains("A畜伴侣 CLI · ") {
                candidates.append(item); continue
            }
            queue += (TargetBridge.attribute(item, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(32)
        }
        guard candidates.count == 1 else { throw BridgeError.message("当前终端输入区未能唯一确认。请回到 Claude Code 输入区重新连接；仍可只读和复制。") }
        return .init(app: app, window: window, focus: focus, element: candidates[0])
    }
    static func screen(_ surface: Surface) -> String? {
        AXUIElementSetMessagingTimeout(surface.element, 0.1)
        guard let value = TargetBridge.attribute(surface.element, kAXValueAttribute) as? String else { return nil }
        if let raw = TargetBridge.attribute(surface.element, kAXVisibleCharacterRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() {
            let ax = raw as! AXValue; var range = CFRange()
            if AXValueGetType(ax) == .cfRange, AXValueGetValue(ax, .cfRange, &range), range.location >= 0, range.length > 0,
               range.location <= value.utf16.count, range.length <= value.utf16.count - range.location {
                return (value as NSString).substring(with: .init(location: range.location, length: range.length))
            }
        }
        return value
    }
    static func focused(_ surface: Surface, _ frontmost: Bool) -> Bool {
        guard !surface.app.isTerminated else { return false }
        if frontmost && NSWorkspace.shared.frontmostApplication?.processIdentifier != surface.app.processIdentifier { return false }
        let app = AXUIElementCreateApplication(surface.app.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let focus = TargetBridge.elementAttribute(app, kAXFocusedUIElementAttribute), CFEqual(focus, surface.focus),
              let window = TargetBridge.elementAttribute(app, kAXFocusedWindowAttribute), CFEqual(window, surface.window),
              TargetBridge.attribute(surface.element, "AXHidden") as? Bool != true,
              TargetBridge.attribute(surface.element, kAXEnabledAttribute) as? Bool != false else { return false }
        var cursor: AXUIElement? = surface.element
        for _ in 0..<12 {
            guard let item = cursor else { return false }
            if CFEqual(item, focus) { return true }
            cursor = TargetBridge.elementAttribute(item, kAXParentAttribute)
        }
        return false
    }
    func bind(surface: Surface, session: String, origin: CLIDeliveryOrigin) throws -> Binding {
        guard origin.valid(for: session) else { throw BridgeError.message("CLI 输入标记不匹配，仍可只读和复制。") }
        let binding = Binding(session: session, origin: origin, surface: surface)
        try validate(binding, requireEmpty: true, frontmost: false)
        return binding
    }
    func validate(_ binding: Binding, requireEmpty: Bool, frontmost: Bool) throws {
        try validateIdentity(binding, frontmost: frontmost)
        guard let screen = environment.screen(binding.surface),
              let prompt = CLIPromptPolicy.prompt(screen: screen, binding: binding.session, origin: binding.origin),
              !requireEmpty || prompt.isEmpty else {
            throw BridgeError.message("Claude Code 的原会话、输入位置或空输入状态已改变。未自动操作，译文已保留；请清空目标草稿并重新按 ⌃⌥E 连接。")
        }
    }
    private func validateIdentity(_ binding: Binding, frontmost: Bool) throws {
        guard environment.trusted(), environment.alive(binding.surface), environment.focused(binding.surface, frontmost),
              environment.live(binding.origin) else {
            throw BridgeError.message("CLI 的原窗口、焦点或进程已改变，没有自动发送。译文已保留。")
        }
    }
    func deliver(_ text: String, to binding: Binding, autoSend: Bool, current: () -> Bool) async throws -> Outcome {
        let beginning = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !beginning.hasPrefix("!"), !beginning.hasPrefix("/") else {
            throw BridgeError.message("译文以 CLI 命令符号开头，未自动填入。请复制后在终端核对，避免改变输入模式。")
        }
        guard current(), environment.companionActive() else { throw BridgeError.message("连接或当前软件已改变，没有自动填入 CLI。译文已保留。") }
        try validate(binding, requireEmpty: true, frontmost: false)
        try Task.checkCancellation()
        environment.activate(binding.surface)
        for _ in 0..<16 {
            if environment.focused(binding.surface, true) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard current() else { throw BridgeError.message("CLI 来源已切换，未自动粘贴。") }
        try validate(binding, requireEmpty: true, frontmost: true)
        let board = environment.board
        let previous = (board.pasteboardItems ?? []).map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } }
        board.clearContents()
        guard board.setString(text, forType: .string) else { throw BridgeError.message("无法写入剪贴板，译文已保留。") }
        let owned = board.changeCount
        defer {
            if board.changeCount == owned {
                board.clearContents()
                let items = previous.map { values in let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: type) }; return item }
                if !items.isEmpty { board.writeObjects(items) }
            }
        }
        try Task.checkCancellation()
        guard current() else { throw BridgeError.message("CLI 连接已改变，未自动粘贴。") }
        try validate(binding, requireEmpty: true, frontmost: true)
        try environment.key(9, .maskCommand, binding.surface.app.processIdentifier)
        var stable = 0
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(50))
            guard current() else { throw BridgeError.message("CLI 来源在粘贴后改变，没有自动发送；请检查原输入区。") }
            try validateIdentity(binding, frontmost: true)
            // Some native terminal redraws briefly remove the accessible text.
            // Wait inside the same receipt window, without another paste.
            guard let screen = environment.screen(binding.surface) else { stable = 0; continue }
            let receipt = CLIPromptPolicy.receipt(screen: screen, binding: binding.session, origin: binding.origin, text: text)
            if receipt == .collapsed { return .collapsed }
            stable = receipt == .confirmed ? stable + 1 : 0
            if stable < 3 { continue }
            guard autoSend, CLIPromptPolicy.maySend(text, receipt: receipt) else { return .inserted }
            try Task.checkCancellation()
            guard current() else { throw BridgeError.message("CLI 来源已改变，没有自动发送。") }
            try validate(binding, requireEmpty: false, frontmost: true)
            guard let latest = environment.screen(binding.surface),
                  CLIPromptPolicy.receipt(screen: latest, binding: binding.session, origin: binding.origin, text: text) == .confirmed else { return .unconfirmed }
            try Task.checkCancellation()
            guard current(), environment.focused(binding.surface, true), environment.live(binding.origin) else {
                throw BridgeError.message("CLI 在发送前发生变化，未按回车。请检查原输入区。")
            }
            try environment.key(36, [], binding.surface.app.processIdentifier)
            return .sendKeyPressed
        }
        return .unconfirmed
    }
}
