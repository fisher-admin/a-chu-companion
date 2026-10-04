import Foundation

enum RemoteTranslationProvider: String, Sendable {
    case openAI = "ai", gemini
    var credentialAccount: String { self == .gemini ? "gemini-translation-api-key" : "translation-api-key" }
    func request(text: String, baseURL: String, model: String, key: String, direction: TranslationDirection) throws -> URLRequest {
        switch self {
        case .openAI: return try AIProtocol.request(text: text, baseURL: baseURL, model: model, key: key, direction: direction)
        case .gemini: return try GeminiProtocol.request(text: text, model: model, key: key, direction: direction)
        }
    }
}

enum GeminiProtocol {
    static let defaultModel = "gemini-3.1-flash-lite"
    static func endpoint(model: String) throws -> URL {
        let name = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.hasPrefix("gemini-"), name.range(of: "^[A-Za-z0-9._-]{1,128}$", options: .regularExpression) != nil,
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(name):generateContent") else {
            throw BridgeError.message("请填写有效的 Gemini 模型名称，例如 gemini-3.1-flash-lite。")
        }
        return url
    }
    static func request(text: String, model: String, key: String, direction: TranslationDirection) throws -> URLRequest {
        let input = try InputPolicy.validated(text)
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else {
            throw BridgeError.message("请在翻译设置中填写并保存 Gemini API 密钥。")
        }
        var request = URLRequest(url: try endpoint(model: model), timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "systemInstruction": ["parts": [["text": direction.systemInstruction]]],
            "contents": [["role": "user", "parts": [["text": input]]]],
            "generationConfig": ["candidateCount": 1, "maxOutputTokens": 8192]
        ])
        return request
    }
    static func response(_ data: Data, status: Int) throws -> String {
        guard (200..<300).contains(status) else {
            if status == 413 { throw TranslationChunkError.tooLarge }
            let detail: String
            switch status {
            case 400, 401, 403: detail = "请检查 API 密钥、模型及项目访问权限。"
            case 404: detail = "找不到此模型，请检查模型名称及项目可用模型。"
            case 429: detail = "项目额度用尽或请求过于频繁，请稍后重试，或查看 Google AI Studio 的项目限额。"
            default: detail = "服务暂时不可用，请稍后重试。"
            }
            throw BridgeError.message("Gemini 翻译服务返回 \(status)。\(detail)")
        }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let block = (body?["promptFeedback"] as? [String: Any])?["blockReason"] as? String,
           block != "BLOCK_REASON_UNSPECIFIED" {
            throw BridgeError.message("Gemini 未允许翻译这段内容，原文已保留。")
        }
        guard let candidate = (body?["candidates"] as? [[String: Any]])?.first else {
            throw BridgeError.message("Gemini 没有返回可用译文，原文已保留。")
        }
        if candidate["finishReason"] as? String == "MAX_TOKENS" { throw TranslationChunkError.tooLarge }
        guard candidate["finishReason"] as? String == "STOP" else {
            throw BridgeError.message("Gemini 翻译结果未完整结束或被拦截，原文已保留。")
        }
        let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        let text = parts.filter { $0["thought"] as? Bool != true }.compactMap { $0["text"] as? String }.joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BridgeError.message("Gemini 没有返回可用译文，原文已保留。")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TranslationConnectionCheck {
    static func run(provider: RemoteTranslationProvider, baseURL: String, model: String, key: String) async throws {
        // Fixed synthetic text only; never use drafts or the bound conversation.
        for (text, direction) in [("请保留现有设置。", TranslationDirection.fromChinese(.english)),
                                  ("Please keep the existing settings.", .toChinese(.english))] {
            try Task.checkCancellation()
            let request = try provider.request(text: text, baseURL: baseURL, model: model, key: key, direction: direction)
            _ = try await AITranslator.translate(request, provider: provider)
        }
        try Task.checkCancellation()
    }
}
