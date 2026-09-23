import Foundation

extension SyntaxLexer {
    /// CSS, SCSS, Sass (indented) and Less. Statements are classified as selector or declaration by
    /// looking ahead to the first `{`, `;` or `}` at paren depth 0.
    func lexCSS(_ flavor: SyntaxCSSFlavor) {
        var i = lo
        var depth = 0
        while i < hi {
            let c = s[i]
            if SyntaxChar.isSpace(c) { i += 1; continue }
            if c == 47 && at(i + 1) == 42 {
                i = cssBlockComment(i)
                continue
            }
            if c == 47 && at(i + 1) == 47 && flavor != .css {
                let e = lineEnd(i)
                emit(i, e, .comment)
                i = e
                continue
            }
            if c == 123 { depth += 1; i += 1; continue }
            if c == 125 { depth = Swift.max(0, depth - 1); i += 1; continue }
            if c == 59 { i += 1; continue }
            let end = cssStatementEnd(i, sass: flavor == .sass)
            if c == 64 { // @rule
                let e = cssIdentEnd(i + 1)
                if flavor == .less && at(skipBlanks(e)) == 58 {
                    emit(i, e, .variable)
                    lexCSSValue(skipBlanks(e) + 1, end, prelude: false)
                } else {
                    emit(i, e, .keyword)
                    lexCSSValue(e, end, prelude: true)
                }
                i = Swift.max(end, i + 1)
                continue
            }
            let terminator = at(end)
            let declaration: Bool
            if flavor == .sass {
                declaration = cssLooksLikeDeclaration(i, end, strict: true)
            } else if terminator == 123 {
                declaration = false
            } else {
                declaration = depth > 0 || c == 36 || cssLooksLikeDeclaration(i, end, strict: true)
            }
            if declaration {
                lexCSSDeclaration(i, end)
            } else {
                lexCSSSelector(i, end)
            }
            i = Swift.max(end, i + 1)
        }
    }

    func cssBlockComment(_ i: Int) -> Int {
        let e = (find("*/", from: i + 2)).map { $0 + 2 } ?? hi
        emit(i, e, .comment)
        return e
    }

    func cssIdentEnd(_ i: Int) -> Int {
        var j = i
        while j < hi {
            let c = s[j]
            if SyntaxChar.isIdentPart(c) || c == 45 { j += 1 } else if c == 92 && j + 1 < hi { j += 2 } else { break }
        }
        return j
    }

    func cssStatementEnd(_ i: Int, sass: Bool) -> Int {
        var j = i
        var parens = 0
        while j < hi {
            let c = s[j]
            switch c {
            case 34, 39:
                j = quotedEnd(j, quote: c)
                continue
            case 47:
                if at(j + 1) == 42 {
                    j = (find("*/", from: j + 2)).map { $0 + 2 } ?? hi
                    continue
                }
            case 35:
                if at(j + 1) == 123 {
                    j = matchingClose(j + 1, open: 123, close: 125, multiline: false)
                    continue
                }
            case 40: parens += 1
            case 41: parens = Swift.max(0, parens - 1)
            case 123, 125, 59:
                if parens == 0 { return j }
            case 10:
                if sass && parens == 0 { return j }
            default: break
            }
            j += 1
        }
        return hi
    }

    func cssLooksLikeDeclaration(_ a: Int, _ b: Int, strict: Bool) -> Bool {
        var j = a
        if at(j) == 36 || at(j) == 64 || at(j) == 43 || at(j) == 61 { return true }
        if at(j) == 45 && at(j + 1) == 45 { return true }
        while j < b && (SyntaxChar.isIdentPart(s[j]) || s[j] == 45) { j += 1 }
        guard j > a else { return false }
        j = skipBlanks(j)
        guard at(j) == 58, at(j + 1) != 58 else { return false }
        let n = at(j + 1)
        return !strict || n == 32 || n == 9 || n == 10 || j + 1 >= b || at(j + 1) == 36 || SyntaxChar.isDigit(n)
    }

    func lexCSSSelector(_ a: Int, _ b: Int) {
        var j = a
        while j < b {
            let c = s[j]
            switch c {
            case 47 where at(j + 1) == 42:
                j = Swift.min(cssBlockComment(j), b)
            case 47 where at(j + 1) == 47:
                let e = Swift.min(lineEnd(j), b)
                emit(j, e, .comment)
                j = e
            case 34, 39:
                let e = Swift.min(quotedEnd(j, quote: c), b)
                emit(j, e, .string)
                j = e
            case 46, 37: // .class, %placeholder
                let e = cssIdentEnd(j + 1)
                if e > j + 1 {
                    emit(j, e, .type)
                    j = e
                } else {
                    j += 1
                }
            case 35: // #id or #{interpolation}
                if at(j + 1) == 123 {
                    let e = matchingClose(j + 1, open: 123, close: 125, multiline: false)
                    emit(j, e, .variable)
                    j = e
                } else {
                    let e = cssIdentEnd(j + 1)
                    emit(j, e, .constant)
                    j = Swift.max(e, j + 1)
                }
            case 58: // :pseudo / ::pseudo
                var k = j + 1
                if at(k) == 58 { k += 1 }
                let e = cssIdentEnd(k)
                if e > k { emit(j, e, .keyword) }
                j = Swift.max(e, j + 1)
            case 91: // [attr=value]
                let close = Swift.min(matchingClose(j, open: 91, close: 93, multiline: false), b)
                var k = j + 1
                let ne = cssIdentEnd(k)
                emit(k, ne, .attribute)
                k = ne
                while k < close {
                    let d = s[k]
                    if d == 34 || d == 39 {
                        let e = Swift.min(quotedEnd(k, quote: d), close)
                        emit(k, e, .string)
                        k = e
                    } else if SyntaxChar.isIdentStart(d) {
                        let e = cssIdentEnd(k)
                        emit(k, e, .string)
                        k = e
                    } else {
                        k += 1
                    }
                }
                j = close
            case 38, 42: // & and *
                emit(j, j + 1, c == 38 ? .keyword : .tag)
                j += 1
            case 36:
                let e = cssIdentEnd(j + 1)
                emit(j, e, .variable)
                j = Swift.max(e, j + 1)
            default:
                if SyntaxChar.isDigit(c) {
                    var e = j
                    while e < b && (SyntaxChar.isDigit(s[e]) || s[e] == 46 || s[e] == 37) { e += 1 }
                    emit(j, e, .number)
                    j = e
                } else if SyntaxChar.isIdentStart(c) || c == 45 {
                    let e = cssIdentEnd(j)
                    emit(j, e, .tag)
                    j = Swift.max(e, j + 1)
                } else {
                    j += 1
                }
            }
        }
    }

    func lexCSSDeclaration(_ a: Int, _ b: Int) {
        let j = skipSpace(a)
        var nameEnd = j
        var kind = SyntaxTokenKind.property
        if at(j) == 36 || at(j) == 64 {
            nameEnd = cssIdentEnd(j + 1)
            kind = .variable
        } else if at(j) == 45 && at(j + 1) == 45 {
            nameEnd = cssIdentEnd(j)
            kind = .variable
        } else if SyntaxChar.isIdentStart(at(j)) || at(j) == 45 || at(j) == 42 {
            nameEnd = cssIdentEnd(at(j) == 42 ? j + 1 : j)
        }
        let colon = skipBlanks(nameEnd)
        if nameEnd > j && at(colon) == 58 && colon < b {
            emit(j, nameEnd, kind)
            lexCSSValue(colon + 1, b, prelude: false)
        } else {
            lexCSSValue(a, b, prelude: false)
        }
    }

    func lexCSSValue(_ a: Int, _ b: Int, prelude: Bool) {
        var j = a
        while j < b {
            let c = s[j]
            if SyntaxChar.isSpace(c) { j += 1; continue }
            switch c {
            case 47 where at(j + 1) == 42:
                j = Swift.min(cssBlockComment(j), b)
                continue
            case 47 where at(j + 1) == 47 && (j == a || SyntaxChar.isSpace(s[j - 1])):
                let e = Swift.min(lineEnd(j), b)
                emit(j, e, .comment)
                j = e
                continue
            case 34, 39:
                let e = Swift.min(quotedEnd(j, quote: c), b)
                emitEscaped(j, e, .string)
                j = e
                continue
            case 35:
                if at(j + 1) == 123 {
                    let e = Swift.min(matchingClose(j + 1, open: 123, close: 125, multiline: false), b)
                    emit(j, e, .variable)
                    j = e
                    continue
                }
                let e = cssIdentEnd(j + 1)
                var hex = e > j + 1
                for k in (j + 1)..<Swift.max(e, j + 1) where !SyntaxChar.isHex(s[k]) { hex = false }
                emit(j, e, hex ? .number : .constant)
                j = Swift.max(e, j + 1)
                continue
            case 33:
                let e = cssIdentEnd(j + 1)
                if e > j + 1 { emit(j, e, .keyword) }
                j = Swift.max(e, j + 1)
                continue
            case 36:
                let e = cssIdentEnd(j + 1)
                emit(j, e, .variable)
                j = Swift.max(e, j + 1)
                continue
            case 64:
                let e = cssIdentEnd(j + 1)
                emit(j, e, prelude ? .keyword : .variable)
                j = Swift.max(e, j + 1)
                continue
            case 38:
                emit(j, j + 1, .keyword)
                j += 1
                continue
            case 46 where prelude && SyntaxChar.isIdentStart(at(j + 1)):
                let e = cssIdentEnd(j + 1)
                emit(j, e, .type)
                j = e
                continue
            default:
                break
            }
            let prevIsWord = j > lo && (SyntaxChar.isIdentPart(s[j - 1]) || s[j - 1] == 45)
            let signed = (c == 45 || c == 43) && (SyntaxChar.isDigit(at(j + 1)) || (at(j + 1) == 46 && SyntaxChar.isDigit(at(j + 2))))
            if !prevIsWord && (SyntaxChar.isDigit(c) || (c == 46 && SyntaxChar.isDigit(at(j + 1))) || signed) {
                var e = j + 1
                while e < b && (SyntaxChar.isDigit(s[e]) || s[e] == 46) { e += 1 }
                if (at(e) | 0x20) == 101 && (SyntaxChar.isDigit(at(e + 1)) || ((at(e + 1) == 45 || at(e + 1) == 43) && SyntaxChar.isDigit(at(e + 2)))) {
                    e += 2
                    while e < b && SyntaxChar.isDigit(s[e]) { e += 1 }
                }
                while e < b && (SyntaxChar.isLetter(s[e]) || s[e] == 37) { e += 1 }
                emit(j, e, .number)
                j = e
                continue
            }
            if SyntaxChar.isIdentStart(c) || (c == 45 && (SyntaxChar.isIdentStart(at(j + 1)) || at(j + 1) == 45)) {
                let e = cssIdentEnd(j)
                if at(e) == 40 {
                    emit(j, e, .function)
                    if word(j, e, is: "url", ci: true) {
                        let k = skipBlanks(e + 1)
                        if at(k) != 34 && at(k) != 39 {
                            var close = k
                            while close < b && s[close] != 41 { close += 1 }
                            emit(k, close, .string)
                            j = close
                            continue
                        }
                    }
                } else if at(e) == 58 && prelude {
                    emit(j, e, .property)
                } else if prelude {
                    let w = string(j, e)
                    let kind: SyntaxTokenKind = ["and", "not", "only", "or", "from", "through", "to", "in", "if", "else", "as", "with", "using", "layer", "screen", "print", "all"].contains(w) ? .keyword : .constant
                    emit(j, e, kind)
                } else if c == 45 && at(j + 1) == 45 {
                    emit(j, e, .variable)
                } else {
                    emit(j, e, .constant)
                }
                j = Swift.max(e, j + 1)
                continue
            }
            j += 1
        }
    }
}
