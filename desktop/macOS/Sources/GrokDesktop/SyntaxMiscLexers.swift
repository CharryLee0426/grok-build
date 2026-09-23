import Foundation

enum SyntaxMiscWords {
    static let lispSpecialForms: SyntaxWordTable = {
        var t = SyntaxWordTable()
        t.add("""
            def defn defn- defmacro defonce defmulti defmethod defprotocol defrecord deftype definterface defstruct ns \
            fn fn* let let* letfn loop recur if if-not when when-not when-let when-some if-let if-some cond condp case \
            do doto quote var try catch finally throw new set! and or not -> ->> as-> cond-> cond->> some-> some->> \
            doseq dotimes for while binding with-open lazy-seq delay future reify proxy extend-type extend-protocol \
            import require use refer in-ns defun defvar defparameter defconstant defclass defgeneric defpackage \
            in-package lambda flet labels macrolet progn prog1 prog2 block return return-from tagbody go unless ecase \
            typecase etypecase do* dolist setf setq psetf incf decf push pop multiple-value-bind destructuring-bind \
            handler-case handler-bind unwind-protect declare declaim the function eval-when with-slots define \
            define-syntax define-record-type define-values λ letrec letrec* let-values named-lambda begin force \
            quasiquote unquote syntax-rules syntax-case module provide struct match parameterize guard call/cc else \
            defcustom defconst defgroup defface interactive save-excursion with-current-buffer condition-case \
            setq-default add-hook define-module export func param result local global memory table elem data type \
            then br br_if call
            """, .keyword)
        return t
    }()

    /// Forms whose next list holds parameters or bindings rather than a call.
    static let lispBinders: SyntaxWordTable = {
        var t = SyntaxWordTable()
        t.add("lambda λ fn named-lambda defmacro defun defmethod defgeneric", .keyword, role: 1)
        t.add("let let* letrec letrec* let-values flet labels macrolet binding loop with-open when-let if-let dotimes doseq for do", .keyword, role: 2)
        return t
    }()

    static let lispDefiners: SyntaxWordTable = {
        var t = SyntaxWordTable()
        t.add("""
            def defn defn- defmacro defonce defmulti defmethod defun defvar defparameter defconstant defgeneric define \
            define-syntax defcustom defconst defface defgroup defprotocol defrecord deftype defstruct defclass func
            """, .keyword)
        return t
    }()

    static let asmDirectives: SyntaxWordTable = {
        var t = SyntaxWordTable(caseInsensitive: true)
        t.add("""
            section segment global globl extern bits default org align db dw dd dq dt ddq do resb resw resd resq rest \
            equ times incbin struc endstruc istruc iend at proc endp ends assume model stack public byte word dword \
            qword tbyte ptr offset near far short end macro endm include
            """, .attribute)
        return t
    }()

    static let asmSizes: SyntaxWordTable = {
        var t = SyntaxWordTable(caseInsensitive: true)
        t.add("byte word dword qword tbyte oword xmmword ymmword zmmword ptr near far short offset rel", .type)
        return t
    }()

    static let asmRegisters: SyntaxWordTable = {
        var t = SyntaxWordTable(caseInsensitive: true)
        t.add("""
            rax rbx rcx rdx rsi rdi rbp rsp rip eax ebx ecx edx esi edi ebp esp eip ax bx cx dx si di bp sp ip al bl \
            cl dl ah bh ch dh sil dil bpl spl cs ds es fs gs ss eflags rflags lr pc fp xzr wzr nzcv cpsr apsr zero ra \
            gp tp
            """, .variable)
        return t
    }()
}

extension SyntaxLexer {
    // MARK: - Lisp family

    func lexLisp(_ flavor: SyntaxLispFlavor) {
        var i = lo
        var head = false
        var defineNext = false
        let clojure = flavor == .clojure
        var depth = 0
        // A list opened at `paramsDepth` is a parameter list; lists opened at `bindingDepth` are bindings.
        var paramsDepth = -1
        var bindingDepth = -1
        var functionQuote = false
        while i < hi {
            let c = s[i]
            if SyntaxChar.isSpace(c) || (c == 44 && clojure) { i += 1; continue }
            switch c {
            case 59:
                let e = lineEnd(i)
                emit(i, e, .comment)
                i = e
                continue
            case 34:
                let e = quotedEnd(i, quote: 34, escapes: true, multiline: true)
                emitEscaped(i, e, .string)
                i = e
                head = false
                continue
            case 40, 91, 123:
                depth += 1
                head = c == 40
                if depth == paramsDepth {
                    head = false
                    paramsDepth = -1
                    if bindingDepth == depth { bindingDepth = depth + 1 }
                } else if depth == bindingDepth {
                    head = false
                }
                if c == 40 { defineNext = false }
                i += 1
                continue
            case 41, 93, 125:
                depth -= 1
                if bindingDepth > depth + 1 { bindingDepth = -1 }
                if paramsDepth > depth + 1 { paramsDepth = -1 }
                head = false
                i += 1
                continue
            case 35:
                let n = at(i + 1)
                if n == 124 {
                    var depth = 1
                    var e = i + 2
                    while e < hi && depth > 0 {
                        if s[e] == 124 && at(e + 1) == 35 { depth -= 1; e += 2; continue }
                        if s[e] == 35 && at(e + 1) == 124 { depth += 1; e += 2; continue }
                        e += 1
                    }
                    emit(i, e, .comment)
                    i = e
                    continue
                }
                if n == 59 || n == 95 {
                    emit(i, i + 2, .comment)
                    i += 2
                    continue
                }
                if n == 34 {
                    let e = quotedEnd(i + 1, quote: 34, escapes: true, multiline: true)
                    emit(i, e, .regex)
                    i = e
                    continue
                }
                if n == 92 {
                    var e = i + 3
                    while e < hi && SyntaxChar.isLetter(s[e]) && SyntaxChar.isLetter(s[e - 1]) { e += 1 }
                    emit(i, Swift.min(e, hi), .string)
                    i = Swift.min(e, hi)
                    continue
                }
                if n == 40 || n == 123 {
                    head = n == 40
                    i += 2
                    continue
                }
                if n == 39 {
                    emit(i, i + 2, .keyword)
                    i += 2
                    functionQuote = true
                    continue
                }
                let e = lispAtomEnd(i + 1, clojure: clojure)
                emit(i, e, .constant)
                i = Swift.max(e, i + 1)
                continue
            case 92 where clojure:
                var e = i + 2
                while e < hi && SyntaxChar.isLetter(s[e]) && SyntaxChar.isLetter(s[i + 1]) { e += 1 }
                emit(i, Swift.min(e, hi), .string)
                i = Swift.min(e, hi)
                continue
            case 39, 96, 126, 64, 94, 44:
                var e = i + 1
                if (c == 126 || c == 44) && at(e) == 64 { e += 1 }
                emit(i, e, .keyword)
                i = e
                if c == 39 || c == 96 {
                    let n = at(i)
                    if n != 40 && n != 91 && n != 123 && !SyntaxChar.isSpace(n) && n != 0 {
                        let ae = lispAtomEnd(i, clojure: clojure)
                        emit(i, ae, .constant)
                        i = Swift.max(ae, i + 1)
                    }
                }
                head = false
                continue
            case 58:
                let e = lispAtomEnd(i, clojure: clojure)
                emit(i, e, .constant)
                i = Swift.max(e, i + 1)
                head = false
                continue
            default:
                break
            }
            let e = lispAtomEnd(i, clojure: clojure)
            guard e > i else {
                i += 1
                continue
            }
            let kind: SyntaxTokenKind
            if lispIsNumber(i, e) {
                kind = .number
            } else if functionQuote {
                kind = .function
            } else if head {
                if SyntaxMiscWords.lispSpecialForms.lookup(s, i, e) != nil {
                    kind = .keyword
                    defineNext = SyntaxMiscWords.lispDefiners.lookup(s, i, e) != nil
                    if let binder = SyntaxMiscWords.lispBinders.lookup(s, i, e) {
                        // `(lambda (x) …)`: next list is params. `(let ((a 1)) …)`: its children are bindings.
                        paramsDepth = depth + 1
                        if binder.role == 2 { bindingDepth = depth + 1 }
                    }
                } else {
                    kind = .function
                }
            } else if defineNext {
                kind = .function
                defineNext = false
                if paramsDepth < 0 { paramsDepth = depth + 1 }
            } else if word(i, e, is: "nil") || word(i, e, is: "t") || word(i, e, is: "true") || word(i, e, is: "false") {
                kind = .constant
            } else if s[i] == 38 {
                kind = .keyword
            } else if s[i] == 42 && e - i > 2 && s[e - 1] == 42 {
                kind = .variable
            } else if clojure && SyntaxChar.isUpper(s[i]) {
                kind = .type
            } else if s[i] == 36 {
                kind = .variable
            } else {
                kind = .plain
            }
            emit(i, e, kind)
            head = false
            functionQuote = false
            i = e
        }
    }

    func lispAtomEnd(_ i: Int, clojure: Bool) -> Int {
        var j = i
        while j < hi {
            let c = s[j]
            if SyntaxChar.isSpace(c) || c == 40 || c == 41 || c == 91 || c == 93 || c == 123 || c == 125 || c == 34 || c == 59 || c == 39 || c == 96 { break }
            if c == 44 && clojure { break }
            j += 1
        }
        return j
    }

    func lispIsNumber(_ a: Int, _ b: Int) -> Bool {
        var j = a
        if s[j] == 45 || s[j] == 43 { j += 1 }
        guard j < b, SyntaxChar.isDigit(s[j]) else { return false }
        for k in j..<b {
            let c = s[k]
            if !(SyntaxChar.isAlnum(c) || c == 46 || c == 47 || c == 95 || ((c == 45 || c == 43) && (s[k - 1] | 0x20) == 101)) { return false }
        }
        return true
    }

    // MARK: - Assembly

    func lexAssembly() {
        var i = lo
        while i < hi {
            let le = lineEnd(i)
            var j = skipBlanks(i)
            let first = j
            var sawMnemonic = false
            var lineDone = false
            while j < le && !lineDone {
                let c = s[j]
                if SyntaxChar.isBlank(c) || c == 44 { j += 1; continue }
                switch c {
                case 59:
                    emit(j, le, .comment)
                    j = le
                    continue
                case 47 where at(j + 1) == 47:
                    emit(j, le, .comment)
                    j = le
                    continue
                case 47 where at(j + 1) == 42:
                    let e = (find("*/", from: j + 2)).map { $0 + 2 } ?? hi
                    emit(j, e, .comment)
                    if e > le {
                        i = e
                        lineDone = true
                        continue
                    }
                    j = e
                    continue
                case 35:
                    let n = at(j + 1)
                    if j == first && SyntaxChar.isLetter(n) {
                        emit(j, identEnd(j + 1), .attribute)
                        j = identEnd(j + 1)
                        continue
                    }
                    if SyntaxChar.isDigit(n) || n == 45 || n == 39 || (n == 48 && at(j + 2) == 120) {
                        let e = asmNumberEnd(n == 45 ? j + 2 : j + 1)
                        emit(j, e, .number)
                        j = e
                        continue
                    }
                    emit(j, le, .comment)
                    j = le
                    continue
                case 64:
                    if at(j + 1) == 0 || SyntaxChar.isSpace(at(j + 1)) {
                        emit(j, le, .comment)
                        j = le
                    } else {
                        let e = identEnd(j + 1)
                        emit(j, e, .attribute)
                        j = Swift.max(e, j + 1)
                    }
                    continue
                case 34, 39:
                    let e = quotedEnd(j, quote: c, escapes: true, multiline: false)
                    emitEscaped(j, e, .string)
                    j = e
                    continue
                case 37:
                    let e = identEnd(j + 1)
                    emit(j, e, j == first ? .attribute : .variable)
                    j = Swift.max(e, j + 1)
                    continue
                case 36:
                    let n = at(j + 1)
                    if SyntaxChar.isDigit(n) || n == 45 {
                        let e = asmNumberEnd(n == 45 ? j + 2 : j + 1)
                        emit(j, e, .number)
                        j = e
                    } else {
                        let e = identEnd(j + 1)
                        emit(j, e, .variable)
                        j = Swift.max(e, j + 1)
                    }
                    continue
                default:
                    break
                }
                if SyntaxChar.isDigit(c) {
                    let e = asmNumberEnd(j)
                    if at(e) == 58 && j == first {
                        emit(j, e + 1, .function)
                        j = e + 1
                        continue
                    }
                    emit(j, e, .number)
                    j = e
                    continue
                }
                if SyntaxChar.isIdentStart(c) || c == 46 {
                    var e = j + 1
                    while e < le && (SyntaxChar.isIdentPart(s[e]) || s[e] == 46 || s[e] == 36) { e += 1 }
                    if at(e) == 58 && at(e + 1) != 58 && !sawMnemonic {
                        emit(j, e + 1, .function)
                        j = e + 1
                        continue
                    }
                    if c == 46 {
                        emit(j, e, sawMnemonic ? .variable : .attribute)
                        sawMnemonic = true
                    } else if !sawMnemonic {
                        let next = skipBlanks(e)
                        var ne = next
                        while ne < le && SyntaxChar.isIdentPart(s[ne]) { ne += 1 }
                        let nextIsData = ne > next && SyntaxMiscWords.asmDirectives.lookup(s, next, ne) != nil && SyntaxMiscWords.asmRegisters.lookup(s, next, ne) == nil
                        if SyntaxMiscWords.asmDirectives.lookup(s, j, e) != nil {
                            emit(j, e, .attribute)
                        } else if nextIsData && j == first {
                            emit(j, e, .function)
                            j = e
                            continue
                        } else {
                            emit(j, e, .keyword)
                        }
                        sawMnemonic = true
                    } else if asmIsRegister(j, e) {
                        emit(j, e, .variable)
                    } else if SyntaxMiscWords.asmSizes.lookup(s, j, e) != nil {
                        emit(j, e, .type)
                    } else if SyntaxMiscWords.asmDirectives.lookup(s, j, e) != nil {
                        emit(j, e, .attribute)
                    }
                    j = e
                    continue
                }
                j += 1
            }
            if !lineDone { i = le + 1 }
        }
    }

    func asmNumberEnd(_ j: Int) -> Int {
        var e = j
        if at(e) == 39 {
            return quotedEnd(e, quote: 39)
        }
        if at(e) == 48 && (at(e + 1) | 0x20) == 120 {
            e += 2
            while e < hi && (SyntaxChar.isHex(s[e]) || s[e] == 95) { e += 1 }
            return e
        }
        while e < hi && (SyntaxChar.isHex(s[e]) || s[e] == 95 || s[e] == 46) { e += 1 }
        if (at(e) | 0x20) == 104 || (at(e) | 0x20) == 111 || (at(e) | 0x20) == 113 { e += 1 }
        return e
    }

    func asmIsRegister(_ a: Int, _ b: Int) -> Bool {
        if SyntaxMiscWords.asmRegisters.lookup(s, a, b) != nil { return true }
        let w = string(a, b).lowercased()
        let prefixes = ["xmm", "ymm", "zmm", "mm", "st", "cr", "dr", "k", "r", "x", "w", "v", "q", "d", "s", "h", "b", "a", "t", "f", "fa", "ft", "fs"]
        for p in prefixes where w.hasPrefix(p) {
            var rest = w.dropFirst(p.count)
            if p == "r", let last = rest.last, "dwb".contains(last), rest.count > 1 { rest = rest.dropLast() }
            if !rest.isEmpty && rest.count <= 2 && rest.allSatisfy({ $0.isNumber }) { return true }
        }
        return false
    }

    // MARK: - Nginx / Apache

    func lexServerConfig(apache: Bool) {
        var i = lo
        var statementStart = true
        var regexNext = false
        var argIndex = 0
        var directive = ""
        while i < hi {
            let c = s[i]
            if c == 10 {
                if apache { statementStart = true }
                i += 1
                continue
            }
            if SyntaxChar.isBlank(c) || (c == 92 && (at(i + 1) == 10 || at(i + 1) == 13)) { i += 1; continue }
            if c == 35 && (statementStart || (i > lo && SyntaxChar.isSpace(s[i - 1]))) {
                let e = lineEnd(i)
                emit(i, e, .comment)
                i = e
                continue
            }
            if (c == 123 || c == 125 || c == 59) && !apache {
                statementStart = true
                regexNext = false
                i += 1
                continue
            }
            if apache && c == 60 && (SyntaxChar.isLetter(at(i + 1)) || at(i + 1) == 47) {
                var e = i + 1
                if at(e) == 47 { e += 1 }
                emit(i, e, .punctuation)
                let ns = e
                while e < hi && (SyntaxChar.isIdentPart(s[e]) || s[e] == 58) { e += 1 }
                emit(ns, e, .tag)
                let close = find(">", from: e, to: lineEnd(e)) ?? lineEnd(e)
                serverArguments(e, close)
                emit(close, close + 1, .punctuation)
                i = Swift.min(close + 1, hi)
                statementStart = true
                continue
            }
            if c == 34 || c == 39 {
                let e = quotedEnd(i, quote: c, escapes: true, multiline: false)
                serverExpand(i, e, regexNext ? .regex : .string)
                i = e
                regexNext = false
                argIndex += 1
                continue
            }
            var e = i
            while e < hi && !SyntaxChar.isSpace(s[e]) && s[e] != 34 && s[e] != 39 {
                if (s[e] == 36 || s[e] == 37) && at(e + 1) == 123 {
                    e = matchingClose(e + 1, open: 123, close: 125, multiline: false)
                    continue
                }
                if !apache && (s[e] == 59 || s[e] == 123 || s[e] == 125) { break }
                e += 1
            }
            if statementStart {
                emit(i, e, .keyword)
                directive = string(i, e).lowercased()
                statementStart = false
                argIndex = 0
                i = e
                continue
            }
            let w = string(i, e)
            if w == "~" || w == "~*" || w == "=" || w == "^~" || w == "!~" || w == "!~*" {
                emit(i, e, .keyword)
                regexNext = w.contains("~")
            } else if regexNext || (apache && ((directive == "rewriterule" || directive.hasSuffix("match")) && argIndex == 0 || directive == "rewritecond" && argIndex == 1)) || (!apache && directive == "rewrite" && argIndex == 0) {
                serverExpand(i, e, .regex)
                regexNext = false
            } else if apache && s[i] == 91 && s[e - 1] == 93 {
                emit(i, e, .attribute)
            } else if ["on", "off", "true", "false", "none"].contains(w.lowercased()) {
                emit(i, e, .constant)
            } else if SyntaxChar.isDigit(s[i]) && w.allSatisfy({ $0.isNumber || $0.isLetter || $0 == "." || $0 == ":" }) && w.count < 16 {
                emit(i, e, .number)
            } else {
                serverExpand(i, e, .plain)
            }
            argIndex += 1
            i = Swift.max(e, i + 1)
        }
    }

    func serverArguments(_ a: Int, _ b: Int) {
        var j = a
        while j < b {
            let c = s[j]
            if c == 34 || c == 39 {
                let e = Swift.min(quotedEnd(j, quote: c), b)
                emit(j, e, .string)
                j = e
                continue
            }
            j += 1
        }
    }

    /// Emits `a..<b` as `base` with `$var`, `${var}`, `%{VAR}` highlighted as variables.
    func serverExpand(_ a: Int, _ b: Int, _ base: SyntaxTokenKind) {
        var seg = a
        var j = a
        while j < b {
            let c = s[j]
            if (c == 36 && (SyntaxChar.isIdentPart(at(j + 1)) || at(j + 1) == 123)) || (c == 37 && at(j + 1) == 123) {
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
}
