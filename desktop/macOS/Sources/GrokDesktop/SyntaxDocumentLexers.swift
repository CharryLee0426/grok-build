import Foundation

extension SyntaxLexer {
    // MARK: - Markdown

    func lexMarkdown() {
        var i = lo
        if has(lo, "---") && (at(lo + 3) == 10 || at(lo + 3) == 13), depth < SyntaxLexer.maxDepth {
            var j = nextLine(lo)
            while j < hi {
                if (has(j, "---") || has(j, "...")) && trimEnd(j, lineEnd(j)) == j + 3 {
                    emit(lo, lo + 3, .punctuation)
                    sub(nextLine(lo), j).lexYAML()
                    emit(j, j + 3, .punctuation)
                    i = nextLine(j)
                    break
                }
                j = nextLine(j)
            }
        }
        var fenceChar: UInt16 = 0
        var fenceCount = 0
        var fenceContent = 0
        var fenceKind: SyntaxLexerKind? = nil
        var fenceIndent = 0
        while i < hi {
            let le = lineEnd(i)
            let k = skipBlanks(i)
            let indent = k - i
            if fenceChar != 0 {
                var n = 0
                while at(k + n) == fenceChar { n += 1 }
                if indent <= fenceIndent + 3 && n >= fenceCount && skipBlanks(k + n) >= le {
                    markdownFenceContent(fenceContent, i, fenceKind)
                    emit(k, le, .punctuation)
                    fenceChar = 0
                }
                i = le + 1
                continue
            }
            guard k < le else {
                i = le + 1
                continue
            }
            let c = s[k]
            if indent <= 12 && (c == 96 || c == 126) {
                var n = 0
                while at(k + n) == c { n += 1 }
                if n >= 3 && (c == 126 || !(k + n..<le).contains(where: { s[$0] == 96 })) {
                    fenceIndent = indent
                    emit(k, k + n, .punctuation)
                    let infoStart = skipBlanks(k + n)
                    let infoEnd = trimEnd(infoStart, le)
                    emit(infoStart, infoEnd, .attribute)
                    fenceChar = c
                    fenceCount = n
                    fenceContent = Swift.min(le + 1, hi)
                    fenceKind = nil
                    if infoEnd > infoStart, let language = SyntaxLanguageRegistry.resolve(string(infoStart, infoEnd)) {
                        fenceKind = SyntaxLanguageRegistry.lexerKind(forId: language.id)
                    }
                    i = le + 1
                    continue
                }
            }
            if indent < 4 && c == 35 {
                var n = 0
                while at(k + n) == 35 { n += 1 }
                if n <= 6 && (k + n >= le || SyntaxChar.isBlank(at(k + n))) {
                    emit(k, le, .heading)
                    i = le + 1
                    continue
                }
            }
            if indent < 4 && (c == 42 || c == 45 || c == 95) && markdownThematicBreak(k, le, c) {
                emit(k, le, .punctuation)
                i = le + 1
                continue
            }
            // Setext heading: a text line followed by `===` or `---`.
            let next = le + 1
            if indent < 4 && next < hi && c != 62 && c != 124 && !markdownListMarker(k, le) {
                let nk = skipBlanks(next)
                let ne = lineEnd(next)
                let u = at(nk)
                if (u == 61 || u == 45) && nk - next < 4 {
                    var q = nk
                    while q < ne && s[q] == u { q += 1 }
                    if skipBlanks(q) >= ne && (u == 61 || q - nk >= 2) {
                        emit(k, le, .heading)
                        emit(nk, ne, .heading)
                        i = ne + 1
                        continue
                    }
                }
            }
            var j = k
            while at(j) == 62 {
                emit(j, j + 1, .keyword)
                j = at(j + 1) == 32 ? j + 2 : j + 1
            }
            j = skipBlanks(j)
            if markdownListMarker(j, le) {
                var e = j
                while SyntaxChar.isDigit(at(e)) { e += 1 }
                e += 1
                emit(j, e, .keyword)
                j = skipBlanks(e)
                if at(j) == 91 && (at(j + 1) == 32 || at(j + 1) | 0x20 == 120) && at(j + 2) == 93 {
                    emit(j, j + 3, .keyword)
                    j += 3
                }
            }
            if at(j) == 124 || (at(j) == 58 && at(j + 1) == 45) {
                var delimiterRow = true
                var q = j
                while q < le {
                    let d = s[q]
                    if !(d == 124 || d == 45 || d == 58 || SyntaxChar.isBlank(d)) { delimiterRow = false; break }
                    q += 1
                }
                if delimiterRow {
                    emit(j, le, .punctuation)
                    i = le + 1
                    continue
                }
            }
            if at(j) == 91 && at(j + 1) != 94, let close = markdownBracketEnd(j, le), at(close + 1) == 58 {
                emit(j, close + 1, .link)
                let u = skipBlanks(close + 1)
                var ue = u
                while ue < le && !SyntaxChar.isBlank(s[ue]) { ue += 1 }
                emit(u, ue, .link)
                markdownInline(ue, le)
                i = le + 1
                continue
            }
            markdownInline(j, le)
            i = le + 1
        }
        if fenceChar != 0 { markdownFenceContent(fenceContent, hi, fenceKind) }
    }

    func markdownFenceContent(_ a: Int, _ b: Int, _ kind: SyntaxLexerKind?) {
        guard b > a else { return }
        if let kind, depth < 3 {
            sub(a, b).run(kind)
        } else if kind == nil {
            emit(a, b, .string)
        }
    }

    func markdownThematicBreak(_ k: Int, _ le: Int, _ c: UInt16) -> Bool {
        var n = 0
        for q in k..<le {
            if s[q] == c { n += 1 } else if !SyntaxChar.isBlank(s[q]) { return false }
        }
        return n >= 3
    }

    func markdownListMarker(_ j: Int, _ le: Int) -> Bool {
        let c = at(j)
        if c == 45 || c == 42 || c == 43 { return j + 1 >= le || SyntaxChar.isBlank(at(j + 1)) }
        var e = j
        while SyntaxChar.isDigit(at(e)) && e - j < 9 { e += 1 }
        guard e > j, at(e) == 46 || at(e) == 41 else { return false }
        return e + 1 >= le || SyntaxChar.isBlank(at(e + 1))
    }

    /// Index of the `]` matching the `[` at `j` on the same line.
    func markdownBracketEnd(_ j: Int, _ le: Int) -> Int? {
        var depth = 0
        var q = j
        while q < le {
            let c = s[q]
            if c == 92 { q += 2; continue }
            if c == 96 {
                var n = 0
                while at(q + n) == 96 { n += 1 }
                q += n
                continue
            }
            if c == 91 { depth += 1 } else if c == 93 {
                depth -= 1
                if depth == 0 { return q }
            }
            q += 1
        }
        return nil
    }

    /// Matching `]` for every `[` in `a..<b`, computed with one stack pass (keeps long bracket runs linear).
    func markdownBracketMatches(_ a: Int, _ b: Int) -> [Int: Int] {
        var matches: [Int: Int] = [:]
        var stack: [Int] = []
        var q = a
        while q < b {
            let c = s[q]
            if c == 92 { q += 2; continue }
            if c == 91 { stack.append(q) } else if c == 93, let open = stack.popLast() { matches[open] = q }
            q += 1
        }
        return matches
    }

    func markdownInline(_ a: Int, _ b: Int) {
        var j = a
        var brackets: [Int: Int]? = nil
        var emphasisMisses: [Int: Int] = [:]
        while j < b {
            let c = s[j]
            switch c {
            case 92:
                let n = at(j + 1)
                if j + 1 < b && n < 128 && !SyntaxChar.isAlnum(n) && !SyntaxChar.isSpace(n) {
                    emit(j, j + 2, .escape)
                    j += 2
                } else {
                    j += 1
                }
            case 96:
                var n = 0
                while at(j + n) == 96 { n += 1 }
                var q = j + n
                var found = -1
                while q < b {
                    if s[q] == 96 {
                        var m = 0
                        while at(q + m) == 96 { m += 1 }
                        if m == n { found = q; break }
                        q += m
                        continue
                    }
                    q += 1
                }
                if found >= 0 {
                    emit(j, found + n, .string)
                    j = found + n
                } else {
                    j += n
                }
            case 42, 95, 126:
                var n = 0
                while at(j + n) == c && n < 3 { n += 1 }
                let after = at(j + n)
                let before = j > lo ? s[j - 1] : 32
                let opens = j + n < b && !SyntaxChar.isSpace(after) && !(c == 95 && SyntaxChar.isAlnum(before)) && (c != 126 || n == 2)
                let memoKey = Int(c) * 4 + n
                let known = emphasisMisses[memoKey].map { j + n >= $0 } ?? false
                if opens && !known, let close = markdownEmphasisClose(j + n, b, c, n) {
                    emit(j, close + n, c == 126 ? .deleted : .emphasis)
                    j = close + n
                } else {
                    if opens && !known && b - (j + n) <= 1000 { emphasisMisses[memoKey] = j + n }
                    while at(j) == c { j += 1 }
                }
            case 33 where at(j + 1) == 91:
                if brackets == nil { brackets = markdownBracketMatches(a, b) }
                if let close = brackets?[j + 1], let e = markdownLink(j + 1, close, b, image: true) { j = e } else { j += 1 }
            case 91:
                if brackets == nil { brackets = markdownBracketMatches(a, b) }
                if let close = brackets?[j], let e = markdownLink(j, close, b, image: false) { j = e } else { j += 1 }
            case 60:
                var q = j + 1
                if SyntaxChar.isLetter(at(q)) || at(q) == 47 {
                    while q < b && s[q] != 62 && s[q] != 60 { q += 1 }
                    if at(q) == 62 {
                        let inner = string(j + 1, Swift.min(q, j + 12))
                        let isLink = inner.hasPrefix("http") || inner.hasPrefix("mailto:") || inner.contains("@")
                        emit(j, q + 1, isLink ? .link : .tag)
                        j = q + 1
                        continue
                    }
                }
                j += 1
            case 104 where (has(j, "http://") || has(j, "https://")) && (j == a || !SyntaxChar.isAlnum(s[j - 1])):
                var q = j
                while q < b && !SyntaxChar.isSpace(s[q]) && s[q] != 60 && s[q] != 62 && s[q] != 41 && s[q] != 93 { q += 1 }
                while q > j && (s[q - 1] == 46 || s[q - 1] == 44 || s[q - 1] == 59 || s[q - 1] == 58 || s[q - 1] == 33 || s[q - 1] == 63) { q -= 1 }
                emit(j, q, .link)
                j = q
            case 38:
                let e = entityEnd(j)
                if e > j {
                    emit(j, e, .escape)
                    j = e
                } else {
                    j += 1
                }
            default:
                j += 1
            }
        }
    }

    func markdownEmphasisClose(_ from: Int, _ b: Int, _ c: UInt16, _ n: Int) -> Int? {
        var q = from
        let limit = Swift.min(b, from + 1000)
        while q < limit {
            let d = s[q]
            if d == 96 { // skip code spans
                var m = 0
                while at(q + m) == 96 { m += 1 }
                q += m
                continue
            }
            if d == c {
                var m = 0
                while at(q + m) == c { m += 1 }
                if m >= n && q > from && !SyntaxChar.isSpace(s[q - 1]) && !(c == 95 && SyntaxChar.isAlnum(at(q + m))) {
                    return q + (m - n)
                }
                q += m
                continue
            }
            q += 1
        }
        return nil
    }

    /// `[text](url)`, `[text][ref]`, `![alt](src)`, `[^note]`; returns the end index when it is a link.
    func markdownLink(_ j: Int, _ close: Int, _ b: Int, image: Bool) -> Int? {
        let start = image ? j - 1 : j
        if at(j + 1) == 94 {
            emit(start, close + 1, .link)
            return close + 1
        }
        let n = at(close + 1)
        if n == 40 {
            var depth = 0
            var q = close + 1
            let limit = Swift.min(b, close + 2_000)
            while q < limit {
                if s[q] == 40 { depth += 1 } else if s[q] == 41 {
                    depth -= 1
                    if depth == 0 { break }
                }
                q += 1
            }
            guard q < limit else { return nil }
            emit(start, close + 1, .string)
            emit(close + 1, q + 1, .link)
            return q + 1
        }
        if n == 91, let refClose = markdownReferenceEnd(close + 1, b) {
            emit(start, close + 1, .string)
            emit(close + 1, refClose + 1, .link)
            return refClose + 1
        }
        return nil
    }

    /// `[ref]` directly after a link text: closes on the same line without nesting.
    func markdownReferenceEnd(_ j: Int, _ b: Int) -> Int? {
        var q = j + 1
        while q < b && q < j + 200 {
            if s[q] == 93 { return q }
            if s[q] == 91 { return nil }
            q += 1
        }
        return nil
    }

    // MARK: - Diff

    func lexDiff() {
        var i = lo
        var inHunk = false
        var oldLeft = 0, newLeft = 0
        while i < hi {
            let le = lineEnd(i)
            let c = at(i)
            if has(i, "diff ") || has(i, "index ") || has(i, "similarity index") || has(i, "dissimilarity index")
                || has(i, "rename from") || has(i, "rename to") || has(i, "new file mode") || has(i, "deleted file mode")
                || has(i, "old mode") || has(i, "new mode") || has(i, "copy from") || has(i, "copy to") || has(i, "Index: ") {
                emit(i, le, .keyword)
                inHunk = false
            } else if has(i, "@@") {
                let close = find("@@", from: i + 2, to: le)
                let e = close.map { $0 + 2 } ?? le
                emit(i, e, .attribute)
                let counts = diffHunkCounts(i, e)
                oldLeft = counts.0
                newLeft = counts.1
                inHunk = true
                if e < le { emit(skipBlanks(e), le, .function) }
            } else if (has(i, "--- ") || has(i, "+++ ") || has(i, "*** ")) && (!inHunk || (oldLeft <= 0 && newLeft <= 0) || (has(i, "--- ") && has(nextLine(i), "+++ "))) {
                emit(i, le, .keyword)
                inHunk = false
            } else if has(i, "***************") {
                emit(i, le, .punctuation)
            } else if c == 43 || c == 62 {
                emit(i, le, .inserted)
                newLeft -= 1
            } else if c == 45 || c == 60 {
                emit(i, le, .deleted)
                oldLeft -= 1
            } else if c == 33 {
                emit(i, le, .attribute)
            } else if c == 92 || has(i, "Binary files") || has(i, "Only in ") || has(i, "No newline") {
                emit(i, le, .comment)
            } else if SyntaxChar.isDigit(c) && diffNormalCommand(i, le) {
                emit(i, le, .attribute)
            } else if c == 32 || c == 10 || i == le {
                oldLeft -= 1
                newLeft -= 1
            }
            i = le + 1
        }
    }

    func diffHunkCounts(_ a: Int, _ b: Int) -> (Int, Int) {
        var old = 1_000_000, new = 1_000_000
        var j = a
        while j < b {
            let c = s[j]
            if (c == 45 || c == 43) && SyntaxChar.isDigit(at(j + 1)) {
                var k = j + 1
                while SyntaxChar.isDigit(at(k)) { k += 1 }
                var count = 1
                if at(k) == 44 {
                    var e = k + 1
                    while SyntaxChar.isDigit(at(e)) { e += 1 }
                    count = Int(string(k + 1, e)) ?? 1
                    k = e
                }
                if c == 45 { old = count } else { new = count }
                j = k
                continue
            }
            j += 1
        }
        return (old, new)
    }

    func diffNormalCommand(_ a: Int, _ b: Int) -> Bool {
        var sawCommand = false
        for j in a..<trimEnd(a, b) {
            let c = s[j]
            if c == 97 || c == 99 || c == 100 {
                if sawCommand { return false }
                sawCommand = true
            } else if !(SyntaxChar.isDigit(c) || c == 44) {
                return false
            }
        }
        return sawCommand
    }

    // MARK: - Git

    func lexGitCommit() {
        var i = lo
        var subjectDone = false
        while i < hi {
            let le = lineEnd(i)
            if has(i, "diff --git") {
                sub(i, hi).lexDiff()
                return
            }
            if at(i) == 35 {
                emit(i, le, .comment)
                if has(i, "# ------------------------ >8") {
                    let rest = nextLine(i)
                    emit(rest, hi, .comment)
                    return
                }
                i = le + 1
                continue
            }
            if !subjectDone {
                if skipBlanks(i) < le {
                    subjectDone = true
                    var j = i
                    while j < le && (SyntaxChar.isLetter(s[j]) || s[j] == 45) { j += 1 }
                    var k = j
                    if at(k) == 40 {
                        while k < le && s[k] != 41 { k += 1 }
                        k += 1
                    }
                    if at(k) == 33 { k += 1 }
                    if j > i && at(k) == 58 && at(k + 1) == 32 {
                        emit(i, j, .keyword)
                        emit(j, k, .attribute)
                        emit(k + 2, le, .heading)
                    } else {
                        emit(i, le, .heading)
                    }
                }
                i = le + 1
                continue
            }
            var j = i
            while j < le && (SyntaxChar.isAlnum(s[j]) || s[j] == 45) { j += 1 }
            if j > i && at(j) == 58 && at(j + 1) == 32 && (string(i, j).contains("-") || word(i, j, is: "Fixes") || word(i, j, is: "Closes") || word(i, j, is: "Refs")) {
                emit(i, j + 1, .property)
                var q = j + 1
                while q < le {
                    if s[q] == 60 {
                        let e = (find(">", from: q, to: le)).map { $0 + 1 } ?? le
                        emit(q, e, .link)
                        q = e
                        continue
                    }
                    q += 1
                }
            }
            i = le + 1
        }
    }

    func lexGitRebase() {
        var i = lo
        while i < hi {
            let le = lineEnd(i)
            let k = skipBlanks(i)
            if at(k) == 35 {
                emit(k, le, .comment)
                i = le + 1
                continue
            }
            var e = k
            while e < le && (SyntaxChar.isLetter(s[e]) || s[e] == 45) { e += 1 }
            if e > k {
                emit(k, e, .keyword)
                let cmd = string(k, e)
                var j = skipBlanks(e)
                if cmd == "exec" || cmd == "x" {
                    if depth < SyntaxLexer.maxDepth { sub(j, le).lexShell(.bash) }
                } else if cmd == "label" || cmd == "l" || cmd == "reset" || cmd == "t" || cmd == "update-ref" || cmd == "u" {
                    emit(j, le, .variable)
                } else {
                    if at(j) == 45 {
                        var q = j
                        while q < le && !SyntaxChar.isBlank(s[q]) { q += 1 }
                        emit(j, q, .attribute)
                        j = skipBlanks(q)
                    }
                    var q = j
                    while q < le && SyntaxChar.isHex(s[q]) { q += 1 }
                    if q > j && (q >= le || SyntaxChar.isBlank(s[q])) { emit(j, q, .number) }
                }
            }
            i = le + 1
        }
    }

    // MARK: - Regex

    func lexRegex() {
        var i = lo
        var end = hi
        if at(lo) == 47, hi - lo > 2 {
            var e = hi
            while e > lo + 1 && SyntaxChar.isLetter(s[e - 1]) { e -= 1 }
            if at(e - 1) == 47 && e - 1 > lo {
                emit(lo, lo + 1, .punctuation)
                emit(e - 1, e, .punctuation)
                emit(e, hi, .keyword)
                i = lo + 1
                end = e - 1
            }
        }
        var inClass = false
        while i < end {
            let c = s[i]
            if c == 92 {
                let e = Swift.min(regexEscapeEnd(i + 1), end)
                emit(i, e, .escape)
                i = e
                continue
            }
            if inClass {
                if c == 93 {
                    emit(i, i + 1, .string)
                    inClass = false
                } else {
                    emit(i, i + 1, .string)
                }
                i += 1
                continue
            }
            switch c {
            case 91:
                inClass = true
                var e = i + 1
                if at(e) == 94 { e += 1 }
                emit(i, e, .string)
                i = e
                if at(i) == 93 { emit(i, i + 1, .string); i += 1 }
                continue
            case 40:
                var e = i + 1
                if at(e) == 63 {
                    e += 1
                    if at(e) == 80 { e += 1 }
                    if at(e) == 60 && at(e + 1) != 61 && at(e + 1) != 33 {
                        while e < end && s[e] != 62 { e += 1 }
                        e += 1
                    } else if at(e) == 60 {
                        e += 2
                    } else {
                        while e < end && (SyntaxChar.isLetter(s[e]) || s[e] == 45) { e += 1 }
                        if at(e) == 58 || at(e) == 61 || at(e) == 33 || at(e) == 62 || at(e) == 41 { e += 1 }
                    }
                }
                emit(i, Swift.min(e, end), e > i + 1 ? .keyword : .punctuation)
                i = Swift.min(e, end)
                continue
            case 41:
                emit(i, i + 1, .punctuation)
            case 42, 43, 63:
                var e = i + 1
                if at(e) == 63 || at(e) == 43 { e += 1 }
                emit(i, e, .keyword)
                i = e
                continue
            case 123:
                var e = i + 1
                while e < end && (SyntaxChar.isDigit(s[e]) || s[e] == 44) { e += 1 }
                if at(e) == 125 && e > i + 1 {
                    e += 1
                    if at(e) == 63 || at(e) == 43 { e += 1 }
                    emit(i, e, .number)
                    i = e
                    continue
                }
            case 94, 36, 124:
                emit(i, i + 1, .keyword)
            case 46:
                emit(i, i + 1, .constant)
            default:
                break
            }
            i += 1
        }
    }

    func regexEscapeEnd(_ j: Int) -> Int {
        let c = at(j)
        if (c == 112 || c == 80 || c == 107 || c == 103) && (at(j + 1) == 123 || at(j + 1) == 60) {
            var e = j + 2
            while e < hi && s[e] != 125 && s[e] != 62 && s[e] != 10 { e += 1 }
            return Swift.min(e + 1, hi)
        }
        if c == 99 { return Swift.min(j + 2, hi) }
        return escapeEnd(j)
    }

    // MARK: - HTTP

    func lexHTTP() {
        var i = lo
        var state = 0 // 0: start line, 1: headers, 2: body
        var contentType = ""
        while i < hi {
            let le = lineEnd(i)
            let k = skipBlanks(i)
            if has(k, "###") {
                emit(k, le, .comment)
                state = 0
                contentType = ""
                i = le + 1
                continue
            }
            switch state {
            case 0:
                if k >= le {
                    i = le + 1
                    continue
                }
                if at(k) == 35 || (at(k) == 47 && at(k + 1) == 47) {
                    emit(k, le, .comment)
                    i = le + 1
                    continue
                }
                if at(k) == 64 {
                    var e = k + 1
                    while e < le && (SyntaxChar.isIdentPart(s[e]) || s[e] == 45) { e += 1 }
                    emit(k, e, .variable)
                    i = le + 1
                    continue
                }
                var e = k
                while e < le && !SyntaxChar.isBlank(s[e]) { e += 1 }
                if has(k, "HTTP/") {
                    emit(k, e, .constant)
                    let codeStart = skipBlanks(e)
                    var ce = codeStart
                    while ce < le && SyntaxChar.isDigit(s[ce]) { ce += 1 }
                    emit(codeStart, ce, .number)
                } else {
                    emit(k, e, .keyword)
                    let target = skipBlanks(e)
                    var te = target
                    while te < le && !SyntaxChar.isBlank(s[te]) { te += 1 }
                    httpTemplated(target, te, base: .link)
                    let version = skipBlanks(te)
                    emit(version, trimEnd(version, le), .constant)
                }
                state = 1
            case 1:
                if k >= le {
                    state = 2
                    i = le + 1
                    let bodyEnd = find("###", from: i) ?? hi
                    let bs = skipSpace(i)
                    if bs < bodyEnd && depth < SyntaxLexer.maxDepth {
                        let body = sub(i, bodyEnd)
                        let first = at(bs)
                        if contentType.contains("json") || first == 123 || first == 91 {
                            body.lexJSON(.json)
                        } else if contentType.contains("xml") || contentType.contains("html") || first == 60 {
                            body.lexMarkup(contentType.contains("html") ? .html : .xml)
                        } else if contentType.contains("graphql") {
                            body.run(.code("graphql"))
                        }
                    }
                    i = bodyEnd
                    continue
                }
                var colon = k
                while colon < le && s[colon] != 58 { colon += 1 }
                if colon < le {
                    emit(k, colon, .property)
                    let name = string(k, colon).lowercased()
                    let v = skipBlanks(colon + 1)
                    if name == "content-type" { contentType = string(v, le).lowercased() }
                    httpTemplated(v, trimEnd(v, le), base: .plain)
                }
            default:
                break
            }
            i = le + 1
        }
    }

    /// Highlights `{{variable}}` placeholders (REST-client style) inside `a..<b`.
    func httpTemplated(_ a: Int, _ b: Int, base: SyntaxTokenKind) {
        var seg = a
        var j = a
        while j < b {
            if s[j] == 123 && at(j + 1) == 123 {
                let e = (find("}}", from: j + 2, to: b)).map { $0 + 2 } ?? b
                emit(seg, j, base)
                emit(j, e, .variable)
                j = e
                seg = e
                continue
            }
            j += 1
        }
        emit(seg, b, base)
    }

    // MARK: - LaTeX

    func lexLaTeX() {
        var i = lo
        while i < hi {
            let c = s[i]
            switch c {
            case 37:
                let e = lineEnd(i)
                emit(i, e, .comment)
                i = e
            case 92:
                let n = at(i + 1)
                if SyntaxChar.isLetter(n) {
                    var e = i + 1
                    while e < hi && (SyntaxChar.isLetter(s[e]) || s[e] == 64) { e += 1 }
                    if at(e) == 42 { e += 1 }
                    i = latexCommand(i, e)
                } else if n == 40 || n == 91 {
                    let close = find(n == 40 ? "\\)" : "\\]", from: i + 2) ?? hi
                    emit(i, i + 2, .keyword)
                    latexMath(i + 2, close)
                    emit(close, close + 2, .keyword)
                    i = Swift.min(close + 2, hi)
                } else if n != 0 {
                    emit(i, i + 2, .escape)
                    i += 2
                } else {
                    i += 1
                }
            case 36:
                let display = at(i + 1) == 36
                let open = display ? 2 : 1
                var q = i + open
                var close: Int? = nil
                while q < hi {
                    let d = s[q]
                    if d == 92 { q += 2; continue }
                    if d == 36 && (!display || at(q + 1) == 36) { close = q; break }
                    if d == 10 && at(q + 1) == 10 { break }
                    q += 1
                }
                if let close {
                    emit(i, i + open, .keyword)
                    latexMath(i + open, close)
                    emit(close, close + open, .keyword)
                    i = close + open
                } else {
                    i += open
                }
            case 38:
                emit(i, i + 1, .keyword)
                i += 1
            default:
                i += 1
            }
        }
    }

    /// Lexes a command whose name spans `i..<e` (including the backslash) and its special arguments.
    func latexCommand(_ i: Int, _ e: Int) -> Int {
        emit(i, e, .keyword)
        let name = string(i + 1, e).replacingOccurrences(of: "*", with: "")
        var j = skipBlanks(e)
        if at(j) == 91 && ["usepackage", "documentclass", "includegraphics", "section", "chapter", "subsection", "item", "begin"].contains(name) {
            j = matchingClose(j, open: 91, close: 93, multiline: false)
        }
        guard at(j) == 123 else { return e }
        let argKind: SyntaxTokenKind?
        switch name {
        case "begin", "end": argKind = .type
        case "part", "chapter", "section", "subsection", "subsubsection", "paragraph", "subparagraph", "title", "caption", "frametitle":
            argKind = .heading
        case "label", "ref", "eqref", "pageref", "autoref", "cref", "Cref", "cite", "citep", "citet", "nameref":
            argKind = .variable
        case "url", "href": argKind = .link
        case "usepackage", "documentclass", "RequirePackage", "input", "include", "includegraphics", "bibliography", "bibliographystyle":
            argKind = .string
        case "textbf", "textit", "emph", "underline", "texttt":
            argKind = .emphasis
        default:
            argKind = nil
        }
        guard let kind = argKind else { return e }
        let close = matchingClose(j, open: 123, close: 125, limit: j + 2_000)
        let argStart = j + 1
        let argEnd = Swift.max(argStart, at(close - 1) != 125 ? close : close - 1)
        emit(argStart, argEnd, kind)
        guard name == "begin" else { return j }
        let env = string(argStart, argEnd)
        let body = Swift.min(argEnd + 1, hi)
        let base = env.replacingOccurrences(of: "*", with: "")
        let verbatim = ["verbatim", "Verbatim", "lstlisting", "minted", "comment", "alltt", "BVerbatim"].contains(base)
        let math = ["equation", "align", "gather", "multline", "math", "displaymath", "eqnarray", "flalign", "alignat", "split"].contains(base)
        guard verbatim || math else { return j }
        let endIndex = findString("\\end{\(env)}", from: body) ?? hi
        if verbatim {
            emit(body, endIndex, base == "comment" ? .comment : .string)
        } else {
            latexMath(body, endIndex)
        }
        return endIndex
    }

    func findString(_ needle: String, from i: Int) -> Int? {
        let units = Array(needle.utf16)
        guard let first = units.first else { return nil }
        var j = i
        while j + units.count <= hi {
            if s[j] == first && has(j, units) { return j }
            j += 1
        }
        return nil
    }

    func latexMath(_ a: Int, _ b: Int) {
        var seg = a
        var j = a
        while j < b {
            let c = s[j]
            if c == 92 {
                emit(seg, j, .string)
                var e = j + 1
                if SyntaxChar.isLetter(at(e)) {
                    while e < b && SyntaxChar.isLetter(s[e]) { e += 1 }
                    emit(j, e, .keyword)
                } else {
                    e = Swift.min(j + 2, b)
                    emit(j, e, .escape)
                }
                j = e
                seg = e
                continue
            }
            if c == 37 {
                emit(seg, j, .string)
                let e = Swift.min(lineEnd(j), b)
                emit(j, e, .comment)
                j = e
                seg = e
                continue
            }
            if SyntaxChar.isDigit(c) {
                emit(seg, j, .string)
                var e = j
                while e < b && (SyntaxChar.isDigit(s[e]) || s[e] == 46) { e += 1 }
                emit(j, e, .number)
                j = e
                seg = e
                continue
            }
            if c == 123 || c == 125 || c == 94 || c == 95 || c == 38 || SyntaxChar.isSpace(c) {
                emit(seg, j, .string)
                j += 1
                seg = j
                continue
            }
            j += 1
        }
        emit(seg, b, .string)
    }
}
