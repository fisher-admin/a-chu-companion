import Foundation

@main struct ReplyTests {
    static func message(_ n: Int, _ author: String, _ text: String) -> ReplyNode {
        let heading = ReplyNode(role: "AXHeading", label: author + ": summary", children: [.init(role: "AXStaticText", text: "summary")])
        let body = ReplyNode(role: "AXGroup", children: [.init(role: "AXStaticText", text: text)])
        return .init(role: "AXGroup", label: "Message \(n) of 8", children: [
            .init(role: "AXGroup", children: [heading, .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: "Searched the web"), .init(role: "AXButton", label: "Searched the web")]), .init(role: "AXStaticText", text: "Searched the web"), body]),
            .init(role: "AXToolbar", label: "Message actions", children: [.init(role: "AXStaticText", text: "Aug 20"), .init(role: "AXButton", label: "Copy")])
        ])
    }
    static func main() {
        let root = ReplyNode(role: "AXGroup", label: "Chat messages", children: [message(1, "You said", "Hello"), message(2, "Claude responded", "Please restart the app.")])
        let messages = ClaudeDecoder.messages(root)
        guard messages.count == 2, messages.last?.text == "Please restart the app." else {
            fputs("FAIL: decode Claude body without headings, tool activity or toolbar\n", stderr); exit(1)
        }
        print("PASS: decode Claude body without tool or toolbar text")
        let old = messages
        let outgoing = ChatMessage(ordinal: 3, author: .user, text: "Please check it.")
        let partial = ChatMessage(ordinal: 4, author: .assistant, text: "Please restart")
        let final = ChatMessage(ordinal: 4, author: .assistant, text: "Please restart the app.")
        var tracker = ReplyTracker(baseline: old, outbound: "Please check it.", conversation: "https://claude.ai/chat/test")
        precondition(try! tracker.observe(conversation: "https://claude.ai/chat/test", messages: old, now: 0) == nil)
        precondition(try! tracker.observe(conversation: "https://claude.ai/chat/test", messages: old + [outgoing, partial], now: 1) == nil)
        precondition(try! tracker.observe(conversation: "https://claude.ai/chat/test", messages: old + [outgoing, final], now: 2) == nil)
        precondition(try! tracker.observe(conversation: "https://claude.ai/chat/test", messages: old + [outgoing, final], now: 4) == nil)
        precondition(try! tracker.observe(conversation: "https://claude.ai/chat/test", messages: old + [outgoing, final], now: 5)?.text == final.text)
        precondition(try! tracker.observe(conversation: "https://claude.ai/chat/test", messages: old + [outgoing, final], now: 9) == nil)
        print("PASS: streaming coalesces; unchanged reply does not translate twice")
        let repeated = ChatMessage(ordinal: 5, author: .assistant, text: final.text)
        _ = try! tracker.observe(conversation: "https://claude.ai/chat/test", messages: old + [outgoing, final, repeated], now: 10)
        precondition(try! tracker.observe(conversation: "https://claude.ai/chat/test", messages: old + [outgoing, final, repeated], now: 13)?.ordinal == 5)
        print("PASS: distinct identical replies translate independently")
        do { _ = try tracker.observe(conversation: "https://claude.ai/chat/other", messages: old, now: 14); fatalError("navigation must stop") } catch { print("PASS: conversation navigation stops monitoring") }
        var mismatch = ReplyTracker(baseline: old, outbound: "different", conversation: "https://claude.ai/chat/test")
        do { _ = try mismatch.observe(conversation: "https://claude.ai/chat/test", messages: old + [outgoing], now: 1); fatalError("wrong prompt must stop") } catch { print("PASS: edited outbound message does not bind silently") }
        var fresh = ReplyTracker(baseline: [], outbound: "Please check it.", conversation: "https://claude.ai/new")
        _ = try! fresh.observe(conversation: "https://claude.ai/chat/new-id", messages: [outgoing, final], now: 0)
        precondition(fresh.bound)
        print("PASS: new-chat route may become conversation once")
        let banner = ReplyNode(role: "AXGroup", label: "Sidebar", children: [.init(role: "AXStaticText", text: "unrelated text")])
        precondition(ClaudeDecoder.messages(banner).isEmpty)
        precondition(ClaudeDecoder.messages(message(1, "Unknown", "unrelated text")).isEmpty)
        print("PASS: unmarked UI text never becomes a reply")
        let long = String(repeating: "😀", count: 12_010)
        precondition(ClaudeDecoder.chunks(long).joined() == long && ClaudeDecoder.chunks(long).allSatisfy { $0.count <= 5000 })
        print("PASS: long replies chunk without losing Unicode")
        let simple = ReplyNode(role: "AXGroup", label: "Message 1 of 1", children: [
            .init(role: "AXGroup", children: [.init(role: "AXHeading", label: "Claude responded: Please"), .init(role: "AXStaticText", text: "Please restart.")])
        ])
        guard ClaudeDecoder.messages(simple).first?.text == "Please restart." else { fputs("FAIL: flattened simple Claude reply\n", stderr); exit(1) }
        print("PASS: flattened simple Claude reply")
        let unnamedHeading = ReplyNode(role: "AXGroup", label: "Message 1 of 1", children: [
            .init(role: "AXGroup", children: [
                .init(role: "AXHeading", children: [.init(role: "AXStaticText", text: "Claude responded: Please restart.")]),
                .init(role: "AXStaticText", text: "Please restart.")
            ])
        ])
        guard ClaudeDecoder.messages(unnamedHeading).first?.text == "Please restart." else {
            fputs("FAIL: authorship text in heading child identifies the reply\n", stderr); exit(1)
        }
        print("PASS: authorship text in heading child identifies the reply")

        var lifecycle = ReplyTranslationLifecycle()
        let completed = lifecycle.begin()
        precondition(lifecycle.isTranslating)
        precondition(lifecycle.finish(completed))
        precondition(!lifecycle.isTranslating)
        print("PASS: completed reply translation clears active state")

        let stale = lifecycle.begin()
        let current = lifecycle.begin()
        precondition(!lifecycle.finish(stale))
        precondition(lifecycle.isCurrent(current) && lifecycle.isTranslating)
        precondition(lifecycle.finish(current))
        print("PASS: stale reply completion cannot clear a newer translation")

        let cancelled = lifecycle.begin()
        precondition(lifecycle.cancel(cancelled))
        precondition(!lifecycle.isTranslating)
        precondition(!lifecycle.finish(cancelled))
        print("PASS: cancelled reply translation clears active state")

        print("13 reply tests passed")
    }
}
