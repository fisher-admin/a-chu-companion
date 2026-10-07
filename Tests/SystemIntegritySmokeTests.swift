import Foundation
import Translation

@main struct SystemIntegritySmokeTests {
    @MainActor static func main() async throws {
        guard #available(macOS 26.0, *) else { exit(2) }
        let session = TranslationSession(installedSource: .init(identifier: "en"), target: .init(identifier: "zh-Hans"))
        let source = "This study has not been conducted. Do not delete files. Results are in leakage_sim.py and results.json. Spread means empirical standard deviation.\n\n| Spread |\n| --- |\n| 0.25 |"
        let translated = try await TextTranslation.runProtected(source) { text in
            try await session.translate(TranslationContext.systemInput(text)).targetText
        }
        print(translated)
        let table = MarkdownTable.blocks(translated).compactMap { if case let .table(value) = $0 { return value }; return nil }.first
        let literal = translated.contains("leakage_sim.py") && translated.contains("results.json") && table?.rows.first == ["0.25"]
        print(literal ? "PASS: actual system translation retains filenames and numeric cells" : "FAIL: actual system translation changed a protected value")
        let meaning = table?.headers.first?.contains("标准差") == true
        print(meaning ? "PASS: contextual statistical header has the defined meaning" : "FAIL: system translation of a contextual statistical header lacks its defined meaning")
        if !literal || !meaning { exit(1) }
        let marked = "| Spread |\n| --- |\n| 0.25 |\n\n**Spread** is the empirical standard deviation of leaky test MSE across 5,000 replications."
        let contextual = try await TextTranslation.runProtected(marked) { text in
            try await session.translate(TranslationContext.systemInput(text)).targetText
        }
        let markedTable = MarkdownTable.blocks(contextual).compactMap { if case let .table(value) = $0 { return value }; return nil }.first
        let markedMeaning = markedTable?.headers.first?.contains("标准差") == true && markedTable?.rows.first == ["0.25"]
        print(markedMeaning ? "PASS: actual system label respects emphasized is-definition below the table" : "FAIL: emphasized actual CLI definition was missed")
        if !markedMeaning { exit(1) }
    }
}
