import Foundation
import AppKit
import ApplicationServices

enum UsageEvidenceSource: String, Codable, CaseIterable, Sendable {
    case usageAX, usagePage, statusLine
    var name: String { switch self { case .usageAX: return "桌面可见 Usage"; case .usagePage: return "网页可见 Usage"; case .statusLine: return "CLI statusLine" } }
}
struct UsageAccountIdentity: Codable, Equatable, Sendable {
    let fingerprint: String
    let displayName: String
    var valid: Bool {
        fingerprint.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil
            && !displayName.isEmpty && displayName.count <= 80
            && !displayName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}
struct UsageAccountObservation: Equatable, Sendable {
    let source: UsageEvidenceSource
    let binding: String
    let epoch: String
    let sequence: Int
    let identity: UsageAccountIdentity?
}
struct UsageEvidence: Equatable, Sendable {
    let source: UsageEvidenceSource
    let binding: String
    let snapshot: ClaudeUsageSnapshot
    var identity: UsageAccountIdentity? = nil
    var epoch: String = ""
    var sequence: Int = 0
    var pageURL: String? = nil
    var accountObservation: UsageAccountObservation {
        .init(source: source, binding: binding, epoch: epoch, sequence: sequence, identity: identity)
    }
    static func statusLine(_ data: Data, binding: String, at: Date = Date()) throws -> Self {
        struct Window: Decodable { let used_percentage: Double?; let resets_at: Double?; let reset_description: String? }
        struct Limits: Decodable { let five_hour: Window?; let seven_day: Window? }
        struct Input: Decodable { let rate_limits: Limits? }
        guard data.count <= 65_536, let input = try? JSONDecoder().decode(Input.self, from: data) else { throw ClaudeUsageError.malformed }
        func window(_ value: Window?) throws -> ClaudeUsageWindow? {
            guard let percent = value?.used_percentage else { return nil }
            guard percent.isFinite, (0...100).contains(percent) else { throw ClaudeUsageError.malformed }
            let reset = value?.resets_at.map { Date(timeIntervalSince1970: $0) }
            return .init(usedPercentage: percent, resetsAt: reset, resetDescription: value?.reset_description.map { String($0.prefix(160)) })
        }
        let five = try window(input.rate_limits?.five_hour), seven = try window(input.rate_limits?.seven_day)
        guard five != nil || seven != nil else { throw ClaudeUsageError.unavailable }
        return .init(source: .statusLine, binding: binding, snapshot: .init(fiveHour: five, sevenDay: seven, observedAt: at))
    }
    var contentSignature: String {
        func window(_ value: ClaudeUsageWindow?) -> String { value.map { "\($0.usedPercentage):\($0.resetsAt?.timeIntervalSince1970 ?? -1):\($0.resetDescription ?? "")" } ?? "absent" }
        return binding + ":" + window(snapshot.fiveHour) + ":" + window(snapshot.sevenDay)
    }
}

enum VisibleUsageParser {
    static func parse(_ lines: [String], binding: String, source: UsageEvidenceSource, at: Date = Date()) throws -> UsageEvidence {
        guard lines.count <= 2_000, lines.joined().count <= 100_000 else { throw ClaudeUsageError.malformed }
        var window: String?; var pendingReset: String?; var values: [String: ClaudeUsageWindow] = [:]
        let regex = try NSRegularExpression(pattern: #"([0-9]+(?:\.[0-9]+)?)\s*%\s*(?:used|已用|已使用|已使用量)"#, options: [.caseInsensitive])
        for raw in lines {
            let line = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            var nextWindow = window
            if ["limit resets", "usage credits", "extra usage", "额度重置"].contains(line) || line.contains("usage by product") { nextWindow = nil }
            else if ["current session", "当前会话", "本次会话", "5小时", "5 小时"].contains(where: { line.contains($0) }) { nextWindow = "five" }
            else if ["this week", "本周"].contains(line) || ["weekly limits", "all models", "每周", "所有模型"].contains(where: { line.contains($0) }) { nextWindow = "seven" }
            else if line.contains("sonnet") || line.contains("opus") { nextWindow = nil }
            if nextWindow != window { window = nextWindow; pendingReset = nil }
            if let window, line.hasPrefix("resets") || line.contains("重置") {
                pendingReset = String(raw.prefix(160))
                if let current = values[window] { values[window] = .init(usedPercentage: current.usedPercentage, resetsAt: current.resetsAt, resetDescription: pendingReset) }
                continue
            }
            guard let window, let match = regex.firstMatch(in: raw, range: NSRange(location: 0, length: (raw as NSString).length)),
                  let percent = Double((raw as NSString).substring(with: match.range(at: 1))), (0...100).contains(percent) else { continue }
            guard values[window] == nil else { throw ClaudeUsageError.malformed }
            values[window] = .init(usedPercentage: percent, resetsAt: nil, resetDescription: pendingReset)
        }
        guard !values.isEmpty else { throw ClaudeUsageError.unavailable }
        return .init(source: source, binding: binding, snapshot: .init(fiveHour: values["five"], sevenDay: values["seven"], observedAt: at))
    }
}

/// Reads only the already open Usage interface; never navigates or decrypts credentials.
enum VisibleUsageAccessibility {
    static func capture() throws -> UsageEvidence {
        guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.anthropic.claudefordesktop").first else { throw ClaudeUsageError.desktopMissing }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var lines: [String] = []; var visited = 0
        let deadline = Date().addingTimeInterval(2)
        func attribute(_ element: AXUIElement, _ name: String) -> Any? {
            var value: CFTypeRef?; AXUIElementCopyAttributeValue(element, name as CFString, &value); return value
        }
        func walk(_ element: AXUIElement, _ depth: Int) throws {
            guard Date() < deadline, visited < 2_000, depth < 30 else { throw ClaudeUsageError.unavailable }
            visited += 1; AXUIElementSetMessagingTimeout(element, 0.05)
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            if ["AXTextArea", "AXTextField"].contains(role) { return }
            if role == "AXStaticText", let text = attribute(element, kAXValueAttribute) as? String { lines.append(text) }
            for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] { try walk(child, depth + 1) }
        }
        func usageRoot(_ element: AXUIElement, _ depth: Int) throws -> AXUIElement? {
            guard Date() < deadline, visited < 2_000, depth < 25 else { throw ClaudeUsageError.unavailable }
            visited += 1; AXUIElementSetMessagingTimeout(element, 0.05)
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            if ["AXTextArea", "AXTextField", "AXStaticText"].contains(role) { return nil }
            let names = [attribute(element, kAXTitleAttribute), attribute(element, kAXDescriptionAttribute)].compactMap { $0 as? String }.map { $0.lowercased() }
            if ["AXGroup", "AXWindow", "AXScrollArea"].contains(role), names.contains(where: { ["usage", "用量", "使用量"].contains($0) }) { return element }
            let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            for child in children {
                if attribute(child, kAXRoleAttribute) as? String == "AXHeading",
                   let name = (attribute(child, kAXTitleAttribute) as? String ?? attribute(child, kAXValueAttribute) as? String)?.lowercased(),
                   ["usage", "用量", "使用量"].contains(name), role == "AXGroup" { return element }
            }
            for child in children { if let found = try usageRoot(child, depth + 1) { return found } }
            return nil
        }
        guard let scoped = try usageRoot(root, 0) else { throw ClaudeUsageError.unavailable }
        visited = 0; try walk(scoped, 0)
        return try VisibleUsageParser.parse(lines, binding: "desktop-visible", source: .usageAX)
    }
}
