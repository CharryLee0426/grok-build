import CoreGraphics
import Foundation

struct MathParseError: Error, CustomStringConvertible {
    let description: String
}

/// Recursive-descent parser from LaTeX math source to a `MathFormula`.
///
/// It works directly on Unicode scalars (no separate tokenizer) because text mode
/// (`\text{…}`) needs the raw characters including spaces. Structural problems
/// (unbalanced braces, unterminated `\left` or environments, unknown environments,
/// missing mandatory arguments) throw; unknown control sequences never do.
final class MathParser {
    /// Why `parseExpression` returned.
    private enum Stop: Equatable {
        case end, closeBrace, right, middle, endEnvironment, cell, row
    }

    private enum RowTerminator: Equatable {
        case environment(String)
        case closeBrace
        case endOfInput
    }

    private struct Rows {
        var rows: [[MathList]] = []
        var horizontalRules: [Int: Int] = [:]
        var extraSpace: [Int: CGFloat] = [:]
    }

    private struct Macro {
        let parameterCount: Int
        let optionalDefault: [Unicode.Scalar]?
        let body: [Unicode.Scalar]
    }

    private var s: [Unicode.Scalar]
    private var pos = 0
    private var macros: [String: Macro]
    private var expansionBudget = 1000
    private let displayMode: Bool
    private var tag: [MathTextSegment]?
    /// `\hline`s seen since the current array row started.
    private var pendingRowRules = 0
    /// Space requested by the most recent `\\[dim]`.
    private var pendingRowSpace: CGFloat?
    private var depth = 0
    /// Recursion limit (real formulas nest < 15 deep); keeps hostile input from
    /// exhausting the stack, since rendering runs on the main thread.
    static let maxDepth = 48

    private init(_ scalars: [Unicode.Scalar], display: Bool, macros: [String: Macro]) {
        self.s = scalars
        self.displayMode = display
        self.macros = macros
    }

    static func parse(_ source: String, display: Bool = true) throws -> MathFormula {
        let parser = MathParser(Array(source.unicodeScalars), display: display, macros: [:])
        let list = try parser.parseTopLevel()
        return MathFormula(list: list, tag: parser.tag)
    }

    private func fail(_ message: String) -> MathParseError {
        MathParseError(description: "\(message) at offset \(pos)")
    }

    // MARK: - Scanning

    private func peek(_ offset: Int = 0) -> Unicode.Scalar? {
        let i = pos + offset
        return i < s.count ? s[i] : nil
    }

    private func advance(_ n: Int = 1) { pos = min(pos + n, s.count) }

    private static func isLetter(_ c: Unicode.Scalar) -> Bool {
        (c.value >= 0x41 && c.value <= 0x5A) || (c.value >= 0x61 && c.value <= 0x7A)
    }

    private static func isSpace(_ c: Unicode.Scalar) -> Bool {
        c == " " || c == "\t" || c == "\n" || c == "\r" || c.value == 0xA0 || c.value == 0x2009 || c.value == 0x200B
    }

    /// Skips whitespace and `%` comments (math mode ignores source spaces).
    private func skipSpaces() {
        while let c = peek() {
            if MathParser.isSpace(c) {
                advance()
            } else if c == "%" {
                while let d = peek(), d != "\n" { advance() }
            } else {
                break
            }
        }
    }

    /// Reads a control sequence name; the current character must be the backslash.
    private func readCommandName() throws -> String {
        advance()  // "\"
        guard let first = peek() else { throw fail("lone backslash") }
        if MathParser.isLetter(first) {
            var name = ""
            while let c = peek(), MathParser.isLetter(c) {
                name.unicodeScalars.append(c)
                advance()
            }
            return name
        }
        advance()
        return String(first)
    }

    private func skipStar() -> Bool {
        if peek() == "*" {
            advance()
            return true
        }
        return false
    }

    /// Raw scalars of a brace group (without the outer braces), or of a single token.
    private func readRawArgument() throws -> [Unicode.Scalar] {
        skipSpaces()
        guard let c = peek() else { throw fail("missing argument") }
        if c == "{" {
            advance()
            let start = pos
            var level = 1
            while let d = peek() {
                if d == "\\" {
                    advance(2)
                    continue
                }
                if d == "{" { level += 1 }
                if d == "}" {
                    level -= 1
                    if level == 0 {
                        let raw = Array(s[start..<pos])
                        advance()
                        return raw
                    }
                }
                advance()
            }
            throw fail("unbalanced braces")
        }
        if c == "}" { throw fail("missing argument") }
        if c == "\\" {
            let start = pos
            _ = try readCommandName()
            return Array(s[start..<pos])
        }
        advance()
        return [c]
    }

    private func readRawString() throws -> String {
        var str = ""
        str.unicodeScalars.append(contentsOf: try readRawArgument())
        return str.trimmingCharacters(in: .whitespaces)
    }

    /// Raw content of an optional `[...]` argument, if present.
    private func readOptionalRaw() -> [Unicode.Scalar]? {
        let save = pos
        skipSpaces()
        guard peek() == "[" else {
            pos = save
            return nil
        }
        advance()
        let start = pos
        var braces = 0
        var brackets = 0
        while let c = peek() {
            if c == "\\" {
                advance(2)
                continue
            }
            if c == "{" { braces += 1 }
            if c == "}" { braces -= 1 }
            if braces == 0 {
                if c == "[" { brackets += 1 }
                if c == "]" {
                    if brackets == 0 {
                        let raw = Array(s[start..<pos])
                        advance()
                        return raw
                    }
                    brackets -= 1
                }
            }
            advance()
        }
        pos = save
        return nil
    }

    private func string(_ scalars: [Unicode.Scalar]) -> String {
        var str = ""
        str.unicodeScalars.append(contentsOf: scalars)
        return str
    }

    /// Parses a math fragment extracted from the source (optional arguments, `$…$`).
    private func subParse(_ scalars: [Unicode.Scalar], style: MathFontStyle) throws -> MathList {
        let child = MathParser(scalars, display: false, macros: macros)
        child.depth = depth + 1
        guard child.depth <= MathParser.maxDepth else { throw fail("nesting too deep") }
        let (list, stop) = try child.parseExpression(style, allowAlignment: false)
        guard stop == .end else { throw fail("unbalanced fragment") }
        return list
    }

    // MARK: - Dimensions

    /// Parses "1.5em", "-3mu", "4pt" … into a space.
    static func dimension(_ text: String) -> MathSpace? {
        let t = text.trimmingCharacters(in: .whitespaces)
        var number = ""
        var rest = Substring(t)
        while let c = rest.first, c.isNumber || c == "." || c == "-" || c == "+" || c == "," {
            number.append(c == "," ? "." : c)
            rest = rest.dropFirst()
        }
        let unit = rest.trimmingCharacters(in: .whitespaces).prefix(2).lowercased()
        let value: CGFloat
        if number == "-" || number == "+" || number.isEmpty {
            value = number == "-" ? -1 : 1
        } else if let v = Double(number) {
            value = CGFloat(v)
        } else {
            return nil
        }
        switch unit {
        case "em": return .em(value)
        case "ex": return .em(value * 0.45)
        case "mu": return .mu(value)
        case "pt", "px": return .em(value / 10)
        case "bp": return .em(value * 0.100375)
        case "pc": return .em(value * 1.2)
        case "dd": return .em(value * 0.107)
        case "cm": return .em(value * 2.845)
        case "mm": return .em(value * 0.2845)
        case "in": return .em(value * 7.227)
        case "sp": return .em(0)
        default: return nil
        }
    }

    /// Reads an inline dimension (`\kern2pt`, `\hskip 1em plus 1fil`).
    private func readInlineDimension() -> MathSpace? {
        skipSpaces()
        if peek() == "{" {
            return (try? readRawString()).flatMap(MathParser.dimension)
        }
        var text = ""
        while let c = peek(), c.properties.numericType != nil || c == "." || c == "-" || c == "+" || c == "," {
            text.unicodeScalars.append(c)
            advance()
        }
        skipSpaces()
        var unit = ""
        while let c = peek(), MathParser.isLetter(c), unit.count < 2 {
            unit.unicodeScalars.append(c)
            advance()
        }
        // Drop TeX glue stretch/shrink ("plus 1fil minus 2pt").
        for keyword in ["plus", "minus"] {
            let save = pos
            skipSpaces()
            if string(Array(s[pos..<min(pos + keyword.count, s.count)])) == keyword {
                advance(keyword.count)
                skipSpaces()
                while let c = peek(), !MathParser.isSpace(c), c != "\\", c != "{", c != "}", c != "$" { advance() }
            } else {
                pos = save
            }
        }
        return MathParser.dimension(text + unit)
    }

    private func readOptionalDimension() -> CGFloat? {
        guard let raw = readOptionalRaw(), let dim = MathParser.dimension(string(raw)) else { return nil }
        switch dim {
        case .em(let v): return v
        case .mu(let v): return v / 18
        }
    }

    // MARK: - Macros

    private func defineMacro(_ name: String) throws {
        switch name {
        case "newcommand", "renewcommand", "providecommand":
            _ = skipStar()
            let target = try readRawString()
            guard target.hasPrefix("\\") else { throw fail("bad \\newcommand") }
            var count = 0
            var optional: [Unicode.Scalar]?
            if let raw = readOptionalRaw() { count = Int(string(raw).trimmingCharacters(in: .whitespaces)) ?? 0 }
            if let raw = readOptionalRaw() { optional = raw }
            let body = try readRawArgument()
            macros[String(target.dropFirst())] = Macro(parameterCount: min(count, 9), optionalDefault: optional, body: body)
        case "def", "gdef", "edef", "xdef":
            skipSpaces()
            guard peek() == "\\" else { throw fail("bad \\def") }
            let target = try readCommandName()
            var count = 0
            while let c = peek(), c != "{" {
                if c == "#" { count += 1 }
                advance()
            }
            let body = try readRawArgument()
            macros[target] = Macro(parameterCount: min(count, 9), optionalDefault: nil, body: body)
        case "DeclareMathOperator":
            let star = skipStar()
            let target = try readRawString()
            let text = try readRawArgument()
            let body = Array((star ? "\\operatorname*{" : "\\operatorname{").unicodeScalars) + text + ["}"]
            macros[String(target.drop(while: { $0 == "\\" }))] = Macro(parameterCount: 0, optionalDefault: nil, body: body)
        default:
            // \let\a\b and friends: consume the two tokens and move on.
            skipSpaces()
            if peek() == "\\" { _ = try readCommandName() }
            skipSpaces()
            if peek() == "=" { advance() }
            skipSpaces()
            _ = try readRawArgument()
        }
    }

    /// Replaces the macro call that ends at `pos` (and its arguments) by its expansion.
    private func expand(_ macro: Macro, callStart: Int) throws {
        expansionBudget -= 1
        guard expansionBudget > 0 else { throw fail("macro expansion limit") }
        var args: [[Unicode.Scalar]] = []
        var remaining = macro.parameterCount
        if let def = macro.optionalDefault, remaining > 0 {
            args.append(readOptionalRaw() ?? def)
            remaining -= 1
        }
        for _ in 0..<remaining { args.append(try readRawArgument()) }
        var out: [Unicode.Scalar] = []
        var i = 0
        let body = macro.body
        while i < body.count {
            if body[i] == "#", i + 1 < body.count, let n = Int(String(body[i + 1])), n >= 1, n <= args.count {
                out.append(contentsOf: args[n - 1])
                i += 2
            } else {
                out.append(body[i])
                i += 1
            }
        }
        // Keep a trailing letter from gluing onto a control word at the end of the expansion.
        if let last = out.last, MathParser.isLetter(last), pos < s.count, MathParser.isLetter(s[pos]) {
            out.append(" ")
        }
        s.replaceSubrange(callStart..<pos, with: out)
        pos = callStart
    }

    // MARK: - Top level & lists

    private func parseTopLevel() throws -> MathList {
        let result = try parseRows(.normal, terminator: .endOfInput)
        let rows = result.rows
        if rows.count == 1 && rows[0].count == 1 { return rows[0][0] }
        if rows.isEmpty { return [] }
        let aligned = rows.contains { $0.count > 1 }
        var array = MathArray(kind: aligned ? .aligned : .gathered, rows: rows)
        array.horizontalRules = result.horizontalRules
        array.extraRowSpace = result.extraSpace
        if aligned { array.rows = MathParser.prefixAlignedCells(rows) }
        return [.atom(MathAtom(.ord, .array(array)))]
    }

    /// amsmath typesets even (left-aligned) align cells as `{}#`, so a leading relation
    /// still gets its spacing.
    private static func prefixAlignedCells(_ rows: [[MathList]]) -> [[MathList]] {
        rows.map { row in
            row.enumerated().map { index, cell in
                index % 2 == 1 && !cell.isEmpty ? [.atom(MathAtom(.ord, .empty))] + cell : cell
            }
        }
    }

    private func parseGroupBody(_ style: MathFontStyle) throws -> MathList {
        let (list, stop) = try parseExpression(style, allowAlignment: false)
        guard stop == .closeBrace else { throw fail("unbalanced braces") }
        return list
    }

    /// Parses list items until a terminator. Handles infix `\over`-style commands.
    private func parseExpression(_ initialStyle: MathFontStyle, allowAlignment: Bool) throws -> (MathList, Stop) {
        depth += 1
        defer { depth -= 1 }
        guard depth <= MathParser.maxDepth else { throw fail("nesting too deep") }
        var list = MathList()
        var style = initialStyle
        var infix: (numerator: MathList, command: String, thickness: CGFloat?)?

        func finish(_ stop: Stop) -> (MathList, Stop) {
            guard let infix = infix else { return (list, stop) }
            var fraction = MathFraction(numerator: infix.numerator, denominator: list, ruleThickness: infix.thickness,
                                        hasRule: infix.command == "over" || infix.command == "above", style: .auto)
            switch infix.command {
            case "choose": (fraction.leftDelimiter, fraction.rightDelimiter) = (0x28, 0x29)
            case "brack": (fraction.leftDelimiter, fraction.rightDelimiter) = (0x5B, 0x5D)
            case "brace": (fraction.leftDelimiter, fraction.rightDelimiter) = (0x7B, 0x7D)
            default: break
            }
            return ([.atom(MathAtom(.inner, .fraction(fraction)))], stop)
        }

        while true {
            skipSpaces()
            guard let c = peek() else { return finish(.end) }
            switch c {
            case "{":
                advance()
                let inner = try parseGroupBody(style)
                list.append(.atom(MathAtom(.ord, .list(inner))))
            case "}":
                advance()
                return finish(.closeBrace)
            case "^", "_":
                advance()
                try attachScript(to: &list, superscript: c == "^", style: style)
            case "'", "\u{2032}", "\u{2033}", "\u{2034}":
                try attachPrimes(to: &list, style: style)
            case "&":
                advance()
                if allowAlignment { return finish(.cell) }
            case "~":
                advance()
                list.append(.space(.em(0.25)))
            case "$", "#":
                advance()
            case "\\":
                let start = pos
                let name = try readCommandName()
                if let macro = macros[name] {
                    try expand(macro, callStart: start)
                    continue
                }
                switch name {
                case "\\", "cr", "newline":
                    _ = skipStar()
                    let extra = readOptionalDimension()
                    if allowAlignment {
                        pendingRowSpace = extra
                        return finish(.row)
                    }
                case "right":
                    return finish(.right)
                case "middle":
                    return finish(.middle)
                case "end":
                    return finish(.endEnvironment)
                case "over", "atop", "choose", "brack", "brace", "above":
                    var thickness: CGFloat?
                    if name == "above", let dim = readInlineDimension() {
                        if case .em(let v) = dim { thickness = v }
                    }
                    if infix == nil {
                        infix = (list, name, thickness)
                        list = []
                    }
                default:
                    try handleCommand(name, into: &list, style: &style)
                }
            default:
                advance()
                try appendCharacter(c, into: &list, style: style)
            }
        }
    }

    // MARK: - Arguments

    /// A mandatory math argument: a brace group or a single token.
    private func parseArgument(_ style: MathFontStyle) throws -> MathList {
        depth += 1
        defer { depth -= 1 }
        guard depth <= MathParser.maxDepth else { throw fail("nesting too deep") }
        while true {
            skipSpaces()
            guard let c = peek() else { throw fail("missing argument") }
            switch c {
            case "{":
                advance()
                return try parseGroupBody(style)
            case "}", "&", "^", "_":
                throw fail("missing argument")
            case "\\":
                let start = pos
                let name = try readCommandName()
                if let macro = macros[name] {
                    try expand(macro, callStart: start)
                    continue
                }
                if ["right", "middle", "end", "\\", "over", "atop", "choose", "cr"].contains(name) {
                    throw fail("missing argument")
                }
                var list = MathList()
                var st = style
                try handleCommand(name, into: &list, style: &st)
                return list
            default:
                advance()
                var list = MathList()
                try appendCharacter(c, into: &list, style: style)
                return list
            }
        }
    }

    private func attachScript(to list: inout MathList, superscript: Bool, style: MathFontStyle) throws {
        let script = try parseArgument(style)
        attach(script, superscript: superscript, to: &list)
    }

    private func attach(_ script: MathList, superscript: Bool, to list: inout MathList) {
        if case .colorGroup(let color, let content)? = list.last {
            list[list.count - 1] = .atom(MathAtom(.ord, .colored(content, color)))
        }
        if case .atom(var atom)? = list.last {
            if superscript, atom.sup == nil {
                atom.sup = script
                list[list.count - 1] = .atom(atom)
                return
            }
            if !superscript, atom.sub == nil {
                atom.sub = script
                list[list.count - 1] = .atom(atom)
                return
            }
        }
        // No base (or a double script): TeX would complain; attach to an empty atom.
        var atom = MathAtom(.ord, .empty)
        if superscript { atom.sup = script } else { atom.sub = script }
        list.append(.atom(atom))
    }

    /// `x'` is `x^{\prime}`, `x''^2` is `x^{\prime\prime 2}`.
    private func attachPrimes(to list: inout MathList, style: MathFontStyle) throws {
        var count = 0
        while let c = peek(), c == "'" || (0x2032...0x2034).contains(c.value) {
            count += c == "'" ? 1 : Int(c.value - 0x2031)
            advance()
        }
        let scalar: UInt32
        switch count {
        case 1: scalar = 0x2032
        case 2: scalar = 0x2033
        case 3: scalar = 0x2034
        default: scalar = 0x2057
        }
        var script: MathList = [.atom(MathAtom(.ord, .symbol(scalar)))]
        if count > 4 {
            script += Array(repeating: .atom(MathAtom(.ord, .symbol(0x2032))), count: count - 4)
        }
        let save = pos
        skipSpaces()
        if peek() == "^" {
            advance()
            script += try parseArgument(style)
        } else {
            pos = save
        }
        if case .atom(let atom)? = list.last, atom.sup != nil {
            // `x^2'`: TeX errors; keep the prime visible instead.
            list.append(.atom(MathAtom(.ord, .empty)))
        }
        attach(script, superscript: true, to: &list)
    }

    // MARK: - Characters

    /// Unicode super/subscript characters (x², aᵢ) typed directly become real scripts.
    private static let superscriptCharacters: [UInt32: UInt32] = [
        0xB2: 0x32, 0xB3: 0x33, 0xB9: 0x31, 0x2070: 0x30, 0x2074: 0x34, 0x2075: 0x35, 0x2076: 0x36,
        0x2077: 0x37, 0x2078: 0x38, 0x2079: 0x39, 0x207A: 0x2B, 0x207B: 0x2212, 0x207C: 0x3D, 0x207D: 0x28,
        0x207E: 0x29, 0x207F: 0x6E, 0x2071: 0x69, 0x1D40: 0x54,
    ]
    private static let subscriptCharacters: [UInt32: UInt32] = [
        0x2080: 0x30, 0x2081: 0x31, 0x2082: 0x32, 0x2083: 0x33, 0x2084: 0x34, 0x2085: 0x35,
        0x2086: 0x36, 0x2087: 0x37, 0x2088: 0x38, 0x2089: 0x39, 0x208A: 0x2B, 0x208B: 0x2212, 0x208C: 0x3D,
        0x208D: 0x28, 0x208E: 0x29, 0x2090: 0x61, 0x2091: 0x65, 0x2092: 0x6F, 0x2093: 0x78, 0x2095: 0x68,
        0x2096: 0x6B, 0x2097: 0x6C, 0x2098: 0x6D, 0x2099: 0x6E, 0x209A: 0x70, 0x209B: 0x73, 0x209C: 0x74,
        0x1D62: 0x69, 0x1D63: 0x72, 0x1D64: 0x75, 0x1D65: 0x76, 0x2C7C: 0x6A,
    ]

    private func appendCharacter(_ c: Unicode.Scalar, into list: inout MathList, style: MathFontStyle) throws {
        let v = c.value
        if MathParser.isSpace(c) { return }
        for (table, isSuperscript) in [(MathParser.superscriptCharacters, true), (MathParser.subscriptCharacters, false)] {
            guard let plain = table[v] else { continue }
            // Consecutive script characters (x²³, aᵢⱼ) form one script.
            var script = MathList()
            var next: UInt32? = plain
            while let c = next {
                try appendCharacter(Unicode.Scalar(c) ?? " ", into: &script, style: style)
                if let p = peek(), let more = table[p.value] {
                    advance()
                    next = more
                } else {
                    next = nil
                }
            }
            attach(script, superscript: isSuperscript, to: &list)
            return
        }
        if v == 0x221A {
            // A typed radical sign takes the next argument, like \sqrt; alone it is a symbol.
            let save = pos
            if let radicand = try? parseArgument(style) {
                list.append(.atom(MathAtom(.ord, .radical(degree: nil, radicand: radicand))))
                return
            }
            pos = save
        }
        switch v {
        case 0x2D, 0x2212:  // hyphen-minus → minus sign
            list.append(.atom(MathAtom(.bin, .symbol(0x2212))))
        case 0x2A:
            list.append(.atom(MathAtom(.bin, .symbol(0x2217))))
        case 0xB7:  // middle dot typed directly means \cdot
            list.append(.atom(MathAtom(.bin, .symbol(0x22C5))))
        case 0x2026, 0x22EF, 0x22F1:
            list.append(.atom(MathAtom(.inner, .symbol(v))))
        case 0x22:
            list.append(.atom(MathAtom(.ord, .symbol(0x201D))))
        default:
            if TeXSymbolTable.largeOperatorScalars.contains(v) {
                let limits: MathLimits = (0x222B...0x2233).contains(v) || (0x2A0B...0x2A1C).contains(v) ? .never : .displayOnly
                list.append(.atom(MathAtom(.op, .largeOperator(v), limits: limits)))
                return
            }
            let type = TeXSymbolTable.characterClasses[v] ?? .ord
            let mapped = MathAlphabet.map(v, style: style)
            list.append(.atom(MathAtom(type, .symbol(mapped))))
        }
    }

    // MARK: - Delimiters

    /// Reads the delimiter after `\left`, `\right`, `\middle`, `\big…`; nil for `.`.
    private func parseDelimiter() throws -> UInt32? {
        skipSpaces()
        guard let c = peek() else { throw fail("missing delimiter") }
        if c == "\\" {
            let name = try readCommandName()
            if let d = TeXSymbolTable.delimiterCommands[name] { return d }
            if let sym = TeXSymbolTable.symbols[name], TeXSymbolTable.delimiterCharacters[sym.scalar] != nil {
                return sym.scalar
            }
            throw fail("unknown delimiter \\\(name)")
        }
        advance()
        if c == "." { return nil }
        if let d = TeXSymbolTable.delimiterCharacters[c.value] { return d }
        if c == "{" || c == "}" { throw fail("bad delimiter") }
        throw fail("unknown delimiter")
    }

    /// Body of `\left…\right`, with `\middle` delimiters inlined.
    private func parseLeftRight(_ style: MathFontStyle) throws -> MathAtom {
        let left = try parseDelimiter()
        var body = MathList()
        while true {
            let (segment, stop) = try parseExpression(style, allowAlignment: false)
            body += segment
            switch stop {
            case .right:
                let right = try parseDelimiter()
                return MathAtom(.inner, .delimited(MathDelimited(left: left, right: right, body: body)))
            case .middle:
                let middle = try parseDelimiter()
                body.append(.atom(MathAtom(.open, .middleDelimiter(middle))))
            default:
                throw fail("unterminated \\left")
            }
        }
    }

    // MARK: - Commands

    private static let fontCommands: [String: MathFontStyle] = [
        "mathrm": .roman, "mathup": .roman, "mathit": .italic, "mathbf": .bold, "mathbfup": .bold,
        "mathbfit": .boldItalic, "boldsymbol": .boldSymbol, "bm": .boldSymbol, "pmb": .boldSymbol,
        "mathbb": .doubleStruck, "mathbbm": .doubleStruck, "Bbb": .doubleStruck, "mathds": .doubleStruck,
        "mathcal": .script, "mathscr": .roundhandScript, "mathbfcal": .boldScript, "mathbfscr": .boldScript,
        "mathfrak": .fraktur, "frak": .fraktur, "mathbffrak": .boldFraktur, "mathsf": .sansSerif,
        "mathsfup": .sansSerif, "mathbfsf": .sansSerifBold, "mathsfbf": .sansSerifBold,
        "mathsfit": .sansSerifItalic, "mathtt": .monospace, "mathnormal": .normal, "mit": .normal,
    ]

    private static let fontSwitches: [String: MathFontStyle] = [
        "rm": .roman, "bf": .bold, "it": .italic, "cal": .script, "sf": .sansSerif, "tt": .monospace,
        "frak": .fraktur, "Bbb": .doubleStruck,
    ]

    private static let textCommands: [String: MathTextFace] = [
        "text": .regular, "textrm": .regular, "textnormal": .regular, "textup": .regular, "textmd": .regular,
        "mbox": .regular, "hbox": .regular, "textbf": .bold, "textit": .italic, "textsl": .italic,
        "emph": .italic, "texttt": .monospace, "textsf": .sansSerif, "mathtext": .regular,
    ]

    private static let spaces: [String: MathSpace] = [
        ",": .mu(3), ":": .mu(4), ">": .mu(4), ";": .mu(5), "!": .mu(-3), " ": .em(0.25), "\t": .em(0.25),
        "\n": .em(0.25), "quad": .em(1), "qquad": .em(2), "enspace": .em(0.5), "enskip": .em(0.5),
        "thinspace": .mu(3), "medspace": .mu(4), "thickspace": .mu(5), "negthinspace": .mu(-3),
        "negmedspace": .mu(-4), "negthickspace": .mu(-5), "space": .em(0.25), "nobreakspace": .em(0.25),
        "hfill": .em(1), "hfil": .em(1), "hss": .em(0), "wr": .em(0),
    ]

    private static let ignored: Set<String> = [
        "nonumber", "notag", "displaybreak", "allowbreak", "nobreak", "relax", "protect", "centering",
        "par", "noindent", "hdashline", "tiny", "scriptsize", "footnotesize", "small", "normalsize",
        "large", "Large", "LARGE", "huge", "Huge", "limits", "nolimits", "displaylimits", "global",
        "left.", "smallskip", "medskip", "bigskip", "leavevmode", "ignorespaces", "unskip",
        "normalfont", "selectfont", "makebox", "hline", "mathclap", "mathllap", "mathrlap",
    ]

    private static let extensibleArrows: [String: UInt32] = [
        "xrightarrow": 0x2192, "xleftarrow": 0x2190, "xleftrightarrow": 0x2194, "xRightarrow": 0x21D2,
        "xLeftarrow": 0x21D0, "xLeftrightarrow": 0x21D4, "xmapsto": 0x21A6, "xhookrightarrow": 0x21AA,
        "xhookleftarrow": 0x21A9, "xtwoheadrightarrow": 0x21A0, "xtwoheadleftarrow": 0x219E,
        "xrightharpoonup": 0x21C0, "xrightharpoondown": 0x21C1, "xleftharpoonup": 0x21BC,
        "xleftharpoondown": 0x21BD, "xrightleftharpoons": 0x21CC, "xleftrightharpoons": 0x21CB,
        "xlongequal": 0x3D, "xLongrightarrow": 0x21D2, "xlongrightarrow": 0x2192,
    ]

    private func appendSymbol(_ scalar: UInt32, _ type: MathAtomType, into list: inout MathList, style: MathFontStyle) {
        list.append(.atom(MathAtom(type, .symbol(MathAlphabet.map(scalar, style: style)))))
    }

    /// Handles every control sequence that is not a list terminator.
    private func handleCommand(_ name: String, into list: inout MathList, style: inout MathFontStyle) throws {
        // Special cases first (they shadow symbol-table entries).
        switch name {
        case "colon":
            list.append(.space(.mu(2)))
            list.append(.atom(MathAtom(.ord, .symbol(0x3A))))
            list.append(.space(.mu(6)))
            return
        case "iff", "implies", "impliedby":
            let scalar: UInt32 = name == "iff" ? 0x27FA : (name == "implies" ? 0x27F9 : 0x27F8)
            list.append(.space(.mu(5)))
            list.append(.atom(MathAtom(.rel, .symbol(scalar))))
            list.append(.space(.mu(5)))
            return
        case "limits", "nolimits", "displaylimits":
            if case .atom(var atom)? = list.last, atom.type == .op {
                atom.limits = name == "limits" ? .always : (name == "nolimits" ? .never : .displayOnly)
                list[list.count - 1] = .atom(atom)
            }
            return
        case "hline", "hdashline":
            pendingRowRules += 1
            return
        default:
            break
        }

        if let symbol = TeXSymbolTable.symbols[name] {
            appendSymbol(symbol.scalar, symbol.type, into: &list, style: style)
            return
        }
        if let op = TeXSymbolTable.largeOperators[name] {
            list.append(.atom(MathAtom(.op, .largeOperator(op.scalar), limits: op.limits)))
            return
        }
        if let op = TeXSymbolTable.namedOperators[name] {
            list.append(.atom(MathAtom(.op, .operatorName(op.text), limits: op.limits)))
            return
        }
        if let space = MathParser.spaces[name] {
            list.append(.space(space))
            return
        }
        if let accent = TeXSymbolTable.accents[name] {
            let body = try parseArgument(style)
            list.append(.atom(MathAtom(.ord, .accent(MathAccent(scalar: accent.scalar, body: body,
                                                                  stretchy: accent.stretchy, under: accent.under)))))
            return
        }
        if let font = MathParser.fontCommands[name] {
            let body = try parseArgument(font)
            list.append(.atom(MathAtom(.ord, .list(body))))
            return
        }
        if let font = MathParser.fontSwitches[name] {
            style = font
            return
        }
        if let face = MathParser.textCommands[name] {
            let segments = try parseTextArgument(face)
            list.append(.atom(MathAtom(.ord, .text(segments))))
            return
        }
        if let arrow = MathParser.extensibleArrows[name] {
            let below = try readOptionalRaw().map { try subParse($0, style: style) }
            let above = try parseArgument(style)
            list.append(.atom(MathAtom(.rel, .extensibleArrow(scalar: arrow, over: above.isEmpty ? nil : above,
                                                              under: (below?.isEmpty ?? true) ? nil : below))))
            return
        }
        if MathParser.ignored.contains(name) { return }
        if let command = MathParser.commands[name] {
            try handleStructural(command, name, into: &list, style: style)
        } else {
            // Unknown control sequence: show it literally so the rest still renders.
            list.append(.atom(MathAtom(.ord, .unknownCommand("\\" + name))))
        }
    }

    /// Structural commands, dispatched through a table so the (recursive) handlers
    /// keep small stack frames even in unoptimized builds.
    private enum Command {
        case fraction, binomial, genfrac, sqrt, left, big, bar, brace, stack, operatorName, mathop, mathClass
        case begin, styleSwitch, color, textcolor, colorbox, boxed, fbox, cancel, phantom, smash, mathstrut, strut
        case not, neq, lowDots, centerDots, smartDots, diagonalDots, antiDiagonalDots, bmod, modulo, substack, tag
        case skipArgument, hspace, kern, macro, ensuremath, paired, derivative, multicolumn, chemistry
    }

    private static let commands: [String: Command] = {
        var table: [String: Command] = [:]
        func add(_ command: Command, _ names: [String]) { for n in names { table[n] = command } }
        add(.fraction, ["frac", "dfrac", "tfrac", "cfrac"])
        add(.binomial, ["binom", "dbinom", "tbinom"])
        add(.genfrac, ["genfrac"])
        add(.sqrt, ["sqrt"])
        add(.left, ["left"])
        add(.big, ["big", "Big", "bigg", "Bigg", "bigl", "Bigl", "biggl", "Biggl", "bigr", "Bigr", "biggr", "Biggr",
                   "bigm", "Bigm", "biggm", "Biggm"])
        add(.bar, ["overline", "underline"])
        add(.brace, ["overbrace", "underbrace", "overbracket", "underbracket"])
        add(.stack, ["overset", "underset", "stackrel"])
        add(.operatorName, ["operatorname", "operatornamewithlimits"])
        add(.mathop, ["mathop"])
        add(.mathClass, ["mathbin", "mathrel", "mathord", "mathopen", "mathclose", "mathpunct", "mathinner"])
        add(.begin, ["begin"])
        add(.styleSwitch, ["displaystyle", "textstyle", "scriptstyle", "scriptscriptstyle"])
        add(.color, ["color"])
        add(.textcolor, ["textcolor"])
        add(.colorbox, ["colorbox", "fcolorbox"])
        add(.boxed, ["boxed"])
        add(.fbox, ["fbox", "framebox"])
        add(.cancel, ["cancel", "bcancel", "xcancel", "sout"])
        add(.phantom, ["phantom", "hphantom", "vphantom"])
        add(.smash, ["smash"])
        add(.mathstrut, ["mathstrut"])
        add(.strut, ["strut"])
        add(.not, ["not"])
        add(.neq, ["neq", "ne"])
        add(.lowDots, ["ldots", "dotsc", "dotso", "mathellipsis", "textellipsis"])
        add(.centerDots, ["cdots", "dotsb", "dotsm", "dotsi", "midhdots"])
        add(.smartDots, ["dots"])
        add(.diagonalDots, ["ddots"])
        add(.antiDiagonalDots, ["iddots", "adots"])
        add(.bmod, ["bmod"])
        add(.modulo, ["pmod", "mod", "pod"])
        add(.substack, ["substack"])
        add(.tag, ["tag"])
        add(.skipArgument, ["label", "cline", "eqref", "ref", "vspace", "hyperref", "href", "url", "leftroot", "uproot"])
        add(.chemistry, ["ce", "pu"])
        add(.hspace, ["hspace", "mspace"])
        add(.kern, ["kern", "mkern", "hskip", "mskip"])
        add(.macro, ["newcommand", "renewcommand", "providecommand", "def", "gdef", "edef", "xdef",
                     "DeclareMathOperator", "let"])
        add(.ensuremath, ["ensuremath"])
        add(.paired, ["abs", "norm", "ket", "bra", "ceil", "floor", "expval", "braket"])
        add(.derivative, ["dv", "pdv", "odv"])
        add(.multicolumn, ["multicolumn"])
        return table
    }()

    private func handleStructural(_ command: Command, _ name: String, into list: inout MathList,
                                  style: MathFontStyle) throws {
        switch command {
        case .fraction, .binomial, .genfrac:
            list.append(.atom(try parseFraction(command, name, style)))
        case .sqrt:
            list.append(.atom(try parseRadical(style)))
        case .left:
            list.append(.atom(try parseLeftRight(style)))
        case .big:
            list.append(.atom(try parseBigDelimiter(name)))
        case .bar, .brace, .stack, .operatorName, .mathop, .mathClass:
            list.append(.atom(try parseDecorated(command, name, style)))
        case .begin:
            list.append(.atom(try parseEnvironment(style)))
        case .styleSwitch:
            let levels: [String: MathStyleLevel] = ["displaystyle": .display, "textstyle": .text,
                                                    "scriptstyle": .script, "scriptscriptstyle": .scriptScript]
            list.append(.style(levels[name] ?? .text))
        case .color, .textcolor, .colorbox:
            try parseColorCommand(command, name, into: &list, style: style)
        case .boxed, .fbox, .cancel, .phantom, .smash, .mathstrut, .strut, .ensuremath, .multicolumn:
            list.append(.atom(try parseBoxLike(command, name, style)))
        case .not:
            try parseNot(into: &list, style: style)
        case .neq:
            appendSymbol(0x2260, .rel, into: &list, style: .roman)
        case .lowDots:
            list.append(.atom(MathAtom(.inner, .symbol(0x2026))))
        case .centerDots:
            list.append(.atom(MathAtom(.inner, .symbol(0x22EF))))
        case .smartDots:
            list.append(.atom(MathAtom(.inner, .symbol(smartDotsUseCenter() ? 0x22EF : 0x2026))))
        case .diagonalDots:
            list.append(.atom(MathAtom(.inner, .symbol(0x22F1))))
        case .antiDiagonalDots:
            list.append(.atom(MathAtom(.inner, .symbol(0x22F0))))
        case .bmod:
            list.append(.atom(MathAtom(.bin, .operatorName("mod"))))
        case .modulo:
            try parseModulo(name, into: &list, style: style)
        case .substack:
            list.append(.atom(MathAtom(.ord, .array(try parseSubstack(style)))))
        case .tag:
            let star = skipStar()
            let segments = try parseTextArgument(.regular)
            tag = star ? segments : [.run("(", .regular)] + segments + [.run(")", .regular)]
        case .skipArgument:
            if name == "vspace" { _ = skipStar() }
            _ = try readRawArgument()
        case .hspace:
            _ = skipStar()
            if let dim = MathParser.dimension(try readRawString()) { list.append(.space(dim)) }
        case .kern:
            if let dim = readInlineDimension() { list.append(.space(dim)) }
        case .macro:
            try defineMacro(name)
        case .paired:
            try parsePairedDelimiter(name, into: &list, style: style)
        case .derivative:
            try parseDerivative(name, into: &list, style: style)
        case .chemistry:
            let raw = string(try readRawArgument())
            let latex = TeXChemistry.latex(from: raw)
            list.append(.atom(MathAtom(.ord, .list(try subParse(Array(latex.unicodeScalars), style: .roman)))))
        }
    }

    private func parseFraction(_ command: Command, _ name: String, _ style: MathFontStyle) throws -> MathAtom {
        var fraction: MathFraction
        switch command {
        case .binomial:
            let num = try parseArgument(style)
            let den = try parseArgument(style)
            fraction = MathFraction(numerator: num, denominator: den, ruleThickness: nil, hasRule: false,
                                    style: name == "dbinom" ? .display : (name == "tbinom" ? .text : .auto))
            fraction.leftDelimiter = 0x28
            fraction.rightDelimiter = 0x29
        case .genfrac:
            let leftRaw = try readRawString()
            let rightRaw = try readRawString()
            let thicknessRaw = try readRawString()
            let styleRaw = try readRawString()
            let num = try parseArgument(style)
            let den = try parseArgument(style)
            var thickness: CGFloat?
            if case .em(let v)? = MathParser.dimension(thicknessRaw) { thickness = v }
            fraction = MathFraction(numerator: num, denominator: den, ruleThickness: thickness,
                                    hasRule: thickness.map { $0 > 0 } ?? true,
                                    style: styleRaw == "0" ? .display : (styleRaw == "1" ? .text : .auto))
            fraction.leftDelimiter = MathParser.delimiter(fromRaw: leftRaw)
            fraction.rightDelimiter = MathParser.delimiter(fromRaw: rightRaw)
        default:
            if name == "cfrac" { _ = readOptionalRaw() }
            let num = try parseArgument(style)
            let den = try parseArgument(style)
            fraction = MathFraction(numerator: num, denominator: den, ruleThickness: nil, hasRule: true,
                                    style: name == "dfrac" || name == "cfrac" ? .display : (name == "tfrac" ? .text : .auto))
            fraction.continued = name == "cfrac"
        }
        return MathAtom(.inner, .fraction(fraction))
    }

    private func parseRadical(_ style: MathFontStyle) throws -> MathAtom {
        let degree = try readOptionalRaw().map { try subParse($0, style: style) }
        let radicand = try parseArgument(style)
        return MathAtom(.ord, .radical(degree: (degree?.isEmpty ?? true) ? nil : degree, radicand: radicand))
    }

    private func parseBigDelimiter(_ name: String) throws -> MathAtom {
        let size: Int
        if name.hasPrefix("Bigg") { size = 4 } else if name.hasPrefix("bigg") { size = 3 } else if name.hasPrefix("Big") { size = 2 } else { size = 1 }
        let type: MathAtomType
        switch name.last {
        case "l": type = .open
        case "r": type = .close
        case "m": type = .rel
        default: type = .ord
        }
        return MathAtom(type, .bigDelimiter(try parseDelimiter(), size: size))
    }

    private func parseDecorated(_ command: Command, _ name: String, _ style: MathFontStyle) throws -> MathAtom {
        switch command {
        case .bar:
            let body = try parseArgument(style)
            return MathAtom(.ord, name == "overline" ? .overline(body) : .underline(body))
        case .brace:
            let body = try parseArgument(style)
            let over = name.hasPrefix("over")
            let scalar: UInt32 = name.hasSuffix("brace") ? (over ? 0x23DE : 0x23DF) : (over ? 0x23B4 : 0x23B5)
            return MathAtom(.op, .horizontalBrace(scalar: scalar, body: body, over: over), limits: .always)
        case .stack:
            // amsmath: \overset{a}{b} takes the class of b (so `\overset{def}{=}` is a relation).
            let script = try parseArgument(style)
            let base = try parseArgument(style)
            var type: MathAtomType = .ord
            if base.count == 1, let atom = base[0].atom, atom.type == .rel || atom.type == .bin { type = atom.type }
            if name == "stackrel" { type = .rel }
            var atom = MathAtom(type, .list(base), limits: .always)
            if name == "underset" { atom.sub = script } else { atom.sup = script }
            return atom
        case .operatorName:
            let star = skipStar() || name == "operatornamewithlimits"
            let raw = try readRawArgument()
            let limits: MathLimits = star ? .displayOnly : .never
            if raw.allSatisfy({ MathParser.isLetter($0) || $0 == " " || ("0"..."9").contains($0) }) {
                return MathAtom(.op, .operatorName(string(raw).trimmingCharacters(in: .whitespaces)), limits: limits)
            }
            return MathAtom(.op, .list(try subParse(raw, style: .roman)), limits: limits)
        case .mathop:
            let body = try parseArgument(style)
            if body.count == 1, var atom = body[0].atom, case .symbol(let v) = atom.nucleus,
               TeXSymbolTable.largeOperatorScalars.contains(v) {
                atom.type = .op
                atom.nucleus = .largeOperator(v)
                atom.limits = .displayOnly
                return atom
            }
            return MathAtom(.op, .list(body), limits: .displayOnly)
        default:
            let body = try parseArgument(style)
            let types: [String: MathAtomType] = ["mathbin": .bin, "mathrel": .rel, "mathord": .ord, "mathopen": .open,
                                                 "mathclose": .close, "mathpunct": .punct, "mathinner": .inner]
            return MathAtom(types[name] ?? .ord, .list(body))
        }
    }

    private func parseColorCommand(_ command: Command, _ name: String, into list: inout MathList,
                                   style: MathFontStyle) throws {
        let model = readOptionalRaw().map(string)
        switch command {
        case .color:
            let spec = try readRawString()
            if let color = MathColorParser.color(spec, model: model) { list.append(.color(color)) }
        case .textcolor:
            let spec = try readRawString()
            let body = try parseArgument(style)
            if let color = MathColorParser.color(spec, model: model) {
                list.append(.colorGroup(color, body))
            } else {
                list.append(.atom(MathAtom(.ord, .list(body))))
            }
        default:  // \colorbox{c}{text}, \fcolorbox{frame}{c}{text}
            if name == "fcolorbox" { _ = try readRawString() }
            let spec = try readRawString()
            let segments = try parseTextArgument(.regular)
            let color = MathColorParser.color(spec, model: model) ?? CGColor(srgbRed: 1, green: 1, blue: 0.6, alpha: 1)
            list.append(.atom(MathAtom(.ord, .colorBox([.atom(MathAtom(.ord, .text(segments)))], color))))
        }
    }

    private func parseBoxLike(_ command: Command, _ name: String, _ style: MathFontStyle) throws -> MathAtom {
        switch command {
        case .boxed:
            return MathAtom(.ord, .boxed(try parseArgument(style)))
        case .fbox:
            _ = readOptionalRaw()
            let segments = try parseTextArgument(.regular)
            return MathAtom(.ord, .boxed([.style(.text), .atom(MathAtom(.ord, .text(segments)))]))
        case .cancel:
            let kind: MathCancelKind = name == "bcancel" ? .backward : (name == "xcancel" ? .cross : .forward)
            return MathAtom(.ord, .cancel(try parseArgument(style), kind))
        case .phantom:
            return MathAtom(.ord, .phantom(try parseArgument(style), horizontal: name != "vphantom", vertical: name != "hphantom"))
        case .smash:
            let option = readOptionalRaw().map(string) ?? ""
            return MathAtom(.ord, .smash(try parseArgument(style), top: option != "b", bottom: option != "t"))
        case .mathstrut:
            return MathAtom(.ord, .phantom([.atom(MathAtom(.open, .symbol(0x28)))], horizontal: false, vertical: true))
        case .strut:
            return MathAtom(.ord, .strut(height: 0.84, depth: 0.36))
        case .multicolumn:
            _ = try readRawArgument()
            _ = try readRawArgument()
            return MathAtom(.ord, .list(try parseArgument(style)))
        default:  // \ensuremath
            return MathAtom(.ord, .list(try parseArgument(style)))
        }
    }

    /// amsmath `\pmod{n}` = `\quad(\mathrm{mod}\ n)`, `\mod{n}`, `\pod{n}`.
    private func parseModulo(_ name: String, into list: inout MathList, style: MathFontStyle) throws {
        let body = try parseArgument(style)
        let lead: CGFloat = displayMode ? 18 : (name == "mod" ? 12 : 8)
        list.append(.space(.mu(lead)))
        if name != "mod" { list.append(.atom(MathAtom(.open, .symbol(0x28)))) }
        if name != "pod" {
            list.append(.atom(MathAtom(.ord, .operatorName("mod"))))
            list.append(.space(.mu(6)))
        }
        list.append(.atom(MathAtom(.ord, .list(body))))
        if name != "mod" { list.append(.atom(MathAtom(.close, .symbol(0x29)))) }
    }

    private static func delimiter(fromRaw raw: String) -> UInt32? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t == "." { return nil }
        if t.hasPrefix("\\") { return TeXSymbolTable.delimiterCommands[String(t.dropFirst())] }
        return t.unicodeScalars.first.flatMap { TeXSymbolTable.delimiterCharacters[$0.value] }
    }

    /// amsmath's `\dots` looks ahead: before a binary operator or relation it means `\cdots`.
    private func smartDotsUseCenter() -> Bool {
        let save = pos
        defer { pos = save }
        skipSpaces()
        guard let c = peek() else { return false }
        if c == "\\" {
            guard let name = try? readCommandName() else { return false }
            if let sym = TeXSymbolTable.symbols[name] { return sym.type == .bin || sym.type == .rel }
            return false
        }
        if let type = TeXSymbolTable.characterClasses[c.value] { return type == .bin || type == .rel }
        return false
    }

    private func parseNot(into list: inout MathList, style: MathFontStyle) throws {
        skipSpaces()
        guard peek() != nil, peek() != "}" else {
            list.append(.atom(MathAtom(.rel, .symbol(0x29F8))))
            return
        }
        var next = try parseArgument(style)
        if next.count == 1, var atom = next[0].atom, case .symbol(let v) = atom.nucleus,
           let negated = TeXSymbolTable.negation(of: v) {
            atom.nucleus = .symbol(negated)
            next[0] = .atom(atom)
            list += next
            return
        }
        var type: MathAtomType = .rel
        if next.count == 1, let atom = next[0].atom { type = atom.type == .ord ? .rel : atom.type }
        list.append(.atom(MathAtom(type, .negated(next))))
    }

    /// `\abs{x}`, `\norm{x}`, `\ket{ψ}`, `\braket{a|b}` (mathtools / physics / braket idioms).
    private func parsePairedDelimiter(_ name: String, into list: inout MathList, style: MathFontStyle) throws {
        _ = skipStar()
        _ = readOptionalRaw()
        var body = try parseArgument(style)
        let pair: (UInt32?, UInt32?)
        switch name {
        case "abs": pair = (0x7C, 0x7C)
        case "norm": pair = (0x2016, 0x2016)
        case "ket": pair = (0x7C, 0x27E9)
        case "bra": pair = (0x27E8, 0x7C)
        case "ceil": pair = (0x2308, 0x2309)
        case "floor": pair = (0x230A, 0x230B)
        default: pair = (0x27E8, 0x27E9)
        }
        if name == "braket" {
            // physics-style \braket{a}{b} takes a second argument.
            let save = pos
            skipSpaces()
            if peek() == "{" {
                let second = try parseArgument(style)
                body = body + [.atom(MathAtom(.open, .middleDelimiter(0x7C)))] + second
            } else {
                pos = save
                body = body.map { item in
                    if case .atom(let a) = item, case .symbol(0x7C) = a.nucleus, a.sup == nil, a.sub == nil {
                        return .atom(MathAtom(.open, .middleDelimiter(0x7C)))
                    }
                    return item
                }
            }
        }
        list.append(.atom(MathAtom(.inner, .delimited(MathDelimited(left: pair.0, right: pair.1, body: body)))))
    }

    /// physics-package `\dv[n]{f}{x}` / `\pdv{f}{x}` (one argument: `d/dx`).
    private func parseDerivative(_ name: String, into list: inout MathList, style: MathFontStyle) throws {
        let order = readOptionalRaw().flatMap { try? subParse($0, style: .roman) }
        let first = try parseArgument(style)
        let save = pos
        skipSpaces()
        var second: MathList?
        if peek() == "{" { second = try parseArgument(style) } else { pos = save }
        let d: UInt32 = name == "pdv" ? MathAlphabet.map(0x2202, style: .normal) : 0x64
        func differential(_ power: MathList?) -> MathListItem {
            var atom = MathAtom(.ord, .symbol(d))
            atom.sup = power
            return .atom(atom)
        }
        var variable = MathAtom(.ord, .list(second ?? first))
        variable.sup = order
        let numerator: MathList = second == nil ? [differential(order)] : [differential(order)] + first
        let denominator: MathList = [differential(nil), .atom(variable)]
        list.append(.atom(MathAtom(.inner, .fraction(MathFraction(numerator: numerator, denominator: denominator,
                                                                  ruleThickness: nil, hasRule: true, style: .auto)))))
    }

    // MARK: - Environments

    private func parseEnvironment(_ style: MathFontStyle) throws -> MathAtom {
        let rawName = try readRawString()
        let name = rawName.replacingOccurrences(of: " ", with: "")
        var kind: MathArrayKind
        var left: UInt32?
        var right: UInt32?
        var alignments: [MathColumnAlignment] = []
        var verticalRules: [Int: Int] = [:]
        var isAligned = false

        switch name {
        case "matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix",
             "matrix*", "pmatrix*", "bmatrix*", "Bmatrix*", "vmatrix*", "Vmatrix*":
            kind = .matrix
            if name.hasSuffix("*"), let raw = readOptionalRaw() {
                let a = MathParser.alignment(string(raw))
                alignments = Array(repeating: a, count: 64)
            }
            switch name.first {
            case "p": (left, right) = (0x28, 0x29)
            case "b": (left, right) = (0x5B, 0x5D)
            case "B": (left, right) = (0x7B, 0x7D)
            case "v": (left, right) = (0x7C, 0x7C)
            case "V": (left, right) = (0x2016, 0x2016)
            default: break
            }
        case "smallmatrix", "psmallmatrix", "bsmallmatrix", "Bsmallmatrix", "vsmallmatrix", "Vsmallmatrix":
            kind = .smallMatrix
            switch name.first {
            case "p": (left, right) = (0x28, 0x29)
            case "b": (left, right) = (0x5B, 0x5D)
            case "B": (left, right) = (0x7B, 0x7D)
            case "v": (left, right) = (0x7C, 0x7C)
            case "V": (left, right) = (0x2016, 0x2016)
            default: break
            }
        case "array", "darray", "subarray":
            kind = name == "subarray" ? .subarray : .array
            _ = readOptionalRaw()
            let spec = try readRawString()
            (alignments, verticalRules) = MathParser.columnSpec(spec)
        case "cases", "dcases", "cases*", "dcases*":
            kind = name.hasPrefix("d") ? .displayCases : .cases
            left = 0x7B
        case "rcases", "drcases", "rcases*":
            kind = name.hasPrefix("d") ? .displayCases : .cases
            right = 0x7D
        case "aligned", "align", "align*", "alignat", "alignat*", "alignedat", "split", "flalign", "flalign*",
             "eqnarray", "eqnarray*", "IEEEeqnarray", "IEEEeqnarray*":
            kind = .aligned
            isAligned = true
            if name.hasPrefix("aligned") || name == "split" { _ = readOptionalRaw() }
            if name.hasPrefix("alignat") || name == "alignedat" || name.hasPrefix("IEEE") { _ = try readRawArgument() }
            if name.hasPrefix("eqnarray") {
                kind = .array
                isAligned = false
                alignments = [.right, .center, .left]
            }
        case "gathered", "gather", "gather*", "multline", "multline*", "equation", "equation*", "displaymath",
             "math", "center":
            kind = .gathered
            if name == "gathered" { _ = readOptionalRaw() }
        default:
            throw fail("unknown environment \(name)")
        }

        let rows = try parseRows(style, terminator: .environment(rawName))
        var array = MathArray(kind: kind, rows: isAligned ? MathParser.prefixAlignedCells(rows.rows) : rows.rows)
        array.alignments = alignments
        array.verticalRules = verticalRules
        array.horizontalRules = rows.horizontalRules
        array.extraRowSpace = rows.extraSpace

        if name.hasPrefix("equation") || name == "displaymath" || name == "math" || name == "center",
           array.rows.count == 1, array.rows[0].count == 1 {
            return MathAtom(.ord, .list(array.rows[0][0]))
        }
        let atom = MathAtom(.ord, .array(array))
        if left != nil || right != nil {
            return MathAtom(.inner, .delimited(MathDelimited(left: left, right: right, body: [.atom(atom)])))
        }
        return atom
    }

    private static func alignment(_ c: String) -> MathColumnAlignment {
        switch c.trimmingCharacters(in: .whitespaces) {
        case "l": return .left
        case "r": return .right
        default: return .center
        }
    }

    /// Parses an array column spec such as `{l|cc|r}` or `{*{3}{c}}`.
    static func columnSpec(_ spec: String) -> ([MathColumnAlignment], [Int: Int]) {
        var alignments: [MathColumnAlignment] = []
        var rules: [Int: Int] = [:]
        var chars = Array(spec)
        var i = 0
        func skipGroup() {
            guard i < chars.count, chars[i] == "{" else { return }
            var level = 0
            while i < chars.count {
                if chars[i] == "{" { level += 1 }
                if chars[i] == "}" {
                    level -= 1
                    if level == 0 {
                        i += 1
                        return
                    }
                }
                i += 1
            }
        }
        func group() -> String {
            guard i < chars.count, chars[i] == "{" else { return "" }
            let start = i + 1
            skipGroup()
            return String(chars[start..<max(start, i - 1)])
        }
        var guardCount = 0
        while i < chars.count, guardCount < 1000 {
            guardCount += 1
            let c = chars[i]
            i += 1
            switch c {
            case "l": alignments.append(.left)
            case "c": alignments.append(.center)
            case "r": alignments.append(.right)
            case "p", "m", "b", "X":
                alignments.append(.left)
                skipGroup()
            case "|", ":": rules[alignments.count, default: 0] += 1
            case "@", "!", ">", "<": skipGroup()
            case "*":
                let count = Int(group().trimmingCharacters(in: .whitespaces)) ?? 1
                let body = group()
                let expanded = String(repeating: body, count: max(0, min(count, 50)))
                chars.replaceSubrange(i..<i, with: Array(expanded))
            default: break
            }
        }
        return (alignments, rules)
    }

    private func parseSubstack(_ style: MathFontStyle) throws -> MathArray {
        skipSpaces()
        guard peek() == "{" else { throw fail("\\substack needs a group") }
        advance()
        let rows = try parseRows(style, terminator: .closeBrace)
        var array = MathArray(kind: .subarray, rows: rows.rows)
        array.alignments = [.center]
        return array
    }

    /// Parses `cell & cell \\ …` until the terminator.
    private func parseRows(_ style: MathFontStyle, terminator: RowTerminator) throws -> Rows {
        var result = Rows()
        var current: [MathList] = []
        let savedRules = pendingRowRules
        let savedSpace = pendingRowSpace
        defer {
            pendingRowRules = savedRules
            pendingRowSpace = savedSpace
        }
        pendingRowRules = 0

        while true {
            let (cell, stop) = try parseExpression(style, allowAlignment: true)
            if pendingRowRules > 0 {
                result.horizontalRules[result.rows.count, default: 0] += pendingRowRules
                pendingRowRules = 0
            }
            current.append(cell)
            switch stop {
            case .cell:
                continue
            case .row:
                result.rows.append(current)
                current = []
                if let extra = pendingRowSpace { result.extraSpace[result.rows.count - 1] = extra }
                pendingRowSpace = nil
                continue
            case .endEnvironment:
                guard case .environment(let name) = terminator else { throw fail("unexpected \\end") }
                let endName = try readRawString()
                guard endName.replacingOccurrences(of: " ", with: "") == name.replacingOccurrences(of: " ", with: "") else {
                    throw fail("\\begin{\(name)} ended by \\end{\(endName)}")
                }
            case .closeBrace:
                guard terminator == .closeBrace else { throw fail("unbalanced braces") }
            case .end:
                guard terminator == .endOfInput else { throw fail("unterminated environment") }
            case .right, .middle:
                throw fail("\\right or \\middle without \\left")
            }
            result.rows.append(current)
            break
        }
        // A trailing `\\` leaves an empty last row; drop it.
        if result.rows.count > 1, let last = result.rows.last, last.count == 1, last[0].isEmpty {
            result.rows.removeLast()
        }
        return result
    }

    // MARK: - Text mode

    private func parseTextArgument(_ face: MathTextFace) throws -> [MathTextSegment] {
        skipSpaces()
        guard let c = peek() else { throw fail("missing text argument") }
        if c == "{" {
            advance()
            return try parseTextBody(face)
        }
        if c == "}" { throw fail("missing text argument") }
        if c == "\\" {
            let name = try readCommandName()
            return [.run(MathParser.textSymbol(name) ?? "\\" + name, face)]
        }
        advance()
        var run = ""
        run.unicodeScalars.append(c)
        return [.run(run, face)]
    }

    private static func combine(_ face: MathTextFace, with other: MathTextFace) -> MathTextFace {
        switch (face, other) {
        case (.bold, .italic), (.italic, .bold), (.boldItalic, .italic), (.boldItalic, .bold): return .boldItalic
        case (.italic, .italic): return .regular  // \emph inside italic toggles back
        default: return other
        }
    }

    private static func textSymbol(_ name: String) -> String? {
        let table: [String: String] = [
            "&": "&", "%": "%", "$": "$", "#": "#", "_": "_", "{": "{", "}": "}", "textbackslash": "\\",
            "ldots": "…", "dots": "…", "textellipsis": "…", "textendash": "–", "textemdash": "—",
            "textasciitilde": "~", "textasciicircum": "^", "textbar": "|", "textless": "<", "textgreater": ">",
            "textquoteleft": "‘", "textquoteright": "’", "textquotedblleft": "“", "textquotedblright": "”",
            "S": "§", "P": "¶", "copyright": "©", "textcopyright": "©", "dag": "†", "ddag": "‡", "LaTeX": "LaTeX",
            "TeX": "TeX", "textdegree": "°", "degree": "°", "textregistered": "®", "texttrademark": "™",
            "textbullet": "•", "pounds": "£", "textsterling": "£", "euro": "€", "ss": "ß", "ae": "æ", "AE": "Æ",
            "oe": "œ", "OE": "Œ", "o": "ø", "O": "Ø", "aa": "å", "AA": "Å", "l": "ł", "L": "Ł", "i": "ı", "j": "ȷ",
            "textperiodcentered": "·", "textminus": "−", "textpm": "±", "texttimes": "×",
        ]
        return table[name]
    }

    private static let textAccents: [String: UInt32] = [
        "'": 0x301, "`": 0x300, "^": 0x302, "\"": 0x308, "~": 0x303, "=": 0x304, ".": 0x307, "u": 0x306,
        "v": 0x30C, "H": 0x30B, "c": 0x327, "k": 0x328, "r": 0x30A, "d": 0x323, "b": 0x331,
    ]

    private func parseTextBody(_ initialFace: MathTextFace) throws -> [MathTextSegment] {
        var segments: [MathTextSegment] = []
        var run = ""
        var face = initialFace
        depth += 1
        defer { depth -= 1 }
        guard depth <= MathParser.maxDepth else { throw fail("nesting too deep") }

        func flush() {
            if !run.isEmpty {
                segments.append(.run(run, face))
                run = ""
            }
        }

        while true {
            guard let c = peek() else { throw fail("unbalanced braces in text") }
            advance()
            switch c {
            case "}":
                flush()
                return segments
            case "{":
                flush()
                segments += try parseTextBody(face)
            case "$":
                flush()
                var display = false
                if peek() == "$" {
                    advance()
                    display = true
                }
                let start = pos
                while let d = peek(), d != "$" {
                    if d == "\\" { advance() }
                    advance()
                }
                guard peek() == "$" else { throw fail("unterminated $ in text") }
                let inner = Array(s[start..<pos])
                advance()
                if display, peek() == "$" { advance() }
                segments.append(.math(try subParse(inner, style: .normal)))
            case "\\":
                pos -= 1
                let name = try readCommandName()
                if let accent = MathParser.textAccents[name] {
                    let arg = try readRawArgument()
                    var composed = ""
                    composed.unicodeScalars.append(contentsOf: arg.filter { $0 != " " })
                    if let mark = Unicode.Scalar(accent) { composed.unicodeScalars.append(mark) }
                    run += composed.precomposedStringWithCanonicalMapping
                    continue
                }
                if MathParser.isLetter(name.unicodeScalars.first ?? " ") {
                    // TeX drops spaces after a control word.
                    while let d = peek(), d == " " || d == "\t" || d == "\n" { advance() }
                }
                if let sub = MathParser.textCommands[name] {
                    flush()
                    segments += try parseTextArgument(MathParser.combine(face, with: sub))
                    continue
                }
                switch name {
                case "bfseries", "bf":
                    flush()
                    face = MathParser.combine(face, with: .bold)
                case "itshape", "it", "em", "slshape":
                    flush()
                    face = MathParser.combine(face, with: .italic)
                case "rmfamily", "upshape", "mdseries", "normalfont", "rm":
                    flush()
                    face = .regular
                case "ttfamily", "tt":
                    flush()
                    face = .monospace
                case "sffamily", "sf":
                    flush()
                    face = .sansSerif
                case " ", "\n", "\t":
                    run += " "
                case ",", "thinspace":
                    flush()
                    segments.append(.space(.mu(3)))
                case ":", ">", "medspace":
                    flush()
                    segments.append(.space(.mu(4)))
                case ";", "thickspace":
                    flush()
                    segments.append(.space(.mu(5)))
                case "!":
                    flush()
                    segments.append(.space(.mu(-3)))
                case "quad", "qquad", "enspace":
                    flush()
                    segments.append(.space(.em(name == "quad" ? 1 : (name == "qquad" ? 2 : 0.5))))
                case "hspace":
                    _ = skipStar()
                    if let dim = MathParser.dimension(try readRawString()) {
                        flush()
                        segments.append(.space(dim))
                    }
                case "\\", "newline", "linebreak", "par", "noindent", "relax", "label", "hfill":
                    if name == "label" { _ = try readRawArgument() }
                    if name == "\\" { _ = readOptionalRaw() }
                    run += " "
                case "color":
                    _ = readOptionalRaw()
                    _ = try readRawArgument()
                case "textcolor":
                    _ = readOptionalRaw()
                    _ = try readRawArgument()
                    flush()
                    segments += try parseTextArgument(face)
                default:
                    if let text = MathParser.textSymbol(name) {
                        run += text
                    } else if TeXSymbolTable.symbols[name] != nil || TeXSymbolTable.largeOperators[name] != nil
                                || TeXSymbolTable.namedOperators[name] != nil || MathParser.fontCommands[name] != nil {
                        // Math commands used in text mode (common in LLM output): set them as math.
                        flush()
                        var list = MathList()
                        var st = MathFontStyle.normal
                        try handleCommand(name, into: &list, style: &st)
                        segments.append(.math(list))
                    } else {
                        run += "\\" + name
                    }
                }
            case "~":
                run += "\u{00A0}"
            case "%":
                while let d = peek(), d != "\n" { advance() }
            case "-":
                if peek() == "-" {
                    advance()
                    if peek() == "-" {
                        advance()
                        run += "—"
                    } else {
                        run += "–"
                    }
                } else {
                    run += "-"
                }
            case "`":
                if peek() == "`" {
                    advance()
                    run += "“"
                } else {
                    run += "‘"
                }
            case "'":
                if peek() == "'" {
                    advance()
                    run += "”"
                } else {
                    run += "’"
                }
            case " ", "\t", "\n", "\r":
                if !run.hasSuffix(" ") { run += " " }
                while let d = peek(), d == " " || d == "\t" || d == "\n" || d == "\r" { advance() }
            default:
                run.unicodeScalars.append(c)
            }
        }
    }
}
