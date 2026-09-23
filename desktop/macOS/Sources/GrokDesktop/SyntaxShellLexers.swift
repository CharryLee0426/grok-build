import Foundation

/// POSIX-ish shell lexer (bash/zsh/fish and Makefile recipes). Words in command position are `.function`.
struct SyntaxShellLexer {
    struct Heredoc {
        let tag: [UInt16]
        let stripTabs: Bool
        let expand: Bool
    }

    enum Expect { case none, loopVariable, awaitingIn, assignments, functionName, caseSubject, fishSet }

    static let keywords: SyntaxWordTable = {
        var t = SyntaxWordTable()
        t.add("if then else elif fi case esac for select while until do done in function time coproc { } ! [[ ]]", .keyword)
        t.add("end begin and or not switch", .keyword)
        return t
    }()

    static let declarations: SyntaxWordTable = {
        var t = SyntaxWordTable()
        t.add("export local declare readonly typeset unset alias unalias integer", .keyword)
        return t
    }()

    static let flowBuiltins: SyntaxWordTable = {
        var t = SyntaxWordTable()
        t.add("return exit break continue shift source eval exec trap wait set shopt", .keyword)
        return t
    }()

    static let prefixCommands: SyntaxWordTable = {
        var t = SyntaxWordTable()
        t.add("sudo time nohup exec env xargs command builtin nice doas watch caffeinate noglob then do else", .keyword)
        return t
    }()

    let L: SyntaxLexer
    let s: UnsafeBufferPointer<UInt16>
    let lo: Int
    let hi: Int
    let flavor: SyntaxShellFlavor
    var commandPosition = true
    var expect = Expect.none
    var heredocs: [Heredoc] = []
    var nesting = 0
    /// Inside `case … in`, words before `)` are patterns, not commands.
    var caseDepth = 0
    var casePattern = false
    /// Index where an assignment's value starts (`FOO="x" cmd` keeps command position).
    var assignmentValueStart = -1
    /// After `sudo`/`env`/`command`, leading options do not end command position.
    var afterPrefixCommand = false

    init(_ lexer: SyntaxLexer, flavor: SyntaxShellFlavor) {
        L = lexer
        s = lexer.s
        lo = lexer.lo
        hi = lexer.hi
        self.flavor = flavor
    }

    @inline(__always) func at(_ i: Int) -> UInt16 { L.at(i) }
    @inline(__always) func emit(_ a: Int, _ b: Int, _ k: SyntaxTokenKind) { L.emit(a, b, k) }

    mutating func run(_ i: inout Int, closer: UInt16) {
        var parens = 0
        while i < hi {
            let c = s[i]
            if c == 10 {
                i += 1
                commandPosition = true
                expect = .none
                if !heredocs.isEmpty { readHeredocs(&i) }
                continue
            }
            if SyntaxChar.isBlank(c) { i += 1; continue }
            if closer == 96 && c == 96 { return }
            if closer == 41 {
                if c == 40 {
                    parens += 1
                } else if c == 41 {
                    if parens == 0 { return }
                    parens -= 1
                }
            }
            let start = i
            step(&i, c)
            if i <= start { i = start + 1 }
        }
    }

    func atWordStart(_ i: Int) -> Bool {
        guard i > lo else { return true }
        let p = s[i - 1]
        return SyntaxChar.isSpace(p) || p == 59 || p == 38 || p == 124 || p == 40 || p == 41
    }

    mutating func step(_ i: inout Int, _ c: UInt16) {
        if (c == 39 || c == 34 || c == 36 || c == 96) && i == assignmentValueStart {
            // Quoted or expanded assignment value: `FOO="bar" cmd`.
            let saved = (commandPosition, expect)
            switch c {
            case 39:
                let e = L.quotedEnd(i, quote: 39, escapes: false, multiline: true)
                emit(i, e, .string)
                i = e
            case 34: doubleQuoted(&i, from: i)
            case 96: substitution(&i, open: 1, closer: 96)
            default: dollar(&i)
            }
            (commandPosition, expect) = saved
            assignmentValueStart = i < hi && !isWordBreak(s[i]) ? -1 : i
            return
        }
        switch c {
        case 35 where atWordStart(i):
            let e = L.lineEnd(i)
            emit(i, e, .comment)
            i = e
        case 39:
            let e = L.quotedEnd(i, quote: 39, escapes: false, multiline: true)
            emit(i, e, .string)
            i = e
            commandPosition = false
        case 34:
            doubleQuoted(&i, from: i)
            commandPosition = false
        case 96:
            substitution(&i, open: 1, closer: 96)
            commandPosition = false
        case 36:
            dollar(&i)
            if expect != .caseSubject { commandPosition = false }
        case 92 where at(i + 1) == 10 || (at(i + 1) == 13 && at(i + 2) == 10):
            i += at(i + 1) == 10 ? 2 : 3
        case 59:
            i += 1
            if at(i) == 59 || at(i) == 38 {
                i += 1
                if at(i) == 38 { i += 1 }
                if caseDepth > 0 { casePattern = true }
            }
            commandPosition = true
            expect = .none
        case 38:
            if at(i + 1) == 38 {
                i += 2
                commandPosition = true
            } else if at(i + 1) == 62 {
                i += 2
                commandPosition = false
            } else {
                i += 1
                commandPosition = true
            }
            expect = .none
        case 124:
            i += (at(i + 1) == 124 || at(i + 1) == 38) ? 2 : 1
            commandPosition = true
            expect = .none
        case 40:
            if at(i + 1) == 40 {
                emit(i, i + 2, .keyword)
                i += 2
                commandPosition = false
            } else {
                i += 1
                commandPosition = true
            }
        case 41:
            i += 1
            commandPosition = true
            casePattern = false
        case 60, 62:
            if c == 60 && at(i + 1) == 60 {
                if at(i + 2) == 60 {
                    i += 3
                    commandPosition = false
                    return
                }
                heredocStart(&i)
                return
            }
            if (c == 60 || c == 62) && at(i + 1) == 40 {
                substitution(&i, open: 2, closer: 41)
                return
            }
            i += 1
            while at(i) == 62 || at(i) == 38 || at(i) == 124 { i += 1 }
            commandPosition = false
        case 123, 125:
            let n = at(i + 1)
            if n == 0 || SyntaxChar.isSpace(n) || n == 59 {
                emit(i, i + 1, .keyword)
                i += 1
                commandPosition = c == 123
            } else {
                word(&i)
            }
        case 91:
            if commandPosition && (at(i + 1) == 91 || SyntaxChar.isBlank(at(i + 1))) {
                let e = at(i + 1) == 91 ? i + 2 : i + 1
                emit(i, e, .keyword)
                i = e
                commandPosition = false
            } else {
                word(&i)
            }
        case 93:
            let n = at(i + 1)
            if n == 93 && (i + 2 >= hi || !SyntaxChar.isIdentPart(at(i + 2))) {
                emit(i, i + 2, .keyword)
                i += 2
            } else if i > lo && SyntaxChar.isBlank(s[i - 1]) && (n == 0 || SyntaxChar.isSpace(n) || n == 59) {
                emit(i, i + 1, .keyword)
                i += 1
            } else {
                word(&i)
            }
        default:
            word(&i)
        }
    }

    func isWordBreak(_ d: UInt16) -> Bool {
        SyntaxChar.isSpace(d) || d == 59 || d == 38 || d == 124 || d == 60 || d == 62 || d == 40 || d == 41 || d == 34 || d == 39 || d == 96 || d == 36
    }

    mutating func word(_ i: inout Int) {
        let a = i
        var j = i
        while j < hi {
            let d = s[j]
            if isWordBreak(d) { break }
            if d == 92 { j += 2; continue }
            j += 1
        }
        j = Swift.min(j, hi)
        guard j > a else {
            i += 1
            return
        }
        classify(a, j)
        i = j
    }

    /// Returns the index of `=` when `a..<b` starts with `NAME=`, `NAME+=` or `NAME[...]=`.
    func assignment(_ a: Int, _ b: Int) -> Int? {
        guard SyntaxChar.isIdentStart(s[a]) else { return nil }
        var j = L.identEnd(a)
        if at(j) == 91 {
            while j < b && s[j] != 93 { j += 1 }
            j += 1
        }
        if at(j) == 43 { j += 1 }
        return j < b && s[j] == 61 ? j : nil
    }

    mutating func classify(_ a: Int, _ b: Int) {
        if commandPosition || expect == .assignments, let eq = assignment(a, b) {
            var nameEnd = eq
            if s[eq - 1] == 43 { nameEnd -= 1 }
            emit(a, nameEnd, .variable)
            if eq + 1 < b && isNumber(eq + 1, b) { emit(eq + 1, b, .number) }
            if eq + 1 == b { assignmentValueStart = b }
            return
        }
        switch expect {
        case .loopVariable:
            emit(a, b, .variable)
            expect = .awaitingIn
            commandPosition = false
            return
        case .functionName:
            emit(a, b, .function)
            expect = .none
            commandPosition = false
            return
        case .awaitingIn, .caseSubject:
            if L.word(a, b, is: "in") {
                emit(a, b, .keyword)
                if expect == .caseSubject {
                    caseDepth += 1
                    casePattern = true
                }
                expect = .none
                commandPosition = false
                return
            }
        case .fishSet:
            if s[a] != 45 {
                emit(a, b, .variable)
                expect = .none
                return
            }
        default:
            break
        }
        if casePattern {
            if L.word(a, b, is: "esac") {
                emit(a, b, .keyword)
                caseDepth = Swift.max(0, caseDepth - 1)
                casePattern = false
                commandPosition = false
            }
            return
        }
        if commandPosition && afterPrefixCommand && s[a] == 45 {
            emit(a, b, .attribute)
            return
        }
        afterPrefixCommand = false
        if commandPosition {
            if let entry = SyntaxShellLexer.keywords.lookup(s, a, b) {
                emit(a, b, entry.kind)
                if L.word(a, b, is: "function") {
                    expect = .functionName
                    commandPosition = false
                } else if L.word(a, b, is: "for") || L.word(a, b, is: "select") {
                    expect = .loopVariable
                    commandPosition = false
                } else if L.word(a, b, is: "case") || L.word(a, b, is: "switch") {
                    expect = .caseSubject
                    commandPosition = false
                } else if L.word(a, b, is: "esac") {
                    caseDepth = Swift.max(0, caseDepth - 1)
                    commandPosition = false
                } else if L.word(a, b, is: "fi") || L.word(a, b, is: "done") || L.word(a, b, is: "in") || L.word(a, b, is: "]]") || L.word(a, b, is: "}") {
                    commandPosition = false
                } else {
                    commandPosition = true
                }
                return
            }
            if SyntaxShellLexer.declarations.lookup(s, a, b) != nil {
                emit(a, b, .keyword)
                expect = .assignments
                commandPosition = false
                return
            }
            if flavor == .fish && L.word(a, b, is: "set") {
                emit(a, b, .keyword)
                expect = .fishSet
                commandPosition = false
                return
            }
            if SyntaxShellLexer.flowBuiltins.lookup(s, a, b) != nil {
                emit(a, b, .keyword)
                commandPosition = false
                return
            }
            emit(a, b, .function)
            commandPosition = SyntaxShellLexer.prefixCommands.lookup(s, a, b) != nil
            afterPrefixCommand = commandPosition
            return
        }
        let first = s[a]
        let second = at(a + 1)
        if first == 45 && b > a + 1 && (SyntaxChar.isLetter(second) || (second == 45 && SyntaxChar.isLetter(at(a + 2)))) {
            var e = a
            while e < b && s[e] != 61 { e += 1 }
            emit(a, e, .attribute)
            return
        }
        if isNumber(a, b) {
            emit(a, b, .number)
            return
        }
        if expect == .assignments && SyntaxChar.isIdentStart(first) && L.identEnd(a) == b {
            emit(a, b, .variable)
        }
    }

    func isNumber(_ a: Int, _ b: Int) -> Bool {
        guard b > a else { return false }
        var dots = 0
        for k in a..<b {
            if s[k] == 46 { dots += 1; continue }
            if !SyntaxChar.isDigit(s[k]) { return false }
        }
        return dots <= 1 && SyntaxChar.isDigit(s[a])
    }

    mutating func doubleQuoted(_ i: inout Int, from a: Int) {
        var seg = a
        i += 1
        while i < hi {
            let c = s[i]
            if c == 34 {
                i += 1
                emit(seg, i, .string)
                return
            }
            if c == 92 {
                let n = at(i + 1)
                if n == 36 || n == 34 || n == 92 || n == 96 || n == 10 {
                    emit(seg, i, .string)
                    emit(i, i + 2, .escape)
                    i += 2
                    seg = i
                } else {
                    i += 1
                }
                continue
            }
            if c == 36 && (SyntaxChar.isIdentStart(at(i + 1)) || at(i + 1) == 123 || at(i + 1) == 40 || SyntaxChar.isDigit(at(i + 1)) || "@*#?$!-".utf16.contains(at(i + 1))) {
                emit(seg, i, .string)
                dollar(&i)
                seg = i
                continue
            }
            if c == 96 {
                emit(seg, i, .string)
                substitution(&i, open: 1, closer: 96)
                seg = i
                continue
            }
            i += 1
        }
        emit(seg, i, .string)
    }

    /// `$( … )`, `` ` … ` ``, `<( … )`: delimiters as `.variable`, contents as commands.
    mutating func substitution(_ i: inout Int, open: Int, closer: UInt16) {
        emit(i, i + open, .variable)
        i += open
        guard nesting < 8 else { return }
        let saved = (commandPosition, expect)
        commandPosition = true
        expect = .none
        nesting += 1
        run(&i, closer: closer)
        nesting -= 1
        (commandPosition, expect) = saved
        if i < hi && s[i] == closer {
            emit(i, i + 1, .variable)
            i += 1
        }
    }

    mutating func dollar(_ i: inout Int) {
        let n = at(i + 1)
        if flavor == .make && (n == 40 || n == 123) {
            let e = L.matchingClose(i + 1, open: n, close: n == 40 ? 41 : 125, multiline: false)
            emit(i, e, .variable)
            i = e
            return
        }
        if flavor == .make && n == 36 {
            let e = SyntaxChar.isIdentStart(at(i + 2)) ? L.identEnd(i + 2) : i + 2
            emit(i, e, .variable)
            i = e
            return
        }
        if n == 40 {
            if at(i + 2) == 40 {
                var e = i + 3
                var depth = 2
                while e < hi && depth > 0 {
                    if s[e] == 40 { depth += 1 } else if s[e] == 41 { depth -= 1 }
                    e += 1
                }
                emit(i, i + 3, .variable)
                arithmetic(i + 3, Swift.max(i + 3, e - 2))
                emit(Swift.max(i + 3, e - 2), e, .variable)
                i = e
                return
            }
            substitution(&i, open: 2, closer: 41)
            return
        }
        if n == 123 {
            let e = L.matchingClose(i + 1, open: 123, close: 125, multiline: false)
            emit(i, e, .variable)
            i = e
            return
        }
        if n == 39 {
            let e = L.quotedEnd(i + 1, quote: 39, escapes: true, multiline: true)
            L.emitEscaped(i, e, .string)
            i = e
            return
        }
        if n == 34 {
            let a = i
            i += 1
            doubleQuoted(&i, from: a)
            return
        }
        if SyntaxChar.isIdentStart(n) {
            let e = L.identEnd(i + 1)
            emit(i, e, .variable)
            i = e
            return
        }
        if SyntaxChar.isDigit(n) || (n != 0 && "@*#?$!-_".utf16.contains(n)) {
            emit(i, i + 2, .variable)
            i += 2
            return
        }
        i += 1
    }

    func arithmetic(_ a: Int, _ b: Int) {
        var j = a
        while j < b {
            let c = s[j]
            if SyntaxChar.isDigit(c) {
                var e = j
                while e < b && SyntaxChar.isAlnum(s[e]) { e += 1 }
                emit(j, e, .number)
                j = e
            } else if SyntaxChar.isIdentStart(c) || c == 36 {
                let e = L.identEnd(c == 36 ? j + 1 : j)
                emit(j, e, .variable)
                j = Swift.max(e, j + 1)
            } else {
                j += 1
            }
        }
    }

    mutating func heredocStart(_ i: inout Int) {
        var j = i + 2
        var strip = false
        if at(j) == 45 { strip = true; j += 1 }
        j = L.skipBlanks(j)
        var quote: UInt16 = 0
        if at(j) == 39 || at(j) == 34 { quote = s[j]; j += 1 } else if at(j) == 92 { quote = 92; j += 1 }
        let ts = j
        while j < hi && (SyntaxChar.isIdentPart(s[j]) || s[j] == 45 || s[j] == 46) { j += 1 }
        guard j > ts else {
            i += 2
            commandPosition = false
            return
        }
        let te = j
        if quote == 39 || quote == 34, at(j) == quote { j += 1 }
        emit(i, j, .string)
        heredocs.append(Heredoc(tag: L.units(ts, te), stripTabs: strip, expand: quote == 0))
        i = j
        commandPosition = false
    }

    mutating func readHeredocs(_ i: inout Int) {
        let pending = heredocs
        heredocs.removeAll()
        for (index, doc) in pending.enumerated() {
            if index > 0 && i < hi && s[i] == 10 { i += 1 }
            let bodyStart = i
            var bodyEnd = hi
            var termEnd = hi
            var j = i
            while j < hi {
                let le = L.lineEnd(j)
                var k = j
                if doc.stripTabs { while k < le && s[k] == 9 { k += 1 } }
                if L.trimEnd(k, le) - k == doc.tag.count && L.has(k, doc.tag) {
                    bodyEnd = j
                    termEnd = le
                    break
                }
                j = le < hi ? le + 1 : hi
            }
            if doc.expand { heredocBody(bodyStart, bodyEnd) } else { emit(bodyStart, bodyEnd, .string) }
            emit(bodyEnd, termEnd, .string)
            i = termEnd
        }
    }

    func heredocBody(_ a: Int, _ b: Int) {
        var seg = a
        var j = a
        while j < b {
            let c = s[j]
            if c == 92 {
                j += 2
                continue
            }
            if c == 36 {
                let n = at(j + 1)
                var e = j
                if n == 123 || n == 40 {
                    e = Swift.min(L.matchingClose(j + 1, open: n, close: n == 40 ? 41 : 125, multiline: false), b)
                } else if SyntaxChar.isIdentStart(n) {
                    e = L.identEnd(j + 1)
                } else if SyntaxChar.isDigit(n) || (n != 0 && "@*#?$!".utf16.contains(n)) {
                    e = j + 2
                }
                if e > j {
                    emit(seg, j, .string)
                    emit(j, e, .variable)
                    j = e
                    seg = e
                    continue
                }
            }
            j += 1
        }
        emit(seg, b, .string)
    }
}

extension SyntaxLexer {
    func lexShell(_ flavor: SyntaxShellFlavor) {
        var lexer = SyntaxShellLexer(self, flavor: flavor)
        var i = lo
        lexer.run(&i, closer: 0)
    }

    // MARK: - Shell sessions

    /// Lines starting with a prompt (`$ `, `% `, `user@host:~$ `, `PS C:\> `) are commands; others are output.
    func lexConsole() {
        var any = false
        var j = lo
        while j < hi {
            let le = lineEnd(j)
            if promptEnd(j, le) != nil { any = true; break }
            j = le + 1
        }
        guard any else {
            lexShell(.bash)
            return
        }
        var i = lo
        while i < hi {
            let le = lineEnd(i)
            guard let pe = promptEnd(i, le) else {
                i = le + 1
                continue
            }
            let symbol = pe > i && s[pe - 1] == 32 ? pe - 2 : pe - 1
            emit(i, symbol, .punctuation)
            emit(symbol, symbol + 1, .keyword)
            var end = le
            while end < hi && end > pe && (s[end - 1] == 92 || (s[end - 1] == 13 && at(end - 2) == 92)) { end = lineEnd(end + 1) }
            if let tag = heredocTag(pe, end) {
                var q = end < hi ? end + 1 : hi
                while q < hi {
                    let qe = lineEnd(q)
                    if trimEnd(skipBlanks(q), qe) - skipBlanks(q) == tag.count && has(skipBlanks(q), tag) {
                        end = qe
                        break
                    }
                    q = qe + 1
                }
            }
            let powershell = has(i, "PS ") && s[symbol] == 62
            if depth < SyntaxLexer.maxDepth {
                if powershell { sub(pe, end).lexPowerShell() } else { sub(pe, end).lexShell(.bash) }
            }
            i = end + 1
        }
    }

    func heredocTag(_ a: Int, _ b: Int) -> [UInt16]? {
        var j = a
        while j + 2 < b {
            if s[j] == 60 && s[j + 1] == 60 && s[j + 2] != 60 {
                var k = j + 2
                if at(k) == 45 { k += 1 }
                k = skipBlanks(k)
                if at(k) == 39 || at(k) == 34 { k += 1 }
                let ts = k
                while k < b && (SyntaxChar.isIdentPart(s[k]) || s[k] == 45) { k += 1 }
                if k > ts { return units(ts, k) }
            }
            j += 1
        }
        return nil
    }

    func promptEnd(_ i: Int, _ le: Int) -> Int? {
        var j = i
        if at(j) == 40 { // (venv) prefix
            var k = j + 1
            while k < le && k < j + 40 && s[k] != 41 && !SyntaxChar.isBlank(s[k]) { k += 1 }
            if at(k) == 41 && at(k + 1) == 32 { j = k + 2 }
        }
        let c = at(j)
        if (c == 36 || c == 37 || c == 0x276F || c == 0x279C || c == 0x03BB || c == 0x00BB) && j < le && (j + 1 == le || at(j + 1) == 32) {
            return Swift.min(j + 2, le)
        }
        // user@host:path$ , [user@host dir]$ , PS C:\path> , C:\path>
        var k = j
        var sawMarker = false
        let bracketed = c == 91
        let powershell = has(j, "PS ") || (SyntaxChar.isLetter(c) && at(j + 1) == 58 && at(j + 2) == 92)
        while k < le && k < j + 120 {
            let d = s[k]
            if d == 64 || d == 126 { sawMarker = true }
            if (d == 36 || d == 35 || d == 37 || (d == 62 && powershell)) && (k + 1 == le || at(k + 1) == 32) && k > j {
                let prev = s[k - 1]
                if sawMarker || (bracketed && prev == 93) || powershell {
                    return Swift.min(k + 2, le)
                }
                return nil
            }
            if d == 34 || d == 39 || d == 61 { return nil }
            if d == 32 && !sawMarker && !bracketed && !powershell { return nil }
            k += 1
        }
        return nil
    }

    func lexPythonConsole() {
        var i = lo
        while i < hi {
            let le = lineEnd(i)
            if (has(i, ">>>") || has(i, "...")) && (i + 3 >= le || at(i + 3) == 32) {
                emit(i, i + 3, .keyword)
                if depth < SyntaxLexer.maxDepth { sub(Swift.min(i + 4, le), le).run(.code("python")) }
            } else if has(i, "In [") || has(i, "Out[") {
                var e = i
                while e < le && s[e] != 58 { e += 1 }
                emit(i, Swift.min(e + 1, le), .keyword)
                if has(i, "In [") && depth < SyntaxLexer.maxDepth { sub(Swift.min(e + 1, le), le).run(.code("python")) }
            } else if has(i, "Traceback (most recent call last)") {
                emit(i, le, .deleted)
            } else if SyntaxChar.isUpper(at(i)) {
                var e = i
                while e < le && (SyntaxChar.isIdentPart(s[e]) || s[e] == 46) { e += 1 }
                let name = string(i, e)
                if at(e) == 58 && (name.hasSuffix("Error") || name.hasSuffix("Exception") || name.hasSuffix("Warning") || name.hasSuffix("Interrupt") || name.hasSuffix("Exit")) {
                    emit(i, le, .deleted)
                }
            }
            i = le + 1
        }
    }

    // MARK: - PowerShell

    func lexPowerShell() {
        var lexer = SyntaxPowerShellLexer(self)
        var i = lo
        lexer.run(&i, closer: 0)
    }

    // MARK: - Windows batch

    func lexBatch() {
        var i = lo
        let keywords = SyntaxBatchWords.keywords
        while i < hi {
            let le = lineEnd(i)
            var j = skipBlanks(i)
            if at(j) == 64 {
                emit(j, j + 1, .keyword)
                j += 1
            }
            if has(j, "::") || (hasCI(j, "rem") && (j + 3 >= le || SyntaxChar.isBlank(at(j + 3)))) {
                emit(j, le, .comment)
                i = le + 1
                continue
            }
            if at(j) == 58 && SyntaxChar.isIdentStart(at(j + 1)) {
                emit(j, le, .function)
                i = le + 1
                continue
            }
            var command = true
            var echo = false
            while j < le {
                let c = s[j]
                if SyntaxChar.isBlank(c) { j += 1; continue }
                if c == 37 || c == 33 {
                    let e = batchVariableEnd(j, le)
                    if e > j {
                        emit(j, e, .variable)
                        j = e
                        command = false
                        continue
                    }
                }
                if c == 34 {
                    var e = j + 1
                    while e < le && s[e] != 34 { e += 1 }
                    e = Swift.min(e + 1, le)
                    var seg = j
                    var q = j + 1
                    while q < e {
                        if s[q] == 37 || s[q] == 33 {
                            let ve = batchVariableEnd(q, e)
                            if ve > q {
                                emit(seg, q, .string)
                                emit(q, ve, .variable)
                                q = ve
                                seg = ve
                                continue
                            }
                        }
                        q += 1
                    }
                    emit(seg, e, .string)
                    j = e
                    command = false
                    continue
                }
                if c == 124 || c == 38 || c == 40 {
                    j += (at(j + 1) == c) ? 2 : 1
                    command = true
                    echo = false
                    continue
                }
                if c == 41 || c == 60 || c == 62 {
                    j += 1
                    command = false
                    continue
                }
                var e = j
                while e < le && !SyntaxChar.isBlank(s[e]) && s[e] != 124 && s[e] != 38 && s[e] != 40 && s[e] != 41 && s[e] != 60 && s[e] != 62 && s[e] != 34 && s[e] != 37 && s[e] != 61 && s[e] != 33 {
                    e += 1
                }
                if e == j {
                    j += 1
                    continue
                }
                if echo {
                    j = e
                    continue
                }
                if keywords.lookup(s, j, e) != nil {
                    emit(j, e, .keyword)
                    let w = string(j, e).lowercased()
                    echo = w == "echo"
                    command = ["if", "else", "do", "not", "call", "exist", "defined"].contains(w)
                    if w == "set" {
                        var k = skipBlanks(e)
                        if at(k) == 47 {
                            let oe = k + 2
                            emit(k, oe, .attribute)
                            k = skipBlanks(oe)
                        }
                        var ne = k
                        while ne < le && s[ne] != 61 && !SyntaxChar.isBlank(s[ne]) { ne += 1 }
                        if at(ne) == 61 {
                            emit(k, ne, .variable)
                            e = ne + 1
                        }
                    }
                } else if s[j] == 47 && e > j + 1 {
                    emit(j, e, .attribute)
                } else if command {
                    emit(j, e, .function)
                    command = false
                } else if SyntaxChar.isDigit(s[j]) && string(j, e).allSatisfy({ $0.isNumber }) {
                    emit(j, e, .number)
                }
                j = e
            }
            i = le + 1
        }
    }

    func batchVariableEnd(_ j: Int, _ le: Int) -> Int {
        let c = s[j]
        if c == 37 {
            if at(j + 1) == 37 { // %%i loop variable
                return SyntaxChar.isLetter(at(j + 2)) ? j + 3 : j
            }
            if at(j + 1) == 126 { // %~dp0
                var e = j + 2
                while e < le && SyntaxChar.isLetter(s[e]) { e += 1 }
                return SyntaxChar.isDigit(at(e)) ? e + 1 : j
            }
            if SyntaxChar.isDigit(at(j + 1)) || at(j + 1) == 42 { return j + 2 }
        }
        var e = j + 1
        while e < le && s[e] != c && !SyntaxChar.isBlank(s[e]) && s[e] != 34 { e += 1 }
        return (at(e) == c && e > j + 1) ? e + 1 : j
    }

    // MARK: - Dockerfile

    func lexDockerfile() {
        var i = lo
        while i < hi {
            let le = lineEnd(i)
            let k = skipBlanks(i)
            if k >= le {
                i = le + 1
                continue
            }
            if at(k) == 35 {
                emit(k, le, .comment)
                i = le + 1
                continue
            }
            var e = k
            while e < le && SyntaxChar.isLetter(s[e]) { e += 1 }
            var end = le
            while end < hi && end > k && s[trimEnd(k, end) - 1] == 92 { end = lineEnd(end + 1) }
            guard e > k, SyntaxBatchWords.dockerInstructions.lookup(s, k, e) != nil else {
                dockerArguments(k, end, assignments: false)
                i = end + 1
                continue
            }
            emit(k, e, .keyword)
            let instruction = string(k, e).uppercased()
            var a = skipBlanks(e)
            if instruction == "ONBUILD" || instruction == "HEALTHCHECK" {
                while has(a, "--") {
                    var q = a
                    while q < end && !SyntaxChar.isSpace(s[q]) { q += 1 }
                    dockerArguments(a, q, assignments: false)
                    a = skipSpace(q)
                }
                var q = a
                while q < end && SyntaxChar.isLetter(s[q]) { q += 1 }
                if q > a && SyntaxBatchWords.dockerInstructions.lookup(s, a, q) != nil {
                    emit(a, q, .keyword)
                    a = skipBlanks(q)
                }
            }
            switch instruction {
            case "RUN", "CMD", "ENTRYPOINT", "SHELL", "ONBUILD", "HEALTHCHECK":
                while has(a, "--") {
                    var q = a
                    while q < end && !SyntaxChar.isSpace(s[q]) { q += 1 }
                    dockerArguments(a, q, assignments: false)
                    a = skipSpace(q)
                }
                if at(a) == 91 {
                    sub(a, end).lexJSON(.json)
                } else {
                    if let tag = heredocTag(a, end) {
                        var q = end < hi ? end + 1 : hi
                        while q < hi {
                            let qe = lineEnd(q)
                            if trimEnd(q, qe) - q == tag.count && has(q, tag) {
                                end = qe
                                break
                            }
                            q = qe + 1
                        }
                    }
                    if depth < SyntaxLexer.maxDepth { sub(a, end).lexShell(.bash) }
                }
            case "FROM":
                var q = a
                var sawImage = false
                while q < end {
                    q = skipSpace(q)
                    guard q < end else { break }
                    var w = q
                    while w < end && !SyntaxChar.isSpace(s[w]) { w += 1 }
                    if has(q, "--") {
                        dockerArguments(q, w, assignments: false)
                    } else if word(q, w, is: "as", ci: true) {
                        emit(q, w, .keyword)
                    } else if !sawImage {
                        dockerArguments(q, w, assignments: false, base: .string)
                        sawImage = true
                    } else {
                        emit(q, w, .type)
                    }
                    q = w
                }
            case "ENV", "ARG", "LABEL":
                dockerArguments(a, end, assignments: true, keyKind: instruction == "LABEL" ? .property : .variable)
            default:
                if at(a) == 91 { sub(a, end).lexJSON(.json) } else { dockerArguments(a, end, assignments: false) }
            }
            i = end + 1
        }
    }

    func dockerArguments(_ a: Int, _ b: Int, assignments: Bool, keyKind: SyntaxTokenKind = .variable, base: SyntaxTokenKind = .plain) {
        var j = a
        var firstWord = true
        while j < b {
            let c = s[j]
            if SyntaxChar.isSpace(c) || c == 92 { j += 1; continue }
            if c == 35 && at(j - 1) == 10 {
                let e = Swift.min(lineEnd(j), b)
                emit(j, e, .comment)
                j = e
                continue
            }
            if c == 34 || c == 39 {
                let e = Swift.min(quotedEnd(j, quote: c, escapes: c == 34, multiline: false), b)
                dockerExpand(j, e, .string)
                j = e
                continue
            }
            var e = j
            while e < b && !SyntaxChar.isSpace(s[e]) && s[e] != 34 && s[e] != 39 { e += 1 }
            if c == 45 && at(j + 1) == 45 {
                var q = j
                while q < e && s[q] != 61 { q += 1 }
                emit(j, q, .attribute)
                dockerExpand(Swift.min(q + 1, e), e, base)
            } else if assignments, let eq = (j..<e).first(where: { s[$0] == 61 }) {
                emit(j, eq, keyKind)
                dockerExpand(eq + 1, e, .string)
            } else if assignments && firstWord && keyKind == .variable {
                emit(j, e, keyKind)
            } else if (j..<e).allSatisfy({ SyntaxChar.isDigit(s[$0]) || s[$0] == 47 || s[$0] == 45 || SyntaxChar.isLetter(s[$0]) }) && SyntaxChar.isDigit(c) {
                emit(j, e, .number)
            } else {
                dockerExpand(j, e, base)
            }
            firstWord = false
            j = e
        }
    }

    /// Emits `a..<b` as `base`, with `$VAR` / `${VAR}` highlighted as variables.
    func dockerExpand(_ a: Int, _ b: Int, _ base: SyntaxTokenKind) {
        var seg = a
        var j = a
        while j < b {
            if s[j] == 36 && (at(j + 1) == 123 || SyntaxChar.isIdentStart(at(j + 1))) {
                let e = at(j + 1) == 123 ? Swift.min(matchingClose(j + 1, open: 123, close: 125, multiline: false), b) : identEnd(j + 1)
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

    // MARK: - Makefile

    func lexMakefile() {
        var i = lo
        while i < hi {
            var le = lineEnd(i)
            if at(i) == 9 {
                while le < hi && le > i && s[le - 1] == 92 { le = lineEnd(le + 1) }
                var a = i + 1
                while at(a) == 64 || at(a) == 45 || at(a) == 43 {
                    emit(a, a + 1, .keyword)
                    a += 1
                }
                if depth < SyntaxLexer.maxDepth { sub(a, le).lexShell(.make) }
                i = le + 1
                continue
            }
            let k = skipBlanks(i)
            if k >= le {
                i = le + 1
                continue
            }
            if at(k) == 35 {
                emit(k, le, .comment)
                i = le + 1
                continue
            }
            while le < hi && s[le - 1] == 92 { le = lineEnd(le + 1) }
            var e = k
            while e < le && (SyntaxChar.isIdentPart(s[e]) || s[e] == 45) { e += 1 }
            if e > k, SyntaxBatchWords.makeDirectives.lookup(s, k, e) != nil, e >= le || SyntaxChar.isSpace(s[e]) {
                emit(k, e, .keyword)
                if word(k, e, is: "define") {
                    let nameEnd = lineEnd(e)
                    makeValue(e, nameEnd)
                    let body = nameEnd + 1
                    var q = body
                    while q < hi {
                        let qk = skipBlanks(q)
                        if has(qk, "endef") { break }
                        q = nextLine(q)
                    }
                    makeValue(body, q)
                    i = q
                    continue
                }
                makeAssignmentOrValue(skipBlanks(e), le)
                i = le + 1
                continue
            }
            makeAssignmentOrValue(k, le)
            i = le + 1
        }
    }

    func makeAssignmentOrValue(_ k: Int, _ le: Int) {
        // Find `=` / `:=` / `?=` / `+=` / `!=` / `::=` or a rule colon.
        var j = k
        while j < le {
            let c = s[j]
            if c == 36 && (at(j + 1) == 40 || at(j + 1) == 123) {
                j = matchingClose(j + 1, open: at(j + 1), close: at(j + 1) == 40 ? 41 : 125, multiline: false)
                continue
            }
            if c == 61 || ((c == 58 || c == 63 || c == 43 || c == 33) && at(j + 1) == 61) || (c == 58 && at(j + 1) == 58 && at(j + 2) == 61) {
                emit(k, trimEnd(k, j), .variable)
                var v = j
                while v < le && s[v] != 61 { v += 1 }
                makeValue(v + 1, le)
                return
            }
            if c == 58 {
                var t = k
                while t < j {
                    t = skipBlanks(t)
                    var w = t
                    while w < j && !SyntaxChar.isBlank(s[w]) {
                        if s[w] == 36 && (at(w + 1) == 40 || at(w + 1) == 123) {
                            w = matchingClose(w + 1, open: at(w + 1), close: at(w + 1) == 40 ? 41 : 125, multiline: false)
                            continue
                        }
                        w += 1
                    }
                    w = Swift.min(w, j)
                    if w > t {
                        if at(t) == 36 { makeValue(t, w) } else { emit(t, w, at(t) == 46 && SyntaxChar.isUpper(at(t + 1)) ? .keyword : .function) }
                    }
                    t = Swift.max(w, t + 1)
                }
                var rest = j + 1
                if at(rest) == 58 { rest += 1 }
                if let semicolon = (rest..<le).first(where: { s[$0] == 59 }) {
                    makeValue(rest, semicolon)
                    if depth < SyntaxLexer.maxDepth { sub(semicolon + 1, le).lexShell(.make) }
                } else {
                    makeValue(rest, le)
                }
                return
            }
            j += 1
        }
        makeValue(k, le)
    }

    func makeValue(_ a: Int, _ b: Int) {
        var j = a
        while j < b {
            let c = s[j]
            if c == 35 && (j == a || s[j - 1] != 92) {
                emit(j, Swift.min(lineEnd(j), b), .comment)
                j = lineEnd(j)
                continue
            }
            if c == 36 {
                j = makeReference(j, b)
                continue
            }
            if c == 34 || c == 39 {
                let e = Swift.min(quotedEnd(j, quote: c, escapes: true, multiline: false), b)
                var seg = j
                var q = j + 1
                while q < e {
                    if s[q] == 36 {
                        emit(seg, q, .string)
                        q = makeReference(q, e)
                        seg = q
                        continue
                    }
                    q += 1
                }
                emit(seg, e, .string)
                j = e
                continue
            }
            j += 1
        }
    }

    /// `$(VAR)`, `$(func args)`, `${VAR}`, `$@`, `$$`; returns the index after the reference.
    func makeReference(_ j: Int, _ b: Int) -> Int {
        let n = at(j + 1)
        if n == 40 || n == 123 {
            let close = Swift.min(matchingClose(j + 1, open: n, close: n == 40 ? 41 : 125, multiline: true), b)
            let ns = j + 2
            var ne = ns
            while ne < close && (SyntaxChar.isIdentPart(s[ne]) || s[ne] == 45) { ne += 1 }
            if ne > ns && ne < close && SyntaxChar.isBlank(s[ne]) && SyntaxBatchWords.makeFunctions.lookup(s, ns, ne) != nil {
                emit(j, ns, .variable)
                emit(ns, ne, .function)
                makeValue(ne, close - 1)
                emit(close - 1, close, .variable)
            } else {
                emit(j, close, .variable)
            }
            return Swift.max(close, j + 1)
        }
        if n == 36 {
            emit(j, j + 2, .escape)
            return j + 2
        }
        if n != 0 && !SyntaxChar.isSpace(n) {
            emit(j, j + 2, .variable)
            return j + 2
        }
        return j + 1
    }
}

/// Word tables for the smaller line-oriented lexers.
enum SyntaxBatchWords {
    static let keywords: SyntaxWordTable = {
        var t = SyntaxWordTable(caseInsensitive: true)
        t.add("""
            if else for in do goto call set setlocal endlocal exit echo pause shift not exist defined errorlevel equ \
            neq lss leq gtr geq start cd chdir pushd popd title cls copy xcopy robocopy del erase move mkdir md rmdir \
            rd ren rename type cmd nul con prompt path choice timeout enabledelayedexpansion enableextensions \
            disabledelayedexpansion where findstr find
            """, .keyword)
        return t
    }()

    static let dockerInstructions: SyntaxWordTable = {
        var t = SyntaxWordTable(caseInsensitive: true)
        t.add("FROM RUN CMD LABEL MAINTAINER EXPOSE ENV ADD COPY ENTRYPOINT VOLUME USER WORKDIR ARG ONBUILD STOPSIGNAL HEALTHCHECK SHELL", .keyword)
        return t
    }()

    static let makeDirectives: SyntaxWordTable = {
        var t = SyntaxWordTable()
        t.add("include -include sinclude ifeq ifneq ifdef ifndef else endif define endef export unexport override private vpath undefine", .keyword)
        return t
    }()

    static let makeFunctions: SyntaxWordTable = {
        var t = SyntaxWordTable()
        t.add("""
            shell wildcard patsubst subst foreach call eval filter filter-out sort dir notdir basename suffix addprefix \
            addsuffix join word words wordlist firstword lastword strip findstring if or and info warning error \
            abspath realpath origin flavor value file let intcmp
            """, .function)
        return t
    }()
}

/// PowerShell: cmdlets (`Verb-Noun`), `-Parameters`, `$variables`, `[types]` and string interpolation.
struct SyntaxPowerShellLexer {
    static let keywords: SyntaxWordTable = {
        var t = SyntaxWordTable(caseInsensitive: true)
        t.add("""
            begin break catch class continue data define do dynamicparam else elseif end enum exit filter finally for \
            foreach from function hidden if in param process return static switch throw trap try until using var \
            while workflow parallel sequence inlinescript configuration clean
            """, .keyword)
        return t
    }()

    static let operators: SyntaxWordTable = {
        var t = SyntaxWordTable(caseInsensitive: true)
        t.add("""
            -eq -ne -gt -ge -lt -le -like -notlike -match -notmatch -contains -notcontains -in -notin -replace \
            -creplace -ireplace -split -join -and -or -xor -not -band -bor -bxor -bnot -shl -shr -is -isnot -as -f \
            -ceq -cne -cgt -clt -cge -cle -clike -cnotlike -cmatch -cnotmatch -ieq -ine -csplit -isplit
            """, .keyword)
        return t
    }()

    let L: SyntaxLexer
    let s: UnsafeBufferPointer<UInt16>
    let lo: Int
    let hi: Int
    var commandPosition = true
    var expectFunctionName = false
    var nesting = 0

    init(_ lexer: SyntaxLexer) {
        L = lexer
        s = lexer.s
        lo = lexer.lo
        hi = lexer.hi
    }

    @inline(__always) func at(_ i: Int) -> UInt16 { L.at(i) }
    @inline(__always) func emit(_ a: Int, _ b: Int, _ k: SyntaxTokenKind) { L.emit(a, b, k) }

    mutating func run(_ i: inout Int, closer: UInt16) {
        var parens = 0
        while i < hi {
            let c = s[i]
            if c == 10 {
                i += 1
                commandPosition = true
                continue
            }
            if SyntaxChar.isBlank(c) { i += 1; continue }
            if closer != 0 {
                if c == 40 { parens += 1 } else if c == 41 {
                    if parens == 0 { return }
                    parens -= 1
                }
            }
            let start = i
            step(&i, c)
            if i <= start { i = start + 1 }
        }
    }

    mutating func step(_ i: inout Int, _ c: UInt16) {
        let n = at(i + 1)
        switch c {
        case 60 where n == 35:
            let e = (L.find("#>", from: i + 2)).map { $0 + 2 } ?? hi
            emit(i, e, .comment)
            i = e
        case 35:
            let e = L.lineEnd(i)
            emit(i, e, .comment)
            i = e
        case 34:
            doubleQuoted(&i, from: i, hereString: false)
            commandPosition = false
        case 39:
            var e = i + 1
            while e < hi {
                if s[e] == 39 {
                    if at(e + 1) == 39 { e += 2; continue }
                    e += 1
                    break
                }
                e += 1
            }
            emit(i, Swift.min(e, hi), .string)
            i = Swift.min(e, hi)
            commandPosition = false
        case 64:
            if (n == 34 || n == 39) && (at(i + 2) == 10 || at(i + 2) == 13) {
                // Here-string: ends at a line starting with `"@` / `'@`.
                var q = L.nextLine(i)
                var end = hi
                while q < hi {
                    if at(q) == n && at(q + 1) == 64 { end = q + 2; break }
                    q = L.nextLine(q)
                }
                if n == 34 {
                    var j = i + 1
                    doubleQuoted(&j, from: i, hereString: true, limit: end)
                } else {
                    emit(i, end, .string)
                }
                i = end
            } else if n == 40 || n == 123 {
                emit(i, i + 1, .keyword)
                i += 1
            } else if SyntaxChar.isIdentStart(n) {
                let e = L.identEnd(i + 1)
                emit(i, e, .variable)
                i = e
            } else {
                i += 1
            }
            commandPosition = n == 40 || n == 123 ? true : false
        case 36:
            variable(&i)
            commandPosition = false
        case 96:
            i += 2
        case 91:
            if let e = typeLiteralEnd(i) {
                let inner = i + 1
                var ne = inner
                while ne < e && s[ne] != 40 && s[ne] != 93 { ne += 1 }
                emit(inner, ne, at(ne) == 40 ? .attribute : .type)
                if at(ne) == 40 {
                    // Attribute arguments: `[Parameter(Mandatory, Position = 0)]`.
                    var j = ne + 1
                    while j < e - 1 {
                        let d = s[j]
                        if d == 34 || d == 39 {
                            let q = Swift.min(L.quotedEnd(j, quote: d), e - 1)
                            emit(j, q, .string)
                            j = q
                        } else if d == 36 {
                            var k = j
                            variable(&k)
                            j = Swift.max(k, j + 1)
                        } else if SyntaxChar.isDigit(d) {
                            var k = j
                            while k < e && SyntaxChar.isAlnum(s[k]) { k += 1 }
                            emit(j, k, .number)
                            j = k
                        } else {
                            j += 1
                        }
                    }
                }
                i = e
            } else {
                i += 1
                commandPosition = false
            }
        case 45 where SyntaxChar.isLetter(n) && (i == lo || !SyntaxChar.isIdentPart(s[i - 1])):
            var e = i + 1
            while e < hi && (SyntaxChar.isIdentPart(s[e]) || s[e] == 45) { e += 1 }
            let isOperator = SyntaxPowerShellLexer.operators.lookup(s, i, e) != nil
            emit(i, e, isOperator ? .keyword : .attribute)
            i = e
            if isOperator { commandPosition = false }
        case 124, 59, 123, 40, 61, 38, 44:
            if c == 38 && n == 38 { i += 2 } else { i += 1 }
            if c == 124 && n == 124 { i += 1 }
            commandPosition = true
        case 125, 41, 93:
            i += 1
            commandPosition = false
        default:
            if SyntaxChar.isDigit(c) || (c == 46 && SyntaxChar.isDigit(n)) {
                var e = i
                if c == 48 && (n | 0x20) == 120 {
                    e += 2
                    while e < hi && SyntaxChar.isHex(s[e]) { e += 1 }
                } else {
                    while e < hi && (SyntaxChar.isDigit(s[e]) || s[e] == 46 || s[e] == 95) { e += 1 }
                    if (at(e) | 0x20) == 101 && (SyntaxChar.isDigit(at(e + 1)) || at(e + 1) == 45) {
                        e += 2
                        while SyntaxChar.isDigit(at(e)) { e += 1 }
                    }
                }
                while e < hi && SyntaxChar.isLetter(s[e]) { e += 1 }
                emit(i, e, .number)
                i = e
                commandPosition = false
                return
            }
            if SyntaxChar.isIdentStart(c) {
                word(&i)
                return
            }
            i += 1
        }
    }

    mutating func word(_ i: inout Int) {
        let a = i
        var e = i
        while e < hi {
            let d = s[e]
            if SyntaxChar.isIdentPart(d) { e += 1; continue }
            if d == 45 && SyntaxChar.isLetter(at(e + 1)) { e += 1; continue }
            if commandPosition && (d == 46 || d == 92 || d == 47) && SyntaxChar.isIdentPart(at(e + 1)) { e += 1; continue }
            break
        }
        let afterDot = a > lo && s[a - 1] == 46
        var kind = SyntaxTokenKind.plain
        if !afterDot, SyntaxPowerShellLexer.keywords.lookup(s, a, e) != nil {
            kind = .keyword
            let w = L.string(a, e).lowercased()
            expectFunctionName = w == "function" || w == "filter" || w == "workflow"
            commandPosition = !["function", "filter", "param", "class", "enum", "in"].contains(w)
            emit(a, e, kind)
            i = e
            return
        }
        if expectFunctionName {
            kind = .function
            expectFunctionName = false
        } else if at(e) == 40 {
            kind = .function
        } else if afterDot {
            kind = .plain
        } else if commandPosition || (a..<e).contains(where: { s[$0] == 45 }) {
            kind = .function
        } else if a > lo + 1 && s[a - 1] == 58 && s[a - 2] == 58 {
            kind = .plain
        }
        emit(a, e, kind)
        commandPosition = false
        i = e
    }

    mutating func variable(_ i: inout Int) {
        let n = at(i + 1)
        if n == 40 {
            emit(i, i + 2, .variable)
            i += 2
            guard nesting < 8 else { return }
            let saved = commandPosition
            commandPosition = true
            nesting += 1
            run(&i, closer: 41)
            nesting -= 1
            commandPosition = saved
            if i < hi && s[i] == 41 {
                emit(i, i + 1, .variable)
                i += 1
            }
            return
        }
        if n == 123 {
            let e = L.matchingClose(i + 1, open: 123, close: 125, multiline: false)
            emit(i, e, .variable)
            i = e
            return
        }
        if SyntaxChar.isIdentStart(n) {
            var e = L.identEnd(i + 1)
            if at(e) == 58 && at(e + 1) != 58 && SyntaxChar.isIdentStart(at(e + 1)) { e = L.identEnd(e + 1) }
            let lower = L.string(i + 1, e).lowercased()
            emit(i, e, lower == "true" || lower == "false" || lower == "null" ? .constant : .variable)
            i = e
            return
        }
        if n == 95 || n == 36 || n == 63 || n == 94 {
            emit(i, i + 2, .variable)
            i += 2
            return
        }
        i += 1
    }

    mutating func doubleQuoted(_ i: inout Int, from a: Int, hereString: Bool, limit: Int? = nil) {
        let end = limit ?? hi
        var seg = a
        if !hereString { i = a + 1 }
        while i < end {
            let c = s[i]
            if c == 34 && !hereString {
                if at(i + 1) == 34 { i += 2; continue }
                i += 1
                emit(seg, i, .string)
                return
            }
            if c == 96 && i + 1 < end {
                emit(seg, i, .string)
                emit(i, i + 2, .escape)
                i += 2
                seg = i
                continue
            }
            if c == 36 && (SyntaxChar.isIdentStart(at(i + 1)) || at(i + 1) == 40 || at(i + 1) == 123 || at(i + 1) == 95) {
                emit(seg, i, .string)
                variable(&i)
                seg = i
                continue
            }
            i += 1
        }
        i = Swift.min(i, end)
        emit(seg, i, .string)
    }

    /// `[int]`, `[System.IO.Path]`, `[string[]]`, `[Parameter(Mandatory)]`; returns the index after `]`.
    func typeLiteralEnd(_ i: Int) -> Int? {
        guard SyntaxChar.isLetter(at(i + 1)) else { return nil }
        var j = i + 1
        while j < hi && (SyntaxChar.isIdentPart(s[j]) || s[j] == 46 || s[j] == 96) { j += 1 }
        if at(j) == 40 {
            let close = L.matchingClose(j, open: 40, close: 41, multiline: false, limit: j + 400)
            return at(close) == 93 ? close + 1 : nil
        }
        if at(j) == 91 && at(j + 1) == 93 { j += 2 }
        if at(j) == 44 || at(j) == 91 {
            let limit = Swift.min(hi, i + 200)
            while j < limit && s[j] != 93 && s[j] != 10 { j += 1 }
            if at(j) == 93 && at(j + 1) == 93 { j += 1 }
        }
        return at(j) == 93 ? j + 1 : nil
    }
}
