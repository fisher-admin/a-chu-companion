import Foundation

@main struct ParagraphTests {
    static var count = 0
    static func check(_ value: Bool, _ name: String) {
        guard value else { fputs("FAIL: \(name)\n", stderr); exit(1) }
        count += 1; print("PASS: \(name)")
    }
    static func reply(_ children: [ReplyNode], code: Bool = true) -> ReplyNode {
        .init(role: "AXGroup", label: code ? "Message 2" : "Message 2 of 2", children: [
            .init(role: "AXHeading", label: "Claude responded: Results")
        ] + children)
    }
    @MainActor static func main() async throws {
        // Sanitized structure of an actual Code paragraph with inline files.
        let files = ReplyNode(role: "AXGroup", children: [
            .init(role: "AXStaticText", text: "Results are in the new script "),
            .init(role: "AXButton", label: "simulation.py"),
            .init(role: "AXStaticText", text: " and its result file "),
            .init(role: "AXButton", label: "results.json"),
            .init(role: "AXStaticText", text: ". Earlier files are unchanged.")
        ])
        let expected = "Results are in the new script simulation.py and its result file results.json. Earlier files are unchanged."
        let code = reply([files])
        check(ClaudeDecoder.codeSegments(code, responseComplete: true).first?.text == expected,
              "inline file references remain in one Code paragraph without injected newlines")
        check(ClaudeDecoder.messages(code, format: .code).first?.text == expected,
              "full Code capture and segmented capture use identical paragraph assembly")
        // Actual Code capture flattens the author wrapper, leaving inline
        // static filename nodes directly beside the message anchor.
        let flatFiles = reply([
            .init(role: "AXStaticText", text: "Plan: I'll read "),
            .init(role: "AXStaticText", text: "leakage_sim.py"),
            .init(role: "AXStaticText", text: " without changing it.")
        ])
        let flatExpected = "Plan: I'll read leakage_sim.py without changing it."
        check(ClaudeDecoder.codeSegments(flatFiles, responseComplete: false).first?.text == flatExpected,
              "flattened streaming Code static filename stays inside its sentence")
        check(ClaudeDecoder.messages(flatFiles, format: .code).first?.text == flatExpected,
              "flattened final Code capture preserves the same inline filename sentence")
        let wrappedFiles = reply([
            .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: "Plan: I'll read ")]),
            .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: "leakage_sim.py")]),
            .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: " without changing it.")])
        ])
        check(ClaudeDecoder.codeSegments(wrappedFiles, responseComplete: true).first?.text == flatExpected,
              "inline filename identity survives separate accessibility wrappers")
        let directory = reply([
            .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: "Results stay inside ")]),
            .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: "continuation-build50/")]),
            .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: ".")])
        ])
        check(ClaudeDecoder.codeSegments(directory, responseComplete: false).first?.text == "Results stay inside continuation-build50/.",
              "an inline directory keeps its sentence spacing during a Code reply")
        let directoryBlock = reply([
            .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: "Results stay inside ")]),
            .init(role: "AXGroup", label: "Code", children: [.init(role: "AXStaticText", text: "continuation-build50/")]),
            .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: ".")])
        ])
        check(ClaudeDecoder.codeSegments(directoryBlock, responseComplete: true).first?.text == "Results stay inside \ncontinuation-build50/\n.",
              "an explicit directory code block retains its original block boundary")
        let wrappedFinal = reply([
            .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: "Results are in ")]),
            .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: "first.json")]),
            .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: " and ")]),
            .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: "second.json")]),
            .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: ". Values are unchanged.")]),
            .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: "A separate paragraph.")])
        ])
        check(ClaudeDecoder.codeSegments(wrappedFinal, responseComplete: true).first?.text ==
              "Results are in first.json and second.json. Values are unchanged.\nA separate paragraph.",
              "wrapped inline references merge without merging the next paragraph")
        let standaloneCodeFile = reply([
            .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: "Read ")]),
            .init(role: "AXGroup", label: "Code", children: [.init(role: "AXStaticText", text: "example.py")]),
            .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: " separately.")])
        ])
        check(ClaudeDecoder.codeSegments(standaloneCodeFile, responseComplete: true).first?.text ==
              "Read \nexample.py\n separately.", "an explicit code block never becomes an inline filename")
        let literalFileBreaks = "Read \nexample.py\n separately."
        check(ClaudeDecoder.codeSegments(reply([.init(role: "AXStaticText", text: literalFileBreaks)]), responseComplete: true).first?.text == literalFileBreaks,
              "literal source line breaks around a filename remain untouched")
        let flatFinal = reply([
            .init(role: "AXStaticText", text: "Results are in "),
            .init(role: "AXStaticText", text: "leakage_results_p20.json"),
            .init(role: "AXStaticText", text: " and "),
            .init(role: "AXStaticText", text: "leakage_results_p100.json"),
            .init(role: "AXStaticText", text: ". Spread is the empirical standard deviation."),
            .init(role: "AXStaticText", text: "Limitation: synthetic data only.")
        ])
        check(ClaudeDecoder.codeSegments(flatFinal, responseComplete: true).first?.text ==
              "Results are in leakage_results_p20.json and leakage_results_p100.json. Spread is the empirical standard deviation.\nLimitation: synthetic data only.",
              "two flattened inline filenames and following punctuation preserve the actual paragraph boundary")
        let standaloneFiles = reply([
            .init(role: "AXStaticText", text: "A genuine paragraph."),
            .init(role: "AXStaticText", text: "leakage_sim.py"),
            .init(role: "AXGroup", label: "Code", children: [.init(role: "AXStaticText", text: "results.json\n  value = 3")])
        ])
        check(ClaudeDecoder.codeSegments(standaloneFiles, responseComplete: true).first?.text ==
              "A genuine paragraph.\nleakage_sim.py\nresults.json\n  value = 3",
              "standalone filenames and code blocks cannot be mistaken for inline prose")
        let link = ReplyNode(role: "AXLink", label: "the report", children: [.init(role: "AXStaticText", text: "the report")])
        let linked = ReplyNode(role: "AXGroup", children: [.init(role: "AXStaticText", text: "Read "), link,
                                                         .init(role: "AXStaticText", text: " before the next step.")])
        check(ClaudeDecoder.messages(reply([linked], code: false)).first?.text == "Read the report before the next step.",
              "Chat preserves an inline link inside its surrounding sentence")
        check(ClaudeDecoder.codeSegments(reply([linked]), responseComplete: false).first?.text == "Read the report before the next step.",
              "Code streaming preserves inline links before task completion")
        let emphasis = ReplyNode(role: "AXGroup", children: [.init(role: "AXStaticText", text: "This "),
            .init(role: "AXStaticText", text: "important"), .init(role: "AXStaticText", text: " result stays together.")])
        check(ClaudeDecoder.codeSegments(reply([emphasis]), responseComplete: true).first?.text == "This important result stays together.",
              "whitespace-separated inline emphasis fragments stay in the same Code sentence")
        check(ClaudeDecoder.messages(reply([emphasis], code: false)).first?.text == "This important result stays together.",
              "Chat uses the same inline whitespace rule")
        let paragraphs = reply([files, .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: "A separate paragraph.")])])
        let body = ClaudeDecoder.codeSegments(paragraphs, responseComplete: true).first?.text ?? ""
        check(body == expected + "\nA separate paragraph.", "genuine sibling paragraphs remain separated after an inline reference")
        let spacedParagraphs = reply([.init(role: "AXGroup", children: [.init(role: "AXStaticText", text: "One paragraph. ")]),
            .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: " Another paragraph.")])])
        check(ClaudeDecoder.codeSegments(spacedParagraphs, responseComplete: true).first?.text == "One paragraph. \n Another paragraph.",
              "whitespace at real paragraph container edges cannot merge separate paragraphs")
        let flatParagraphs = reply([.init(role: "AXStaticText", text: "First paragraph."),
                                    .init(role: "AXStaticText", text: " Second paragraph.")])
        check(ClaudeDecoder.codeSegments(flatParagraphs, responseComplete: true).first?.text == "First paragraph.\n Second paragraph.",
              "flat Code paragraph siblings retain their boundary even with leading whitespace")
        let lines = "First line.\nSecond line.\n\nAnother paragraph.\n```python\n  x = 3\n```"
        check(ClaudeDecoder.codeSegments(reply([.init(role: "AXStaticText", text: lines)]), responseComplete: true).first?.text == lines,
              "literal paragraph breaks, indentation and code line breaks survive source capture")
        let list = ReplyNode(role: "AXList", children: ["First item", "Second item"].map { value in
            ReplyNode(role: "AXGroup", children: [.init(role: "AXListMarker", text: "• "), .init(role: "AXStaticText", text: value)])
        })
        check(ClaudeDecoder.codeSegments(reply([list]), responseComplete: true).first?.text == "• First item\n• Second item",
              "list markers stay with their item and different items retain line breaks")
        let normalized = try await TextTranslation.run("One continuous paragraph.") { _ in "  这是同一段话。\n\n不要拆成两段。\n" }
        check(normalized == "这是同一段话。 不要拆成两段。", "a provider cannot insert hard paragraph breaks into a single-line prose slice")
        let inlineCode = try await TextTranslation.runProtected("Use `value` here.") { value in
            value == "Use" ? "使用\n" : "\n这里。"
        }
        check(inlineCode == "使用 `value` 这里。", "translation chunk edges do not inject newlines around protected inline code")
        let multiline = "First paragraph.\n\nSecond paragraph."
        let unchanged = try await TextTranslation.run(multiline) { $0 }
        check(unchanged == multiline, "intentional multiline source formatting is not flattened")
        let chunkSource = String(repeating: "Keep this sentence continuous. ", count: 30)
        let chunkResult = try await TextTranslation.run(chunkSource, limit: 80) { "\n" + $0.uppercased() + "\n" }
        check(chunkResult == chunkSource.uppercased(), "long paragraph chunks merge without provider-added boundary newlines")
        var requests = 0; var chinese = ""; var ready = false; var original = ""
        let pipeline = ReplyPipeline { _ in
            requests += 1; return requests == 1 ? "\n中文起始。\n" : "\n后续中文。\n"
        }
        pipeline.onOriginal = { _, value, _ in original = value }
        pipeline.onTranslation = { _, _, value, complete in chinese = value; ready = complete }
        let first = "One stable sentence. "
        pipeline.observe(conversation: "paragraph-stream", messages: [.init(ordinal: 2, author: .assistant, text: first)], responseComplete: false, now: 0)
        pipeline.tick(now: 3)
        while pipeline.busy { try await Task.sleep(for: .milliseconds(5)) }
        let earlyChinese = chinese
        pipeline.observe(conversation: "paragraph-stream", messages: [.init(ordinal: 2, author: .assistant, text: first + "A continuation.")], responseComplete: false, now: 4)
        let immediateOriginal = original
        pipeline.tick(now: 7)
        while pipeline.busy { try await Task.sleep(for: .milliseconds(5)) }
        check(earlyChinese == "中文起始。 " && !ready && immediateOriginal == first + "A continuation." && chinese == "中文起始。 后续中文。" && requests == 2,
              "stable Chinese still arrives before completion and later slices continue the same paragraph")
        pipeline.cancel()
        let returnedCell = "真实误差\n\n" + String(repeating: "不要把周围正文加入表头。", count: 30)
        let expandedCell = try await TranslationContext.$source.withValue("Synthetic statistical context, never output.") {
            try await TextTranslation.run("Honest error") { _ in returnedCell }
        }
        check(expandedCell == returnedCell, "table cell output is not rejected by a length-based quality gate")
        let legitimateCell = try await TranslationContext.$source.withValue("Statistical context") {
            try await TextTranslation.run("Spread") { _ in "离散\n程度" }
        }
        check(legitimateCell == "离散\n程度", "short legitimate multiline table cells remain available for safe table escaping")
        print("\(count) paragraph contracts passed")
    }
}
