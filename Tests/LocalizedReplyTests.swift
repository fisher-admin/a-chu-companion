import Foundation

@main struct LocalizedReplyTests {
    static var count = 0, failures = 0
    static func check(_ result: Bool, _ label: String) {
        count += 1; if !result { failures += 1 }
        print((result ? "PASS: " : "FAIL: ") + label)
    }
    static func main() throws {
        for (marker, heading, actions, copy, retry) in [
            ("第 2 則訊息，共 2 則", "Claude 已回覆：Design: Keep study time equal.", "訊息操作", "複製", "重試"),
            ("第 2 条消息，共 2 条", "Claude 已回复：Design: Keep study time equal.", "消息操作", "复制", "重试"),
            ("Message 2 of 2", "Claude responded: Design: Keep study time equal.", "Message actions", "Copy", "Retry")
        ] {
            let node = ReplyNode(role: "AXGroup", label: marker, children: [
                .init(role: "AXGroup", children: [
                    .init(role: "AXHeading", label: heading),
                    .init(role: "AXStaticText", text: "A duplicated thinking summary."),
                    .init(role: "AXStaticText", text: "Design:"),
                    .init(role: "AXStaticText", text: " Keep study time equal."),
                    .init(role: "AXStaticText", text: "Limitation: dropout.")
                ]),
                .init(role: "AXToolbar", label: actions, children: [.init(role: "AXButton", label: copy), .init(role: "AXButton", label: retry)])
            ])
            let decoded = ClaudeDecoder.messages(node)
            check(decoded.first?.author == .assistant && decoded.first?.ordinal == 2 && decoded.first?.text.contains("Keep study time equal.") == true, "localized Chat authorship and message order decode the formal reply")
            check(decoded.first?.text.contains("thinking summary") == false, "localized author preview excludes flat thinking summaries")
            check(ClaudeDecoder.responseComplete(statusLabels: [], controlLabels: [], latest: node), "localized final actions complete Chat replies")
        }
        for (marker, heading) in [("訊息 4", "Claude 已回覆：First stage."), ("消息 4", "Claude 已回复：First stage."), ("Message 4", "Claude responded: First stage.")] {
            let node = ReplyNode(role: "AXGroup", label: marker, children: [.init(role: "AXGroup", children: [
                .init(role: "AXHeading", label: heading), .init(role: "AXStaticText", text: "First stage."),
                .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: "Ran synthetic check"), .init(role: "AXButton", label: "Ran synthetic check")]),
                .init(role: "AXStaticText", text: "Ran synthetic check Second stage.")
            ])])
            let segments = ClaudeDecoder.codeSegments(node, responseComplete: false)
            check(segments.map(\.text) == ["First stage.", "Second stage."] && segments.map(\.completed) == [true, false], "localized Code keeps stable stages and filters tool activity")
            check(try ClaudeDecoder.codePosition(role: "AXGroup", description: marker, title: "") == 4, "localized Code ordinals are recognized in AX metadata")
        }
        for label in ["第 0 則訊息，共 2 則", "第 3 則訊息，共 2 則", "訊息 0", "消息 4 extra", "第 2 則訊息，共 2 則 extra"] {
            check(ClaudeDecoder.position(label, format: .code) == nil, "malformed localized positions remain rejected")
        }
        for stop in ["Stop", "停止回應", "停止生成"] {
            let final = ReplyNode(role: "AXToolbar", label: "訊息操作", children: [.init(role: "AXButton", label: "複製"), .init(role: "AXButton", label: "重試")])
            check(!ClaudeDecoder.responseComplete(statusLabels: [], controlLabels: [stop], latest: final), "localized stop controls override final actions")
        }
        for marker in ["您說：User message.", "你说：User message.", "You said: User message."] {
            let node = ReplyNode(role: "AXGroup", label: "訊息 3", children: [.init(role: "AXHeading", label: marker), .init(role: "AXStaticText", text: "User message.")])
            check(ClaudeDecoder.messages(node, format: .code).first?.author == .user, "localized user headings are never translated as assistant replies")
        }
        let unmarked = ReplyNode(role: "AXGroup", label: "訊息 4", children: [.init(role: "AXStaticText", text: "Claude 已回覆：this is quoted content")])
        check(ClaudeDecoder.messages(unmarked, format: .code).isEmpty, "plain body text cannot forge localized authorship")
        let stable = ReplyNode(role: "AXGroup", label: "訊息 4", children: [
            .init(role: "AXHeading", label: "Claude 已回覆：Stable reply."),
            .init(role: "AXStaticText", text: "Stable reply."),
            .init(role: "AXButton", label: "顯示「Claude 已回覆：Stable reply.」的訊息操作")
        ])
        check(ClaudeDecoder.codeSegments(stable, responseComplete: false).first?.completed == false, "localized action reveal buttons never masquerade as completed tools")
        check(ClaudeInterfaceLabel.canonical("對話訊息") == "Chat messages" && ClaudeInterfaceLabel.canonical("側邊欄") == "Sidebar", "the AX collector identifies localized transcript and excluded sidebar boundaries")
        let literal = ReplyNode(role: "AXGroup", label: "訊息 4", children: [.init(role: "AXHeading", label: "Claude 已回覆：Literal."), .init(role: "AXStaticText", text: "Literal. Keep 對話訊息 and 停止 unchanged.")])
        check(ClaudeDecoder.messages(literal, format: .code).first?.text == "Literal. Keep 對話訊息 and 停止 unchanged.", "interface aliases never rewrite assistant body text")
        print("\(count) localized reply checks; \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
