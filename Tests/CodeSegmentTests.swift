import Foundation

@main struct CodeSegmentTests {
    static let tool = ReplyNode(role: "AXGroup", label: "Ran a command", children: [
        .init(role: "AXStaticText", text: "Ran a command"), .init(role: "AXButton", label: "Ran a command"),
        .init(role: "AXStaticText", text: "PRIVATE TOOL OUTPUT")
    ])
    static func reply(_ body: [ReplyNode]) -> ReplyNode {
        .init(role: "AXGroup", label: "Message 4", children: [
            .init(role: "AXGroup", label: "Message 4", children: [.init(role: "AXHeading", label: "Claude responded: update")])
        ] + body)
    }
    static func main() throws {
        let page = reply([.init(role: "AXStaticText", text: "First complete update."), tool,
                          .init(role: "AXStaticText", text: "Second update is still streaming")])
        let segments = ClaudeDecoder.codeSegments(page, responseComplete: false)
        guard segments.count == 2, segments[0].text == "First complete update.", segments[0].completed == true,
              segments[1].completed == false, segments.map(\.segment) == [1, 2] else {
            fputs("FAIL: finished Code segment must be available before the full task ends\n", stderr); exit(1)
        }
        print("PASS: finished Code segment is available while a later segment is streaming")
        let open = ClaudeDecoder.codeSegments(reply([.init(role: "AXStaticText", text: "Still writing")]), responseComplete: false)
        precondition(open.count == 1 && open[0].completed == false)
        print("PASS: the open Code tail remains unfinished for manual history selection")
        precondition(!segments.map(\.text).joined().contains("Ran a command") && !segments.map(\.text).joined().contains("PRIVATE TOOL OUTPUT"))
        print("PASS: tool summaries and output never become translated segments")
        let closed = ClaudeDecoder.codeSegments(reply([tool, .init(role: "AXStaticText", text: "One"), tool, tool]), responseComplete: false)
        precondition(closed.count == 1 && closed[0].segment == 1 && closed[0].completed == true)
        print("PASS: consecutive tool events do not create empty or duplicate segments")
        let final = ClaudeDecoder.codeSegments(page, responseComplete: true)
        precondition(final.map(\.text) == segments.map(\.text) && final.allSatisfy { $0.completed == true })
        print("PASS: final completion closes the remaining text without merging earlier segments")
        let stablePage = reply([.init(role: "AXStaticText", text: "A stable formal update before any next tool.")])
        let stableSegments = ClaudeDecoder.codeSegments(stablePage, responseComplete: false)
        var liveTracker = ConversationReplyTracker(baseline: stableSegments, conversation: "https://claude.ai/epitaxy/stable-test")
        _ = try liveTracker.observe(conversation: liveTracker.conversation, messages: stableSegments, responseComplete: false, now: 0)
        let early = try liveTracker.observe(conversation: liveTracker.conversation, messages: stableSegments, responseComplete: false, now: 2.99)
        precondition(early.isEmpty)
        print("PASS: changing or briefly paused Code text waits for the stability interval")
        let timely = try liveTracker.observe(conversation: liveTracker.conversation, messages: stableSegments, responseComplete: false, now: 3)
        guard timely.count == 1, timely[0].text == stableSegments[0].text else {
            fputs("FAIL: stable formal Code text must translate before another tool or task completion\n", stderr); exit(1)
        }
        print("PASS: stable formal Code text emits while the task is active without a later tool")
        let extended = ClaudeDecoder.codeSegments(reply([.init(role: "AXStaticText", text: "A stable formal update before any next tool. More detail.")]), responseComplete: false)
        let changing = try liveTracker.observe(conversation: liveTracker.conversation, messages: extended, responseComplete: false, now: 4)
        let settling = try liveTracker.observe(conversation: liveTracker.conversation, messages: extended, responseComplete: false, now: 6.99)
        precondition(changing.isEmpty && settling.isEmpty && !liveTracker.isCurrent(timely[0]))
        print("PASS: resumed streaming invalidates the old candidate and restarts stability")
        let revised = try liveTracker.observe(conversation: liveTracker.conversation, messages: extended, responseComplete: false, now: 7)
        precondition(revised.count == 1 && ReplyWork(candidate: timely[0], conversation: liveTracker.conversation).id == ReplyWork(candidate: revised[0], conversation: liveTracker.conversation).id)
        print("PASS: a stable continuation updates the same segment record")
        let completeExtended = ClaudeDecoder.codeSegments(reply([.init(role: "AXStaticText", text: extended[0].text)]), responseComplete: true)
        let finishedAgain = try liveTracker.observe(conversation: liveTracker.conversation, messages: completeExtended, responseComplete: true, now: 8)
        precondition(finishedAgain.isEmpty && liveTracker.isCurrent(revised[0]))
        print("PASS: final completion does not duplicate an already translated stable segment")
        var tracker = ConversationReplyTracker(baseline: segments, conversation: "https://claude.ai/epitaxy/segment-test")
        let initial = try tracker.observe(conversation: tracker.conversation, messages: segments, responseComplete: false, now: 0)
        var movingTail = segments
        movingTail[1] = .init(ordinal: 4, author: .assistant, text: "Second update keeps streaming", segment: 2, completed: false)
        _ = try tracker.observe(conversation: tracker.conversation, messages: movingTail, responseComplete: false, now: 2)
        let first = try tracker.observe(conversation: tracker.conversation, messages: movingTail, responseComplete: false, now: 3)
        movingTail[1] = .init(ordinal: 4, author: .assistant, text: "Second update resumes writing", segment: 2, completed: false)
        let waiting = try tracker.observe(conversation: tracker.conversation, messages: movingTail, responseComplete: false, now: 1200)
        precondition(initial.isEmpty && first.count == 1 && first[0].segment == 1 && waiting.isEmpty)
        print("PASS: closed segment emits during twenty-minute work while the streaming tail waits")
        let candidate = first[0]
        _ = try tracker.observe(conversation: tracker.conversation, messages: final, responseComplete: true, now: 1201)
        precondition(tracker.isCurrent(candidate))
        print("PASS: later segments do not invalidate an already complete translation job")
        let last = try tracker.observe(conversation: tracker.conversation, messages: final, responseComplete: true, now: 1204)
        let repeated = try tracker.observe(conversation: tracker.conversation, messages: final, responseComplete: true, now: 1300)
        precondition(last.count == 1 && last[0].segment == 2 && repeated.isEmpty)
        print("PASS: the final segment emits once with its own identity")
        let a = ReplyWork(candidate: candidate, conversation: tracker.conversation)
        let b = ReplyWork(candidate: last[0], conversation: tracker.conversation)
        var queue = ReplyWorkQueue(); queue.add(a); queue.add(b); queue.add(a)
        precondition(a.id != b.id && queue.pop() == a && queue.pop() == b && queue.pop() == nil)
        print("PASS: same-message segments have separate queue and display identities")
        let tail = try ClaudeDecoder.recentCodeSegments([page], responseComplete: false)
        precondition(tail == segments && tail.filter { $0.completed == true }.count == 1)
        print("PASS: current Code history can distinguish finished segments from the open tail")
        let huge = String(repeating: "A", count: ForeignTextPolicy.limit + 1)
        let tooLong = ClaudeDecoder.codeSegments(reply([.init(role: "AXStaticText", text: huge), tool]), responseComplete: true)
        precondition(tooLong.count == 1 && tooLong[0].segment == 0 && tooLong[0].text == huge)
        _ = try tracker.observe(conversation: tracker.conversation, messages: tooLong, responseComplete: false, now: 1301)
        precondition(!tracker.isCurrent(candidate), "Oversized whole-reply fallback must retire old segment jobs")
        print("PASS: segmentation cannot bypass the total foreign-reply limit or truncate its original")
        let links = reply([.init(role: "AXGroup", children: [.init(role: "AXStaticText", text: "Read the report:"),
            .init(role: "AXButton", label: "SUMMARY.md"), .init(role: "AXStaticText", text: "Complete ending.")])])
        let linked = ClaudeDecoder.codeSegments(links, responseComplete: true)
        precondition(linked.count == 1 && linked[0].text.contains("SUMMARY.md") && linked[0].text.contains("Complete ending."))
        print("PASS: formal file references preserve the answer instead of becoming tool activity")
        print("17 Code segment tests passed")
    }
}
