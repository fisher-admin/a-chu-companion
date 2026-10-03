import Foundation

@main struct CheckClaudeUsage {
    static func main() async {
        guard CommandLine.arguments.contains("--desktop-live") else {
            print("Pass --desktop-live to perform an explicit read-only Claude Desktop usage check."); return
        }
        do {
            let connection = try ClaudeDesktopSession.read()
            let client = ClaudeUsageClient(); defer { client.cancel() }
            let (value, plan) = try await client.fetch(connection)
            print("Plan: \(plan.rawValue)")
            for (name, window) in [("five-hour", value.fiveHour),("weekly",value.sevenDay)] {
                if let window { print("\(name): used=\(window.usedPercentage)%, reset=\(window.resetsAt?.ISO8601Format() ?? "not provided")") }
                else { print("\(name): not provided") }
            }
            if CommandLine.arguments.contains("--reset-details") {
                let request = try ClaudeUsageRequest.make(sessionKey: connection.key, organization: connection.organization)
                let data = try await client.data(request)
                if let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    for name in ["five_hour", "seven_day"] {
                        if let field = fields[name] as? [String: Any], let reset = field["resets_at"] as? String { print("\(name) raw reset: \(reset)") }
                    }
                    if let limits = fields["limits"] as? [[String: Any]] {
                        for field in limits {
                            guard let kind = field["kind"] as? String, ["session", "weekly_all"].contains(kind), let reset = field["resets_at"] as? String else { continue }
                            print("\(kind) raw reset: \(reset)")
                        }
                    }
                }
                let diagnostic = try ClaudeUsageSnapshot.decode(data)
                if let reset = diagnostic.sevenDay?.resetsAt { print("Reset epoch: " + String(format: "%.9f", reset.timeIntervalSince1970)); print("Local reset: " + ClaudeUsageDisplay.resetTime(reset)) }
            }
        } catch { print("Usage check unavailable: " + error.localizedDescription); exit(2) }
    }
}
