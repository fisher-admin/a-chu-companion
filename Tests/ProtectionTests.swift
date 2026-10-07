import Foundation

@main struct ProtectionTests {
    static var passed = 0
    static var failed = 0
    static func check(_ value: Bool, _ name: String) {
        if value { passed += 1; print("PASS: " + name) }
        else { failed += 1; fputs("FAIL: \(name)\n", stderr) }
    }
    @MainActor static func main() async throws {
        let source = "The script leakage_sim.py writes leakage_results_p20.json and RESULTS.CSV."
        var sent: [String] = []
        let result = try await TextTranslation.runProtected(source) { sent.append($0); return $0.uppercased() }
        check(result.contains("leakage_sim.py") && result.contains("leakage_results_p20.json") && result.contains("RESULTS.CSV"),
              "plain filenames retain exact bytes even when a translator changes all received text")
        check(!sent.contains { $0.contains("leakage_sim.py") || $0.contains("leakage_results_p20.json") || $0.contains("RESULTS.CSV") },
              "plain filenames stay on device and never enter provider input")
        let ordinary = "This is an example, e.g. a study in Fig. 2 with 1.25 variance."
        let ordinaryResult = try await TextTranslation.runProtected(ordinary) { $0.uppercased() }
        check(ordinaryResult == ordinary.uppercased(), "ordinary punctuation and abbreviations remain translatable")
        let table = "| File | Note |\n| --- | --- |\n| leakage_sim.py | Check this |"
        let tableResult = try await TextTranslation.runProtected(table) { $0.uppercased() }
        check(tableResult.contains("leakage_sim.py") && MarkdownTable.blocks(tableResult).count == 1,
              "filenames inside table cells retain structure and literal spelling")
        let request = try TranslationContext.$source.withValue("Spread means empirical standard deviation.") {
            try AIProtocol.request(text: "Spread", baseURL: "https://example.com", model: "test-model", key: "dummy-context-key", direction: .toChinese(.english))
        }
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let messages = body["messages"] as! [[String: String]]
        let fields = try? JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as? [String: String]
        check(fields?["source_text"] == "Spread" && fields?["context_only"]?.contains("standard deviation") == true,
              "compatible AI receives bounded table context separately from source text")
        check(messages[0]["content"]?.contains("context_only") == true,
              "compatible AI explicitly treats table context as data that must not be translated")
        let systemInput = TranslationContext.$source.withValue("Spread means empirical standard deviation.\nTable text: Spread") {
            TranslationContext.systemInput("Spread")
        }
        check(systemInput == "empirical standard deviation", "system translation uses an explicit nearby definition for a table label")
        let unrelated = TranslationContext.$source.withValue("This discusses the spread of disease.") { TranslationContext.systemInput("Spread") }
        check(unrelated == "Spread" && TranslationContext.systemInput("Spread") == "Spread", "system translation never guesses a meaning from an unrelated or absent context")
        let ambiguous = TranslationContext.$source.withValue("Spread means standard deviation. Spread means range.") { TranslationContext.systemInput("Spread") }
        check(ambiguous == "Spread", "conflicting explicit definitions do not silently select one meaning")
        let afterTable = "| Spread |\n| --- |\n| 0.25 |\n\nSpread means empirical standard deviation."
        let cell = TranslationStructure.parts(afterTable).first { $0.tableCell && $0.text.trimmingCharacters(in:.whitespacesAndNewlines) == "Spread" }
        let defined = TranslationContext.$source.withValue(cell?.context) { TranslationContext.systemInput("Spread") }
        check(defined == "empirical standard deviation", "definitions immediately below a table are available to its isolated cells")
        let emphasizedDefinition = "**Spread** is the empirical standard deviation of leaky test MSE across 5,000 replications."
        let emphasized = TranslationContext.$source.withValue(emphasizedDefinition) { TranslationContext.systemInput("Spread") }
        check(emphasized == "empirical standard deviation", "emphasized statistical definitions from the actual CLI reply produce a concise system table label")
        let markedAfterTable = "| Spread |\n| --- |\n| 0.25 |\n\n" + emphasizedDefinition
        let markedCell = TranslationStructure.parts(markedAfterTable).first { $0.tableCell && $0.text.trimmingCharacters(in:.whitespacesAndNewlines) == "Spread" }
        check(markedCell?.context?.contains("standard deviation") == true, "definitions with emphasis below a table enter the shared context")
        let negative = TranslationContext.$source.withValue("Spread is not a standard deviation. Spread is large.") { TranslationContext.systemInput("Spread") }
        check(negative == "Spread", "negative and ordinary is predicates never become guessed statistical labels")
        print("\(passed) protection contracts passed; \(failed) failed")
        if failed != 0 { exit(1) }
    }
}
