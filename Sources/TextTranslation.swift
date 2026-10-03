import Foundation

enum TranslationChunks {
    static func split(_ text: String, limit: Int = 3_000) -> [String] {
        precondition(limit > 0)
        var result: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            var end = text.index(start, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
            if end != text.endIndex {
                let halfway = text.index(start, offsetBy: limit / 2)
                if let boundary = text[halfway..<end].lastIndex(where: { $0.isWhitespace || "。！？.!?;；".contains($0) }) {
                    end = text.index(after: boundary)
                }
            }
            result.append(String(text[start..<end]))
            start = end
        }
        return result
    }
}

@MainActor enum TextTranslation {
    static func run(_ text: String, limit: Int = 3_000,
                    progress: (Int, Int) -> Void = { _, _ in },
                    timeout: Duration = .seconds(120),
                    translate: @escaping @MainActor (String) async throws -> String) async throws -> String {
        let chunks = TranslationChunks.split(text, limit: limit)
        var result = ""
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            progress(index + 1, chunks.count)
            result += try await piece(chunk, timeout: timeout, translate: translate)
        }
        try Task.checkCancellation()
        return result
    }

    private static func piece(_ text: String, timeout: Duration,
                              translate: @escaping @MainActor (String) async throws -> String) async throws -> String {
        try Task.checkCancellation()
        let prefix = String(text.prefix(while: \.isWhitespace))
        let rest = text.dropFirst(prefix.count)
        let suffix = String(rest.reversed().prefix(while: \.isWhitespace).reversed())
        let core = String(rest.dropLast(suffix.count))
        guard !core.isEmpty else { return text }
        do {
            let value = try await withDeadline(timeout: timeout) { try await translate(core) }
            try Task.checkCancellation()
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BridgeError.message("翻译服务返回空白片段，未提交译文。") }
            return prefix + value + suffix
        } catch TranslationChunkError.tooLarge {
            guard core.count > 64 else { throw TranslationChunkError.tooLarge }
            var result = prefix
            for smaller in TranslationChunks.split(core, limit: core.count / 2) {
                result += try await piece(smaller, timeout: timeout, translate: translate)
            }
            return result + suffix
        }
    }

    static func withDeadline(timeout: Duration = .seconds(120),
                             operation: @escaping @MainActor () async throws -> String) async throws -> String {
        let race = TranslationDeadline()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.continuation = continuation
                race.work = Task {
                    do { try Task.checkCancellation(); race.finish(.success(try await operation())) }
                    catch { race.finish(.failure(error)) }
                }
                race.timer = Task {
                    do { try await Task.sleep(for: timeout); race.finish(.failure(TranslationChunkError.timedOut)) }
                    catch { /* Cancellation means another result won. */ }
                }
                if Task.isCancelled { race.finish(.failure(CancellationError())) }
            }
        } onCancel: {
            Task { @MainActor in race.finish(.failure(CancellationError())) }
        }
    }
}

@MainActor private final class TranslationDeadline {
    var continuation: CheckedContinuation<String, Error>?
    var work: Task<Void, Never>?
    var timer: Task<Void, Never>?
    func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        work?.cancel(); work = nil
        timer?.cancel(); timer = nil
        continuation.resume(with: result)
    }
}
