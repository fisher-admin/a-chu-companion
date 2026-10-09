import Foundation

@main struct ManagedWebTests {
    static var count = 0, failures = 0
    @MainActor static func check(_ value: Bool, _ label: String) {
        count += 1; if !value { failures += 1 }; print((value ? "PASS: " : "FAIL: ") + label)
    }
    @MainActor static func main() async throws {
        check(ManagedWebUsage.installationBrowser(bound:nil,available:["com.google.Chrome"]) == "com.google.Chrome", "a sole installed runtime can prepare authorization before input binding")
        check(ManagedWebUsage.installationBrowser(bound:nil,available:["com.google.Chrome","com.microsoft.edgemac"]) == nil, "multiple runtime carriers are never guessed")
        check(ManagedWebUsage.installationBrowser(bound:"com.microsoft.edgemac",available:["com.google.Chrome"]) == nil, "authorization does not substitute another browser for the user-selected carrier")
        var event: [String: Any] = ["kind":"usage", "binding":"web-synthetic", "url":"https://claude.ai/code/session_test123", "epoch":"synthetic-epoch", "sequence":5,
                                    "account":["fingerprint":String(repeating:"a", count:64),"displayName":"a***@example.test"],
                                    "usage":["rate_limits":["five_hour":["used_percentage":17,"resets_at":1900000000]]]]
        let evidence = try ManagedWebUsage.evidence(event)
        check(evidence.source == .usagePage && evidence.snapshot.fiveHour?.usedPercentage == 17, "managed Web source produces its own quota evidence")
        check(evidence.identity?.displayName == "a***@example.test", "only masked identity reaches the monitor")
        for change: [String: Any] in [["url":"https://claude.ai.evil.example/chat/test"], ["binding":"cli-synthetic"], ["sequence":true], ["cookie":"forbidden"], ["account":["fingerprint":String(repeating:"a",count:64),"displayName":"full@example.test"]]] {
            var invalid = event; for (key, value) in change { invalid[key] = value }
            do { _ = try ManagedWebUsage.evidence(invalid); check(false, "invalid managed report rejected") }
            catch { check(true, "invalid managed report rejected") }
        }
        let suite = "local.achu.managed-web-test." + UUID().uuidString
        let settings = UserDefaults(suiteName:suite)!
        defer { settings.removePersistentDomain(forName:suite) }
        let monitor = ClaudeUsageMonitor(settings:settings, enabled:{true})
        defer { monitor.stop() }
        monitor.follow(channel:.web,binding:"web-synthetic")
        monitor.receive(evidence)
        check(monitor.snapshot?.fiveHour?.usedPercentage == 17, "verified focused binding publishes quota without borrowing Desktop")
        event["epoch"] = "synthetic-second-account"; event["sequence"] = 6
        event["account"] = ["fingerprint":String(repeating:"b",count:64),"displayName":"b***@example.test"]
        monitor.receive(try ManagedWebUsage.evidence(event))
        check(monitor.accountDisplayName == "b***@example.test", "account switch follows fresh evidence epoch")
        event["epoch"] = "synthetic-return-account"; event["sequence"] = 7
        event["account"] = ["fingerprint":String(repeating:"a",count:64),"displayName":"a***@example.test"]
        monitor.receive(try ManagedWebUsage.evidence(event))
        check(monitor.accountDisplayName == "a***@example.test", "returning to a previously used account is valid under a new epoch")
        monitor.receiveAccount(.init(source:.usagePage,binding:"web-synthetic",epoch:"synthetic-return-account",sequence:8,identity:nil))
        check(monitor.snapshot == nil, "failed current account read withdraws quota")
        print("\(count) managed Web checks; \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
