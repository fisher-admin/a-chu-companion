import Foundation

@main struct TableTests {
    static let markdown = "| Students | Noise | Spread |\n| --- | --- | --- |\n| 60 | 8 | 2.52 |\n| 120 | 12 | 16% |"
    static func cell(_ text: String, role: String = "AXCell") -> ReplyNode {
        .init(role: role, children: [.init(role: "AXStaticText", text: text)])
    }
    @MainActor static func main() async throws {
        let table = ReplyNode(role: "AXTable", children: [
            .init(role: "AXRow", children: [cell("Students", role: "AXColumn"), cell("Noise", role: "AXColumn"), cell("Spread", role: "AXColumn")]),
            .init(role: "AXRow", children: [cell("60"), cell("8"), cell("2.52")]),
            .init(role: "AXRow", children: [cell("120"), cell("12"), cell("16%")])
        ])
        let message = ReplyNode(role: "AXGroup", label: "Message 2", children: [
            .init(role: "AXHeading", label: "Claude responded: Results"), table
        ])
        guard ClaudeDecoder.messages(message, format: .code).first?.text == markdown else {
            fputs("FAIL: AX table rows, columns and header must survive formal reply capture\n", stderr); exit(1)
        }
        print("PASS: accessibility table retains rows, columns and header")
        var calls: [String] = []
        let translated = try await TextTranslation.runProtected(markdown) { text in
            calls.append(text)
            return ["Students": "学生人数", "Noise": "噪声", "Spread": "离散程度"][text] ?? "UNEXPECTED"
        }
        precondition(translated == markdown.replacingOccurrences(of: "Students", with: "学生人数").replacingOccurrences(of: "Noise", with: "噪声").replacingOccurrences(of: "Spread", with: "离散程度"))
        precondition(calls == ["Students", "Noise", "Spread"])
        print("PASS: only textual cells go to translation; numeric cells and delimiters are preserved locally")
        let block = MarkdownTable.blocks(translated)
        guard case .table(let parsed) = block.first else { fatalError("translated table missing") }
        precondition(parsed.headers == ["学生人数", "噪声", "离散程度"] && parsed.rows == [["60", "8", "2.52"], ["120", "12", "16%"]])
        print("PASS: Chinese renderer receives the original table geometry and unchanged values")
        let protected = "| Method | Literal |\n| :--- | ---: |\n| Active recall | `a|b` |\n| Control | $x=3$ |\n| Website | https://example.com/report |"
        let upper = try await TextTranslation.runProtected(protected) { $0.uppercased() }
        precondition(upper.contains("`a|b`") && upper.contains("$x=3$") && upper.contains("https://example.com/report"))
        guard case .table(let protectedTable) = MarkdownTable.blocks(upper).first else { fatalError("protected table missing") }
        precondition(protectedTable.headers.count == 2 && protectedTable.rows.count == 3)
        print("PASS: table code, formulas and URLs stay local and preserve cell boundaries")
        let escaped = "| Label | Value |\n| --- | --- |\n| A\\|B | 2.52 |"
        let changed = try await TextTranslation.runProtected(escaped) { _ in "中文|另列\n第二行" }
        guard case .table(let safeTable) = MarkdownTable.blocks(changed).first else { fatalError("escaped translation table missing") }
        precondition(safeTable.rows[0].count == 2 && safeTable.rows[0][1] == "2.52" && safeTable.rows[0][0].contains("\\|") && safeTable.rows[0][0].contains("<br>"))
        print("PASS: model-added pipes and newlines cannot create new rows or columns")
        let malformed = "| A | B |\n| --- | --- |\n| incomplete |\n"
        precondition(MarkdownTable.blocks(malformed) == [.text(malformed)])
        print("PASS: a malformed or unfinished row is kept intact instead of silently truncated")
        let fenced = "```markdown\n" + markdown + "\n```"
        precondition(MarkdownTable.blocks(fenced) == [.text(fenced)] && TranslationStructure.parts(fenced).allSatisfy { !$0.translatable })
        print("PASS: tables shown inside code fences stay code rather than becoming live tables")
        let surrounding = "Results:\n\n" + markdown + "\n\nNo real participants."
        precondition(TranslationStructure.parts(surrounding).map(\.text).joined() == surrounding && MarkdownTable.blocks(surrounding).count == 3)
        print("PASS: prose, whitespace and tables round-trip together without losing content")
        let chat = ReplyNode(role: "AXGroup", label: "Message 2 of 2", children: [
            .init(role: "AXHeading", label: "Claude responded: Results"), .init(role: "AXGroup", children: [table])
        ])
        precondition(ClaudeDecoder.messages(chat).first?.text == markdown)
        print("PASS: Chat and Code formal table capture share the same row-preserving format")
        let oneColumn = "| Header |\n| --- |\n| One |"
        guard case .table(let single) = MarkdownTable.blocks(oneColumn).first else { fatalError("single column missing") }
        precondition(single.headers.count == 1 && single.rows == [["One"]])
        print("PASS: single-column tables work while ragged multi-column rows remain invalid")
        let multiLine = ReplyNode(role: "AXTable", children: [
            .init(role: "AXRow", children: [cell("Label", role: "AXColumn"), cell("Value", role: "AXColumn")]),
            .init(role: "AXRow", children: [cell("Line one\nLine two | literal"), cell("3")])
        ])
        var multilineMessage = message; multilineMessage.children[1] = multiLine
        precondition(ClaudeDecoder.messages(multilineMessage, format: .code).first?.text.contains("Line one<br>Line two \\| literal") == true)
        print("PASS: multiline and literal-pipe accessibility cells retain their content and boundaries")
        var pipelineResult = ""; var finished = false
        let pipeline = ReplyPipeline(translate: { _ in "中文|内容\n续行" })
        pipeline.onTranslation = { _, _, value, complete in pipelineResult = value; finished = complete }
        pipeline.observe(conversation: "synthetic-table", messages: [.init(ordinal: 2, author: .assistant, text: escaped)], responseComplete: true, now: 0)
        let deadline = Date().addingTimeInterval(5)
        while !finished && Date() < deadline { await Task.yield() }
        guard finished, case .table(let pipelineTable) = MarkdownTable.blocks(pipelineResult).first else { fatalError("pipeline table did not complete") }
        precondition(pipelineTable.headers.count == 2 && pipelineTable.rows[0].count == 2 && pipelineTable.rows[0][1] == "2.52")
        pipeline.cancel()
        print("PASS: the incremental reply pipeline also prevents translated cell text from breaking table geometry")
        let files = ReplyNode(role: "AXList", children: ["simulate.py", "baseline_results.json", "sensitivity_results.csv"].map { name in
            ReplyNode(role: "AXGroup", children: [.init(role: "AXButton", label: name)])
        })
        let fileMessage = ReplyNode(role: "AXGroup", label: "Message 2", children: [.init(role: "AXHeading", label: "Claude responded: Results"), files])
        let capturedFiles = ClaudeDecoder.messages(fileMessage, format: .code).first?.text ?? ""
        guard capturedFiles.contains("simulate.py") && capturedFiles.contains("baseline_results.json") && capturedFiles.contains("sensitivity_results.csv") else {
            fputs("FAIL: a CSV file reference must not hide the whole formal file list\n", stderr); exit(1)
        }
        print("PASS: a CSV file reference preserves the full formal result file list")
        print("13 table tests passed")
    }
}
