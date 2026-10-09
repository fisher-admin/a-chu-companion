import Foundation

/// Removes chatter a model wraps around a translation. It never judges wording,
/// language or length: TranslationStructure already keeps code, links, paths and
/// table structure away from the model, so only meta text and model-added fences
/// are handled here. An unpaired fence is the one result that is not repaired.
enum TranslationCleanup {
    struct UnpairedFence: LocalizedError {
        var errorDescription: String? { "AI 译文的代码块标记不成对，本段已改用系统翻译。" }
    }

    // A marker line or prefix about the task itself. Ordinary openings such as
    // "Sure," or "当然" can be faithful translations and are never removed.
    private static let preamble = try! NSRegularExpression(pattern: #"""
        (?ix)\A[\ \t]*(?:
          (?:here\ is|here's|below\ is)\ (?:the|your|a)\ (?:\w+\ )?translation[^\n:：]{0,40}[:：.]?
        | (?:translation|translated\ text|übersetzung|译文|翻译|中文翻译|翻訳|번역)[\ \t]*[:：]
        | 以下是(?:中文|英文|德文|日文|韩文)?(?:的)?(?:翻译|译文)(?:如下)?[^\n:：]{0,20}[:：]?
        | 翻译如下[:：]?
        | 以下は(?:翻訳|訳文)(?:です)?[:：。]?
        | 다음은\ 번역(?:입니다)?[:：.]?
        )[\ \t]*\n?
        """#)
    private static let fence = try! NSRegularExpression(pattern: #"(?m)^[ \t]*(?:`{3,}|~{3,})"#)

    static func normalize(_ output: String, source: String) throws -> String {
        var value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceStart = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = preamble.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
           let range = Range(match.range, in: value),
           preamble.firstMatch(in: sourceStart, range: NSRange(sourceStart.startIndex..., in: sourceStart)) == nil {
            let rest = value[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty { value = rest }
        }
        let sourceFences = fences(in: source)
        if fences(in: value) > sourceFences, sourceFences == 0 {
            value = unwrapped(value)
        }
        if fences(in: value) != sourceFences, !fences(in: value).isMultiple(of: 2) { throw UnpairedFence() }
        for (open, close) in [("\"", "\""), ("“", "”"), ("「", "」")]
        where value.count > 2 && value.hasPrefix(open) && value.hasSuffix(close) && !sourceStart.hasPrefix(open) {
            value = String(value.dropFirst(open.count).dropLast(close.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        guard !value.isEmpty else { throw BridgeError.message("翻译服务返回空白片段，未提交译文。") }
        return value
    }

    static func fences(in text: String) -> Int {
        fence.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// A whole answer wrapped in one fenced block, e.g. ```text … ```.
    private static func unwrapped(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lines.count >= 2,
              fences(in: lines[0]) == 1, fences(in: lines[lines.count - 1]) == 1,
              lines[lines.count - 1].trimmingCharacters(in: .whitespaces).allSatisfy({ $0 == "`" || $0 == "~" }) else { return text }
        lines.removeFirst(); lines.removeLast()
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
