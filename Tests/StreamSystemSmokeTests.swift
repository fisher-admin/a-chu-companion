import Foundation
import Translation

/// Requires installed English↔Chinese system language packs (run via ./test-languages.sh).
@main struct StreamSystemSmokeTests {
    @MainActor static func main() async throws {
        let broker = SystemSessionBroker(startTimeout: .milliseconds(100))
        do { _ = try await broker.session(for: .toChinese(.english)); fatalError("no view hosts the translation task") }
        catch is SystemTranslationUnavailable { precondition(broker.configuration == nil) }
        print("PASS: without a hosting view the session broker gives up instead of waiting forever")

        guard #available(macOS 26.0, *), await SystemTranslator.status(.toChinese(.english)) == .installed else {
            print("SKIP: English → Chinese system language pack not installed"); return
        }
        let system = SystemTranslator()
        var reasons: [FallbackReason] = []
        let translator = FailoverTranslator(preferAI: true, ai: { _, _ in throw AIError.http(status: 429, retryAfter: nil) },
                                            system: { text, direction in try await system.translate(text, direction: direction) })
        translator.onFallback = { reasons.append($0) }
        let pipeline = StreamTranslationPipeline(translator: translator, direction: .toChinese(.english))
        let reply = "Please keep the existing settings. Restart the application after saving your work.\n\n```sh\nmake test\n```\n\nThe build should pass afterwards."
        let characters = Array(reply)
        for end in stride(from: 9, to: characters.count, by: 9) {
            pipeline.ingest(snapshot: String(characters[0..<end]))
            try await Task.sleep(for: .milliseconds(20))
        }
        pipeline.finish(snapshot: reply)
        let deadline = ContinuousClock.now + .seconds(60)
        while !pipeline.state.complete {
            precondition(ContinuousClock.now < deadline, "system translation did not finish")
            try await Task.sleep(for: .milliseconds(50))
        }
        let result = pipeline.state.translated
        precondition(pipeline.state.failedSegments.isEmpty, pipeline.state.lastFailure ?? "failed")
        precondition(result.contains("```sh\nmake test\n```") && result.contains("设置"), result)
        precondition(reasons.allSatisfy { $0 == .rateLimited || $0 == .circuitOpen } && reasons.contains(.rateLimited))
        print("PASS: streamed reply translated by the real system engine after AI rate limiting; code kept verbatim")
        print(result)
    }
}
