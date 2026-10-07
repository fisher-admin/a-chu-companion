import Foundation

/// macOS system translation accepts no instructions or glossary, so names and
/// literals are shielded with placeholders that measured as surviving all four
/// language pairs in both directions, then restored verbatim. Any missing or
/// duplicated placeholder discards the protected attempt entirely.
enum SystemTranslationProtection {
    struct Masked: Equatable {
        let text: String
        let replacements: [String: String]
    }

    // Only names measured as mistranslated when left alone (双子座, 克劳德).
    // Shielding names the system already keeps perturbed nearby wording.
    static let products = [#"Gemini"#, #"Claude(?! Code)"#]
    // Observed system mistranslations of statistics terms (build59 probe).
    // Corrected after translation, and only when the English source contains
    // the term: placeholders for these phrases disturbed sentence structure.
    static let chineseCorrections: [(source: String, wrong: [String], right: String)] = [
        ("unbiased estimator", ["不偏不倚的估计器", "公正的估计器", "无偏见的估计器"], "无偏估计量"),
        ("unbiased estimate", ["不偏不倚的估计", "公正的估计", "无偏见的估计"], "无偏估计"),
        ("unbiased", ["不偏不倚"], "无偏"),
        ("feature selection", ["功能选择"], "特征选择"),
        ("held-out error", ["保留错误", "保留误差", "留出错误"], "留出误差"),
        ("random variation", ["随机变化"], "随机波动"),
        ("chance", ["偶然的", "偶然性"], "随机水平"),
        ("engine", ["发动机"], "引擎"),
    ]
    static func corrected(_ translated: String, source: String) -> String {
        var result = translated
        for item in chineseCorrections where source.range(of: #"(?<![\p{L}\p{N}_])"# + NSRegularExpression.escapedPattern(for: item.source) + #"(?![\p{L}\p{N}_])"#, options: [.regularExpression, .caseInsensitive]) != nil {
            for wrong in item.wrong { result = result.replacingOccurrences(of: wrong, with: item.right) }
        }
        return result
    }
    private static let literalPatterns = [
        #"`[^`\n]+`"#,                                                     // inline code
        #"https?://[^\s<>"'）)]+"#,                                         // URLs
        #"(?<![A-Za-z0-9_.~/-])(?:~|\.{1,2})?/?[A-Za-z0-9_.@%+-]+(?:/[A-Za-z0-9_.@%+-]+)+/?"#, // absolute and relative paths (Latin only)
        #"(?<![\p{L}\p{N}_])[\w-]+(?:\.[\w-]+)*\.(?:py|swift|js|ts|json|md|txt|sh|csv|html|ya?ml|toml|log|plist|app)(?![\p{L}\p{N}_])"#,
        #"(?<![\p{L}\p{N}_.-])(?=[A-Za-z0-9_.-]*[A-Za-z])(?=[A-Za-z0-9_.-]*[0-9_])[A-Za-z][A-Za-z0-9]*(?:[._-][A-Za-z0-9]+)+(?![\p{L}\p{N}_-])"#, // gemini-3.1-flash-lite, leakage_sim
        #"(?<![\p{L}\p{N}_])[A-Za-z]+[0-9]+[A-Za-z0-9]*(?![\p{L}\p{N}_])"#,    // python3, build58
    ]

    static func mask(_ text: String, toChinese: Bool) -> Masked {
        guard !text.contains("⟦") else { return .init(text: text, replacements: [:]) }
        var result = text; var replacements: [String: String] = [:]; var next = 1
        func replace(_ pattern: String, options: NSString.CompareOptions = [], output: (String) -> String) {
            var searchStart = result.startIndex
            while let range = result.range(of: pattern, options: options.union(.regularExpression), range: searchStart..<result.endIndex) {
                let original = String(result[range])
                let token = "⟦\(next)⟧"; next += 1
                replacements[token] = output(original)
                result.replaceSubrange(range, with: token)
                searchStart = result.index(range.lowerBound, offsetBy: token.count)
            }
        }
        for pattern in literalPatterns { replace(pattern) { $0 } }
        if toChinese {
            // Measured: system translation keeps Latin names inside Chinese
            // text, but renders English "Gemini" as 双子座 and "Claude" as 克劳德.
            // Shielding names in the other direction degraded German grammar.
            for name in products { replace(#"(?<![\p{L}\p{N}_])"# + name + #"(?![\p{L}\p{N}_])"#) { $0 } }
        }
        return .init(text: result, replacements: replacements)
    }

    /// Restores every placeholder exactly once, or returns nil.
    static func restore(_ translated: String, _ masked: Masked) -> String? {
        var result = translated
        for (token, value) in masked.replacements {
            guard result.components(separatedBy: token).count == 2 else { return nil }
            result = result.replacingOccurrences(of: token, with: value)
        }
        return result.contains("⟦") && !masked.replacements.isEmpty ? nil : result
    }

    /// Translate with protection; fall back to the unprotected text whenever
    /// the system translation did not return every placeholder intact.
    /// The reply target is Simplified Chinese, yet system translation was
    /// observed returning Traditional for some slices inside the app.
    static func simplified(_ text: String) -> String {
        text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
    }
    static func translate(_ text: String, toChinese: Bool,
                          using translate: (String) async throws -> String) async throws -> String {
        let masked = mask(text, toChinese: toChinese)
        func attempt() async throws -> String {
            if masked.replacements.isEmpty { return try await translate(text) }
            if let restored = restore(try await translate(masked.text), masked) { return restored }
            return try await translate(text)
        }
        var output = try await attempt()
        if toChinese {
            // One retry usually returns Simplified; otherwise convert the script.
            if simplified(output) != output {
                let again = try await attempt()
                output = simplified(again) == again ? again : simplified(output)
            }
            output = corrected(output, source: text)
        }
        return output
    }
}
