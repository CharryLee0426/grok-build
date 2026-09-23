import Foundation

/// Inline parser (CommonMark + GFM strikethrough/autolinks + math) working on UTF-8 bytes.
///
/// Scanning produces a flat token list; `[`/`]` pairs are resolved as they close and
/// emphasis delimiters are resolved with the CommonMark delimiter-run algorithm in
/// `resolve(_:)` (per link text, then for the whole subject).
struct MarkdownInlineParser {
    enum Token {
        case text(String)
        case node(MarkdownInline)
        case delimiter(char: UInt8, count: Int, canOpen: Bool, canClose: Bool)
        case bracket(image: Bool)
    }

    struct Bracket {
        var tokenIndex: Int
        var image: Bool
        var textStart: Int
        var bracketAfter: Bool
    }

    enum MathCloser { case single, double, paren, bracket }

    /// Prefix used for footnote labels stored in the definitions map.
    static let footnoteKeyPrefix = "\u{0}fn:"

    let s: [UInt8]
    let n: Int
    let refs: [String: MarkdownLinkDefinition]
    var pos = 0
    var tokens: [Token] = []
    var pending: [UInt8] = []
    var brackets: [Bracket] = []
    // Positions from which a closer search is known to fail (avoids quadratic rescans).
    var backtickFail = [Int](repeating: Int.max, count: 33)
    var mathFail = [Int](repeating: Int.max, count: 4)
    var titleFail = [Int](repeating: Int.max, count: 2)
    /// Link openers (`[`, not `![`) below this bracket-stack index are inactive because a
    /// link was formed after them (links cannot contain links).
    var inactiveBelow = 0

    static func parse(_ bytes: [UInt8], refs: [String: MarkdownLinkDefinition]) -> [MarkdownInline] {
        guard !bytes.isEmpty else { return [] }
        var parser = MarkdownInlineParser(s: bytes, refs: refs)
        return parser.run()
    }

    init(s: [UInt8], refs: [String: MarkdownLinkDefinition]) {
        self.s = s
        self.n = s.count
        self.refs = refs
        pending.reserveCapacity(min(s.count, 256))
    }

    static let specialTable: [Bool] = {
        var t = [Bool](repeating: false, count: 256)
        for c in "\n\\`$*_~[]!<&:wW".utf8 { t[Int(c)] = true }
        return t
    }()

    mutating func run() -> [MarkdownInline] {
        let special = MarkdownInlineParser.specialTable
        while pos < n {
            let c = s[pos]
            if !special[Int(c)] {
                let start = pos
                pos += 1
                while pos < n && !special[Int(s[pos])] { pos += 1 }
                pending.append(contentsOf: s[start..<pos])
                continue
            }
            switch c {
            case 0x0A: handleNewline()
            case 0x5C: handleBackslash()
            case 0x60: handleBackticks()
            case 0x24: handleDollar()
            case 0x2A, 0x5F, 0x7E: handleDelimiterRun(c)
            case 0x5B: handleOpenBracket(image: false)
            case 0x21:
                if pos + 1 < n && s[pos + 1] == 0x5B {
                    handleOpenBracket(image: true)
                } else {
                    pending.append(c)
                    pos += 1
                }
            case 0x5D: handleCloseBracket()
            case 0x3C: handleLessThan()
            case 0x26: handleEntity()
            case 0x3A: handleColon()
            default: handleW()
            }
        }
        flush()
        return MarkdownInlineParser.resolve(tokens[...])
    }

    @inline(__always) mutating func flush() {
        if !pending.isEmpty {
            tokens.append(.text(MarkdownChar.string(pending)))
            pending.removeAll(keepingCapacity: true)
        }
    }

    @inline(__always) mutating func literal(_ c: UInt8) {
        pending.append(c)
        pos += 1
    }

    mutating func skipLeadingSpaces() {
        while pos < n && MarkdownChar.isSpaceOrTab(s[pos]) { pos += 1 }
    }

    // MARK: Line breaks

    mutating func handleNewline() {
        var spaces = 0
        while let last = pending.last, last == MarkdownChar.space {
            pending.removeLast()
            spaces += 1
        }
        flush()
        pos += 1
        if spaces >= 2 {
            tokens.append(.node(.lineBreak))
        } else if case .node(.lineBreak)? = tokens.last {
            // `<br>` right before a newline: the newline adds nothing.
        } else {
            tokens.append(.node(.softBreak))
        }
        skipLeadingSpaces()
    }

    mutating func handleBackslash() {
        if pos + 1 < n {
            let next = s[pos + 1]
            if next == MarkdownChar.newline {
                flush()
                tokens.append(.node(.lineBreak))
                pos += 2
                skipLeadingSpaces()
                return
            }
            if next == 0x28 || next == 0x5B { // \( … \)  and  \[ … \]
                let kind: MathCloser = next == 0x28 ? .paren : .bracket
                if let close = findMathCloser(from: pos + 2, kind: kind) {
                    let r = MarkdownChar.trimmedRange(s, pos + 2, close)
                    if !r.isEmpty && !isOnlyEscapes(r) {
                        flush()
                        let latex = MarkdownChar.string(s[r])
                        tokens.append(.node(kind == .paren ? .math(latex) : .displayMath(latex)))
                        pos = close + 2
                        return
                    }
                }
            }
            if MarkdownChar.isASCIIPunctuation(next) {
                pending.append(next)
                pos += 2
                return
            }
        }
        literal(MarkdownChar.backslash)
    }

    /// `\[\\\]` is escaped punctuation, not math: require something besides escape pairs.
    func isOnlyEscapes(_ r: Range<Int>) -> Bool {
        var i = r.lowerBound
        while i < r.upperBound {
            guard s[i] == MarkdownChar.backslash, i + 1 < r.upperBound, MarkdownChar.isASCIIPunctuation(s[i + 1]) else { return false }
            i += 2
        }
        return true
    }

    // MARK: Code spans

    mutating func findBacktickCloser(from: Int, length: Int) -> (start: Int, end: Int)? {
        let cacheable = length < backtickFail.count
        if cacheable && from >= backtickFail[length] { return nil }
        var j = from
        while j < n {
            if s[j] == MarkdownChar.backtick {
                let runStart = j
                while j < n && s[j] == MarkdownChar.backtick { j += 1 }
                if j - runStart == length { return (runStart, j) }
            } else {
                j += 1
            }
        }
        if cacheable { backtickFail[length] = min(backtickFail[length], from) }
        return nil
    }

    mutating func handleBackticks() {
        let start = pos
        var k = pos
        while k < n && s[k] == MarkdownChar.backtick { k += 1 }
        guard let closer = findBacktickCloser(from: k, length: k - start) else {
            pending.append(contentsOf: s[start..<k])
            pos = k
            return
        }
        var content = Array(s[k..<closer.start])
        for i in content.indices where content[i] == MarkdownChar.newline { content[i] = MarkdownChar.space }
        if content.count >= 2, content.first == MarkdownChar.space, content.last == MarkdownChar.space,
           content.contains(where: { $0 != MarkdownChar.space }) {
            content = Array(content[1..<(content.count - 1)])
        }
        flush()
        tokens.append(.node(.code(MarkdownChar.string(content))))
        pos = closer.end
    }

    // MARK: Math

    /// Finds the start index of the closing math delimiter. A code span starting inside the
    /// candidate math makes it fail (code spans bind tighter than math).
    mutating func findMathCloser(from: Int, kind: MathCloser) -> Int? {
        let cacheIndex: Int
        switch kind {
        case .single: cacheIndex = 0
        case .double: cacheIndex = 1
        case .paren: cacheIndex = 2
        case .bracket: cacheIndex = 3
        }
        if from >= mathFail[cacheIndex] { return nil }
        var j = from
        while j < n {
            let c = s[j]
            if c == MarkdownChar.backslash {
                if j + 1 < n {
                    let d = s[j + 1]
                    if (kind == .paren && d == 0x29) || (kind == .bracket && d == 0x5D) { return j }
                }
                j += 2
                continue
            }
            if c == MarkdownChar.backtick {
                let runStart = j
                while j < n && s[j] == MarkdownChar.backtick { j += 1 }
                if findBacktickCloser(from: j, length: j - runStart) != nil { return nil }
                continue
            }
            if c == MarkdownChar.dollar {
                if kind == .double {
                    if j + 1 < n && s[j + 1] == MarkdownChar.dollar { return j }
                } else if kind == .single {
                    // Pandoc: the closer needs a non-space before it and no digit right after it.
                    // Refinement: the first `$` decides; if it cannot close, there is no math
                    // (so "costs $5, then $x$" does not swallow text up to the `x`).
                    let valid = !MarkdownChar.isWhitespace(s[j - 1]) && !(j + 1 < n && MarkdownChar.isDigit(s[j + 1]))
                    return valid ? j : nil
                }
            }
            j += 1
        }
        mathFail[cacheIndex] = min(mathFail[cacheIndex], from)
        return nil
    }

    mutating func handleDollar() {
        if pos + 1 < n && s[pos + 1] == MarkdownChar.dollar {
            if let close = findMathCloser(from: pos + 2, kind: .double) {
                let r = MarkdownChar.trimmedRange(s, pos + 2, close)
                if !r.isEmpty {
                    flush()
                    tokens.append(.node(.displayMath(MarkdownChar.string(s[r]))))
                    pos = close + 2
                    return
                }
            }
            pending.append(MarkdownChar.dollar)
            pending.append(MarkdownChar.dollar)
            pos += 2
            return
        }
        // Pandoc: the opener needs a non-space right after it.
        if pos + 1 < n && !MarkdownChar.isWhitespace(s[pos + 1]),
           let close = findMathCloser(from: pos + 1, kind: .single) {
            flush()
            tokens.append(.node(.math(MarkdownChar.string(s[(pos + 1)..<close]))))
            pos = close + 1
            return
        }
        literal(MarkdownChar.dollar)
    }

    // MARK: Emphasis delimiters

    mutating func handleDelimiterRun(_ c: UInt8) {
        let start = pos
        var k = pos
        while k < n && s[k] == c { k += 1 }
        let count = k - start
        pos = k
        if c == 0x7E && count != 2 { // GFM strikethrough uses exactly `~~`
            pending.append(contentsOf: s[start..<k])
            return
        }
        let before = MarkdownChar.classBefore(s, start)
        let after = MarkdownChar.classAt(s, k)
        let leftFlanking = after != .whitespace && (after != .punctuation || before != .other)
        let rightFlanking = before != .whitespace && (before != .punctuation || after != .other)
        let canOpen: Bool
        let canClose: Bool
        if c == 0x5F {
            canOpen = leftFlanking && (!rightFlanking || before == .punctuation)
            canClose = rightFlanking && (!leftFlanking || after == .punctuation)
        } else {
            canOpen = leftFlanking
            canClose = rightFlanking
        }
        guard canOpen || canClose else {
            pending.append(contentsOf: s[start..<k])
            return
        }
        flush()
        tokens.append(.delimiter(char: c, count: count, canOpen: canOpen, canClose: canClose))
    }

    // MARK: Links and images

    mutating func handleOpenBracket(image: Bool) {
        if !image, pos + 2 < n, s[pos + 1] == 0x5E, let end = footnoteReferenceEnd() {
            flush()
            tokens.append(.node(.footnoteReference(MarkdownChar.string(s[(pos + 2)..<(end - 1)]))))
            pos = end
            return
        }
        flush()
        if !brackets.isEmpty { brackets[brackets.count - 1].bracketAfter = true }
        tokens.append(.bracket(image: image))
        let width = image ? 2 : 1
        brackets.append(Bracket(tokenIndex: tokens.count - 1, image: image, textStart: pos + width, bracketAfter: false))
        pos += width
    }

    /// `[^label]`: a footnote reference when the label is numeric or has a definition.
    func footnoteReferenceEnd() -> Int? {
        var j = pos + 2
        var allDigits = true
        while j < n && j - pos < 130 {
            let c = s[j]
            if c == 0x5D || c == 0x5B || MarkdownChar.isWhitespace(c) { break }
            if !MarkdownChar.isDigit(c) { allDigits = false }
            j += 1
        }
        guard j < n, s[j] == 0x5D, j > pos + 2 else { return nil }
        if allDigits { return j + 1 }
        let key = MarkdownInlineParser.footnoteKeyPrefix + MarkdownChar.normalizeLabel(s[(pos + 2)..<j])
        return refs[key] != nil ? j + 1 : nil
    }

    mutating func handleCloseBracket() {
        let closePos = pos
        pos += 1
        guard let bracket = brackets.last else {
            pending.append(0x5D)
            return
        }
        guard bracket.image || brackets.count - 1 >= inactiveBelow else {
            popBracketAsText()
            return
        }
        var destination: String?
        var title: String?
        var end = pos
        if pos < n && s[pos] == 0x28 {
            let j = MarkdownLinkScanner.skipSpacesAndNewline(s, at: pos + 1)
            if j < n && s[j] == 0x29 {
                destination = ""
                end = j + 1
            } else if let (d, dEnd) = MarkdownLinkScanner.linkDestination(s, at: j) {
                var k = MarkdownLinkScanner.skipSpacesAndNewline(s, at: dEnd)
                var t: String?
                if k > dEnd && k < n {
                    // Unclosed quoted titles are remembered so repeated attempts stay linear.
                    let quoteIndex = s[k] == 0x22 ? 0 : (s[k] == 0x27 ? 1 : -1)
                    if quoteIndex >= 0 && k >= titleFail[quoteIndex] {
                        // known to be unterminated
                    } else if let (tt, tEnd) = MarkdownLinkScanner.linkTitle(s, at: k) {
                        t = tt
                        k = MarkdownLinkScanner.skipSpacesAndNewline(s, at: tEnd)
                    } else if quoteIndex >= 0 {
                        titleFail[quoteIndex] = min(titleFail[quoteIndex], k)
                    }
                }
                if k < n && s[k] == 0x29 {
                    destination = d
                    title = t
                    end = k + 1
                }
            }
        }
        if destination == nil && !refs.isEmpty {
            var label: ArraySlice<UInt8>?
            var afterLabel = pos
            if pos < n && s[pos] == 0x5B, let labelEnd = MarkdownLinkScanner.linkLabel(s, at: pos) {
                if labelEnd - pos > 2 {
                    label = s[(pos + 1)..<(labelEnd - 1)]
                } else if !bracket.bracketAfter {
                    label = s[bracket.textStart..<closePos]
                }
                afterLabel = labelEnd
            } else if !bracket.bracketAfter {
                label = s[bracket.textStart..<closePos]
            }
            if let label, label.count <= 999, let def = refs[MarkdownChar.normalizeLabel(label)] {
                destination = def.destination
                title = def.title
                end = afterLabel
            }
        }
        guard let destination else {
            popBracketAsText()
            return
        }
        flush()
        let children = MarkdownInlineParser.resolve(tokens[(bracket.tokenIndex + 1)...])
        tokens.removeSubrange(bracket.tokenIndex...)
        brackets.removeLast()
        inactiveBelow = min(inactiveBelow, brackets.count)
        if bracket.image {
            tokens.append(.node(.image(source: destination, title: title, alt: MarkdownInline.plainText(children))))
        } else {
            tokens.append(.node(.link(destination: destination, title: title, content: MarkdownInlineParser.flattenLinks(children))))
            // No links inside links: earlier `[` openers can no longer form links.
            inactiveBelow = brackets.count
        }
        pos = end
    }

    /// The innermost bracket did not form a link: it becomes literal text, as does the `]`.
    mutating func popBracketAsText() {
        let bracket = brackets.removeLast()
        inactiveBelow = min(inactiveBelow, brackets.count)
        tokens[bracket.tokenIndex] = .text(bracket.image ? "![" : "[")
        pending.append(0x5D)
    }

    static func flattenLinks(_ inlines: [MarkdownInline]) -> [MarkdownInline] {
        var out: [MarkdownInline] = []
        out.reserveCapacity(inlines.count)
        for inline in inlines {
            switch inline {
            case .link(_, _, let content): out.append(contentsOf: flattenLinks(content))
            case .emphasis(let c): out.append(.emphasis(flattenLinks(c)))
            case .strong(let c): out.append(.strong(flattenLinks(c)))
            case .strikethrough(let c): out.append(.strikethrough(flattenLinks(c)))
            default: out.append(inline)
            }
        }
        return out
    }

    // MARK: Autolinks, HTML, entities

    mutating func handleLessThan() {
        if let end = MarkdownLinkScanner.uriAutolink(s, at: pos) {
            let uri = MarkdownChar.string(s[(pos + 1)..<(end - 1)])
            flush()
            tokens.append(.node(.link(destination: uri, title: nil, content: [.text(uri)])))
            pos = end
            return
        }
        if let end = MarkdownLinkScanner.emailAutolink(s, at: pos) {
            let email = MarkdownChar.string(s[(pos + 1)..<(end - 1)])
            flush()
            tokens.append(.node(.link(destination: "mailto:" + email, title: nil, content: [.text(email)])))
            pos = end
            return
        }
        if let end = MarkdownLinkScanner.htmlTag(s, at: pos) {
            flush()
            if MarkdownLinkScanner.isBreakTag(s, pos, end) {
                tokens.append(.node(.lineBreak))
            } else {
                tokens.append(.node(.html(MarkdownChar.string(s[pos..<end]))))
            }
            pos = end
            return
        }
        literal(0x3C)
    }

    mutating func handleEntity() {
        if let (bytes, length) = MarkdownEntities.decode(s, at: pos) {
            pending.append(contentsOf: bytes)
            pos += length
        } else {
            literal(0x26)
        }
    }

    /// Extended-autolink boundary: start, whitespace, `*_~("'[`, or any non-ASCII character.
    @inline(__always) func autolinkBoundary(_ i: Int) -> Bool {
        guard i > 0 else { return true }
        let b = s[i - 1]
        if b >= 0x80 || MarkdownChar.isWhitespace(b) { return true }
        switch b {
        case 0x2A, 0x5F, 0x7E, 0x28, 0x22, 0x27, 0x5B: return true
        default: return false
        }
    }

    /// Bare `http://` / `https://` / `ftp://` autolinks (triggered at the `:`).
    mutating func handleColon() {
        guard pos + 3 < n, s[pos + 1] == 0x2F, s[pos + 2] == 0x2F else { return literal(0x3A) }
        var schemeLength = 0
        if pos >= 5 && MarkdownChar.matches(s, at: pos - 5, lowercase: "https") {
            schemeLength = 5
        } else if pos >= 4 && MarkdownChar.matches(s, at: pos - 4, lowercase: "http") {
            schemeLength = 4
        } else if pos >= 3 && MarkdownChar.matches(s, at: pos - 3, lowercase: "ftp") {
            schemeLength = 3
        }
        let schemeStart = pos - schemeLength
        guard schemeLength > 0, pending.count >= schemeLength, autolinkBoundary(schemeStart) else { return literal(0x3A) }
        for k in 0..<schemeLength where pending[pending.count - schemeLength + k] != s[schemeStart + k] {
            return literal(0x3A)
        }
        guard let end = extendedAutolinkEnd(from: pos + 3) else { return literal(0x3A) }
        pending.removeLast(schemeLength)
        flush()
        let url = MarkdownChar.string(s[schemeStart..<end])
        tokens.append(.node(.link(destination: url, title: nil, content: [.text(url)])))
        pos = end
    }

    /// Bare `www.` autolinks.
    mutating func handleW() {
        if autolinkBoundary(pos), pos + 4 < n, MarkdownChar.matches(s, at: pos, lowercase: "www."),
           let end = extendedAutolinkEnd(from: pos + 4) {
            flush()
            let text = MarkdownChar.string(s[pos..<end])
            tokens.append(.node(.link(destination: "http://" + text, title: nil, content: [.text(text)])))
            pos = end
            return
        }
        literal(s[pos])
    }

    /// Non-ASCII punctuation that terminates a bare URL (general punctuation, CJK
    /// punctuation and fullwidth forms), so `见https://a.com。` stops before `。`.
    @inline(__always) func isURLStopper(_ j: Int) -> Bool {
        let b = s[j]
        guard b >= 0xE2, j + 1 < n else { return false }
        let b1 = s[j + 1]
        return (b == 0xE2 && b1 == 0x80) || (b == 0xE3 && b1 == 0x80) || (b == 0xEF && b1 >= 0xBC && b1 <= 0xBF)
    }

    /// End of an extended autolink whose domain starts at `from`, applying GFM's
    /// trailing-punctuation rules; `nil` if there is no domain.
    func extendedAutolinkEnd(from: Int) -> Int? {
        var j = from
        while j < n {
            let c = s[j]
            if MarkdownChar.isAlphanumeric(c) || c == 0x2D || c == 0x5F || c == 0x2E {
                j += 1
            } else if c >= 0x80 && !isURLStopper(j) {
                j += 1
            } else {
                break
            }
        }
        guard j > from else { return nil }
        // Inside potential link text, `]` ends the URL so `[https://a.com](b)` stays a link.
        let insideBrackets = !brackets.isEmpty
        while j < n {
            let c = s[j]
            if MarkdownChar.isWhitespace(c) || c == 0x3C || (c >= 0x80 && isURLStopper(j)) || (c == 0x5D && insideBrackets) { break }
            j += 1
        }
        var end = j
        var parens = 0, brackets = 0 // closing minus opening, over s[from..<end]
        for k in from..<end {
            switch s[k] {
            case 0x28: parens -= 1
            case 0x29: parens += 1
            case 0x5B: brackets -= 1
            case 0x5D: brackets += 1
            default: break
            }
        }
        trimming: while end > from {
            let c = s[end - 1]
            switch c {
            case 0x3F, 0x21, 0x2E, 0x2C, 0x3A, 0x2A, 0x5F, 0x7E, 0x27, 0x22:
                end -= 1
            case 0x3B:
                var k = end - 2
                while k >= from && MarkdownChar.isAlphanumeric(s[k]) { k -= 1 }
                end = (k >= from && s[k] == 0x26 && k < end - 2) ? k : end - 1
            case 0x29 where parens > 0:
                parens -= 1
                end -= 1
            case 0x5D where brackets > 0:
                brackets -= 1
                end -= 1
            default:
                break trimming
            }
        }
        // Require at least one domain character to survive trimming.
        guard end > from, MarkdownChar.isAlphanumeric(s[from]) || s[from] >= 0x80 else { return nil }
        return end
    }
}
