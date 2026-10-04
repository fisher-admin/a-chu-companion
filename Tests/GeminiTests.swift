import Foundation

@main struct GeminiTests {
    static var count = 0
    static func check(_ value: Bool, _ name: String) {
        guard value else { fputs("FAIL: \(name)\n", stderr); exit(1) }
        count += 1; print("PASS: \(name)")
    }
    static func rejects(_ operation: () throws -> Void) -> Bool {
        do { try operation(); return false } catch { return true }
    }
    static func payload(_ parts: [[String: Any]], finish: String? = "STOP") throws -> Data {
        var candidate: [String: Any] = ["content": ["parts": parts]]
        if let finish { candidate["finishReason"] = finish }
        return try JSONSerialization.data(withJSONObject: ["candidates": [candidate]])
    }
    static func main() throws {
        let text = "请不要删除配置。\n\n```swift\nlet x = 123\n```\nhttps://example.org"
        let request = try GeminiProtocol.request(text: text, model: GeminiProtocol.defaultModel, key: "dummy-gemini-key", direction: .fromChinese(.german))
        check(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent", "pin the requested Flash-Lite model at Google's native endpoint")
        check(request.httpMethod == "POST" && request.value(forHTTPHeaderField: "X-goog-api-key") == "dummy-gemini-key" && request.value(forHTTPHeaderField: "Authorization") == nil && request.url?.query == nil, "Gemini key uses only its header, never Bearer authentication or the URL")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let contents = body["contents"] as! [[String: Any]]
        let parts = contents[0]["parts"] as! [[String: Any]]
        let instruction = ((body["systemInstruction"] as! [String: Any])["parts"] as! [[String: Any]])[0]["text"] as! String
        check(contents[0]["role"] as? String == "user" && parts[0]["text"] as? String == text && instruction.contains("German") && instruction.contains("Do not answer") && instruction.contains("code"), "preserve input and separate translation-only instructions")
        var directionsWork = true
        for language in TranslationLanguage.allCases {
            for direction in [TranslationDirection.fromChinese(language), .toChinese(language)] {
                let r = try RemoteTranslationProvider.gemini.request(text: "内容", baseURL: "https://unrelated.invalid", model: GeminiProtocol.defaultModel, key: "dummy-gemini-key", direction: direction)
                let b = try JSONSerialization.jsonObject(with: r.httpBody!) as! [String: Any]
                let p = ((b["systemInstruction"] as! [String: Any])["parts"] as! [[String: Any]])[0]["text"] as! String
                directionsWork = directionsWork && p.contains(direction.instruction) && r.url?.host == "generativelanguage.googleapis.com"
            }
        }
        check(directionsWork, "both directions support all four selected languages at the fixed Google host")
        check(rejects { _ = try GeminiProtocol.endpoint(model: "../other?key=secret") } && rejects { _ = try GeminiProtocol.endpoint(model: "") }, "model names cannot inject paths or queries")
        check(rejects { _ = try GeminiProtocol.request(text: "你好", model: GeminiProtocol.defaultModel, key: "", direction: .fromChinese(.english)) } && rejects { _ = try GeminiProtocol.request(text: "你好", model: GeminiProtocol.defaultModel, key: "bad\nkey", direction: .fromChinese(.english)) }, "missing or invalid Gemini credentials fail before networking")
        check(RemoteTranslationProvider.openAI.credentialAccount == "translation-api-key" && RemoteTranslationProvider.gemini.credentialAccount != RemoteTranslationProvider.openAI.credentialAccount, "Gemini credentials remain separate while the existing key account is preserved")
        let result = try GeminiProtocol.response(payload([["text": "private thought", "thought": true], ["text": "Hello\n"], ["text": "World"]]), status: 200)
        check(result == "Hello\nWorld", "join final text parts without leaking thinking content")
        check(rejects { _ = try GeminiProtocol.response(payload([["text": "partial"]], finish: nil), status: 200) } && rejects { _ = try GeminiProtocol.response(payload([["text": "partial"]], finish: "SAFETY"), status: 200) }, "unfinished and blocked candidates never become accepted translations")
        do { _ = try GeminiProtocol.response(payload([["text": "partial"]], finish: "MAX_TOKENS"), status: 200); check(false, "truncated output requests smaller chunks") }
        catch TranslationChunkError.tooLarge { check(true, "truncated output requests smaller chunks") }
        check(rejects { _ = try GeminiProtocol.response(payload([["text": "thought", "thought": true]]), status: 200) } && rejects { _ = try GeminiProtocol.response(Data("{}".utf8), status: 200) }, "thinking-only and malformed output are refused")
        check(rejects { _ = try GeminiProtocol.response(Data("{\"promptFeedback\":{\"blockReason\":\"SAFETY\"}}".utf8), status: 200) }, "prompt safety blocks preserve the original instead of returning empty success")
        for status in [400, 401, 403, 404, 429, 500] {
            do { _ = try GeminiProtocol.response(Data("{\"error\":{\"message\":\"dummy-key PRIVATE INPUT\"}}".utf8), status: status); check(false, "HTTP \(status) has safe feedback") }
            catch {
                let message = error.localizedDescription
                check(message.contains("Gemini") && !message.contains("dummy-key") && !message.contains("PRIVATE INPUT"), "HTTP \(status) has safe feedback")
            }
        }
        let old = try RemoteTranslationProvider.openAI.request(text: "你好", baseURL: "https://example.org/v1", model: "existing", key: "dummy-old-key", direction: .fromChinese(.english))
        check(old.url?.path == "/v1/chat/completions" && old.value(forHTTPHeaderField: "Authorization") == "Bearer dummy-old-key" && old.value(forHTTPHeaderField: "X-goog-api-key") == nil, "existing compatible services keep their original protocol")
        print("\(count) Gemini tests passed")
    }
}
