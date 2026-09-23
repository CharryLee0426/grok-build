import CoreGraphics
import Foundation

/// TeX atom classes; they drive inter-atom spacing (TeXbook ch. 18, Appendix G).
enum MathAtomType: Int, Equatable {
    case ord = 0, op, bin, rel, open, close, punct, inner
}

/// When scripts of an atom go above/below instead of to the side.
enum MathLimits: Equatable {
    /// Above/below in display style only (`\sum`, `\lim`).
    case displayOnly
    /// Always above/below (`\limits`, `\overbrace`, `\overset`).
    case always
    /// Always to the side (`\nolimits`, `\int`, `\sin`).
    case never
}

enum MathStyleLevel: Int, Comparable {
    case display = 0, text, script, scriptScript

    static func < (a: MathStyleLevel, b: MathStyleLevel) -> Bool { a.rawValue < b.rawValue }
}

/// Explicit horizontal space.
enum MathSpace: Equatable {
    /// Math units (1/18 em of the current style's size).
    case mu(CGFloat)
    /// Ems of the current style's size.
    case em(CGFloat)
}

/// A piece of `\text{…}` content.
enum MathTextSegment {
    case run(String, MathTextFace)
    case math(MathList)
    case space(MathSpace)
}

enum MathFractionStyle: Equatable {
    case auto, display, text
}

struct MathFraction {
    var numerator: MathList
    var denominator: MathList
    /// Rule thickness in ems; nil = the font's default rule.
    var ruleThickness: CGFloat?
    var hasRule: Bool
    var style: MathFractionStyle
    /// Delimiters wrapped around the fraction (`\binom`), nil = none.
    var leftDelimiter: UInt32?
    var rightDelimiter: UInt32?
    /// `\cfrac` keeps numerator and denominator in display style.
    var continued: Bool = false
}

struct MathDelimited {
    /// nil = null delimiter (`.`).
    var left: UInt32?
    var right: UInt32?
    /// The body; `\middle` delimiters appear inside as `.middleDelimiter` atoms.
    var body: MathList
}

struct MathAccent {
    var scalar: UInt32
    var body: MathList
    var stretchy: Bool
    /// Accent goes below (`\underrightarrow`, …).
    var under: Bool = false
}

enum MathArrayKind: Equatable {
    case matrix  // matrix, pmatrix, …: centered columns, no outer padding
    case smallMatrix
    case array  // explicit column spec
    case cases  // left-aligned, text style
    case displayCases  // dcases: display style
    case aligned  // alternating r/l, display style
    case gathered  // centered, display style
    case subarray  // \substack / subarray: script-level, tight rows
}

enum MathColumnAlignment: Equatable {
    case left, center, right
}

struct MathArray {
    var kind: MathArrayKind
    var rows: [[MathList]]
    /// Per-column alignment (array/subarray); other kinds derive it from `kind`.
    var alignments: [MathColumnAlignment] = []
    /// Number of vertical rules before column i (index == column count → after last).
    var verticalRules: [Int: Int] = [:]
    /// Number of `\hline`s above row i (index == rows.count → below the last row).
    var horizontalRules: [Int: Int] = [:]
    /// Extra space (ems) requested with `\\[dim]` after row i.
    var extraRowSpace: [Int: CGFloat] = [:]
}

enum MathCancelKind: Equatable {
    case forward, backward, cross
}

indirect enum MathNucleus {
    case empty
    /// A single math character (already mapped to its styled code point).
    case symbol(UInt32)
    /// A large operator glyph (∑, ∫, …) that uses display variants and sits on the axis.
    case largeOperator(UInt32)
    /// An upright operator name drawn with the math font (`\sin`, `\operatorname{…}`).
    case operatorName(String)
    /// `\text{…}` and friends.
    case text([MathTextSegment])
    /// An unknown control sequence, rendered literally in upright text.
    case unknownCommand(String)
    case list(MathList)
    case fraction(MathFraction)
    case radical(degree: MathList?, radicand: MathList)
    case delimited(MathDelimited)
    /// `\middle` inside a `\left…\right` body.
    case middleDelimiter(UInt32?)
    /// `\big(` … `\Bigg)`; size 1…4.
    case bigDelimiter(UInt32?, size: Int)
    case accent(MathAccent)
    case overline(MathList)
    case underline(MathList)
    /// `\overbrace` / `\underbrace` (label arrives as a limit script).
    case horizontalBrace(scalar: UInt32, body: MathList, over: Bool)
    /// `\xrightarrow[below]{above}`.
    case extensibleArrow(scalar: UInt32, over: MathList?, under: MathList?)
    case array(MathArray)
    case phantom(MathList, horizontal: Bool, vertical: Bool)
    case smash(MathList, top: Bool, bottom: Bool)
    case boxed(MathList)
    case colorBox(MathList, CGColor)
    case cancel(MathList, MathCancelKind)
    /// `\not` applied to something without a precomposed negation.
    case negated(MathList)
    case colored(MathList, CGColor)
    /// Content set in a fixed style (`\dfrac`-like wrappers, `{\displaystyle …}`).
    case styled(MathList, MathStyleLevel)
    /// A vertical strut of the given height/depth in ems (`\mathstrut`, `\\[..]` helpers).
    case strut(height: CGFloat, depth: CGFloat)
}

struct MathAtom {
    var type: MathAtomType
    var nucleus: MathNucleus
    var sup: MathList?
    var sub: MathList?
    var limits: MathLimits = .never

    init(_ type: MathAtomType, _ nucleus: MathNucleus, limits: MathLimits = .never) {
        self.type = type
        self.nucleus = nucleus
        self.limits = limits
    }
}

enum MathListItem {
    case atom(MathAtom)
    case space(MathSpace)
    /// `\displaystyle` & co: applies to the rest of the current list.
    case style(MathStyleLevel)
    /// `\color{…}` switch: applies to the rest of the current list.
    case color(CGColor)
    /// Content whose atoms take part in the surrounding spacing (`\textcolor{c}{…}`).
    case colorGroup(CGColor, MathList)

    var atom: MathAtom? {
        if case .atom(let a) = self { return a }
        return nil
    }
}

typealias MathList = [MathListItem]

/// Parser output for one formula.
struct MathFormula {
    var list: MathList
    /// `\tag{…}` content (already including parentheses unless `\tag*`).
    var tag: [MathTextSegment]?
}
