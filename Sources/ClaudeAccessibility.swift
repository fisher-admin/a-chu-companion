import AppKit
import ApplicationServices

struct ReplySnapshot: Sendable {
    let conversation: String
    let messages: [ChatMessage]
    let foundTranscript: Bool
}
final class ClaudeSource: @unchecked Sendable {
    let pid: pid_t
    let root: AXUIElement
    let window: AXUIElement
    let name: String
    let fixture: Bool
    init(pid: pid_t, root: AXUIElement, window: AXUIElement, name: String, fixture: Bool) {
        self.pid = pid; self.root = root; self.window = window; self.name = name; self.fixture = fixture
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
        let fixture = bundle == "local.yiqiao.fixture"
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
                    return ClaudeSource(pid: pid, root: element, window: window, name: name, fixture: fixture)
                }
            }
            cursor = axElement(attribute(element, kAXParentAttribute))
        }
        throw BridgeError.message("没有识别到 Claude 网页。请在 Claude 的聊天输入框中重新按 ⌃⌥E。")
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
    func snapshot() throws -> ReplySnapshot {
        guard AXIsProcessTrusted() else { throw BridgeError.message("辅助功能权限已关闭，自动读取已停止。") }
        guard isInCurrentWindow() else { throw BridgeError.message("原对话已不在当前窗口中，自动读取已停止。请重新选择 Claude 会话。") }
        let conversation = fixture ? "fixture://chat/test" : Self.urlString(root)
        guard fixture || (URL(string: conversation)?.host == "claude.ai" && (URL(string: conversation)?.path.hasPrefix("/chat/") == true || ["/new", "/"].contains(URL(string: conversation)?.path ?? ""))) else {
            throw BridgeError.message("Claude 对话页面已关闭或切换，自动读取已停止。")
        }
        let started = Date()
        var count = 0
        var characters = 0
        let names = [kAXRoleAttribute, kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute, kAXChildrenAttribute] as CFArray
        func read(_ element: AXUIElement, depth: Int) throws -> ReplyNode {
            count += 1
            guard count <= 1_800, depth <= 50, characters < 90_000, Date().timeIntervalSince(started) < 2.5 else {
                throw BridgeError.message("本页内容过长或响应较慢，已停止读取。请打开较短的对话后重试。")
            }
            AXUIElementSetMessagingTimeout(element, 0.15)
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, names, [], &raw) == .success, let values = raw as? [Any], values.count == 5 else {
                throw BridgeError.message("Claude 界面暂时不可读取，请保持目标会话打开后重新尝试。")
            }
            let role = values[0] as? String ?? ""
            let description = values[1] as? String ?? ""
            let title = values[2] as? String ?? ""
            let label = description.isEmpty ? title : description
            let text = values[3] as? String ?? ""
            // Read no sidebar history, editable drafts, notifications, or toolbar data.
            if ["Sidebar", "Notifications", "Message actions"].contains(label) || ["AXTextArea", "AXTextField", "AXToolbar", "AXButton", "AXPopUpButton", "AXCheckBox"].contains(role) {
                return ReplyNode(role: role, label: label)
            }
            characters += text.count
            let children = values[4] as? [AXUIElement] ?? []
            return ReplyNode(role: role, label: label, text: text, children: try children.map { try read($0, depth: depth + 1) })
        }
        let tree = try read(root, depth: 0)
        func transcript(_ node: ReplyNode) -> ReplyNode? {
            if node.label == "Chat messages" { return node }
            for child in node.children { if let found = transcript(child) { return found } }
            return nil
        }
        guard let region = transcript(tree) else {
            if !fixture && URL(string: conversation)?.path.hasPrefix("/chat/") == true {
                throw BridgeError.message("当前页面没有可识别的 Claude 消息区，自动读取已停止。")
            }
            return ReplySnapshot(conversation: conversation, messages: [], foundTranscript: false)
        }
        let messages = ClaudeDecoder.messages(region)
        return ReplySnapshot(conversation: conversation, messages: messages, foundTranscript: true)
    }
}
