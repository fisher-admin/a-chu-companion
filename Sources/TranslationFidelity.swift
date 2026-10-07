import Foundation

/// The language a translation request is producing. Callers that know the
/// direction set it so provider output can be checked before use.
enum TranslationTarget: Equatable, Sendable {
    case chinese, foreign(TranslationLanguage)
}

struct TranslationFidelityError: LocalizedError, Sendable {
    let reason: String
    var errorDescription: String? { "译文疑似加入了原文没有的内容（\(reason)），未采用该结果。" }
}

/// Deterministic checks for the observed failure where a model translates a
/// request and then answers it. They cannot prove semantic fidelity; they only
/// refuse output whose shape the source cannot explain.
enum TranslationFidelity {
    @TaskLocal static var target: TranslationTarget?

    /// Script-weighted length: one Han character carries roughly as much
    /// content as three Latin characters, so ratios stay comparable across
    /// language pairs. Whitespace runs count once.
    static func weightedLength(_ text: String) -> Double {
        var total = 0.0; var previousSpace = false
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !previousSpace { total += 1 }
                previousSpace = true; continue
            }
            previousSpace = false
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FFFF: total += 3
            case 0x3040...0x30FF: total += 1.6
            case 0xAC00...0xD7AF: total += 2.2
            default: total += 1
            }
        }
        return total
    }

    /// Calibrated on faithful research prompts (largest observed: German at
    /// 1.94) against translations followed by one appended answer paragraph
    /// (2.4 and above). The constant keeps short phrases and idioms free.
    static func lengthFactor(_ target: TranslationTarget?) -> Double {
        switch target {
        case .chinese: return 1.8
        case .foreign(.german), nil: return 2.5
        case .foreign: return 2.0
        }
    }

    private enum Structure: Hashable { case table, heading, list, fence, quote }
    private static func structures(_ text: String) -> Set<Structure> {
        var found = Set<Structure>()
        if MarkdownTable.blocks(text).contains(where: { if case .table = $0 { return true }; return false }) { found.insert(.table) }
        for line in text.split(whereSeparator: \.isNewline) {
            let value = String(line)
            func has(_ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
            if has(#"^\s{0,3}#{1,6}\s"#) { found.insert(.heading) }
            if has(#"^\s*([-*+•·]|\d{1,3}[.)、）]|[（(]\d{1,3}[)）]|[一二三四五六七八九十]{1,3}[、.])\s*\S"#) { found.insert(.list) }
            if has(#"^\s*(```|~~~)"#) { found.insert(.fence) }
            if has(#"^\s*>"#) { found.insert(.quote) }
        }
        return found
    }

    private static let closing = CharacterSet(charactersIn: "\"'”’」』）)]】*_ \t\n")
    private static func endsWithQuestion(_ text: String) -> Bool {
        let trimmed = text.unicodeScalars.reversed().drop(while: { closing.contains($0) })
        guard let last = trimmed.first else { return false }
        return last == "?" || last == "？"
    }

    static func validate(source: String, translation: String, target: TranslationTarget?) throws {
        let added = structures(translation).subtracting(structures(source))
        if added.contains(.table) { throw TranslationFidelityError(reason: "原文没有的表格") }
        if added.contains(.heading) { throw TranslationFidelityError(reason: "原文没有的标题") }
        if added.contains(.list) { throw TranslationFidelityError(reason: "原文没有的列表") }
        if added.contains(.fence) { throw TranslationFidelityError(reason: "原文没有的代码块") }
        if added.contains(.quote) { throw TranslationFidelityError(reason: "原文没有的引用") }
        let limit = lengthFactor(target) * weightedLength(source) + 48
        if weightedLength(translation) > limit { throw TranslationFidelityError(reason: "译文远长于原文，可能附加了回答或解释") }
        // English and German questions keep a question mark; Japanese and
        // Korean questions can legitimately end otherwise, so they are exempt.
        if case let .foreign(language) = target, [.english, .german].contains(language),
           endsWithQuestion(source), !endsWithQuestion(translation) {
            throw TranslationFidelityError(reason: "原文是问句，译文结尾却不是问句")
        }
    }
}
