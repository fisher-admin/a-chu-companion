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
    static func footer(screen: String, binding: String, origin: CLIDeliveryOrigin) -> Footer? {
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
                return .init(lines: lines, start: start, end: end)
            }
        }
        return nil
    }
    static func isHint(_ line: String) -> Bool {
        // Claude can place several shortcuts on one row. Validate each known
        // atom; a familiar first hint must not conceal arbitrary trailing text.
        guard line.count <= 400 else { return false }
        let parts = line.components(separatedBy: " · ")
        guard parts.count <= 3 else { return false }
        return parts.allSatisfy { part in
            let hint = part.trimmingCharacters(in: .whitespaces)
            return hint == "? for shortcuts" || hint == "-- INSERT --" || hint == "← for agents" ||
                hint.range(of: #"^(?:[⏵▶]{1,2} .+ \(shift\+tab to cycle\)|shift\+tab to cycle|ctrl\+g to edit in (?:editor|.+))$"#, options: .regularExpression) != nil
        }
    }

}

@MainActor final class CLITargetBridge {
    struct Surface {
        let app: NSRunningApplication
        let window: AXUIElement
        let focus: AXUIElement
        let element: AXUIElement
        var name: String { app.localizedName ?? "终端" }
        var location: ManualInputDelivery.Location { .init(app: app, window: window, input: focus) }
    }
    struct Binding {
        let id = UUID()
        let session: String
        let origin: CLIDeliveryOrigin
        let surface: Surface
    }
    typealias Outcome = ManualInputDelivery.Outcome
    @MainActor struct Environment {
        var trusted: @MainActor () -> Bool = { TargetBridge.trusted }
        var alive: @MainActor (Surface) -> Bool = { ManualInputDelivery.available($0.location) }
        var screen: @MainActor (Surface) -> String? = CLITargetBridge.screen
        var live: @MainActor (CLIDeliveryOrigin) -> Bool = { CLIProcessRecord.read($0.pid)?.matches($0) == true }
        var focused: @MainActor (Surface, Bool) -> Bool = CLITargetBridge.focused
        var activate: @MainActor (Surface) -> Void = { ManualInputDelivery.restore($0.location) }
        var key: @MainActor (CGKeyCode, CGEventFlags, pid_t) throws -> Void = { try TargetBridge.key($0, flags: $1, pid: $2) }
        var board: NSPasteboard = .general
    }
    private let environment: Environment
    let inputDelivery: ManualInputDelivery
    init(environment: Environment? = nil) {
        let env = environment ?? .init(); self.environment = env
        func surface(_ location: ManualInputDelivery.Location) -> Surface {
            .init(app: location.app, window: location.window, focus: location.input, element: location.input)
        }
        var sending = ManualInputDelivery.Environment()
        sending.trusted = env.trusted
        sending.available = { env.alive(surface($0)) }
        sending.restore = { env.activate(surface($0)) }
        sending.focused = { env.focused(surface($0), true) }
        sending.key = env.key; sending.board = env.board
        inputDelivery = ManualInputDelivery(environment: sending)
    }
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
        // The user selected this exact focus. Its contents, role, terminal
        // brand and footer are not prerequisites for a sending connection.
        guard TargetBridge.attribute(focus, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole else {
            throw BridgeError.message("密码输入区不能作为对话发送位置。")
        }
        return .init(app: app, window: window, focus: focus, element: focus)
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
        guard origin.valid(for: session) else { throw BridgeError.message("CLI 读取身份无效，发送位置保持。") }
        try inputDelivery.validate(surface.location)
        return Binding(session: session, origin: origin, surface: surface)
    }
    func validate(_ binding: Binding, frontmost: Bool) throws {
        try inputDelivery.validate(binding.surface.location)
    }
    func readMatches(surface: Surface, session: String, origin: CLIDeliveryOrigin) -> Bool {
        guard origin.valid(for: session), environment.live(origin), let screen = environment.screen(surface) else { return false }
        return CLIPromptPolicy.footer(screen: screen, binding: session, origin: origin) != nil
    }
    func passiveScreen(_ surface: Surface) -> (String?, Bool) {
        guard (try? inputDelivery.validate(surface.location)) != nil else { return (nil, false) }
        let value = environment.screen(surface)
        return (value, value != nil)
    }
    func passiveScreen(_ binding: Binding) -> (String?, Bool) { passiveScreen(binding.surface) }
    func deliver(_ text: String, to binding: Binding, autoSend: Bool, current: () -> Bool) async throws -> Outcome {
        try await inputDelivery.deliver(text, to: .init(id: binding.id, location: binding.surface.location), autoSend: autoSend, current: current)
    }
}
