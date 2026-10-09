import AppKit
import ApplicationServices

/// Public accessibility controls in one physical browser window. No cookies,
/// credential stores, injected scripts, address-bar typing or message actions.
@MainActor enum WebUsageAccessibility {
    private(set) static var discoverySummary = ""
    private static func value(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(node,0.05)
        return TargetBridge.attribute(node,key)
    }
    private static func role(_ node: AXUIElement) -> String { value(node,kAXRoleAttribute) as? String ?? "" }
    private static func label(_ node: AXUIElement) -> String {
        for key in [kAXTitleAttribute,kAXDescriptionAttribute,kAXValueAttribute] {
            if let text = value(node,key) as? String, !text.isEmpty { return text }
        }
        return ""
    }
    private static func children(_ node: AXUIElement) -> [AXUIElement] { value(node,kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    private static func url(_ node: AXUIElement) -> String {
        WebUsagePage.urlString(value(node,kAXURLAttribute))
    }
    private static func find(_ root: AXUIElement, stopAtWebArea: Bool = false,
                             matches: @MainActor (AXUIElement) -> Bool) throws -> [AXUIElement] {
        let deadline = Date().addingTimeInterval(1.5)
        var result: [AXUIElement] = [], visited = 0
        @MainActor func walk(_ node: AXUIElement, _ depth: Int) throws {
            guard Date() < deadline, visited < 5000, depth < 35 else { throw BridgeError.message("网页控件读取超时，请在所需窗口重试。") }
            visited += 1
            if matches(node) { result.append(node); return }
            let type = role(node)
            if ["AXTextArea","AXTextField","AXStaticText"].contains(type) || (stopAtWebArea && type == "AXWebArea") { return }
            for child in children(node) { try walk(child,depth+1) }
        }
        try walk(root,0); return result
    }
    private static func one(_ nodes: [AXUIElement], _ message: String) throws -> AXUIElement {
        guard nodes.count == 1, let node = nodes.first else { throw BridgeError.message(message) }; return node
    }
    static func available(_ selected: WebUsageSelection) -> Bool {
        guard !selected.app.isTerminated else { return false }
        let root = AXUIElementCreateApplication(selected.app.processIdentifier)
        return (value(root,kAXWindowsAttribute) as? [AXUIElement] ?? []).contains { CFEqual($0,selected.window) }
    }
    static func foreground(_ selected: WebUsageSelection) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == selected.app.processIdentifier else { return false }
        let root = AXUIElementCreateApplication(selected.app.processIdentifier)
        guard let focused = TargetBridge.elementAttribute(root,kAXFocusedWindowAttribute) else { return false }
        return CFEqual(focused,selected.window)
    }
    static func activate(_ selected: WebUsageSelection) {
        guard available(selected) else { return }
        selected.app.activate(options:[])
        AXUIElementPerformAction(selected.window,kAXRaiseAction as CFString)
    }
    private static func current(_ selected: WebUsageSelection) throws {
        try Task.checkCancellation()
        guard selected.allowed(), available(selected), foreground(selected) else { throw CancellationError() }
    }
    private static func page(_ selected: WebUsageSelection) throws -> AXUIElement {
        try current(selected)
        return try one(find(selected.window,stopAtWebArea:true) { role($0) == "AXWebArea" && WebUsagePage.official(url($0)) },"所选窗口没有唯一可读取的 Claude 官方网页。")
    }
    static func discover() throws -> [WebUsageSelection] {
        guard AXIsProcessTrusted() else { throw BridgeError.message("请先开启伴侣的辅助功能权限。") }
        var result: [WebUsageSelection] = [], windowCount = 0, pageCount = 0, officialCount = 0, emptyURLCount = 0
        // Browser host processes need not have regular activation policy (for
        // example, embedded windows). Presence of a public window/WebArea is
        // the selection criterion; application brand or Dock policy is not.
        for app in NSWorkspace.shared.runningApplications where !app.isTerminated && app.processIdentifier != getpid() && app.bundleIdentifier != "com.anthropic.claudefordesktop" {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            guard !(value(root,kAXWindowsAttribute) as? [AXUIElement] ?? []).isEmpty else { continue }
            // The same Chromium accessibility opt-in already used for capture.
            AXUIElementSetAttributeValue(root,"AXManualAccessibility" as CFString,kCFBooleanTrue)
            AXUIElementSetAttributeValue(root,"AXEnhancedUserInterface" as CFString,kCFBooleanTrue)
            for window in value(root,kAXWindowsAttribute) as? [AXUIElement] ?? [] {
                windowCount += 1
                let pages = try find(window,stopAtWebArea:true) { node in
                    guard role(node) == "AXWebArea" else { return false }
                    pageCount += 1
                    let location = url(node)
                    if location.isEmpty { emptyURLCount += 1 }
                    if WebUsagePage.official(location) { officialCount += 1 }
                    return WebUsagePage.isUsageURL(location)
                }
                if pages.count == 1 { result.append(.init(app:app,window:window,input:nil)) }
                else if pages.count > 1 { throw BridgeError.message("一个窗口包含多个 Usage 页面，请在目标输入区用 ⌃⌥E 指定窗口。") }
            }
        }
        discoverySummary = "已检查\(windowCount)个窗口、\(pageCount)个网页，其中\(officialCount)个Claude官方可见页（\(emptyURLCount)个未提供网址）"
        return result
    }
    static func begin(_ selected: WebUsageSelection) throws -> NativeWebUsage.PageState {
        let location = url(try page(selected))
        guard !WebUsagePage.isOtherSettings(location) else { throw BridgeError.message("请先关闭 Claude 其他设置页面，再读取额度。") }
        return .init(url:location,wasUsage:WebUsagePage.isUsageURL(location))
    }
    private static func press(_ node: AXUIElement) throws {
        guard (value(node,kAXEnabledAttribute) as? Bool) != false,
              AXUIElementPerformAction(node,kAXPressAction as CFString) == .success else { throw BridgeError.message("网页未响应额度控件操作，请在所选窗口重试。") }
    }
    private static func wait<T>(_ selected: WebUsageSelection, _ probe: @MainActor () throws -> T?) async throws -> T {
        let deadline = Date().addingTimeInterval(6)
        repeat {
            try current(selected)
            if let result = try probe() { return result }
            try await Task.sleep(for:.milliseconds(100))
        } while Date() < deadline
        throw BridgeError.message("Claude 额度界面尚未就绪，请稍后重试。")
    }
    private static func settings(_ area: AXUIElement) throws -> AXUIElement? {
        let found = try find(area) { role($0) == "AXGroup" && ["settings","设置","设定"].contains(WebUsagePage.normalized(label($0))) }
        return found.count == 1 ? found.first : nil
    }
    private static func closeUsage(_ selected: WebUsageSelection) async throws {
        let area = try page(selected)
        guard WebUsagePage.isUsageURL(url(area)) else { return }
        guard let scoped = try settings(area) else { throw BridgeError.message("无法定位 Usage 设置窗口。") }
        let close = try one(find(scoped) { role($0) == "AXButton" && ["close","关闭","关掉"].contains(WebUsagePage.normalized(label($0))) },"无法找到 Usage 关闭按钮。")
        try press(close)
        let _: Bool = try await wait(selected) { !WebUsagePage.isUsageURL(url(try page(selected))) ? true : nil }
    }
    private static func accountPopup(_ selected: WebUsageSelection) throws -> AXUIElement {
        let area = try page(selected)
        let sidebar = try one(find(area) { ["AXGroup","AXLandmarkNavigation"].contains(role($0)) && ["sidebar","侧边栏"].contains(WebUsagePage.normalized(label($0))) },"请先展开 Claude 网页侧栏，再读取额度。")
        return try one(find(sidebar) { node in
            guard role(node) == "AXPopUpButton" else { return false }
            let name = WebUsagePage.normalized(label(node))
            return name.range(of:#"\s(pro|max|free|team|enterprise)$"#,options:.regularExpression) != nil || ["account menu","账户菜单","帐号菜单"].contains(name)
        },"无法唯一定位侧栏账户菜单，请在当前网页重试。")
    }
    private static func menu(_ selected: WebUsageSelection) throws -> AXUIElement? {
        let popup = try accountPopup(selected), name = label(popup)
        let menus = try find(try page(selected)) { role($0) == "AXMenu" && label($0) == name }
        return menus.count == 1 ? menus.first : nil
    }
    static func account(_ selected: WebUsageSelection) async throws -> UsageAccountIdentity {
        try await closeUsage(selected)
        guard !WebUsagePage.isOtherSettings(url(try page(selected))) else { throw BridgeError.message("账户核对期间页面发生变化。") }
        if try menu(selected) == nil { try press(accountPopup(selected)) }
        let scoped: AXUIElement = try await wait(selected) { try menu(selected) }
        var lines: [String] = [], visited = 0
        let deadline = Date().addingTimeInterval(1.5)
        @MainActor func collect(_ node: AXUIElement, _ depth: Int) throws {
            guard Date() < deadline, depth < 8, visited < 100 else { throw ClaudeUsageError.malformed }; visited += 1
            if role(node) == "AXStaticText" { lines.append(label(node)); return }
            for child in children(node) { try collect(child,depth+1) }
        }
        try collect(scoped,0)
        return try WebUsagePage.identity(lines)
    }
    private static func usageSection(_ selected: WebUsageSelection) throws -> AXUIElement? {
        let area = try page(selected)
        guard WebUsagePage.isUsageURL(url(area)), let modal = try settings(area) else { return nil }
        let sections = try find(modal) { node in
            guard role(node) == "AXGroup" else { return false }
            return children(node).contains { role($0) == "AXHeading" && ["your usage","usage","您的使用量","你的使用量","使用量","用量"].contains(WebUsagePage.normalized(label($0))) }
        }
        return sections.count == 1 ? sections.first : nil
    }
    private static func openUsage(_ selected: WebUsageSelection) async throws -> AXUIElement {
        guard let scoped = try menu(selected) else { throw BridgeError.message("当前账户菜单已关闭，请重试额度读取。") }
        let entry = try one(find(scoped) { ["AXMenuItem","AXButton"].contains(role($0)) && ["usage","使用量","用量"].contains(WebUsagePage.normalized(label($0))) },"账户菜单没有唯一 Usage 入口。")
        try press(entry)
        return try await wait(selected) { try usageSection(selected) }
    }
    static func quota(_ selected: WebUsageSelection) async throws -> ClaudeUsageSnapshot {
        let scoped = try await openUsage(selected)
        // Refresh is a read-only UI action. Paid-credit controls are excluded.
        let refresh = try find(scoped) { role($0) == "AXButton" && ["refresh","重新整理","刷新"].contains(WebUsagePage.normalized(label($0))) }
        if refresh.count == 1 { try press(refresh[0]) }
        return try await wait(selected) {
            // Refresh may replace the AX subtree. Resolve it anew on every
            // probe rather than waiting forever on a retired section node.
            guard let scoped = try usageSection(selected) else { return nil }
            var items: [WebUsagePage.Item] = [], visited = 0
            let deadline = Date().addingTimeInterval(1.5)
            @MainActor func collect(_ node: AXUIElement, _ depth: Int) throws {
                guard Date() < deadline, depth < 30, visited < 1000 else { throw ClaudeUsageError.malformed }; visited += 1
                let type = role(node)
                if ["AXTextArea","AXTextField"].contains(type) { return }
                if type == "AXStaticText" { items.append(.init(label(node))); return }
                if type == "AXLevelIndicator" || type == "AXProgressIndicator" {
                    items.append(.init(label(node),number:(value(node,kAXValueAttribute) as? NSNumber)?.doubleValue)); return
                }
                for child in children(node) { try collect(child,depth+1) }
            }
            try collect(scoped,0)
            do { return try WebUsagePage.parse(items) }
            catch ClaudeUsageError.unavailable { return nil }
        }
    }
    private static func baseURL(_ raw: String) -> String? {
        guard var parts = URLComponents(string:raw) else { return nil }
        parts.fragment = nil; parts.query = nil; return parts.string
    }
    static func restore(_ selected: WebUsageSelection, _ state: NativeWebUsage.PageState) async throws {
        try current(selected)
        if state.wasUsage {
            if !WebUsagePage.isUsageURL(url(try page(selected))) {
                if try menu(selected) == nil { _ = try await account(selected) }
                _ = try await openUsage(selected)
            }
        } else {
            try await closeUsage(selected)
            if try menu(selected) != nil { try press(accountPopup(selected)) }
            guard baseURL(url(try page(selected))) == baseURL(state.url) else { throw BridgeError.message("Usage 已关闭，但原会话未恢复，请返回原会话再重试。") }
            if let input = selected.input { AXUIElementSetAttributeValue(input,kAXFocusedAttribute as CFString,kCFBooleanTrue) }
        }
        try current(selected)
    }
}
