import CoreGraphics
import CoreText
import Foundation

/// Big-endian reader over a raw OpenType table. Out-of-range reads return 0 so a
/// truncated or malformed table degrades to "missing data" instead of trapping.
struct MathByteReader {
    let bytes: [UInt8]

    init(_ data: CFData) {
        let length = CFDataGetLength(data)
        var buffer = [UInt8](repeating: 0, count: length)
        if length > 0 {
            CFDataGetBytes(data, CFRange(location: 0, length: length), &buffer)
        }
        bytes = buffer
    }

    func u16(_ offset: Int) -> Int {
        guard offset >= 0, offset + 1 < bytes.count else { return 0 }
        return Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
    }

    func i16(_ offset: Int) -> Int {
        let v = u16(offset)
        return v >= 0x8000 ? v - 0x10000 : v
    }

    func u32(_ offset: Int) -> Int {
        u16(offset) << 16 | u16(offset + 2)
    }

    func tag(_ offset: Int) -> UInt32 {
        UInt32(u16(offset)) << 16 | UInt32(u16(offset + 2))
    }

    /// Coverage table → glyph IDs in coverage-index order.
    func coverage(_ offset: Int) -> [CGGlyph] {
        guard offset > 0 else { return [] }
        var glyphs: [CGGlyph] = []
        switch u16(offset) {
        case 1:
            let count = u16(offset + 2)
            glyphs.reserveCapacity(count)
            for i in 0..<count { glyphs.append(CGGlyph(u16(offset + 4 + 2 * i))) }
        case 2:
            let ranges = u16(offset + 2)
            for i in 0..<ranges {
                let r = offset + 4 + 6 * i
                let start = u16(r), end = u16(r + 2), startIndex = u16(r + 4)
                guard end >= start else { continue }
                if glyphs.count < startIndex + (end - start + 1) {
                    glyphs.append(contentsOf: [CGGlyph](repeating: 0, count: startIndex + (end - start + 1) - glyphs.count))
                }
                for g in start...end { glyphs[startIndex + g - start] = CGGlyph(g) }
            }
        default:
            break
        }
        return glyphs
    }
}

/// One size variant of a stretchy glyph (`advance` is its height for vertical
/// constructions, width for horizontal ones), in design units.
struct MathGlyphVariant {
    let glyph: CGGlyph
    let advance: CGFloat
}

/// One piece of a glyph assembly. Parts are listed bottom-to-top (vertical) or
/// left-to-right (horizontal); extenders may be repeated any number of times.
struct MathGlyphPart {
    let glyph: CGGlyph
    let startConnector: CGFloat
    let endConnector: CGFloat
    let fullAdvance: CGFloat
    let isExtender: Bool
}

struct MathGlyphAssembly {
    let italicCorrection: CGFloat
    let parts: [MathGlyphPart]
}

struct MathGlyphConstruction {
    let variants: [MathGlyphVariant]
    let assembly: MathGlyphAssembly?
}

/// A MathKern table: a staircase of kern values separated by correction heights.
struct MathKernTable {
    let heights: [CGFloat]
    let values: [CGFloat]

    func value(atHeight height: CGFloat) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        for (i, h) in heights.enumerated() where height < h {
            return values[i]
        }
        return values[min(heights.count, values.count - 1)]
    }
}

/// Cut-in kerns for the four corners of a glyph (used for script placement).
struct MathKernInfo {
    var topRight: MathKernTable?
    var topLeft: MathKernTable?
    var bottomRight: MathKernTable?
    var bottomLeft: MathKernTable?
}

/// All MathConstants we use, in design units (percentages kept as raw numbers).
struct MathConstants {
    var scriptPercentScaleDown: CGFloat = 70
    var scriptScriptPercentScaleDown: CGFloat = 50
    var delimitedSubFormulaMinHeight: CGFloat = 1300
    var displayOperatorMinHeight: CGFloat = 1300
    var mathLeading: CGFloat = 150
    var axisHeight: CGFloat = 250
    var accentBaseHeight: CGFloat = 450
    var flattenedAccentBaseHeight: CGFloat = 660
    var subscriptShiftDown: CGFloat = 200
    var subscriptTopMax: CGFloat = 400
    var subscriptBaselineDropMin: CGFloat = 160
    var superscriptShiftUp: CGFloat = 360
    var superscriptShiftUpCramped: CGFloat = 250
    var superscriptBottomMin: CGFloat = 120
    var superscriptBaselineDropMax: CGFloat = 230
    var subSuperscriptGapMin: CGFloat = 150
    var superscriptBottomMaxWithSubscript: CGFloat = 380
    var spaceAfterScript: CGFloat = 40
    var upperLimitGapMin: CGFloat = 150
    var upperLimitBaselineRiseMin: CGFloat = 300
    var lowerLimitGapMin: CGFloat = 150
    var lowerLimitBaselineDropMin: CGFloat = 600
    var stackTopShiftUp: CGFloat = 470
    var stackTopDisplayStyleShiftUp: CGFloat = 780
    var stackBottomShiftDown: CGFloat = 385
    var stackBottomDisplayStyleShiftDown: CGFloat = 690
    var stackGapMin: CGFloat = 200
    var stackDisplayStyleGapMin: CGFloat = 400
    var stretchStackTopShiftUp: CGFloat = 800
    var stretchStackBottomShiftDown: CGFloat = 590
    var stretchStackGapAboveMin: CGFloat = 150
    var stretchStackGapBelowMin: CGFloat = 150
    var fractionNumeratorShiftUp: CGFloat = 390
    var fractionNumeratorDisplayStyleShiftUp: CGFloat = 680
    var fractionDenominatorShiftDown: CGFloat = 340
    var fractionDenominatorDisplayStyleShiftDown: CGFloat = 690
    var fractionNumeratorGapMin: CGFloat = 40
    var fractionNumDisplayStyleGapMin: CGFloat = 100
    var fractionRuleThickness: CGFloat = 60
    var fractionDenominatorGapMin: CGFloat = 40
    var fractionDenomDisplayStyleGapMin: CGFloat = 100
    var skewedFractionHorizontalGap: CGFloat = 350
    var skewedFractionVerticalGap: CGFloat = 100
    var overbarVerticalGap: CGFloat = 130
    var overbarRuleThickness: CGFloat = 60
    var overbarExtraAscender: CGFloat = 60
    var underbarVerticalGap: CGFloat = 130
    var underbarRuleThickness: CGFloat = 60
    var underbarExtraDescender: CGFloat = 60
    var radicalVerticalGap: CGFloat = 70
    var radicalDisplayStyleVerticalGap: CGFloat = 170
    var radicalRuleThickness: CGFloat = 60
    var radicalExtraAscender: CGFloat = 60
    var radicalKernBeforeDegree: CGFloat = 280
    var radicalKernAfterDegree: CGFloat = -550
    var radicalDegreeBottomRaisePercent: CGFloat = 60
}

/// Parsed OpenType MATH table plus the `ssty` (script-style) alternates from GSUB.
/// Everything is in font design units.
struct MathOpenTypeTable {
    var constants = MathConstants()
    var italicCorrections: [CGGlyph: CGFloat] = [:]
    var topAccentAttachments: [CGGlyph: CGFloat] = [:]
    var extendedShapes: Set<CGGlyph> = []
    var kerns: [CGGlyph: MathKernInfo] = [:]
    var minConnectorOverlap: CGFloat = 20
    var verticalConstructions: [CGGlyph: MathGlyphConstruction] = [:]
    var horizontalConstructions: [CGGlyph: MathGlyphConstruction] = [:]
    /// glyph → [script alternate, scriptscript alternate]
    var scriptAlternates: [CGGlyph: [CGGlyph]] = [:]
    /// Script letters → roundhand forms (`ss01`), used for `\mathscr`.
    var roundhandAlternates: [CGGlyph: CGGlyph] = [:]
    var hasMathTable = false

    static let mathTag: CTFontTableTag = 0x4D41_5448  // 'MATH'
    static let gsubTag: CTFontTableTag = 0x4753_5542  // 'GSUB'

    init() {}

    init(font: CTFont) {
        if let data = CTFontCopyTable(font, MathOpenTypeTable.mathTag, []) {
            parseMath(MathByteReader(data))
        }
        if let data = CTFontCopyTable(font, MathOpenTypeTable.gsubTag, []) {
            let reader = MathByteReader(data)
            scriptAlternates = MathOpenTypeTable.substitutions(reader, feature: 0x7373_7479)  // 'ssty'
            // STIX Two Math's ss01 turns the (chancery) script alphabet into roundhand: \mathscr.
            roundhandAlternates = MathOpenTypeTable.substitutions(reader, feature: 0x7373_3031).compactMapValues(\.first)
        }
    }

    // MARK: - MATH

    private mutating func parseMath(_ r: MathByteReader) {
        guard r.bytes.count >= 10, r.u16(0) == 1 else { return }
        hasMathTable = true
        let constantsOffset = r.u16(4)
        let glyphInfoOffset = r.u16(6)
        let variantsOffset = r.u16(8)
        if constantsOffset > 0 { parseConstants(r, constantsOffset) }
        if glyphInfoOffset > 0 { parseGlyphInfo(r, glyphInfoOffset) }
        if variantsOffset > 0 { parseVariants(r, variantsOffset) }
    }

    private mutating func parseConstants(_ r: MathByteReader, _ base: Int) {
        var c = MathConstants()
        c.scriptPercentScaleDown = CGFloat(r.i16(base))
        c.scriptScriptPercentScaleDown = CGFloat(r.i16(base + 2))
        c.delimitedSubFormulaMinHeight = CGFloat(r.u16(base + 4))
        c.displayOperatorMinHeight = CGFloat(r.u16(base + 6))
        // 51 MathValueRecords (int16 value + Offset16 device table) follow, in spec order.
        var index = 0
        func next() -> CGFloat {
            defer { index += 1 }
            return CGFloat(r.i16(base + 8 + 4 * index))
        }
        c.mathLeading = next()
        c.axisHeight = next()
        c.accentBaseHeight = next()
        c.flattenedAccentBaseHeight = next()
        c.subscriptShiftDown = next()
        c.subscriptTopMax = next()
        c.subscriptBaselineDropMin = next()
        c.superscriptShiftUp = next()
        c.superscriptShiftUpCramped = next()
        c.superscriptBottomMin = next()
        c.superscriptBaselineDropMax = next()
        c.subSuperscriptGapMin = next()
        c.superscriptBottomMaxWithSubscript = next()
        c.spaceAfterScript = next()
        c.upperLimitGapMin = next()
        c.upperLimitBaselineRiseMin = next()
        c.lowerLimitGapMin = next()
        c.lowerLimitBaselineDropMin = next()
        c.stackTopShiftUp = next()
        c.stackTopDisplayStyleShiftUp = next()
        c.stackBottomShiftDown = next()
        c.stackBottomDisplayStyleShiftDown = next()
        c.stackGapMin = next()
        c.stackDisplayStyleGapMin = next()
        c.stretchStackTopShiftUp = next()
        c.stretchStackBottomShiftDown = next()
        c.stretchStackGapAboveMin = next()
        c.stretchStackGapBelowMin = next()
        c.fractionNumeratorShiftUp = next()
        c.fractionNumeratorDisplayStyleShiftUp = next()
        c.fractionDenominatorShiftDown = next()
        c.fractionDenominatorDisplayStyleShiftDown = next()
        c.fractionNumeratorGapMin = next()
        c.fractionNumDisplayStyleGapMin = next()
        c.fractionRuleThickness = next()
        c.fractionDenominatorGapMin = next()
        c.fractionDenomDisplayStyleGapMin = next()
        c.skewedFractionHorizontalGap = next()
        c.skewedFractionVerticalGap = next()
        c.overbarVerticalGap = next()
        c.overbarRuleThickness = next()
        c.overbarExtraAscender = next()
        c.underbarVerticalGap = next()
        c.underbarRuleThickness = next()
        c.underbarExtraDescender = next()
        c.radicalVerticalGap = next()
        c.radicalDisplayStyleVerticalGap = next()
        c.radicalRuleThickness = next()
        c.radicalExtraAscender = next()
        c.radicalKernBeforeDegree = next()
        c.radicalKernAfterDegree = next()
        c.radicalDegreeBottomRaisePercent = CGFloat(r.i16(base + 8 + 4 * index))
        if c.scriptPercentScaleDown <= 0 { c.scriptPercentScaleDown = 70 }
        if c.scriptScriptPercentScaleDown <= 0 { c.scriptScriptPercentScaleDown = 50 }
        constants = c
    }

    private mutating func parseGlyphInfo(_ r: MathByteReader, _ base: Int) {
        let italicsOffset = r.u16(base)
        let accentOffset = r.u16(base + 2)
        let extendedOffset = r.u16(base + 4)
        let kernOffset = r.u16(base + 6)

        if italicsOffset > 0 {
            let t = base + italicsOffset
            let glyphs = r.coverage(t + r.u16(t))
            let count = min(r.u16(t + 2), glyphs.count)
            for i in 0..<count {
                italicCorrections[glyphs[i]] = CGFloat(r.i16(t + 4 + 4 * i))
            }
        }
        if accentOffset > 0 {
            let t = base + accentOffset
            let glyphs = r.coverage(t + r.u16(t))
            let count = min(r.u16(t + 2), glyphs.count)
            for i in 0..<count {
                topAccentAttachments[glyphs[i]] = CGFloat(r.i16(t + 4 + 4 * i))
            }
        }
        if extendedOffset > 0 {
            extendedShapes = Set(r.coverage(base + extendedOffset))
        }
        if kernOffset > 0 {
            let t = base + kernOffset
            let glyphs = r.coverage(t + r.u16(t))
            let count = min(r.u16(t + 2), glyphs.count)
            for i in 0..<count {
                let rec = t + 4 + 8 * i
                var info = MathKernInfo()
                info.topRight = kernTable(r, t, r.u16(rec))
                info.topLeft = kernTable(r, t, r.u16(rec + 2))
                info.bottomRight = kernTable(r, t, r.u16(rec + 4))
                info.bottomLeft = kernTable(r, t, r.u16(rec + 6))
                kerns[glyphs[i]] = info
            }
        }
    }

    private func kernTable(_ r: MathByteReader, _ base: Int, _ offset: Int) -> MathKernTable? {
        guard offset > 0 else { return nil }
        let t = base + offset
        let n = r.u16(t)
        var heights: [CGFloat] = []
        var values: [CGFloat] = []
        for i in 0..<n { heights.append(CGFloat(r.i16(t + 2 + 4 * i))) }
        for i in 0...n { values.append(CGFloat(r.i16(t + 2 + 4 * n + 4 * i))) }
        return MathKernTable(heights: heights, values: values)
    }

    private mutating func parseVariants(_ r: MathByteReader, _ base: Int) {
        minConnectorOverlap = CGFloat(r.u16(base))
        let vertCoverage = r.coverage(base + r.u16(base + 2))
        let horizCoverage = r.coverage(base + r.u16(base + 4))
        let vertCount = r.u16(base + 6)
        let horizCount = r.u16(base + 8)
        for i in 0..<min(vertCount, vertCoverage.count) {
            let off = r.u16(base + 10 + 2 * i)
            if off > 0 { verticalConstructions[vertCoverage[i]] = construction(r, base + off) }
        }
        for i in 0..<min(horizCount, horizCoverage.count) {
            let off = r.u16(base + 10 + 2 * vertCount + 2 * i)
            if off > 0 { horizontalConstructions[horizCoverage[i]] = construction(r, base + off) }
        }
    }

    private func construction(_ r: MathByteReader, _ t: Int) -> MathGlyphConstruction {
        let assemblyOffset = r.u16(t)
        let count = r.u16(t + 2)
        var variants: [MathGlyphVariant] = []
        for i in 0..<count {
            variants.append(MathGlyphVariant(glyph: CGGlyph(r.u16(t + 4 + 4 * i)),
                                             advance: CGFloat(r.u16(t + 6 + 4 * i))))
        }
        var assembly: MathGlyphAssembly?
        if assemblyOffset > 0 {
            let a = t + assemblyOffset
            let italic = CGFloat(r.i16(a))
            let partCount = r.u16(a + 4)
            var parts: [MathGlyphPart] = []
            for i in 0..<partCount {
                let p = a + 6 + 10 * i
                parts.append(MathGlyphPart(glyph: CGGlyph(r.u16(p)),
                                           startConnector: CGFloat(r.u16(p + 2)),
                                           endConnector: CGFloat(r.u16(p + 4)),
                                           fullAdvance: CGFloat(r.u16(p + 6)),
                                           isExtender: r.u16(p + 8) & 1 != 0))
            }
            if !parts.isEmpty { assembly = MathGlyphAssembly(italicCorrection: italic, parts: parts) }
        }
        return MathGlyphConstruction(variants: variants, assembly: assembly)
    }

    // MARK: - GSUB

    /// Collects the single (type 1) and alternate (type 3) substitutions of one GSUB
    /// feature. OpenType math fonts use `ssty` for optically-adjusted script-size
    /// glyphs; CoreText does not apply it for us when drawing glyph IDs directly.
    private static func substitutions(_ r: MathByteReader, feature tag: UInt32) -> [CGGlyph: [CGGlyph]] {
        var result: [CGGlyph: [CGGlyph]] = [:]
        guard r.bytes.count >= 10 else { return result }
        let featureList = r.u16(6)
        let lookupList = r.u16(8)
        guard featureList > 0, lookupList > 0 else { return result }
        var lookupIndices: [Int] = []
        for i in 0..<r.u16(featureList) {
            let rec = featureList + 2 + 6 * i
            guard r.tag(rec) == tag else { continue }
            let feature = featureList + r.u16(rec + 4)
            for j in 0..<r.u16(feature + 2) { lookupIndices.append(r.u16(feature + 4 + 2 * j)) }
        }
        for index in Set(lookupIndices).sorted() {
            guard index < r.u16(lookupList) else { continue }
            let lookup = lookupList + r.u16(lookupList + 2 + 2 * index)
            let type = r.u16(lookup)
            for s in 0..<r.u16(lookup + 4) {
                var sub = lookup + r.u16(lookup + 6 + 2 * s)
                var subType = type
                if subType == 7 {  // extension lookup
                    subType = r.u16(sub + 2)
                    sub += r.u32(sub + 4)
                }
                let format = r.u16(sub)
                let glyphs = r.coverage(sub + r.u16(sub + 2))
                switch (subType, format) {
                case (1, 1):
                    let delta = r.i16(sub + 4)
                    for g in glyphs where result[g] == nil {
                        result[g] = [CGGlyph((Int(g) + delta) & 0xFFFF)]
                    }
                case (1, 2):
                    for (k, g) in glyphs.enumerated() where k < r.u16(sub + 4) && result[g] == nil {
                        result[g] = [CGGlyph(r.u16(sub + 6 + 2 * k))]
                    }
                case (3, 1):
                    for (k, g) in glyphs.enumerated() where k < r.u16(sub + 4) && result[g] == nil {
                        let set = sub + r.u16(sub + 6 + 2 * k)
                        var alternates: [CGGlyph] = []
                        for a in 0..<r.u16(set) { alternates.append(CGGlyph(r.u16(set + 2 + 2 * a))) }
                        if !alternates.isEmpty { result[g] = alternates }
                    }
                default:
                    break
                }
            }
        }
        return result
    }
}
