import Foundation

struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@main struct StreamPipelineTests {
    static var passed = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
        passed += 1
        print("PASS: \(name)")
    }

    static let reply = """
    Sure. Here is the plan for the migration, e.g. the schema first. Dr. Smith reviewed it at 3.14 p.m. yesterday!

    1. Back up the database before you start.
    2. Run the script below. It is idempotent.

    ```swift
    let value = 1. description
    // A blank line inside code must not split it.

    print("Done. Really?")
    ```

    | Step | Note. With period |
    | --- | --- |
    | One | Keep. Together |

    Call `config.load(). reset()` once. Then restart the service and wait for the health check to pass.
    这是第一句中文说明，内容足够长。第二句也要保持完整！最后一句？
    日本語の説明もあります。こちらは二文目です。
    """

    static func segments(of text: String, chunks: [Int]?, snapshots: Bool) -> [StreamSegment] {
        var segmenter = StreamSegmenter()
        var all: [StreamSegment] = []
        guard let chunks else { return segmenter.finish(snapshot: text).segments }
        let characters = Array(text)
        var offset = 0
        for size in chunks where offset < characters.count {
            let end = min(characters.count, offset + size)
            if snapshots {
                let update = segmenter.update(snapshot: String(characters[0..<end]))
                precondition(update.invalidatedFrom == nil, "growing snapshots never invalidate")
                all += update.segments
            } else {
                all += segmenter.append(String(characters[offset..<end]))
            }
            offset = end
        }
        all += snapshots ? segmenter.finish(snapshot: text).segments : segmenter.finish().segments
        return all
    }

    static func cut(_ text: String, minimumLength: Int = 20) -> [String] {
        var segmenter = StreamSegmenter(minimumLength: minimumLength)
        return segmenter.finish(snapshot: text).segments.map(\.text)
    }

    @MainActor static func main() async throws {
        segmenterTests()
        try await pipelineTests()
        print("\(passed) stream tests passed")
    }

    static func segmenterTests() {
        let whole = segments(of: reply, chunks: nil, snapshots: false)
        check(whole.map(\.text).joined() == reply, "joined segments reproduce the reply exactly")
        var rng = SplitMix(state: 42)
        var identical = true
        for round in 0..<400 {
            let chunks = (0..<reply.count).map { _ in Int.random(in: 1...(round.isMultiple(of: 2) ? 3 : 40), using: &rng) }
            identical = identical && segments(of: reply, chunks: chunks, snapshots: round.isMultiple(of: 3)) == whole
        }
        check(identical, "400 random chunkings (deltas and snapshots) produce identical segments")

        let code = whole.filter { $0.kind == .code }
        check(code.count == 1 && code[0].text.hasPrefix("```swift\n") && code[0].text.contains("print(\"Done. Really?\")\n```"),
              "fenced code block is one pass-through segment, blank lines inside included")
        check(!whole.contains { $0.kind == .prose && $0.text.contains("```") }, "no prose segment contains a fence")
        let prose = whole.filter { $0.kind == .prose }.map(\.text)
        check(prose.contains { $0.hasSuffix("e.g. the schema first. ") } && prose.contains { $0.hasPrefix("Dr. Smith reviewed it at 3.14 p.m. yesterday!") },
              "abbreviations, titles and decimals never end a sentence")
        check(prose.contains { $0.hasPrefix("1. Back up") } && prose.contains { $0.hasPrefix("2. Run the script") },
              "numbered list items start their own segments")
        check(prose.contains { $0.contains("| Step | Note. With period |\n| --- | --- |\n| One | Keep. Together |") }, "table rows are never split")
        check(prose.contains { $0.contains("`config.load(). reset()` once.") }, "inline code is never split")
        check(prose.contains { $0.hasSuffix("内容足够长。") } && prose.contains { $0.hasPrefix("第二句也要保持完整！") }, "Chinese sentences split at 。！？")
        check(prose.contains { $0.contains("日本語の説明もあります。") }, "Japanese text is segmented")

        check(cut("Yes. No. Maybe so, I think that it is fine. Next one is here.") == ["Yes. No. Maybe so, I think that it is fine. ", "Next one is here."],
              "short sentences merge up to the minimum length")
        check(cut("Ends with a quote, said the narrator.\" Then the story continues.") == ["Ends with a quote, said the narrator.\" ", "Then the story continues."],
              "closing quotes stay with their sentence")
        let paragraph = String(repeating: "word ", count: 400)
        let forced = cut(paragraph)
        check(forced.allSatisfy { $0.count <= 800 } && forced.joined() == paragraph && forced.count > 1, "overlong text without sentence ends is cut at word boundaries")

        var waiting = StreamSegmenter()
        check(waiting.append("This first sentence is long enough.").isEmpty, "no cut until text after the boundary arrives")
        check(waiting.append(" ").isEmpty, "whitespace alone does not prove the boundary")
        check(waiting.append("Next").map(\.text) == ["This first sentence is long enough. "], "cut is emitted as soon as the boundary is proven")
        check(waiting.append("\n```py\nx = 1.\n\nmore").map(\.text) == ["Next\n"] && waiting.segments.count == 2, "prose before an open fence is cut; the unclosed block waits")
        check(waiting.append("\n```").isEmpty, "a closing fence needs its line end")
        check(waiting.append("\nAfter.").first?.kind == .code, "the block is emitted once closed")

        var ansi = StreamSegmenter()
        _ = ansi.append("\u{1B}[1;3")
        _ = ansi.append("1mRed text is long enough here.\u{1B}[0m\r")
        _ = ansi.append("\n\u{1B}]0;title\u{07}Next line.\u{1B}(B")
        _ = ansi.finish()
        check(ansi.segments.map(\.text).joined() == "Red text is long enough here.\nNext line." && ansi.text == "Red text is long enough here.\nNext line.",
              "ANSI CSI/OSC/charset sequences and CRLF split across chunks are removed")

        var snapshot = StreamSegmenter()
        let first = "Alpha sentence is long enough here. Beta sentence is long enough too. Gamma"
        check(snapshot.update(snapshot: first).segments.count == 2, "snapshot segments emitted")
        check(snapshot.update(snapshot: String(first.prefix(50))) == SegmenterUpdate(), "a shorter transient snapshot is ignored")
        let revised = snapshot.update(snapshot: "Alpha sentence is long enough here. BETA sentence is long enough too. Gamma ray. ")
        check(revised.invalidatedFrom == 1 && revised.segments.first?.index == 1 && revised.segments.first?.text.hasPrefix("BETA") == true,
              "an edited earlier sentence invalidates only from that segment")
        check(snapshot.finish().segments.map(\.text).joined() == "Gamma ray. " && snapshot.text.hasSuffix("Gamma ray. "), "finish flushes the remainder")
    }

    @MainActor static func pipelineTests() async throws {
        let source = reply
        let segmenter = { () -> [StreamSegment] in var s = StreamSegmenter(); return s.finish(snapshot: source).segments }()
        let expected = segmenter.map { $0.kind == .prose ? $0.text.uppercased() : $0.text }.joined()
        var inFlight = 0, peak = 0, translatedTexts: [String] = []
        var states: [StreamTranslationPipeline.State] = []
        let pipeline = StreamTranslationPipeline(maxConcurrent: 3) { text in
            inFlight += 1; peak = max(peak, inFlight); translatedTexts.append(text)
            defer { inFlight -= 1 }
            // Earlier segments take longer, so completions arrive out of order.
            try await Task.sleep(for: .milliseconds(max(5, 60 - translatedTexts.count * 6)))
            return text.uppercased()
        }
        pipeline.onUpdate = { states.append($0) }
        var rng = SplitMix(state: 7)
        let characters = Array(source)
        var offset = 0
        while offset < characters.count {
            offset = min(characters.count, offset + Int.random(in: 1...25, using: &rng))
            pipeline.ingest(snapshot: String(characters[0..<offset]))
            await Task.yield()
        }
        pipeline.finish(snapshot: source)
        while !pipeline.state.complete { try await Task.sleep(for: .milliseconds(10)) }
        check(pipeline.state.translated == expected, "streamed translation equals the in-order full translation")
        let ordered = states.allSatisfy { state in
            expected.hasPrefix(state.translated) && state.translated == segmenter.prefix(state.renderedSegments).map { $0.kind == .prose ? $0.text.uppercased() : $0.text }.joined()
        }
        check(ordered && states.count > 3, "every rendered state is an in-order prefix even though tasks finished out of order")
        check(peak <= 3 && peak > 1, "translation runs concurrently within the limit")
        check(!translatedTexts.contains { $0.contains("```") || $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, "code and whitespace are never sent for translation")

        var gate: CheckedContinuation<Void, Never>?
        var calls: [String] = []
        let revising = StreamTranslationPipeline(maxConcurrent: 2) { text in
            calls.append(text)
            if text.hasPrefix("Beta") { await withCheckedContinuation { gate = $0 } }
            return "<" + text + ">"
        }
        revising.ingest(snapshot: "Alpha sentence is long enough here. Beta sentence is long enough too. Ga")
        while gate == nil { await Task.yield() }
        revising.ingest(snapshot: "Alpha sentence is long enough here. BETA sentence is long enough too. Ga")
        gate?.resume()
        revising.finish()
        while !revising.state.complete { try await Task.sleep(for: .milliseconds(5)) }
        check(revising.state.translated == "<Alpha sentence is long enough here. ><BETA sentence is long enough too. ><Ga>",
              "a revised segment replaces the stale in-flight result")

        var failOnce = true
        let flaky = StreamTranslationPipeline { text in
            if text.hasPrefix("Second"), failOnce { throw URLError(.timedOut) }
            return text.uppercased()
        }
        flaky.ingest(snapshot: "First sentence is long enough here. Second sentence is long enough too. Third sentence follows here.")
        flaky.finish()
        while !flaky.state.complete { try await Task.sleep(for: .milliseconds(5)) }
        check(flaky.state.translated == "FIRST SENTENCE IS LONG ENOUGH HERE. Second sentence is long enough too. THIRD SENTENCE FOLLOWS HERE." && flaky.state.failedSegments == [1],
              "a failed segment keeps its original text in place and later segments continue")
        failOnce = false
        flaky.retryFailed()
        while !flaky.state.complete || !flaky.state.failedSegments.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        check(flaky.state.translated == "FIRST SENTENCE IS LONG ENOUGH HERE. SECOND SENTENCE IS LONG ENOUGH TOO. THIRD SENTENCE FOLLOWS HERE.", "failed segments can be retried")

        var updatesAfterCancel = 0
        let cancelling = StreamTranslationPipeline { text in try await Task.sleep(for: .milliseconds(30)); return text }
        cancelling.ingest(snapshot: "First sentence is long enough here. Second sentence is long enough too. ")
        cancelling.cancel()
        cancelling.onUpdate = { _ in updatesAfterCancel += 1 }
        cancelling.ingest(snapshot: "First sentence is long enough here. Second sentence is long enough too. Third.")
        cancelling.finish()
        try await Task.sleep(for: .milliseconds(80))
        check(updatesAfterCancel == 0 && !cancelling.state.complete, "a cancelled pipeline publishes nothing further")

        var fallbacks: [FallbackReason] = []
        let translator = FailoverTranslator(preferAI: true, aiTimeout: { _ in .seconds(2) },
            ai: { text, _ in
                if text.contains("限流") { throw AIError.http(status: 429, retryAfter: nil) }
                return "EN:" + text
            },
            system: { text, _ in "SYS:" + text })
        translator.onFallback = { fallbacks.append($0) }
        let integrated = StreamTranslationPipeline(translator: translator, direction: .toChinese(.english))
        integrated.finish(snapshot: "这里是第一段足够长的说明文字。\n\n这一段会触发限流然后改用系统翻译。\n\n```sh\nmake test\n```\n")
        while !integrated.state.complete { try await Task.sleep(for: .milliseconds(5)) }
        check(integrated.state.translated == "EN:这里是第一段足够长的说明文字。\n\nSYS:这一段会触发限流然后改用系统翻译。\n\n```sh\nmake test\n```\n",
              "pipeline plugs into FailoverTranslator and keeps code verbatim")
        check(fallbacks.contains(.rateLimited) && integrated.state.translated.contains("SYS:这一段会触发限流"), "a rate-limited segment falls back without breaking order")
    }
}
