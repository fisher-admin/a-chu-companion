import Foundation

@main struct StreamingReplyTests {
    static func main() throws {
        let url = "https://claude.ai/chat/continuous"
        let old = [ChatMessage(ordinal: 1, author: .user, text: "Old question"), .init(ordinal: 2, author: .assistant, text: "Old answer")]
        var tracker = StreamingReplyTracker(baseline: old, conversation: url)
        precondition(try! tracker.observe(conversation: url, messages: old, responseComplete: true) == [.init(candidate: .init(ordinal: 2, text: "Old answer"), complete: true)])
        print("PASS: connection immediately acquires the current complete reply, with no stability delay")
        precondition(try! tracker.observe(conversation: url, messages: old, responseComplete: true).isEmpty)
        print("PASS: unchanged snapshots report nothing")
        let prompt = old + [.init(ordinal: 3, author: .user, text: "Typed directly in Claude")]
        var growing = prompt + [.init(ordinal: 4, author: .assistant, text: "First")]
        precondition(try! tracker.observe(conversation: url, messages: growing, responseComplete: false) == [.init(candidate: .init(ordinal: 4, text: "First"), complete: false)])
        growing[3] = .init(ordinal: 4, author: .assistant, text: "First sentence. Second")
        precondition(try! tracker.observe(conversation: url, messages: growing, responseComplete: false) == [.init(candidate: .init(ordinal: 4, text: "First sentence. Second"), complete: false)])
        print("PASS: every streamed growth of a reply is reported at once as incomplete")
        precondition(try! tracker.observe(conversation: url, messages: growing, responseComplete: true) == [.init(candidate: .init(ordinal: 4, text: "First sentence. Second"), complete: true)])
        print("PASS: the completion signal alone is reported without waiting")
        let next = growing + [.init(ordinal: 5, author: .user, text: "Another"), .init(ordinal: 6, author: .assistant, text: "Third")]
        let both = try tracker.observe(conversation: url, messages: next, responseComplete: false)
        precondition(both == [.init(candidate: .init(ordinal: 6, text: "Third"), complete: false)])
        precondition(tracker.isCurrent(.init(ordinal: 4, text: "First sentence. Second")) && !tracker.isCurrent(.init(ordinal: 4, text: "First")))
        print("PASS: later turns keep earlier replies current and complete")
        var batch = StreamingReplyTracker(baseline: [.init(ordinal: 1, author: .user, text: "First")], conversation: url)
        let three = [ChatMessage(ordinal: 1, author: .user, text: "First"), .init(ordinal: 2, author: .assistant, text: "A"),
                     .init(ordinal: 3, author: .user, text: "Q"), .init(ordinal: 4, author: .assistant, text: "B"),
                     .init(ordinal: 5, author: .user, text: "Q2"), .init(ordinal: 6, author: .assistant, text: "C")]
        let reported = try batch.observe(conversation: url, messages: three, responseComplete: false)
        precondition(reported.map(\.candidate.ordinal) == [2, 4, 6] && reported.map(\.complete) == [true, true, false])
        print("PASS: several replies are reported in order; only the newest can still be streaming")
        var revised = three
        revised[5] = .init(ordinal: 6, author: .assistant, text: "Rewritten")
        precondition(try! batch.observe(conversation: url, messages: revised, responseComplete: true) == [.init(candidate: .init(ordinal: 6, text: "Rewritten"), complete: true)])
        print("PASS: a rewritten reply is reported with its new text")
        do { _ = try tracker.observe(conversation: "https://claude.ai/chat/other", messages: next, responseComplete: true); fatalError("old tracker must not accept another conversation") }
        catch { print("PASS: old conversation tracker never accepts a different route") }
        do { _ = try tracker.observe(conversation: url, messages: [next[1], next[0]], responseComplete: true); fatalError("out-of-order messages are not trusted") }
        catch let pending as ReplyReadPending { precondition(!pending.structural); print("PASS: unordered message numbers are a transient read, not a structure change") }
        var empty = StreamingReplyTracker(baseline: [], conversation: "https://claude.ai/new")
        precondition(try! empty.observe(conversation: "https://claude.ai/new", messages: [], responseComplete: true).isEmpty)
        print("PASS: an empty connected conversation can wait indefinitely")
        let toolbar = ReplyNode(role: "AXToolbar", label: "Message actions", children: [.init(role: "AXButton", label: "Copy"), .init(role: "AXButton", label: "Retry")])
        precondition(!ClaudeDecoder.responseComplete(statusLabels: ["Claude finished the response"], controlLabels: ["Stop response"], latest: toolbar))
        print("PASS: a generation stop button overrides a stale finished announcement")
        precondition(ClaudeDecoder.responseComplete(statusLabels: ["Claude finished the response"], controlLabels: [], latest: nil))
        precondition(ClaudeDecoder.responseComplete(statusLabels: [], controlLabels: [], latest: toolbar))
        precondition(!ClaudeDecoder.responseComplete(statusLabels: [], controlLabels: [], latest: nil))
        print("PASS: finished announcements or final actions are required for latest replies")
        func card(_ ordinal: Int, _ total: Int, heading: String, body: String) -> ReplyNode {
            ReplyNode(role: "AXGroup", label: "Message \(ordinal) of \(total)", children: [
                .init(role: "AXGroup", children: [.init(role: "AXHeading", label: heading), .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: body)])])
            ])
        }
        let thinking = [card(1, 2, heading: "You said: Hello", body: "Hello"), ReplyNode(role: "AXGroup", label: "Message 2 of 2", children: [.init(role: "AXGroup", children: [.init(role: "AXHeading", label: "Claude responded:")])])]
        do { _ = try ClaudeDecoder.recentMessages(thinking); fatalError("thinking card has no body") }
        catch let pending as ReplyReadPending { precondition(!pending.structural); print("PASS: a reply that is still thinking is a normal wait") }
        let relabelled = [card(1, 2, heading: "Du hast gesagt: Hallo", body: "Hallo"), card(2, 2, heading: "Claude hat geantwortet:", body: "Antwort")]
        do { _ = try ClaudeDecoder.recentMessages(relabelled); fatalError("unknown author markers") }
        catch let pending as ReplyReadPending { precondition(pending.structural); print("PASS: unrecognised author markers on every card are a structural change") }
        precondition(ReplyIdentity.id(conversation: url, ordinal: 2) == ReplyIdentity.id(conversation: url, ordinal: 2))
        precondition(ReplyIdentity.id(conversation: url, ordinal: 2) != ReplyIdentity.id(conversation: url + "other", ordinal: 2))
        print("PASS: reply bubble identities persist on reconnect and separate conversations")
        let viewport = CGRect(x: 0, y: 100, width: 500, height: 400)
        precondition(VisibleReplyGeometry.intersects(CGRect(x: 0, y: 0, width: 500, height: 250), viewport: viewport))
        precondition(!VisibleReplyGeometry.intersects(CGRect(x: 0, y: -500, width: 500, height: 250), viewport: viewport))
        precondition(!VisibleReplyGeometry.intersects(CGRect(x: 0, y: 499, width: 500, height: 100), viewport: viewport))
        print("PASS: history selection includes visible reply bodies and excludes offscreen or one-pixel edges")
        print("16 streaming reply tests passed")
    }
}
