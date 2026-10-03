import AppKit
import ApplicationServices

struct ReplySnapshot: Sendable {
    let conversation: String
    let messages: [ChatMessage]
    let foundTranscript: Bool
    let responseComplete: Bool
}
final class ClaudeSource: @unchecked Sendable {
    let pid: pid_t
    private var root: AXUIElement
    let window: AXUIElement
    let composer: AXUIElement
    let name: String
    let fixture: Bool
    init(pid: pid_t, root: AXUIElement, window: AXUIElement, composer: AXUIElement, name: String, fixture: Bool) {
        self.pid = pid; self.root = root; self.window = window; self.composer = composer; self.name = name; self.fixture = fixture
    }
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    static func axElement(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    static func bind(pid: pid_t, bundle: String, composer: AXUIElement, window: AXUIElement, name: String) throws -> ClaudeSource {
        let fixture = bundle == "local.achu.fixture"
        guard fixture || ["com.anthropic.claudefordesktop", "com.google.Chrome", "com.apple.Safari", "com.microsoft.edgemac", "com.brave.Browser"].contains(bundle) else {
            throw BridgeError.message("自动回复翻译目前只适配 Claude 桌面版及浏览器中的 claude.ai。")
        }
        var cursor: AXUIElement? = composer
        for _ in 0..<32 {
            guard let element = cursor else { break }
            AXUIElementSetMessagingTimeout(element, 0.2)
            if attribute(element, kAXRoleAttribute) as? String == "AXWebArea" {
                let url = urlString(element)
                if fixture || URL(string: url)?.host == "claude.ai" {
                    return ClaudeSource(pid: pid, root: element, window: window, composer: composer, name: name, fixture: fixture)
                }
            }
            cursor = axElement(attribute(element, kAXParentAttribute))
        }
        // SPA navigation may replace the original composer and web area.
        // Rebind reading only within the already selected window.
        let source = ClaudeSource(pid: pid, root: composer, window: window, composer: composer, name: name, fixture: fixture)
        try source.refreshRoot()
        return source
    }
    private static func urlString(_ element: AXUIElement) -> String {
        let raw = attribute(element, kAXURLAttribute)
        let string = (raw as? URL)?.absoluteString ?? (raw as? String) ?? ""
        guard var parts = URLComponents(string: string) else { return "" }
        parts.query = nil; parts.fragment = nil
        return parts.string ?? ""
    }
    private func isInCurrentWindow() -> Bool {
        let start = Date()
        var visited = 0
        func contains(_ element: AXUIElement, depth: Int) -> Bool {
            if CFEqual(element, root) { return true }
            visited += 1
            guard visited < 350, depth < 25, Date().timeIntervalSince(start) < 1 else { return false }
            AXUIElementSetMessagingTimeout(element, 0.1)
            let role = Self.attribute(element, kAXRoleAttribute) as? String ?? ""
            if ["AXToolbar", "AXMenuBar", "AXTextArea", "AXTextField"].contains(role) { return false }
            // Other browser tabs are not our bound conversation. Claude desktop's
            // file-based outer web area can contain the actual claude.ai web area.
            if role == "AXWebArea" && !Self.urlString(element).hasPrefix("file:") { return false }
            let children = Self.attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            return children.contains { contains($0, depth: depth + 1) }
        }
        return contains(window, depth: 0)
    }
    private func refreshRoot() throws {
        if Self.attribute(root, kAXRoleAttribute) as? String == "AXWebArea", isInCurrentWindow() { return }
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            throw BridgeError.message("Claude 已关闭，读取已停止。")
        }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.5)
        if let windows = Self.attribute(axApp, kAXWindowsAttribute) as? [AXUIElement], !windows.contains(where: { CFEqual($0, window) }) {
            throw BridgeError.message("连接的 Claude 窗口已关闭，读取已停止。")
        }
        var visited = 0
        let start = Date()
        func find(_ element: AXUIElement, depth: Int) -> AXUIElement? {
            visited += 1
            guard visited < 350, depth < 25, Date().timeIntervalSince(start) < 1 else { return nil }
            AXUIElementSetMessagingTimeout(element, 0.1)
            let role = Self.attribute(element, kAXRoleAttribute) as? String ?? ""
            if ["AXToolbar", "AXMenuBar", "AXTextArea", "AXTextField"].contains(role) { return nil }
            if role == "AXWebArea" {
                let url = Self.urlString(element)
                if URL(string: url)?.host == "claude.ai" { return element }
                if !url.hasPrefix("file:") { return nil }
            }
            for child in Self.attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                if let found = find(child, depth: depth + 1) { return found }
            }
            return nil
        }
        guard let current = find(window, depth: 0) else { throw ReplyReadPending(message: "正在等待当前窗口的 Claude 对话页面。") }
        root = current
    }
    func capture() async throws -> ReplySnapshot {
        let work = Task.detached(priority: .utility) { try await self.snapshot() }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }
    func captureVisibleReplies() async throws -> ReplySnapshot {
        let work = Task.detached(priority: .utility) { try await self.snapshot(visibleOnly: true) }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }
    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let rawPosition = attribute(element, kAXPositionAttribute), let rawSize = attribute(element, kAXSizeAttribute),
              CFGetTypeID(rawPosition) == AXValueGetTypeID(), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
        let position = rawPosition as! AXValue; let size = rawSize as! AXValue
        guard AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize else { return nil }
        var point = CGPoint.zero; var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private func snapshot(visibleOnly: Bool = false) async throws -> ReplySnapshot {
        guard AXIsProcessTrusted() else { throw BridgeError.message("辅助功能权限已关闭，自动读取已停止。") }
        try refreshRoot()
        let conversation = Self.urlString(root)
        guard fixture || (URL(string: conversation)?.host == "claude.ai" && (URL(string: conversation)?.path.hasPrefix("/chat/") == true || ["/new", "/"].contains(URL(string: conversation)?.path ?? ""))) else {
            throw BridgeError.message("Claude 对话页面已关闭或切换，自动读取已停止。")
        }
        let metadata = [kAXRoleAttribute, kAXDescriptionAttribute, kAXTitleAttribute, kAXChildrenAttribute] as CFArray
        let skipRoles = ["AXTextArea", "AXTextField", "AXToolbar", "AXButton", "AXPopUpButton", "AXCheckBox"]
        var visited = 0
        func info(_ element: AXUIElement, depth: Int) async throws -> (String, String, [AXUIElement]) {
            try Task.checkCancellation()
            visited += 1
            // Structural safety bounds are unrelated to message character count.
            guard depth <= 80, visited <= 1_000_000 else { throw BridgeError.message("对话界面结构异常，无法完整读取，请重新连接。") }
            if visited.isMultiple(of: 64) { await Task.yield() }
            AXUIElementSetMessagingTimeout(element, 0.5)
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, metadata, [], &raw) == .success,
                  let values = raw as? [Any], values.count == 4 else { throw ReplyReadPending(message: "Claude 界面暂时不可读取。") }
            for value in values {
                if CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() {
                    let failure = value as! AXValue
                    guard AXValueGetType(failure) == .axError else { continue }
                    var error = AXError.success
                    AXValueGetValue(failure, .axError, &error)
                    guard error == .attributeUnsupported || error == .noValue else {
                        throw ReplyReadPending(message: "Claude 消息结构尚未完整返回，本次读取已丢弃。")
                    }
                }
            }
            let role = values[0] as? String ?? ""
            let description = values[1] as? String ?? ""
            let label = description.isEmpty ? (values[2] as? String ?? "") : description
            return (role, label, values[3] as? [AXUIElement] ?? [])
        }
        func findTranscript(_ element: AXUIElement, depth: Int) async throws -> AXUIElement? {
            let (role, label, children) = try await info(element, depth: depth)
            if label == "Chat messages" { return element }
            if skipRoles.contains(role) || ["Sidebar", "Notifications", "Message actions"].contains(label) { return nil }
            for child in children {
                if let found = try await findTranscript(child, depth: depth + 1) { return found }
            }
            return nil
        }
        var statusLabels: [String] = []
        var controlLabels: [String] = []
        func generationStatus(_ element: AXUIElement, depth: Int) async throws {
            let (role, label, children) = try await info(element, depth: depth)
            if ["Chat messages", "Sidebar", "Notifications"].contains(label) || ["AXTextArea", "AXTextField"].contains(role) { return }
            if role == "AXButton" { controlLabels.append(label); return }
            if role == "AXStaticText" {
                let value = Self.attribute(element, kAXValueAttribute) as? String ?? label
                if value.hasPrefix("Claude ") { statusLabels.append(value) }
                return
            }
            for child in children { try await generationStatus(child, depth: depth + 1) }
        }
        try await generationStatus(root, depth: 0)
        guard let region = try await findTranscript(root, depth: 0) else {
            if !fixture && URL(string: conversation)?.path.hasPrefix("/chat/") == true { throw ReplyReadPending(message: "Claude 消息区尚未就绪。") }
            return ReplySnapshot(conversation: conversation, messages: [], foundTranscript: false, responseComplete: false)
        }
        var viewport: CGRect?
        if visibleOnly {
            guard var bounds = Self.frame(window) else { throw ReplyReadPending(message: "无法核对 Claude 窗口的可见位置，请保持窗口打开。") }
            bounds.origin.y += 60; bounds.size.height -= 60
            if let input = Self.frame(composer), input.minY > bounds.minY, input.minY < bounds.maxY {
                bounds.size.height = input.minY - bounds.minY - 12
            }
            var cursor = Self.axElement(Self.attribute(region, kAXParentAttribute))
            for _ in 0..<20 {
                guard let parent = cursor else { break }
                if Self.attribute(parent, kAXRoleAttribute) as? String == "AXScrollArea", let clip = Self.frame(parent) {
                    bounds = bounds.intersection(clip); break
                }
                if CFEqual(parent, root) { break }
                cursor = Self.axElement(Self.attribute(parent, kAXParentAttribute))
            }
            viewport = bounds
        }
        var elements: [(ordinal: Int, total: Int, element: AXUIElement)] = []
        func newest(_ element: AXUIElement, depth: Int) async throws {
            guard elements.count < (visibleOnly ? 100 : 8) else { return }
            let (role, label, children) = try await info(element, depth: depth)
            let words = label.split(separator: " ")
            if words.count == 4, words[0] == "Message", words[2] == "of", let ordinal = Int(words[1]), let total = Int(words[3]) {
                if let viewport {
                    guard let frame = Self.frame(element), VisibleReplyGeometry.intersects(frame, viewport: viewport) else { return }
                }
                elements.append((ordinal, total, element)); return
            }
            guard !skipRoles.contains(role) else { return }
            for child in children.reversed() { try await newest(child, depth: depth + 1) }
        }
        try await newest(region, depth: 0)
        elements.sort { $0.ordinal < $1.ordinal }
        if let latest = elements.last {
            guard (visibleOnly || latest.ordinal == latest.total), Set(elements.map(\.ordinal)).count == elements.count,
                  elements.allSatisfy({ $0.total == latest.total }) else { throw ReplyReadPending(message: "Claude 消息区正在更新。") }
        }
        func read(_ element: AXUIElement, depth: Int) async throws -> ReplyNode {
            let (role, label, children) = try await info(element, depth: depth)
            if role == "AXToolbar", label == "Message actions" {
                var actions: [ReplyNode] = []
                for child in children {
                    let (childRole, childLabel, _) = try await info(child, depth: depth + 1)
                    actions.append(ReplyNode(role: childRole, label: childLabel))
                }
                return ReplyNode(role: role, label: label, children: actions)
            }
            if ["Sidebar", "Notifications", "Message actions"].contains(label) || skipRoles.contains(role) { return ReplyNode(role: role, label: label) }
            // No page-wide text reads and no character cap; only complete bodies
            // of the most recent, author-marked messages are retained.
            var text = ""
            if ["AXStaticText", "AXListMarker"].contains(role) {
                var value: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
                guard result == .success || result == .attributeUnsupported || result == .noValue else {
                    throw ReplyReadPending(message: "消息文字尚未完整返回，已丢弃本次读取。")
                }
                text = value as? String ?? ""
            }
            var nodes: [ReplyNode] = []
            for child in children { nodes.append(try await read(child, depth: depth + 1)) }
            return ReplyNode(role: role, label: label, text: text, children: nodes)
        }
        var nodes: [ReplyNode] = []
        for element in elements { nodes.append(try await read(element.element, depth: 0)) }
        try Task.checkCancellation()
        guard isInCurrentWindow(), Self.urlString(root) == conversation else { throw ReplyReadPending(message: "读取期间会话已更新，本次内容已丢弃。") }
        let complete = ClaudeDecoder.responseComplete(statusLabels: statusLabels, controlLabels: controlLabels, latest: nodes.last)
        let messages: [ChatMessage]
        if visibleOnly {
            messages = zip(nodes, elements).flatMap { node, element in
                ClaudeDecoder.messages(node).filter { $0.author == .assistant && (element.ordinal < element.total || complete) }
            }
        } else { messages = try ClaudeDecoder.recentMessages(nodes) }
        return ReplySnapshot(conversation: conversation, messages: messages, foundTranscript: true, responseComplete: complete)
    }
}
