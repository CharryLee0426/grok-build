import CoreGraphics
import CoreText
import Foundation

/// Ink box and advance of a glyph, in font design units.
struct MathGlyphMetrics {
    let advance: CGFloat
    let bounds: CGRect
}

/// Faces used for `\text{…}` runs.
enum MathTextFace: Hashable {
    case regular, italic, bold, boldItalic, monospace, sansSerif
}

/// The STIX Two Math font plus everything we derive from it: glyph lookup, cached
/// metrics, the parsed MATH table and sized CTFont instances. Loaded once; all
/// mutable caches are guarded by a lock so drawing handlers may run on any thread.
final class MathFont: @unchecked Sendable {
    static let shared: MathFont? = MathFont.load()

    static let mathFontPath = "/System/Library/Fonts/Supplemental/STIXTwoMath.otf"
    static let textFontPath = "/System/Library/Fonts/Supplemental/STIXTwoText.ttf"
    static let textItalicFontPath = "/System/Library/Fonts/Supplemental/STIXTwoText-Italic.ttf"

    /// The math font at size == unitsPerEm, so all metrics come back in design units.
    let designFont: CTFont
    let unitsPerEm: CGFloat
    let table: MathOpenTypeTable
    let xHeight: CGFloat
    private let textDescriptors: [MathTextFace: CTFontDescriptor]

    private let lock = NSLock()
    private var glyphCache: [UInt32: CGGlyph] = [:]
    private var metricsCache: [CGGlyph: MathGlyphMetrics] = [:]
    private var sizedFonts: [Int: CTFont] = [:]
    private var sizedTextFonts: [MathTextFaceSize: CTFont] = [:]
    private var missing: [UInt32] = []

    private struct MathTextFaceSize: Hashable {
        let face: MathTextFace
        let size: Int
    }

    private init(designFont: CTFont, textDescriptors: [MathTextFace: CTFontDescriptor]) {
        self.designFont = designFont
        self.unitsPerEm = CGFloat(CTFontGetUnitsPerEm(designFont))
        self.table = MathOpenTypeTable(font: designFont)
        self.xHeight = CTFontGetXHeight(designFont)
        self.textDescriptors = textDescriptors
    }

    private static func load() -> MathFont? {
        var descriptor = descriptors(at: mathFontPath).first
        if descriptor == nil {
            // Fall back to a by-name lookup; CoreText substitutes another font when the
            // name is unknown, so verify we really got STIX Two Math with a MATH table.
            let named = CTFontCreateWithName("STIXTwoMath-Regular" as CFString, 12, nil)
            let postScript = CTFontCopyPostScriptName(named) as String
            if postScript.hasPrefix("STIXTwoMath") {
                descriptor = CTFontCopyFontDescriptor(named)
            }
        }
        guard let mathDescriptor = descriptor else { return nil }
        let probe = CTFontCreateWithFontDescriptor(mathDescriptor, 12, nil)
        let unitsPerEm = CGFloat(CTFontGetUnitsPerEm(probe))
        guard unitsPerEm > 0 else { return nil }
        let design = CTFontCreateWithFontDescriptor(mathDescriptor, unitsPerEm, nil)
        guard CTFontCopyTable(design, MathOpenTypeTable.mathTag, []) != nil else { return nil }

        var text: [MathTextFace: CTFontDescriptor] = [:]
        let upright = descriptors(at: textFontPath)
        let italic = descriptors(at: textItalicFontPath)
        text[.regular] = pick(upright, bold: false)
        text[.bold] = pick(upright, bold: true)
        text[.italic] = pick(italic, bold: false)
        text[.boldItalic] = pick(italic, bold: true)
        text[.monospace] = CTFontDescriptorCreateWithNameAndSize("Menlo-Regular" as CFString, 12)
        text[.sansSerif] = CTFontDescriptorCreateWithNameAndSize("HelveticaNeue" as CFString, 12)
        let font = MathFont(designFont: design, textDescriptors: text)
        return font.table.hasMathTable ? font : nil
    }

    private static func descriptors(at path: String) -> [CTFontDescriptor] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        let url = URL(fileURLWithPath: path) as CFURL
        return (CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor]) ?? []
    }

    /// STIX Two Text ships as a variable font whose named instances come back as
    /// separate descriptors (Regular, Medium, SemiBold, Bold).
    private static func pick(_ list: [CTFontDescriptor], bold: Bool) -> CTFontDescriptor? {
        let named = list.map { d -> (CTFontDescriptor, String) in
            let name = CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String ?? ""
            return (d, name)
        }
        if bold {
            return named.first { $0.1.hasSuffix("_Bold") || $0.1.hasSuffix("Bold-Italic") }?.0 ?? list.last
        }
        return named.first { !$0.1.contains("_") }?.0 ?? list.first
    }

    // MARK: - Glyphs

    /// Glyph for a Unicode scalar in the math font, or nil if the font lacks it
    /// (the miss is logged for the missing-glyph debug hook).
    func glyph(for scalar: UInt32) -> CGGlyph? {
        lock.lock()
        if let cached = glyphCache[scalar] {
            lock.unlock()
            return cached == 0 ? nil : cached
        }
        lock.unlock()
        var glyph: CGGlyph = 0
        if let u = Unicode.Scalar(scalar) {
            var units = Array(String(Character(u)).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            if CTFontGetGlyphsForCharacters(designFont, &units, &glyphs, units.count) {
                glyph = glyphs[0]
            }
        }
        lock.lock()
        glyphCache[scalar] = glyph
        lock.unlock()
        return glyph == 0 ? nil : glyph
    }

    /// Whether the math font covers `scalar`, without logging a miss.
    func hasGlyph(for scalar: UInt32) -> Bool {
        glyph(for: scalar) != nil
    }

    func recordMissing(_ scalar: UInt32) {
        lock.lock()
        missing.append(scalar)
        lock.unlock()
    }

    var missingScalars: [UInt32] {
        lock.lock()
        defer { lock.unlock() }
        return missing
    }

    func resetMissing() {
        lock.lock()
        missing.removeAll()
        lock.unlock()
    }

    func metrics(_ glyph: CGGlyph) -> MathGlyphMetrics {
        lock.lock()
        if let m = metricsCache[glyph] {
            lock.unlock()
            return m
        }
        lock.unlock()
        var g = glyph
        var rect = CGRect.zero
        var advance = CGSize.zero
        CTFontGetBoundingRectsForGlyphs(designFont, .horizontal, &g, &rect, 1)
        CTFontGetAdvancesForGlyphs(designFont, .horizontal, &g, &advance, 1)
        let m = MathGlyphMetrics(advance: advance.width, bounds: rect.isNull ? .zero : rect)
        lock.lock()
        metricsCache[glyph] = m
        lock.unlock()
        return m
    }

    func italicCorrection(_ glyph: CGGlyph) -> CGFloat {
        table.italicCorrections[glyph] ?? 0
    }

    func topAccentAttachment(_ glyph: CGGlyph) -> CGFloat? {
        table.topAccentAttachments[glyph]
    }

    /// `ssty` alternate for script (level 1) or scriptscript (level 2) style.
    func scriptVariant(_ glyph: CGGlyph, level: Int) -> CGGlyph {
        guard level > 0, let alternates = table.scriptAlternates[glyph], !alternates.isEmpty else { return glyph }
        return alternates[min(level, alternates.count) - 1]
    }

    // MARK: - Sized fonts

    func ctFont(size: CGFloat) -> CTFont {
        let key = Int((size * 1000).rounded())
        lock.lock()
        defer { lock.unlock() }
        if let f = sizedFonts[key] { return f }
        let f = CTFontCreateCopyWithAttributes(designFont, size, nil, nil)
        sizedFonts[key] = f
        return f
    }

    func textFont(_ face: MathTextFace, size: CGFloat) -> CTFont {
        let key = MathTextFaceSize(face: face, size: Int((size * 1000).rounded()))
        lock.lock()
        defer { lock.unlock() }
        if let f = sizedTextFonts[key] { return f }
        let f: CTFont
        if let d = textDescriptors[face] ?? textDescriptors[.regular] {
            f = CTFontCreateWithFontDescriptor(d, size, nil)
        } else {
            f = CTFontCreateCopyWithAttributes(designFont, size, nil, nil)
        }
        sizedTextFonts[key] = f
        return f
    }
}
