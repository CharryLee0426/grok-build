import XCTest
@testable import GrokDesktop

final class MarkdownInlineTests: MarkdownTestCase {
    func testEscapes() {
        assertInlines("\\*not em\\* \\_x\\_ \\# \\\\", [t("*not em* _x_ # \\")])
        assertInlines("\\a stays", [t("\\a stays")])
        assertInlines("`\\*` code", [code("\\*"), t(" code")])
    }

    func testEntities() {
        assertInlines("&amp; &lt; &gt; &quot; &#39; &copy;", [t("& < > \" ' ©")])
        assertInlines("&nbsp;x &#123; &#x1F600; &#X22;", [t("\u{00A0}x { 😀 \"")])
        assertInlines("&unknownentity; & &#; &#xZZ;", [t("&unknownentity; & &#; &#xZZ;")])
        assertInlines("&#0;", [t("\u{FFFD}")])
    }

    func testCodeSpans() {
        assertInlines("`a`", [code("a")])
        assertInlines("`` a ` b ``", [code("a ` b")])
        assertInlines("` `` `", [code("``")])
        assertInlines("`  `", [code("  ")])
        assertInlines("```x``` y", [code("x"), t(" y")])
        assertInlines("`unclosed", [t("`unclosed")])
        assertInlines("``a`", [t("``a`")])
        assertInlines("`a\nb`", [code("a b")])
    }

    func testEmphasis() {
        assertInlines("*a* _b_ **c** __d__", [em(t("a")), t(" "), em(t("b")), t(" "), strong(t("c")), t(" "), strong(t("d"))])
        assertInlines("***both***", [em(strong(t("both")))])
        assertInlines("snake_case_name", [t("snake_case_name")])
        assertInlines("foo*bar*baz", [t("foo"), em(t("bar")), t("baz")])
        assertInlines("* not em *", [t("* not em *")])
        assertInlines("**a *b* c**", [strong(t("a "), em(t("b")), t(" c"))])
        assertInlines("*a **b** c*", [em(t("a "), strong(t("b")), t(" c"))])
        assertInlines("**unclosed", [t("**unclosed")])
        assertInlines("*foo**bar**baz*", [em(t("foo"), strong(t("bar")), t("baz"))])
        assertInlines("*foo**bar*", [em(t("foo**bar"))])
        assertInlines("**foo*", [t("*"), em(t("foo"))])
        assertInlines("***a** b*", [em(strong(t("a")), t(" b"))])
        assertInlines("**Note:** text", [strong(t("Note:")), t(" text")])
        assertInlines("__init__", [strong(t("init"))])
        assertInlines("2 * 3 * 4", [t("2 * 3 * 4")])
        assertInlines("*(a)*", [em(t("(a)"))])
        assertInlines("“*quoted*”", [t("“"), em(t("quoted")), t("”")])
    }

    func testLinks() {
        assertInlines("[a](https://x.com)", [link("https://x.com", t("a"))])
        assertInlines("[a](<url with spaces> 'T')", [link("url with spaces", t("a"), title: "T")])
        assertInlines("[a [nested] b](u)", [link("u", t("a [nested] b"))])
        assertInlines("[a](u(1)(2))", [link("u(1)(2)", t("a"))])
        assertInlines("[a](u \"t\")", [link("u", t("a"), title: "t")])
        assertInlines("[*em* `c`](u)", [link("u", em(t("em")), t(" "), code("c"))])
        assertInlines("[a]( u )", [link("u", t("a"))])
        assertInlines("[a]()", [link("", t("a"))])
        assertInlines("[a](url with spaces)", [t("[a](url with spaces)")])
        assertInlines("[a](u\\)v)", [link("u)v", t("a"))])
        assertInlines("[link [inner](a)](b)", [t("[link "), link("a", t("inner")), t("](b)")])
        assertInlines("*[a*](u)", [t("*"), link("u", t("a*"))])
        assertInlines("[a`]`](u)", [link("u", t("a"), code("]"))])
        assertInlines("[a `b](c)`", [t("[a "), code("b](c)")])
    }

    func testImages() {
        assertInlines("![alt *text*](a.png \"T\")", [.image(source: "a.png", title: "T", alt: "alt text")])
        assertInlines("[![img](i.png)](page)", [link("page", .image(source: "i.png", title: nil, alt: "img"))])
        assertInlines("!not an image", [t("!not an image")])
    }

    func testInlineHTML() {
        assertInlines("Press <kbd>Ctrl</kbd>+C", [t("Press "), .html("<kbd>"), t("Ctrl"), .html("</kbd>"), t("+C")])
        assertInlines("H<sub>2</sub>O and x<sup>2</sup>", [t("H"), .html("<sub>"), t("2"), .html("</sub>"), t("O and x"), .html("<sup>"), t("2"), .html("</sup>")])
        assertInlines("<span class=\"a\">x</span>", [.html("<span class=\"a\">"), t("x"), .html("</span>")])
        assertInlines("a<br>b<br/>c<BR />d", [t("a"), hard, t("b"), hard, t("c"), hard, t("d")])
        assertInlines("a<br>\nb", [t("a"), hard, t("b")])
        assertInlines("a < b > c", [t("a < b > c")])
        assertInlines("<!-- note -->", [.html("<!-- note -->")])
    }

    func testBreaks() {
        assertInlines("a  \nb", [t("a"), hard, t("b")])
        assertInlines("a\\\nb", [t("a"), hard, t("b")])
        assertInlines("a\nb", [t("a"), soft, t("b")])
        assertInlines("a \n   b", [t("a"), soft, t("b")])
        assertInlines("trailing\\", [t("trailing\\")])
    }

    func testFootnoteReferences() {
        assertInlines("fact[^1].", [t("fact"), .footnoteReference("1"), t(".")])
        assertInlines("[^ 1]", [t("[^ 1]")])
        assertInlines("[^]", [t("[^]")])
    }

    func testPlainText() {
        let inlines = MarkdownParser.parseInlines("**Bold** [link](u) `c` $x$ ![alt](i)  \nnext\nline")
        XCTAssertEqual(MarkdownParser.plainText(inlines), "Bold link c $x$ alt\nnext line")
        let blocks = MarkdownParser.parse("# T\n\n- [x] a\n- b\n\n| h |\n|---|\n| c |")
        XCTAssertEqual(MarkdownParser.plainText(blocks), "T\n\n- [x] a\n- b\n\nh\nc")
    }
}
