import Foundation
import AppKit

/// Streaming, fallback and safety improvements ported onto build78, plus the review's
/// edge cases: stable tails, long table rows and inline code, ordered concurrency,
/// bounded memory, relaxed output cleanup and interface-change escalation.
@main struct StreamingIntegrationTests {
    static var passed = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
        passed += 1; print("PASS: \(name)")
    }
    @MainActor static func settle(_ seconds: Double = 3, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while !condition() {
            guard ContinuousClock.now < deadline else { return }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @MainActor static func main() async throws {
        _ = NSApplication.shared
        try await boundaries()
        try await structure()
        try await concurrency()
        try await serviceFallback()
        cleanup()
        try await escalation()
        safety()
        try await memory()
        try await thinkingWait()
        try await lateRevision()
        quotes()
        try await longStages()
        print("\(passed) streaming integration contracts passed")
    }

    @MainActor static func boundaries() async throws {
        var requests: [String] = []; var latest = ""
        let early = ReplyPipeline { text in requests.append(text); return "译:" + text }
        early.onTranslation = { _, _, value, _ in latest = value }
        let first = "The first paragraph is finished.\n\n"
        early.observe(conversation: "c", messages: [.init(ordinal: 2, author: .assistant, text: first + "The tail is still")], responseComplete: false, now: 0)
        try await settle { !requests.isEmpty }
        check(requests == ["The first paragraph is finished."], "a paragraph followed by more text translates at once, without the 3-second wait")
        try await Task.sleep(for: .milliseconds(50))
        check(requests.count == 1 && !latest.contains("tail"), "the still-growing tail is not translated early")

        // Review case: a complete stage ends with a full stop and a blank line, and the
        // same snapshot repeats while Code runs a long tool; the next stage never arrives.
        var stageRequests = 0; var stage = ""
        let paused = ReplyPipeline { text in stageRequests += 1; return "中文:" + text }
        paused.onTranslation = { _, _, value, _ in stage = value }
        let text = "阶段说明：已完成依赖安装，正在等待测试结果。\n\n"
        for second in 0..<8 {
            paused.observe(conversation: "code", messages: [.init(ordinal: 2, author: .assistant, text: text)], responseComplete: false, now: TimeInterval(second))
        }
        try await settle { stageRequests > 0 }
        check(stageRequests == 1 && stage.hasPrefix("中文:阶段说明"), "a stable stage without a following stage is flushed after it stops changing")
        var completeRequests = 0
        let finished = ReplyPipeline { text in completeRequests += 1; return text }
        finished.observe(conversation: "done", messages: [.init(ordinal: 2, author: .assistant, text: "Final answer without a trailing newline")], responseComplete: true, now: 0)
        try await settle { completeRequests > 0 }
        check(completeRequests == 1, "a completed reply flushes its tail immediately, even without a delimiter")
    }

    @MainActor static func structure() async throws {
        let longCell = String(repeating: "Explain the regularisation effect on validation loss ", count: 20)
        let table = "| Model | Notes |\n| --- | --- |\n| RandomForestClassifier | \(longCell)|\n\n"
        let longCode = "Run `" + String(repeating: "python train.py --epochs 40 --lr 0.001 ", count: 30) + "` before comparing.\n\n"
        var requests: [String] = []; var output = ""
        let pipeline = ReplyPipeline(concurrency: 3) { text in requests.append(text); return text.uppercased() }
        pipeline.onTranslation = { _, _, value, complete in if complete { output = value } }
        pipeline.observe(conversation: "s", messages: [.init(ordinal: 2, author: .assistant, text: table + longCode)], responseComplete: true, now: 0)
        try await settle { !output.isEmpty }
        check(!requests.contains { $0.contains("|") || $0.contains("---") }, "table separators and the delimiter row are never sent for translation")
        check(!requests.contains { $0.contains("`") || $0.contains("--epochs") }, "long inline code is never sent or split")
        let rows = output.components(separatedBy: "\n").filter { $0.hasPrefix("|") }
        check(rows.count == 3 && rows.allSatisfy { $0.filter { $0 == "|" }.count == 3 }, "every table row keeps its columns after translation")
        check(output.contains("`" + String(repeating: "python train.py --epochs 40 --lr 0.001 ", count: 30) + "`"), "inline code survives verbatim")
    }

    @MainActor static func concurrency() async throws {
        var gates: [String: CheckedContinuation<String, Never>] = [:]
        var inFlight = 0, peak = 0
        var published: [String] = []
        let pipeline = ReplyPipeline(concurrency: 3) { text in
            inFlight += 1; peak = max(peak, inFlight)
            defer { inFlight -= 1 }
            return await withCheckedContinuation { gates[text] = $0 }
        }
        pipeline.onTranslation = { _, _, value, _ in published.append(value) }
        let paragraphs = (1...5).map { "Paragraph number \($0) is complete." }
        // While streaming, every paragraph followed by another one is finished and ready at once.
        pipeline.observe(conversation: "p", messages: [.init(ordinal: 2, author: .assistant, text: paragraphs.joined(separator: "\n\n"))], responseComplete: false, now: 0)
        try await settle { gates.count == 3 }
        check(gates.count == 3 && peak == 3, "three slices translate at once, never more")
        gates.removeValue(forKey: paragraphs[2])?.resume(returning: "C")
        gates.removeValue(forKey: paragraphs[1])?.resume(returning: "B")
        try await Task.sleep(for: .milliseconds(30))
        check(published.isEmpty, "later slices finishing first publish nothing before the first slice")
        gates.removeValue(forKey: paragraphs[0])?.resume(returning: "A")
        try await settle { published.last?.hasPrefix("A\n\nB\n\nC") == true }
        check(published.last?.hasPrefix("A\n\nB\n\nC") == true, "out-of-order completions render in source order")
        try await settle { gates[paragraphs[3]] != nil }
        gates.removeValue(forKey: paragraphs[3])?.resume(returning: "D")
        pipeline.tick(now: 10)
        try await settle { gates[paragraphs[4]] != nil }
        gates.removeValue(forKey: paragraphs[4])?.resume(returning: "E")
        try await settle { !pipeline.busy && published.last == "A\n\nB\n\nC\n\nD\n\nE" }
        check(published.last == "A\n\nB\n\nC\n\nD\n\nE" && !pipeline.busy, "all slots are released when the reply is done")

        var revisions = 0
        let revising = ReplyPipeline(incremental: true, concurrency: 2) { text in
            revisions += 1; try await Task.sleep(for: .milliseconds(20)); return text
        }
        for step in 0..<40 {
            revising.observe(conversation: "r", messages: [.init(ordinal: 2, author: .assistant, text: "Stage \(step) is finished.\n\nTail \(step)")], responseComplete: false, now: TimeInterval(step) * 0.1)
        }
        try await settle { !revising.busy }
        check(!revising.busy && revisions > 0, "repeated revisions cancel superseded slices without leaking slots")
    }

    @MainActor static func serviceFallback() async throws {
        var primary = 0, fallback = 0; var statuses: [String] = []
        let pipeline = ReplyPipeline(concurrency: 1) { _ in
            primary += 1
            throw ServiceAuthorizationError(seconds: 600, reason: "Gemini 翻译服务返回 403。")
        }
        pipeline.fallback = { text in fallback += 1; return "系统:" + text }
        pipeline.onStatus = { message, _ in statuses.append(message) }
        var output = ""
        pipeline.onTranslation = { _, _, value, _ in output = value }
        pipeline.observe(conversation: "f", messages: [.init(ordinal: 2, author: .assistant, text: "One.\n\nTwo.\n\nThree.")], responseComplete: false, now: 0)
        try await settle { output.contains("Two") }
        pipeline.tick(now: 5)
        try await settle { output.contains("Three") }
        check(output == "系统:One.\n\n系统:Two.\n\n系统:Three." && fallback == 3, "a rejected key falls back to system translation for every slice")
        check(primary == 1, "after a rejected key the service is paused; later slices skip it")
        check(statuses.contains { $0.contains("本段已改用系统翻译") }, "the fallback is reported to the user")
    }

    static func cleanup() {
        let source = "Compare RandomForestClassifier with GradientBoostingClassifier on the validation split."
        let technical = "在验证集上比较 RandomForestClassifier 与 GradientBoostingClassifier。"
        check((try? TranslationCleanup.normalize(technical, source: source)) == technical, "technical text with kept identifiers passes unchanged (review false-rejection case)")
        check((try? TranslationCleanup.normalize("Yes", source: "是")) == "Yes", "a legitimate short answer passes unchanged")
        check((try? TranslationCleanup.normalize("Here is the translation:\n在验证集上比较。", source: "Compare on the validation split.")) == "在验证集上比较。", "an added English preamble line is removed")
        check((try? TranslationCleanup.normalize("以下是翻译：先运行测试。", source: "Run the tests first.")) == "先运行测试。", "an added Chinese preamble is removed")
        check((try? TranslationCleanup.normalize("Translation: the word", source: "Translation: 这个词")) == "Translation: the word", "a marker that is in the source is kept")
        check((try? TranslationCleanup.normalize("Sure, I agree.", source: "当然，我同意。")) == "Sure, I agree.", "natural openings such as Sure are never stripped")
        check((try? TranslationCleanup.normalize("```text\n先运行测试。\n```", source: "Run the tests first.")) == "先运行测试。", "a fence the model wrapped around the answer is removed")
        check((try? TranslationCleanup.normalize("“先运行测试。”", source: "Run the tests first.")) == "先运行测试。", "added outer quotes are removed")
        do { _ = try TranslationCleanup.normalize("先运行：\n```\nmake", source: "Run first: make"); check(false, "unpaired fence") }
        catch { check(error is TranslationCleanup.UnpairedFence, "an unpaired model-added fence falls back instead of breaking layout") }
    }

    @MainActor static func escalation() async throws {
        let monitor = ReplyMonitor()
        var now: TimeInterval = 0
        monitor.clock = { now }
        monitor.watching = true
        let structural = ReplyReadPending(message: "未识别到 Claude 消息标记。", structural: true)
        monitor.handleReadFailure(structural)
        check(monitor.readError == nil && monitor.status.contains("等待 Claude 原文"), "a short structural failure is a normal wait")
        now = 30; monitor.handleReadFailure(ReplyReadPending(message: "正文尚未就绪"))
        monitor.handleReadFailure(structural)
        check(monitor.readError == nil, "thinking or partial reads in between do not reset or trigger escalation")
        now = 46; monitor.handleReadFailure(structural)
        check(monitor.readError?.contains("界面结构已变化") == true && monitor.status == monitor.readError && monitor.watching, "45 seconds of structural failure show a visible interface-change warning without stopping")
        check(monitor.readRetrySeconds == 3, "polling slows while the interface is unrecognised")
        for _ in 0..<20 { monitor.handleReadFailure(ReplyReadPending(message: "正文尚未就绪")) }
        check(monitor.readError != nil && monitor.status == monitor.readError, "later ordinary waits do not hide the warning")
        monitor.handleReadFailure(BridgeError.message("暂时无法读取"))
        check(monitor.status == monitor.readError, "a transient read error does not hide the warning either")
        monitor.ingest(ReplySnapshot(conversation: "https://claude.ai/chat/x", messages: [], foundTranscript: true, responseComplete: true), now: 0)
        check(monitor.readError == nil && monitor.status.contains("已恢复"), "a readable snapshot clears the warning automatically")
        let quiet = ReplyMonitor(); quiet.clock = { now }; quiet.watching = true
        for second in 0..<600 { now = TimeInterval(second); quiet.handleReadFailure(ReplyReadPending(message: "正文尚未就绪")) }
        check(quiet.readError == nil, "ten minutes of thinking never raise the interface warning")
        monitor.stop()
        check(monitor.readError == nil, "stopping clears the warning")
    }

    @MainActor static func safety() {
        let item = ManualInputDelivery.privateItem("secret draft")
        check(item.string(forType: .string) == "secret draft" && item.types.contains(ManualInputDelivery.transientType)
              && item.types.contains(ManualInputDelivery.concealedType), "pasted translations carry transient and concealed clipboard markers")
        var ledger = AccessibilityFlagLedger()
        check(ledger.shouldEnable(pid: 10, flag: "AXEnhancedUserInterface", currentlyOn: false), "an off accessibility flag is switched on and recorded")
        check(!ledger.shouldEnable(pid: 11, flag: "AXEnhancedUserInterface", currentlyOn: true), "a flag the app enabled itself is left alone")
        _ = ledger.shouldEnable(pid: 10, flag: "AXManualAccessibility", currentlyOn: false)
        check(ledger.release(pid: 10) == ["AXEnhancedUserInterface", "AXManualAccessibility"] && ledger.release(pid: 10).isEmpty, "disconnecting switches off exactly the flags the companion enabled, once")
        check(ledger.release(pid: 11).isEmpty && ledger.processes.isEmpty, "apps the companion did not change are untouched")
        let chat = ReplyIdentity.id(conversation: "https://claude.ai/chat/a", ordinal: 7)
        let stage = { (segment: Int) in ReplyIdentity.id(conversation: "https://claude.ai/code/a", ordinal: 2, segment: segment) }
        var retired = RetiredIDs(conversationLimit: 2, ordinalWindow: 128, otherLimit: 2)
        retired.formUnion([chat] + (1...600).map(stage))
        check(retired.contains(chat) && (1...600).allSatisfy { retired.contains(stage($0)) } && retired.storedRanges == 2,
              "600 retired segments of one message are all remembered as one compressed range")
        retired.remove(stage(300))
        check(!retired.contains(stage(300)) && retired.contains(stage(299)) && retired.contains(stage(301)), "an explicit history selection un-retires exactly one segment")
        retired.formUnion([ReplyIdentity.id(conversation: "https://claude.ai/chat/a", ordinal: 400)])
        check(!retired.contains(chat), "message numbers far below the tracked window are dropped")
        retired.formUnion([ReplyIdentity.id(conversation: "https://claude.ai/chat/c", ordinal: 1)])
        check(!retired.contains(stage(1)), "only the most recent conversations are kept")
        retired.formUnion(["draft-1", "draft-2", "draft-3"])
        check(!retired.contains("draft-1") && retired.contains("draft-3"), "non-reply identities keep a fixed-size window")
    }

    /// Review issue 1: a blank thinking card from the real decoder is a normal wait.
    @MainActor static func thinkingWait() async throws {
        let thinking = ReplyNode(role: "AXGroup", label: "Message 4 of 4", children: [
            .init(role: "AXGroup", children: [.init(role: "AXHeading", label: "Claude responded:"), .init(role: "AXStaticText", text: "")])
        ])
        let monitor = ReplyMonitor(); var now: TimeInterval = 0
        monitor.clock = { now }; monitor.watching = true
        var structuralSeen = false
        for second in 0...120 {
            now = TimeInterval(second)
            do { _ = try ClaudeDecoder.recentMessages([thinking]); check(false, "a thinking card must not decode") }
            catch { structuralSeen = structuralSeen || (error as? ReplyReadPending)?.structural == true; monitor.handleReadFailure(error) }
        }
        check(!structuralSeen && monitor.readError == nil && monitor.readRetrySeconds == 1 && monitor.watching,
              "a lone thinking card with its author marker waits two minutes without an interface warning")
        let relabelled = ReplyNode(role: "AXGroup", label: "Message 4 of 4", children: [
            .init(role: "AXGroup", children: [.init(role: "AXHeading", label: "Claude a répondu :"), .init(role: "AXStaticText", text: "Réponse")])
        ])
        do { _ = try ClaudeDecoder.recentMessages([relabelled]); check(false, "unknown labels must not decode") }
        catch { check((error as? ReplyReadPending)?.structural == true, "a card without any recognised author marker is still a structural failure") }
        monitor.stop()
    }

    /// A slice whose translation already started is revised; its late result is discarded.
    @MainActor static func lateRevision() async throws {
        var gates: [String: CheckedContinuation<String, Never>] = [:]
        var published: [String] = []
        let pipeline = ReplyPipeline(concurrency: 2) { text in await withCheckedContinuation { gates[text] = $0 } }
        pipeline.onTranslation = { _, _, value, _ in published.append(value) }
        pipeline.observe(conversation: "late", messages: [.init(ordinal: 2, author: .assistant, text: "Alpha stage is complete.\n\nTail")], responseComplete: false, now: 0)
        try await settle { gates["Alpha stage is complete."] != nil }
        pipeline.observe(conversation: "late", messages: [.init(ordinal: 2, author: .assistant, text: "Alpha stage was revised.\n\nTail")], responseComplete: false, now: 1)
        try await settle { gates["Alpha stage was revised."] != nil }
        gates.removeValue(forKey: "Alpha stage is complete.")?.resume(returning: "OLD")
        try await Task.sleep(for: .milliseconds(30))
        gates.removeValue(forKey: "Alpha stage was revised.")?.resume(returning: "NEW")
        try await settle { published.contains { $0.hasPrefix("NEW") } }
        check(!published.contains { $0.contains("OLD") } && published.last?.hasPrefix("NEW") == true,
              "a stale result that arrives after its slice was revised is never published")
        pipeline.tick(now: 10)
        try await settle { gates["Tail"] != nil }
        gates.removeValue(forKey: "Tail")?.resume(returning: "T")
        try await settle { !pipeline.busy }
        check(!pipeline.busy, "the superseded request does not keep a concurrency slot")
    }

    /// Review issue 3: quotation is semantic across languages.
    static func quotes() {
        func clean(_ output: String, _ source: String) -> String? { try? TranslationCleanup.normalize(output, source: source) }
        check(clean("“你好。”", "\"Hello.\"") == "“你好。”", "straight source quotes keep Chinese curved quotes")
        check(clean("「こんにちは。」", "\"Hello.\"") == "「こんにちは。」", "straight source quotes keep Japanese corner quotes")
        check(clean("『引用』", "“Quote”") == "『引用』", "curved source quotes keep Japanese double corner quotes")
        check(clean("“你好。”", "'Hello.'") == "“你好。”", "single-quoted sources keep their translated quotation")
        check(clean("\"Hallo.\"", "「你好。」") == "\"Hallo.\"", "corner-quoted Chinese keeps translated straight quotes")
        check(clean("“你好。”", "Hello.") == "你好。", "quotes added around an unquoted source are still removed")
        check(clean("“A”或“B”", "Use A or B") == "“A”或“B”", "two separate quotations are never mistaken for a wrapper")
        check(clean("'tis done'", "It is done") == "'tis done'", "apostrophes are never stripped as quotes")
    }

    /// Review issue 2: re-reading one Code reply with 600 segments changes nothing.
    @MainActor static func longStages() async throws {
        let model = TranslatorModel(permissionCheck: { true }, remoteKeyRead: { _ in "" })
        defer { model.replies.stop(); model.stopPermissionMonitoring() }
        var requests = 0
        model.replies.testTranslation = { text in requests += 1; return "中文:" + text }
        model.replies.watching = true
        let messages: [ChatMessage] = (1...600).map {
            .init(ordinal: 2, author: .assistant, text: "Finished research stage \($0).", segment: $0, completed: true)
        }
        let snapshot = ReplySnapshot(conversation: "https://claude.ai/code/review-large-stages", messages: messages, foundTranscript: true, responseComplete: true)
        func settled() -> Bool { !model.replies.translating && model.history.filter { !$0.isUser && !$0.chinese.isEmpty }.count == 10 }
        model.replies.ingest(snapshot, now: 0)
        try await settle(15) { settled() }
        let firstRequests = requests, firstRevision = model.chatRevision, firstIDs = model.history.map(\.id)
        check(model.history.last?.foreign == "Finished research stage 600." && model.history.first?.foreign == "Finished research stage 591.",
              "the first read of 600 segments shows the latest ten")
        for pass in 1...3 {
            model.replies.ingest(snapshot, now: TimeInterval(pass * 5))
            try await Task.sleep(for: .milliseconds(100))
            try await settle(15) { settled() }
        }
        check(requests == firstRequests, "re-reading the identical 600-segment reply sends no further requests (\(requests - firstRequests) extra)")
        check(model.history.map(\.id) == firstIDs, "the latest ten segments are not replaced by older ones")
        check(model.chatRevision == firstRevision, "re-reading causes no scroll updates (\(model.chatRevision - firstRevision) extra)")
        check(model.replies.pipelineRecordCount <= 10, "the pipeline still holds at most the visible window")
    }

    @MainActor static func memory() async throws {
        let model = TranslatorModel(permissionCheck: { true })
        defer { model.stopPermissionMonitoring() }
        model.replies.testTranslation = { "中文" + $0 }
        model.replies.watching = true
        var messages: [ChatMessage] = []
        let conversation = "https://claude.ai/chat/memory"
        for turn in 1...30 {
            messages.append(.init(ordinal: turn * 2 - 1, author: .user, text: "Question \(turn)"))
            messages.append(.init(ordinal: turn * 2, author: .assistant, text: "Answer number \(turn) is here."))
            model.replies.ingest(ReplySnapshot(conversation: conversation, messages: Array(messages.suffix(16)), foundTranscript: true, responseComplete: true),
                                 now: TimeInterval(turn))
            try await settle { model.history.contains { $0.foreign == "Answer number \(turn) is here." && !$0.chinese.isEmpty } }
        }
        let replies = model.history.filter { !$0.isUser }
        check(replies.count == 10 && replies.last?.foreign == "Answer number 30 is here.", "after 30 replies the visible history keeps the latest ten")
        check(model.replies.pipelineRecordCount <= 10, "the translation pipeline keeps no more records than the visible window (\(model.replies.pipelineRecordCount))")
        // Turns 16-20 were evicted but are still on screen in this snapshot.
        model.replies.ingest(ReplySnapshot(conversation: conversation, messages: Array(messages.suffix(30)), foundTranscript: true, responseComplete: true), now: 40)
        try await Task.sleep(for: .milliseconds(50))
        check(model.history.filter { !$0.isUser }.count == 10 && !model.history.contains { $0.foreign == "Answer number 18 is here." },
              "evicted replies still visible in Claude are not re-added")
        model.replies.stop()
    }
}
