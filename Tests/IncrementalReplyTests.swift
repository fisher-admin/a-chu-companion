import Foundation

@main struct IncrementalReplyTests {
    @MainActor static func settle(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() { precondition(ContinuousClock.now < deadline); try await Task.sleep(for: .milliseconds(5)) }
    }
    @MainActor static func main() async throws {
        var requests: [String] = []; var results: [String] = []
        let stream = ReplyPipeline { text in requests.append(text); return "译:" + text }
        stream.onTranslation = { _, _, value, _ in results.append(value) }
        let first = "First completed paragraph.\n\n"
        stream.observe(conversation: "stream", messages: [.init(ordinal:2,author:.assistant,text:first + "Tail")], responseComplete:false, now:0)
        stream.observe(conversation: "stream", messages: [.init(ordinal:2,author:.assistant,text:first + "Tail continues")], responseComplete:false, now:1)
        stream.tick(now:3)
        try await settle { !results.isEmpty }
        precondition(requests.first == first.trimmingCharacters(in: .whitespacesAndNewlines) && !results[0].contains("Tail") && stream.completedTurns == 0)
        print("PASS: an unchanged paragraph translates while the message tail keeps streaming")
        stream.tick(now:4); try await settle { results.last?.contains("Tail continues") == true }
        let count = requests.count
        stream.observe(conversation:"stream",messages:[.init(ordinal:2,author:.assistant,text:first + "Tail continues. More ending.")],responseComplete:false,now:5)
        stream.tick(now:8); try await settle { results.last?.contains("More ending") == true }
        precondition(!requests.dropFirst(count).contains { $0.contains("First completed paragraph") })
        print("PASS: appended material does not retranslate previously completed paragraphs")
        stream.clear()
        var gate: CheckedContinuation<String, Never>?; var late = 0
        let cleared = ReplyPipeline { _ in await withCheckedContinuation { gate = $0 } }
        cleared.onTranslation = { _,_,_,_ in late += 1 }
        cleared.observe(conversation:"clear",messages:[.init(ordinal:2,author:.assistant,text:"Blocked reply",completed:true)],responseComplete:true,now:0)
        try await settle { gate != nil }
        cleared.clear(); gate?.resume(returning:"late result")
        try await Task.sleep(for: .milliseconds(30))
        precondition(late == 0 && cleared.pendingCharacters == 0)
        print("PASS: clearing retires a translation even if its provider returns late")
        var oldGate: CheckedContinuation<String, Never>?; var switched: [String] = []
        let switcher = ReplyPipeline { text in
            if text == "old" { return await withCheckedContinuation { oldGate = $0 } }
            return "new Chinese"
        }
        switcher.onTranslation = { _,_,text,_ in switched.append(text) }
        switcher.observe(conversation:"old-session",messages:[.init(ordinal:2,author:.assistant,text:"old",completed:true)],responseComplete:true,now:0)
        try await settle { oldGate != nil }
        switcher.observe(conversation:"new-session",messages:[.init(ordinal:2,author:.assistant,text:"new",completed:true)],responseComplete:true,now:1)
        oldGate?.resume(returning:"old Chinese")
        try await settle { switched.contains("new Chinese") }
        precondition(!switched.contains("old Chinese"))
        print("PASS: old sessions cannot write into the new session")
        var failure = true; var retried = false
        let retry = ReplyPipeline { text in if failure { throw BridgeError.message("simulated offline") }; return text }
        retry.onTranslation = { _,_,_,_ in retried = true }
        retry.submit(.init(candidate:.init(ordinal:2,text:"retry text"),conversation:"retry",manual:true),now:0)
        try await settle { retry.hasFailures }
        failure = false; retry.retry(); try await settle { retried }
        print("PASS: failed fragments remain retryable without losing acquired content")
        var serviceUnavailable = true; var failureStatus = ""; var availableRequests = 0
        let mixed = ReplyPipeline { text in
            if text == "Unavailable stage" && serviceUnavailable { throw BridgeError.message("Synthetic service unavailable") }
            if text == "Available stage" { availableRequests += 1 }
            return text
        }
        mixed.onStatus = { value, _ in failureStatus = value }
        mixed.submit(.init(candidate: .init(ordinal: 2, text: "Unavailable stage"), conversation: "mixed-failure", manual: true), now: 0)
        try await settle { mixed.hasFailures && !mixed.busy }
        mixed.submit(.init(candidate: .init(ordinal: 4, text: "Available stage"), conversation: "mixed-failure", manual: true), now: 1)
        try await settle { availableRequests == 1 && !mixed.busy }
        precondition(mixed.hasFailures && failureStatus.contains("翻译失败"), "A later successful stage must not hide an untranslated stage's failure")
        print("PASS: a later successful reply preserves the outstanding translation failure status")
        serviceUnavailable = false; mixed.retry()
        try await settle { !mixed.hasFailures && !mixed.busy }
        precondition(availableRequests == 1 && !failureStatus.contains("翻译失败"))
        print("PASS: retry clears the failure after recovery without translating the successful stage again")
        mixed.clear()
        var queueGate: CheckedContinuation<String, Never>?
        let bounded = ReplyPipeline { _ in await withCheckedContinuation { queueGate = $0 } }
        for ordinal in 1...80 { bounded.submit(.init(candidate:.init(ordinal:ordinal,text:String(repeating:"x",count:50_000)),conversation:"queue",manual:true),now:0) }
        precondition(bounded.queuedCount <= 64 && bounded.queuedCharacters <= 150_000)
        try await settle { queueGate != nil }; bounded.clear(); queueGate?.resume(returning:"retired")
        print("PASS: pending scheduling respects both count and character budgets")
        var finishedRequests: [String] = []; var finished = false
        let completeBody = "Research Hypothesis.\n\nCompare the two methods.\n\nExperimental Procedure.\n\nUse identical materials for 20 minutes."
        let completeReply = ReplyPipeline { text in finishedRequests.append(text); return "译:" + text }
        completeReply.onTranslation = { _, _, _, allDone in finished = allDone }
        completeReply.observe(conversation: "complete-research", messages: [.init(ordinal: 2, author: .assistant, text: completeBody)], responseComplete: true, now: 0)
        try await settle { finished }
        precondition(finishedRequests == [completeBody], "A finished short answer must not send a separate API request for each title and text span")
        print("PASS: finished short answers coalesce paragraph spans into one bounded request")
        var cachedPublications = 0; var cachedStatus = "请选择当前可见的 Claude 历史回复。"
        completeReply.onTranslation = { _, _, _, allDone in if allDone { cachedPublications += 1 } }
        completeReply.onStatus = { value, _ in cachedStatus = value }
        completeReply.submit(.init(candidate: .init(ordinal: 2, text: completeBody), conversation: "complete-research", manual: true), now: 1)
        precondition(cachedPublications == 1 && finishedRequests == [completeBody] && cachedStatus.contains("已就绪"), "A cached history selection must publish the saved Chinese and replace its selection prompt without another request")
        completeReply.cancel()
        print("PASS: cached history selections publish saved Chinese and a ready status without another cloud request")
        stream.cancel(); switcher.cancel(); retry.cancel()
        print("10 incremental reply contracts passed")
    }
}
