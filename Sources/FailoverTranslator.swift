import Foundation

enum TranslationEngineKind: String, Sendable { case ai, system }

enum AIPreset {
    /// Gemini's OpenAI-compatible endpoint; `AIProtocol.endpoint` appends `/chat/completions`.
    static let geminiBaseURL = "https://generativelanguage.googleapis.com/v1beta/openai/"
}

enum FallbackReason: Equatable, Sendable {
    case circuitOpen, timeout, rateLimited, unauthorized, network, http(Int), rejected(TranslationRejected.Reason), failed
    var message: String {
        switch self {
        case .circuitOpen: return "AI 翻译暂停使用，正在使用系统翻译。"
        case .timeout: return "AI 翻译超时，已改用系统翻译。"
        case .rateLimited: return "AI 翻译请求过于频繁，已改用系统翻译。"
        case .unauthorized: return "AI 翻译密钥或权限无效，已改用系统翻译。请检查设置。"
        case .network: return "无法连接 AI 翻译服务，已改用系统翻译。"
        case let .http(status): return "AI 翻译服务返回 \(status)，已改用系统翻译。"
        case let .rejected(reason): return "AI 译文未通过校验（\(reason.rawValue)），已改用系统翻译。"
        case .failed: return "AI 翻译失败，已改用系统翻译。"
        }
    }
}

struct FailoverExhausted: LocalizedError {
    let reason: FallbackReason
    let underlying: Error
    var errorDescription: String? { reason.message + " 系统翻译也失败：" + underlying.localizedDescription }
}

/// Translates one piece of text with AI first (when preferred and the circuit allows) and
/// falls back to system translation. Each call resolves exactly once, so callers that
/// assemble results by position never see a piece duplicated or skipped.
@MainActor final class FailoverTranslator {
    typealias Engine = @MainActor (String, TranslationDirection) async throws -> String
    var preferAI: Bool
    let circuit: AICircuit
    var onFallback: (FallbackReason) -> Void = { _ in }
    private(set) var lastEngine: TranslationEngineKind?
    private let ai: Engine
    private let system: Engine
    private let aiTimeout: (String) -> Duration

    init(preferAI: Bool, circuit: AICircuit? = nil, aiTimeout: @escaping (String) -> Duration = FailoverTranslator.defaultTimeout,
         ai: @escaping Engine, system: @escaping Engine) {
        self.preferAI = preferAI; self.circuit = circuit ?? AICircuit(); self.aiTimeout = aiTimeout; self.ai = ai; self.system = system
    }

    nonisolated static func defaultTimeout(_ text: String) -> Duration { .seconds(min(60, 15 + text.count / 100)) }

    static func openAICompatible(baseURL: String, model: String, key: String) -> Engine {
        { text, direction in
            try await AITranslator.translate(AIProtocol.request(text: text, baseURL: baseURL, model: model, key: key, direction: direction))
        }
    }

    func translate(_ text: String, direction: TranslationDirection) async throws -> String {
        guard preferAI else { return try await useSystem(text, direction, after: nil) }
        guard let permit = circuit.acquire() else { return try await useSystem(text, direction, after: .circuitOpen) }
        let reason: FallbackReason
        do {
            let raw = try await TextTranslation.withDeadline(timeout: aiTimeout(text)) { try await self.ai(text, direction) }
            try Task.checkCancellation()
            let checked = try TranslationGuard.check(source: text, output: raw, direction: direction)
            circuit.succeeded(permit); lastEngine = .ai
            return checked
        } catch {
            // URLSession reports a cancelled parent task as URLError(.cancelled), not CancellationError.
            if Task.isCancelled || error is CancellationError { circuit.released(permit); throw CancellationError() }
            if case TranslationChunkError.tooLarge = error {
                circuit.released(permit)
                // Let TextTranslation split the piece and retry AI on smaller parts.
                if text.count > 64 { throw error }
                reason = .failed
            } else {
                reason = Self.classify(error)
                circuit.failed(permit, retryAfter: (error as? AIError)?.retryAfter, severe: reason == .unauthorized)
            }
        }
        return try await useSystem(text, direction, after: reason)
    }

    private func useSystem(_ text: String, _ direction: TranslationDirection, after reason: FallbackReason?) async throws -> String {
        if let reason { onFallback(reason) }
        do {
            let value = try await system(text, direction)
            lastEngine = .system
            return value
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            guard let reason, reason != .circuitOpen else { throw error }
            throw FailoverExhausted(reason: reason, underlying: error)
        }
    }

    static func classify(_ error: Error) -> FallbackReason {
        switch error {
        case TranslationChunkError.timedOut: return .timeout
        case let error as AIError:
            switch error.status {
            case 429: return .rateLimited
            case 401, 403: return .unauthorized
            default: return .http(error.status)
            }
        case let error as URLError: return error.code == .timedOut ? .timeout : .network
        case let error as TranslationRejected: return .rejected(error.reason)
        default: return .failed
        }
    }
}
