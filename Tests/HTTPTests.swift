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
        print("5 HTTP integration tests passed")
    }
}
