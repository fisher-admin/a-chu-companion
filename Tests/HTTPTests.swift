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
        print("7 HTTP integration tests passed")
    }
}
