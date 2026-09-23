import Foundation

/// A link reference definition (`[label]: destination "title"`).
struct MarkdownLinkDefinition: Equatable, Sendable {
    var destination: String
    var title: String?
}

/// Scanners shared by the block parser (reference definitions) and the inline parser
/// (links, autolinks, raw HTML). All functions take a byte array and an index and
/// return the index just past the matched construct, or `nil`.
enum MarkdownLinkScanner {
    /// `[label]` starting at `s[i] == "["`. Returns the index after `]`.
    static func linkLabel(_ s: [UInt8], at i: Int) -> Int? {
        let n = s.count
        guard i < n, s[i] == 0x5B else { return nil }
        var j = i + 1
        while j < n {
            let c = s[j]
            if c == MarkdownChar.backslash, j + 1 < n, MarkdownChar.isASCIIPunctuation(s[j + 1]) {
                j += 2
                continue
            }
            if c == 0x5B { return nil }
            if c == 0x5D { return j - i - 1 <= 999 ? j + 1 : nil }
            j += 1
            if j - i > 1001 { return nil }
        }
        return nil
    }

    /// Skips spaces/tabs, at most one line ending, then spaces/tabs again.
    static func skipSpacesAndNewline(_ s: [UInt8], at i: Int) -> Int {
        let n = s.count
        var j = i
        while j < n, MarkdownChar.isSpaceOrTab(s[j]) { j += 1 }
        if j < n, s[j] == MarkdownChar.newline {
            j += 1
            while j < n, MarkdownChar.isSpaceOrTab(s[j]) { j += 1 }
        }
        return j
    }

    /// Link destination: `<…>` or a raw destination with balanced parentheses.
    static func linkDestination(_ s: [UInt8], at i: Int) -> (destination: String, end: Int)? {
        let n = s.count
        guard i < n else { return nil }
        if s[i] == 0x3C { // '<'
            var j = i + 1
            while j < n {
                let c = s[j]
                if c == MarkdownChar.backslash, j + 1 < n, MarkdownChar.isASCIIPunctuation(s[j + 1]) {
                    j += 2
                    continue
                }
                if c == 0x3E { return (MarkdownChar.unescape(s[(i + 1)..<j]), j + 1) }
                if c == 0x3C || c == MarkdownChar.newline { return nil }
                j += 1
            }
            return nil
        }
        var j = i
        var depth = 0
        while j < n {
            let c = s[j]
            if c == MarkdownChar.backslash, j + 1 < n, MarkdownChar.isASCIIPunctuation(s[j + 1]) {
                j += 2
                continue
            }
            if c == 0x28 {
                depth += 1
                if depth > 32 { return nil }
            } else if c == 0x29 {
                if depth == 0 { break }
                depth -= 1
            } else if c <= 0x20 || c == 0x7F {
                break
            }
            j += 1
        }
        guard j > i, depth == 0 else { return nil }
        return (MarkdownChar.unescape(s[i..<j]), j)
    }

    /// Link title: `"…"`, `'…'` or `(…)`.
    static func linkTitle(_ s: [UInt8], at i: Int) -> (title: String, end: Int)? {
        let n = s.count
        guard i < n else { return nil }
        let open = s[i]
        let close: UInt8
        switch open {
        case 0x22: close = 0x22
        case 0x27: close = 0x27
        case 0x28: close = 0x29
        default: return nil
        }
        var j = i + 1
        var lastWasNewline = false
        while j < n {
            let c = s[j]
            if c == MarkdownChar.backslash, j + 1 < n, MarkdownChar.isASCIIPunctuation(s[j + 1]) {
                j += 2
                lastWasNewline = false
                continue
            }
            if c == close { return (MarkdownChar.unescape(s[(i + 1)..<j]), j + 1) }
            if open == 0x28 && c == 0x28 { return nil }
            if c == MarkdownChar.newline {
                if lastWasNewline { return nil } // blank line
                lastWasNewline = true
            } else if !MarkdownChar.isSpaceOrTab(c) {
                lastWasNewline = false
            }
            j += 1
        }
        return nil
    }

    /// Parses one link reference definition starting at `s[i] == "["`.
    static func referenceDefinition(_ s: [UInt8], at i: Int) -> (label: String, definition: MarkdownLinkDefinition, end: Int)? {
        let n = s.count
        guard let labelEnd = linkLabel(s, at: i), labelEnd < n, s[labelEnd] == 0x3A else { return nil }
        let label = MarkdownChar.normalizeLabel(s[(i + 1)..<(labelEnd - 1)])
        guard !label.isEmpty else { return nil }
        var j = skipSpacesAndNewline(s, at: labelEnd + 1)
        guard let (destination, destEnd) = linkDestination(s, at: j) else { return nil }
        if destEnd == j { return nil }
        j = destEnd
        func lineEnd(from k: Int) -> Int? {
            var m = k
            while m < n, MarkdownChar.isSpaceOrTab(s[m]) { m += 1 }
            if m == n { return m }
            if s[m] == MarkdownChar.newline { return m + 1 }
            return nil
        }
        let beforeTitle = j
        let titleStart = skipSpacesAndNewline(s, at: j)
        if titleStart != beforeTitle, let (title, titleEnd) = linkTitle(s, at: titleStart), let end = lineEnd(from: titleEnd) {
            return (label, MarkdownLinkDefinition(destination: destination, title: title), end)
        }
        guard let end = lineEnd(from: beforeTitle) else { return nil }
        return (label, MarkdownLinkDefinition(destination: destination, title: nil), end)
    }

    // MARK: Autolinks

    /// `<scheme:…>` URI autolink starting at `s[i] == "<"`; returns index after `>`.
    static func uriAutolink(_ s: [UInt8], at i: Int) -> Int? {
        let n = s.count
        var j = i + 1
        guard j < n, MarkdownChar.isLetter(s[j]) else { return nil }
        let schemeStart = j
        while j < n, MarkdownChar.isAlphanumeric(s[j]) || s[j] == 0x2B || s[j] == 0x2E || s[j] == 0x2D { j += 1 }
        let schemeLength = j - schemeStart
        guard schemeLength >= 2, schemeLength <= 32, j < n, s[j] == 0x3A else { return nil }
        j += 1
        while j < n {
            let c = s[j]
            if c == 0x3E { return j + 1 }
            if c <= 0x20 || c == 0x3C || c == 0x7F { return nil }
            j += 1
        }
        return nil
    }

    /// `<user@example.com>` email autolink; returns index after `>`.
    static func emailAutolink(_ s: [UInt8], at i: Int) -> Int? {
        let n = s.count
        var j = i + 1
        let localStart = j
        while j < n {
            let c = s[j]
            if MarkdownChar.isAlphanumeric(c) || ".!#$%&'*+/=?^_`{|}~-".utf8.contains(c) { j += 1 } else { break }
        }
        guard j > localStart, j < n, s[j] == 0x40 else { return nil }
        j += 1
        var labels = 0
        while true {
            let labelStart = j
            while j < n, MarkdownChar.isAlphanumeric(s[j]) || s[j] == 0x2D { j += 1 }
            let length = j - labelStart
            guard length >= 1, length <= 63, s[labelStart] != 0x2D, s[j - 1] != 0x2D else { return nil }
            labels += 1
            guard j < n else { return nil }
            if s[j] == 0x2E { j += 1; continue }
            if s[j] == 0x3E { return j + 1 }
            return nil
        }
    }

    // MARK: Raw HTML

    /// Any CommonMark raw HTML construct starting at `s[i] == "<"`; returns index after it.
    static func htmlTag(_ s: [UInt8], at i: Int) -> Int? {
        let n = s.count
        guard i + 1 < n else { return nil }
        let c = s[i + 1]
        if MarkdownChar.isLetter(c) { return openTag(s, at: i) }
        if c == 0x2F { return closingTag(s, at: i) }
        if c == 0x3F { return find(s, from: i + 2, "?>") }
        if c == 0x21 {
            if MarkdownChar.matches(s, at: i, lowercase: "<!--") {
                if MarkdownChar.matches(s, at: i, lowercase: "<!-->") { return i + 5 }
                if MarkdownChar.matches(s, at: i, lowercase: "<!--->") { return i + 6 }
                return find(s, from: i + 4, "-->")
            }
            if i + 9 <= n && MarkdownChar.string(s[i..<(i + 9)]) == "<![CDATA[" {
                return find(s, from: i + 9, "]]>")
            }
            if i + 2 < n, MarkdownChar.isLetter(s[i + 2]) {
                var j = i + 3
                while j < n, s[j] != 0x3E { j += 1 }
                return j < n ? j + 1 : nil
            }
        }
        return nil
    }

    static func tagNameEnd(_ s: [UInt8], at i: Int) -> Int? {
        let n = s.count
        guard i < n, MarkdownChar.isLetter(s[i]) else { return nil }
        var j = i + 1
        while j < n, MarkdownChar.isAlphanumeric(s[j]) || s[j] == 0x2D { j += 1 }
        return j
    }

    static func openTag(_ s: [UInt8], at i: Int) -> Int? {
        let n = s.count
        guard var j = tagNameEnd(s, at: i + 1) else { return nil }
        while true {
            let wsStart = j
            while j < n, MarkdownChar.isWhitespace(s[j]) { j += 1 }
            guard j < n else { return nil }
            if s[j] == 0x3E { return j + 1 }
            if s[j] == 0x2F { return j + 1 < n && s[j + 1] == 0x3E ? j + 2 : nil }
            // attribute requires preceding whitespace
            guard j > wsStart else { return nil }
            let a = s[j]
            guard MarkdownChar.isLetter(a) || a == 0x5F || a == 0x3A else { return nil }
            j += 1
            while j < n, MarkdownChar.isAlphanumeric(s[j]) || s[j] == 0x5F || s[j] == 0x2E || s[j] == 0x3A || s[j] == 0x2D { j += 1 }
            // optional value
            var k = j
            while k < n, MarkdownChar.isWhitespace(s[k]) { k += 1 }
            if k < n, s[k] == 0x3D {
                k += 1
                while k < n, MarkdownChar.isWhitespace(s[k]) { k += 1 }
                guard k < n else { return nil }
                let q = s[k]
                if q == 0x22 || q == 0x27 {
                    k += 1
                    while k < n, s[k] != q { k += 1 }
                    guard k < n else { return nil }
                    j = k + 1
                } else {
                    let valueStart = k
                    while k < n {
                        let v = s[k]
                        if MarkdownChar.isWhitespace(v) || v == 0x22 || v == 0x27 || v == 0x3D || v == 0x3C || v == 0x3E || v == 0x60 { break }
                        k += 1
                    }
                    guard k > valueStart else { return nil }
                    j = k
                }
            }
        }
    }

    static func closingTag(_ s: [UInt8], at i: Int) -> Int? {
        let n = s.count
        guard var j = tagNameEnd(s, at: i + 2) else { return nil }
        while j < n, MarkdownChar.isWhitespace(s[j]) { j += 1 }
        return j < n && s[j] == 0x3E ? j + 1 : nil
    }

    /// Index just past the first occurrence of `literal` at or after `from`.
    static func find(_ s: [UInt8], from: Int, _ literal: StaticString) -> Int? {
        let count = literal.utf8CodeUnitCount
        return literal.withUTF8Buffer { lit -> Int? in
            let first = lit[0]
            var j = from
            let limit = s.count - count
            while j <= limit {
                if s[j] == first {
                    var k = 1
                    while k < count && s[j + k] == lit[k] { k += 1 }
                    if k == count { return j + count }
                }
                j += 1
            }
            return nil
        }
    }

    /// Is `s[i..<end]` a `<br>`, `<br/>` or `<br />` tag (case-insensitive)?
    static func isBreakTag(_ s: [UInt8], _ i: Int, _ end: Int) -> Bool {
        guard end - i >= 4, MarkdownChar.matches(s, at: i, lowercase: "<br") else { return false }
        var j = i + 3
        while j < end, MarkdownChar.isWhitespace(s[j]) { j += 1 }
        if j < end, s[j] == 0x2F { j += 1 }
        return j == end - 1 && s[j] == 0x3E
    }
}
