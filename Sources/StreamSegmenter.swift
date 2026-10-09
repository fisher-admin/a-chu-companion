import Foundation

struct StreamSegment: Equatable, Sendable {
    enum Kind: Sendable { case prose, code, whitespace }
    let index: Int
    let text: String
    let kind: Kind
    var translatable: Bool { kind == .prose }
}

struct SegmenterUpdate: Equatable, Sendable {
    /// Segments at or after this index no longer match the source and must be discarded.
    var invalidatedFrom: Int?
    var segments: [StreamSegment] = []
}

enum TerminalText {
    /// Removes ANSI/VT escape sequences and control characters other than tab and newline.
    /// `pending` is a trailing incomplete sequence to prepend to the next chunk.
    static func sanitize(_ raw: String) -> (text: String, pending: String) {
        let s = Array(raw.unicodeScalars)
        var out = String.UnicodeScalarView()
        func pending(_ from: Int) -> (String, String) { (String(out), String(String.UnicodeScalarView(s[from...]))) }
        var i = 0
        while i < s.count {
            let v = s[i].value
            if v == 0x1B || v == 0x9B {
                var j = v == 0x9B ? i + 1 : i + 2
                guard v == 0x9B || i + 1 < s.count else { return pending(i) }
                let kind = v == 0x9B ? 0x5B : s[i + 1].value
                switch kind {
                case 0x5B: // CSI: parameters, then one final byte 0x40...0x7E
                    while j < s.count, !(0x40...0x7E).contains(s[j].value) { j += 1 }
                    guard j < s.count else { return pending(i) }
                    i = j + 1
                case 0x5D, 0x50, 0x58, 0x5E, 0x5F: // OSC, DCS, SOS, PM, APC: until BEL or ESC \
                    var end: Int?
                    while j < s.count {
                        if s[j].value == 0x07 && kind == 0x5D { end = j + 1; break }
                        if s[j].value == 0x1B {
                            guard j + 1 < s.count else { break }
                            if s[j + 1].value == 0x5C { end = j + 2; break }
                        }
                        j += 1
                    }
                    guard let end else { return pending(i) }
                    i = end
                case 0x28, 0x29, 0x2A, 0x2B, 0x23, 0x25: // charset designation: ESC ( B
                    guard i + 2 < s.count else { return pending(i) }
                    i += 3
                default: i += 2
                }
                continue
            }
            if v == 0x0D {
                if i + 1 == s.count { return pending(i) }
                i += 1; continue // CRLF becomes LF; a lone CR is dropped
            }
            if (v < 0x20 && v != 0x0A && v != 0x09) || v == 0x7F || (0x80...0x9F).contains(v) { i += 1; continue }
            out.append(s[i]); i += 1
        }
        return (String(out), "")
    }
}

/// Cuts a growing reply into translation units at safe boundaries: blank lines, sentence
/// ends (`。！？` immediately, `.!?` once whitespace follows) and Markdown block starts.
/// Fenced code blocks are emitted whole as pass-through segments. A cut is only made once
/// the text after it proves the boundary, so the result never depends on how the stream
/// was chunked, and joining every segment reproduces the sanitized source exactly.
struct StreamSegmenter {
    var minimumLength = 20
    var maximumLength = 800
    private(set) var segments: [StreamSegment] = []
    private(set) var finished = false
    private var ends: [Int] = []
    private var committed = ""
    private var buffer = ""
    private var carry = ""

    var text: String { committed + buffer }

    init(minimumLength: Int = 20, maximumLength: Int = 800) {
        precondition(minimumLength >= 1 && maximumLength > minimumLength)
        self.minimumLength = minimumLength; self.maximumLength = maximumLength
    }

    mutating func append(_ delta: String) -> [StreamSegment] {
        guard !finished else { return [] }
        let (clean, pending) = TerminalText.sanitize(carry + delta)
        carry = pending; buffer += clean
        return drain(final: false)
    }

    /// Accepts the full reply observed so far. A shorter snapshot is treated as a transient
    /// read and ignored; a changed earlier part invalidates the segments it touches.
    mutating func update(snapshot raw: String) -> SegmenterUpdate {
        guard !finished else { return SegmenterUpdate() }
        return replace(with: TerminalText.sanitize(raw).text, final: false)
    }

    mutating func finish(snapshot raw: String? = nil) -> SegmenterUpdate {
        guard !finished else { return SegmenterUpdate() }
        var update = SegmenterUpdate()
        if let raw { update = replace(with: TerminalText.sanitize(raw).text, final: true) }
        else { buffer += TerminalText.sanitize(carry).text; carry = "" }
        finished = true
        update.segments += drain(final: true)
        return update
    }

    private mutating func replace(with clean: String, final: Bool) -> SegmenterUpdate {
        var update = SegmenterUpdate()
        if clean.hasPrefix(committed) {
            let tail = String(clean.dropFirst(committed.count))
            if !final, tail.count < buffer.count, buffer.hasPrefix(tail) { return update }
            buffer = tail
        } else {
            if !final, committed.hasPrefix(clean) { return update }
            let shared = zip(committed, clean).prefix(while: { $0 == $1 }).count
            let keep = ends.firstIndex(where: { $0 > shared }) ?? ends.count
            let kept = keep == 0 ? 0 : ends[keep - 1]
            segments.removeSubrange(keep...); ends.removeSubrange(keep...)
            committed = String(committed.prefix(kept))
            buffer = String(clean.dropFirst(kept))
            update.invalidatedFrom = keep
        }
        update.segments = drain(final: false)
        return update
    }

    private mutating func drain(final: Bool) -> [StreamSegment] {
        let chars = Array(buffer)
        var start = 0
        var produced: [StreamSegment] = []
        while let (end, kind) = nextCut(chars, start: start, final: final) {
            let piece = String(chars[start..<end])
            let segment = StreamSegment(index: segments.count, text: piece, kind: kind)
            segments.append(segment); produced.append(segment)
            ends.append((ends.last ?? 0) + (end - start))
            committed += piece
            start = end
        }
        buffer = String(chars[start...])
        return produced
    }

    // MARK: Boundary scanning

    private static let terminators: Set<Character> = ["。", "！", "？", "…"]
    private static let closers: Set<Character> = ["\"", "'", "”", "’", "」", "』", "）", ")", "]", "*", "_", "》"]
    private static let softBreaks: Set<Character> = ["，", ",", "、", "；", ";", "：", ":"]
    private static let abbreviations: Set<String> = [
        "e.g", "i.e", "etc", "vs", "mr", "mrs", "ms", "dr", "st", "jr", "sr", "no", "fig", "approx", "cf", "u.s", "a.m", "p.m",
        "z.b", "d.h", "bzw", "ca", "nr", "vgl", "evtl", "ggf", "usw", "inkl", "bzgl"
    ]

    private enum Fence { case none, undecided, open(Character, Int) }

    private func nextCut(_ c: [Character], start: Int, final: Bool) -> (Int, StreamSegment.Kind)? {
        let n = c.count
        guard start < n else { return nil }
        func kind(_ end: Int) -> StreamSegment.Kind { c[start..<end].allSatisfy(\.isWhitespace) ? .whitespace : .prose }
        var inline: Int?
        var tableLine = false
        var i = start
        while i < n {
            if i - start >= maximumLength { let cut = softCut(c, start: start); return (cut, kind(cut)) }
            if lineStarts(c, at: i) {
                switch fence(c, at: i, final: final) {
                case .undecided: return nil
                case let .open(marker, length):
                    if i > start { return (i, kind(i)) }
                    guard let end = codeBlockEnd(c, from: i, marker: marker, length: length, final: final) else { return nil }
                    return (end, .code)
                case .none: break
                }
                var k = i
                while k < n, c[k] == " " || c[k] == "\t" { k += 1 }
                tableLine = k < n && c[k] == "|"
                inline = nil
            }
            let ch = c[i]
            if ch == "`" {
                var r = 0
                while i + r < n, c[i + r] == "`" { r += 1 }
                if i + r == n && !final { return nil }
                if inline == nil { inline = r } else if inline == r { inline = nil }
                i += r; continue
            }
            if ch.isWhitespace {
                var j = i
                while j < n, c[j].isWhitespace { j += 1 }
                if j == n && !final { return nil }
                let newlines = c[i..<j].filter { $0 == "\n" }.count
                if newlines >= 2 { return (j, kind(j)) }
                if inline == nil, !tableLine, reachesMinimum(c, start, j), j < n {
                    if newlines == 1 {
                        guard let block = startsBlock(c, at: j, final: final) else { return nil }
                        if block { return (j, .prose) }
                    }
                    if endsSentence(c, before: i, start: start) { return (j, .prose) }
                }
                i = j; continue
            }
            if Self.terminators.contains(ch) {
                var k = i + 1
                while k < n, Self.closers.contains(c[k]) || Self.terminators.contains(c[k]) { k += 1 }
                if k == n && !final { return nil }
                // A following whitespace run is handled (and included) by the branch above.
                if k < n, !c[k].isWhitespace, inline == nil, !tableLine, reachesMinimum(c, start, k) { return (k, .prose) }
                i = k; continue
            }
            i += 1
        }
        return final ? (n, kind(n)) : nil
    }

    /// CJK characters carry roughly twice the content of a Latin letter.
    private func reachesMinimum(_ c: [Character], _ start: Int, _ end: Int) -> Bool {
        var weight = 0
        for ch in c[start..<end] {
            weight += ch.unicodeScalars.first.map { $0.value >= 0x2E80 } == true ? 2 : 1
            if weight >= minimumLength { return true }
        }
        return false
    }

    /// Cut an overlong run at its last soft break, else at the length limit.
    private func softCut(_ c: [Character], start: Int) -> Int {
        let limit = start + maximumLength
        for p in stride(from: limit - 1, through: start + minimumLength, by: -1)
        where c[p].isWhitespace || Self.softBreaks.contains(c[p]) || Self.terminators.contains(c[p]) {
            return p + 1
        }
        return limit
    }

    private func fence(_ c: [Character], at i: Int, final: Bool) -> Fence {
        var k = i
        while k < c.count, k - i < 4, c[k] == " " || c[k] == "\t" { k += 1 }
        guard k < c.count else { return final ? .none : .undecided }
        let marker = c[k]
        guard marker == "`" || marker == "~" else { return .none }
        var r = 0
        while k + r < c.count, c[k + r] == marker { r += 1 }
        if r >= 3 { return .open(marker, r) }
        return k + r == c.count && !final ? .undecided : .none
    }

    private func codeBlockEnd(_ c: [Character], from i: Int, marker: Character, length: Int, final: Bool) -> Int? {
        let n = c.count
        guard var line = c[i...].firstIndex(of: "\n").map({ $0 + 1 }) else { return final ? n : nil }
        while line < n {
            var k = line
            while k < n, c[k] == " " || c[k] == "\t" { k += 1 }
            var r = 0
            while k + r < n, c[k + r] == marker { r += 1 }
            let lineEnd = c[line...].firstIndex(of: "\n") ?? n
            if r >= length, c[(k + r)..<lineEnd].allSatisfy({ $0 == " " || $0 == "\t" }) {
                if lineEnd == n && !final { return nil }
                var j = lineEnd
                while j < n, c[j].isWhitespace { j += 1 }
                return j == n && !final ? nil : j
            }
            guard lineEnd < n else { break }
            line = lineEnd + 1
        }
        return final ? n : nil
    }

    /// nil when more text is needed to decide.
    private func startsBlock(_ c: [Character], at j: Int, final: Bool) -> Bool? {
        let n = c.count
        var k = j
        while k < n, c[k] == " " || c[k] == "\t" { k += 1 }
        guard k < n else { return final ? false : nil }
        let ch = c[k]
        if ["#", ">", "|"].contains(ch) { return true }
        if ["-", "*", "+"].contains(ch) {
            guard k + 1 < n else { return final ? false : nil }
            return c[k + 1] == " "
        }
        if ch.isASCII, ch.isNumber {
            var d = k
            while d < n, c[d].isASCII, c[d].isNumber { d += 1 }
            guard d + 1 < n else { return final ? false : nil }
            return (c[d] == "." || c[d] == ")") && c[d + 1] == " "
        }
        return false
    }

    private func endsSentence(_ c: [Character], before i: Int, start: Int) -> Bool {
        var k = i - 1
        while k >= start, Self.closers.contains(c[k]) { k -= 1 }
        guard k >= start else { return false }
        if Self.terminators.contains(c[k]) || c[k] == "!" || c[k] == "?" { return true }
        guard c[k] == "." else { return false }
        if k > start, c[k - 1] == "." { return true } // ellipsis
        var t = k
        while t > start, !c[t - 1].isWhitespace { t -= 1 }
        let token = String(c[t..<k]).trimmingCharacters(in: CharacterSet(charactersIn: "(\"'“‘[")).lowercased()
        if token.isEmpty { return true }
        if Self.abbreviations.contains(token) { return false }
        if token.count == 1, token.first!.isLetter { return false } // initials such as "J."
        if token.allSatisfy(\.isNumber), lineStarts(c, at: t) { return false } // "1." list marker
        return true
    }

    private func lineStarts(_ c: [Character], at i: Int) -> Bool {
        i == 0 ? committed.isEmpty || committed.last == "\n" : c[i - 1] == "\n"
    }
}
