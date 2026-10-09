import Foundation
import CoreFoundation

@main struct NativeUsageParserTests {
    static var checks = 0, failures = 0
    static func check(_ value: Bool, _ label: String) {
        checks += 1; if !value { failures += 1 }; print((value ? "PASS: " : "FAIL: ") + label)
    }
    static func main() throws {
        let location = "https://claude.ai/new#settings/usage"
        let representations: [CFTypeRef] = [location as NSString, URL(string:location)! as NSURL,
            CFURLCreateWithString(nil,location as CFString,nil)!]
        for raw in representations {
            check(WebUsagePage.urlString(raw) == location,"public URL and string representations retain the official URL")
        }
        check(WebUsagePage.urlString(nil).isEmpty && WebUsagePage.urlString(NSNumber(value:12)).isEmpty,
              "missing and unrelated attributes cannot supply a URL by description")
        check(!WebUsagePage.official(WebUsagePage.urlString("not a URL" as NSString)),"invalid string representations remain rejected")
        let traditional = ["您的使用量", "目前工作階段", "從您的第一則訊息開始", "已使用 0%", "本週", "星期五下午2:00 重設", "已使用 34%", "使用量額度", "本週各產品使用量", "Claude Code", "已使用 40%"]
        let value = try? VisibleUsageParser.parse(traditional, binding:"web-native-fixture", source:.usagePage)
        check(value?.snapshot.fiveHour?.usedPercentage == 0, "Traditional current session preserves reported zero")
        check(value?.snapshot.sevenDay?.usedPercentage == 34, "used-before-percent maps the week without product shares")
        check(value?.snapshot.sevenDay?.resetDescription == "星期五下午2:00 重設", "original reset description survives normalization")
        let items: [WebUsagePage.Item] = [.init("Pro"), .init("目前工作階段"), .init("從您的第一則訊息開始"), .init("目前工作階段", number:0), .init("已使用 0%"), .init("本週"), .init("星期五下午2:00 重設"), .init("本週", number:34), .init("已使用 34%"), .init("使用量額度"), .init("已使用 99%"), .init("本週各產品使用量"), .init("Claude Code", number:40)]
        let parsed = try WebUsagePage.parse(items)
        check(parsed.reportedPlan == .pro,"plan comes from the scoped Usage label rather than quota assumptions")
        let max = try WebUsagePage.parse([.init("Max"),.init("Current session"),.init("12% used"),.init("This week"),.init("34% used")])
        check(max.reportedPlan == .max && max.fiveHour?.usedPercentage == 12,"reported five-hour quota is preserved even when the plan is Max")
        check(parsed.fiveHour?.usedPercentage == 0 && parsed.sevenDay?.usedPercentage == 34, "level indicators and matching text do not duplicate or mix product allocations")
        check(parsed.fiveHour?.resetDescription == "從您的第一則訊息開始", "inactive session keeps the actual start description")
        let credits = try? WebUsagePage.parse([.init("This week"),.init("This week",number:34),.init("34% used"),
            .init("Cloud session credits"),.init("Included credit",number:2),.init("$98 of $100 left")])
        check(credits?.sevenDay?.usedPercentage == 34,"cloud session credit indicators are not subscription usage even without the optional reset section")
        for lines in [["Current session","12% used","This week","34% used"], ["当前会话","已使用12%","本周","34% 已使用"]] {
            let snapshot = try WebUsagePage.parse(lines.map { .init($0) })
            check(snapshot.fiveHour?.usedPercentage == 12 && snapshot.sevenDay?.usedPercentage == 34, "English and Simplified text fallback works")
        }
        for invalid: [WebUsagePage.Item] in [[.init("Current session"),.init("Current session",number:12),.init("13% used")], [.init("This week"),.init("101% used")], [.init("This week"),.init("This week",number:12),.init("101% used")], [.init("This week"),.init("This week",number:12),.init("12% used"),.init("12% used")], [.init("Current session"),.init("-1% used")], [.init("This week's usage by product"),.init("Claude Code",number:23)], [.init("Current session"),.init("23% remaining")]] {
            do { _ = try WebUsagePage.parse(invalid); check(false,"conflicting, invalid, remaining and product-only values are rejected") }
            catch { check(true,"conflicting, invalid, remaining and product-only values are rejected") }
        }
        let account = try WebUsagePage.identity(["reader@example.test"])
        check(account.valid && account.displayName == "r***@example.test" && !account.fingerprint.contains("reader"), "only hash and masked account leave the scoped menu")
        for invalid in [[], ["nickname Pro"], ["a@example.test","b@example.test"], ["A message with a@example.test inside"]] {
            do { _ = try WebUsagePage.identity(invalid); check(false,"unknown or ambiguous account menu is rejected") }
            catch { check(true,"unknown or ambiguous account menu is rejected") }
        }
        check(WebUsagePage.isUsageURL("https://claude.ai/new#settings/usage") && WebUsagePage.isUsageURL("https://claude.ai/settings/usage"), "both official Usage routes are accepted")
        for url in ["https://claude.ai.evil.test/new#settings/usage","https://claude.ai/chat/test","https://user@claude.ai/new#settings/usage","http://claude.ai/new#settings/usage"] {
            check(!WebUsagePage.isUsageURL(url), "a chat title or deceptive origin cannot impersonate Usage")
        }
        print("\(checks) native Usage parser checks; \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
