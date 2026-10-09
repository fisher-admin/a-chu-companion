import Foundation
import CryptoKit
import CoreFoundation

/// Only items from the official Usage section or its scoped account menu.
enum WebUsagePage {
    struct Item {
        let label: String
        let number: Double?
        init(_ label: String, number: Double? = nil) { self.label = label; self.number = number }
    }
    // AXURL can be a URL object or a string, depending on the browser. Never
    // infer a location from an unrelated object's textual description.
    static func urlString(_ raw: CFTypeRef?) -> String {
        guard let raw else { return "" }
        if CFGetTypeID(raw) == CFURLGetTypeID() {
            return CFURLGetString(unsafeBitCast(raw,to:CFURL.self)) as String
        }
        return (raw as? String) ?? ""
    }
    static func normalized(_ text: String) -> String {
        (text.applyingTransform(StringTransform("Hant-Hans"), reverse:false) ?? text).lowercased().trimmingCharacters(in:.whitespacesAndNewlines)
    }
    static func official(_ raw: String) -> Bool {
        guard let url = URLComponents(string:raw) else { return false }
        return url.scheme == "https" && url.host == "claude.ai" && url.port == nil && url.user == nil && url.password == nil
    }
    static func isUsageURL(_ raw: String) -> Bool {
        guard official(raw), let url = URLComponents(string:raw) else { return false }
        return url.path == "/settings/usage" || url.fragment == "settings/usage"
    }
    static func isOtherSettings(_ raw: String) -> Bool {
        guard let url = URLComponents(string:raw) else { return false }
        return !isUsageURL(raw) && (url.path.hasPrefix("/settings/") || url.fragment?.hasPrefix("settings/") == true)
    }
    static func identity(_ lines: [String]) throws -> UsageAccountIdentity {
        guard lines.count <= 100 else { throw ClaudeUsageError.malformed }
        let values = Set(lines.map { $0.trimmingCharacters(in:.whitespacesAndNewlines).lowercased() }
            .filter { $0.count <= 254 && $0.range(of:#"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options:.regularExpression) != nil })
        guard values.count == 1, let email = values.first else { throw BridgeError.message("当前网页账户无法唯一识别，旧额度已隐藏。") }
        let components = email.split(separator:"@")
        let label = String(components[0].prefix(1)) + "***@" + components[1]
        guard label.count <= 80 else { throw ClaudeUsageError.malformed }
        let fingerprint = SHA256.hash(data:Data(("achu-native-web-account\0" + email).utf8)).map { String(format:"%02x",$0) }.joined()
        return .init(fingerprint:fingerprint,displayName:label)
    }
    static func parse(_ items: [Item], at: Date = Date()) throws -> ClaudeUsageSnapshot {
        guard items.count <= 1000, items.map(\.label).joined().count <= 100_000 else { throw ClaudeUsageError.malformed }
        var section: String?, groups: [String:[String]] = [:], levels: [String:Double] = [:]
        for item in items {
            let label = normalized(item.label)
            if label.contains("usage by product") || label.contains("各产品使用量") || ["usage credits","extra usage","cloud session credits","limit resets","使用量额度","额度重置"].contains(label) {
                section = nil; continue
            }
            if ["current session","当前会话","本次会话","目前工作阶段"].contains(label) { section = "five" }
            else if ["this week","weekly limits","all models","本周","每周限额","所有模型"].contains(label) { section = "seven" }
            else if label.contains("sonnet") || label.contains("opus") || label.contains("fable") { section = nil }
            guard let section else { continue }
            if let number = item.number {
                guard number.isFinite, (0...100).contains(number), levels[section] == nil else { throw ClaudeUsageError.malformed }
                levels[section] = number
            } else { groups[section,default:[]].append(item.label) }
        }
        var windows: [String:ClaudeUsageWindow] = [:]
        for section in ["five","seven"] {
            let heading = section == "five" ? "Current session" : "This week"
            let lines = [heading] + (groups[section] ?? [])
            var textValue: ClaudeUsageSnapshot?
            do { textValue = try VisibleUsageParser.parse(lines,binding:"web-native-parser",source:.usagePage,at:at).snapshot }
            catch ClaudeUsageError.unavailable { /* A numeric AX level may be the only percentage. */ }
            catch { throw error }
            let candidate = section == "five" ? textValue?.fiveHour : textValue?.sevenDay
            if let level = levels[section] {
                if let candidate, candidate.usedPercentage != level { throw ClaudeUsageError.malformed }
                let reset = candidate?.resetDescription ?? lines.first { let value = normalized($0); return value.hasPrefix("resets") || value.contains("重设") || value.contains("重置") || value.contains("first message") || value.contains("第一则讯息") }
                windows[section] = .init(usedPercentage:level,resetsAt:nil,resetDescription:reset)
            } else if let candidate { windows[section] = candidate }
        }
        guard !windows.isEmpty else { throw ClaudeUsageError.unavailable }
        let plans = Set(items.map { normalized($0.label) }.filter { ["pro","max","team","enterprise","free"].contains($0) })
        let plan = plans.count == 1 ? ClaudePlan.allReportedPlans.first { normalized($0.rawValue) == plans.first } : nil
        return .init(fiveHour:windows["five"],sevenDay:windows["seven"],observedAt:at,reportedPlan:plan)
    }
}
