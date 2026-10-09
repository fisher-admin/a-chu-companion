import Foundation
import NaturalLanguage

struct TranslationRejected: LocalizedError, Equatable {
    enum Reason: String, Sendable { case empty, wrapper, preamble, codeFence, inlineCode, url, length, language }
    let reason: Reason
    var errorDescription: String? { "AI 译文未通过校验（\(reason.rawValue)），已改用系统翻译。" }
}

/// Rejects AI output that answers, rewrites or wraps the source instead of translating it.
/// Every check compares against the source, so text that legitimately contains a
/// marker (for example a quoted "Translation:") is never rejected for it.
enum TranslationGuard {
    // Only meta phrases about the task itself: "Sure," or "当然" can open a faithful translation.
    // Phrases are grouped by meaning, so a marker present in the source in any language is allowed.
    private static let preambles: [[String]] = [
        ["translation:", "translated text:", "übersetzung:", "翻译：", "翻译:", "译文：", "译文:", "翻訳：", "翻訳:", "번역:"],
        ["here is the translation", "here's the translation", "the translation is", "hier ist die übersetzung",
         "以下是翻译", "以下是译文", "以下是中文翻译", "翻译如下", "以下は翻訳", "다음은 번역"],
        ["as an ai", "als ki", "作为一个ai", "作为ai", "aiとして", "ai로서"]
    ]
    private static let urlPattern = try! NSRegularExpression(pattern: #"https?://[^\s<>()\[\]`"']+"#)
    private static let fencePattern = try! NSRegularExpression(pattern: #"(?m)^[ \t]*(```|~~~)"#)
    private static let fencedBlock = try! NSRegularExpression(pattern: #"(?ms)^[ \t]*(```|~~~).*?^[ \t]*\1[^\n]*$"#)
    private static let inlineCode = try! NSRegularExpression(pattern: #"`[^`\n]+`"#)

    static func check(source: String, output raw: String, direction: TranslationDirection) throws -> String {
        let output = try unwrap(raw, source: source)
        let sourceProse = prose(source), outputProse = prose(output)
        let head = output.prefix(80).lowercased()
        let sourceHead = source.prefix(160).lowercased()
        if preambles.contains(where: { group in group.contains(where: head.hasPrefix) && !group.contains(where: sourceHead.contains) }) {
            throw TranslationRejected(reason: .preamble)
        }
        guard matches(fencePattern, in: output).count == matches(fencePattern, in: source).count else {
            throw TranslationRejected(reason: .codeFence)
        }
        guard Set(matches(inlineCode, in: source)).isSubset(of: Set(matches(inlineCode, in: output))) else {
            throw TranslationRejected(reason: .inlineCode)
        }
        let urls = matches(urlPattern, in: source).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?。，；：！？")) }
        guard urls.allSatisfy({ output.contains($0) }) else { throw TranslationRejected(reason: .url) }
        try checkLength(source: sourceProse, output: outputProse, direction: direction)
        try checkLanguage(source: sourceProse, output: outputProse, direction: direction)
        return output
    }

    /// Removes the request wrapper, matched outer quotes and surrounding whitespace the model added.
    static func unwrap(_ raw: String, source: String) throws -> String {
        var output = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !source.contains(AIProtocol.openTag) {
            if output.hasPrefix(AIProtocol.openTag) { output.removeFirst(AIProtocol.openTag.count) }
            if output.hasSuffix(AIProtocol.closeTag) { output.removeLast(AIProtocol.closeTag.count) }
            guard !output.contains(AIProtocol.openTag), !output.contains(AIProtocol.closeTag) else {
                throw TranslationRejected(reason: .wrapper)
            }
        }
        output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("\"", "\""), ("“", "”"), ("「", "」"), ("『", "』"), ("„", "“")]
        where output.count > 2 && output.hasPrefix(open) && output.hasSuffix(close)
            && !(trimmedSource.hasPrefix(open) || trimmedSource.hasPrefix("\"") || trimmedSource.hasPrefix("“")) {
            output = String(output.dropFirst(open.count).dropLast(close.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        guard !output.isEmpty else { throw TranslationRejected(reason: .empty) }
        return output
    }

    /// Natural-language text without code, URLs or inline code, which translators keep verbatim.
    static func prose(_ text: String) -> String {
        var value = text
        for pattern in [fencedBlock, inlineCode, urlPattern] {
            value = pattern.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: " ")
        }
        return value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func checkLength(source: String, output: String, direction: TranslationDirection) throws {
        let input = source.filter { !$0.isWhitespace }.count, result = output.filter { !$0.isWhitespace }.count
        // Short fragments vary too much for ratios; only stop an answer that is far longer than its question.
        guard input >= 12 else {
            if result > max(48, input * 10) { throw TranslationRejected(reason: .length) }
            return
        }
        let ratio = Double(result) / Double(input)
        let bounds: ClosedRange<Double>
        switch direction {
        case let .fromChinese(language): bounds = [.english, .german].contains(language) ? 0.6...8 : 0.4...4
        case let .toChinese(language): bounds = [.english, .german].contains(language) ? 0.08...1.6 : 0.3...2.5
        }
        guard bounds.contains(ratio) else { throw TranslationRejected(reason: .length) }
    }

    private static func checkLanguage(source: String, output: String, direction: TranslationDirection) throws {
        let letters = output.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        // Scripts are distinct enough to judge short text; statistical detection needs more.
        guard letters >= 4 else { return }
        let scalars = output.unicodeScalars
        func share(_ test: (Unicode.Scalar) -> Bool) -> Double { Double(scalars.filter(test).count) / Double(letters) }
        let han = share(isHan), kana = share(isKana), hangul = share(isHangul), latin = share(isLatin)
        let accepted: Bool
        switch direction {
        case .toChinese:
            // Identifiers and names stay Latin, so Chinese only has to be clearly present.
            accepted = han >= 0.15 && kana < 0.1 && hangul < 0.1
        case .fromChinese(.japanese): accepted = hangul < 0.1 && (kana >= 0.05 || letters < 12)
        case .fromChinese(.korean): accepted = hangul >= 0.3
        case let .fromChinese(language):
            guard latin >= 0.6, han < 0.2, kana < 0.1, hangul < 0.1 else { accepted = false; break }
            guard letters >= 40 else { accepted = true; break }
            let recognizer = NLLanguageRecognizer()
            recognizer.languageConstraints = [.english, .german, .french, .dutch, .spanish, .italian]
            recognizer.processString(output)
            let target: NLLanguage = language == .german ? .german : .english
            accepted = recognizer.dominantLanguage == target || (recognizer.languageHypotheses(withMaximum: 3)[target] ?? 0) >= 0.3
        }
        guard accepted else { throw TranslationRejected(reason: .language) }
    }

    private static func matches(_ pattern: NSRegularExpression, in text: String) -> [String] {
        pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }
    private static func isHan(_ s: Unicode.Scalar) -> Bool { (0x4E00...0x9FFF).contains(s.value) || (0x3400...0x4DBF).contains(s.value) || (0x20000...0x2EBEF).contains(s.value) }
    private static func isKana(_ s: Unicode.Scalar) -> Bool { (0x3040...0x30FF).contains(s.value) || (0x31F0...0x31FF).contains(s.value) }
    private static func isHangul(_ s: Unicode.Scalar) -> Bool { (0xAC00...0xD7AF).contains(s.value) || (0x1100...0x11FF).contains(s.value) || (0x3130...0x318F).contains(s.value) }
    private static func isLatin(_ s: Unicode.Scalar) -> Bool { (0x41...0x5A).contains(s.value) || (0x61...0x7A).contains(s.value) || (0xC0...0x24F).contains(s.value) }
}
