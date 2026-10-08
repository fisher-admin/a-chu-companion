import Foundation

@main struct WebUsageSetupTests {
    static var count = 0, failures = 0
    @MainActor static func check(_ value: Bool, _ label: String) {
        count += 1; if !value { failures += 1 }; print((value ? "PASS: " : "FAIL: ") + label)
    }
    @MainActor static func main() async throws {
        let suite = "local.achu.web-setup-test." + UUID().uuidString
        let settings = UserDefaults(suiteName: suite)!
        defer { settings.removePersistentDomain(forName: suite) }
        let monitor = ClaudeUsageMonitor(settings: settings, enabled: { true })
        defer { monitor.stop() }
        monitor.requestReport = { _, _, _ in throw BridgeError.message("网页额度入口未配置，请在连接额度中配置网页入口。") }
        monitor.follow(channel: .web, pageURL: "https://claude.ai/chat/synthetic")
        monitor.acquire(.web, pageURL: "https://claude.ai/chat/synthetic")
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while monitor.acquiring && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(2)) }
        check(monitor.status.contains("网页额度入口未配置"), "the main quota display exposes missing setup instead of claiming it is still checking")
        check(!monitor.acquiring && monitor.snapshot == nil && monitor.channel == .web, "missing Web setup never borrows Desktop quota")
        var pending: CheckedContinuation<Void, Error>?
        monitor.requestReport = { _, _, _ in try await withCheckedThrowingContinuation { pending = $0 } }
        monitor.acquire(.web, pageURL: "https://claude.ai/chat/synthetic")
        while pending == nil { try await Task.sleep(for: .milliseconds(2)) }
        monitor.follow(channel: .cli, binding: "cli-synthetic-current")
        let current = monitor.status
        pending?.resume(throwing: BridgeError.message("Synthetic old Web setup failure")); pending = nil
        try await Task.sleep(for: .milliseconds(20))
        check(monitor.channel == .cli && monitor.status == current, "a late Web setup failure cannot replace the current CLI status")
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("achu-web-setup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: support) }
        check(UsageAcquisition.webSetupError(bundle: "com.google.Chrome", supportDirectory: support)?.contains("未配置") == true, "missing browser host is diagnosed without reading login data")
        let host = support.appendingPathComponent("Google/Chrome/NativeMessagingHosts/local.achu.companion.json")
        try FileManager.default.createDirectory(at: host.deletingLastPathComponent(), withIntermediateDirectories: true)
        let launcher = support.appendingPathComponent("synthetic-launcher")
        try Data("synthetic test only".utf8).write(to: launcher)
        let valid: [String: Any] = ["name": "local.achu.companion", "type": "stdio", "path": launcher.path, "allowed_origins": ["chrome-extension://" + String(repeating: "a", count: 32) + "/"]]
        try JSONSerialization.data(withJSONObject: valid).write(to: host)
        check(UsageAcquisition.webSetupError(bundle: "com.google.Chrome", supportDirectory: support) == nil, "configured current browser can request its own usage")
        check(UsageAcquisition.webSetupError(bundle: "com.microsoft.edgemac", supportDirectory: support)?.contains("未配置") == true, "another browser's setup is not substituted for the current browser")
        check(UsageAcquisition.webSetupError(bundle: nil, supportDirectory: support) == nil, "settings can prepare acquisition before a browser is bound")
        check(UsageAcquisition.webSetupError(bundle: "com.apple.Safari", supportDirectory: support)?.contains("尚未提供") == true, "an unsupported quota adapter does not imply sending or reading is unsupported")
        for change in [["allowed_origins": []], ["path": support.appendingPathComponent("missing").path], ["name": "other.host"]] as [[String: Any]] {
            var invalid = valid; for (key, value) in change { invalid[key] = value }
            try JSONSerialization.data(withJSONObject: invalid).write(to: host)
            check(UsageAcquisition.webSetupError(bundle: "com.google.Chrome", supportDirectory: support)?.contains("失效") == true, "invalid host setup is reported without modifying browser permissions")
        }
        print("\(count) web usage setup checks; \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
