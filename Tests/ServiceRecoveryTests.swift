import Foundation

@main struct ServiceRecoveryTests {
    static var count = 0, failures = 0
    @MainActor static func check(_ value: Bool, _ name: String) {
        count += 1
        if value { print("PASS: " + name) } else { failures += 1; print("FAIL: " + name) }
    }
    @MainActor static func settle(_ pipeline: ReplyPipeline) async throws {
        let end = ContinuousClock.now.advanced(by: .seconds(2))
        while pipeline.busy, ContinuousClock.now < end { try await Task.sleep(for: .milliseconds(2)) }
        check(!pipeline.busy, "scheduled work finishes without blocking source acquisition")
    }
    @MainActor static func main() async throws {
        var calls = 0, original = "", chinese = ""
        let recovered = ReplyPipeline(incremental: false) { _ in
            calls += 1
            if calls == 1 { throw ServiceTransientError(seconds: 2, reason: "Synthetic timeout") }
            return "恢复后的中文。"
        }
        recovered.onOriginal = { _, text, _ in original = text }
        recovered.onTranslation = { _, _, text, _ in chinese = text }
        let messages = [ChatMessage(ordinal: 2, author: .assistant, text: "A recovered translation.")]
        recovered.observe(conversation: "recovery", messages: messages, responseComplete: true, now: 0)
        try await settle(recovered)
        check(!original.isEmpty && chinese.isEmpty, "source is immediate during temporary service failure")
        recovered.tick(now: 1); try await settle(recovered)
        check(calls == 1, "temporary service retries respect the delay")
        recovered.tick(now: 2); try await settle(recovered)
        check(calls == 2 && !chinese.isEmpty, "temporary service failure recovers automatically")
        recovered.cancel()
        var failuresCalls = 0
        let bounded = ReplyPipeline(incremental: false) { _ in
            failuresCalls += 1; throw ServiceTransientError(seconds: 1, reason: "Synthetic overloaded service")
        }
        bounded.observe(conversation: "bounded", messages: messages, responseComplete: true, now: 0)
        try await settle(bounded)
        for value in [1.0, 3, 7, 60, 1_000] { bounded.tick(now: value); try await settle(bounded) }
        check(failuresCalls == 3 && bounded.hasFailures, "persistent transient failure stops after three attempts and remains explicitly retryable")
        bounded.cancel()
        var authCalls = 0
        let unauthorized = ReplyPipeline(incremental: false) { _ in authCalls += 1; throw BridgeError.message("Synthetic 403") }
        unauthorized.observe(conversation: "auth", messages: messages, responseComplete: true, now: 0)
        try await settle(unauthorized); unauthorized.tick(now: 1_000); try await settle(unauthorized)
        check(authCalls == 1, "authentication errors do not enter automatic retries")
        unauthorized.cancel()
        let monitor = ReplyMonitor(); monitor.watching = true
        for expected in [1.0, 2, 4, 8, 16, 32, 60, 60] {
            monitor.handleReadFailure(BridgeError.message("Synthetic AX interruption"))
            check(monitor.watching && monitor.readRetrySeconds == expected, "read recovery uses bounded backoff " + String(expected))
        }
        monitor.testTranslation = { _ in "恢复中文。" }
        monitor.ingest(.init(conversation: "recovered-read", messages: messages, foundTranscript: true, responseComplete: true))
        check(monitor.readRetrySeconds == 1 && monitor.watching, "successful capture restores one-second polling")
        monitor.stop(); monitor.handleReadFailure(BridgeError.message("Late callback"))
        check(!monitor.watching && monitor.readRetrySeconds == 1, "stopped reading stays stopped after a late failure")
        let gate = TranslationServiceGate()
        let first = try await gate.begin("synthetic-account-A", now: 100)
        let late = try await gate.begin("synthetic-account-A", now: 100)
        _ = await gate.fail(first, cooldown: 60, now: 100)
        await gate.success(late)
        do { _ = try await gate.begin("synthetic-account-A", now: 159); check(false, "late success cannot erase a newer cooldown") }
        catch let wait as ServiceCooldown { check(wait.seconds == 1, "late success cannot erase a newer cooldown") }
        let probe = try await gate.begin("synthetic-account-A", now: 160)
        do { _ = try await gate.begin("synthetic-account-A", now: 160); check(false, "only one recovery probe enters after cooldown") }
        catch is ServiceCooldown { check(true, "only one recovery probe enters after cooldown") }
        _ = try await gate.begin("synthetic-account-B", now: 101)
        check(true, "a different credential scope is independent")
        await gate.success(probe)
        _ = try await gate.begin("synthetic-account-A", now: 160)
        check(true, "successful recovery reopens the shared service gate")
        var request = URLRequest(url: URL(string: "https://example.org/models/translation")!)
        request.setValue("synthetic-private-value", forHTTPHeaderField: "Authorization")
        let scope = TranslationServiceGate.scope(request, provider: .openAI)
        check(!scope.contains("synthetic-private-value"), "service identity never includes the credential itself")
        let revoked = ReplyMonitor(); revoked.watching = true
        revoked.handleReadFailure(ReplyReadStopped(message: "Synthetic revoked permission"))
        check(!revoked.watching && revoked.status.contains("revoked"), "explicit permission loss stops with an actionable cause")
        print("\(count) service recovery checks; \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
