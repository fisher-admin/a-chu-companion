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
    private let metricsLock = NSLock()
    private var captureSamples = 0
    private var lastCaptureSeconds: TimeInterval = 0
    var captureMetrics: (samples: Int, lastSeconds: TimeInterval) { metricsLock.withLock { (captureSamples, lastCaptureSeconds) } }
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
        let captureStarted = Date()
        defer { metricsLock.withLock { captureSamples += 1; lastCaptureSeconds = Date().timeIntervalSince(captureStarted) } }
        guard AXIsProcessTrusted() else { throw BridgeError.message("辅助功能权限已关闭，自动读取已停止。") }
        try refreshRoot()
        let conversation = Self.urlString(root)
        guard let format = ClaudeConversationPage.format(conversation) ?? (fixture ? .chat : nil) else {
            throw BridgeError.message("Claude 对话页面已关闭或切换，自动读取已停止。")
        }
        let metadata = [kAXRoleAttribute, kAXDescriptionAttribute, kAXTitleAttribute, kAXChildrenAttribute] as CFArray
        let skipRoles = ["AXTextArea", "AXTextField", "AXToolbar", "AXButton", "AXPopUpButton", "AXCheckBox"]
        var visited = 0
        let captureDeadline = captureStarted.addingTimeInterval(2.5)
        func info(_ element: AXUIElement, depth: Int) async throws -> (String, String, [AXUIElement], Bool) {
            try Task.checkCancellation()
            visited += 1
            // Structural safety bounds are unrelated to message character count.
            guard Date() < captureDeadline else { throw ReplyReadPending(message: "本次读取达到时间预算，保留上次完整快照并继续检查。") }
            guard depth <= 80, visited <= 20_000 else { throw BridgeError.message("对话界面结构异常，无法完整读取，请重新连接。") }
            if visited.isMultiple(of: 64) { await Task.yield() }
            AXUIElementSetMessagingTimeout(element, 0.05)
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
            let title = values[2] as? String ?? ""
            var label = description.isEmpty ? title : description
            if format == .code, let ordinal = try ClaudeDecoder.codePosition(role: role, description: description, title: title) {
                label = "Message \(ordinal)"
            }
            let streaming = role == "AXGroup" && [description, title].contains("Currently streaming message")
            return (role, label, values[3] as? [AXUIElement] ?? [], streaming)
        }
        func findTranscript(_ element: AXUIElement, depth: Int) async throws -> AXUIElement? {
            let (role, label, children, _) = try await info(element, depth: depth)
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
            let (role, label, children, _) = try await info(element, depth: depth)
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
            if !fixture && !["/new", "/", ""].contains(URL(string: conversation)?.path ?? "") { throw ReplyReadPending(message: "Claude 消息区尚未就绪。") }
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
        var elements: [(ordinal: Int, total: Int, members: [AXUIElement], streamingAssistant: Bool)] = []
        func newest(_ element: AXUIElement, depth: Int) async throws {
            guard elements.count < (visibleOnly ? 100 : 8) else { return }
            let (role, label, children, _) = try await info(element, depth: depth)
            if let position = ClaudeDecoder.position(label, format: .chat), let total = position.total {
                if let viewport {
                    guard let frame = Self.frame(element), VisibleReplyGeometry.intersects(frame, viewport: viewport) else { return }
                }
                elements.append((position.ordinal, total, [element], false)); return
            }
            guard !skipRoles.contains(role) else { return }
            for child in children.reversed() { try await newest(child, depth: depth + 1) }
        }
        if format == .code {
            func branch(_ element: AXUIElement, depth: Int) async throws -> CodeTranscriptBranch<AXUIElement> {
                let (role, label, children, streaming) = try await info(element, depth: depth)
                let ordinal = role == "AXGroup" ? ClaudeDecoder.position(label, format: .code)?.ordinal : nil
                var nested: [CodeTranscriptBranch<AXUIElement>] = []
                if !skipRoles.contains(role) {
                    for child in children { nested.append(try await branch(child, depth: depth + 1)) }
                }
                let authors = Set(nested.compactMap(\.author))
                let author = ClaudeDecoder.codeHeadingAuthor(role: role, label: label) ?? (authors.count == 1 ? authors.first : nil)
                return .init(element: element, ordinal: ordinal, children: nested, author: author,
                             isStreamingAssistant: streaming)
            }
            let pieces = try ClaudeDecoder.codeStreamingPieces(ClaudeDecoder.codeTranscriptPieces(try await branch(region, depth: 0)))
            let ranges = try ClaudeDecoder.codeMessageRanges(pieces.map { $0.ordinal.map { "Message \($0)" } ?? "" })
            if let latest = ranges.last {
                for group in ranges.suffix(visibleOnly ? 100 : 8) {
                    let members = pieces[group.range].map(\.element)
                    if let viewport, !members.contains(where: { member in
                        Self.frame(member).map { VisibleReplyGeometry.intersects($0, viewport: viewport) } ?? false
                    }) { continue }
                    elements.append((group.ordinal, latest.ordinal, members, pieces[group.range.lowerBound].isStreamingAssistant))
                }
            }
        } else { try await newest(region, depth: 0) }
        elements.sort { $0.ordinal < $1.ordinal }
        if let latest = elements.last {
            guard (visibleOnly || latest.ordinal == latest.total), Set(elements.map(\.ordinal)).count == elements.count,
                  elements.allSatisfy({ $0.total == latest.total }) else { throw ReplyReadPending(message: "Claude 消息区正在更新。") }
        }
        func read(_ element: AXUIElement, depth: Int) async throws -> ReplyNode {
            let (role, label, children, streaming) = try await info(element, depth: depth)
            if role == "AXToolbar", label == "Message actions" {
                var actions: [ReplyNode] = []
                for child in children {
                    let (childRole, childLabel, _, _) = try await info(child, depth: depth + 1)
                    actions.append(ReplyNode(role: childRole, label: childLabel))
                }
                return ReplyNode(role: role, label: label, children: actions)
            }
            if ["Sidebar", "Notifications", "Message actions"].contains(label) || skipRoles.contains(role) { return ReplyNode(role: role, label: label) }
            // No page-wide text reads and no character cap; only complete bodies
            // of the most recent, author-marked messages are retained.
            var text = ""
            if ["AXStaticText", "AXListMarker", "AXHeading"].contains(role) {
                var value: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
                guard result == .success || result == .attributeUnsupported || result == .noValue else {
                    throw ReplyReadPending(message: "消息文字尚未完整返回，已丢弃本次读取。")
                }
                text = value as? String ?? ""
                if role == "AXHeading", !text.hasPrefix("Claude responded:"), !text.hasPrefix("You said:") {
                    text = Self.attribute(element, kAXTitleAttribute) as? String ?? text
                }
            }
            var nodes: [ReplyNode] = []
            for child in children { nodes.append(try await read(child, depth: depth + 1)) }
            return ReplyNode(role: role, label: label, text: text, children: nodes, isStreamingAssistant: streaming)
        }
        var nodes: [ReplyNode] = []
        for element in elements {
            if format == .code {
                var members: [ReplyNode] = []
                for member in element.members { members.append(try await read(member, depth: 0)) }
                nodes.append(ReplyNode(role: "AXGroup", label: "Message \(element.ordinal)", children: members,
                                       isStreamingAssistant: element.streamingAssistant))
            } else { nodes.append(try await read(element.members[0], depth: 0)) }
        }
        try Task.checkCancellation()
        guard isInCurrentWindow(), Self.urlString(root) == conversation else { throw ReplyReadPending(message: "读取期间会话已更新，本次内容已丢弃。") }
        let complete = ClaudeDecoder.responseComplete(statusLabels: statusLabels, controlLabels: controlLabels, latest: nodes.last, format: format)
        let messages: [ChatMessage]
        if visibleOnly {
            messages = zip(nodes, elements).flatMap { node, element in
                let finished = element.ordinal < element.total || complete
                let decoded = format == .code ? ClaudeDecoder.codeSegments(node, responseComplete: finished) : ClaudeDecoder.messages(node)
                return decoded.filter { $0.author == .assistant && ($0.completed ?? finished) }
            }
        } else {
            messages = format == .code ? try ClaudeDecoder.recentCodeSegments(nodes, responseComplete: complete) : try ClaudeDecoder.recentMessages(nodes)
        }
        return ReplySnapshot(conversation: conversation, messages: messages, foundTranscript: true, responseComplete: complete)
    }
}
