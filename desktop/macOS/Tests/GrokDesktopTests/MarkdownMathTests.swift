import XCTest
@testable import GrokDesktop

final class MarkdownMathTests: MarkdownTestCase {
    // MARK: Inline $…$

    func testSimpleInlineMath() {
        assertInlines("$x$", [math("x")])
        assertInlines("$a+b=c$", [math("a+b=c")])
        assertInlines("$\\frac{1}{2}$", [math("\\frac{1}{2}")])
        assertInlines("$E = mc^2$.", [math("E = mc^2"), t(".")])
        assertInlines("so $x$, $y$ and $z$", [t("so "), math("x"), t(", "), math("y"), t(" and "), math("z")])
    }

    func testCurrencyIsNotMath() {
        assertInlines("costs $5 and $10", [t("costs $5 and $10")])
        assertInlines("between $5 and $10.", [t("between $5 and $10.")])
        assertInlines("$ 5 dollars $", [t("$ 5 dollars $")])
        assertInlines("price: $20", [t("price: $20")])
        assertInlines("$x $", [t("$x $")])
        assertInlines("$$", [t("$$")])
        assertInlines("a $ b", [t("a $ b")])
    }

    func testClosingDollarFollowedByDigitIsNotACloser() {
        assertInlines("$x$1", [t("$x$1")])
        // The first `$` after the opener decides (refinement of Pandoc, which would keep scanning).
        assertInlines("$x$1 and $y$", [t("$x$1 and "), math("y")])
        assertInlines("The cost is $5 per unit and the value is $x$.", [t("The cost is $5 per unit and the value is "), math("x"), t(".")])
        assertParse("It costs $5.\nThen $y$ grows.", [p(t("It costs $5."), soft, t("Then "), math("y"), t(" grows."))])
        assertInlines("$x$2", [t("$x$2")])
    }

    func testEscapedDollars() {
        assertInlines("\\$x\\$", [t("$x$")])
        assertInlines("\\$5 and $x$", [t("$5 and "), math("x")])
        assertInlines("$a\\$b$", [math("a\\$b")])
    }

    func testMathContentIsRaw() {
        assertInlines("$a_1 * b_2 * c$", [math("a_1 * b_2 * c")])
        assertInlines("$\\{x\\}$", [math("\\{x\\}")])
        assertInlines("$*a*$ and _b_", [math("*a*"), t(" and "), em(t("b"))])
        assertInlines("$[a](b)$", [math("[a](b)")])
        assertInlines("$<b>$", [math("<b>")])
        assertInlines("$a \\\\ b$", [math("a \\\\ b")])
    }

    func testCodeSpansBindTighterThanMath() {
        assertInlines("`$x$`", [code("$x$")])
        assertInlines("`$` and `$`", [code("$"), t(" and "), code("$")])
        assertInlines("$a `b$` c", [t("$a "), code("b$"), t(" c")])
        assertInlines("$x$ and `y`", [math("x"), t(" and "), code("y")])
    }

    func testInlineMathMaySpanLines() {
        assertParse("where $a +\nb$ holds", [p(t("where "), math("a +\nb"), t(" holds"))])
    }

    func testMathDoesNotCrossParagraphs() {
        assertParse("a $x\n\ny$ b", [p(t("a $x")), p(t("y$ b"))])
    }

    // MARK: Display math inside paragraphs

    func testDisplayMathInParagraph() {
        assertInlines("so $$x^2$$ holds", [t("so "), dmath("x^2"), t(" holds")])
        assertInlines("$$ a $$ and $$b$$", [dmath("a"), t(" and "), dmath("b")])
        assertInlines("\\(x+1\\) and \\[y\\]", [math("x+1"), t(" and "), dmath("y")])
        assertInlines("\\( \\alpha \\)", [math("\\alpha")])
        assertInlines("\\(unclosed", [t("(unclosed")])
        assertInlines("\\[not math", [t("[not math")])
    }

    func testDisplayDollarsClosingOnOwnLineInsideParagraph() {
        assertParse("The formula $$\nx = 1\n$$ is nice", [p(t("The formula "), dmath("x = 1"), t(" is nice"))])
        assertParse("Formula $$x\n$$\nafter", [p(t("Formula "), dmath("x"), soft, t("after"))])
    }

    // MARK: Display math blocks

    func testDollarBlock() {
        assertParse("$$\nx = 1\n$$", [.math("x = 1")])
        assertParse("$$\n\\sum_{i=1}^n i\n= \\frac{n(n+1)}{2}\n$$\n", [.math("\\sum_{i=1}^n i\n= \\frac{n(n+1)}{2}")])
        assertParse("$$ x = 1 $$", [.math("x = 1")])
        assertParse("$$x = 1\ny = 2$$", [.math("x = 1\ny = 2")])
        assertParse("   $$\n   a\n   $$", [.math("a")])
    }

    func testMathBlockInterruptsParagraph() {
        assertParse("The formula is:\n$$\nE = mc^2\n$$\nwhere E is energy.", [
            p(t("The formula is:")),
            .math("E = mc^2"),
            p(t("where E is energy.")),
        ])
    }

    func testBracketAndEnvironmentBlocks() {
        assertParse("\\[\n\\int_0^1 x\\,dx\n\\]", [.math("\\int_0^1 x\\,dx")])
        assertParse("\\[ a^2 + b^2 = c^2 \\]", [.math("a^2 + b^2 = c^2")])
        assertParse("\\begin{align}\na &= b \\\\\nc &= d\n\\end{align}", [.math("\\begin{align}\na &= b \\\\\nc &= d\n\\end{align}")])
        assertParse("\\begin{equation*} x \\end{equation*}", [.math("\\begin{equation*} x \\end{equation*}")])
        assertParse(
            "\\begin{pmatrix}\n1 & 0 \\\\\n0 & 1\n\\end{pmatrix}\ntext",
            [.math("\\begin{pmatrix}\n1 & 0 \\\\\n0 & 1\n\\end{pmatrix}"), p(t("text"))]
        )
        // Unknown environments are not math blocks.
        assertParse("\\begin{itemize}\n\\end{itemize}", [p(t("\\begin{itemize}"), soft, t("\\end{itemize}"))])
    }

    func testNestedEnvironmentClosesOnOuterEnd() {
        let src = "\\begin{align}\nf(x) &= \\begin{cases} 1 \\\\ 0 \\end{cases}\n\\end{align}"
        assertParse(src, [.math(src)])
    }

    func testUnterminatedMathIsLatexCodeWhileStreaming() {
        assertParse("$$\nx = ", [fence("latex", "$$\nx = ", closed: false)])
        assertParse("Intro\n\n$$\n\\frac{a}{b}", [p(t("Intro")), fence("latex", "$$\n\\frac{a}{b}", closed: false)])
        assertParse("\\begin{align}\na &= b", [fence("latex", "\\begin{align}\na &= b", closed: false)])
        assertParse("\\[\nx", [fence("latex", "\\[\nx", closed: false)])
    }

    func testBlankLineEndsUnterminatedMath() {
        assertParse("$$\nx = 1\n\nNext paragraph", [fence("latex", "$$\nx = 1", closed: false), p(t("Next paragraph"))])
    }

    // MARK: Math in containers

    func testMathInListItems() {
        assertParse("1. Compute $x^2$:\n   $$\n   x^2 = 4\n   $$\n2. Done", [
            ol([p(t("Compute "), math("x^2"), t(":")), .math("x^2 = 4")], [p(t("Done"))]),
        ])
        assertParse("- item\n\n  $$\n  a+b\n  $$\n- next", [
            ul(tight: false, [p(t("item")), .math("a+b")], [p(t("next"))]),
        ])
    }

    func testMathInQuote() {
        assertParse("> $$\n> x\n> $$\n> and $y$", [quote(.math("x"), p(t("and "), math("y")))])
    }

    func testMathInTableCells() {
        let blocks = MarkdownParser.parse("| f | value |\n|---|---|\n| $x^2$ | $\\frac{1}{2}$ |\n| cost | $5 |")
        guard case .table(let table)? = blocks.first else { return XCTFail("expected table: \(blocks)") }
        XCTAssertEqual(table.rows[0], [[math("x^2")], [math("\\frac{1}{2}")]])
        XCTAssertEqual(table.rows[1], [[t("cost")], [t("$5")]])
    }

    func testMathPlainText() {
        XCTAssertEqual(MarkdownInline.plainText([t("a "), math("x"), t(" "), dmath("y")]), "a $x$ $$y$$")
        XCTAssertEqual(MarkdownParser.plainText([link("u", t("site")), soft, code("c")]), "site c")
    }
}
