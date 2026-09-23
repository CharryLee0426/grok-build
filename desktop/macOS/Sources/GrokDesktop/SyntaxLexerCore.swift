import Foundation

/// Collects tokens in document order. Overlaps are clipped and adjacent runs of one kind are merged,
/// so the output is always sorted and non-overlapping even if a lexer misbehaves.
final class SyntaxTokenSink {
    private(set) var tokens: [SyntaxToken] = []
    private var lastEnd = 0

    init(capacity: Int) { tokens.reserveCapacity(Swift.min(capacity, 1 << 16)) }

    func add(_ start: Int, _ end: Int, _ kind: SyntaxTokenKind) {
        guard kind != .plain else { return }
        let a = Swift.max(start, lastEnd)
        guard end > a else { return }
        if let last = tokens.last, last.kind == kind, last.range.location + last.range.length == a {
            tokens[tokens.count - 1] = SyntaxToken(range: NSRange(location: last.range.location, length: end - last.range.location), kind: kind)
        } else {
            tokens.append(SyntaxToken(range: NSRange(location: a, length: end - a), kind: kind))
        }
        lastEnd = end
    }

    struct Mark {
        let count: Int
        let last: SyntaxToken?
        let lastEnd: Int
    }

    func mark() -> Mark { Mark(count: tokens.count, last: tokens.last, lastEnd: lastEnd) }

    func rollback(_ mark: Mark) {
        if tokens.count > mark.count { tokens.removeSubrange(mark.count...) }
        if let last = mark.last, mark.count > 0, mark.count <= tokens.count { tokens[mark.count - 1] = last }
        lastEnd = mark.lastEnd
    }
}

/// UTF-16 code unit classification (ASCII-centric; other BMP letters count as identifier characters).
enum SyntaxChar {
    @inline(__always) static func isDigit(_ c: UInt16) -> Bool { c &- 48 < 10 }
    @inline(__always) static func isHex(_ c: UInt16) -> Bool { c &- 48 < 10 || (c | 0x20) &- 97 < 6 }
    @inline(__always) static func isLetter(_ c: UInt16) -> Bool { (c | 0x20) &- 97 < 26 }
    @inline(__always) static func isUpper(_ c: UInt16) -> Bool { c &- 65 < 26 }
    @inline(__always) static func isLower(_ c: UInt16) -> Bool { c &- 97 < 26 }
    @inline(__always) static func isAlnum(_ c: UInt16) -> Bool { isLetter(c) || isDigit(c) }
    @inline(__always) static func isBlank(_ c: UInt16) -> Bool { c == 32 || c == 9 || c == 13 || c == 12 || c == 11 }
    @inline(__always) static func isSpace(_ c: UInt16) -> Bool { c == 32 || c == 10 || c == 9 || c == 13 || c == 12 || c == 11 }

    @inline(__always) static func isIdentStart(_ c: UInt16) -> Bool {
        if c < 128 { return (c | 0x20) &- 97 < 26 || c == 95 }
        return isWordLike(c)
    }

    @inline(__always) static func isIdentPart(_ c: UInt16) -> Bool {
        if c < 128 { return (c | 0x20) &- 97 < 26 || c &- 48 < 10 || c == 95 }
        return isWordLike(c)
    }

    /// Non-ASCII units that behave like letters: excludes spaces, general punctuation, arrows, math
    /// operators, box drawing, CJK punctuation, surrogates (emoji) and specials.
    static func isWordLike(_ c: UInt16) -> Bool {
        switch c {
        case 0x80...0xBF, 0xD7, 0xF7: return false
        case 0x2000...0x2BFF: return false
        case 0x3000...0x303F: return false
        case 0xD800...0xDFFF: return false
        case 0xFE30...0xFE4F, 0xFEFF, 0xFF00...0xFF0F, 0xFFF0...0xFFFF: return false
        default: return true
        }
    }

    @inline(__always) static func lower(_ c: UInt16) -> UInt16 { c &- 65 < 26 ? c + 32 : c }
}

/// Word → (kind, role) lookup keyed by an FNV-1a hash of the UTF-16 units, so lookups never allocate.
struct SyntaxWordTable {
    struct Entry {
        let units: [UInt16]
        var kind: SyntaxTokenKind
        var role: UInt8
    }

    static let defineFunction: UInt8 = 1
    static let defineType: UInt8 = 2
    static let soft: UInt8 = 4
    static let afterDot: UInt8 = 8
    static let value: UInt8 = 16
    /// Keyword only when not used like an identifier (`get(`, `type:`, `set =`).
    static let contextual: UInt8 = 32

    private(set) var buckets: [UInt64: [Entry]] = [:]
    private(set) var maxLength = 0
    let caseInsensitive: Bool

    init(caseInsensitive: Bool = false) { self.caseInsensitive = caseInsensitive }

    var isEmpty: Bool { buckets.isEmpty }

    mutating func add(_ words: String, _ kind: SyntaxTokenKind, role: UInt8 = 0) {
        for word in words.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            var units = Array(word.utf16)
            if caseInsensitive { units = units.map(SyntaxChar.lower) }
            let h = units.withUnsafeBufferPointer { SyntaxWordTable.hash($0, 0, $0.count, ci: false) }
            var bucket = buckets[h] ?? []
            if let index = bucket.firstIndex(where: { $0.units == units }) {
                bucket[index].kind = kind
                bucket[index].role = role
            } else {
                bucket.append(Entry(units: units, kind: kind, role: role))
            }
            buckets[h] = bucket
            maxLength = Swift.max(maxLength, units.count)
        }
    }

    /// Adds `role` to words that are already present.
    mutating func addRole(_ words: String, _ role: UInt8) {
        for word in words.split(separator: " ") {
            var units = Array(word.utf16)
            if caseInsensitive { units = units.map(SyntaxChar.lower) }
            let h = units.withUnsafeBufferPointer { SyntaxWordTable.hash($0, 0, $0.count, ci: false) }
            guard var bucket = buckets[h], let index = bucket.firstIndex(where: { $0.units == units }) else { continue }
            bucket[index].role |= role
            buckets[h] = bucket
        }
    }

    @inline(__always) static func hash(_ p: UnsafeBufferPointer<UInt16>, _ a: Int, _ b: Int, ci: Bool) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        var k = a
        while k < b {
            let c = ci ? SyntaxChar.lower(p[k]) : p[k]
            h = (h ^ UInt64(c)) &* 0x0000_0100_0000_01b3
            k += 1
        }
        return h
    }

    func lookup(_ p: UnsafeBufferPointer<UInt16>, _ a: Int, _ b: Int) -> Entry? {
        let length = b - a
        guard length > 0, length <= maxLength else { return nil }
        guard let bucket = buckets[SyntaxWordTable.hash(p, a, b, ci: caseInsensitive)] else { return nil }
        outer: for entry in bucket where entry.units.count == length {
            var k = 0
            while k < length {
                let c = caseInsensitive ? SyntaxChar.lower(p[a + k]) : p[a + k]
                if c != entry.units[k] { continue outer }
                k += 1
            }
            return entry
        }
        return nil
    }

    func kind(_ p: UnsafeBufferPointer<UInt16>, _ a: Int, _ b: Int) -> SyntaxTokenKind? { lookup(p, a, b)?.kind }
}

/// Shared cursor over a UTF-16 buffer range; bespoke lexers are extensions of this type.
struct SyntaxLexer {
    let s: UnsafeBufferPointer<UInt16>
    let lo: Int
    let hi: Int
    let sink: SyntaxTokenSink
    let depth: Int

    static let maxDepth = 6

    @inline(__always) func at(_ i: Int) -> UInt16 { i < hi && i >= lo ? s[i] : 0 }

    @inline(__always) func emit(_ a: Int, _ b: Int, _ kind: SyntaxTokenKind) { sink.add(a, Swift.min(b, hi), kind) }

    /// A lexer for a nested range (embedded language); deeper nesting is left unhighlighted.
    func sub(_ a: Int, _ b: Int) -> SyntaxLexer {
        SyntaxLexer(s: s, lo: Swift.max(a, lo), hi: Swift.min(b, hi), sink: sink, depth: depth + 1)
    }

    func lineEnd(_ i: Int) -> Int {
        var j = i
        while j < hi && s[j] != 10 { j += 1 }
        return j
    }

    func nextLine(_ i: Int) -> Int {
        let e = lineEnd(i)
        return e < hi ? e + 1 : hi
    }

    func skipBlanks(_ i: Int) -> Int {
        var j = i
        while j < hi && SyntaxChar.isBlank(s[j]) { j += 1 }
        return j
    }

    func skipSpace(_ i: Int) -> Int {
        var j = i
        while j < hi && SyntaxChar.isSpace(s[j]) { j += 1 }
        return j
    }

    func identEnd(_ i: Int) -> Int {
        var j = i
        while j < hi && SyntaxChar.isIdentPart(s[j]) { j += 1 }
        return j
    }

    /// Index after the last non-blank character in `a..<b`.
    func trimEnd(_ a: Int, _ b: Int) -> Int {
        var e = b
        while e > a && SyntaxChar.isBlank(s[e - 1]) { e -= 1 }
        return e
    }

    func has(_ i: Int, _ lit: StaticString) -> Bool {
        let n = lit.utf8CodeUnitCount
        guard i >= lo, i + n <= hi else { return false }
        return lit.withUTF8Buffer { buf in
            for k in 0..<n where s[i + k] != UInt16(buf[k]) { return false }
            return true
        }
    }

    /// Case-insensitive match against an ASCII literal.
    func hasCI(_ i: Int, _ lit: StaticString) -> Bool {
        let n = lit.utf8CodeUnitCount
        guard i >= lo, i + n <= hi else { return false }
        return lit.withUTF8Buffer { buf in
            for k in 0..<n where SyntaxChar.lower(s[i + k]) != SyntaxChar.lower(UInt16(buf[k])) { return false }
            return true
        }
    }

    func has(_ i: Int, _ lit: [UInt16]) -> Bool {
        guard i >= lo, i + lit.count <= hi else { return false }
        for k in 0..<lit.count where s[i + k] != lit[k] { return false }
        return true
    }

    /// Whether `a..<b` equals the literal (optionally ignoring ASCII case).
    func word(_ a: Int, _ b: Int, is lit: StaticString, ci: Bool = false) -> Bool {
        guard b - a == lit.utf8CodeUnitCount else { return false }
        return ci ? hasCI(a, lit) : has(a, lit)
    }

    func find(_ lit: StaticString, from i: Int, to limit: Int? = nil) -> Int? {
        let end = limit ?? hi
        let first = lit.withUTF8Buffer { UInt16($0[0]) }
        var j = i
        while j < end {
            if s[j] == first && has(j, lit) { return j }
            j += 1
        }
        return nil
    }

    func findCI(_ lit: StaticString, from i: Int) -> Int? {
        let first = lit.withUTF8Buffer { SyntaxChar.lower(UInt16($0[0])) }
        var j = i
        while j < hi {
            if SyntaxChar.lower(s[j]) == first && hasCI(j, lit) { return j }
            j += 1
        }
        return nil
    }

    func units(_ a: Int, _ b: Int) -> [UInt16] { Array(s[Swift.max(a, lo)..<Swift.min(b, hi)]) }

    func string(_ a: Int, _ b: Int) -> String { String(decoding: s[Swift.max(a, lo)..<Swift.min(b, hi)], as: UTF16.self) }

    /// End of a backslash escape; `j` is the index just after the backslash.
    func escapeEnd(_ j: Int) -> Int {
        guard j < hi else { return hi }
        let c = s[j]
        switch c {
        case 120: // x
            if at(j + 1) == 123 { return braceEscapeEnd(j + 1) }
            var k = j + 1
            while k < hi && k < j + 3 && SyntaxChar.isHex(s[k]) { k += 1 }
            return k
        case 117: // u
            if at(j + 1) == 123 { return braceEscapeEnd(j + 1) }
            var k = j + 1
            while k < hi && k < j + 5 && SyntaxChar.isHex(s[k]) { k += 1 }
            return k
        case 85: // U
            var k = j + 1
            while k < hi && k < j + 9 && SyntaxChar.isHex(s[k]) { k += 1 }
            return k
        case 48...55:
            var k = j + 1
            while k < hi && k < j + 3 && s[k] &- 48 < 8 { k += 1 }
            return k
        case 0xD800...0xDBFF:
            return Swift.min(j + 2, hi)
        default:
            return j + 1
        }
    }

    private func braceEscapeEnd(_ j: Int) -> Int {
        var k = j + 1
        while k < hi && k < j + 12 {
            if s[k] == 125 { return k + 1 }
            if !SyntaxChar.isAlnum(s[k]) && s[k] != 95 && s[k] != 43 && s[k] != 32 { break }
            k += 1
        }
        return j
    }

    /// Emits `a..<b` as `kind`, splitting out backslash escapes as `.escape`.
    func emitEscaped(_ a: Int, _ b: Int, _ kind: SyntaxTokenKind) {
        var seg = a
        var j = a
        while j < b {
            if s[j] == 92 && j + 1 < b {
                let e = Swift.min(escapeEnd(j + 1), b)
                emit(seg, j, kind)
                emit(j, e, .escape)
                j = e
                seg = e
            } else {
                j += 1
            }
        }
        emit(seg, b, kind)
    }

    /// Scans a quoted string starting at the opening quote `i`; returns the index after the closing quote
    /// (or the end of line/buffer when unterminated).
    func quotedEnd(_ i: Int, quote: UInt16, escapes: Bool = true, multiline: Bool = false) -> Int {
        var j = i + 1
        while j < hi {
            let c = s[j]
            if c == quote { return j + 1 }
            if c == 10 && !multiline { return j }
            if escapes && c == 92 { j += 2; continue }
            j += 1
        }
        return hi
    }

    /// Index after the bracket matching the opener at `i` (nesting-aware, skips quoted strings).
    func matchingClose(_ i: Int, open: UInt16, close: UInt16, multiline: Bool = true, limit: Int? = nil) -> Int {
        var depth = 0
        var j = i
        let end = Swift.min(limit ?? hi, hi)
        while j < end {
            let c = s[j]
            if c == open { depth += 1 } else if c == close {
                depth -= 1
                if depth == 0 { return j + 1 }
            } else if c == 34 || c == 39 {
                j = quotedEnd(j, quote: c)
                continue
            } else if c == 10 && !multiline {
                return j
            } else if c == 92 {
                j += 1
            }
            j += 1
        }
        return end
    }

    /// Runs the lexer for `kind` over this range.
    func run(_ kind: SyntaxLexerKind) {
        guard depth <= SyntaxLexer.maxDepth, lo < hi else { return }
        switch kind {
        case .none: return
        case .code(let id):
            guard let spec = SyntaxSpecs.spec(id) else { return }
            var lexer = SyntaxCodeLexer(self, spec)
            lexer.lexAll()
        case .markup(let flavor): lexMarkup(flavor)
        case .php: lexPHPDocument()
        case .css(let flavor): lexCSS(flavor)
        case .json(let flavor): lexJSON(flavor)
        case .yaml: lexYAML()
        case .toml: lexTOML()
        case .ini(let flavor): lexINI(flavor)
        case .markdown: lexMarkdown()
        case .diff: lexDiff()
        case .gitCommit: lexGitCommit()
        case .gitRebase: lexGitRebase()
        case .regex: lexRegex()
        case .http: lexHTTP()
        case .latex: lexLaTeX()
        case .shell(let flavor): lexShell(flavor)
        case .console: lexConsole()
        case .pycon: lexPythonConsole()
        case .powershell: lexPowerShell()
        case .batch: lexBatch()
        case .dockerfile: lexDockerfile()
        case .makefile: lexMakefile()
        case .lisp(let flavor): lexLisp(flavor)
        case .asm: lexAssembly()
        case .nginx: lexServerConfig(apache: false)
        case .apache: lexServerConfig(apache: true)
        }
    }

    func run(languageId: String) {
        if let kind = SyntaxLanguageRegistry.lexerKind(forId: languageId) { run(kind) }
    }
}
