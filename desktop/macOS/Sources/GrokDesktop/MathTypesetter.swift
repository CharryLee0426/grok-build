import AppKit
import CoreText

/// TeX math style: D, T, S, SS, each optionally cramped (TeXbook ch. 17).
struct MathStyle: Equatable {
    var level: MathStyleLevel
    var cramped: Bool

    static let display = MathStyle(level: .display, cramped: false)
    static let text = MathStyle(level: .text, cramped: false)

    var isDisplay: Bool { level == .display }
    var isScript: Bool { level >= .script }
    /// 0 for D/T, 1 for S, 2 for SS: selects the font size and the `ssty` alternate.
    var scriptLevel: Int { max(0, level.rawValue - 1) }

    private var smaller: MathStyleLevel { level <= .text ? .script : .scriptScript }
    var superscript: MathStyle { MathStyle(level: smaller, cramped: cramped) }
    var subscriptStyle: MathStyle { MathStyle(level: smaller, cramped: true) }
    var numerator: MathStyle {
        MathStyle(level: level == .display ? .text : (level == .text ? .script : .scriptScript), cramped: cramped)
    }
    var denominator: MathStyle { MathStyle(level: numerator.level, cramped: true) }
    var crampedStyle: MathStyle { MathStyle(level: level, cramped: true) }
}

struct MathLayoutEnvironment {
    var style: MathStyle
    var color: CGColor
    /// Size for `\middle` delimiters during the second pass of `\left…\right`.
    var middleDelimiterSize: CGFloat?

    func with(style: MathStyle) -> MathLayoutEnvironment {
        var copy = self
        copy.style = style
        copy.middleDelimiterSize = nil
        return copy
    }
}

/// Converts a parsed formula into a `MathBox` tree following TeXbook Appendix G,
/// with the font parameters taken from the OpenType MATH table (as MathML Core does).
final class MathTypesetter {
    let font: MathFont
    let baseSize: CGFloat
    let k: MathConstants
    private let unitsPerEm: CGFloat

    init(font: MathFont, size: CGFloat) {
        self.font = font
        self.baseSize = size
        self.k = font.table.constants
        self.unitsPerEm = font.unitsPerEm
    }

    // MARK: - Units

    func size(_ style: MathStyle) -> CGFloat {
        switch style.scriptLevel {
        case 0: return baseSize
        case 1: return baseSize * k.scriptPercentScaleDown / 100
        default: return baseSize * k.scriptScriptPercentScaleDown / 100
        }
    }

    /// Design units → points at the environment's size.
    func pt(_ designUnits: CGFloat, _ env: MathLayoutEnvironment) -> CGFloat {
        designUnits * size(env.style) / unitsPerEm
    }

    func em(_ env: MathLayoutEnvironment) -> CGFloat { size(env.style) }

    func spaceWidth(_ space: MathSpace, _ env: MathLayoutEnvironment) -> CGFloat {
        switch space {
        case .mu(let v): return v * em(env) / 18
        case .em(let v): return v * em(env)
        }
    }

    // MARK: - Inter-atom spacing

    /// TeXbook p. 170. 1 = thin (3mu), 2 = medium (4mu), 3 = thick (5mu);
    /// negative entries apply only in display and text styles.
    private static let spacingTable: [[Int]] = [
        // ord op  bin  rel open close punct inner
        [0, 1, -2, -3, 0, 0, 0, -1],  // ord
        [1, 1, 0, -3, 0, 0, 0, -1],  // op
        [-2, -2, 0, 0, -2, 0, 0, -2],  // bin
        [-3, -3, 0, 0, -3, 0, 0, -3],  // rel
        [0, 0, 0, 0, 0, 0, 0, 0],  // open
        [0, 1, -2, -3, 0, 0, 0, -1],  // close
        [-1, -1, 0, -1, -1, -1, -1, -1],  // punct
        [-1, 1, -2, -3, -1, 0, -1, -1],  // inner
    ]

    func interAtomSpace(_ left: MathAtomType, _ right: MathAtomType, _ env: MathLayoutEnvironment) -> CGFloat {
        let code = MathTypesetter.spacingTable[left.rawValue][right.rawValue]
        if code == 0 || (code < 0 && env.style.isScript) { return 0 }
        let mu: [CGFloat] = [0, 3, 4, 5]
        return mu[abs(code)] * em(env) / 18
    }

    // MARK: - Entry point

    func typeset(_ formula: MathFormula, display: Bool, color: CGColor) -> MathBox {
        let env = MathLayoutEnvironment(style: display ? .display : .text, color: color)
        let box = layoutList(formula.list, env)
        guard let tag = formula.tag else { return box }
        let tagBox = textBox(tag, env.with(style: .text))
        return MathBox.hbox([box, .kern(2 * baseSize), tagBox])
    }

    // MARK: - Lists

    /// TeX's mlist_to_hlist: resolve style/color switches, reclassify binary atoms
    /// (Rules 5 & 6), lay out each atom, then insert inter-atom glue.
    func layoutList(_ list: MathList, _ env: MathLayoutEnvironment) -> MathBox {
        struct Entry {
            var atom: MathAtom?
            var space: MathSpace?
            var env: MathLayoutEnvironment
            var type: MathAtomType
        }
        var entries: [Entry] = []
        var current = env

        func walk(_ items: MathList) {
            for item in items {
                switch item {
                case .atom(let atom):
                    entries.append(Entry(atom: atom, space: nil, env: current, type: atom.type))
                case .space(let space):
                    entries.append(Entry(atom: nil, space: space, env: current, type: .ord))
                case .style(let level):
                    current.style = MathStyle(level: level, cramped: current.style.cramped)
                case .color(let color):
                    current.color = color
                case let .colorGroup(color, inner):
                    let saved = current
                    current.color = color
                    walk(inner)
                    current = saved
                }
            }
        }
        walk(list)

        // A Bin becomes Ord at the start of a list or after Bin/Op/Rel/Open/Punct,
        // and a Bin followed by Rel/Close/Punct (or at the end) becomes Ord too.
        var previous: Int?
        for i in entries.indices where entries[i].atom != nil {
            var type = entries[i].type
            if type == .bin {
                if let p = previous {
                    if [.bin, .op, .rel, .open, .punct].contains(entries[p].type) { type = .ord }
                } else {
                    type = .ord
                }
            }
            if [.rel, .close, .punct].contains(type), let p = previous, entries[p].type == .bin {
                entries[p].type = .ord
            }
            entries[i].type = type
            previous = i
        }
        if let p = previous, entries[p].type == .bin { entries[p].type = .ord }

        // A single atom keeps its own box so character-ness and italic correction
        // survive grouping (`{x}^2`, `\mathbf{v}^2`).
        if entries.count == 1, let atom = entries[0].atom {
            return layoutAtom(atom, type: entries[0].type, env: entries[0].env)
        }

        var children: [MathPlacedBox] = []
        var x: CGFloat = 0
        var previousType: MathAtomType?
        for entry in entries {
            if let space = entry.space {
                x += spaceWidth(space, entry.env)
                continue
            }
            guard let atom = entry.atom else { continue }
            let box = layoutAtom(atom, type: entry.type, env: entry.env)
            if let p = previousType { x += interAtomSpace(p, entry.type, entry.env) }
            children.append(MathPlacedBox(box: box, x: x, y: 0))
            x += box.width
            previousType = entry.type
        }
        return MathBox.group(children, width: x)
    }

    // MARK: - Atoms

    func layoutAtom(_ atom: MathAtom, type: MathAtomType, env: MathLayoutEnvironment) -> MathBox {
        let nucleus = layoutNucleus(atom.nucleus, env)
        guard atom.sup != nil || atom.sub != nil else { return nucleus }
        var isLargeOperator = false
        if case .largeOperator = atom.nucleus { isLargeOperator = true }
        let limits = atom.limits == .always || (atom.limits == .displayOnly && env.style.isDisplay)
        if limits {
            return limitsBox(nucleus, atom.sup, atom.sub, env, isLargeOperator: isLargeOperator)
        }
        return scriptsBox(nucleus, atom.sup, atom.sub, env, isLargeOperator: isLargeOperator)
    }

    func layoutNucleus(_ nucleus: MathNucleus, _ env: MathLayoutEnvironment) -> MathBox {
        switch nucleus {
        case .empty:
            return MathBox()
        case .symbol(let scalar):
            return symbolBox(scalar, env)
        case .largeOperator(let scalar):
            return largeOperatorBox(scalar, env)
        case .operatorName(let name):
            return operatorNameBox(name, env)
        case .text(let segments):
            return textBox(segments, env)
        case .unknownCommand(let name):
            return textBox([.run(name, .regular)], env)
        case .list(let list):
            return layoutList(list, env)
        case .fraction(let fraction):
            return fractionBox(fraction, env)
        case let .radical(degree, radicand):
            return radicalBox(degree, radicand, env)
        case .delimited(let delimited):
            return delimitedBox(delimited, env)
        case .middleDelimiter(let scalar):
            return delimiterBox(scalar, height: env.middleDelimiterSize ?? 0, env)
        case let .bigDelimiter(scalar, size):
            return bigDelimiterBox(scalar, size: size, env)
        case .accent(let accent):
            return accentBox(accent, env)
        case .overline(let list):
            return overlineBox(list, env)
        case .underline(let list):
            return underlineBox(list, env)
        case let .horizontalBrace(scalar, body, over):
            return braceBox(scalar, body, over: over, env)
        case let .extensibleArrow(scalar, over, under):
            return extensibleArrowBox(scalar, over, under, env)
        case .array(let array):
            return arrayBox(array, env)
        case let .phantom(list, horizontal, vertical):
            let inner = layoutList(list, env)
            return MathBox(width: horizontal ? inner.width : 0, height: vertical ? inner.height : 0,
                           depth: vertical ? inner.depth : 0)
        case let .smash(list, top, bottom):
            let inner = layoutList(list, env)
            return MathBox(width: inner.width, height: top ? 0 : inner.height, depth: bottom ? 0 : inner.depth,
                           content: .group([MathPlacedBox(box: inner, x: 0, y: 0)]))
        case .boxed(let list):
            return framedBox(list, env)
        case let .colorBox(list, color):
            return colorBackgroundBox(list, color, env)
        case let .cancel(list, kind):
            return cancelBox(list, kind, env)
        case .negated(let list):
            return negatedBox(list, env)
        case let .colored(list, color):
            var inner = env
            inner.color = color
            return layoutList(list, inner)
        case let .styled(list, level):
            return layoutList(list, env.with(style: MathStyle(level: level, cramped: env.style.cramped)))
        case let .strut(height, depth):
            return MathBox(width: 0, height: height * em(env), depth: depth * em(env))
        }
    }

    // MARK: - Glyphs

    func glyphBox(_ glyph: CGGlyph, _ env: MathLayoutEnvironment) -> MathBox {
        let size = self.size(env.style)
        let m = font.metrics(glyph)
        let s = size / unitsPerEm
        let ink = CGRect(x: m.bounds.minX * s, y: m.bounds.minY * s, width: m.bounds.width * s, height: m.bounds.height * s)
        let box = MathBox(width: m.advance * s, height: max(0, ink.maxY), depth: max(0, -ink.minY),
                          content: .glyph(glyph, size: size, color: env.color, ink: ink))
        box.italicCorrection = font.italicCorrection(glyph) * s
        box.topAccentAttachment = font.topAccentAttachment(glyph).map { $0 * s }
        box.isCharacter = true
        box.kernGlyph = glyph
        return box
    }

    func symbolBox(_ flaggedScalar: UInt32, _ env: MathLayoutEnvironment) -> MathBox {
        let roundhand = flaggedScalar & MathAlphabet.roundhandFlag != 0
        let scalar = flaggedScalar & ~MathAlphabet.roundhandFlag
        if roundhand, let glyph = font.glyph(for: scalar) {
            let alternate = font.table.roundhandAlternates[glyph] ?? glyph
            return glyphBox(font.scriptVariant(alternate, level: env.style.scriptLevel), env)
        }
        guard let glyph = font.glyph(for: scalar) else {
            font.recordMissing(scalar)
            var text = ""
            if let u = Unicode.Scalar(scalar) { text.unicodeScalars.append(u) }
            return textRunBox(text, .regular, size(env.style), env.color)
        }
        return glyphBox(font.scriptVariant(glyph, level: env.style.scriptLevel), env)
    }

    /// Rule 13: large operators use a display-size variant in display style and are
    /// centered on the math axis.
    func largeOperatorBox(_ scalar: UInt32, _ env: MathLayoutEnvironment) -> MathBox {
        guard let base = font.glyph(for: scalar) else { return symbolBox(scalar, env) }
        var glyph = font.scriptVariant(base, level: env.style.scriptLevel)
        if env.style.isDisplay, let construction = font.table.verticalConstructions[base] {
            glyph = construction.variants.first(where: { $0.advance >= k.displayOperatorMinHeight })?.glyph
                ?? construction.variants.last?.glyph ?? base
        }
        let box = glyphBox(glyph, env)
        let shifted = box.shifted(by: pt(k.axisHeight, env) - (box.height - box.depth) / 2)
        shifted.isCharacter = false
        return shifted
    }

    func operatorNameBox(_ name: String, _ env: MathLayoutEnvironment) -> MathBox {
        var boxes: [MathBox] = []
        for scalar in name.unicodeScalars {
            if scalar == " " {
                boxes.append(.kern(3 * em(env) / 18))
            } else {
                boxes.append(symbolBox(scalar.value, env))
            }
        }
        if boxes.count == 1 { return boxes[0] }
        // Operator names sit on the baseline like characters; scripts attach as they
        // would to a character (the box drop rule would push `\log_2` far down).
        let box = MathBox.hbox(boxes)
        box.isCharacter = true
        return box
    }

    // MARK: - Text

    func textRunBox(_ string: String, _ face: MathTextFace, _ size: CGFloat, _ color: CGColor) -> MathBox {
        let ctFont = font.textFont(face, size: size)
        let attributes: [CFString: Any] = [kCTFontAttributeName: ctFont, kCTForegroundColorAttributeName: color]
        guard let attributed = CFAttributedStringCreate(nil, string as CFString, attributes as CFDictionary) else {
            return MathBox()
        }
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        var ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        if ink.isNull || ink.isInfinite { ink = .zero }
        return MathBox(width: width, height: max(0, ink.maxY), depth: max(0, -ink.minY),
                       content: .text(line, color: color, ink: ink))
    }

    func textBox(_ segments: [MathTextSegment], _ env: MathLayoutEnvironment) -> MathBox {
        let size = self.size(env.style)
        var boxes: [MathBox] = []
        for segment in segments {
            switch segment {
            case let .run(string, face):
                boxes.append(textRunBox(string, face, size, env.color))
            case .math(let list):
                // `$…$` inside \text starts a new text-style formula at the current size.
                let level = max(env.style.level, .text)
                boxes.append(layoutList(list, env.with(style: MathStyle(level: level, cramped: env.style.cramped))))
            case .space(let space):
                boxes.append(.kern(spaceWidth(space, env)))
            }
        }
        if boxes.count == 1 { return boxes[0] }
        return MathBox.hbox(boxes)
    }

    // MARK: - Scripts

    /// Cut-in kern from a MathKern table at `height` (points, relative to the glyph's baseline).
    private func mathKern(_ glyph: CGGlyph?, _ corner: KeyPath<MathKernInfo, MathKernTable?>,
                          height: CGFloat, size: CGFloat) -> CGFloat {
        guard let glyph = glyph, let info = font.table.kerns[glyph], let table = info[keyPath: corner] else { return 0 }
        let scale = size / unitsPerEm
        return table.value(atHeight: height / scale) * scale
    }

    /// Rule 18 with OpenType MATH parameters.
    func scriptsBox(_ base: MathBox, _ sup: MathList?, _ sub: MathList?, _ env: MathLayoutEnvironment,
                    isLargeOperator: Bool) -> MathBox {
        let supEnv = env.with(style: env.style.superscript)
        let subEnv = env.with(style: env.style.subscriptStyle)
        let supBox = sup.map { layoutList($0, supEnv) }
        let subBox = sub.map { layoutList($0, subEnv) }

        var u: CGFloat = 0
        var v: CGFloat = 0
        if !base.isCharacter {
            u = base.height - pt(k.superscriptBaselineDropMax, env)
            v = base.depth + pt(k.subscriptBaselineDropMin, env)
        }
        if let sb = subBox, supBox == nil {
            v = max(v, pt(k.subscriptShiftDown, env), sb.height - pt(k.subscriptTopMax, env))
        }
        if let sp = supBox {
            let shift = env.style.cramped ? k.superscriptShiftUpCramped : k.superscriptShiftUp
            u = max(u, pt(shift, env), sp.depth + pt(k.superscriptBottomMin, env))
        }
        if let sp = supBox, let sb = subBox {
            v = max(v, pt(k.subscriptShiftDown, env))
            let gap = (u - sp.depth) - (sb.height - v)
            let minGap = pt(k.subSuperscriptGapMin, env)
            if gap < minGap {
                v += minGap - gap
                let psi = pt(k.superscriptBottomMaxWithSubscript, env) - (u - sp.depth)
                if psi > 0 {
                    u += psi
                    v -= psi
                }
            }
        }

        // Italic correction: superscripts go after it; for large operators (∫) the
        // font's convention is that subscripts are pulled back by it instead.
        let italic = base.italicCorrection
        var supX = isLargeOperator ? base.width : base.width + italic
        var subX = isLargeOperator ? base.width - italic : base.width

        if !isLargeOperator, let glyph = base.kernGlyph {
            let baseSize = size(env.style)
            if let sp = supBox {
                let spSize = size(supEnv.style)
                let top = base.height
                let bottom = u - sp.depth
                let k1 = mathKern(glyph, \.topRight, height: top, size: baseSize)
                    + mathKern(sp.kernGlyph, \.bottomLeft, height: top - u, size: spSize)
                let k2 = mathKern(glyph, \.topRight, height: bottom, size: baseSize)
                    + mathKern(sp.kernGlyph, \.bottomLeft, height: bottom - u, size: spSize)
                supX += max(k1, k2)
            }
            if let sb = subBox {
                let sbSize = size(subEnv.style)
                let top = sb.height - v
                let bottom = -base.depth
                let k1 = mathKern(glyph, \.bottomRight, height: top, size: baseSize)
                    + mathKern(sb.kernGlyph, \.topLeft, height: top + v, size: sbSize)
                let k2 = mathKern(glyph, \.bottomRight, height: bottom, size: baseSize)
                    + mathKern(sb.kernGlyph, \.topLeft, height: bottom + v, size: sbSize)
                subX += max(k1, k2)
            }
        }

        var children = [MathPlacedBox(box: base, x: 0, y: 0)]
        var width = base.width
        if let sp = supBox {
            children.append(MathPlacedBox(box: sp, x: supX, y: u))
            width = max(width, supX + sp.width)
        }
        if let sb = subBox {
            children.append(MathPlacedBox(box: sb, x: subX, y: -v))
            width = max(width, subX + sb.width)
        }
        return MathBox.group(children, width: width + pt(k.spaceAfterScript, env))
    }

    /// Rule 13a: limits above and below, shifted by half the italic correction.
    func limitsBox(_ base: MathBox, _ sup: MathList?, _ sub: MathList?, _ env: MathLayoutEnvironment,
                   isLargeOperator: Bool) -> MathBox {
        let supBox = sup.map { layoutList($0, env.with(style: env.style.superscript)) }
        let subBox = sub.map { layoutList($0, env.with(style: env.style.subscriptStyle)) }
        let italic = isLargeOperator ? base.italicCorrection : 0
        let width = max(base.width, supBox?.width ?? 0, subBox?.width ?? 0)
        var children = [MathPlacedBox(box: base, x: (width - base.width) / 2, y: 0)]
        if let sp = supBox {
            let shift = max(pt(k.upperLimitBaselineRiseMin, env), pt(k.upperLimitGapMin, env) + sp.depth)
            children.append(MathPlacedBox(box: sp, x: (width - sp.width + italic) / 2, y: base.height + shift))
        }
        if let sb = subBox {
            let shift = max(pt(k.lowerLimitBaselineDropMin, env), pt(k.lowerLimitGapMin, env) + sb.height)
            children.append(MathPlacedBox(box: sb, x: (width - sb.width - italic) / 2, y: -(base.depth + shift)))
        }
        let minX = min(0, children.map(\.x).min() ?? 0)
        let maxX = max(width, children.map { $0.x + $0.box.width }.max() ?? 0)
        if minX < 0 {
            children = children.map { MathPlacedBox(box: $0.box, x: $0.x - minX, y: $0.y) }
        }
        return MathBox.group(children, width: maxX - minX)
    }

    // MARK: - Fractions

    func fractionBox(_ f: MathFraction, _ environment: MathLayoutEnvironment) -> MathBox {
        var env = environment
        switch f.style {
        case .display: env.style = MathStyle(level: .display, cramped: env.style.cramped)
        case .text: env.style = MathStyle(level: .text, cramped: env.style.cramped)
        case .auto: break
        }
        let display = env.style.isDisplay
        var numEnv = env.with(style: env.style.numerator)
        var denEnv = env.with(style: env.style.denominator)
        if f.continued {
            numEnv.style = .display
            denEnv.style = MathStyle(level: .display, cramped: true)
        }
        let num = layoutList(f.numerator, numEnv)
        let den = layoutList(f.denominator, denEnv)
        let axis = pt(k.axisHeight, env)
        let thickness = f.hasRule ? (f.ruleThickness.map { $0 * em(env) } ?? pt(k.fractionRuleThickness, env)) : 0

        var u: CGFloat
        var v: CGFloat
        if thickness > 0 {
            u = pt(display ? k.fractionNumeratorDisplayStyleShiftUp : k.fractionNumeratorShiftUp, env)
            v = pt(display ? k.fractionDenominatorDisplayStyleShiftDown : k.fractionDenominatorShiftDown, env)
            let gapNum = pt(display ? k.fractionNumDisplayStyleGapMin : k.fractionNumeratorGapMin, env)
            let gapDen = pt(display ? k.fractionDenomDisplayStyleGapMin : k.fractionDenominatorGapMin, env)
            u = max(u, axis + thickness / 2 + gapNum + num.depth)
            v = max(v, gapDen + den.height - axis + thickness / 2)
        } else {
            u = pt(display ? k.stackTopDisplayStyleShiftUp : k.stackTopShiftUp, env)
            v = pt(display ? k.stackBottomDisplayStyleShiftDown : k.stackBottomShiftDown, env)
            let gapMin = pt(display ? k.stackDisplayStyleGapMin : k.stackGapMin, env)
            let gap = (u - num.depth) - (den.height - v)
            if gap < gapMin {
                u += (gapMin - gap) / 2
                v += (gapMin - gap) / 2
            }
        }

        let width = max(num.width, den.width)
        var children = [
            MathPlacedBox(box: num, x: (width - num.width) / 2, y: u),
            MathPlacedBox(box: den, x: (width - den.width) / 2, y: -v),
        ]
        if thickness > 0 {
            let rule = MathBox(width: width, height: thickness, depth: 0, content: .rule(env.color))
            children.append(MathPlacedBox(box: rule, x: 0, y: axis - thickness / 2))
        }
        let stack = MathBox.group(children, width: width)

        if f.leftDelimiter != nil || f.rightDelimiter != nil {
            // TeX uses delim1 (2.39em) in display style and delim2 (1.01em) otherwise.
            let target = max(display ? 2.39 * em(env) : 1.01 * em(env), delimiterTarget(for: stack, env))
            return MathBox.hbox([delimiterBox(f.leftDelimiter, height: target, env), stack,
                                 delimiterBox(f.rightDelimiter, height: target, env)])
        }
        let nullSpace = MathBox.kern(0.12 * em(env))
        return MathBox.hbox([nullSpace, stack, nullSpace])
    }

    // MARK: - Radicals

    func radicalBox(_ degree: MathList?, _ radicand: MathList, _ env: MathLayoutEnvironment) -> MathBox {
        let inner = layoutList(radicand, env.with(style: env.style.crampedStyle))
        let thickness = pt(k.radicalRuleThickness, env)
        var gap = pt(env.style.isDisplay ? k.radicalDisplayStyleVerticalGap : k.radicalVerticalGap, env)
        let target = inner.height + inner.depth + gap + thickness
        guard let radicalGlyph = font.glyph(for: 0x221A) else { return inner }
        let sign = verticalStretch(radicalGlyph, target: target, env)
        let signTotal = sign.height + sign.depth
        if signTotal > target { gap += (signTotal - target) / 2 }
        let ruleBottom = inner.height + gap
        // Raise the sign so its top edge meets the top of the overbar.
        let signShift = ruleBottom + thickness - sign.height

        var children: [MathPlacedBox] = []
        var x: CGFloat = 0
        if let degree = degree {
            let degreeBox = layoutList(degree, env.with(style: MathStyle(level: .scriptScript, cramped: true)))
            let before = pt(k.radicalKernBeforeDegree, env)
            let after = pt(k.radicalKernAfterDegree, env)
            let raise = k.radicalDegreeBottomRaisePercent / 100 * signTotal
            let y = (signShift - sign.depth) + raise + degreeBox.depth
            children.append(MathPlacedBox(box: degreeBox, x: before, y: y))
            x = max(0, before + degreeBox.width + after)
        }
        children.append(MathPlacedBox(box: sign, x: x, y: signShift))
        x += sign.width
        let rule = MathBox(width: inner.width, height: thickness, depth: 0, content: .rule(env.color))
        children.append(MathPlacedBox(box: rule, x: x, y: ruleBottom))
        children.append(MathPlacedBox(box: inner, x: x, y: 0))
        x += inner.width
        let box = MathBox.group(children, width: x)
        box.height = max(box.height, ruleBottom + thickness + pt(k.radicalExtraAscender, env))
        return box
    }

    // MARK: - Stretchy glyphs

    /// Smallest vertical variant at least `target` tall (points), else an assembly.
    func verticalStretch(_ glyph: CGGlyph, target: CGFloat, _ env: MathLayoutEnvironment) -> MathBox {
        let scale = size(env.style) / unitsPerEm
        let targetUnits = target / scale
        guard let construction = font.table.verticalConstructions[glyph] else { return glyphBox(glyph, env) }
        if let variant = construction.variants.first(where: { $0.advance >= targetUnits }) {
            return glyphBox(variant.glyph, env)
        }
        if let assembly = construction.assembly {
            return assemblyBox(assembly, target: targetUnits, vertical: true, env)
        }
        return glyphBox(construction.variants.last?.glyph ?? glyph, env)
    }

    func horizontalStretch(_ glyph: CGGlyph, target: CGFloat, _ env: MathLayoutEnvironment) -> MathBox {
        let scale = size(env.style) / unitsPerEm
        let targetUnits = target / scale
        guard let construction = font.table.horizontalConstructions[glyph] else { return glyphBox(glyph, env) }
        if let variant = construction.variants.first(where: { $0.advance >= targetUnits }) {
            return glyphBox(variant.glyph, env)
        }
        if let assembly = construction.assembly {
            return assemblyBox(assembly, target: targetUnits, vertical: false, env)
        }
        return glyphBox(construction.variants.last?.glyph ?? glyph, env)
    }

    /// Builds a glyph assembly of at least `target` design units: repeat extenders
    /// until the maximal length (minimum connector overlap everywhere) reaches the
    /// target, then spread the overlap evenly so the result is as close as possible.
    func assemblyBox(_ assembly: MathGlyphAssembly, target: CGFloat, vertical: Bool,
                     _ env: MathLayoutEnvironment) -> MathBox {
        let scale = size(env.style) / unitsPerEm
        let minOverlap = font.table.minConnectorOverlap
        let hasExtender = assembly.parts.contains { $0.isExtender }
        func sequence(_ repeats: Int) -> [MathGlyphPart] {
            assembly.parts.flatMap { $0.isExtender ? Array(repeating: $0, count: repeats) : [$0] }
        }
        var repeats = 0
        var parts = sequence(repeats)
        while hasExtender, repeats < 400 {
            let length = parts.reduce(0) { $0 + $1.fullAdvance } - minOverlap * CGFloat(max(parts.count - 1, 0))
            if length >= target { break }
            repeats += 1
            parts = sequence(repeats)
        }
        // Overlap at each joint: start at the minimum, then shrink toward the target by
        // spreading the excess over the joints, each capped by its own connector lengths.
        let joints = max(parts.count - 1, 0)
        var overlaps = [CGFloat](repeating: minOverlap, count: joints)
        if joints > 0 {
            let capacity = (0..<joints).map { max(0, min(parts[$0].endConnector, parts[$0 + 1].startConnector) - minOverlap) }
            var excess = parts.reduce(0) { $0 + $1.fullAdvance } - minOverlap * CGFloat(joints) - target
            var open = Set(0..<joints)
            while excess > 0.01, !open.isEmpty {
                let share = excess / CGFloat(open.count)
                for j in open.sorted() {
                    let take = min(share, capacity[j] - (overlaps[j] - minOverlap))
                    overlaps[j] += take
                    excess -= take
                    if overlaps[j] - minOverlap >= capacity[j] - 0.001 { open.remove(j) }
                }
            }
        }

        var children: [MathPlacedBox] = []
        var offset: CGFloat = 0
        var crossSize: CGFloat = 0
        for (index, part) in parts.enumerated() {
            let box = glyphBox(part.glyph, env)
            if vertical {
                // Stack parts by their ink bottoms (the part's advance is its ink height).
                let bottom = font.metrics(part.glyph).bounds.minY
                children.append(MathPlacedBox(box: box, x: 0, y: (offset - bottom) * scale))
                crossSize = max(crossSize, box.width)
            } else {
                children.append(MathPlacedBox(box: box, x: offset * scale, y: 0))
            }
            offset += part.fullAdvance - (index < joints ? overlaps[index] : 0)
        }
        let length = offset * scale
        if vertical {
            let box = MathBox(width: crossSize, height: length, depth: 0, content: .group(children))
            box.italicCorrection = assembly.italicCorrection * scale
            return box
        }
        return MathBox.group(children, width: length)
    }

    /// Vertical extent of the ink of a box (falls back to its height/depth).
    func inkExtent(_ box: MathBox) -> (minY: CGFloat, maxY: CGFloat) {
        switch box.content {
        case let .glyph(_, _, _, ink):
            return (ink.minY, ink.maxY)
        case .group(let children):
            var lo = CGFloat.infinity
            var hi = -CGFloat.infinity
            for child in children {
                let e = inkExtent(child.box)
                lo = min(lo, e.minY + child.y)
                hi = max(hi, e.maxY + child.y)
            }
            return lo <= hi ? (lo, hi) : (-box.depth, box.height)
        default:
            return (-box.depth, box.height)
        }
    }

    // MARK: - Delimiters

    /// Rule 19: the delimiter must cover the material around the axis, with
    /// \delimiterfactor = 901 and \delimitershortfall = 5pt.
    func delimiterTarget(for box: MathBox, _ env: MathLayoutEnvironment) -> CGFloat {
        let axis = pt(k.axisHeight, env)
        let extent = max(box.height - axis, box.depth + axis)
        return max(2 * extent * 0.901, 2 * extent - 0.5 * em(env))
    }

    func delimiterBox(_ scalar: UInt32?, height target: CGFloat, _ env: MathLayoutEnvironment) -> MathBox {
        guard let scalar = scalar else { return .kern(0.12 * em(env)) }  // \nulldelimiterspace
        guard let glyph = font.glyph(for: scalar) else { return symbolBox(scalar, env) }
        let box = verticalStretch(glyph, target: target, env)
        return box.shifted(by: pt(k.axisHeight, env) - (box.height - box.depth) / 2)
    }

    func bigDelimiterBox(_ scalar: UInt32?, size index: Int, _ env: MathLayoutEnvironment) -> MathBox {
        let heights: [CGFloat] = [0, 1.2, 1.8, 2.4, 3.0]
        let target = heights[max(0, min(index, 4))] * em(env)
        guard let scalar = scalar else { return .kern(0.12 * em(env)) }
        guard let glyph = font.glyph(for: scalar) else { return symbolBox(scalar, env) }
        let scale = em(env) / unitsPerEm
        var box: MathBox
        if let construction = font.table.verticalConstructions[glyph], let largest = construction.variants.last {
            if target / scale > largest.advance * 1.05, let assembly = construction.assembly {
                box = assemblyBox(assembly, target: target / scale, vertical: true, env)
            } else {
                // \big sizes are fixed heights: take the variant closest to them.
                let best = construction.variants.min { abs($0.advance * scale - target) < abs($1.advance * scale - target) }
                box = glyphBox(best?.glyph ?? glyph, env)
            }
        } else {
            box = glyphBox(glyph, env)
        }
        return box.shifted(by: pt(k.axisHeight, env) - (box.height - box.depth) / 2)
    }

    private func containsMiddle(_ list: MathList) -> Bool {
        list.contains { item in
            switch item {
            case .atom(let atom):
                if case .middleDelimiter = atom.nucleus { return true }
                return false
            case .colorGroup(_, let inner):
                return containsMiddle(inner)
            default:
                return false
            }
        }
    }

    func delimitedBox(_ d: MathDelimited, _ env: MathLayoutEnvironment) -> MathBox {
        var inner = layoutList(d.body, env)
        let target = delimiterTarget(for: inner, env)
        if containsMiddle(d.body) {
            var second = env
            second.middleDelimiterSize = target
            inner = layoutList(d.body, second)
        }
        return MathBox.hbox([delimiterBox(d.left, height: target, env), inner,
                             delimiterBox(d.right, height: target, env)])
    }

    // MARK: - Accents, bars, braces

    func accentBox(_ accent: MathAccent, _ env: MathLayoutEnvironment) -> MathBox {
        let base = layoutList(accent.body, env.with(style: env.style.crampedStyle))
        guard let glyph = font.glyph(for: accent.scalar) else {
            font.recordMissing(accent.scalar)
            return base
        }
        let mark = accent.stretchy ? horizontalStretch(glyph, target: base.width, env) : glyphBox(glyph, env)
        let baseAttach = accent.under ? base.width / 2 : (base.topAccentAttachment ?? base.width / 2)
        let markAttach: CGFloat
        if let t = mark.topAccentAttachment {
            markAttach = t
        } else if mark.width > 0 {
            markAttach = mark.width / 2
        } else if case let .glyph(_, _, _, ink) = mark.content {
            markAttach = ink.midX
        } else {
            markAttach = 0
        }
        let dy: CGFloat
        if accent.under {
            dy = -base.depth
        } else {
            // Accents are designed for bases of height accentBaseHeight; raise them for taller bases.
            dy = max(0, base.height - pt(k.accentBaseHeight, env))
        }
        let children = [MathPlacedBox(box: base, x: 0, y: 0), MathPlacedBox(box: mark, x: baseAttach - markAttach, y: dy)]
        let box = MathBox.group(children, width: base.width)
        box.italicCorrection = base.italicCorrection
        box.topAccentAttachment = base.topAccentAttachment
        // Rule 12: scripts on an accented character sit as if the accent weren't there.
        box.isCharacter = base.isCharacter
        return box
    }

    func overlineBox(_ list: MathList, _ env: MathLayoutEnvironment) -> MathBox {
        let base = layoutList(list, env.with(style: env.style.crampedStyle))
        let gap = pt(k.overbarVerticalGap, env)
        let thickness = pt(k.overbarRuleThickness, env)
        let rule = MathBox(width: base.width, height: thickness, depth: 0, content: .rule(env.color))
        let box = MathBox.group([MathPlacedBox(box: base, x: 0, y: 0),
                                 MathPlacedBox(box: rule, x: 0, y: base.height + gap)], width: base.width)
        box.height += pt(k.overbarExtraAscender, env)
        return box
    }

    func underlineBox(_ list: MathList, _ env: MathLayoutEnvironment) -> MathBox {
        let base = layoutList(list, env)
        let gap = pt(k.underbarVerticalGap, env)
        let thickness = pt(k.underbarRuleThickness, env)
        let rule = MathBox(width: base.width, height: thickness, depth: 0, content: .rule(env.color))
        let box = MathBox.group([MathPlacedBox(box: base, x: 0, y: 0),
                                 MathPlacedBox(box: rule, x: 0, y: -(base.depth + gap + thickness))], width: base.width)
        box.depth += pt(k.underbarExtraDescender, env)
        return box
    }

    func braceBox(_ scalar: UInt32, _ body: MathList, over: Bool, _ env: MathLayoutEnvironment) -> MathBox {
        let base = layoutList(body, env)
        guard let glyph = font.glyph(for: scalar) else { return base }
        let brace = horizontalStretch(glyph, target: base.width, env)
        let ink = inkExtent(brace)
        let gap = max(pt(k.stretchStackGapBelowMin, env), 0.1 * em(env))
        let dy = over ? base.height + gap - ink.minY : -(base.depth + gap) - ink.maxY
        let width = max(base.width, brace.width)
        return MathBox.group([MathPlacedBox(box: base, x: (width - base.width) / 2, y: 0),
                              MathPlacedBox(box: brace, x: (width - brace.width) / 2, y: dy)], width: width)
    }

    func extensibleArrowBox(_ scalar: UInt32, _ over: MathList?, _ under: MathList?,
                            _ env: MathLayoutEnvironment) -> MathBox {
        let overBox = over.map { layoutList($0, env.with(style: env.style.superscript)) }
        let underBox = under.map { layoutList($0, env.with(style: env.style.subscriptStyle)) }
        let content = max(overBox?.width ?? 0, underBox?.width ?? 0)
        let target = max(content + 0.8 * em(env), 1.4 * em(env))
        var arrow: MathBox
        if let glyph = font.glyph(for: scalar), font.table.horizontalConstructions[glyph] != nil {
            arrow = horizontalStretch(glyph, target: target, env)
        } else if scalar == 0x3D {
            arrow = equalsBarBox(width: target, env)
        } else if let glyph = font.glyph(for: 0x2192) {
            arrow = horizontalStretch(glyph, target: target, env)
        } else {
            arrow = MathBox()
        }
        let ink = inkExtent(arrow)
        let gap = max(pt(k.stretchStackGapAboveMin, env), 0.1 * em(env))
        let width = max(arrow.width, content)
        var children = [MathPlacedBox(box: arrow, x: (width - arrow.width) / 2, y: 0)]
        if let o = overBox {
            children.append(MathPlacedBox(box: o, x: (width - o.width) / 2, y: ink.maxY + gap + o.depth))
        }
        if let u = underBox {
            children.append(MathPlacedBox(box: u, x: (width - u.width) / 2, y: ink.minY - gap - u.height))
        }
        return MathBox.group(children, width: width)
    }

    /// A stretched "=" (for \xlongequal) drawn as two rules matching the font's equals sign.
    private func equalsBarBox(width: CGFloat, _ env: MathLayoutEnvironment) -> MathBox {
        let axis = pt(k.axisHeight, env)
        let t = pt(k.fractionRuleThickness, env)
        let halfGap = 0.11 * em(env)
        let top = MathBox(width: width, height: t, depth: 0, content: .rule(env.color))
        let bottom = MathBox(width: width, height: t, depth: 0, content: .rule(env.color))
        return MathBox.group([MathPlacedBox(box: top, x: 0, y: axis + halfGap - t / 2),
                              MathPlacedBox(box: bottom, x: 0, y: axis - halfGap - t / 2)], width: width)
    }

    // MARK: - Boxes, cancel, negation

    private func ruleBox(_ width: CGFloat, _ height: CGFloat, _ color: CGColor) -> MathBox {
        MathBox(width: width, height: height, depth: 0, content: .rule(color))
    }

    func framedBox(_ list: MathList, _ env: MathLayoutEnvironment) -> MathBox {
        let innerStyle = env.style.level <= .text ? MathStyle.display : env.style
        let inner = layoutList(list, env.with(style: innerStyle))
        let pad = 0.3 * em(env)  // \fboxsep = 3pt
        let t = max(0.04 * em(env), 0.5)  // \fboxrule = 0.4pt
        let width = inner.width + 2 * (pad + t)
        let height = inner.height + pad + t
        let depth = inner.depth + pad + t
        let children = [
            MathPlacedBox(box: inner, x: pad + t, y: 0),
            MathPlacedBox(box: ruleBox(width, t, env.color), x: 0, y: height - t),
            MathPlacedBox(box: ruleBox(width, t, env.color), x: 0, y: -depth),
            MathPlacedBox(box: ruleBox(t, height + depth, env.color), x: 0, y: -depth),
            MathPlacedBox(box: ruleBox(t, height + depth, env.color), x: width - t, y: -depth),
        ]
        let box = MathBox.group(children, width: width)
        box.height = height
        box.depth = depth
        return box
    }

    func colorBackgroundBox(_ list: MathList, _ color: CGColor, _ env: MathLayoutEnvironment) -> MathBox {
        let inner = layoutList(list, env)
        let pad = 0.3 * em(env)
        let width = inner.width + 2 * pad
        let background = MathBox(width: width, height: inner.height + pad, depth: inner.depth + pad, content: .rule(color))
        return MathBox.group([MathPlacedBox(box: background, x: 0, y: 0), MathPlacedBox(box: inner, x: pad, y: 0)],
                             width: width)
    }

    func cancelBox(_ list: MathList, _ kind: MathCancelKind, _ env: MathLayoutEnvironment) -> MathBox {
        let inner = layoutList(list, env)
        let pad = 0.1 * em(env)
        let path = CGMutablePath()
        let lo = CGPoint(x: -pad * 0.5, y: -inner.depth - pad * 0.5)
        let hi = CGPoint(x: inner.width + pad * 0.5, y: inner.height + pad * 0.5)
        if kind != .backward {
            path.move(to: lo)
            path.addLine(to: hi)
        }
        if kind != .forward {
            path.move(to: CGPoint(x: lo.x, y: hi.y))
            path.addLine(to: CGPoint(x: hi.x, y: lo.y))
        }
        let stroke = MathBox(width: 0, content: .stroke(path, lineWidth: max(pt(k.fractionRuleThickness, env) * 0.8, 0.5),
                                                        color: env.color))
        return MathBox.group([MathPlacedBox(box: inner, x: 0, y: 0), MathPlacedBox(box: stroke, x: 0, y: 0)],
                             width: inner.width)
    }

    func negatedBox(_ list: MathList, _ env: MathLayoutEnvironment) -> MathBox {
        let inner = layoutList(list, env)
        guard let glyph = font.glyph(for: 0x0338) else { return inner }
        let slash = glyphBox(glyph, env)
        var midX: CGFloat = 0
        if case let .glyph(_, _, _, ink) = slash.content { midX = ink.midX }
        return MathBox.group([MathPlacedBox(box: inner, x: 0, y: 0),
                              MathPlacedBox(box: slash, x: inner.width / 2 - midX, y: 0)], width: inner.width)
    }
}
