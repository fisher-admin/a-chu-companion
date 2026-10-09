import Foundation

@main struct FailoverTests {
    static var passed = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
        passed += 1
        print("PASS: \(name)")
    }
    static func rejected(_ source: String, _ output: String, _ direction: TranslationDirection) -> TranslationRejected.Reason? {
        do { _ = try TranslationGuard.check(source: source, output: output, direction: direction); return nil }
        catch let error as TranslationRejected { return error.reason }
        catch { return nil }
    }

    @MainActor static func main() async throws {
        try guardTests()
        circuitTests()
        try await failoverTests()
        print("\(passed) failover tests passed")
    }

    static func guardTests() throws {
        let zh = "请先运行 `swift test`，然后查看 https://example.com/guide 里的说明。如果仍然失败，把完整日志发给我。"
        let faithful: [(TranslationDirection, String)] = [
            (.fromChinese(.english), "Please run `swift test` first, then read the instructions at https://example.com/guide. If it still fails, send me the full log."),
            (.fromChinese(.german), "Bitte führe zuerst `swift test` aus und lies dann die Anleitung unter https://example.com/guide. Wenn es weiterhin fehlschlägt, schick mir das vollständige Protokoll."),
            (.fromChinese(.japanese), "まず `swift test` を実行してから、https://example.com/guide の説明を確認してください。それでも失敗する場合は、完全なログを送ってください。"),
            (.fromChinese(.korean), "먼저 `swift test`를 실행한 다음 https://example.com/guide 의 설명을 확인하세요. 그래도 실패하면 전체 로그를 보내 주세요.")
        ]
        for (direction, output) in faithful {
            check((try? TranslationGuard.check(source: zh, output: output, direction: direction)) == output, "faithful \(direction.targetName) translation accepted")
            check((try? TranslationGuard.check(source: output, output: zh, direction: .toChinese(direction.foreign))) == zh, "faithful \(direction.foreign.englishName) → Chinese accepted")
        }
        let english = "Run the migration first. If the schema check fails, roll back with `make rollback` and tell me which table was affected."
        let chinese = "先运行迁移。如果模式检查失败，用 `make rollback` 回滚，并告诉我哪张表受到了影响。"
        let reverse = TranslationDirection.toChinese(.english)
        check((try? TranslationGuard.check(source: english, output: "<source>" + chinese + "</source>", direction: reverse)) == chinese, "echoed wrapper tags are removed")
        check((try? TranslationGuard.check(source: english, output: "“" + chinese + "”", direction: reverse)) == chinese, "added outer quotes are removed")
        check(rejected(english, "以下是翻译：" + chinese, reverse) == .preamble, "translation preamble rejected")
        check(rejected(english, "先运行迁移。如果模式检查失败，回滚并告诉我哪张表受到了影响。", reverse) == .inlineCode, "dropped inline code rejected")
        check(rejected("Check https://example.com/a and report back to me today.", "请查看链接并在今天回复我。", reverse) == .url, "dropped URL rejected")
        check(rejected("Use this:\n```sh\nmake\n```\nThen tell me what happens next.", "使用这个：make 然后告诉我接下来发生了什么。", reverse) == .codeFence, "removed code fence rejected")
        check(rejected("Before I start, which version are you on? Reply with just the number.", "18", reverse) == .length, "answering instead of translating rejected by length")
        let rambling = String(repeating: "我认为这是一个很好的问题，我们需要从多个角度仔细地分析它的背景和影响。", count: 6)
        check(rejected("Why?", rambling, reverse) == .length, "long answer to a short question rejected")
        check(rejected(zh, "请先运行 `swift test`，然后查看 https://example.com/guide 里的说明。如果仍然失败，把完整日志发给我。", .fromChinese(.english)) == .language, "untranslated Chinese rejected for English")
        check(rejected(zh, faithful[2].1, .fromChinese(.korean)) == .language, "wrong target script rejected")
        check(rejected(english, "Run the migration first. If the schema check fails, roll back with `make rollback` and tell me which table was affected.", reverse) == .language, "untranslated English rejected for Chinese")
        let quoted = "Translation: the word means \"bridge\" in this context, see `glossary.md` for more."
        check(rejected(quoted, "翻译：这个词在此语境中的意思是“桥”，更多内容请参阅 `glossary.md`。", reverse) == nil, "marker that exists in the source is not a preamble")
        check(rejected("Sure, I agree with that plan completely.", "当然，我完全同意这个计划。", reverse) == nil, "natural openings such as Sure are allowed")
        check(rejected("OK", "好的", reverse) == nil, "short fragments are not ratio-checked")
        check(rejected("Run npm install now, then restart the dev server.", "立即运行 npm install，然后重启 dev server。", reverse) == nil, "Chinese mixed with kept identifiers is accepted")
        check(rejected("请重启服务。", "好的，我会重启服务。", .fromChinese(.english)) == .language, "a short Chinese reply instead of English is rejected")
        check(rejected("了解。", "了解。", .fromChinese(.japanese)) == nil, "short kanji-only Japanese is accepted")
    }

    @MainActor static func circuitTests() {
        var clock = Date(timeIntervalSince1970: 1_000)
        let circuit = AICircuit(threshold: 3, window: 60, baseCooldown: 60, maxCooldown: 600, now: { clock })
        let a = circuit.acquire()!, b = circuit.acquire()!, c = circuit.acquire()!
        circuit.failed(a); circuit.failed(b)
        check(circuit.state == .closed, "below threshold stays closed")
        circuit.failed(c)
        check(circuit.state == .open(until: clock.addingTimeInterval(60)) && circuit.acquire() == nil, "threshold failures open the circuit")
        clock += 61
        let probe = circuit.acquire()
        check(probe != nil && circuit.state == .halfOpen && circuit.acquire() == nil, "after cooldown exactly one probe is allowed")
        circuit.failed(probe!)
        check(circuit.state == .open(until: clock.addingTimeInterval(120)), "failed probe reopens with doubled cooldown")
        clock += 121
        let second = circuit.acquire()!
        circuit.released(second)
        check(circuit.state == .halfOpen && circuit.acquire() != nil, "cancelled probe releases its slot")
        circuit.reset()
        let x = circuit.acquire()!, y = circuit.acquire()!
        circuit.failed(x); circuit.failed(y)
        let z = circuit.acquire()!
        circuit.succeeded(z)
        circuit.failed(circuit.acquire()!)
        check(circuit.state == .closed, "a success clears the failure history without invalidating peers")
        circuit.failed(circuit.acquire()!, retryAfter: 30)
        check(circuit.state == .open(until: clock.addingTimeInterval(30)), "Retry-After opens for the requested time")
        circuit.reset()
        let stale = circuit.acquire()!
        circuit.failed(circuit.acquire()!, severe: true)
        check(circuit.state == .open(until: clock.addingTimeInterval(600)), "rejected credentials open for the maximum cooldown")
        clock += 601
        let recovery = circuit.acquire()!
        circuit.failed(stale); circuit.failed(stale); circuit.failed(stale)
        check(circuit.state == .halfOpen, "late failures from an older state are ignored")
        circuit.succeeded(recovery)
        check(circuit.state == .closed, "successful probe closes the circuit")
    }

    @MainActor static func failoverTests() async throws {
        let english = TranslationDirection.fromChinese(.english)
        let source = "请检查配置文件，然后重新启动服务。"
        let good = "Please check the configuration file and then restart the service."
        var aiCalls = 0, systemCalls = 0
        var aiBehavior: () async throws -> String = { good }
        var reasons: [FallbackReason] = []
        func make(preferAI: Bool = true, circuit: AICircuit? = nil, timeout: Duration = .seconds(2)) -> FailoverTranslator {
            let translator = FailoverTranslator(preferAI: preferAI, circuit: circuit, aiTimeout: { _ in timeout },
                                                ai: { _, _ in aiCalls += 1; return try await aiBehavior() },
                                                system: { text, _ in systemCalls += 1; return "SYSTEM(\(text.count))" })
            translator.onFallback = { reasons.append($0) }
            return translator
        }
        func reset() { aiCalls = 0; systemCalls = 0; reasons = []; aiBehavior = { good } }

        var t = make(preferAI: false)
        let r1 = try await t.translate(source, direction: english)
        check(r1 == "SYSTEM(\(source.count))" && aiCalls == 0 && reasons.isEmpty, "system engine by default; AI never contacted")
        reset(); t = make()
        let r2 = try await t.translate(source, direction: english)
        check(r2 == good && t.lastEngine == .ai && systemCalls == 0, "AI result used when it passes the guard")

        reset(); let circuit = AICircuit(); t = make(circuit: circuit)
        aiBehavior = { throw AIError.http(status: 429, retryAfter: 45) }
        let r3 = try await t.translate(source, direction: english)
        check(r3.hasPrefix("SYSTEM") && reasons == [.rateLimited], "429 falls back seamlessly")
        if case .open = circuit.state { check(true, "429 opens the circuit") } else { check(false, "429 opens the circuit") }
        aiCalls = 0
        _ = try await t.translate(source, direction: english)
        check(aiCalls == 0 && reasons.last == .circuitOpen, "open circuit skips AI entirely")

        reset(); t = make(timeout: .milliseconds(50))
        aiBehavior = { try await Task.sleep(for: .seconds(5)); return good }
        let started = ContinuousClock.now
        let r4 = try await t.translate(source, direction: english)
        check(r4.hasPrefix("SYSTEM") && reasons == [.timeout], "AI timeout falls back")
        check(ContinuousClock.now - started < .seconds(2), "timeout fallback does not wait for the slow request")

        reset(); t = make()
        aiBehavior = { "以下是翻译：Please check the configuration file and then restart the service." }
        let r5 = try await t.translate(source, direction: english)
        check(r5.hasPrefix("SYSTEM") && reasons == [.rejected(.preamble)], "guard rejection falls back")
        reset(); t = make()
        aiBehavior = { "好的，我会检查配置文件。" }
        let r6 = try await t.translate(source, direction: english)
        check(r6.hasPrefix("SYSTEM") && reasons == [.rejected(.language)], "a reply in the wrong language falls back")

        reset(); t = make()
        aiBehavior = { throw URLError(.notConnectedToInternet) }
        _ = try await t.translate(source, direction: english)
        check(reasons == [.network], "network failure falls back")

        reset(); t = make()
        aiBehavior = { throw AIError.http(status: 401, retryAfter: nil) }
        _ = try await t.translate(source, direction: english)
        check(reasons == [.unauthorized], "rejected key falls back and is reported")
        if case .open = t.circuit.state { check(true, "rejected key pauses AI") } else { check(false, "rejected key pauses AI") }

        reset(); t = make()
        aiBehavior = { try await Task.sleep(for: .seconds(5)); return good }
        let cancelled = Task { @MainActor in try await t.translate(source, direction: english) }
        try await Task.sleep(for: .milliseconds(50))
        cancelled.cancel()
        do { _ = try await cancelled.value; check(false, "cancellation must not fall back") }
        catch is CancellationError { check(systemCalls == 0 && reasons.isEmpty && t.circuit.state == .closed, "cancellation never falls back or counts as failure") }

        reset(); t = make()
        let long = String(repeating: "请检查配置文件，然后重新启动服务。", count: 12)
        aiBehavior = { throw TranslationChunkError.tooLarge }
        do { _ = try await t.translate(long, direction: english); check(false, "oversized piece is split first") }
        catch TranslationChunkError.tooLarge { check(systemCalls == 0 && t.circuit.state == .closed, "oversized piece is returned for splitting, not counted as failure") }
        _ = try await TextTranslation.run(long, limit: 3_000) { chunk in try await t.translate(chunk, direction: english) }
        check(systemCalls > 1 && reasons.allSatisfy { $0 == .failed }, "pieces that stay oversized at the minimum size use system translation")

        reset()
        let failing = FailoverTranslator(preferAI: true, ai: { _, _ in throw AIError.http(status: 503, retryAfter: nil) },
                                         system: { _, direction in throw SystemUnavailableStub(direction: direction) })
        do { _ = try await failing.translate(source, direction: english); check(false, "both engines failing is an error") }
        catch let error as FailoverExhausted { check(error.reason == .http(503) && error.localizedDescription.contains("系统翻译也失败"), "both engines failing reports both causes") }

        reset(); t = make()
        var order: [Int] = []
        aiBehavior = { good }
        _ = try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<6 { group.addTask { @MainActor in _ = try await t.translate(source, direction: english); order.append(index) } }
            try await group.waitForAll()
        }
        check(order.count == 6 && aiCalls == 6, "concurrent calls each resolve exactly once")
    }
}

struct SystemUnavailableStub: LocalizedError {
    let direction: TranslationDirection
    var errorDescription: String? { "stub unavailable" }
}
