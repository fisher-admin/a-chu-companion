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
            if has(#"^\s*(?:[-*+]\s+\S|[•·]\s*\S|\d{1,3}[.)]\s+\S|\d{1,3}[、）]\s*\S|[（(]\d{1,3}[)）]\s*\S|[一二三四五六七八九十]{1,3}[、.]\s*\S)"#) { found.insert(.list) }
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
        if clearNegativeCommand(source), !hasNegation(translation, target: target) {
            throw TranslationFidelityError(reason: "明确的禁止指令丢失了否定含义")
        }
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
        if endsWithQuestion(source), !questionLike(translation, target: target),
           translation.range(of: #"(?i)^\s*(?:yes\b|no\b|ja\b|nein\b|是的|不是|はい|いいえ|네[,.，。\s]|아니요)"#, options: .regularExpression) != nil {
            throw TranslationFidelityError(reason: "译文回答了原文的问题")
        }
    }

    private static func clearNegativeCommand(_ text: String) -> Bool {
        text.range(of: #"(?i)^\s*(?:(?:请)?(?:不要|勿|不得|禁止|切勿)\s*(?:删除|修改|覆盖|发送|访问|运行|执行|安装|重置|打开)|(?:do\s+not|don't|never)\s+(?:delete|modify|overwrite|send|access|run|execute|install|reset|open)\b)"#, options: .regularExpression) != nil
    }
    private static func hasNegation(_ text: String, target: TranslationTarget?) -> Bool {
        let pattern: String
        switch target {
        case .chinese: pattern = "不|勿|禁止|避免|未|没"
        case .foreign(.japanese): pattern = "ない|ません|禁止|避け"
        case .foreign(.korean): pattern = "않|하지\\s*마|하지\\s*말|금지|피하|삼가"
        case .foreign(.german): pattern = #"(?i)\b(?:nicht|kein\w*|nie|vermeid\w*)\b"#
        default: pattern = #"(?i)\b(?:not|no|never|avoid|refrain)\b|n't\b"#
        }
        return text.range(of: pattern, options: .regularExpression) != nil
    }
    private static func questionLike(_ text: String, target: TranslationTarget?) -> Bool {
        if endsWithQuestion(text) { return true }
        switch target {
        case .chinese: return text.range(of: "(?:吗|呢)[。！]?\\s*$|是否|能否", options: .regularExpression) != nil
        case .foreign(.japanese): return text.range(of: "(?:ですか|ますか|でしょうか)[。]?\\s*$", options: .regularExpression) != nil
        case .foreign(.korean): return text.range(of: "(?:나요|까요|습니까)[.]?\\s*$", options: .regularExpression) != nil
        default: return false
        }
    }

    /// Run after reassembly, not on a fragment whose neighbouring literals
    /// were deliberately withheld from the provider.
    static func validateAssembly(source: String, translation: String, target: TranslationTarget?) throws {
        try validate(source: source, translation: translation, target: target)
        func literals(_ text: String) -> [String] {
            TranslationStructure.parts(text).filter { !$0.translatable &&
                ($0.text.rangeOfCharacter(from: .letters) != nil || $0.text.contains("`") || $0.text.contains("$")) }.map(\.text)
        }
        guard literals(source) == literals(translation) else {
            throw TranslationFidelityError(reason: "代码、文件名、路径或链接发生了增加、删除或改动")
        }
        func numbers(_ text: String) -> [String] {
            // Han/Hangul may touch a number without a space. Only Latin
            // identifier prefixes suppress matches; display spacing before %
            // does not change the numeric fact.
            let regex = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])[-+−]?\d+(?:[.,]\d+)*(?:[eE][-+]?\d+)?(?:\s*%)?"#)
            let ns = text as NSString
            return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range).filter { !$0.isWhitespace } }
        }
        let beforeNumbers = numbers(source), afterNumbers = numbers(translation)
        let spelledNumber = beforeNumbers.isEmpty && source.range(of: "[零〇一二三四五六七八九十百千万亿]", options: .regularExpression) != nil
        guard beforeNumbers == afterNumbers || spelledNumber else { throw TranslationFidelityError(reason: "原文数字发生了增加、删除或改动") }
        func tables(_ text: String) -> [[Int]] {
            MarkdownTable.blocks(text).compactMap { block in
                guard case .table(let table) = block else { return nil }
                return [table.headers.count] + table.rows.map(\.count)
            }
        }
        guard tables(source) == tables(translation) else { throw TranslationFidelityError(reason: "表格行列结构发生了改动") }
    }

    /// Uncertain changes remain visible for review. These checks deliberately
    /// do not claim to prove equivalence or spend another model request.
    static func reviewReasons(source: String, translation: String, target: TranslationTarget?) -> [String] {
        func sentences(_ text: String) -> Int {
            let prose = TranslationStructure.parts(text).filter(\.translatable).map(\.text).joined()
            let pattern = #"[。！？!?]+|\.(?=\s+[A-Z]|\s*$)"#
            let regex = try! NSRegularExpression(pattern: pattern)
            return max(1, regex.numberOfMatches(in: prose, range: NSRange(location: 0, length: (prose as NSString).length)))
        }
        let before = sentences(source), after = sentences(translation)
        var reasons = before <= 3 && after > before ? ["译文句子增多，可能包含额外解释"] : []
        let statisticalFold = source.range(of: #"训练折(?:内|中|[，。\s]|$)|(?i:\btraining\s+folds?\b)"#, options: .regularExpression) != nil
        let discount = translation.range(of: #"(?i:\bdiscount\b|rabatt)|折扣|割引|할인"#, options: .regularExpression) != nil
        if statisticalFold && discount { reasons.append("统计学训练折可能被误译为折扣") }
        if case let .foreign(language) = target, [.english, .german].contains(language) {
            let prose = TranslationStructure.parts(translation).filter(\.translatable).map(\.text).joined()
            let letters = prose.unicodeScalars.filter { CharacterSet.letters.contains($0) }
            let han = letters.filter { (0x3400...0x4DBF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }.count
            if han >= 4 && Double(han) / Double(max(1, letters.count)) > 0.3 {
                reasons.append("目标为" + language.name + "，译文正文仍含较多中文")
            }
        }
        return reasons
    }
}
