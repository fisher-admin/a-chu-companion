import Foundation
@main struct HTTPTests {
    static func main() async throws {
        let base = CommandLine.arguments[1]
        let request = try AIProtocol.request(text: "你好", baseURL: base + "/ok", model: "test", key: "dummy-not-a-secret")
        let result = try await AITranslator.translate(request)
        precondition(result == "Hello")
        print("PASS: actual HTTP request and response")
        for path in ["unauthorized", "truncated", "redirect", "slow"] {
            var request = try AIProtocol.request(text: "你好", baseURL: base + "/" + path, model: "test", key: "")
            if path == "slow" { request.timeoutInterval = 0.3 }
            do {
                _ = try await AITranslator.translate(request)
                fputs("FAIL: expected rejection for \(path)\n", stderr); exit(1)
            } catch { print("PASS: \(path) blocked") }
        }
        let long = String(repeating: "第一段😀。\n  let x = 123\n", count: 6_000)
        let merged = try await TextTranslation.run(long) { chunk in
            try await AITranslator.translate(AIProtocol.request(text: chunk, baseURL: base + "/echo", model: "test", key: "", direction: .fromChinese(.german)))
        }
        precondition(merged == long)
        print("PASS: >100k text completes actual HTTP chunking without losing code or Unicode")
        let adaptiveText = String(repeating: "保持完整😀。", count: 150)
        let adaptive = try await TextTranslation.run(adaptiveText) { chunk in
            try await AITranslator.translate(AIProtocol.request(text: chunk, baseURL: base + "/adaptive", model: "test", key: "", direction: .toChinese(.korean)))
        }
        precondition(adaptive == adaptiveText)
        print("PASS: actual HTTP 413 recovers through smaller requests")
        func geminiRequest(_ text: String, _ path: String) throws -> URLRequest {
            var request = try GeminiProtocol.request(text: text, model: GeminiProtocol.defaultModel, key: "dummy-gemini-key", direction: .toChinese(.english))
            request.url = URL(string: base + "/gemini/" + path)
            return request
        }
        let gemini = try await AITranslator.translate(geminiRequest("你好", "ok"), provider: .gemini)
        precondition(gemini == "Hello")
        print("PASS: native Gemini HTTP payload, key header and thinking-part filtering")
        for path in ["quota", "truncated", "redirect"] {
            do { _ = try await AITranslator.translate(geminiRequest("你好", path), provider: .gemini); fputs("FAIL: Gemini \(path) was accepted\n", stderr); exit(1) }
            catch { print("PASS: Gemini \(path) blocked without accepting partial output") }
        }
        let echoed = try await TextTranslation.run(long) { chunk in
            try await AITranslator.translate(geminiRequest(chunk, "echo"), provider: .gemini)
        }
        precondition(echoed == long)
        print("PASS: actual Gemini HTTP chunking preserves long Unicode and code originals")
        let adapted = try await TextTranslation.run(adaptiveText) { chunk in
            try await AITranslator.translate(geminiRequest(chunk, "adaptive"), provider: .gemini)
        }
        precondition(adapted == adaptiveText)
        print("PASS: Gemini MAX_TOKENS recovers through smaller actual HTTP requests")
        var slowGemini = try geminiRequest("你好", "slow"); slowGemini.timeoutInterval = 0.3
        do { _ = try await AITranslator.translate(slowGemini, provider: .gemini); fputs("FAIL: Gemini network timeout accepted\n", stderr); exit(1) }
        catch {
            // build59: a slow service is a timeout, not a local network fault
            // (build58 showed "check your network" after server-side 503s).
            guard error.localizedDescription.contains("Gemini") && error.localizedDescription.contains("超时")
                    && !error.localizedDescription.contains("检查网络") else {
                fputs("FAIL: Gemini timeout needs clear Chinese feedback that is not a network fault\n", stderr); exit(1)
            }
        }
        print("PASS: Gemini network timeouts produce clear feedback without exposing request details")
        let recoveryRequest = try AIProtocol.request(text: "你好", baseURL: base + "/recover", model: "test", key: "synthetic-recovery-key")
        do { _ = try await AITranslator.translate(recoveryRequest); preconditionFailure("503 must be typed") }
        catch let failure as ServiceTransientError { precondition(failure.seconds == 2 && failure.reason.contains("503")) }
        print("PASS: actual HTTP 503 has a typed bounded-recovery cause")
        do { _ = try await AITranslator.translate(recoveryRequest); preconditionFailure("shared cooldown must block") }
        catch is ServiceCooldown { }
        print("PASS: another translation request cannot bypass a transient cooldown")
        try await Task.sleep(for: .milliseconds(2100))
        let recovered = try await AITranslator.translate(recoveryRequest)
        precondition(recovered == "Hello")
        print("PASS: actual HTTP recovers after the shared service wait")
        let quotaRequest = try AIProtocol.request(text: "你好", baseURL: base + "/quota", model: "test", key: "synthetic-quota-key")
        do { _ = try await AITranslator.translate(quotaRequest); preconditionFailure("429 must be typed") }
        catch let failure as ServiceCooldown { precondition(failure.seconds == 2) }
        print("PASS: HTTP Retry-After reaches the shared gate")
        do { _ = try await AITranslator.translate(quotaRequest); preconditionFailure("429 wait must survive another request") }
        catch let failure as ServiceCooldown { precondition(failure.seconds > 0 && failure.seconds <= 2) }
        print("PASS: subsequent requests honor the original quota wait")
        try await authorization(base)
        print("\(19 + authorizationChecks) HTTP integration tests passed")
    }

    static var authorizationChecks = 0
    static func pass(_ name: String) { authorizationChecks += 1; print("PASS: " + name) }
    static func counts(_ base: String) async throws -> [String: Int] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: base + "/counts")!)
        return try JSONSerialization.jsonObject(with: data) as? [String: Int] ?? [:]
    }

    /// 401/403 over real HTTP: one pause per rejected key, local blocking afterwards,
    /// concurrent pipeline slices falling back, and a new key reaching the service again.
    @MainActor static func authorization(_ base: String) async throws {
        for (provider, tag) in [(RemoteTranslationProvider.openAI, "compatible"), (.gemini, "gemini")] {
            for code in [401, 403] {
                let header = provider == .gemini ? "X-goog-api-key" : "Authorization"
                var rejected = URLRequest(url: URL(string: base + "/auth/\(tag)/\(code)")!)
                rejected.httpMethod = "POST"; rejected.httpBody = Data("{}".utf8)
                rejected.setValue("synthetic-rejected-\(tag)-\(code)", forHTTPHeaderField: header)
                do { _ = try await AITranslator.translate(rejected, provider: provider); preconditionFailure("rejection expected") }
                catch let error as ServiceAuthorizationError { precondition(error.seconds == 600) }
                do { _ = try await AITranslator.translate(rejected, provider: provider); preconditionFailure("paused key must stay local") }
                catch let error as ServiceCooldown { precondition(error.seconds > 590) }
                var accepted = rejected
                accepted.setValue("synthetic-accepted-\(tag)-\(code)", forHTTPHeaderField: header)
                let renewed = try await AITranslator.translate(accepted, provider: provider)
                precondition(renewed == "Hello")
                pass("\(tag) HTTP \(code) pauses the rejected key, blocks it locally and lets a new key through")
            }
        }
        var observed = try await counts(base)
        precondition(["compatible", "gemini"].allSatisfy { tag in [401, 403].allSatisfy { code in
            observed["/auth/\(tag)/\(code)#rejected"] == 1 && observed["/auth/\(tag)/\(code)#accepted"] == 1 } })
        pass("each rejected key reached the network exactly once")

        func pipeline(key: String, fallbacks: @escaping () -> Void) -> ReplyPipeline {
            let pipeline = ReplyPipeline(concurrency: 3) { text in
                let request = try AIProtocol.request(text: text, baseURL: base + "/auth/pipeline/401", model: "test", key: key, direction: .toChinese(.english))
                return try await AITranslator.translate(request)
            }
            pipeline.fallback = { text in fallbacks(); return "系统:" + text }
            return pipeline
        }
        let paragraphs = (1...6).map { "Paragraph \($0) is complete." }
        func run(_ pipeline: ReplyPipeline) async throws -> String {
            var output = ""
            pipeline.onTranslation = { _, _, value, _ in output = value }
            pipeline.observe(conversation: "auth", messages: [.init(ordinal: 2, author: .assistant, text: paragraphs.joined(separator: "\n\n"))], responseComplete: false, now: 0)
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while output.components(separatedBy: "\n\n").count < 5 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            pipeline.tick(now: 5)
            while output.components(separatedBy: "\n\n").count < 6 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            while pipeline.busy && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            return output
        }
        var fallbacks = 0
        let rejectedOutput = try await run(pipeline(key: "synthetic-rejected-pipeline") { fallbacks += 1 })
        observed = try await counts(base)
        let rejectedHits = observed["/auth/pipeline/401/chat/completions#rejected"] ?? 0
        precondition(rejectedOutput == paragraphs.map { "系统:" + $0 }.joined(separator: "\n\n") && fallbacks == 6)
        pass("three concurrent slices hitting a real 401 all fall back to system translation in order")
        precondition((1...3).contains(rejectedHits))
        pass("only the first concurrent wave reaches the service; later slices skip it (\(rejectedHits) requests for 6 slices)")
        fallbacks = 0
        let acceptedOutput = try await run(pipeline(key: "synthetic-accepted-pipeline") { fallbacks += 1 })
        observed = try await counts(base)
        precondition(acceptedOutput == paragraphs.map { "已译:" + $0 }.joined(separator: "\n\n") && fallbacks == 0
                     && observed["/auth/pipeline/401/chat/completions#accepted"] == 6)
        pass("after changing the key, the same service translates every slice again")
    }
}
