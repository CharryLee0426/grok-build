import Foundation

enum SyntaxSingleQuote { case none, string, limited, char, rust, ml, transpose, nixIndented }
enum SyntaxBacktick { case none, template, raw, identifier, command }
enum SyntaxInterpolation { case none, dollarBrace, dollarBraceIdent, dollarBraceVariable, hashBrace, swift, brace, php, perl, julia }
enum SyntaxStringPrefixes { case none, python, rust, cpp, dart, scala, sql, nim, julia }
enum SyntaxAtRule { case none, attribute, decorator, objc, variable, zig, csharp }
enum SyntaxDollarRule { case none, variable, perl, swift, csharp, cmake, awk }
enum SyntaxRegexRule { case none, js, ruby }
enum SyntaxHeredocRule { case none, ruby, perl, php, hcl }
enum SyntaxQuestionRule { case none, elixirChar, erlangMacro }

struct SyntaxDelimiterPair {
    let open: [UInt16]
    let close: [UInt16]

    init(_ open: String, _ close: String) {
        self.open = Array(open.utf16)
        self.close = Array(close.utf16)
    }
}

/// Table-driven description of a C-like/scripting language for `SyntaxCodeLexer`.
struct SyntaxLangSpec {
    var words: SyntaxWordTable
    var lineComments: [[UInt16]] = []
    /// Comment markers recognised only as the first non-blank text on a line (Vim `"`, Fortran `*`).
    var lineStartComments: [[UInt16]] = []
    var blockComments: [SyntaxDelimiterPair] = []
    /// Block comments whose open/close markers must start a line (Ruby `=begin`, Perl POD, MATLAB `%{`).
    var lineStartBlocks: [SyntaxDelimiterPair] = []
    /// Line-start markers after which the rest of the file is data (`__END__`).
    var endMarkers: [[UInt16]] = []
    var nestedComments = false

    var doubleQuote = true
    var tripleDouble = false
    var tripleSingle = false
    var singleQuote: SyntaxSingleQuote = .string
    var backtick: SyntaxBacktick = .none
    var escapes = true
    var multilineStrings = false
    var doubledQuotes = false
    var interpolation: SyntaxInterpolation = .none
    var singleQuoteInterpolates = false
    var prefixes: SyntaxStringPrefixes = .none

    var at: SyntaxAtRule = .none
    var dollar: SyntaxDollarRule = .none
    var preprocessor = false
    var rustAttributes = false
    var phpAttributes = false
    var swiftPound = false
    var hashPrivate = false
    var haskellPragma = false
    var haskellDashes = false
    var nimPragma = false
    var csharpAttributes = false
    var fsharpAttributes = false
    var luaLongBrackets = false
    var zigLineStrings = false
    var regex: SyntaxRegexRule = .none
    var jsx = false
    var heredoc: SyntaxHeredocRule = .none
    var percentLiterals = false
    var perlQuoteOperators = false
    var sigils = false
    var symbols = false
    var labelSymbols = false
    var question: SyntaxQuestionRule = .none
    var erlangAttributes = false
    var fortranDots = false
    var nixPaths = false
    var vimScopes = false
    /// R-style infix operators (`%>%`, `%in%`).
    var percentOperators = false

    var identDollar = false
    var identPrime = false
    var identDash = false
    var identDot = false
    var identQuestion = false
    var identBang = false
    var macroBang = false

    var numbers = true
    var callHeuristic = true
    var capitalizedCallIsType = false
    /// Kind for Capitalized identifiers (nil: leave plain).
    var capitalized: SyntaxTokenKind? = .type
    /// PascalCase members after `.` are properties/methods, not types (C#, Go).
    var capitalizedMembersPlain = false
    var allCapsConstants = true
    var objcSelectors = false
    var assignmentKeys = false
    var signatureFunctions = false
    /// Elm/PureScript-style `name : Type` signatures (single colon).
    var signatureSingleColon = false
    var arrowMemberAccess = false
    var cppDigitSeparators = false
    var fortranExponent = false
    var erlangBase = false

    init(caseInsensitive: Bool = false) {
        words = SyntaxWordTable(caseInsensitive: caseInsensitive)
    }

    mutating func keywords(_ w: String) { words.add(w, .keyword) }
    mutating func valueKeywords(_ w: String) { words.add(w, .keyword, role: SyntaxWordTable.value) }
    mutating func functionDefiners(_ w: String) { words.add(w, .keyword, role: SyntaxWordTable.defineFunction) }
    mutating func typeDefiners(_ w: String) { words.add(w, .keyword, role: SyntaxWordTable.defineType) }
    mutating func softKeywords(_ w: String) { words.add(w, .keyword, role: SyntaxWordTable.soft) }
    mutating func types(_ w: String) { words.add(w, .type) }
    mutating func constants(_ w: String) { words.add(w, .constant) }
    mutating func builtins(_ w: String) { words.add(w, .function) }
    mutating func variables(_ w: String) { words.add(w, .variable) }
    mutating func allowedAfterDot(_ w: String) { words.addRole(w, SyntaxWordTable.afterDot) }
    mutating func contextual(_ w: String) { words.addRole(w, SyntaxWordTable.contextual) }

    mutating func lineComment(_ markers: String...) { lineComments += markers.map { Array($0.utf16) } }
    mutating func blockComment(_ open: String, _ close: String) { blockComments.append(SyntaxDelimiterPair(open, close)) }

    mutating func cComments(nested: Bool = false) {
        lineComment("//")
        blockComment("/*", "*/")
        nestedComments = nested
    }

    /// ASCII characters that may start a construct handled by `SyntaxCodeLexer.special`.
    func specialMask() -> (UInt64, UInt64) {
        var mask: (UInt64, UInt64) = (0, 0)
        func set(_ c: UInt16) {
            if c < 64 { mask.0 |= 1 << UInt64(c) } else if c < 128 { mask.1 |= 1 << UInt64(c - 64) }
        }
        for marker in lineComments + lineStartComments + endMarkers { if let f = marker.first { set(f) } }
        for pair in blockComments + lineStartBlocks { if let f = pair.open.first { set(f) } }
        set(35) // `#!` shebang and hash rules
        set(46) // `.5`, Fortran `.and.`, Nix paths
        if doubleQuote { set(34) }
        if singleQuote != .none { set(39) }
        if backtick != .none { set(96) }
        if at != .none { set(64) }
        if dollar != .none { set(36) }
        if symbols { set(58) }
        if question != .none { set(63) }
        if regex != .none { set(47) }
        if jsx || heredoc != .none || nixPaths { set(60) }
        if percentLiterals || dollar == .perl || percentOperators { set(37) }
        if sigils { set(126) }
        if luaLongBrackets || csharpAttributes || fsharpAttributes { set(91) }
        if haskellPragma || nimPragma { set(123) }
        if zigLineStrings { set(92) }
        if erlangAttributes || luaLongBrackets { set(45) }
        if vimScopes { set(38); set(60) }
        return mask
    }
}
