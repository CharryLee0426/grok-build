import AppKit

/// A typeset formula as a resolution-independent image plus its baseline metrics.
struct RenderedMath {
    /// Point-sized (width × (ascent + descent)); draws vectors at any backing scale.
    let image: NSImage
    let width: CGFloat
    /// Distance from the baseline up to the top of the image.
    let ascent: CGFloat
    /// Distance from the baseline down to the bottom of the image (positive).
    let descent: CGFloat
    var height: CGFloat { ascent + descent }
}

/// Native LaTeX math renderer on STIX Two Math (OpenType MATH), no dependencies.
///
/// Pipeline: `MathParser` (source → `MathFormula`) → `MathTypesetter` (TeXbook
/// Appendix G with MATH-table parameters → `MathBox` tree) → `MathDisplayList`
/// (flattened glyph runs/rules) → a vector `NSImage`. Results are cached.
/// Align the image's bottom at `baseline - descent`. The image is drawn y-up; in a
/// flipped view use `draw(in:from:operation:fraction:respectFlipped: true, hints:)`
/// (NSTextAttachment and SwiftUI `Image(nsImage:)` handle this themselves).
enum MathRenderer {
    /// Immutable cache entry (nil = the source failed to parse, which is cached too).
    private final class MathCacheEntry {
        let value: RenderedMath?
        init(_ value: RenderedMath?) { self.value = value }
    }

    /// NSCache is internally synchronized; the wrapper only tells the compiler so.
    private final class MathRenderCache: @unchecked Sendable {
        let storage: NSCache<NSString, MathCacheEntry> = {
            let cache = NSCache<NSString, MathCacheEntry>()
            cache.countLimit = 4000
            return cache
        }()
    }

    private static let cacheBox = MathRenderCache()
    private static var cache: NSCache<NSString, MathCacheEntry> { cacheBox.storage }

    static var isAvailable: Bool { MathFont.shared != nil }

    /// Renders `latex` (without surrounding `$`; a single pair of `$`, `$$`, `\(…\)` or
    /// `\[…\]` is stripped if present). `display` selects display style (large
    /// operators, limits above/below, full-size fractions). Returns nil on structural
    /// errors; unknown commands are rendered literally instead.
    static func render(_ latex: String, fontSize: CGFloat, color: NSColor, display: Bool) -> RenderedMath? {
        guard let font = MathFont.shared, fontSize.isFinite, fontSize > 0 else { return nil }
        let resolved = color.usingColorSpace(.sRGB) ?? color
        let cgColor = resolved.cgColor
        let c = cgColor.components ?? []
        let rgba = c.map { String(format: "%.4f", Double($0)) }.joined(separator: ",")
        let key = "\(display ? "D" : "T")\u{1}\(fontSize)\u{1}\(rgba)\u{1}\(latex)" as NSString
        if let hit = cache.object(forKey: key) { return hit.value }
        let result = renderUncached(latex, fontSize: fontSize, color: cgColor, display: display, font: font)
        cache.setObject(MathCacheEntry(result), forKey: key)
        return result
    }

    private static func renderUncached(_ latex: String, fontSize: CGFloat, color: CGColor, display: Bool,
                                       font: MathFont) -> RenderedMath? {
        guard let list = displayList(latex, fontSize: fontSize, color: color, display: display, font: font) else {
            return nil
        }
        let bounds = list.bounds
        let ascent = max(0, bounds.maxY)
        let descent = max(0, -bounds.minY)
        let width = bounds.width
        guard width > 0, ascent + descent > 0 else { return nil }
        let image = NSImage(size: NSSize(width: width, height: ascent + descent), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.translateBy(x: -bounds.minX, y: descent)
            list.draw(in: context)
            context.restoreGState()
            return true
        }
        return RenderedMath(image: image, width: width, ascent: ascent, descent: descent)
    }

    static func displayList(_ latex: String, fontSize: CGFloat, color: CGColor, display: Bool,
                            font: MathFont) -> MathDisplayList? {
        let source = stripDelimiters(latex)
        guard !source.isEmpty else { return nil }
        guard let formula = try? MathParser.parse(source, display: display) else { return nil }
        let typesetter = MathTypesetter(font: font, size: fontSize)
        let box = typesetter.typeset(formula, display: display, color: color)
        return MathDisplayList(box: box, font: font)
    }

    /// Removes one pair of math delimiters that were passed by accident.
    static func stripDelimiters(_ latex: String) -> String {
        var t = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs = [("$$", "$$"), ("\\[", "\\]"), ("\\(", "\\)"), ("$", "$")]
        for (open, close) in pairs where t.count >= open.count + close.count && t.hasPrefix(open) && t.hasSuffix(close) {
            let inner = t.dropFirst(open.count).dropLast(close.count)
            // Don't strip `$x\$`: the closing dollar is escaped.
            if close == "$", inner.hasSuffix("\\") { continue }
            t = String(inner).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        return t
    }

    // MARK: - Debug hooks (tests)

    /// Number of characters requested from the math font that it does not contain
    /// (they would have drawn as .notdef; the renderer falls back to system text).
    static var debugMissingGlyphCount: Int { MathFont.shared?.missingScalars.count ?? 0 }

    static var debugMissingScalars: [UInt32] { MathFont.shared?.missingScalars ?? [] }

    static func debugResetMissingGlyphs() { MathFont.shared?.resetMissing() }

    static func debugClearCache() { cache.removeAllObjects() }
}
