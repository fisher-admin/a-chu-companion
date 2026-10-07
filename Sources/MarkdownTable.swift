import Foundation

struct MarkdownTable: Equatable, Sendable {
    enum Alignment: Sendable { case left, center, right }
    let source: String
    let headers: [String]
    let rows: [[String]]
    let alignments: [Alignment]

    enum Block: Equatable { case text(String), table(MarkdownTable) }

    // Keep escaped pipes and pipes inside inline code in their own cells.
    static func tokens(_ line: String) -> [String] {
        let characters = Array(line); var result: [String] = []; var current = ""
        var index = 0; var ticks = 0
        while index < characters.count {
            let c = characters[index]
            if c == "\\", index + 1 < characters.count {
                current.append(c); current.append(characters[index + 1]); index += 2; continue
            }
            if c == "`" {
                var end = index
                while end < characters.count, characters[end] == "`" { end += 1 }
                let count = end - index
                if ticks == 0 { ticks = count } else if ticks == count { ticks = 0 }
                current += String(repeating: "`", count: count); index = end; continue
            }
            if c == "|", ticks == 0 {
                result.append(current); result.append("|"); current = ""
            } else { current.append(c) }
            index += 1
        }
        result.append(current)
        return result
    }
    static func cells(_ line: String) -> [String]? {
        let line = line.trimmingCharacters(in: .whitespaces)
        let pieces = tokens(line)
        guard pieces.contains("|") else { return nil }
        var cells = pieces.enumerated().filter { $0.offset.isMultiple(of: 2) }.map { $0.element.trimmingCharacters(in: .whitespaces) }
        if pieces.first == "" { cells.removeFirst() }
        if pieces.last == "", !cells.isEmpty { cells.removeLast() }
        return cells.isEmpty ? nil : cells
    }
    private static func separators(_ line: String) -> [Alignment]? {
        guard let cells = cells(line), cells.allSatisfy({ $0.range(of: "^:?-{3,}:?$", options: .regularExpression) != nil }) else { return nil }
        return cells.map { $0.hasSuffix(":") ? ($0.hasPrefix(":") ? .center : .right) : .left }
    }
    static func blocks(_ text: String) -> [Block] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var result: [Block] = []; var plain = ""; var i = 0
        var fence: Character?; var fenceCount = 0
        func line(_ index: Int) -> String { lines[index] + (index < lines.count - 1 ? "\n" : "") }
        while i < lines.count {
            let trimmed = lines[i].drop(while: { $0 == " " || $0 == "\t" })
            let c = trimmed.first
            let count = c.map { character in trimmed.prefix(while: { $0 == character }).count } ?? 0
            if let active = fence {
                plain += line(i)
                if c == active, count >= fenceCount, trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                i += 1; continue
            }
            if (c == "`" || c == "~"), count >= 3 {
                fence = c; fenceCount = count; plain += line(i); i += 1; continue
            }
            if i + 1 < lines.count, let headers = cells(lines[i]), let alignments = separators(lines[i + 1]), headers.count == alignments.count {
                var end = i + 2; var rows: [[String]] = []; var valid = true
                while end < lines.count, let cells = cells(lines[end]) {
                    if cells.count != headers.count { valid = false }
                    rows.append(cells); end += 1
                }
                if valid {
                    if !plain.isEmpty { result.append(.text(plain)); plain = "" }
                    result.append(.table(.init(source: (i..<end).map(line).joined(), headers: headers, rows: rows, alignments: alignments)))
                    i = end; continue
                }
                // A malformed or unfinished row stays intact as original text.
                plain += (i..<end).map(line).joined(); i = end; continue
            }
            plain += line(i); i += 1
        }
        if !plain.isEmpty { result.append(.text(plain)) }
        return result
    }
    static func escapeCell(_ value: String) -> String {
        var result = ""; var slashes = 0
        for c in value {
            if c == "|", slashes.isMultiple(of: 2) { result += "\\" }
            if c == "\n" { result += "<br>" } else if c != "\r" { result.append(c) }
            slashes = c == "\\" ? slashes + 1 : 0
        }
        return result
    }
    static func displayCell(_ value: String) -> String {
        value.replacingOccurrences(of: "\\|", with: "|").replacingOccurrences(of: "<br>", with: "\n")
    }
    static func source(headers: [String], rows: [[String]]) -> String {
        func row(_ cells: [String]) -> String { "| " + cells.map(escapeCell).joined(separator: " | ") + " |" }
        return ([row(headers), row(Array(repeating: "---", count: headers.count))] + rows.map(row)).joined(separator: "\n")
    }
}
