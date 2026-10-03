import Foundation

@main struct TranslationPipelineTests {
    @MainActor static func main() async throws {
        let source = "  " + String(repeating: "第一段保留😀。\n\n```swift\n  let x = 123\n```\n", count: 4_000) + "\n  "
        let pieces = TranslationChunks.split(source)
        precondition(pieces.count > 1 && pieces.allSatisfy { $0.count <= 3_000 }, "Long input must be split below the per-request size")
        precondition(pieces.joined() == source, "Partition must preserve every Unicode character and whitespace")
        print("PASS: >100k text, code, Unicode and whitespace partition without loss")
        var calls = 0
        let restored = try await TextTranslation.run(source) { chunk in calls += 1; return chunk }
        precondition(restored == source && calls > 1)
        print("PASS: full long translation merges without omissions or artificial paragraphs")
        var attempts = 0
        let adaptiveSource = String(repeating: "测试😀保持完整。", count: 100)
        let adaptive = try await TextTranslation.run(adaptiveSource) { chunk in
            attempts += 1
            if chunk.count > 128 { throw TranslationChunkError.tooLarge }
            return chunk
        }
        precondition(adaptive == adaptiveSource && attempts > 1)
        print("PASS: oversized or truncated chunks automatically split and recover fully")
        var failures = 0
        do {
            _ = try await TextTranslation.run(source) { chunk in
                failures += 1
                if failures == 2 { throw BridgeError.message("service failure") }
                return chunk
            }
            fatalError("Incomplete translation must never be returned")
        } catch { precondition(failures == 2) }
        print("PASS: normal service errors stop without returning a partial translation")
        let cancelled = Task { try await TextTranslation.run(source) { chunk in
            try await Task.sleep(nanoseconds: 100_000_000)
            return chunk
        } }
        cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("cancel must stop") }
        catch is CancellationError { print("PASS: cancellation stops long translation") }
        // Hosted runners may pause for longer than a few milliseconds. Keep a
        // generous per-piece margin while the complete run still exceeds it.
        let many = String(repeating: "测试", count: 600)
        let clock = ContinuousClock()
        let began = clock.now
        let perChunk = try await TextTranslation.run(many, limit: 100, timeout: .seconds(2)) { chunk in
            try await Task.sleep(for: .milliseconds(200)); return chunk
        }
        precondition(perChunk == many && began.duration(to: clock.now) > .seconds(2))
        print("PASS: total duration may exceed the per-chunk deadline while every chunk progresses")
        var lateContinuation: CheckedContinuation<String, Never>?
        var lateOperationFinished = false
        do {
            _ = try await TextTranslation.withDeadline(timeout: .seconds(2)) {
                let value = await withCheckedContinuation { lateContinuation = $0 }
                lateOperationFinished = true
                return value
            }
            fatalError("deadline must not wait for an uncooperative operation")
        } catch TranslationChunkError.timedOut { print("PASS: a blocked operation times out without trapping the caller") }
        // Release the operation only after the caller has returned. This also
        // exercises a late result without racing two short wall-clock sleeps.
        precondition(lateContinuation != nil && !lateOperationFinished)
        lateContinuation?.resume(returning: "late")
        while !lateOperationFinished { await Task.yield() }
        print("PASS: late completion after timeout cannot resume twice")
        print("8 translation pipeline tests passed")
    }
}
