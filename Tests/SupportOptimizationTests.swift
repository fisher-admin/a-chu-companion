import Foundation

@main struct SupportOptimizationTests {
    @MainActor static func main() async throws {
        let payload = Data(#"{"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1800000000},"seven_day":{"used_percentage":41.2,"resets_at":1800500000}}}"#.utf8)
        let value = try UsageEvidence.statusLine(payload, binding: "cli-one", at: Date(timeIntervalSince1970: 100))
        precondition(value.snapshot.fiveHour?.usedPercentage == 23.5 && value.snapshot.sevenDay?.usedPercentage == 41.2)
        let missing = try UsageEvidence.statusLine(Data(#"{"rate_limits":{"seven_day":{"used_percentage":0}}}"#.utf8), binding: "cli-one", at: Date())
        precondition(missing.snapshot.fiveHour == nil && missing.snapshot.sevenDay?.usedPercentage == 0)
        print("PASS: official statusLine windows decode independently without guessing plan or account")
        let parsed = try VisibleUsageParser.parse(["Current session", "23% used", "Weekly limits", "All models", "41% used"], binding: "page-one", source: .usagePage, at: Date())
        precondition(parsed.snapshot.fiveHour?.usedPercentage == 23 && parsed.snapshot.sevenDay?.usedPercentage == 41)
        print("PASS: visible usage labels map to subscription windows")
        let current = try VisibleUsageParser.parse(["Current session", "Resets at 5:00 AM", "12% used", "This week", "Resets Friday 2:00 PM", "34% used", "Limit resets", "This week’s usage by product", "Claude Code", "15% used"], binding: "current-page", source: .usagePage)
        precondition(current.snapshot.fiveHour?.usedPercentage == 12 && current.snapshot.sevenDay?.usedPercentage == 34)
        precondition(current.snapshot.fiveHour?.resetDescription == "Resets at 5:00 AM" && current.snapshot.sevenDay?.resetDescription == "Resets Friday 2:00 PM")
        do { _ = try VisibleUsageParser.parse(["This week’s usage by product", "Claude Code", "15% used"], binding: "products-only", source: .usagePage); fatalError("product shares are not subscription usage") } catch {}
        print("PASS: current Usage headings keep preceding resets and exclude product shares")
        do { _ = try VisibleUsageParser.parse(["Current session", "23% remaining"], binding: "page-one", source: .usagePage, at: Date()); fatalError("remaining must not be treated as used") } catch {}
        let center = HealthCenter()
        var calls = 0
        await center.check(key: "settings", now: 0) { calls += 1; return [.init(name: "翻译", state: .unconfigured, detail: "尚未配置")] }
        await center.check(key: "settings", now: 1) { calls += 1; return [] }
        precondition(calls == 1 && center.items.first?.state == .unconfigured)
        await center.check(key: "new-settings", now: 2) { calls += 1; return [.init(name: "权限", state: .ready, detail: "可用")] }
        precondition(calls == 2)
        print("PASS: passive health caches repeated opens and invalidates changed configuration")
        print("5 support optimization contracts passed")
    }
}
