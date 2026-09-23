import Foundation

extension SyntaxLexer {
    // MARK: - JSON

    /// JSON / JSONC / JSON5 / JSON Lines. Strings followed by `:` are keys (`.property`).
    func lexJSON(_ flavor: SyntaxJSONFlavor) {
        var i = lo
        while i < hi {
            let c = s[i]
            switch c {
            case 34, 39:
                let e = quotedEnd(i, quote: c)
                emitEscaped(i, e, jsonIsKey(e) ? .property : .string)
                i = e
            case 47 where at(i + 1) == 47:
                let e = lineEnd(i)
                emit(i, e, .comment)
                i = e
            case 47 where at(i + 1) == 42:
                let e = (find("*/", from: i + 2)).map { $0 + 2 } ?? hi
                emit(i, e, .comment)
                i = e
            case 35 where flavor == .json5:
                let e = lineEnd(i)
                emit(i, e, .comment)
                i = e
            default:
                if SyntaxChar.isDigit(c) || ((c == 45 || c == 43 || c == 46) && (SyntaxChar.isDigit(at(i + 1)) || at(i + 1) == 46 || at(i + 1) == 73)) {
                    var e = i + 1
                    while e < hi && (SyntaxChar.isAlnum(s[e]) || s[e] == 46 || s[e] == 95 || ((s[e] == 45 || s[e] == 43) && (s[e - 1] | 0x20) == 101)) { e += 1 }
                    emit(i, e, jsonIsKey(e) ? .property : .number)
                    i = e
                } else if SyntaxChar.isIdentStart(c) || c == 36 {
                    var e = i + 1
                    while e < hi && (SyntaxChar.isIdentPart(s[e]) || s[e] == 36 || s[e] == 45) { e += 1 }
                    let kind: SyntaxTokenKind
                    if jsonIsKey(e) {
                        kind = .property
                    } else if word(i, e, is: "true") || word(i, e, is: "false") || word(i, e, is: "null")
                        || word(i, e, is: "Infinity") || word(i, e, is: "NaN") || word(i, e, is: "undefined") {
                        kind = .constant
                    } else {
                        kind = .plain
                    }
                    emit(i, e, kind)
                    i = e
                } else {
                    i += 1
                }
            }
        }
    }

    /// Whether the next significant character after `e` is a key separator `:`.
    func jsonIsKey(_ e: Int) -> Bool {
        var j = e
        while j < hi {
            let c = s[j]
            if SyntaxChar.isSpace(c) { j += 1; continue }
            if c == 47 && at(j + 1) == 42, let close = find("*/", from: j + 2) { j = close + 2; continue }
            return c == 58
        }
        return false
    }

    // MARK: - YAML

    func lexYAML() {
        var i = lo
        var lineStart = true
        var keyPosition = true
        var flow = 0
        var lineIndent = 0
        var keyColumn = 0
        var blockParent: Int? = nil
        var pendingBlock: Int? = nil
        var lineBegin = lo
        while i < hi {
            if lineStart {
                lineStart = false
                let ls = i
                lineBegin = i
                let k = skipBlanks(i)
                lineIndent = k - ls
                keyColumn = lineIndent
                if let parent = pendingBlock {
                    blockParent = parent
                    pendingBlock = nil
                }
                if let parent = blockParent {
                    if at(k) == 10 || k >= hi {
                        i = k
                        continue
                    }
                    if lineIndent > parent {
                        let e = lineEnd(k)
                        emit(k, e, .string)
                        i = e
                        continue
                    }
                    blockParent = nil
                }
                keyPosition = flow == 0
                if lineIndent == 0 && flow == 0 {
                    if (has(k, "---") || has(k, "...")) && (k + 3 >= hi || SyntaxChar.isSpace(at(k + 3))) {
                        emit(k, k + 3, .keyword)
                        i = k + 3
                        continue
                    }
                    if at(k) == 37 { // %YAML / %TAG directives
                        let e = lineEnd(k)
                        emit(k, e, .attribute)
                        i = e
                        continue
                    }
                }
                i = k
                continue
            }
            let c = s[i]
            if c == 10 {
                lineStart = true
                i += 1
                continue
            }
            if SyntaxChar.isBlank(c) { i += 1; continue }
            if c == 35 && (i == lo || SyntaxChar.isSpace(s[i - 1])) {
                let e = lineEnd(i)
                emit(i, e, .comment)
                i = e
                continue
            }
            let n = at(i + 1)
            let separated = n == 0 || SyntaxChar.isSpace(n)
            if keyPosition && flow == 0 && (c == 45 || c == 63) && separated {
                emit(i, i + 1, .punctuation)
                keyColumn = i - lineBegin
                i += 1
                continue
            }
            if c == 34 || c == 39 {
                var e = i + 1
                while e < hi {
                    let d = s[e]
                    if d == c {
                        if c == 39 && at(e + 1) == 39 { e += 2; continue }
                        e += 1
                        break
                    }
                    if d == 92 && c == 34 { e += 2; continue }
                    e += 1
                }
                e = Swift.min(e, hi)
                let key = yamlKeyFollows(e, flow: flow)
                if key {
                    if c == 34 { emitEscaped(i, e, .property) } else { emit(i, e, .property) }
                } else {
                    emitTemplated(i, e, .string, escapes: c == 34)
                }
                if key {
                    keyColumn = i - lineBegin
                    i = skipBlanks(e) + 1
                } else {
                    i = e
                }
                keyPosition = false
                continue
            }
            if (c == 38 || c == 42) && SyntaxChar.isIdentPart(n) { // &anchor / *alias
                var e = i + 1
                while e < hi && !SyntaxChar.isSpace(s[e]) && s[e] != 44 && s[e] != 93 && s[e] != 125 { e += 1 }
                emit(i, e, .variable)
                i = e
                continue
            }
            if c == 33 { // !tag
                var e = i + 1
                while e < hi && !SyntaxChar.isSpace(s[e]) { e += 1 }
                emit(i, e, .attribute)
                i = e
                continue
            }
            if (c == 124 || c == 62) && flow == 0 {
                var e = i + 1
                while e < hi && (s[e] == 43 || s[e] == 45 || SyntaxChar.isDigit(s[e])) { e += 1 }
                let k = skipBlanks(e)
                if k >= hi || s[k] == 10 || s[k] == 35 {
                    emit(i, e, .keyword)
                    pendingBlock = keyColumn
                    i = e
                    continue
                }
            }
            if c == 91 || c == 123 {
                flow += 1
                keyPosition = c == 123
                i += 1
                continue
            }
            if c == 93 || c == 125 {
                flow = Swift.max(0, flow - 1)
                keyPosition = false
                i += 1
                continue
            }
            if c == 44 && flow > 0 {
                keyPosition = true
                i += 1
                continue
            }
            if c == 58 && separated {
                keyPosition = false
                i += 1
                continue
            }
            // Plain scalar: key if followed by `: `, otherwise a value up to ` #` / end of line.
            var e = i
            var keyEnd: Int? = nil
            while e < hi {
                let d = s[e]
                if d == 10 { break }
                if d == 35 && e > i && SyntaxChar.isBlank(s[e - 1]) { break }
                if d == 58 {
                    let m = at(e + 1)
                    if m == 0 || SyntaxChar.isSpace(m) || (flow > 0 && (m == 44 || m == 93 || m == 125)) {
                        keyEnd = e
                        break
                    }
                }
                if flow > 0 && (d == 44 || d == 93 || d == 125) { break }
                e += 1
            }
            if let ke = keyEnd {
                emit(i, trimEnd(i, ke), .property)
                keyColumn = i - lineBegin
                i = ke + 1
                keyPosition = false
                continue
            }
            let ve = trimEnd(i, e)
            let kind = yamlScalarKind(i, ve)
            if kind == .string { emitTemplated(i, ve, .string) } else { emit(i, ve, kind) }
            i = Swift.max(e, i + 1)
            keyPosition = false
        }
    }

    /// Emits `a..<b` as `kind`, with `${{ … }}` / `{{ … }}` template expressions as `.variable`.
    func emitTemplated(_ a: Int, _ b: Int, _ kind: SyntaxTokenKind, escapes: Bool = false) {
        var seg = a
        var j = a
        while j + 1 < b {
            if s[j] == 123 && s[j + 1] == 123 {
                let start = j > a && s[j - 1] == 36 ? j - 1 : j
                var e = j + 2
                while e + 1 < b && !(s[e] == 125 && s[e + 1] == 125) { e += 1 }
                e = Swift.min(e + 2, b)
                if escapes { emitEscaped(seg, start, kind) } else { emit(seg, start, kind) }
                emit(start, e, .variable)
                j = e
                seg = e
                continue
            }
            j += 1
        }
        if escapes { emitEscaped(seg, b, kind) } else { emit(seg, b, kind) }
    }

    func yamlKeyFollows(_ e: Int, flow: Int) -> Bool {
        let k = skipBlanks(e)
        guard at(k) == 58 else { return false }
        let m = at(k + 1)
        return m == 0 || SyntaxChar.isSpace(m) || (flow > 0 && (m == 44 || m == 125))
    }

    func yamlScalarKind(_ a: Int, _ b: Int) -> SyntaxTokenKind {
        guard b > a else { return .plain }
        let w = b - a
        if w <= 5 {
            let v = string(a, b)
            switch v {
            case "true", "false", "True", "False", "TRUE", "FALSE", "yes", "no", "Yes", "No", "YES", "NO", "on", "off",
                 "On", "Off", "ON", "OFF", "null", "Null", "NULL", "~":
                return .constant
            case ".inf", ".Inf", ".INF", "-.inf", ".nan", ".NaN", ".NAN":
                return .number
            default: break
            }
        }
        var j = a
        if s[j] == 45 || s[j] == 43 { j += 1 }
        guard j < b, SyntaxChar.isDigit(s[j]) || (s[j] == 46 && j + 1 < b && SyntaxChar.isDigit(s[j + 1])) else { return .string }
        var sawSpace = false
        for k in j..<b {
            let c = s[k]
            if c == 32 { sawSpace = true; continue }
            if !(SyntaxChar.isAlnum(c) || c == 46 || c == 95 || c == 45 || c == 43 || c == 58) { return .string }
        }
        if sawSpace { return .string }
        // Plain numbers, hex/octal, and ISO dates/times.
        for k in j..<b where SyntaxChar.isLetter(s[k]) {
            let l = s[k] | 0x20
            if !(l == 101 || l == 120 || l == 111 || (SyntaxChar.isHex(s[k]) && s[j] == 48) || l == 116 || l == 122) { return .string }
        }
        return .number
    }

    // MARK: - TOML

    func lexTOML() {
        var i = lo
        var keyPosition = true
        var brackets: [UInt16] = []
        while i < hi {
            let c = s[i]
            if c == 10 {
                if brackets.isEmpty { keyPosition = true }
                i += 1
                continue
            }
            if SyntaxChar.isBlank(c) { i += 1; continue }
            if c == 35 {
                let e = lineEnd(i)
                emit(i, e, .comment)
                i = e
                continue
            }
            if c == 91 && keyPosition && brackets.isEmpty {
                let le = lineEnd(i)
                var e = i
                let double = at(i + 1) == 91
                while e < le && s[e] != 93 {
                    if s[e] == 34 || s[e] == 39 { e = Swift.min(quotedEnd(e, quote: s[e]), le); continue }
                    e += 1
                }
                e = Swift.min(e + (double ? 2 : 1), le)
                emit(i, e, .type)
                i = e
                continue
            }
            if keyPosition && (SyntaxChar.isIdentPart(c) || c == 45 || c == 34 || c == 39) {
                // Dotted / quoted key up to `=`.
                var e = i
                while e < hi && s[e] != 61 && s[e] != 10 {
                    if s[e] == 34 || s[e] == 39 { e = quotedEnd(e, quote: s[e]); continue }
                    e += 1
                }
                if at(e) == 61 {
                    emit(i, trimEnd(i, e), .property)
                    i = e + 1
                    keyPosition = false
                    continue
                }
                keyPosition = false
            }
            if c == 34 || c == 39 {
                let triple = at(i + 1) == c && at(i + 2) == c
                var e: Int
                if triple {
                    e = hi
                    var k = i + 3
                    while k + 2 < hi {
                        if c == 34 && s[k] == 92 { k += 2; continue }
                        if s[k] == c && s[k + 1] == c && s[k + 2] == c {
                            e = k + 3
                            while at(e) == c && e < k + 5 { e += 1 }
                            break
                        }
                        k += 1
                    }
                } else {
                    e = quotedEnd(i, quote: c, escapes: c == 34)
                }
                if c == 34 { emitEscaped(i, e, .string) } else { emit(i, e, .string) }
                i = e
                continue
            }
            if c == 91 || c == 123 {
                brackets.append(c)
                keyPosition = c == 123
                i += 1
                continue
            }
            if c == 93 || c == 125 {
                if !brackets.isEmpty { brackets.removeLast() }
                keyPosition = false
                i += 1
                continue
            }
            if c == 44 {
                keyPosition = brackets.last == 123
                i += 1
                continue
            }
            if SyntaxChar.isAlnum(c) || c == 43 || c == 45 || c == 46 {
                var e = i
                while e < hi && (SyntaxChar.isAlnum(s[e]) || s[e] == 95 || s[e] == 45 || s[e] == 43 || s[e] == 46 || s[e] == 58
                                 || (s[e] == 32 && SyntaxChar.isDigit(at(e + 1)) && e > i && SyntaxChar.isDigit(s[e - 1]) && at(e + 3) == 58)) {
                    e += 1
                }
                let kind: SyntaxTokenKind
                if word(i, e, is: "true") || word(i, e, is: "false") {
                    kind = .constant
                } else if SyntaxChar.isDigit(c) || c == 43 || c == 45 || word(i, e, is: "inf") || word(i, e, is: "nan") {
                    kind = .number
                } else {
                    kind = .plain
                }
                emit(i, e, kind)
                i = Swift.max(e, i + 1)
                continue
            }
            i += 1
        }
    }

    // MARK: - INI / properties / .env

    func lexINI(_ flavor: SyntaxINIFlavor) {
        var i = lo
        while i < hi {
            let le = lineEnd(i)
            let k = skipBlanks(i)
            let c = at(k)
            if k >= le {
                i = le + 1
                continue
            }
            if c == 59 || c == 35 || (flavor == .properties && c == 33) {
                emit(k, le, .comment)
                i = le + 1
                continue
            }
            if c == 91 && flavor != .properties {
                var e = k
                while e < le && s[e] != 93 { e += 1 }
                e = Swift.min(e + 1, le)
                emit(k, e, .type)
                let r = skipBlanks(e)
                if r < le && (s[r] == 59 || s[r] == 35) { emit(r, le, .comment) }
                i = le + 1
                continue
            }
            var j = k
            if flavor == .dotenv && has(j, "export") && SyntaxChar.isBlank(at(j + 6)) {
                emit(j, j + 6, .keyword)
                j = skipBlanks(j + 6)
            }
            // Key up to `=` or `:` (properties also accept whitespace).
            var e = j
            while e < le {
                let d = s[e]
                if d == 61 || (d == 58 && flavor != .dotenv) { break }
                if d == 92 { e += 2; continue }
                if flavor == .properties && SyntaxChar.isBlank(d) {
                    let n = skipBlanks(e)
                    if n < le && (s[n] == 61 || s[n] == 58) { e = n }
                    break
                }
                e += 1
            }
            e = Swift.min(e, le)
            guard e < le || flavor == .properties else {
                i = le + 1
                continue
            }
            emit(j, trimEnd(j, e), .property)
            var v = skipBlanks(Swift.min(e + 1, le))
            if e >= le { v = le }
            var valueEnd = le
            // Continuation lines (`\` at end of line).
            while flavor == .properties && valueEnd > v && s[valueEnd - 1] == 92 && valueEnd < hi {
                valueEnd = lineEnd(valueEnd + 1)
            }
            // Inline comments after whitespace (INI/.env).
            var comment: (Int, Int)? = nil
            if flavor != .properties {
                var q = v
                var quote: UInt16 = 0
                while q < valueEnd {
                    let d = s[q]
                    if quote != 0 {
                        if d == quote { quote = 0 }
                    } else if d == 34 || d == 39 {
                        quote = d
                    } else if (d == 35 || d == 59) && q > v && SyntaxChar.isBlank(s[q - 1]) {
                        comment = (q, valueEnd)
                        valueEnd = trimEnd(v, q)
                        break
                    }
                    q += 1
                }
            }
            lexINIValue(v, trimEnd(v, valueEnd), flavor: flavor)
            if let comment { emit(comment.0, comment.1, .comment) }
            i = le + 1
            if valueEnd > le { i = valueEnd + 1 }
        }
    }

    func lexINIValue(_ a: Int, _ b: Int, flavor: SyntaxINIFlavor) {
        guard b > a else { return }
        let v = string(a, b)
        let lower = v.lowercased()
        if ["true", "false", "yes", "no", "on", "off", "null", "none"].contains(lower) {
            emit(a, b, .constant)
            return
        }
        if Double(v) != nil || (v.hasPrefix("0x") && v.count > 2) {
            emit(a, b, .number)
            return
        }
        var seg = a
        var j = a
        while j < b {
            let c = s[j]
            if c == 36 && (at(j + 1) == 123 || SyntaxChar.isIdentStart(at(j + 1))) {
                let e = at(j + 1) == 123 ? Swift.min(matchingClose(j + 1, open: 123, close: 125, multiline: false), b) : identEnd(j + 1)
                emit(seg, j, .string)
                emit(j, e, .variable)
                j = e
                seg = e
                continue
            }
            if c == 37 && at(j + 1) == 40 { // %(interpolation)s
                var e = j + 2
                while e < b && s[e] != 41 { e += 1 }
                e = Swift.min(e + 2, b)
                emit(seg, j, .string)
                emit(j, e, .variable)
                j = e
                seg = e
                continue
            }
            if c == 92 && flavor == .properties && j + 1 < b {
                emit(seg, j, .string)
                let e = escapeEnd(j + 1)
                emit(j, e, .escape)
                j = e
                seg = e
                continue
            }
            j += 1
        }
        emit(seg, b, .string)
    }
}
