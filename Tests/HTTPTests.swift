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
        print("14 HTTP integration tests passed")
    }
}
