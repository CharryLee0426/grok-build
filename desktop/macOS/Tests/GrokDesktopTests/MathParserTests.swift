import XCTest
@testable import GrokDesktop

final class MathParserTests: XCTestCase {
    private func parse(_ s: String, display: Bool = true) throws -> MathFormula {
        try MathParser.parse(s, display: display)
    }

    private func atoms(_ list: MathList) -> [MathAtom] {
        list.compactMap(\.atom)
    }

    private func symbol(_ atom: MathAtom?) -> UInt32? {
        if case .symbol(let v)? = atom?.nucleus { return v }
        return nil
    }

    func testSuperscriptAndSubscript() throws {
        let f = try parse("x^2")
        XCTAssertEqual(f.list.count, 1)
        let atom = try XCTUnwrap(f.list.first?.atom)
        XCTAssertEqual(symbol(atom), 0x1D465)  // italic x
        XCTAssertEqual(symbol(atom.sup?.first?.atom), 0x32)
        XCTAssertNil(atom.sub)

        for source in ["x_i^2", "x^2_i"] {
            let a = try XCTUnwrap(parse(source).list.first?.atom)
            XCTAssertEqual(symbol(a.sup?.first?.atom), 0x32, source)
            XCTAssertEqual(symbol(a.sub?.first?.atom), 0x1D456, source)
        }
    }

    func testPrimes() throws {
        let f = try XCTUnwrap(parse("f''").list.first?.atom)
        XCTAssertEqual(symbol(f.sup?.first?.atom), 0x2033)
        let x = try XCTUnwrap(parse("x'^2").list.first?.atom)
        XCTAssertEqual(x.sup?.count, 2)
        XCTAssertEqual(symbol(x.sup?.first?.atom), 0x2032)
        XCTAssertEqual(symbol(x.sup?.last?.atom), 0x32)
    }

    func testLetterStylesAndGreek() throws {
        XCTAssertEqual(symbol(try parse("h").list.first?.atom), 0x210E)  // Planck constant
        XCTAssertEqual(symbol(try parse("\\alpha").list.first?.atom), 0x1D6FC)
        XCTAssertEqual(symbol(try parse("\\Gamma").list.first?.atom), 0x393)  // upright capital
        XCTAssertEqual(symbol(try parse("\\varGamma").list.first?.atom), 0x1D6E4)
        XCTAssertEqual(symbol(try parse("2").list.first?.atom), 0x32)
        XCTAssertEqual(symbol(try parse("α").list.first?.atom), 0x1D6FC)  // Unicode input
        let bb = try XCTUnwrap(parse("\\mathbb{R}").list.first?.atom)
        guard case .list(let inner) = bb.nucleus else { return XCTFail("expected list") }
        XCTAssertEqual(symbol(inner.first?.atom), 0x211D)
        guard case .list(let cal) = try XCTUnwrap(parse("\\mathcal{L}").list.first?.atom).nucleus else { return XCTFail() }
        XCTAssertEqual(symbol(cal.first?.atom), 0x2112)
        guard case .list(let bf) = try XCTUnwrap(parse("\\mathbf{x1}").list.first?.atom).nucleus else { return XCTFail() }
        XCTAssertEqual(bf.compactMap { symbol($0.atom) }, [0x1D431, 0x1D7CF])
        guard case .list(let rm) = try XCTUnwrap(parse("\\mathrm{d}").list.first?.atom).nucleus else { return XCTFail() }
        XCTAssertEqual(symbol(rm.first?.atom), 0x64)
    }

    func testAtomClasses() throws {
        let types = atoms(try parse("a + b = -c, d").list).map(\.type)
        XCTAssertEqual(types, [.ord, .bin, .ord, .rel, .bin, .ord, .punct, .ord])
        XCTAssertEqual(symbol(atoms(try parse("-x").list).first), 0x2212)  // hyphen → minus
    }

    func testFractionAndBinomial() throws {
        let frac = try XCTUnwrap(parse("\\frac{a}{b}").list.first?.atom)
        XCTAssertEqual(frac.type, .inner)
        guard case .fraction(let f) = frac.nucleus else { return XCTFail("expected fraction") }
        XCTAssertTrue(f.hasRule)
        XCTAssertEqual(f.numerator.count, 1)
        XCTAssertEqual(f.denominator.count, 1)

        guard case .fraction(let b) = try XCTUnwrap(parse("\\binom{n}{k}").list.first?.atom).nucleus else { return XCTFail() }
        XCTAssertFalse(b.hasRule)
        XCTAssertEqual(b.leftDelimiter, 0x28)

        guard case .list(let group) = try XCTUnwrap(parse("{a \\over b}").list.first?.atom).nucleus,
              case .fraction(let over)? = group.first?.atom?.nucleus else {
            return XCTFail("\\over should build a fraction")
        }
        XCTAssertEqual(over.numerator.count, 1)
        XCTAssertEqual(over.denominator.count, 1)
        guard case .fraction(let short) = try XCTUnwrap(parse("\\frac12").list.first?.atom).nucleus else { return XCTFail() }
        XCTAssertEqual(symbol(short.numerator.first?.atom), 0x31)
        XCTAssertEqual(symbol(short.denominator.first?.atom), 0x32)
    }

    func testLeftRight() throws {
        let atom = try XCTUnwrap(parse("\\left( x \\middle| y \\right.").list.first?.atom)
        XCTAssertEqual(atom.type, .inner)
        guard case .delimited(let d) = atom.nucleus else { return XCTFail() }
        XCTAssertEqual(d.left, 0x28)
        XCTAssertNil(d.right)
        XCTAssertEqual(d.body.count, 3)
        guard case .middleDelimiter(let m)? = d.body[1].atom?.nucleus else { return XCTFail() }
        XCTAssertEqual(m, 0x7C)
    }

    func testLargeOperatorsAndLimits() throws {
        let sum = try XCTUnwrap(parse("\\sum_{i=1}^n").list.first?.atom)
        XCTAssertEqual(sum.type, .op)
        XCTAssertEqual(sum.limits, .displayOnly)
        guard case .largeOperator(0x2211) = sum.nucleus else { return XCTFail() }
        XCTAssertEqual(sum.sub?.count, 3)
        XCTAssertEqual(try XCTUnwrap(parse("\\int_0^1").list.first?.atom).limits, .never)
        XCTAssertEqual(try XCTUnwrap(parse("\\int\\limits_0^1").list.first?.atom).limits, .always)
        XCTAssertEqual(try XCTUnwrap(parse("\\sum\\nolimits_i").list.first?.atom).limits, .never)
        let lim = try XCTUnwrap(parse("\\lim_{x\\to 0}").list.first?.atom)
        guard case .operatorName("lim") = lim.nucleus else { return XCTFail() }
        XCTAssertEqual(lim.limits, .displayOnly)
        guard case .operatorName("sin") = try XCTUnwrap(parse("\\sin").list.first?.atom).nucleus else { return XCTFail() }
        guard case .operatorName("tr") = try XCTUnwrap(parse("\\operatorname{tr}").list.first?.atom).nucleus else { return XCTFail() }
        XCTAssertEqual(try XCTUnwrap(parse("\\operatorname*{argmax}").list.first?.atom).limits, .displayOnly)
        XCTAssertEqual(try XCTUnwrap(parse("\\argmax").list.first?.atom).limits, .displayOnly)
    }

    func testEnvironments() throws {
        let pm = try XCTUnwrap(parse("\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}").list.first?.atom)
        guard case .delimited(let d) = pm.nucleus, case .array(let array)? = d.body.first?.atom?.nucleus else {
            return XCTFail("pmatrix should be a delimited array")
        }
        XCTAssertEqual(d.left, 0x28)
        XCTAssertEqual(array.kind, .matrix)
        XCTAssertEqual(array.rows.count, 2)
        XCTAssertEqual(array.rows[0].count, 2)

        let cases = try XCTUnwrap(parse("\\begin{cases} 1 & x > 0 \\\\ 0 & \\text{otherwise} \\end{cases}").list.first?.atom)
        guard case .delimited(let c) = cases.nucleus, case .array(let ca)? = c.body.first?.atom?.nucleus else { return XCTFail() }
        XCTAssertEqual(c.left, 0x7B)
        XCTAssertEqual(ca.kind, .cases)
        XCTAssertEqual(ca.rows.count, 2)

        guard case .array(let arr) = try XCTUnwrap(parse("\\begin{array}{l|cr} a & b & c \\\\ \\hline d & e & f \\end{array}").list.first?.atom).nucleus else { return XCTFail() }
        XCTAssertEqual(arr.alignments, [.left, .center, .right])
        XCTAssertEqual(arr.verticalRules[1], 1)
        XCTAssertEqual(arr.horizontalRules[1], 1)

        // Trailing \\ and \\[4pt] are tolerated.
        guard case .array(let al) = try XCTUnwrap(parse("\\begin{aligned} a &= b \\\\[4pt] &= c \\\\ \\end{aligned}").list.first?.atom).nucleus else { return XCTFail() }
        XCTAssertEqual(al.kind, .aligned)
        XCTAssertEqual(al.rows.count, 2)
        XCTAssertEqual(al.extraRowSpace[0] ?? 0, 0.4, accuracy: 0.001)
    }

    func testTopLevelLinesBecomeAlignedOrGathered() throws {
        guard case .array(let aligned) = try XCTUnwrap(parse("a &= b \\\\ &= c").list.first?.atom).nucleus else { return XCTFail() }
        XCTAssertEqual(aligned.kind, .aligned)
        XCTAssertEqual(aligned.rows.count, 2)
        // amsmath prefixes even cells with {} so the relation keeps its spacing.
        guard case .empty? = aligned.rows[0][1].first?.atom?.nucleus else { return XCTFail() }
        guard case .array(let gathered) = try XCTUnwrap(parse("a = b \\\\ c = d").list.first?.atom).nucleus else { return XCTFail() }
        XCTAssertEqual(gathered.kind, .gathered)
    }

    func testTextAndTag() throws {
        let f = try parse("x = 1 \\text{ if $y$ is } \\tag{3.1}")
        let text = try XCTUnwrap(atoms(f.list).last)
        guard case .text(let segments) = text.nucleus else { return XCTFail() }
        XCTAssertEqual(segments.count, 3)
        guard case .run(let first, .regular) = segments[0] else { return XCTFail() }
        XCTAssertEqual(first, " if ")
        guard case .math = segments[1] else { return XCTFail() }
        XCTAssertNotNil(f.tag)
    }

    func testNegation() throws {
        XCTAssertEqual(symbol(try parse("\\not=").list.first?.atom), 0x2260)
        XCTAssertEqual(symbol(try parse("\\not\\in").list.first?.atom), 0x2209)
        XCTAssertEqual(symbol(try parse("\\not\\subseteq").list.first?.atom), 0x2288)
        guard case .negated = try XCTUnwrap(parse("\\not\\propto").list.first?.atom).nucleus else { return XCTFail() }
    }

    func testRadicalAccentAndUnknown() throws {
        guard case .radical(let degree, let radicand) = try XCTUnwrap(parse("\\sqrt[3]{x}").list.first?.atom).nucleus else { return XCTFail() }
        XCTAssertEqual(degree?.count, 1)
        XCTAssertEqual(radicand.count, 1)
        guard case .accent(let a) = try XCTUnwrap(parse("\\hat x").list.first?.atom).nucleus else { return XCTFail() }
        XCTAssertEqual(a.scalar, 0x302)
        XCTAssertFalse(a.stretchy)
        guard case .unknownCommand("\\foo") = try XCTUnwrap(parse("\\foo{x}").list.first?.atom).nucleus else { return XCTFail() }
    }

    func testMacrosAndComments() throws {
        let f = try parse("\\newcommand{\\R}{\\mathbb{R}} x \\in \\R % trailing comment")
        XCTAssertEqual(atoms(f.list).count, 3)
        let g = try parse("\\newcommand{\\norm}[1]{\\left\\| #1 \\right\\|} \\norm{v}")
        guard case .delimited(let d) = try XCTUnwrap(atoms(g.list).first).nucleus else { return XCTFail() }
        XCTAssertEqual(d.left, 0x2016)
        let h = try parse("\\DeclareMathOperator{\\Tr}{Tr} \\Tr A")
        guard case .operatorName("Tr") = try XCTUnwrap(atoms(h.list).first).nucleus else { return XCTFail() }
    }

    func testChemistryTranslation() {
        XCTAssertEqual(TeXChemistry.latex(from: "H2O"), "\\mathrm{H}_{2}\\mathrm{O}")
        XCTAssertEqual(TeXChemistry.latex(from: "Ca2+"), "\\mathrm{Ca}^{2+}")
        XCTAssertEqual(TeXChemistry.latex(from: "OH-"), "\\mathrm{O}\\mathrm{H}^{-}")
        XCTAssertTrue(TeXChemistry.latex(from: "A -> B").contains("\\rightarrow"))
        XCTAssertNoThrow(try MathParser.parse("\\ce{2H2 + O2 -> 2H2O}"))
    }

    func testDimensions() {
        XCTAssertEqual(MathParser.dimension("1em"), .em(1))
        XCTAssertEqual(MathParser.dimension("-3mu"), .mu(-3))
        XCTAssertEqual(MathParser.dimension("10pt"), .em(1))
        XCTAssertEqual(MathParser.dimension("2 em"), .em(2))
        XCTAssertNil(MathParser.dimension("abc"))
    }

    func testStructuralErrorsThrow() {
        let bad = [
            "{x", "x}", "\\left( x", "x \\right)", "\\begin{foo} x \\end{foo}", "\\frac{a}", "x^",
            "\\begin{matrix} a", "\\begin{matrix} a \\end{pmatrix}", "\\sqrt", "\\text{abc", "\\left x \\right)",
            "\\end{matrix}",
        ]
        for source in bad {
            XCTAssertThrowsError(try MathParser.parse(source), source)
        }
    }

    func testRobustInputsParse() throws {
        let ok = [
            "\\;x\\;", "x \\\\", "a & b", "\\left. \\frac{a}{b} \\right|_{x=0}", "\\foo + \\bar{x}", "x^2^3",
            "\\text{naïve 中文}", "α ≤ β → ∑ ℝ", "\\hspace{1em}x\\hspace*{2pt}", "a \\mathrel{\\#} b",
            "\\def\\x{y} \\x", "\\color{red} x", "\\textcolor{#ff0000}{x}", "\\color[HTML]{00FF00}{x}",
        ]
        for source in ok {
            XCTAssertNoThrow(try MathParser.parse(source), source)
        }
    }
}
