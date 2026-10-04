import Foundation

@main struct CodeReplyTests {
    static func main() throws {
        // Sanitized shape observed in Claude Desktop Code: the ordinal marker
        // holds the author, while paragraphs and the final toolbar are siblings.
        let marker = ReplyNode(role: "AXGroup", label: "Message 4", children: [
            .init(role: "AXGroup", children: [
                .init(role: "AXHeading", label: "Claude responded: Starting"),
                .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: "Ran 2 commands , used 2 tools")]),
                .init(role: "AXGroup", children: [
                    .init(role: "AXStaticText", text: "Ran 2 commands, used 2 tools"),
                    .init(role: "AXButton", label: "Ran 2 commands, used 2 tools")
                ]),
                .init(role: "AXStaticText", text: "Ran 2 commands, used 2 tools")
            ])
        ])
        let actions = ReplyNode(role: "AXToolbar", label: "Message actions", children: [
            .init(role: "AXButton", label: "Copy"), .init(role: "AXButton", label: "Fork from here")
        ])
        let message = ReplyNode(role: "AXGroup", label: "Message 4", children: [marker,
            .init(role: "AXStaticText", text: "Starting the checks."),
            .init(role: "AXGroup", children: [
                .init(role: "AXGroup", children: [
                    .init(role: "AXStaticText", text: "Read a file"), .init(role: "AXButton", label: "Read a file"),
                    .init(role: "AXStaticText", text: "PRIVATE TOOL OUTPUT")
                ]), .init(role: "AXStaticText", text: "Read a file")
            ]),
            .init(role: "AXGroup", children: [
                .init(role: "AXStaticText", text: "The checks passed."),
                .init(role: "AXGroup", label: "Code", children: [
                    .init(role: "AXButton", label: "Copy code"), .init(role: "AXStaticText", text: "print(\"complete\")")
                ]),
                .init(role: "AXStaticText", text: "FINAL-END"), actions
            ])
        ])
        guard let decoded = ClaudeDecoder.messages(message, format: .code).first,
              decoded.ordinal == 4, decoded.author == .assistant,
              decoded.text.contains("Starting the checks."), decoded.text.contains("The checks passed."),
              decoded.text.contains("print(\"complete\")"), decoded.text.contains("FINAL-END"),
              !decoded.text.contains("Ran 2 commands"), !decoded.text.contains("Read a file"),
              !decoded.text.contains("PRIVATE TOOL OUTPUT"), !decoded.text.contains("Fork from here") else {
            fputs("FAIL: Code reply must include sibling paragraphs through its ending, without tool activity\n", stderr)
            exit(1)
        }
        print("PASS: Code reply keeps sibling paragraphs, final code and ending without tool activity")
        precondition(!ClaudeDecoder.responseComplete(statusLabels: ["Claude finished the response", "Claude is working"], controlLabels: [], latest: actions))
        print("PASS: ongoing work overrides a stale finished status")
        precondition(ClaudeConversationPage.format("https://claude.ai/epitaxy/local-test") == .code)
        precondition(ClaudeConversationPage.format("https://claude.ai/chat/test") == .chat)
        precondition(ClaudeConversationPage.format("https://claude.ai/new") == .chat)
        print("PASS: desktop Code sessions and existing Chat routes are recognized separately")
        for address in ["https://claude.ai/settings", "https://claude.ai/epitaxy", "https://claude.ai.evil.example/epitaxy/test", "http://claude.ai/epitaxy/test", "file:///epitaxy/test"] {
            precondition(ClaudeConversationPage.format(address) == nil)
        }
        print("PASS: unrelated pages and untrusted origins remain excluded")
        precondition(ClaudeDecoder.position("Message 4", format: .chat) == nil)
        precondition(ClaudeDecoder.position("Message 4", format: .code)?.ordinal == 4)
        precondition(ClaudeDecoder.position("Message 0", format: .code) == nil)
        precondition(ClaudeDecoder.position("Message 4 of 3", format: .code) == nil)
        print("PASS: Code ordinal format does not weaken Chat message validation")
        let ranges = try ClaudeDecoder.codeMessageRanges(["unrelated preface", "Message 2", "", "Message 3", "", "Message 4", "", ""])
        precondition(ranges.map(\.ordinal) == [2, 3, 4] && ranges.map(\.range) == [1..<3, 3..<5, 5..<8])
        print("PASS: Code paragraph groups end at the next message and exclude pre-marker content")
        for labels in [["Message 4", "Message 4"], ["Message 4", "Message 2"], ["Message 4", "Message 5 of 4"]] {
            do { _ = try ClaudeDecoder.codeMessageRanges(labels); fatalError("invalid order must wait") }
            catch { precondition(error is ReplyReadPending) }
        }
        print("PASS: duplicate or reordered Code markers remain retryable")
        let tail = try ClaudeDecoder.recentMessages([message], format: .code)
        precondition(tail.count == 1 && tail[0] == decoded)
        print("PASS: virtualized Code history can decode the complete latest reply")
        let empty = ReplyNode(role: "AXGroup", label: "Message 4", children: [.init(role: "AXHeading", label: "Claude responded:")])
        do { _ = try ClaudeDecoder.recentMessages([empty], format: .code); fatalError("empty Code reply must wait") }
        catch { precondition(error is ReplyReadPending) }
        print("PASS: empty Code thinking card is retryable without a partial reply")
        precondition(!ClaudeDecoder.responseComplete(statusLabels: ["Claude finished the response"], controlLabels: ["Stop"], latest: actions, format: .code))
        precondition(ClaudeDecoder.responseComplete(statusLabels: [], controlLabels: [], latest: actions, format: .code))
        precondition(!ClaudeDecoder.responseComplete(statusLabels: [], controlLabels: [], latest: actions))
        print("PASS: Code final actions are distinct and never override an active stop control")
        let flatActions = ReplyNode(role: "AXGroup", label: "Message 4", children: [marker,
            .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: "Full final answer."),
                .init(role: "AXButton", label: "Copy"), .init(role: "AXButton", label: "Fork from here"),
                .init(role: "AXButton", label: "Read aloud")])
        ])
        precondition(ClaudeDecoder.messages(flatActions, format: .code).first?.text == "Full final answer.")
        print("PASS: flattened Code message actions cannot remove their neighboring final answer")
        let quoted = ReplyNode(role: "AXGroup", label: "Message 4", children: [
            .init(role: "AXGroup", label: "Message 4", children: [.init(role: "AXStaticText", text: "unmarked")]),
            .init(role: "AXHeading", label: "Claude responded: quoted example"), .init(role: "AXStaticText", text: "Untrusted body")
        ])
        precondition(ClaudeDecoder.messages(quoted, format: .code).isEmpty)
        print("PASS: a quoted author prefix outside the Code ordinal anchor is not authorship")
        precondition(try! ClaudeDecoder.codePosition(role: "AXGroup", description: "message container", title: "Message 4") == 4)
        precondition(try! ClaudeDecoder.codePosition(role: "AXGroup", description: "Message 4", title: "different description") == 4)
        do { _ = try ClaudeDecoder.codePosition(role: "AXGroup", description: "Message 4", title: "Message 5"); fatalError("conflicting metadata must wait") }
        catch { precondition(error is ReplyReadPending) }
        print("PASS: structural title survives a different description; conflicting ordinals wait")
        let nested = CodeTranscriptBranch(element: "transcript", ordinal: nil, children: [
            .init(element: "load earlier", ordinal: nil),
            .init(element: "outer wrapper", ordinal: nil, children: [
                .init(element: "inner wrapper", ordinal: 4, children: [.init(element: "author anchor", ordinal: 4)]),
                .init(element: "first paragraph", ordinal: nil),
                .init(element: "tool card", ordinal: nil, children: [.init(element: "tool detail", ordinal: nil)])
            ]),
            .init(element: "final paragraph and actions", ordinal: nil)
        ])
        let pieces = ClaudeDecoder.codeTranscriptPieces(nested)
        precondition(pieces.map(\.element) == ["load earlier", "author anchor", "first paragraph", "tool card", "final paragraph and actions"])
        let spans = try ClaudeDecoder.codeMessageRanges(pieces.map { $0.ordinal.map { "Message \($0)" } ?? "" })
        precondition(spans.count == 1 && spans[0].range == 1..<5)
        print("PASS: nested header-only wrappers do not prevent collecting outside answer siblings")
        let multiple = CodeTranscriptBranch(element: "root", ordinal: nil, children: [
            nested, .init(element: "next user", ordinal: 5), .init(element: "next answer", ordinal: 6), .init(element: "ending", ordinal: nil)
        ])
        let following = ClaudeDecoder.codeTranscriptPieces(multiple)
        let separated = try ClaudeDecoder.codeMessageRanges(following.map { $0.ordinal.map { "Message \($0)" } ?? "" })
        precondition(separated.map(\.ordinal) == [4, 5, 6] && separated.map(\.range) == [1..<5, 5..<6, 6..<8])
        print("PASS: wrapper flattening keeps subsequent user and assistant message boundaries")
        precondition(try! ClaudeDecoder.codePosition(role: "AXStaticText", description: "Message 5", title: "Message 5") == nil)
        precondition(try! ClaudeDecoder.codePosition(role: "AXButton", description: "Message 5", title: "Message 5") == nil)
        print("PASS: literal Message N body text and buttons cannot create Code boundaries")
        var tracker = ConversationReplyTracker(baseline: [], conversation: "https://claude.ai/epitaxy/local-test")
        let partial = ChatMessage(ordinal: 4, author: .assistant, text: "Starting the checks.")
        for now in [0.0, 5, 30, 300, 1200] {
            let candidates = try tracker.observe(conversation: tracker.conversation, messages: [partial], responseComplete: false, now: now)
            precondition(candidates.isEmpty)
        }
        let settling = try tracker.observe(conversation: tracker.conversation, messages: [decoded], responseComplete: true, now: 1201)
        let completed = try tracker.observe(conversation: tracker.conversation, messages: [decoded], responseComplete: true, now: 1204)
        let repeated = try tracker.observe(conversation: tracker.conversation, messages: [decoded], responseComplete: true, now: 1210)
        precondition(settling.isEmpty && completed.first?.text == decoded.text && repeated.isEmpty)
        print("PASS: twenty-minute Code work waits for the complete body and emits once")
        print("17 Code reply tests passed")
    }
}
