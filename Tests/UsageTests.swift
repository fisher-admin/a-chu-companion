import Foundation

@main struct UsageTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let value = try ClaudeUsageSnapshot.decode(Data("""
        {"five_hour":{"utilization":79,"resets_at":"2027-01-16T10:30:00Z"},"seven_day":{"utilization":13,"resets_at":"2027-01-22T22:00:00.000Z"},"seven_day_sonnet":{"utilization":99,"resets_at":null}}
        """.utf8), at: now)
        precondition(value.fiveHour?.usedPercentage == 79 && value.sevenDay?.usedPercentage == 13)
        precondition(value.fiveHour?.resetsAt != nil && value.sevenDay?.resetsAt != nil)
        print("PASS: both windows preserve exact reset timestamps without mixing model-specific limits")
        let zero = try ClaudeUsageSnapshot.decode(Data("{\"five_hour\":{\"utilization\":0,\"resets_at\":null},\"seven_day\":null}".utf8), at: now)
        precondition(zero.fiveHour?.usedPercentage == 0 && zero.sevenDay == nil && zero.fiveHour?.resetsAt == nil)
        print("PASS: a reported zero differs from missing data")
        for percent in ["-1", "101", "\"79\"", "true"] {
            do {
                _ = try ClaudeUsageSnapshot.decode(Data("{\"five_hour\":{\"utilization\":\(percent),\"resets_at\":null}}".utf8), at: now)
                preconditionFailure("Invalid percentage accepted")
            } catch {}
        }
        for json in ["{}", "{\"five_hour\":{\"utilization\":79,\"resets_at\":\"bad-date\"}}"] {
            do { _ = try ClaudeUsageSnapshot.decode(Data(json.utf8), at: now); preconditionFailure("Invalid data accepted") } catch {}
        }
        print("PASS: malformed data is refused instead of becoming zero")
        let modern = try ClaudeUsageSnapshot.decode(Data("""
        {"limits":[{"kind":"session","group":"session","percent":22.5,"resets_at":"2027-01-16T10:30:00Z"},{"kind":"weekly_all","group":"weekly","percent":14,"resets_at":null},{"kind":"weekly_model","group":"weekly","percent":98}],"five_hour":{"utilization":80,"resets_at":null}}
        """.utf8), at: now)
        precondition(modern.fiveHour?.usedPercentage == 22.5 && modern.sevenDay?.usedPercentage == 14)
        print("PASS: current Desktop rows override legacy fields")
        precondition(!value.isStale(at: now.addingTimeInterval(10)) && value.isStale(at: now.addingTimeInterval(601)))
        print("PASS: old readings become stale")
        let org = "12345678-1234-1234-1234-123456789abc"
        let request = try ClaudeUsageRequest.make(sessionKey: "sk-ant-sid01-testonlyabcdefghijklmnop", organization: org)
        precondition(request.url?.absoluteString == "https://claude.ai/api/organizations/\(org)/usage?skip_spend=1")
        precondition(request.httpMethod == "GET" && request.httpBody == nil && request.cachePolicy == .reloadIgnoringLocalCacheData)
        for secret in ["", "sk-ant-api03-testapikey", "bad;cookie=1", "bad\r\nheader:value"] {
            do { _ = try ClaudeUsageRequest.make(sessionKey: secret, organization: org); preconditionFailure("Invalid credential accepted") } catch {}
        }
        do { _ = try ClaudeUsageRequest.make(sessionKey: "sk-ant-sid01-testonlyabcdefghijklmnop", organization: "../billing"); preconditionFailure() } catch {}
        print("PASS: only the verified read-only endpoint receives a valid session credential")
        let resetDate = ISO8601DateFormatter().date(from: "2026-10-09T21:00:00Z")!
        precondition(ClaudeUsageDisplay.resetTime(resetDate, timeZone: TimeZone(identifier: "America/Los_Angeles")!) == "10/09 14:00")
        precondition(ClaudeUsageDisplay.resetTime(resetDate, timeZone: TimeZone(secondsFromGMT: 0)!) == "10/09 21:00")
        precondition(ClaudeUsageDisplay.resetTime(resetDate, timeZone: TimeZone(identifier: "Asia/Shanghai")!) == "10/10 05:00")
        print("PASS: reset times use an explicit 24-hour clock and the correct local date")
        let boundary = try ClaudeUsageSnapshot.decode(Data("{\"seven_day\":{\"utilization\":13,\"resets_at\":\"2026-10-09T20:59:59.851728+00:00\"}}".utf8), at: now).sevenDay!.resetsAt!
        precondition(ClaudeUsageDisplay.resetTime(boundary, timeZone: TimeZone(identifier: "America/Los_Angeles")!) == "10/09 14:00")
        precondition(ClaudeUsageDisplay.resetTime(resetDate.addingTimeInterval(-35), timeZone: TimeZone(identifier: "America/Los_Angeles")!) == "10/09 13:59")
        let midnight = ISO8601DateFormatter().date(from: "2026-10-09T23:59:40Z")!
        precondition(ClaudeUsageDisplay.resetTime(midnight, timeZone: TimeZone(secondsFromGMT: 0)!) == "10/10 00:00")
        precondition(boundary < resetDate, "Formatting must not change the underlying reset date")
        print("PASS: minute precision rounds boundary seconds without changing reset data")
        print("8 usage tests passed")
    }
}
