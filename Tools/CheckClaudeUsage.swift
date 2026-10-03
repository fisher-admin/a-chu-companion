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
        } catch { print("Usage check unavailable: " + error.localizedDescription); exit(2) }
    }
}
