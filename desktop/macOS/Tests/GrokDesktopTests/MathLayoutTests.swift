import AppKit
import XCTest
@testable import GrokDesktop

final class MathLayoutTests: XCTestCase {
    private let size: CGFloat = 20

    private func r(_ latex: String, display: Bool = true, size: CGFloat? = nil, color: NSColor = .black) -> RenderedMath {
        guard let result = MathRenderer.render(latex, fontSize: size ?? self.size, color: color, display: display) else {
            XCTFail("render returned nil for \(latex)")
            return RenderedMath(image: NSImage(), width: 0, ascent: 0, descent: 0)
        }
        return result
    }

    private func list(_ latex: String, display: Bool = true) throws -> MathDisplayList {
        let font = try XCTUnwrap(MathFont.shared)
        return try XCTUnwrap(MathRenderer.displayList(latex, fontSize: size, color: NSColor.black.cgColor,
                                                      display: display, font: font))
    }

    private var axis: CGFloat {
        MathFont.shared!.table.constants.axisHeight * size / MathFont.shared!.unitsPerEm
    }

    func testFontIsAvailableWithMathTable() throws {
        XCTAssertTrue(MathRenderer.isAvailable)
        let font = try XCTUnwrap(MathFont.shared)
        XCTAssertTrue(font.table.hasMathTable)
        XCTAssertEqual(font.table.constants.scriptPercentScaleDown, 70)
        XCTAssertGreaterThan(font.table.verticalConstructions.count, 50)
        XCTAssertGreaterThan(font.table.horizontalConstructions.count, 20)
        XCTAssertGreaterThan(font.table.italicCorrections.count, 100)
        XCTAssertGreaterThan(font.table.topAccentAttachments.count, 100)
        XCTAssertGreaterThan(font.table.scriptAlternates.count, 100)
    }

    func testScriptsChangeAscentAndDescent() {
        let x = r("x")
        XCTAssertGreaterThan(r("x^2").ascent, x.ascent + 2)
        XCTAssertGreaterThan(r("x_i").descent, x.descent + 2)
        XCTAssertGreaterThan(r("x^2").width, x.width)
        // Scripts are smaller than the base.
        XCTAssertLessThan(r("x^{x}").width - x.width, x.width)
    }

    func testDisplayFractionIsTallerThanTextFraction() {
        let display = r("\\frac{a}{b}", display: true)
        let inline = r("\\frac{a}{b}", display: false)
        XCTAssertGreaterThan(display.height, inline.height * 1.1)
        XCTAssertGreaterThan(r("\\dfrac{a}{b}", display: false).height, inline.height * 1.1)
        XCTAssertEqual(r("\\tfrac{a}{b}", display: true).height, inline.height, accuracy: 0.01)
    }

    func testFractionBarSitsOnTheAxis() throws {
        let dl = try list("\\frac{a}{b}")
        let rules = dl.ops.compactMap { op -> CGRect? in
            if case let .rect(rect, _) = op { return rect }
            return nil
        }
        let bar = try XCTUnwrap(rules.first)
        XCTAssertEqual(bar.midY, axis, accuracy: 0.01)
    }

    func testDelimiterGrowsWithContent() {
        let small = r("\\left( x \\right)")
        let medium = r("\\left( \\frac{a}{b} \\right)")
        let tall = r("\\left( \\frac{\\frac{a}{b}}{\\frac{c}{d}} \\right)")
        XCTAssertEqual(small.height, r("(x)").height, accuracy: 0.5)
        XCTAssertGreaterThan(medium.height, small.height + 5)
        XCTAssertGreaterThan(tall.height, medium.height + 5)
        // Very tall content needs a glyph assembly.
        let huge = r("\\left( \\begin{matrix} 1 \\\\ 2 \\\\ 3 \\\\ 4 \\\\ 5 \\\\ 6 \\\\ 7 \\\\ 8 \\end{matrix} \\right)")
        XCTAssertGreaterThan(huge.height, 8 * 1.2 * size * 0.9)
    }

    func testBigDelimiterSizesIncrease() {
        let heights = ["(", "\\big(", "\\Big(", "\\bigg(", "\\Bigg("].map { r($0).height }
        for i in 1..<heights.count { XCTAssertGreaterThan(heights[i], heights[i - 1]) }
    }

    func testSumLimitsDisplayVsInline() {
        let display = r("\\sum_{i=1}^n", display: true)
        let inline = r("\\sum_{i=1}^n", display: false)
        XCTAssertLessThan(display.width, inline.width)
        XCTAssertGreaterThan(display.height, inline.height)
        // Integrals keep their scripts at the side even in display style.
        XCTAssertGreaterThan(r("\\int_0^1", display: true).width, r("\\int", display: true).width + 5)
        // \limits forces limits in text style.
        XCTAssertLessThan(r("\\sum\\limits_{i=1}^n", display: false).width, inline.width)
    }

    func testLargeOperatorIsBiggerInDisplay() {
        XCTAssertGreaterThan(r("\\sum", display: true).height, r("\\sum", display: false).height)
        XCTAssertGreaterThan(r("\\int", display: true).height, r("\\int", display: false).height * 1.5)
    }

    func testRadicalGrowsAndRuleJoinsSign() throws {
        XCTAssertGreaterThan(r("\\sqrt{\\frac{a}{b}}").height, r("\\sqrt{x}").height + 5)
        let dl = try list("\\sqrt{x}")
        let font = try XCTUnwrap(MathFont.shared)
        // Ops are emitted in child order: sign glyph, overbar rule, radicand.
        guard case let .glyphs(ctFont, glyphs, positions, _)? = dl.ops.first else { return XCTFail() }
        let m = font.metrics(glyphs[0])
        let signTop = positions[0].y + m.bounds.maxY * CTFontGetSize(ctFont) / font.unitsPerEm
        let bar = try XCTUnwrap(dl.ops.compactMap { op -> CGRect? in
            if case let .rect(rect, _) = op { return rect }
            return nil
        }.first)
        XCTAssertEqual(bar.maxY, signTop, accuracy: 0.05)
        // The bar starts where the sign's advance ends (the sign's ink overlaps it).
        XCTAssertEqual(bar.minX, positions[0].x + m.advance * CTFontGetSize(ctFont) / font.unitsPerEm, accuracy: 0.01)
    }

    func testMatrixHeightGrowsWithRows() {
        let one = r("\\begin{pmatrix} a \\end{pmatrix}")
        let three = r("\\begin{pmatrix} a \\\\ b \\\\ c \\end{pmatrix}")
        XCTAssertGreaterThan(three.height, one.height * 2)
        // Arrays are centered on the math axis.
        XCTAssertEqual((three.ascent - three.descent) / 2, axis, accuracy: 1.0)
    }

    func testBinaryOperatorSpacing() {
        // Binary minus gets medium spaces; unary minus none.
        XCTAssertGreaterThan(r("a-b").width, r("a{-b}").width + 2)
        // Relations get thick spaces, suppressed in scripts.
        XCTAssertGreaterThan(r("a=b").width, r("a{=}b").width + 3)
        let script = r("x^{a=b}").width - r("x^{a{=}b}").width
        XCTAssertEqual(script, 0, accuracy: 0.01)
    }

    func testColorsAreApplied() throws {
        let dl = try list("x \\color{red} y \\textcolor{#0000FF}{z}")
        let colors = dl.ops.compactMap { op -> CGColor? in
            if case let .glyphs(_, _, _, color) = op { return color }
            return nil
        }
        XCTAssertEqual(colors.count, 3)
        XCTAssertEqual(colors[1].components?[0] ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(colors[2].components?[2] ?? 0, 1, accuracy: 0.01)
    }

    func testInkOverhangIsNotClipped() throws {
        let font = try XCTUnwrap(MathFont.shared)
        let dl = try list("f")
        guard case let .glyphs(_, glyphs, _, _) = try XCTUnwrap(dl.ops.first) else { return XCTFail() }
        let m = font.metrics(glyphs[0])
        let scale = size / font.unitsPerEm
        XCTAssertLessThanOrEqual(dl.bounds.minX, m.bounds.minX * scale + 0.01)
        XCTAssertGreaterThanOrEqual(dl.bounds.maxX, m.bounds.maxX * scale - 0.01)
        XCTAssertLessThanOrEqual(dl.bounds.minY, m.bounds.minY * scale + 0.01)
        // Display integral overhangs its advance on the right.
        let integral = try list("\\int")
        XCTAssertGreaterThan(integral.bounds.width, 0)
    }

    func testErrorsReturnNil() {
        for source in ["", "   ", "$$", "{x", "\\left( x", "\\begin{foo}x\\end{foo}", "\\frac{a}", "x}"] {
            XCTAssertNil(MathRenderer.render(source, fontSize: 14, color: .black, display: true), source)
        }
    }

    func testUnknownCommandStillRenders() {
        let result = r("\\foo + x")
        XCTAssertGreaterThan(result.width, r("x").width * 3)
    }

    func testStripsAccidentalDelimiters() {
        for wrapped in ["$x^2$", "$$x^2$$", "\\(x^2\\)", "\\[x^2\\]", "  $x^2$ "] {
            XCTAssertEqual(r(wrapped).width, r("x^2").width, accuracy: 0.001, wrapped)
        }
    }

    func testCacheReturnsSameImage() {
        let a = r("\\alpha + \\beta")
        let b = r("\\alpha + \\beta")
        XCTAssertTrue(a.image === b.image)
        let c = r("\\alpha + \\beta", color: .red)
        XCTAssertFalse(a.image === c.image)
    }

    func testImageIsPointSized() {
        let result = r("\\frac{1}{2}")
        XCTAssertEqual(result.image.size.width, result.width, accuracy: 0.001)
        XCTAssertEqual(result.image.size.height, result.ascent + result.descent, accuracy: 0.001)
        XCTAssertEqual(result.height, result.ascent + result.descent)
    }

    func testTagIsPlacedAfterFormula() {
        XCTAssertGreaterThan(r("x \\tag{1}").width, r("x").width + 2 * size)
    }

    func testTopLevelLineBreaksStackLines() {
        XCTAssertGreaterThan(r("a \\\\ b").height, r("a").height * 2)
        XCTAssertGreaterThan(r("a &= b \\\\ &= c").height, r("a = b").height * 2)
    }

    func testTextKeepsSpaces() {
        XCTAssertGreaterThan(r("\\text{a b}").width, r("\\text{ab}").width + 2)
        XCTAssertGreaterThan(r("a b").width + 0.01, r("ab").width)  // math mode ignores spaces
        XCTAssertEqual(r("a b").width, r("ab").width, accuracy: 0.001)
    }

    func testGlyphRunsAreMerged() throws {
        let dl = try list("abcdef")
        XCTAssertEqual(dl.ops.count, 1)
        XCTAssertEqual(dl.glyphCount, 6)
    }
}
