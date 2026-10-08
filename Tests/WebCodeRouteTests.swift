import Foundation

@main struct WebCodeRouteTests {
    static var checks = 0, failures = 0
    static func check(_ result: Bool, _ label: String) {
        checks += 1
        if !result { failures += 1 }
        print((result ? "PASS: " : "FAIL: ") + label)
    }
    @MainActor static func main() throws {
        for address in ["https://claude.ai/code", "https://claude.ai/code/",
                        "https://claude.ai/code/session_syntheticResearch01",
                        "https://claude.ai/code/session_syntheticResearch01?view=conversation#latest"] {
            check(ClaudeConversationPage.format(address) == .code, "official Web Code homepage and session use the Code decoder")
        }
        for address in ["https://claude.ai/code/artifacts", "https://claude.ai/code/settings",
                        "https://claude.ai/code/session_", "https://claude.ai/code/session_test/other",
                        "https://claude.ai/code/session_test%20extra", "https://claude.ai.evil.example/code/session_test",
                        "http://claude.ai/code/session_test", "file:///code/session_test"] {
            check(ClaudeConversationPage.format(address) == nil, "unrelated or malformed routes remain excluded")
        }
        let monitor = ReplyMonitor()
        monitor.watching = true
        for _ in 0..<7 { monitor.handleReadFailure(ReplyReadPending(message: "Claude 消息区尚未就绪。")) }
        check(monitor.watching, "Code navigation loading keeps polling instead of ending the connection")
        let summary = "已執行 4 個指令, 已使用 2 個工具"
        let reply = ReplyNode(role: "AXGroup", label: "訊息 2", children: [.init(role: "AXGroup", children: [
            .init(role: "AXHeading", label: "Claude 已回覆：A synthetic result."),
            .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: summary)]),
            .init(role: "AXButton", label: summary),
            .init(role: "AXStaticText", text: summary + " A synthetic result."),
            .init(role: "AXStaticText", text: " The final paragraph stays complete."),
            .init(role: "AXButton", label: "顯示「Claude 已回覆：A synthetic result.」的訊息操作")
        ])])
        let segments = ClaudeDecoder.codeSegments(reply, responseComplete: false)
        check(segments.count == 1 && segments[0].text == "A synthetic result. The final paragraph stays complete.",
              "localized Web Code tool summary is excluded while adjacent formal text is preserved")
        check(segments.first?.completed == false, "action reveal alone does not mark an active task finished")
        print("\(checks) Web Code checks; \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
