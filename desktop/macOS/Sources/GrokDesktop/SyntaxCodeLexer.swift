import Foundation

/// Generic table-driven lexer for C-like and scripting languages (see `SyntaxLangSpec`).
struct SyntaxCodeLexer {
    enum Prev { case none, op, value }

    struct StringOptions {
        var close: [UInt16]
        var escapes = true
        /// Only `\\` and `\<quote>` are escapes (Ruby/PHP/Perl single quotes).
        var limitedEscapes = false
        var escapeChar: UInt16 = 92
        var multiline = false
        var interpolation: SyntaxInterpolation = .none
        var doubled = false
        /// Swift extended delimiters: escapes and interpolation need `\` followed by this many `#`.
        var rawHashes = 0
        var kind: SyntaxTokenKind = .string
        /// Nix indented strings: two quotes followed by a quote, `$` or backslash are escapes, not terminators.
        var nix = false
    }

    struct Heredoc {
        let tag: [UInt16]
        let indented: Bool
        let interpolates: Bool
    }

    static let dq: [UInt16] = [34]
    static let sq: [UInt16] = [39]
    static let bt: [UInt16] = [96]
    static let tdq: [UInt16] = [34, 34, 34]
    static let tsq: [UInt16] = [39, 39, 39]

    let L: SyntaxLexer
    let spec: SyntaxLangSpec
    let s: UnsafeBufferPointer<UInt16>
    let lo: Int
    let hi: Int
    let mask: (UInt64, UInt64)
    var lineStart = true
    var prev: Prev = .none
    var prevIdent = false
    var pendingDef: UInt8 = 0
    var heredocs: [Heredoc] = []
    var nesting = 0
    var stopAtPHPClose = false
    var jsxClosers: Set<[UInt16]>?

    init(_ lexer: SyntaxLexer, _ spec: SyntaxLangSpec) {
        L = lexer
        self.spec = spec
        s = lexer.s
        lo = lexer.lo
        hi = lexer.hi
        mask = spec.specialMask()
    }

    @inline(__always) func at(_ i: Int) -> UInt16 { i < hi && i >= lo ? s[i] : 0 }
    @inline(__always) func emit(_ a: Int, _ b: Int, _ k: SyntaxTokenKind) { L.emit(a, b, k) }

    @inline(__always) func isSpecial(_ c: UInt16) -> Bool {
        if c < 64 { return (mask.0 >> UInt64(c)) & 1 != 0 }
        if c < 128 { return (mask.1 >> UInt64(c - 64)) & 1 != 0 }
        return false
    }

    mutating func lexAll() {
        var i = lo
        run(&i, closer: 0, opener: 0, stopAtNewline: false)
    }

    /// Main loop. With a `closer`, returns (without consuming it) at the first unbalanced closer.
    mutating func run(_ i: inout Int, closer: UInt16, opener: UInt16, stopAtNewline: Bool, formatSpec: Bool = false) {
        var nest = 0
        var brackets = 0
        while i < hi {
            let c = s[i]
            if c == 10 {
                if stopAtNewline { return }
                i += 1
                lineStart = true
                if !heredocs.isEmpty { readHeredocs(&i) }
                continue
            }
            if c == 32 || c == 9 || c == 13 || c == 12 { i += 1; continue }
            if closer != 0 {
                if c == closer {
                    if nest == 0 { return }
                    nest -= 1
                } else if c == opener {
                    nest += 1
                }
            }
            if formatSpec {
                // `{value:>10}` / `{value!r}` / `{DateTime.Now:HH:mm}`: stop at the format specifier.
                if c == 40 || c == 91 { brackets += 1 } else if c == 41 || c == 93 { brackets -= 1 }
                if nest == 0 && brackets <= 0 {
                    if c == 58 && at(i + 1) != 61 && at(i + 1) != 58 { return }
                    if c == 33 && (at(i + 2) == 58 || at(i + 2) == 125) && "rsa".utf16.contains(at(i + 1)) { return }
                }
            }
            if stopAtPHPClose && nesting == 0 && c == 63 && at(i + 1) == 62 { return }
            let start = i
            let atLineStart = lineStart
            lineStart = false
            step(&i, c, atLineStart)
            if i <= start { i = start + 1 }
        }
    }

    mutating func step(_ i: inout Int, _ c: UInt16, _ atLineStart: Bool) {
        if isSpecial(c) && special(&i, c, atLineStart) { return }
        if SyntaxChar.isDigit(c) && spec.numbers {
            let e = numberEnd(i)
            emit(i, e, .number)
            i = e
            prev = .value
            prevIdent = false
            pendingDef = 0
            return
        }
        if SyntaxChar.isIdentStart(c) || (c == 36 && spec.identDollar) {
            identifier(&i, atLineStart)
            return
        }
        switch c {
        case 41, 93, 125: prev = .value
        default: prev = .op
        }
        if c != 46 { pendingDef = 0 }
        prevIdent = false
        i += 1
    }

    // MARK: - Special constructs

    mutating func special(_ i: inout Int, _ c: UInt16, _ atLineStart: Bool) -> Bool {
        if c == 35 && i == lo && at(i + 1) == 33 {
            let e = L.lineEnd(i)
            emit(i, e, .comment)
            i = e
            return true
        }
        if atLineStart {
            for pair in spec.lineStartBlocks where L.has(i, pair.open) {
                if pair.open == [61] && !SyntaxChar.isLetter(at(i + 1)) { continue }
                i = lineStartBlockEnd(i, pair)
                return true
            }
            for marker in spec.lineStartComments where L.has(i, marker) {
                let e = L.lineEnd(i)
                emit(i, e, .comment)
                i = e
                return true
            }
            for marker in spec.endMarkers where L.has(i, marker) {
                emit(i, hi, .comment)
                i = hi
                return true
            }
        }
        if c == 35 && hashRule(&i, atLineStart) { return true }
        if c == 123 {
            if spec.haskellPragma && L.has(i, "{-#") {
                let e = (L.find("#-}", from: i + 3)).map { $0 + 3 } ?? hi
                emit(i, e, .attribute)
                i = e
                return true
            }
            if spec.nimPragma && at(i + 1) == 46 {
                let e = (L.find(".}", from: i + 2, to: L.lineEnd(i))).map { $0 + 2 } ?? i + 2
                emit(i, e, .attribute)
                i = e
                return true
            }
        }
        if spec.luaLongBrackets && c == 45 && at(i + 1) == 45 && at(i + 2) == 91, let e = luaLongEnd(i + 2) {
            emit(i, e, .comment)
            i = e
            return true
        }
        for pair in spec.blockComments where L.has(i, pair.open) {
            let e = blockCommentEnd(i, pair)
            emit(i, e, .comment)
            i = e
            return true
        }
        for marker in spec.lineComments where L.has(i, marker) {
            if spec.haskellDashes && !haskellCommentStart(i) { continue }
            let e = L.lineEnd(i)
            emit(i, e, .comment)
            i = e
            return true
        }
        switch c {
        case 34:
            guard spec.doubleQuote else { return false }
            doubleQuoted(&i, from: i)
            return true
        case 39: return singleQuote(&i)
        case 96: return backtick(&i)
        case 64: return atSign(&i, atLineStart)
        case 36: return dollar(&i)
        case 58: return colonSymbol(&i)
        case 63: return question(&i)
        case 47: return regexLiteral(&i, atLineStart)
        case 60: return angle(&i)
        case 37: return percent(&i)
        case 126: return sigil(&i)
        case 91: return bracket(&i, atLineStart)
        case 92:
            guard spec.zigLineStrings && at(i + 1) == 92 else { return false }
            let e = L.lineEnd(i)
            emit(i, e, .string)
            i = e
            prev = .value
            return true
        case 46: return dot(&i)
        case 45:
            guard spec.erlangAttributes && atLineStart && SyntaxChar.isLower(at(i + 1)) else { return false }
            let e = L.identEnd(i + 1)
            emit(i, e, .attribute)
            i = e
            prev = .op
            return true
        case 38:
            guard spec.vimScopes && SyntaxChar.isLetter(at(i + 1)) else { return false }
            let e = L.identEnd(i + 1)
            emit(i, e, .variable)
            i = e
            prev = .value
            return true
        default:
            return false
        }
    }

    func blockCommentEnd(_ i: Int, _ pair: SyntaxDelimiterPair) -> Int {
        var j = i + pair.open.count
        var depth = 1
        let c0 = pair.close[0], o0 = pair.open[0]
        while j < hi {
            let c = s[j]
            if c == c0 && L.has(j, pair.close) {
                depth -= 1
                j += pair.close.count
                if depth == 0 { return j }
                continue
            }
            if spec.nestedComments && c == o0 && L.has(j, pair.open) {
                depth += 1
                j += pair.open.count
                continue
            }
            j += 1
        }
        return hi
    }

    mutating func lineStartBlockEnd(_ i: Int, _ pair: SyntaxDelimiterPair) -> Int {
        var j = L.nextLine(i)
        while j < hi {
            let k = L.skipBlanks(j)
            if L.has(k, pair.close) {
                let e = L.lineEnd(k)
                emit(i, e, .comment)
                return e
            }
            j = L.nextLine(j)
        }
        emit(i, hi, .comment)
        return hi
    }

    /// Haskell: `--` starts a comment only when the dash run is not part of an operator (`-->`).
    func haskellCommentStart(_ i: Int) -> Bool {
        var j = i
        while j < hi && s[j] == 45 { j += 1 }
        let c = at(j)
        let symbols: [UInt16] = [33, 35, 36, 37, 38, 42, 43, 46, 47, 60, 61, 62, 63, 64, 92, 94, 124, 126, 58]
        return !symbols.contains(c)
    }

    /// Lua long bracket `[==[ ... ]==]` starting at `i` (the `[`); nil if not a long bracket.
    func luaLongEnd(_ i: Int) -> Int? {
        guard at(i) == 91 else { return nil }
        var j = i + 1
        var level = 0
        while at(j) == 61 { level += 1; j += 1 }
        guard at(j) == 91 else { return nil }
        j += 1
        while j < hi {
            if s[j] == 93 {
                var k = j + 1
                var n = 0
                while k < hi && s[k] == 61 { n += 1; k += 1 }
                if n == level && at(k) == 93 { return k + 1 }
            }
            j += 1
        }
        return hi
    }

    mutating func hashRule(_ i: inout Int, _ atLineStart: Bool) -> Bool {
        let n = at(i + 1)
        if (spec.rustAttributes && (n == 91 || (n == 33 && at(i + 2) == 91))) || (spec.phpAttributes && n == 91) {
            let open = n == 91 ? i + 1 : i + 2
            var e = L.matchingClose(open, open: 91, close: 93, limit: open + 4_000)
            if at(e - 1) != 93 { e = L.lineEnd(i) }
            emit(i, e, .attribute)
            i = e
            prev = .op
            return true
        }
        if spec.preprocessor && atLineStart {
            let w = L.skipBlanks(i + 1)
            let we = L.identEnd(w)
            if L.word(w, we, is: "region") || L.word(w, we, is: "endregion") || L.word(w, we, is: "pragma")
                || L.word(w, we, is: "error") || L.word(w, we, is: "warning") || L.word(w, we, is: "line") {
                let e = L.lineEnd(i)
                emit(i, e, .attribute)
                i = e
                return true
            }
            emit(i, we, .attribute)
            i = we
            if L.word(w, we, is: "include") || L.word(w, we, is: "import") || L.word(w, we, is: "include_next") {
                let k = L.skipBlanks(we)
                if at(k) == 60 {
                    let le = L.lineEnd(k)
                    var e = k + 1
                    while e < le && s[e] != 62 { e += 1 }
                    e = Swift.min(e + 1, le)
                    emit(k, e, .string)
                    i = e
                }
            }
            prev = .op
            return true
        }
        if spec.swiftPound {
            if n == 34 || n == 35 {
                var h = 0
                while at(i + h) == 35 { h += 1 }
                guard at(i + h) == 34 else { return false }
                let a = i
                var close = [UInt16]()
                var j = i + h
                if at(j + 1) == 34 && at(j + 2) == 34 {
                    close = SyntaxCodeLexer.tdq
                    j += 3
                } else {
                    close = SyntaxCodeLexer.dq
                    j += 1
                }
                close += Array(repeating: 35, count: h)
                var o = StringOptions(close: close)
                o.multiline = close.count > h + 1
                o.interpolation = .swift
                o.rawHashes = h
                i = j
                lexString(a, &i, o)
                prev = .value
                return true
            }
            if SyntaxChar.isIdentStart(n) {
                let e = L.identEnd(i + 1)
                emit(i, e, .keyword)
                i = e
                prev = .op
                return true
            }
        }
        if spec.hashPrivate && SyntaxChar.isIdentStart(n) {
            let e = L.identEnd(i + 1)
            emit(i, e, .variable)
            i = e
            prev = .value
            return true
        }
        return false
    }

    // MARK: - Strings

    mutating func lexString(_ a: Int, _ i: inout Int, _ o: StringOptions) {
        var seg = a
        let c0 = o.close[0]
        while i < hi {
            let c = s[i]
            if c == 10 && !o.multiline { break }
            if c == c0 && L.has(i, o.close) {
                if o.nix, at(i + 2) == 39 || at(i + 2) == 36 || at(i + 2) == 92 {
                    emit(seg, i, o.kind)
                    emit(i, i + 3, .escape)
                    i += 3
                    seg = i
                    continue
                }
                if o.doubled && o.close.count == 1 && at(i + 1) == c0 {
                    i += 2
                    continue
                }
                i += o.close.count
                emit(seg, i, o.kind)
                return
            }
            if c == o.escapeChar && (o.escapes || o.limitedEscapes) {
                var j = i + 1
                if o.rawHashes > 0 {
                    var h = 0
                    while h < o.rawHashes && at(j + h) == 35 { h += 1 }
                    if h < o.rawHashes { i += 1; continue }
                    j += h
                }
                if j >= hi { i = hi; break }
                let n = s[j]
                if o.interpolation == .swift && n == 40 {
                    interpolate(&seg, &i, openStart: i, openEnd: j + 1, closer: 41, opener: 40, o)
                    continue
                }
                if o.limitedEscapes {
                    if n == 92 || n == c0 {
                        emit(seg, i, o.kind)
                        emit(i, j + 1, .escape)
                        i = j + 1
                        seg = i
                    } else {
                        i += 1
                    }
                    continue
                }
                if n == 10 && !o.multiline {
                    i = j + 1
                    continue
                }
                let e = o.escapeChar == 92 ? L.escapeEnd(j) : j + 1
                emit(seg, i, o.kind)
                emit(i, e, .escape)
                i = e
                seg = e
                continue
            }
            switch o.interpolation {
            case .dollarBrace, .dollarBraceIdent:
                if c == 36 {
                    let n = at(i + 1)
                    if n == 123 {
                        interpolate(&seg, &i, openStart: i, openEnd: i + 2, closer: 125, opener: 123, o)
                        continue
                    }
                    if o.interpolation == .dollarBraceIdent && SyntaxChar.isIdentStart(n) {
                        let e = L.identEnd(i + 1)
                        emit(seg, i, o.kind)
                        emit(i, e, .variable)
                        i = e
                        seg = e
                        continue
                    }
                }
            case .dollarBraceVariable:
                if c == 36 && at(i + 1) == 123 {
                    let e = L.matchingClose(i + 1, open: 123, close: 125, multiline: false)
                    emit(seg, i, o.kind)
                    emit(i, e, .variable)
                    i = e
                    seg = e
                    continue
                }
            case .hashBrace:
                if c == 35 && at(i + 1) == 123 {
                    interpolate(&seg, &i, openStart: i, openEnd: i + 2, closer: 125, opener: 123, o)
                    continue
                }
            case .brace:
                if c == 123 {
                    if at(i + 1) == 123 {
                        emit(seg, i, o.kind)
                        emit(i, i + 2, .escape)
                        i += 2
                        seg = i
                        continue
                    }
                    interpolate(&seg, &i, openStart: i, openEnd: i + 1, closer: 125, opener: 123, o)
                    continue
                }
                if c == 125 && at(i + 1) == 125 {
                    emit(seg, i, o.kind)
                    emit(i, i + 2, .escape)
                    i += 2
                    seg = i
                    continue
                }
            case .php:
                if c == 36 && SyntaxChar.isIdentStart(at(i + 1)) {
                    var e = L.identEnd(i + 1)
                    if at(e) == 45 && at(e + 1) == 62 && SyntaxChar.isIdentStart(at(e + 2)) { e = L.identEnd(e + 2) }
                    emit(seg, i, o.kind)
                    emit(i, e, .variable)
                    i = e
                    seg = e
                    continue
                }
                if c == 123 && at(i + 1) == 36 {
                    interpolate(&seg, &i, openStart: i, openEnd: i + 1, closer: 125, opener: 123, o)
                    continue
                }
            case .perl:
                if (c == 36 || c == 64) && (SyntaxChar.isIdentStart(at(i + 1)) || (c == 36 && at(i + 1) == 123)) {
                    var e = i + 1
                    if at(e) == 123 {
                        e = L.matchingClose(e, open: 123, close: 125, multiline: false)
                    } else {
                        e = L.identEnd(e)
                        while at(e) == 58 && at(e + 1) == 58 && SyntaxChar.isIdentStart(at(e + 2)) { e = L.identEnd(e + 2) }
                    }
                    emit(seg, i, o.kind)
                    emit(i, e, .variable)
                    i = e
                    seg = e
                    continue
                }
            case .julia:
                if c == 36 {
                    if at(i + 1) == 40 {
                        interpolate(&seg, &i, openStart: i, openEnd: i + 2, closer: 41, opener: 40, o)
                        continue
                    }
                    if SyntaxChar.isIdentStart(at(i + 1)) {
                        let e = L.identEnd(i + 1)
                        emit(seg, i, o.kind)
                        emit(i, e, .variable)
                        i = e
                        seg = e
                        continue
                    }
                }
            case .none, .swift:
                break
            }
            i += 1
        }
        emit(seg, i, o.kind)
    }

    /// Emits the delimiter, lexes the embedded expression as code, then resumes the string.
    mutating func interpolate(_ seg: inout Int, _ i: inout Int, openStart: Int, openEnd: Int, closer: UInt16, opener: UInt16, _ o: StringOptions) {
        guard nesting < 8 else {
            i = openEnd
            return
        }
        emit(seg, openStart, o.kind)
        emit(openStart, openEnd, .keyword)
        i = openEnd
        let saved = (prev, pendingDef, lineStart, prevIdent)
        prev = .op
        pendingDef = 0
        nesting += 1
        let formatSpec = o.interpolation == .brace
        run(&i, closer: closer, opener: opener, stopAtNewline: !o.multiline, formatSpec: formatSpec)
        nesting -= 1
        (prev, pendingDef, lineStart, prevIdent) = saved
        if formatSpec && i < hi && (s[i] == 58 || s[i] == 33) {
            var j = i
            var depth = 0
            while j < hi {
                let d = s[j]
                if d == 10 && !o.multiline { break }
                if d == 123 { depth += 1 } else if d == 125 {
                    if depth == 0 { break }
                    depth -= 1
                }
                j += 1
            }
            emit(i, j, o.kind)
            i = j
        }
        if i < hi && s[i] == closer {
            emit(i, i + 1, .keyword)
            i += 1
        }
        seg = i
    }

    mutating func doubleQuoted(_ i: inout Int, from a: Int) {
        var o = StringOptions(close: SyntaxCodeLexer.dq)
        o.escapes = spec.escapes
        o.interpolation = spec.interpolation
        o.doubled = spec.doubledQuotes
        o.multiline = spec.multilineStrings
        if spec.tripleDouble && at(i + 1) == 34 && at(i + 2) == 34 {
            o.close = SyntaxCodeLexer.tdq
            o.multiline = true
            o.doubled = false
            i += 3
        } else {
            i += 1
        }
        lexString(a, &i, o)
        prev = .value
        prevIdent = false
        pendingDef = 0
    }

    mutating func singleQuote(_ i: inout Int) -> Bool {
        let a = i
        switch spec.singleQuote {
        case .none:
            return false
        case .string, .limited:
            var o = StringOptions(close: SyntaxCodeLexer.sq)
            o.escapes = spec.escapes && spec.singleQuote == .string
            o.limitedEscapes = spec.escapes && spec.singleQuote == .limited
            o.doubled = spec.doubledQuotes
            o.multiline = spec.multilineStrings
            o.interpolation = spec.singleQuoteInterpolates ? spec.interpolation : .none
            if spec.tripleSingle && at(i + 1) == 39 && at(i + 2) == 39 {
                o.close = SyntaxCodeLexer.tsq
                o.multiline = true
                o.doubled = false
                i += 3
            } else {
                i += 1
            }
            lexString(a, &i, o)
        case .char:
            i += 1
            var o = StringOptions(close: SyntaxCodeLexer.sq)
            o.escapes = spec.escapes
            lexString(a, &i, o)
        case .rust:
            let n = at(i + 1)
            if n == 92 {
                i += 1
                lexString(a, &i, StringOptions(close: SyntaxCodeLexer.sq))
            } else if n != 0 && n != 39 && n != 10 {
                let w = (n >= 0xD800 && n < 0xDC00) ? 2 : 1
                if at(i + 1 + w) == 39 {
                    emit(i, i + 2 + w, .string)
                    i += 2 + w
                } else if SyntaxChar.isIdentStart(n) {
                    let e = L.identEnd(i + 1)
                    emit(i, e, .keyword)
                    i = e
                } else {
                    return false
                }
            } else {
                return false
            }
        case .ml:
            let n = at(i + 1)
            if n == 92 {
                i += 1
                lexString(a, &i, StringOptions(close: SyntaxCodeLexer.sq))
            } else if n != 0 && n != 39 && n != 10 && at(i + 2) == 39 {
                emit(i, i + 3, .string)
                i += 3
            } else if SyntaxChar.isIdentStart(n) {
                let e = L.identEnd(i + 1)
                emit(i, e, .type)
                i = e
            } else {
                return false
            }
        case .nixIndented:
            guard at(i + 1) == 39 else { return false }
            var o = StringOptions(close: [39, 39])
            o.escapes = false
            o.multiline = true
            o.interpolation = .dollarBrace
            o.nix = true
            i += 2
            lexString(a, &i, o)
        case .transpose:
            if i > lo {
                let p = s[i - 1]
                if SyntaxChar.isIdentPart(p) || p == 41 || p == 93 || p == 125 || p == 39 || p == 46 { return false }
            }
            i += 1
            var o = StringOptions(close: SyntaxCodeLexer.sq)
            o.escapes = spec.escapes
            o.doubled = spec.doubledQuotes
            lexString(a, &i, o)
        }
        prev = .value
        prevIdent = false
        return true
    }

    mutating func backtick(_ i: inout Int) -> Bool {
        let a = i
        switch spec.backtick {
        case .none:
            return false
        case .template:
            var o = StringOptions(close: SyntaxCodeLexer.bt)
            o.multiline = true
            o.interpolation = .dollarBrace
            i += 1
            lexString(a, &i, o)
        case .raw:
            var o = StringOptions(close: SyntaxCodeLexer.bt)
            o.multiline = true
            o.escapes = false
            i += 1
            lexString(a, &i, o)
        case .identifier:
            let le = L.lineEnd(i)
            var e = i + 1
            while e < le && s[e] != 96 { e += 1 }
            guard e < le else { return false }
            i = e + 1
        case .command:
            var o = StringOptions(close: SyntaxCodeLexer.bt)
            o.multiline = true
            o.interpolation = spec.interpolation
            i += 1
            lexString(a, &i, o)
        }
        prev = .value
        prevIdent = false
        return true
    }

    /// String literal introduced by an identifier prefix (`f"…"`, `r#"…"#`, `R"x(…)x"`, `s"…"`).
    mutating func prefixedString(_ a: Int, _ b: Int, _ i: inout Int) -> Bool {
        let q = s[b]
        let length = b - a
        var o = StringOptions(close: q == 39 ? SyntaxCodeLexer.sq : SyntaxCodeLexer.dq)
        o.multiline = spec.multilineStrings
        o.doubled = spec.doubledQuotes
        switch spec.prefixes {
        case .none:
            return false
        case .python:
            guard length <= 2, q == 34 || q == 39 else { return false }
            var raw = false, formatted = false
            for k in a..<b {
                switch SyntaxChar.lower(s[k]) {
                case 114: raw = true
                case 102, 116: formatted = true
                case 98, 117: break
                default: return false
                }
            }
            o.escapes = !raw
            o.limitedEscapes = raw
            o.interpolation = formatted ? .brace : .none
        case .rust:
            let w = L.string(a, b)
            guard ["r", "b", "br", "c", "cr"].contains(w) else { return false }
            if w.contains("r") {
                var h = 0
                while at(b + h) == 35 { h += 1 }
                guard at(b + h) == 34 else { return false }
                o.close = SyntaxCodeLexer.dq + Array(repeating: 35, count: h)
                o.escapes = false
                o.multiline = true
                i = b + h + 1
                lexString(a, &i, o)
                return true
            }
            guard q == 34 || (q == 39 && w == "b") else { return false }
            o.multiline = q == 34
        case .cpp:
            let w = L.string(a, b)
            if w.hasSuffix("R") && q == 34 && ["R", "LR", "uR", "UR", "u8R"].contains(w) {
                var j = b + 1
                while j < hi && j < b + 18 && s[j] != 40 && !SyntaxChar.isSpace(s[j]) && s[j] != 92 && s[j] != 41 { j += 1 }
                guard at(j) == 40 else { return false }
                o.close = [41] + L.units(b + 1, j) + [34]
                o.escapes = false
                o.multiline = true
                i = j + 1
                lexString(a, &i, o)
                return true
            }
            guard ["L", "u", "U", "u8"].contains(w), q == 34 || q == 39 else { return false }
        case .dart:
            guard length == 1, s[a] == 114, q == 34 || q == 39 else { return false }
            o.escapes = false
        case .scala:
            guard q == 34 else { return false }
            o.escapes = !L.word(a, b, is: "raw")
            o.interpolation = .dollarBraceIdent
        case .sql:
            guard length <= 2, q == 39 else { return false }
            let w = L.string(a, b).uppercased()
            guard ["N", "E", "X", "B", "U", "R"].contains(w) else { return false }
            o.escapes = w == "E"
            o.doubled = true
        case .nim:
            guard q == 34 else { return false }
            o.escapes = false
            o.doubled = true
        case .julia:
            guard q == 34 else { return false }
            if L.word(a, b, is: "r") { o.kind = .regex }
            o.escapes = !L.word(a, b, is: "raw")
        }
        if q == 34 && at(b + 1) == 34 && at(b + 2) == 34 && (spec.tripleDouble || spec.prefixes == .python) {
            o.close = SyntaxCodeLexer.tdq
            o.multiline = true
            o.doubled = false
            i = b + 3
        } else if q == 39 && at(b + 1) == 39 && at(b + 2) == 39 && spec.tripleSingle {
            o.close = SyntaxCodeLexer.tsq
            o.multiline = true
            o.doubled = false
            i = b + 3
        } else {
            i = b + 1
        }
        lexString(a, &i, o)
        return true
    }

    // MARK: - Sigils and prefixes

    mutating func atSign(_ i: inout Int, _ atLineStart: Bool) -> Bool {
        let n = at(i + 1)
        switch spec.at {
        case .none:
            return false
        case .attribute, .decorator:
            if spec.at == .decorator && !atLineStart { return false }
            guard SyntaxChar.isIdentStart(n) else { return false }
            var e = L.identEnd(i + 1)
            while (at(e) == 46 || at(e) == 58) && SyntaxChar.isIdentStart(at(e + 1)) { e = L.identEnd(e + 1) }
            emit(i, e, .attribute)
            i = e
            prev = .op
            return true
        case .objc:
            if n == 34 {
                let a = i
                i += 2
                lexString(a, &i, StringOptions(close: SyntaxCodeLexer.dq))
                prev = .value
                return true
            }
            if SyntaxChar.isIdentStart(n) {
                let e = L.identEnd(i + 1)
                let kind = spec.words.kind(s, i, e) ?? .keyword
                emit(i, e, kind)
                i = e
                prev = .op
                return true
            }
            if n == 91 || n == 123 || n == 40 || SyntaxChar.isDigit(n) {
                emit(i, i + 1, .keyword)
                i += 1
                prev = .op
                return true
            }
            return false
        case .variable:
            var e = i + 1
            if at(e) == 64 { e += 1 }
            guard SyntaxChar.isIdentStart(at(e)) else { return false }
            e = L.identEnd(e)
            emit(i, e, .variable)
            i = e
            prev = .value
            return true
        case .zig:
            if n == 34 {
                let a = i
                i += 2
                lexString(a, &i, StringOptions(close: SyntaxCodeLexer.dq))
                prev = .value
                return true
            }
            guard SyntaxChar.isIdentStart(n) else { return false }
            let e = L.identEnd(i + 1)
            emit(i, e, .function)
            i = e
            prev = .value
            return true
        case .csharp:
            var j = i + 1
            var interpolated = false
            if at(j) == 36 { interpolated = true; j += 1 }
            guard at(j) == 34 else {
                if SyntaxChar.isIdentStart(n) {
                    let e = L.identEnd(i + 1)
                    i = e
                    prev = .value
                    return true
                }
                return false
            }
            var o = StringOptions(close: SyntaxCodeLexer.dq)
            o.escapes = false
            o.doubled = true
            o.multiline = true
            o.interpolation = interpolated ? .brace : .none
            let a = i
            i = j + 1
            lexString(a, &i, o)
            prev = .value
            return true
        }
    }

    mutating func dollar(_ i: inout Int) -> Bool {
        let n = at(i + 1)
        var e = i + 1
        switch spec.dollar {
        case .none:
            return false
        case .variable:
            while at(e) == 36 { e += 1 }
            guard SyntaxChar.isIdentPart(at(e)) else { return false }
            e = L.identEnd(e)
        case .perl:
            if n == 35 { e += 1 }
            if SyntaxChar.isIdentStart(at(e)) {
                e = L.identEnd(e)
                while at(e) == 58 && at(e + 1) == 58 && SyntaxChar.isIdentStart(at(e + 2)) { e = L.identEnd(e + 2) }
            } else if SyntaxChar.isDigit(at(e)) {
                while SyntaxChar.isDigit(at(e)) { e += 1 }
            } else if at(e) == 123 {
                e = L.matchingClose(e, open: 123, close: 125, multiline: false)
            } else if n != 0 && !SyntaxChar.isSpace(n) && "&`'+!@/\\,;.0<>[]$^_".utf16.contains(n) {
                e = i + 2
            } else {
                return false
            }
        case .swift:
            guard SyntaxChar.isIdentPart(n) else { return false }
            e = L.identEnd(i + 1)
        case .awk:
            if SyntaxChar.isIdentPart(n) { e = L.identEnd(i + 1) } else { e = i + 1 }
        case .csharp:
            var j = i + 1
            var verbatim = false
            if at(j) == 64 { verbatim = true; j += 1 }
            var dollars = 0
            if at(j) == 36 { dollars = 1; j += 1 }
            guard at(j) == 34 else { return false }
            var o = StringOptions(close: SyntaxCodeLexer.dq)
            o.interpolation = .brace
            if at(j + 1) == 34 && at(j + 2) == 34 {
                o.close = SyntaxCodeLexer.tdq
                o.escapes = false
                o.multiline = true
                j += 2
            } else if verbatim {
                o.escapes = false
                o.doubled = true
                o.multiline = true
            }
            _ = dollars
            let a = i
            i = j + 1
            lexString(a, &i, o)
            prev = .value
            return true
        case .cmake:
            if n == 123 {
                e = L.matchingClose(i + 1, open: 123, close: 125, multiline: false)
            } else if n == 60 {
                e = L.matchingClose(i + 1, open: 60, close: 62, multiline: false)
            } else if SyntaxChar.isUpper(n) {
                let w = L.identEnd(i + 1)
                guard at(w) == 123 else { return false }
                e = L.matchingClose(w, open: 123, close: 125, multiline: false)
            } else {
                return false
            }
        }
        emit(i, e, .variable)
        i = e
        prev = .value
        prevIdent = false
        return true
    }

    mutating func colonSymbol(_ i: inout Int) -> Bool {
        guard spec.symbols else { return false }
        let n = at(i + 1)
        if n == 58 { return false }
        if i > lo {
            let p = s[i - 1]
            if p == 58 || SyntaxChar.isIdentPart(p) || p == 41 || p == 93 || p == 125 || p == 34 || p == 39 { return false }
        }
        if SyntaxChar.isIdentStart(n) {
            var e = L.identEnd(i + 1)
            if (at(e) == 63 || at(e) == 33) && at(e + 1) != 61 && spec.identQuestion { e += 1 }
            emit(i, e, .constant)
            i = e
            prev = .value
            return true
        }
        if n == 34 {
            let a = i
            i += 2
            var o = StringOptions(close: SyntaxCodeLexer.dq)
            o.kind = .constant
            lexString(a, &i, o)
            prev = .value
            return true
        }
        return false
    }

    mutating func question(_ i: inout Int) -> Bool {
        let n = at(i + 1)
        switch spec.question {
        case .none:
            return false
        case .elixirChar:
            guard prev != .value, n != 0, !SyntaxChar.isSpace(n) else { return false }
            var e = i + 2
            if n == 92 { e = L.escapeEnd(i + 2) } else if n >= 0xD800 && n < 0xDC00 { e = i + 3 }
            emit(i, e, .string)
            i = e
        case .erlangMacro:
            guard SyntaxChar.isIdentStart(n) else { return false }
            let e = L.identEnd(i + 1)
            emit(i, e, .constant)
            i = e
        }
        prev = .value
        return true
    }

    mutating func regexLiteral(_ i: inout Int, _ atLineStart: Bool) -> Bool {
        guard spec.regex != .none else { return false }
        var allowed = prev != .value || atLineStart
        if !allowed && spec.regex == .ruby && prevIdent && i > lo && SyntaxChar.isBlank(s[i - 1]) && !SyntaxChar.isSpace(at(i + 1)) && at(i + 1) != 61 {
            allowed = true
        }
        guard allowed else { return false }
        var j = i + 1
        var inClass = false
        let limit = Swift.min(hi, i + 1_000)
        while j < limit {
            let c = s[j]
            if c == 10 { return false }
            if c == 92 { j += 2; continue }
            if c == 91 { inClass = true } else if c == 93 { inClass = false } else if c == 47 && !inClass { break }
            j += 1
        }
        guard j < limit, j > i + 1, !SyntaxChar.isBlank(s[i + 1]) else { return false }
        j += 1
        while j < hi && SyntaxChar.isLetter(s[j]) { j += 1 }
        emit(i, j, .regex)
        i = j
        prev = .value
        prevIdent = false
        return true
    }

    mutating func angle(_ i: inout Int) -> Bool {
        if spec.jsx && jsx(&i) { return true }
        if spec.heredoc != .none && at(i + 1) == 60 && heredocStart(&i) { return true }
        if spec.nixPaths && SyntaxChar.isIdentStart(at(i + 1)) {
            var j = i + 1
            while j < hi && (SyntaxChar.isIdentPart(s[j]) || s[j] == 47 || s[j] == 46 || s[j] == 45) { j += 1 }
            if at(j) == 62 {
                emit(i, j + 1, .string)
                i = j + 1
                prev = .value
                return true
            }
        }
        if spec.vimScopes && SyntaxChar.isLetter(at(i + 1)) {
            var j = i + 1
            while j < hi && (SyntaxChar.isIdentPart(s[j]) || s[j] == 45) { j += 1 }
            if at(j) == 62 {
                emit(i, j + 1, .constant)
                i = j + 1
                prev = .value
                return true
            }
        }
        return false
    }

    /// Ruby `%w[...]`/`%r{...}` literals and Perl `%hash` variables.
    mutating func percent(_ i: inout Int) -> Bool {
        if spec.percentOperators {
            var e = i + 1
            let limit = Swift.min(hi, i + 16)
            while e < limit && s[e] != 37 && s[e] != 10 && !SyntaxChar.isBlank(s[e]) { e += 1 }
            guard at(e) == 37 else { return false }
            emit(i, e + 1, .keyword)
            i = e + 1
            prev = .op
            return true
        }
        guard prev != .value else { return false }
        if spec.dollar == .perl {
            guard SyntaxChar.isIdentStart(at(i + 1)) else { return false }
            let e = L.identEnd(i + 1)
            emit(i, e, .variable)
            i = e
            prev = .value
            return true
        }
        guard spec.percentLiterals else { return false }
        var j = i + 1
        var kind = SyntaxTokenKind.string
        let n = at(j)
        if "qQwWiIrsx".utf16.contains(n) && !SyntaxChar.isAlnum(at(j + 1)) {
            if n == 114 { kind = .regex }
            if n == 115 { kind = .constant }
            j += 1
        }
        let d = at(j)
        guard d != 0, !SyntaxChar.isAlnum(d), !SyntaxChar.isSpace(d), d != 61 else { return false }
        let e = delimitedEnd(j)
        var k = e
        if kind == .regex { while k < hi && SyntaxChar.isLetter(s[k]) { k += 1 } }
        emit(i, k, kind)
        i = k
        prev = .value
        return true
    }

    /// End of a delimited literal whose opening delimiter is at `j` (brackets nest; others repeat).
    func delimitedEnd(_ j: Int) -> Int {
        let d = s[j]
        let close: UInt16
        switch d {
        case 40: close = 41
        case 91: close = 93
        case 123: close = 125
        case 60: close = 62
        default: close = d
        }
        var depth = 1
        var k = j + 1
        while k < hi {
            let c = s[k]
            if c == 92 { k += 2; continue }
            if c == close {
                depth -= 1
                if depth == 0 { return k + 1 }
            } else if c == d && close != d {
                depth += 1
            }
            k += 1
        }
        return hi
    }

    /// Elixir sigils: `~r/.../i`, `~s(...)`, `~w[...]a`, `~S"""..."""`.
    mutating func sigil(_ i: inout Int) -> Bool {
        guard spec.sigils else { return false }
        var j = i + 1
        let first = at(j)
        guard SyntaxChar.isLetter(first) else { return false }
        if SyntaxChar.isLower(first) { j += 1 } else { while SyntaxChar.isUpper(at(j)) { j += 1 } }
        let d = at(j)
        guard "/|\"'([{<".utf16.contains(d) else { return false }
        var e: Int
        if (d == 34 || d == 39) && at(j + 1) == d && at(j + 2) == d {
            let a = j + 3
            e = hi
            var k = a
            while k + 2 < hi {
                if s[k] == d && s[k + 1] == d && s[k + 2] == d { e = k + 3; break }
                k += 1
            }
        } else {
            e = delimitedEnd(j)
        }
        while e < hi && SyntaxChar.isLetter(s[e]) { e += 1 }
        emit(i, e, (first == 114 || first == 82) ? .regex : .string)
        i = e
        prev = .value
        return true
    }

    mutating func bracket(_ i: inout Int, _ atLineStart: Bool) -> Bool {
        if spec.luaLongBrackets, let e = luaLongEnd(i) {
            emit(i, e, .string)
            i = e
            prev = .value
            return true
        }
        if spec.fsharpAttributes && at(i + 1) == 60 {
            let le = L.lineEnd(i)
            var e = i + 2
            while e + 1 < le && !(s[e] == 62 && s[e + 1] == 93) { e += 1 }
            e = Swift.min(e + 2, le)
            emit(i, e, .attribute)
            i = e
            return true
        }
        if spec.csharpAttributes && atLineStart && SyntaxChar.isUpper(at(i + 1)) {
            var e = L.identEnd(i + 1)
            while at(e) == 46 && SyntaxChar.isIdentStart(at(e + 1)) { e = L.identEnd(e + 1) }
            let n = at(e)
            guard n == 40 || n == 93 || n == 44 || n == 58 else { return false }
            emit(i + 1, e, .attribute)
            i = e
            prev = .op
            return true
        }
        return false
    }

    mutating func dot(_ i: inout Int) -> Bool {
        let n = at(i + 1)
        if SyntaxChar.isDigit(n) && prev != .value && spec.numbers {
            let e = numberEnd(i)
            emit(i, e, .number)
            i = e
            prev = .value
            return true
        }
        if spec.fortranDots && SyntaxChar.isLetter(n) {
            var e = i + 1
            while SyntaxChar.isLetter(at(e)) { e += 1 }
            if at(e) == 46, let kind = spec.words.kind(s, i, e + 1) {
                emit(i, e + 1, kind)
                i = e + 1
                prev = kind == .constant ? .value : .op
                return true
            }
        }
        if spec.nixPaths && (n == 47 || (n == 46 && at(i + 2) == 47)) && prev != .value {
            var e = i + 1
            while e < hi && (SyntaxChar.isIdentPart(s[e]) || s[e] == 47 || s[e] == 46 || s[e] == 45 || s[e] == 43) { e += 1 }
            emit(i, e, .string)
            i = e
            prev = .value
            return true
        }
        return false
    }

    // MARK: - Numbers and identifiers

    func numberEnd(_ start: Int) -> Int {
        var j = start
        if s[j] == 48 && j + 1 < hi {
            let n = s[j + 1] | 0x20
            if n == 120 && SyntaxChar.isHex(at(j + 2)) {
                j += 2
                while j < hi && (SyntaxChar.isHex(s[j]) || s[j] == 95) { j += 1 }
                if at(j) == 46 && SyntaxChar.isHex(at(j + 1)) {
                    j += 1
                    while j < hi && SyntaxChar.isHex(s[j]) { j += 1 }
                }
                if (at(j) | 0x20) == 112 { j = exponentEnd(j) }
                return suffixEnd(j)
            }
            if (n == 98 || n == 111) && SyntaxChar.isDigit(at(j + 2)) {
                j += 2
                while j < hi && (SyntaxChar.isDigit(s[j]) || s[j] == 95) { j += 1 }
                return suffixEnd(j)
            }
        }
        j = digitsEnd(j)
        if spec.erlangBase && at(j) == 35 && SyntaxChar.isAlnum(at(j + 1)) {
            j += 1
            while j < hi && SyntaxChar.isAlnum(s[j]) { j += 1 }
            return j
        }
        if at(j) == 46 && SyntaxChar.isDigit(at(j + 1)) {
            j = digitsEnd(j + 1)
        }
        let e = at(j) | 0x20
        if e == 101 || (spec.fortranExponent && (e == 100 || e == 113)) {
            j = exponentEnd(j)
        }
        return suffixEnd(j)
    }

    func digitsEnd(_ start: Int) -> Int {
        var j = start
        while j < hi {
            let c = s[j]
            if SyntaxChar.isDigit(c) || (c == 95 && SyntaxChar.isDigit(at(j + 1))) {
                j += 1
            } else if c == 39 && spec.cppDigitSeparators && SyntaxChar.isHex(at(j + 1)) && j > start {
                j += 1
            } else {
                break
            }
        }
        return j
    }

    func exponentEnd(_ j: Int) -> Int {
        var k = j + 1
        if at(k) == 43 || at(k) == 45 { k += 1 }
        guard SyntaxChar.isDigit(at(k)) else { return j }
        while SyntaxChar.isDigit(at(k)) || at(k) == 95 { k += 1 }
        return k
    }

    func suffixEnd(_ j: Int) -> Int {
        var k = j
        while k < hi && SyntaxChar.isIdentPart(s[k]) { k += 1 }
        return k
    }

    mutating func identifier(_ i: inout Int, _ atLineStart: Bool) {
        let a = i
        var j = i + 1
        while j < hi {
            let c = s[j]
            if SyntaxChar.isIdentPart(c) { j += 1; continue }
            if c == 36 && spec.identDollar { j += 1; continue }
            if c == 39 && spec.identPrime { j += 1; continue }
            if c == 45 && spec.identDash && j + 1 < hi && SyntaxChar.isIdentStart(s[j + 1]) { j += 1; continue }
            if c == 46 && spec.identDot && j + 1 < hi && SyntaxChar.isIdentStart(s[j + 1]) { j += 1; continue }
            break
        }
        if j < hi {
            let c = s[j]
            if (c == 63 && spec.identQuestion) || (c == 33 && spec.identBang) {
                let n = at(j + 1)
                if n != 61 && n != 58 && !(c == 63 && n == 63) { j += 1 }
            }
        }
        var b = j
        i = b
        if b < hi {
            let q = s[b]
            if (q == 34 || q == 39 || q == 35) && spec.prefixes != .none && prefixedString(a, b, &i) {
                prev = .value
                prevIdent = false
                pendingDef = 0
                return
            }
            if spec.perlQuoteOperators && perlQuote(a, b, &i) {
                prev = .value
                prevIdent = false
                return
            }
        }
        let next = at(b)
        let afterDot = memberAccess(a)
        var kind = SyntaxTokenKind.plain
        var role: UInt8 = 0
        if let entry = spec.words.lookup(s, a, b) {
            if afterDot && entry.role & SyntaxWordTable.afterDot == 0 {
                // `obj.default`, `re.match`: keywords used as member names
            } else if entry.role & SyntaxWordTable.soft != 0 && !softKeywordApplies(atLineStart, b) {
                // soft keyword used as an identifier
            } else if entry.role & SyntaxWordTable.contextual != 0 && !contextualKeywordApplies(b) {
                // contextual keyword used as a name: `get(key)`, `type: string`
            } else {
                kind = entry.kind
                role = entry.role
            }
        }
        if spec.macroBang && next == 33 && at(b + 1) != 61 {
            b += 1
            i = b
            if kind == .plain { kind = .function }
        }
        if spec.labelSymbols && next == 58 && at(b + 1) != 58 && (b + 1 >= hi || SyntaxChar.isSpace(s[b + 1])) && kind != .constant {
            b += 1
            i = b
            kind = .constant
        } else if kind == .plain {
            if pendingDef != 0 && next != 46 {
                kind = pendingDef == 1 ? .function : .type
            } else if next == 40 && spec.callHeuristic {
                kind = (spec.capitalizedCallIsType && !afterDot && SyntaxChar.isUpper(s[a])) ? .type : .function
            } else if next == 96 && spec.backtick == .template {
                kind = .function
            } else if spec.objcSelectors && next == 58 && at(b + 1) != 58 {
                kind = .function
            } else if spec.assignmentKeys && isAssignment(b) {
                kind = .property
            } else if spec.signatureFunctions && atLineStart && isTypeSignature(b) {
                kind = .function
            } else if spec.vimScopes && next == 58 && b == a + 1 && "gslabwtv".utf16.contains(s[a]) && SyntaxChar.isIdentStart(at(b + 1)) {
                b = L.identEnd(b + 1)
                i = b
                kind = .variable
            } else if spec.allCapsConstants && isAllCaps(a, b) {
                kind = .constant
            } else if let capitalized = spec.capitalized, SyntaxChar.isUpper(s[a]), !(afterDot && spec.capitalizedMembersPlain) {
                kind = capitalized
            }
        }
        emit(a, b, kind)
        if kind == .keyword {
            if role & SyntaxWordTable.defineFunction != 0 {
                pendingDef = 1
            } else if role & SyntaxWordTable.defineType != 0 {
                pendingDef = 2
            } else if !(pendingDef != 0 && next == 46) {
                pendingDef = 0
            }
            prev = role & SyntaxWordTable.value != 0 ? .value : .op
            prevIdent = false
        } else {
            if !(pendingDef != 0 && next == 46) { pendingDef = 0 }
            prev = .value
            prevIdent = true
        }
    }

    func memberAccess(_ a: Int) -> Bool {
        guard a > lo else { return false }
        let p = s[a - 1]
        if p == 46 { return !(a - 2 >= lo && s[a - 2] == 46) }
        if spec.arrowMemberAccess && p == 62 && a - 2 >= lo && s[a - 2] == 45 { return true }
        return false
    }

    func softKeywordApplies(_ atLineStart: Bool, _ b: Int) -> Bool {
        guard atLineStart else { return false }
        let n = at(b)
        if n == 40 || n == 46 { return false }
        let k = L.skipBlanks(b)
        let c = at(k)
        if c == 0 || c == 10 || c == 44 || c == 41 || c == 58 || c == 93 { return false }
        if c == 61 && at(k + 1) != 61 { return false }
        return true
    }

    func contextualKeywordApplies(_ b: Int) -> Bool {
        if at(b) == 40 { return false }
        let k = L.skipBlanks(b)
        let c = at(k)
        if c == 61 { return at(k + 1) == 61 || at(k + 1) == 62 }
        if c == 58 { return at(k + 1) == 58 }
        return !(c == 44 || c == 41 || c == 59 || c == 46 || c == 93 || c == 63 || c == 125)
    }

    func isAssignment(_ b: Int) -> Bool {
        let k = L.skipBlanks(b)
        return at(k) == 61 && at(k + 1) != 61 && at(k + 1) != 62
    }

    func isTypeSignature(_ b: Int) -> Bool {
        let k = L.skipBlanks(b)
        if spec.signatureSingleColon { return at(k) == 58 && at(k + 1) != 58 }
        return at(k) == 58 && at(k + 1) == 58
    }

    func isAllCaps(_ a: Int, _ b: Int) -> Bool {
        guard b - a >= 2 else { return false }
        var upper = 0
        for k in a..<b {
            let c = s[k]
            if SyntaxChar.isUpper(c) { upper += 1 } else if !(SyntaxChar.isDigit(c) || c == 95) { return false }
        }
        return upper >= 2 || (upper == 1 && b - a >= 3 && s[a] != 95 && SyntaxChar.isUpper(s[a]) && s[a + 1] == 95)
    }

    /// Perl quote-like operators: `q(...)`, `qw/.../`, `m{...}`, `s/a/b/g`, `tr/a-z/A-Z/`.
    mutating func perlQuote(_ a: Int, _ b: Int, _ i: inout Int) -> Bool {
        let d = s[b]
        guard !SyntaxChar.isAlnum(d), !SyntaxChar.isSpace(d), d != 61, d != 44, d != 59, d != 41, d != 45, d != 95, d != 58 else { return false }
        let two: Bool
        let kind: SyntaxTokenKind
        if L.word(a, b, is: "s") || L.word(a, b, is: "tr") || L.word(a, b, is: "y") {
            two = true
            kind = .regex
        } else if L.word(a, b, is: "m") || L.word(a, b, is: "qr") {
            two = false
            kind = .regex
        } else if L.word(a, b, is: "q") || L.word(a, b, is: "qq") || L.word(a, b, is: "qw") || L.word(a, b, is: "qx") {
            two = false
            kind = .string
        } else {
            return false
        }
        if d == 62 || d == 41 || d == 93 || d == 125 { return false }
        var e = delimitedEnd(b)
        if two && e < hi {
            let bracketed = d == 40 || d == 91 || d == 123 || d == 60
            if bracketed {
                let k = L.skipSpace(e)
                if k < hi && !SyntaxChar.isAlnum(s[k]) && !SyntaxChar.isSpace(s[k]) { e = delimitedEnd(k) }
            } else {
                var k = e
                while k < hi {
                    if s[k] == 92 { k += 2; continue }
                    if s[k] == d { k += 1; break }
                    k += 1
                }
                e = Swift.min(k, hi)
            }
        }
        while e < hi && SyntaxChar.isLetter(s[e]) { e += 1 }
        emit(a, e, kind)
        i = e
        return true
    }

    // MARK: - Heredocs

    mutating func heredocStart(_ i: inout Int) -> Bool {
        var j = i + 2
        var indented = false
        switch spec.heredoc {
        case .none:
            return false
        case .php:
            guard at(j) == 60 else { return false }
            j = L.skipBlanks(j + 1)
            indented = true
        case .ruby, .perl:
            if at(j) == 126 || at(j) == 45 { indented = true; j += 1 }
        case .hcl:
            if at(j) == 45 { indented = true; j += 1 }
            indented = true
        }
        var quote: UInt16 = 0
        if at(j) == 34 || at(j) == 39 { quote = s[j]; j += 1 }
        let ts = j
        guard SyntaxChar.isIdentStart(at(j)) else { return false }
        j = L.identEnd(j)
        let te = j
        if quote != 0 {
            guard at(j) == quote else { return false }
            j += 1
        } else if spec.heredoc == .ruby || spec.heredoc == .perl, !(at(i + 2) == 126 || at(i + 2) == 45) {
            for k in ts..<te where SyntaxChar.isLower(s[k]) { return false }
        }
        emit(i, j, .string)
        heredocs.append(Heredoc(tag: L.units(ts, te), indented: indented, interpolates: quote != 39))
        i = j
        prev = .value
        return true
    }

    /// Called just after a newline: consumes pending heredoc bodies up to their terminator lines.
    mutating func readHeredocs(_ i: inout Int) {
        let pending = heredocs
        heredocs.removeAll()
        for (index, doc) in pending.enumerated() {
            if index > 0 && i < hi && s[i] == 10 { i += 1 }
            let bodyStart = i
            var bodyEnd = hi
            var terminatorEnd = hi
            while i < hi {
                let le = L.lineEnd(i)
                let k = doc.indented ? L.skipBlanks(i) : i
                if L.has(k, doc.tag) && (k + doc.tag.count >= le || !SyntaxChar.isIdentPart(s[k + doc.tag.count])) {
                    bodyEnd = i
                    terminatorEnd = le
                    break
                }
                i = le < hi ? le + 1 : hi
            }
            if doc.interpolates && spec.interpolation != .none && nesting < 8 && bodyEnd > bodyStart {
                var body = SyntaxCodeLexer(L.sub(bodyStart, bodyEnd), spec)
                body.nesting = nesting + 1
                var j = bodyStart
                var o = StringOptions(close: [0])
                o.multiline = true
                o.interpolation = spec.interpolation
                body.lexString(bodyStart, &j, o)
            } else {
                emit(bodyStart, bodyEnd, .string)
            }
            emit(bodyEnd, terminatorEnd, .string)
            i = terminatorEnd
        }
    }

    // MARK: - JSX

    enum JSXTag { case open, selfClosing }

    mutating func jsx(_ i: inout Int) -> Bool {
        guard prev != .value, nesting < 4 else { return false }
        let n = at(i + 1)
        guard n == 62 || SyntaxChar.isLetter(n) else { return false }
        let mark = L.sink.mark()
        let saved = (prev, pendingDef, prevIdent)
        var j = i
        guard let first = jsxTag(&j, requireClosing: true) else {
            L.sink.rollback(mark)
            (prev, pendingDef, prevIdent) = saved
            return false
        }
        if first == .open {
            var depth = 1
            while j < hi && depth > 0 {
                let c = s[j]
                if c == 123 {
                    jsxExpression(&j)
                    continue
                }
                if c == 60 {
                    let m = at(j + 1)
                    if m == 47 {
                        var k = L.skipSpace(j + 2)
                        let ns = k
                        while k < hi && isJSXNameChar(s[k]) { k += 1 }
                        emit(j, j + 2, .punctuation)
                        emit(ns, k, jsxNameKind(ns, k))
                        k = L.skipSpace(k)
                        if at(k) == 62 {
                            emit(k, k + 1, .punctuation)
                            k += 1
                        }
                        depth -= 1
                        j = k
                        continue
                    }
                    if m == 62 || SyntaxChar.isLetter(m) {
                        var k = j
                        if let tag = jsxTag(&k, requireClosing: false) {
                            if tag == .open { depth += 1 }
                            j = k
                            continue
                        }
                    }
                    j += 1
                    continue
                }
                if c == 38 {
                    var k = j + 1
                    while k < hi && k < j + 10 && (SyntaxChar.isAlnum(s[k]) || s[k] == 35) { k += 1 }
                    if at(k) == 59 && k > j + 1 {
                        emit(j, k + 1, .escape)
                        j = k + 1
                        continue
                    }
                }
                j += 1
            }
        }
        i = j
        prev = .value
        prevIdent = false
        pendingDef = 0
        return true
    }

    func isJSXNameChar(_ c: UInt16) -> Bool { SyntaxChar.isIdentPart(c) || c == 45 || c == 46 || c == 58 || c == 36 }

    func jsxNameKind(_ a: Int, _ b: Int) -> SyntaxTokenKind {
        guard a < b else { return .tag }
        if SyntaxChar.isUpper(s[a]) { return .type }
        for k in a..<b where s[k] == 46 { return .type }
        return .tag
    }

    mutating func jsxClosingNames() -> Set<[UInt16]> {
        if let names = jsxClosers { return names }
        var names = Set<[UInt16]>()
        var j = lo
        while j + 1 < hi {
            if s[j] == 60 && s[j + 1] == 47 {
                var k = j + 2
                while k < hi && isJSXNameChar(s[k]) { k += 1 }
                names.insert(L.units(j + 2, k))
                j = k
            } else {
                j += 1
            }
        }
        jsxClosers = names
        return names
    }

    mutating func jsxExpression(_ j: inout Int) {
        emit(j, j + 1, .punctuation)
        j += 1
        let saved = (prev, pendingDef, lineStart, prevIdent)
        prev = .op
        nesting += 1
        run(&j, closer: 125, opener: 123, stopAtNewline: false)
        nesting -= 1
        (prev, pendingDef, lineStart, prevIdent) = saved
        if j < hi {
            emit(j, j + 1, .punctuation)
            j += 1
        }
    }

    /// Parses `<name attr=…>` or `<name … />` at `j`. With `requireClosing`, an open tag is only accepted
    /// when a matching `</name` exists somewhere, which keeps TypeScript generics (`<T>(x: T) =>`) intact.
    mutating func jsxTag(_ j: inout Int, requireClosing: Bool) -> JSXTag? {
        let a = j
        var k = j + 1
        if at(k) == 62 {
            if requireClosing && !jsxClosingNames().contains([]) { return nil }
            emit(a, k + 1, .punctuation)
            j = k + 1
            return .open
        }
        let ns = k
        while k < hi && isJSXNameChar(s[k]) { k += 1 }
        let ne = k
        if requireClosing {
            let closable = jsxClosingNames().contains(L.units(ns, ne))
            if !closable && !jsxLooksSelfClosing(ne) { return nil }
        }
        emit(a, a + 1, .punctuation)
        emit(ns, ne, jsxNameKind(ns, ne))
        while true {
            k = L.skipSpace(k)
            guard k < hi else {
                if requireClosing { return nil }
                j = k
                return .open
            }
            let c = s[k]
            if c == 62 {
                emit(k, k + 1, .punctuation)
                k += 1
                if requireClosing && !jsxClosingNames().contains(L.units(ns, ne)) { return nil }
                j = k
                return .open
            }
            if c == 47 && at(k + 1) == 62 {
                emit(k, k + 2, .punctuation)
                j = k + 2
                return .selfClosing
            }
            if c == 123 {
                jsxExpression(&k)
                continue
            }
            if SyntaxChar.isIdentStart(c) {
                let an = k
                while k < hi && (isJSXNameChar(s[k])) { k += 1 }
                emit(an, k, .attribute)
                let eq = L.skipSpace(k)
                if at(eq) == 61 {
                    k = L.skipSpace(eq + 1)
                    let v = at(k)
                    if v == 34 || v == 39 {
                        let e = L.quotedEnd(k, quote: v, escapes: false, multiline: true)
                        emit(k, e, .string)
                        k = e
                    } else if v == 123 {
                        jsxExpression(&k)
                    } else {
                        return nil
                    }
                }
                continue
            }
            return nil
        }
    }

    /// Cheap scan for `/>` before the next `>` (bounded), used when no closing tag exists.
    func jsxLooksSelfClosing(_ from: Int) -> Bool {
        var k = from
        var braces = 0
        let limit = Swift.min(hi, from + 2000)
        while k < limit {
            let c = s[k]
            if c == 123 { braces += 1 } else if c == 125 { braces -= 1 } else if (c == 34 || c == 39) && braces == 0 {
                k = L.quotedEnd(k, quote: c, escapes: false, multiline: true)
                continue
            } else if c == 62 && braces <= 0 {
                return k > from && s[k - 1] == 47
            } else if c == 60 && braces <= 0 {
                return false
            }
            k += 1
        }
        return false
    }
}
