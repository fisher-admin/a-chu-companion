import Foundation

struct ReplyNode: Sendable {
    let role: String
    var label: String = ""
    var text: String = ""
    var children: [ReplyNode] = []
}
struct ChatMessage: Equatable, Sendable {
    enum Author: Sendable { case user, assistant }
    let ordinal: Int
    let author: Author
    let text: String
}
struct ReplyCandidate: Equatable, Sendable {
    let ordinal: Int
    let text: String
}

struct ReplyTranslationLifecycle {
    private(set) var activeID: UUID?
    var isTranslating: Bool { activeID != nil }

    mutating func begin() -> UUID {
        let id = UUID()
        activeID = id
        return id
    }

    func isCurrent(_ id: UUID) -> Bool { activeID == id }

    @discardableResult mutating func finish(_ id: UUID) -> Bool {
        guard activeID == id else { return false }
        activeID = nil
        return true
    }

    @discardableResult mutating func cancel(_ id: UUID) -> Bool { finish(id) }
}

enum ClaudeDecoder {
    private static func ordinal(_ label: String) -> Int? {
        let parts = label.split(separator: " ")
        guard parts.count == 4, parts[0] == "Message", parts[2] == "of", Int(parts[3]) != nil else { return nil }
        return Int(parts[1])
    }
    private static func author(_ node: ReplyNode) -> ChatMessage.Author? {
        guard node.role == "AXHeading" else { return nil }
        // Some native AX headings expose their name only as a text child.
        // Keep the heading and authorship markers mandatory.
        let names = [node.label, node.text] + node.children.filter { $0.role == "AXStaticText" }.map { $0.text.isEmpty ? $0.label : $0.text }
        for name in names {
            if name.hasPrefix("Claude responded:") { return .assistant }
            if name.hasPrefix("You said:") { return .user }
        }
        return nil
    }
    private static func headingParent(_ node: ReplyNode) -> (ReplyNode, ChatMessage.Author)? {
        for child in node.children { if let found = author(child) { return (node, found) } }
        for child in node.children { if let found = headingParent(child) { return found } }
        return nil
    }
    private static func hasControls(_ node: ReplyNode) -> Bool {
        if node.role == "AXButton" && ["Copy", "Copy code", "复制", "复制代码"].contains(node.label) { return false }
        return ["AXButton", "AXPopUpButton", "AXCheckBox", "AXToolbar", "AXTextArea", "AXTextField"].contains(node.role) || node.children.contains(where: hasControls)
    }
    private static func text(_ node: ReplyNode) -> String {
        if node.role == "AXToolbar" || author(node) != nil || ["AXButton", "AXPopUpButton", "AXCheckBox"].contains(node.role) { return "" }
        if node.role == "AXStaticText" || node.role == "AXListMarker" { return node.text.isEmpty ? node.label : node.text }
        if node.role == "AXLink" && node.children.isEmpty { return node.label }
        return node.children.map(text).filter { !$0.isEmpty }.joined(separator: "\n")
    }
    static func messages(_ root: ReplyNode) -> [ChatMessage] {
        var result: [ChatMessage] = []
        func visit(_ node: ReplyNode) {
            if let n = ordinal(node.label), let (parent, author) = headingParent(node) {
                // Claude's answer body is a sibling group of its authorship heading.
                // Ignore sibling tool activity, duplicated status text, and message actions.
                let controlGroups = parent.children.filter { hasControls($0) }
                func allText(_ node: ReplyNode) -> [String] {
                    (node.role == "AXStaticText" ? [node.text.isEmpty ? node.label : node.text] : []) + node.children.flatMap(allText)
                }
                let statusText = Set(controlGroups.flatMap(allText))
                let body = parent.children.compactMap { child -> String? in
                    guard self.author(child) == nil, !hasControls(child) else { return nil }
                    let value = text(child)
                    guard !value.isEmpty, !statusText.contains(value) else { return nil }
                    return value
                }.joined(separator: "\n\n")
                if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(.init(ordinal: n, author: author, text: body))
                }
                return
            }
            for child in node.children { visit(child) }
        }
        visit(root)
        return result.sorted { $0.ordinal < $1.ordinal }
    }
    static func normalize(_ value: String) -> String { value.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    static func chunks(_ text: String, limit: Int = 5_000) -> [String] {
        var chunks: [String] = []; var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[start..<end])); start = end
        }
        return chunks
    }
}

struct ReplyTracker {
    private let baseline: [ChatMessage]
    private let outbound: String
    private var conversation: String
    private var anchor: Int?
    private var changedAt: TimeInterval = 0
    private var emitted: ReplyCandidate?
    private(set) var latest: ReplyCandidate?
    var bound: Bool { anchor != nil }
    init(baseline: [ChatMessage], outbound: String, conversation: String) {
        self.baseline = baseline; self.outbound = ClaudeDecoder.normalize(outbound); self.conversation = conversation
    }
    mutating func observe(conversation current: String, messages: [ChatMessage], now: TimeInterval) throws -> ReplyCandidate? {
        if current != conversation {
            let initial = conversation.hasSuffix("/new") || conversation.hasSuffix("claude.ai/")
            guard initial, anchor == nil, baseline.isEmpty, current.contains("claude.ai/chat/") else {
                throw BridgeError.message("检测到切换会话，已停止自动读取。请在新会话重新唤出A畜伴侣。")
            }
            conversation = current
        }
        guard messages.count >= baseline.count,
              Array(messages.prefix(baseline.count)) == baseline else {
            throw BridgeError.message("对话结构或历史发生变化，已停止自动读取。")
        }
        if anchor == nil {
            let users = messages.dropFirst(baseline.count).filter { $0.author == .user }
            if let first = users.first {
                guard ClaudeDecoder.normalize(first.text) == outbound else { throw BridgeError.message("检测到与译文不同的新消息，已停止读取。请重新唤出A畜伴侣。") }
                anchor = first.ordinal
            }
        }
        guard let anchor, let message = messages.last(where: { $0.author == .assistant && $0.ordinal > anchor }) else { return nil }
        let candidate = ReplyCandidate(ordinal: message.ordinal, text: message.text)
        if candidate != latest { latest = candidate; changedAt = now; return nil }
        guard now - changedAt >= 3, candidate != emitted else { return nil }
        emitted = candidate
        return candidate
    }
}
