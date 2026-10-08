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
    static func terminalLines(_ screen: String) -> [String] {
        var lines = screen.suffix(32_768).components(separatedBy: .newlines)
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        return Array(lines.suffix(200))
    }
    struct Footer {
        let lines: [String]
        let start: Int
        let end: Int
    }
    static func footer(screen: String, binding: String, origin: CLIDeliveryOrigin, requireInputHints: Bool = true) -> Footer? {
        guard screen.utf16.count <= 500_000 else { return nil }
        let lines = terminalLines(screen)
        let prefix = "A畜伴侣 CLI · " + String(binding.suffix(6)) + " · "
        // Join only contiguous footer fragments, preserving every character.
        // Never hunt for the token in old scrollback or remove arbitrary text.
        let markers = lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("A畜伴侣 CLI · ") }
        guard markers.count == 1, let start = markers.first else { return nil }
        var joined = ""
        for end in start..<min(lines.count, start + 4) {
            joined += lines[end].trimmingCharacters(in: .whitespaces)
            if joined.hasPrefix(prefix), joined.hasSuffix(" · 输入 " + origin.tag) {
                let following = lines.suffix(from: end + 1).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if requireInputHints && !(following.count <= 3 && following.allSatisfy(isHint)) { return nil }
                return .init(lines: lines, start: start, end: end)
            }
        }
        return nil
    }
    private static func isHint(_ line: String) -> Bool {
        line == "? for shortcuts" || line == "-- INSERT --" ||
        line.range(of: #"^(?:⏵{1,2} .+ \(shift\+tab to cycle\)|shift\+tab to cycle|ctrl\+g to edit in (?:editor|.+))$"#, options: .regularExpression) != nil
    }
    static func diagnostic(_ screen: String) -> String {
        let tail = terminalLines(screen)
        let footerCount = tail.filter { $0.contains("A畜伴侣 CLI · ") }.count
        let inputCount = tail.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("❯") }.count
        return "（末尾标记 \(footerCount)，输入标识 \(inputCount)）"
    }
    static func prompt(screen: String, binding: String, origin: CLIDeliveryOrigin) -> Prompt? {
        guard let footer = footer(screen: screen, binding: binding, origin: origin),
              !footer.lines.joined(separator: "\n").contains("-- NORMAL --"),
              CLIInteractionPolicy.notice(screen: screen) == nil else { return nil }
        let tail = footer.lines
        var end = footer.start
        if end > 0, separator(tail[end - 1]) { end -= 1 }
        guard let latest = tail.prefix(end).lastIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("❯") }) else { return nil }
        let boundary = tail.prefix(latest).lastIndex(where: separator).map { $0 + 1 } ?? 0
        let prompts = (boundary..<end).filter { tail[$0].trimmingCharacters(in: .whitespaces).hasPrefix("❯") }
        guard prompts.count == 1, let start = prompts.first else { return nil }
        // Preserve payload trailing whitespace. Only the known prompt gutter
        // may be removed; receipt comparison does not trim or normalize text.
        let first = String(tail[start].drop(while: { $0 == " " }))
        var draft = String(first.dropFirst())
        if draft.hasPrefix(" ") { draft.removeFirst() }
        var body = [draft]
        for line in tail[(start + 1)..<end] {
            body.append(line.hasPrefix("  ") ? String(line.dropFirst(2)) : line)
        }
        while body.count > 1 && body.last?.isEmpty == true { body.removeLast() }
        return .init(lines: body)
    }
    private static func separator(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        return stripped.count >= 3 && stripped.allSatisfy { "─━═".contains($0) }
    }
    static func failureHint(screen: String?, binding: String, origin: CLIDeliveryOrigin) -> String {
        guard let screen else { return "终端暂未提供文字" }
        if CLIInteractionPolicy.notice(screen: screen) != nil { return "CLI 正在显示运行或选择提示" }
        guard footer(screen: screen, binding: binding, origin: origin) != nil else { return "底部会话标记或提示行未匹配" }
        guard prompt(screen: screen, binding: binding, origin: origin) != nil else { return "输入布局或输入标识未匹配" }
        return "输入全文与译文不一致"
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
    private(set) var receiptHint = ""
    private var pasteAttempt: (binding: UUID, translation: String, prompt: String)?
    private static func fingerprint(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
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
        return try captureSurface(app: app, focus: focus, window: window)
    }
    static func captureSurface(app: NSRunningApplication, focus: AXUIElement, window: AXUIElement) throws -> Surface {
        // Only the focused subtree. Never search other windows/tabs/panes.
        var queue = [focus], candidates: [AXUIElement] = [], textAreas: [AXUIElement] = [], visited: Set<CFHashCode> = []
        while !queue.isEmpty && visited.count < 64 {
            let item = queue.removeFirst(); guard visited.insert(CFHash(item)).inserted else { continue }
            if TargetBridge.attribute(item, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole { continue }
            if let value = TargetBridge.attribute(item, kAXValueAttribute) as? String {
                if value.contains("A畜伴侣 CLI · ") { candidates.append(item); continue }
                if [kAXTextAreaRole, kAXTextFieldRole].contains(TargetBridge.attribute(item, kAXRoleAttribute) as? String ?? "") {
                    textAreas.append(item)
                }
            }
            queue += (TargetBridge.attribute(item, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(32)
        }
        // A first status-line report may arrive only after configuring the
        // adapter. Capture one text surface now; bind/deliver still require the
        // exact current footer and process identity before any input operation.
        let surfaces = candidates.isEmpty ? textAreas : candidates
        guard surfaces.count == 1 else { throw BridgeError.message("当前终端未提供唯一的文字输入表面（文字区 \(textAreas.count)，标记区 \(candidates.count)）。请点中 Claude Code 输入区再按 ⌃⌥E；未自动选择其他窗口。") }
        return .init(app: app, window: window, focus: focus, element: surfaces[0])
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
        try validate(binding, frontmost: false)
        return binding
    }
    func validate(_ binding: Binding, frontmost: Bool) throws {
        try validateIdentity(binding, frontmost: frontmost)
        guard let screen = environment.screen(binding.surface) else { throw BridgeError.message("当前终端暂未提供输入区文字，尚未绑定自动填入。") }
        guard CLIPromptPolicy.prompt(screen: screen, binding: binding.session, origin: binding.origin) != nil else {
            throw BridgeError.message("当前 CLI 输入区与底部输入标记尚未匹配" + CLIPromptPolicy.diagnostic(screen) + "。等待同一窗口刷新，无需选择会话。")
        }
        // The rendered text can be a suggestion, not the editable draft.
        // Let CLI's normal paste dismiss it; verify exact receipt afterward.
    }
    func passiveScreen(_ binding: Binding) -> (String?, Bool) {
        // No activation, paste, key, or search outside the bound surface.
        guard (try? validateIdentity(binding, frontmost: false)) != nil,
              let screen = environment.screen(binding.surface) else { return (nil, false) }
        let matched = CLIPromptPolicy.footer(screen: screen, binding: binding.session, origin: binding.origin, requireInputHints: false) != nil
        return (screen, matched)
    }
    private func validateIdentity(_ binding: Binding, frontmost: Bool) throws {
        guard environment.trusted() else { throw BridgeError.message("辅助功能权限当前不可用，未自动填入 CLI。") }
        guard environment.alive(binding.surface) else { throw BridgeError.message("原终端已关闭，未自动填入 CLI。") }
        guard environment.focused(binding.surface, frontmost) else { throw BridgeError.message("原终端窗口或输入焦点尚未核对，未自动填入 CLI；请在原输入区按 ⌃⌥E。") }
        guard environment.live(binding.origin) else { throw BridgeError.message("CLI 原进程已退出、挂起或改变，未自动发送。译文已保留。") }
    }
    func deliver(_ text: String, to binding: Binding, autoSend: Bool, current: () -> Bool) async throws -> Outcome {
        receiptHint = ""
        let beginning = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !beginning.hasPrefix("!"), !beginning.hasPrefix("/") else {
            throw BridgeError.message("译文以 CLI 命令符号开头，未自动填入。请复制后在终端核对，避免改变输入模式。")
        }
        guard current(), environment.companionActive() else { throw BridgeError.message("连接或当前软件已改变，没有自动填入 CLI。译文已保留。") }
        try validate(binding, frontmost: false)
        try Task.checkCancellation()
        environment.activate(binding.surface)
        for _ in 0..<16 {
            if environment.focused(binding.surface, true) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard current() else { throw BridgeError.message("CLI 来源已切换，未自动粘贴。") }
        try validate(binding, frontmost: true)
        let translationFingerprint = Self.fingerprint(text)
        if let previous = pasteAttempt, previous.binding == binding.id, previous.translation == translationFingerprint,
           let screen = environment.screen(binding.surface),
           let prompt = CLIPromptPolicy.prompt(screen: screen, binding: binding.session, origin: binding.origin),
           previous.prompt == Self.fingerprint(prompt.text) {
            throw BridgeError.message("此译文已尝试填入，原 CLI 内容尚未改变；未重复粘贴。请在终端核对后发送。")
        }
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
        try validate(binding, frontmost: true)
        try environment.key(9, .maskCommand, binding.surface.app.processIdentifier)
        pasteAttempt = nil
        var stable = 0
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(50))
            guard current() else { throw BridgeError.message("CLI 来源在粘贴后改变，没有自动发送；请检查原输入区。") }
            try validateIdentity(binding, frontmost: true)
            // Some native terminal redraws briefly remove the accessible text.
            // Wait inside the same receipt window, without another paste.
            guard let screen = environment.screen(binding.surface) else { receiptHint = "终端暂未提供文字"; stable = 0; continue }
            receiptHint = CLIPromptPolicy.failureHint(screen: screen, binding: binding.session, origin: binding.origin)
            if let prompt = CLIPromptPolicy.prompt(screen: screen, binding: binding.session, origin: binding.origin) {
                pasteAttempt = (binding.id, translationFingerprint, Self.fingerprint(prompt.text))
            }
            let receipt = CLIPromptPolicy.receipt(screen: screen, binding: binding.session, origin: binding.origin, text: text)
            if receipt == .collapsed { return .collapsed }
            stable = receipt == .confirmed ? stable + 1 : 0
            if stable < 3 { continue }
            guard autoSend, CLIPromptPolicy.maySend(text, receipt: receipt) else { return .inserted }
            try Task.checkCancellation()
            guard current() else { throw BridgeError.message("CLI 来源已改变，没有自动发送。") }
            try validate(binding, frontmost: true)
            guard let latest = environment.screen(binding.surface),
                  CLIPromptPolicy.receipt(screen: latest, binding: binding.session, origin: binding.origin, text: text) == .confirmed else { return .unconfirmed }
            try Task.checkCancellation()
            guard current(), environment.focused(binding.surface, true), environment.live(binding.origin) else {
                throw BridgeError.message("CLI 在发送前发生变化，未按回车。请检查原输入区。")
            }
            try environment.key(36, [], binding.surface.app.processIdentifier)
            pasteAttempt = nil
            return .sendKeyPressed
        }
        return .unconfirmed
    }
}
