import Foundation
import AppKit

@main struct ReviewRegressionTests {
    static var count = 0
    static var failures = 0
    @MainActor static func check(_ condition: Bool, _ name: String) {
        count += 1
        if condition { print("PASS: " + name) }
        else { failures += 1; print("FAIL: " + name) }
    }
    @MainActor static func settle(_ pipeline: ReplyPipeline) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while pipeline.busy, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(2)) }
        check(!pipeline.busy, "bounded synthetic work reaches an idle state")
    }
    @MainActor static func main() async throws {
        setvbuf(stdout, nil, _IONBF, 0)
        _ = NSApplication.shared
        let stages = [ChatMessage(ordinal: 2, author: .assistant, text: "First stage.", segment: 1, completed: true),
                      ChatMessage(ordinal: 2, author: .assistant, text: "Second stage.", segment: 2, completed: true)]
        var cloud = 0, local = 0
        let limited = ReplyPipeline(incremental: false) { _ in cloud += 1; throw ServiceCooldown(seconds: 60) }
        limited.fallback = { _ in local += 1; return "阶段中文。" }
        limited.observe(conversation: "limited", messages: stages, responseComplete: true, now: 100)
        try await settle(limited)
        check(cloud == 1 && local == 2, "local stages continue while the primary service honors Retry-After")

        var retryCalls = 0, recovered = ""
        let retry = ReplyPipeline(incremental: false) { _ in
            retryCalls += 1
            if retryCalls == 1 { throw ServiceCooldown(seconds: 60) }
            return "恢复中文。"
        }
        retry.fallback = { _ in throw BridgeError.message("Synthetic local service failure") }
        retry.onTranslation = { _, _, value, _ in recovered = value }
        retry.observe(conversation: "retry", messages: [.init(ordinal: 2, author: .assistant, text: "Stable reply.")], responseComplete: true, now: 100)
        try await settle(retry)
        retry.tick(now: 159)
        try await settle(retry)
        check(retryCalls == 1, "a failed fallback cannot cause early primary retries")
        retry.tick(now: 161)
        try await settle(retry)
        check(retryCalls == 2 && recovered == "恢复中文。", "a failed fallback preserves the primary cooldown recovery condition")
        limited.cancel(); retry.cancel()

        let suite = "achu-review-regression-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func evidence(_ sequence: Int) -> UsageEvidence {
            .init(source: .statusLine, binding: "cli-fixture", snapshot: .init(fiveHour: nil, sevenDay: .init(usedPercentage: 25, resetsAt: nil), observedAt: Date()),
                  identity: .init(fingerprint: String(repeating: "a", count: 64), displayName: "Synthetic A"), epoch: "fixture", sequence: sequence)
        }
        let usage = ClaudeUsageMonitor(settings: defaults, enabled: { false })
        usage.follow(channel: .cli, binding: "cli-fixture")
        usage.receive(evidence(1))
        check(usage.snapshot != nil, "a verified connected CLI report is visible")
        usage.awaitChatEntrance()
        usage.receive(evidence(2))
        check(usage.snapshot == nil && usage.awaitingEntrance && usage.accountDisplayName == "账户待核对", "waiting for an entrance hides old quota and account identity")
        let restarted = ClaudeUsageMonitor(settings: defaults, enabled: { false })
        restarted.awaitChatEntrance(); restarted.receive(evidence(3))
        check(restarted.snapshot == nil && restarted.awaitingEntrance, "saved CLI preferences cannot publish quota before a startup connection")
        check(!restarted.candidates(for: .cli).isEmpty, "waiting may collect candidates without publishing quota")
        usage.stop(); restarted.stop()

        let monitor = ReplyMonitor()
        monitor.testTranslation = { _ in "回复中文。" }
        var completions = 0
        monitor.onReplyCompleted = { completions += 1 }
        for conversation in ["https://claude.ai/chat/first", "https://claude.ai/chat/second"] {
            let snapshot = ReplySnapshot(conversation: conversation, messages: [.init(ordinal: 2, author: .assistant, text: "Same response.")], foundTranscript: true, responseComplete: true)
            monitor.ingest(snapshot); monitor.ingest(snapshot)
        }
        check(completions == 2, "identical replies in distinct conversations refresh once for each conversation")
        monitor.stop()

        check(SystemTranslationProtection.corrected("这个发现是偶然的。", source: "The finding was due to chance.") == "这个发现是偶然的。", "chance does not become an invented random-level claim")
        check(SystemTranslationProtection.corrected("这位法官不偏不倚。", source: "The judge was unbiased.") == "这位法官不偏不倚。", "a judge is not rewritten into a statistical estimator")
        check(SystemTranslationProtection.corrected("汽车的发动机停止了。", source: "The car engine stopped.") == "汽车的发动机停止了。", "ordinary mechanical terminology remains unchanged")
        check(SystemTranslationProtection.corrected("界面支持功能选择。", source: "The UI supports feature selection.") == "界面支持功能选择。", "software features do not inherit an inferred statistical domain")
        var negative = false
        do {
            _ = try await TranslationFidelity.$target.withValue(.foreign(.english)) {
                try await TextTranslation.run("负零点三") { _ in "-0.3" }
            }
            negative = true
        } catch { }
        check(negative, "a translated negative decimal is not an invented Markdown list")
        var listRejected = false
        do { try TranslationFidelity.validate(source: "请解释。", translation: "- First\n- Second", target: .foreign(.english)) }
        catch { listRejected = true }
        check(listRejected, "real invented Markdown lists remain rejected")
        var chineseList = false
        do { try TranslationFidelity.validate(source: "步骤：\n1、生成数据\n2、选择特征", translation: "Steps:\n1. Generate data\n2. Select features", target: .foreign(.english)); chineseList = true }
        catch { }
        check(chineseList, "Chinese enumeration without spaces remains a source list")

        let marker = ReplyNode(role: "AXGroup", label: "Message 9", children: [.init(role: "AXGroup", children: [.init(role: "AXHeading", label: "Claude responded: Example")])])
        let formal = ReplyNode(role: "AXGroup", label: "Message 9", children: [marker, .init(role: "AXStaticText", text: "How is Claude doing this session?")])
        check(ClaudeDecoder.codeSegments(formal, responseComplete: true).map(\.text).joined() == "How is Claude doing this session?", "formal reply text may quote the same words as an interface prompt")
        let runningProse = ReplyNode(role: "AXGroup", label: "Message 9", children: [marker,
            .init(role: "AXGroup", label: "Currently streaming message", children: [
                .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: "running"),
                    .init(role: "AXStaticText", text: "This is the state label explained in the formal answer.")])], isStreamingAssistant: true)])
        check(ClaudeDecoder.codeSegments(runningProse, responseComplete: true).map(\.text).joined().contains("state label explained"), "formal explanation of a running state is not removed as a tool")

        var calls = 0
        let literal = try await SystemTranslationProtection.translate("Open 繁體.md now.", toChinese: true) { text in
            calls += 1; return text.contains("⟦") ? "打開 ⟦1⟧。" : "打開 繁體.md。"
        }
        check(literal == "打开 繁體.md。", "script conversion changes prose before restoring protected filenames")
        check(calls == 1, "script conversion does not need another translation request")
        print("\(count) review regression checks; \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
