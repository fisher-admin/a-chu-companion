import Foundation
import CryptoKit

struct ReplyNode: Sendable {
    let role: String
    var label: String = ""
    var text: String = ""
    var children: [ReplyNode] = []
    var isStreamingAssistant = false
}
struct ChatMessage: Equatable, Sendable {
    enum Author: Sendable { case user, assistant }
    let ordinal: Int
    let author: Author
    let text: String
    var segment: Int = 0
    var completed: Bool? = nil
    var address: ReplyAddress { .init(ordinal: ordinal, segment: segment) }
}
struct ReplyCandidate: Equatable, Sendable {
    let ordinal: Int
    let text: String
    var segment: Int = 0
    var address: ReplyAddress { .init(ordinal: ordinal, segment: segment) }
}

struct ReplyAddress: Hashable, Comparable, Sendable {
    let ordinal: Int
    let segment: Int
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.ordinal == rhs.ordinal ? lhs.segment < rhs.segment : lhs.ordinal < rhs.ordinal
    }
}

struct ReplyReadPending: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

enum ClaudeTranscriptFormat: Sendable { case chat, code }

enum ClaudeConversationPage {
    static func format(_ address: String) -> ClaudeTranscriptFormat? {
        guard let url = URL(string: address), url.scheme == "https", url.host == "claude.ai" else { return nil }
        let parts = url.path.split(separator: "/")
        if (1...2).contains(parts.count), parts[0] == "epitaxy" { return .code }
        if parts.count >= 2, parts[0] == "chat" { return .chat }
        return ["/", "", "/new"].contains(url.path) ? .chat : nil
    }
}

struct ClaudeMessagePosition {
    let ordinal: Int
    let total: Int?
}

struct CodeMessageRange {
    let ordinal: Int
    let range: Range<Int>
}

struct CodeTranscriptBranch<Element> {
    let element: Element
    let ordinal: Int?
    var children: [CodeTranscriptBranch<Element>] = []
    var author: ChatMessage.Author? = nil
    var isStreamingAssistant = false
}
struct CodeTranscriptPiece<Element> {
    let element: Element
    let ordinal: Int?
    var author: ChatMessage.Author? = nil
    var isStreamingAssistant = false
}

struct ReplyTranslationLifecycle {
    private(set) var activeID: UUID?
    var isTranslating: Bool { activeID != nil }

    mutating func begin() -> UUID {
        let id = UUID()
        activeID = id
        return id
    }

    func isCurrent(_ id: UUID) -> Bool { activeID == id }

    @discardableResult mutating func finish(_ id: UUID) -> Bool {
        guard activeID == id else { return false }
        activeID = nil
        return true
    }

    @discardableResult mutating func cancel(_ id: UUID) -> Bool { finish(id) }
}

enum ClaudeDecoder {
    private struct BodyText {
        let value: String
        var joinsPrevious = false
        var joinsNext = false
        var block = false
        var staticFileName = false
    }
    private static func joined(_ fragments: [BodyText], inlineWhitespace: Bool = true) -> String {
        var result = ""; var previous: BodyText?
        for fragment in fragments where !fragment.value.isEmpty {
            if let previous {
                let spacedInline = inlineWhitespace && !previous.block && !fragment.block &&
                    ([" ", "\t"].contains(previous.value.last) || [" ", "\t"].contains(fragment.value.first))
                if previous.block || fragment.block || (!previous.joinsNext && !fragment.joinsPrevious && !spacedInline) { result += "\n" }
            }
            result += fragment.value; previous = fragment
        }
        return result
    }
    static func codeSegments(_ root: ReplyNode, responseComplete: Bool) -> [ChatMessage] {
        guard let n = position(root.label, format: .code)?.ordinal else { return [] }
        guard let author = codeAuthor(root, ordinal: n) else { return [] }
        let full = codeBody(root)
        // Keep the original per-reply limit: splitting cannot bypass it.
        if author == .user || full.count > ForeignTextPolicy.limit { return messages(root, format: .code) }
        var result: [ChatMessage] = []
        var text: [BodyText] = []
        func finish(_ completed: Bool) {
            let value = joined(text)
            text = []
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            result.append(.init(ordinal: n, author: author, text: value, segment: result.count + 1, completed: completed))
        }
        for part in codeBodyParts(root) {
            switch part {
            case .text(let value): text.append(value)
            case .tool: finish(true)
            }
        }
        finish(responseComplete)
        return result
    }
    /// Privacy-safe diagnostic: per message, its ordinal, detected author,
    /// streaming flag and counts of images, buttons and text characters.
    static func structureSummary(_ nodes: [ReplyNode]) -> String {
        func count(_ node: ReplyNode, _ match: (ReplyNode) -> Bool) -> Int { (match(node) ? 1 : 0) + node.children.reduce(0) { $0 + count($1, match) } }
        func chars(_ node: ReplyNode) -> Int { node.text.count + node.children.reduce(0) { $0 + chars($1) } }
        return nodes.map { node in
            let ordinal = position(node.label, format: .code)?.ordinal ?? -1
            let author = codeAuthor(node, ordinal: ordinal).map { $0 == .user ? "u" : "a" } ?? "?"
            let headings = count(node) { $0.role == "AXHeading" }
            return "[\(ordinal) \(author) s=\(node.isStreamingAssistant ? 1 : 0) img=\(count(node) { $0.role == "AXImage" }) btn=\(count(node) { $0.role == "AXButton" }) h=\(headings) top=\(node.children.count) chars=\(chars(node))]"
        }.joined(separator: " ")
    }
    static func recentCodeSegments(_ nodes: [ReplyNode], responseComplete: Bool) throws -> [ChatMessage] {
        let full = try recentMessages(nodes, format: .code)
        let ordinals = Set(full.map(\.ordinal))
        let latest = full.last?.ordinal ?? 0
        return nodes.flatMap { node -> [ChatMessage] in
            guard let n = position(node.label, format: .code)?.ordinal, ordinals.contains(n) else { return [] }
            return codeSegments(node, responseComplete: n < latest || responseComplete)
        }
    }
    static func responseComplete(statusLabels: [String], controlLabels: [String], latest: ReplyNode?, format: ClaudeTranscriptFormat = .chat) -> Bool {
        let controls = controlLabels.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        if controls.contains(where: { ["stop response", "stop generating", "stop"].contains($0) }) { return false }
        let statuses = statusLabels.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        if statuses.contains(where: { ["claude is responding", "claude is thinking", "claude is working"].contains($0) }) { return false }
        if statuses.contains("claude finished the response") { return true }
        func hasFinalActions(_ node: ReplyNode) -> Bool {
            if node.role == "AXToolbar", node.label == "Message actions" {
                let names = node.children.map(\.label)
                return names.contains("Copy") && (names.contains("Retry") || names.contains("Good response") || (format == .code && names.contains("Fork from here")))
            }
            return node.children.contains(where: hasFinalActions)
        }
        return latest.map(hasFinalActions) ?? false
    }
    static func position(_ label: String, format: ClaudeTranscriptFormat) -> ClaudeMessagePosition? {
        let parts = label.split(separator: " ")
        guard parts.first == "Message", parts.count >= 2, let n = Int(parts[1]), n > 0 else { return nil }
        if format == .code, parts.count == 2 { return .init(ordinal: n, total: nil) }
        guard parts.count == 4, parts[2] == "of", let total = Int(parts[3]), n <= total else { return nil }
        return .init(ordinal: n, total: total)
    }
    // Code's paragraph siblings belong to the preceding author-marked ordinal,
    // through the next ordinal. Content before the first marker is never read.
    static func codeMessageRanges(_ labels: [String]) throws -> [CodeMessageRange] {
        for label in labels where label.hasPrefix("Message ") && label != "Message actions" {
            guard position(label, format: .code) != nil else {
                throw ReplyReadPending(message: "Claude Code 消息序号尚未完整。")
            }
        }
        let markers = labels.enumerated().compactMap { index, label -> (Int, Int)? in
            position(label, format: .code).map { (index, $0.ordinal) }
        }
        guard zip(markers, markers.dropFirst()).allSatisfy({ $0.1 < $1.1 }) else {
            throw ReplyReadPending(message: "Claude Code 消息区正在更新，本次读取已丢弃。")
        }
        return markers.enumerated().map { index, marker in
            .init(ordinal: marker.1, range: marker.0..<(index + 1 < markers.count ? markers[index + 1].0 : labels.count))
        }
    }
    static func codePosition(role: String, description: String, title: String) throws -> Int? {
        guard role == "AXGroup" else { return nil }
        let positions = [description, title].compactMap { position($0, format: .code)?.ordinal }
        guard Set(positions).count <= 1 else { throw ReplyReadPending(message: "Claude Code 消息标记正在更新。") }
        return positions.first
    }
    // Only flatten wrapper branches that contain ordinal anchors. Other
    // subtrees remain intact so tool-card and code-block boundaries survive.
    static func codeTranscriptPieces<Element>(_ branch: CodeTranscriptBranch<Element>) -> [CodeTranscriptPiece<Element>] {
        let nested = branch.children.flatMap(codeTranscriptPieces)
        if nested.contains(where: { $0.ordinal != nil || $0.isStreamingAssistant }) { return nested }
        return [.init(element: branch.element, ordinal: branch.ordinal, author: branch.author, isStreamingAssistant: branch.isStreamingAssistant)]
    }
    /// `continuing` is the ordinal this conversation's streaming container was
    /// validated with earlier. Long turns scroll the user anchor out of the
    /// virtualized transcript; only an unanchored, sole, final container may
    /// keep that ordinal.
    static func codeStreamingPieces<Element>(_ pieces: [CodeTranscriptPiece<Element>], continuing: Int? = nil) throws -> [CodeTranscriptPiece<Element>] {
        var result: [CodeTranscriptPiece<Element>] = []
        var previous: (ordinal: Int, author: ChatMessage.Author?)?
        for (index, piece) in pieces.enumerated() {
            if piece.isStreamingAssistant {
                // Only the explicit renderer container, after a verified user
                // anchor in this transcript, may stand in for a missing ordinal.
                let later = pieces.dropFirst(index + 1).contains(where: { $0.ordinal != nil || $0.isStreamingAssistant })
                let ordinal: Int
                if let previous, previous.author == .user, previous.ordinal < Int.max,
                   piece.ordinal == nil || piece.ordinal == previous.ordinal + 1, !later {
                    ordinal = previous.ordinal + 1
                } else if previous == nil, let continuing, piece.ordinal == nil || piece.ordinal == continuing, !later {
                    ordinal = continuing
                } else {
                    throw ReplyReadPending(message: "Claude Code 流式回复边界尚未完整。")
                }
                result.append(.init(element: piece.element, ordinal: ordinal,
                                    author: .assistant, isStreamingAssistant: true))
            } else {
                result.append(piece)
                if let ordinal = piece.ordinal { previous = (ordinal, piece.author) }
            }
        }
        return result
    }
    static func codeHeadingAuthor(role: String, label: String) -> ChatMessage.Author? {
        guard role == "AXHeading" else { return nil }
        if label.hasPrefix("You said:") { return .user }
        if label.hasPrefix("Claude responded:") { return .assistant }
        return nil
    }
    private static func codeAuthor(_ root: ReplyNode, ordinal: Int) -> ChatMessage.Author? {
        let anchor = root.children.first { position($0.label, format: .code)?.ordinal == ordinal } ?? root
        if let (_, author) = headingParent(anchor) { return author }
        // Set only by the Code transcript collector after boundary validation.
        if root.isStreamingAssistant, let first = root.children.first,
           first.isStreamingAssistant || first.label == "Currently streaming message" { return .assistant }
        return nil
    }
    private static func author(_ node: ReplyNode) -> ChatMessage.Author? {
        guard node.role == "AXHeading" else { return nil }
        // Some native AX headings expose their name only as a text child.
        // Keep the heading and authorship markers mandatory.
        let names = [node.label, node.text] + node.children.filter { $0.role == "AXStaticText" }.map { $0.text.isEmpty ? $0.label : $0.text }
        for name in names {
            if name.hasPrefix("Claude responded:") { return .assistant }
            if name.hasPrefix("You said:") { return .user }
        }
        return nil
    }
    private static func headingParent(_ node: ReplyNode) -> (ReplyNode, ChatMessage.Author)? {
        for child in node.children { if let found = author(child) { return (node, found) } }
        for child in node.children { if let found = headingParent(child) { return found } }
        return nil
    }
    private static func hasControls(_ node: ReplyNode) -> Bool {
        // The desktop's author-marked answer has a Code group containing its
        // actual text alongside Open in Claude Code / Copy controls.
        if node.role == "AXGroup", node.label == "Code" { return false }
        if node.role == "AXButton" && ["Copy", "Copy code", "复制", "复制代码"].contains(node.label) { return false }
        return ["AXButton", "AXPopUpButton", "AXCheckBox", "AXToolbar", "AXTextArea", "AXTextField"].contains(node.role) || node.children.contains(where: hasControls)
    }
    private static func text(_ node: ReplyNode) -> String {
        if node.role == "AXToolbar" || author(node) != nil || ["AXButton", "AXPopUpButton", "AXCheckBox"].contains(node.role) { return "" }
        if node.role == "AXStaticText" { return node.text.isEmpty ? node.label : node.text }
        if node.role == "AXListMarker" {
            let value = node.text.isEmpty ? node.label : node.text
            return value.isEmpty || value.last?.isWhitespace == true ? value : value + " "
        }
        if node.role == "AXLink" { return node.children.isEmpty ? node.label : node.children.map(text).joined() }
        if let table = tableText(node) { return table }
        return joined(node.children.map { child in
            BodyText(value: text(child), joinsPrevious: child.role == "AXLink",
                     joinsNext: ["AXLink", "AXListMarker"].contains(child.role),
                     block: !["AXStaticText", "AXLink", "AXListMarker"].contains(child.role))
        })
    }
    private static func tableText(_ node: ReplyNode) -> String? {
        guard node.role == "AXTable" else { return nil }
        let rows = node.children.filter { $0.role == "AXRow" }.map { row in
            row.children.map { text($0) }
        }
        guard let headers = rows.first, !headers.isEmpty, rows.allSatisfy({ $0.count == headers.count }) else { return nil }
        return MarkdownTable.source(headers: headers, rows: Array(rows.dropFirst()))
    }
    private enum CodeBodyPart { case text(BodyText), tool }
    /// Claude app interface prompts observed inside a reply's AX subtree.
    static let appPrompts: Set<String> = ["How is Claude doing this session?", "How's Claude doing this session?"]
    private static func codeBody(_ root: ReplyNode) -> String {
        joined(codeBodyParts(root).compactMap { part -> BodyText? in
            if case .text(let value) = part { return value }; return nil
        })
    }
    private static func codeBodyParts(_ root: ReplyNode) -> [CodeBodyPart] {
        func fileName(_ value: String) -> Bool {
            !value.contains(where: \.isWhitespace) &&
                ["md", "txt", "pdf", "py", "sh", "swift", "js", "ts", "json", "html", "css", "csv", "tsv"].contains((value as NSString).pathExtension.lowercased())
        }
        func inlineReference(_ value: String) -> Bool {
            fileName(value) || value.range(of: #"^(?:~/|/)?[\p{L}\p{N}_.-]+(?:/[\p{L}\p{N}_.-]+)*/$"#, options: .regularExpression) != nil
        }
        func fileReference(_ node: ReplyNode) -> Bool {
            node.role == "AXButton" && fileName(node.label)
        }
        func activityButton(_ node: ReplyNode) -> Bool {
            node.role == "AXButton" && !fileReference(node) && !["Copy", "Copy code", "Copy to clipboard", "Fork from here", "Read aloud", "Retry", "Good response", "Bad response", "复制", "复制代码"].contains(node.label) && !node.label.hasPrefix("Show message actions")
        }
        func toolCard(_ node: ReplyNode) -> Bool {
            node.label != "Code" && node.role != "AXToolbar" && headingParent(node) == nil &&
                (node.children.contains(where: activityButton) || (node.role == "AXList" && node.children.contains { $0.children.contains(where: activityButton) }))
        }
        func activityText(_ node: ReplyNode) -> [String] {
            (["AXStaticText", "AXButton"].contains(node.role) ? [node.text.isEmpty ? node.label : node.text] : []) + node.children.flatMap(activityText)
        }
        var excluded: Set<String> = []
        // AX may insert spaces around a comma in a tool summary's text while
        // its button exposes the same summary without those spaces.
        func activityKey(_ value: String) -> String { value.filter { !$0.isWhitespace } }
        func collectActivity(_ node: ReplyNode) {
            if toolCard(node) || activityButton(node) {
                excluded.formUnion(activityText(node).filter { !$0.isEmpty }.map(activityKey)); return
            }
            for child in node.children { collectActivity(child) }
        }
        collectActivity(root)
        // A container can contain inline links/files as separate AX nodes.
        // Assemble them inside that container before joining paragraph siblings.
        // Tool boundaries survive and continue to close individual Code stages.
        func coalesce(_ parts: [CodeBodyPart], inlineWhitespace: Bool = true, preserveFileReference: Bool = true) -> [CodeBodyPart] {
            var result: [CodeBodyPart] = []; var fragments: [BodyText] = []
            func flush() {
                // AX may wrap each inline span separately. Preserve the file
                // marker through those wrappers, then join only a filename
                // explicitly surrounded by sentence spacing/punctuation.
                // Never remove literal newlines inside a text node.
                var index = 1
                while index + 1 < fragments.count {
                    let before = fragments[index - 1], file = fragments[index], after = fragments[index + 1]
                    if file.staticFileName, [" ", "\t"].contains(before.value.last),
                       [" ", "\t", ".", ",", ";", ":", "!", "?", ")", "]"].contains(after.value.first) {
                        let combined = BodyText(value: before.value + file.value + after.value,
                                                joinsPrevious: before.joinsPrevious, joinsNext: after.joinsNext,
                                                block: before.block || file.block || after.block)
                        fragments.replaceSubrange((index - 1)...(index + 1), with: [combined])
                        index = max(1, index - 1)
                    } else { index += 1 }
                }
                if !inlineWhitespace {
                    // Bold, inline code and similar runs of one sentence arrive
                    // as flattened siblings, and AX sometimes drops the space at
                    // their seam. Adjacent runs continue the sentence unless the
                    // earlier one ends it; a colon or semicolon ends it only
                    // before a capitalised run. Dropped word spacing is restored.
                    for index in fragments.indices where index > 0 {
                        let before = fragments[index - 1], current = fragments[index]
                        guard !before.block, !current.block, before.value.last?.isNewline != true,
                              current.value.first?.isNewline != true,
                              let last = before.value.last(where: { !$0.isWhitespace }),
                              let first = current.value.first(where: { !$0.isWhitespace }) else { continue }
                        if ".!?。！？".contains(last) { continue }
                        if ":;：；".contains(last), first.isUppercase { continue }
                        fragments[index - 1].joinsNext = true; fragments[index].joinsPrevious = true
                        let seam = [" ", "\t"].contains(before.value.last) || [" ", "\t"].contains(current.value.first)
                        let closing = ",.;:!?)]\u{201D}\u{2019}".contains(first)
                        if !seam, !closing, (last.isLetter || last.isNumber || ":;,".contains(last)), (first.isLetter || first.isNumber),
                           !(last.isCJK && first.isCJK), !first.isCJK || !":;,".contains(last) {
                            fragments[index] = BodyText(value: " " + current.value, joinsPrevious: true, joinsNext: current.joinsNext,
                                                        block: current.block, staticFileName: current.staticFileName)
                        }
                    }
                    // Code's ordinal wrapper is flattened by AX. A static
                    // filename with an explicit preceding inline space still
                    // belongs to that sentence, including following punctuation.
                    // Other flat paragraphs retain their existing boundaries.
                    for index in fragments.indices where index > 0 && fragments[index].staticFileName {
                        let before = fragments[index - 1]
                        guard !before.block, [" ", "\t"].contains(before.value.last) else { continue }
                        fragments[index].joinsPrevious = true
                        if index + 1 < fragments.count {
                            let after = fragments[index + 1]
                            fragments[index].joinsNext = !after.block &&
                                ([" ", "\t"].contains(after.value.first) ||
                                 [".", ",", ";", ":", "!", "?", ")", "]"].contains(after.value.first))
                        }
                    }
                }
                let singleFile = preserveFileReference && fragments.count == 1 && fragments[0].staticFileName
                let value = joined(fragments, inlineWhitespace: inlineWhitespace); fragments = []
                if !value.isEmpty { result.append(.text(.init(value: value, block: true, staticFileName: singleFile))) }
            }
            for part in parts {
                switch part {
                case .text(let value): fragments.append(value)
                case .tool: flush(); result.append(.tool)
                }
            }
            flush(); return result
        }
        func body(_ node: ReplyNode) -> [CodeBodyPart] {
            if author(node) != nil { return [] }
            if toolCard(node) || activityButton(node) { return [.tool] }
            if fileReference(node) { return [.text(.init(value: node.label, joinsPrevious: true, joinsNext: true))] }
            if ["AXToolbar", "AXButton", "AXPopUpButton", "AXCheckBox", "AXTextArea", "AXTextField"].contains(node.role) { return [] }
            if ["AXStaticText", "AXListMarker"].contains(node.role) {
                let value = node.text.isEmpty ? node.label : node.text
                let marker = node.role == "AXListMarker"
                let content = marker && value.last?.isWhitespace != true ? value + " " : value
                return value.isEmpty || excluded.contains(activityKey(value)) || appPrompts.contains(value.trimmingCharacters(in: .whitespacesAndNewlines)) ? [] : [.text(.init(value: content, joinsNext: marker, staticFileName: !marker && inlineReference(value)))]
            }
            if node.role == "AXLink" {
                let value = text(node)
                return value.isEmpty ? [] : [.text(.init(value: value, joinsPrevious: true, joinsNext: true))]
            }
            if let table = tableText(node) { return [.text(.init(value: table, block: true))] }
            if node.role == "AXGroup", node.isStreamingAssistant || node.label == "Currently streaming message" {
                return coalesce(node.children.enumerated().flatMap { index, child in
                    // This is the renderer's trailing activity group, not a
                    // keyword filter over the assistant's actual paragraphs.
                    let values = child.children.map { $0.text.isEmpty ? $0.label : $0.text }
                    let footer = index > 0 && child.role == "AXGroup" && !values.isEmpty &&
                        child.children.allSatisfy { $0.role == "AXStaticText" } && values.allSatisfy {
                            ["running", "Working…", "Thinking…", "Working...", "Thinking..."].contains($0) ||
                            $0.range(of: "^[0-9,.]+ tokens$", options: .regularExpression) != nil
                        }
                    // A tool still in progress renders its label beside a bare
                    // "running" status before its card controls appear.
                    let running = child.role == "AXGroup" && !values.isEmpty &&
                        child.children.allSatisfy { $0.role == "AXStaticText" } &&
                        values.contains { ["running", "Running", "running…", "Running…"].contains($0.trimmingCharacters(in: .whitespaces)) }
                    return footer ? [] : running ? [.tool] : body(child)
                })
            }
            return coalesce(node.children.flatMap(body), inlineWhitespace: position(node.label, format: .code) == nil,
                            preserveFileReference: node.label != "Code")
        }
        return body(root)
    }
    static func messages(_ root: ReplyNode, format: ClaudeTranscriptFormat = .chat) -> [ChatMessage] {
        var result: [ChatMessage] = []
        func visit(_ node: ReplyNode) {
            if let n = position(node.label, format: format)?.ordinal {
                if format == .code {
                    guard let author = codeAuthor(node, ordinal: n) else { return }
                    let value = codeBody(node)
                    if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        result.append(.init(ordinal: n, author: author, text: value))
                    }
                    return
                }
                guard let (parent, author) = headingParent(node) else { return }
                // Claude's answer body is a sibling group of its authorship heading.
                // Ignore sibling tool activity, duplicated status text, and message actions.
                let controlGroups = parent.children.filter { hasControls($0) }
                func allText(_ node: ReplyNode) -> [String] {
                    (["AXStaticText", "AXButton"].contains(node.role) ? [node.text.isEmpty ? node.label : node.text] : []) + node.children.flatMap(allText)
                }
                let statusText = Set(controlGroups.flatMap(allText) + controlGroups.filter { $0.role == "AXButton" }.map(\.label))
                let bodyPieces = parent.children.enumerated().compactMap { index, child -> (Int, String)? in
                    guard self.author(child) == nil, !hasControls(child) else { return nil }
                    var value = text(child)
                    // Desktop flattens a tool card into status text, a button,
                    // then a text node with the same status prefixed to the answer.
                    if index > 0 {
                        let previous = parent.children[index - 1]
                        if ["AXButton", "AXGroup"].contains(previous.role), hasControls(previous) {
                            for prefix in Set(allText(previous)).filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) where value.hasPrefix(prefix) {
                                let remainder = value.dropFirst(prefix.count)
                                if remainder.first?.isWhitespace == true {
                                    value = String(remainder.drop(while: \.isWhitespace)); break
                                }
                            }
                        }
                    }
                    guard !value.isEmpty, !statusText.contains(value) else { return nil }
                    return (index, value)
                }
                // The author heading previews the formal answer. New desktop
                // builds expose thinking summaries as flat siblings before it.
                let heading = parent.children.first { self.author($0) == author }
                let names = heading.map { [$0.label, $0.text] + $0.children.filter { $0.role == "AXStaticText" }.map { $0.text.isEmpty ? $0.label : $0.text } } ?? []
                let marker = author == .assistant ? "Claude responded:" : "You said:"
                let preview = normalize(String((names.first { $0.hasPrefix(marker) } ?? marker).dropFirst(marker.count)))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "…"))
                let formalStart = preview.isEmpty ? nil : bodyPieces.first { _, value in
                    let candidate = normalize(value)
                    return !candidate.isEmpty && (candidate.hasPrefix(preview) || preview.hasPrefix(candidate))
                }?.0
                let flatOnly = !bodyPieces.isEmpty && bodyPieces.allSatisfy { parent.children[$0.0].role == "AXStaticText" }
                if author == .assistant, flatOnly, formalStart == nil { return }
                let body = bodyPieces.filter { formalStart == nil || $0.0 >= formalStart! }.map(\.1).joined(separator: "\n\n")
                if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(.init(ordinal: n, author: author, text: body))
                }
                return
            }
            for child in node.children { visit(child) }
        }
        visit(root)
        return result.sorted { $0.ordinal < $1.ordinal }
    }
    static func normalize(_ value: String) -> String { value.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    static func recentMessages(_ nodes: [ReplyNode], format: ClaudeTranscriptFormat = .chat) throws -> [ChatMessage] {
        guard !nodes.isEmpty else { return [] }
        let positions = try nodes.map { node -> ClaudeMessagePosition in
            guard let position = position(node.label, format: format) else {
                throw ReplyReadPending(message: "Claude 消息序号尚未完整。")
            }
            return position
        }
        guard let last = positions.last, (format == .code || last.ordinal == last.total),
              positions.allSatisfy({ $0.total == last.total }),
              zip(positions, positions.dropFirst()).allSatisfy({ $1.ordinal > $0.ordinal }) else {
            throw ReplyReadPending(message: "Claude 消息区正在更新，本次读取已丢弃。")
        }
        var tail: [ChatMessage] = []
        var expected = last.ordinal
        for (node, position) in zip(nodes, positions).reversed() {
            guard position.ordinal == expected else { break }
            let decoded = messages(node, format: format)
            // Historical attachment-only cards have no author/body marker.
            // Stop at that boundary; never guess its author or skip a gap in
            // the current turn. The latest message must itself be complete.
            guard decoded.count == 1 else { break }
            tail.append(decoded[0])
            expected -= 1
        }
        guard !tail.isEmpty else {
            throw ReplyReadPending(message: "最新消息的正文或作者标记尚未完整，未使用部分内容。")
        }
        return tail.reversed()
    }
    static func chunks(_ text: String, limit: Int = 5_000) -> [String] {
        var chunks: [String] = []; var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[start..<end])); start = end
        }
        return chunks
    }
}

private struct MessageStamp: Equatable {
    let ordinal: Int
    let author: ChatMessage.Author
    let digest: SHA256.Digest
    init(_ message: ChatMessage) {
        ordinal = message.ordinal; author = message.author
        digest = SHA256.hash(data: Data(message.text.utf8))
    }
}

struct ReplyTracker {
    private let baseline: [MessageStamp]
    private let baselineOrdinal: Int
    private let outbound: String
    private var conversation: String
    private var anchor: Int?
    private var anchorStamp: MessageStamp?
    private var changedAt: TimeInterval = 0
    private var emitted: ReplyCandidate?
    private(set) var latest: ReplyCandidate?
    var bound: Bool { anchor != nil }
    init(baseline: [ChatMessage], outbound: String, conversation: String) {
        self.baseline = baseline.suffix(4).map(MessageStamp.init)
        baselineOrdinal = baseline.last?.ordinal ?? 0
        self.outbound = ClaudeDecoder.normalize(outbound); self.conversation = conversation
    }
    mutating func observe(conversation current: String, messages: [ChatMessage], now: TimeInterval) throws -> ReplyCandidate? {
        if current != conversation {
            let initial = conversation.hasSuffix("/new") || conversation.hasSuffix("claude.ai/")
            guard initial, anchor == nil, baseline.isEmpty, current.contains("claude.ai/chat/") else {
                throw BridgeError.message("检测到切换会话，已停止自动读取。请在新会话重新唤出A畜伴侣。")
            }
            conversation = current
        }
        let ordinals = messages.map(\.ordinal)
        guard ordinals == ordinals.sorted(), Set(ordinals).count == ordinals.count,
              (ordinals.last ?? 0) >= baselineOrdinal else {
            throw BridgeError.message("对话结构或历史发生变化，已停止自动读取。")
        }
        let stamps = messages.map(MessageStamp.init)
        let overlap = baseline.filter { old in stamps.contains(where: { $0.ordinal == old.ordinal }) }
        guard overlap.allSatisfy({ stamps.contains($0) }) else { throw BridgeError.message("已读取的消息发生变化，请重新连接会话。") }
        if let anchorStamp {
            guard stamps.contains(anchorStamp) else { throw BridgeError.message("无法核对原发送消息，已停止读取，请重新连接。") }
        } else if !baseline.isEmpty && overlap.isEmpty {
            throw BridgeError.message("旧消息已从界面隐藏，无法证明对话连续，请重新连接后读取。")
        }
        if anchor == nil {
            if let first = messages.first(where: { $0.ordinal > baselineOrdinal }) {
                guard first.ordinal == baselineOrdinal + 1, first.author == .user,
                      ClaudeDecoder.normalize(first.text) == outbound else { throw BridgeError.message("检测到与译文不同的新消息或缺失消息，已停止读取。请重新唤出A畜伴侣。") }
                anchor = first.ordinal
                anchorStamp = MessageStamp(first)
            }
        }
        if let anchor {
            guard !messages.contains(where: { $0.ordinal > anchor && $0.author == .user }) else { throw BridgeError.message("检测到另一条用户消息，请重新连接后读取对应回复。") }
            let later = messages.filter { $0.ordinal >= anchor }
            guard zip(later, later.dropFirst()).allSatisfy({ $1.ordinal == $0.ordinal + 1 }) else { throw BridgeError.message("当前消息区不完整，请重新读取。") }
        }
        guard let anchor, let message = messages.last(where: { $0.author == .assistant && $0.ordinal > anchor }) else { return nil }
        let candidate = ReplyCandidate(ordinal: message.ordinal, text: message.text)
        if candidate != latest { latest = candidate; changedAt = now; return nil }
        guard now - changedAt >= 3, candidate != emitted else { return nil }
        emitted = candidate
        return candidate
    }
}

private extension Character {
    var isCJK: Bool {
        unicodeScalars.first.map { (0x3040...0x30FF).contains($0.value) || (0x3400...0x9FFF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) } ?? false
    }
}
