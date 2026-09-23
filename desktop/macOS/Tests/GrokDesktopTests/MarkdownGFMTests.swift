import XCTest
@testable import GrokDesktop

final class MarkdownGFMTests: MarkdownTestCase {
    func table(_ markdown: String, file: StaticString = #filePath, line: UInt = #line) -> MarkdownTable? {
        let blocks = MarkdownParser.parse(markdown)
        for block in blocks {
            if case .table(let table) = block { return table }
        }
        XCTFail("no table in \(dump(blocks))", file: file, line: line)
        return nil
    }

    // MARK: Tables

    func testBasicTable() {
        let src = "| Name | Value |\n|------|-------|\n| a | **1** |\n| b | `2` |"
        assertParse(src, [.table(MarkdownTable(
            alignments: [.none, .none],
            header: [[t("Name")], [t("Value")]],
            rows: [[[t("a")], [strong(t("1"))]], [[t("b")], [code("2")]]]
        ))])
    }

    func testAlignments() {
        let tbl = table("| a | b | c | d |\n|:--|:-:|--:|---|\n")
        XCTAssertEqual(tbl?.alignments, [.left, .center, .right, .none])
        XCTAssertEqual(tbl?.rows, [])
    }

    func testPipesOptionalAtEdges() {
        let tbl = table("a | b\n--- | ---\n1 | 2")
        XCTAssertEqual(tbl?.header, [[t("a")], [t("b")]])
        XCTAssertEqual(tbl?.rows, [[[t("1")], [t("2")]]])
    }

    func testEscapedPipesAndCodeSpans() {
        let tbl = table("| a | b |\n|---|---|\n| x \\| y | `c \\| d` |\n| `e|f` | g |")
        XCTAssertEqual(tbl?.rows[0], [[t("x | y")], [code("c | d")]])
        // GFM: an unescaped pipe inside a code span still separates cells.
        XCTAssertEqual(tbl?.rows[1], [[t("`e")], [t("f`")]])
    }

    func testRowsArePaddedAndTruncated() {
        let tbl = table("| a | b | c |\n|---|---|---|\n| 1 |\n| 1 | 2 | 3 | 4 |")
        XCTAssertEqual(tbl?.rows, [[[t("1")], [], []], [[t("1")], [t("2")], [t("3")]]])
    }

    func testHeaderAndDelimiterMustMatch() {
        assertParse("| a | b |\n|---|\n| c |", [p(t("| a | b |"), soft, t("|---|"), soft, t("| c |"))])
    }

    func testDelimiterNeedsDashes() {
        assertParse("| a |\n| : |", [p(t("| a |"), soft, t("| : |"))])
    }

    func testTableInterruptsParagraphAndEndsAtBlankOrBlock() {
        let src = "Intro text\n| a | b |\n|---|---|\n| 1 | 2 |\nstill row\n\nAfter\n\n| x |\n|---|\n| y |\n# Heading"
        let blocks = MarkdownParser.parse(src)
        XCTAssertEqual(blocks.count, 5, dump(blocks))
        XCTAssertEqual(blocks.first, p(t("Intro text")))
        if case .table(let t1) = blocks[1] {
            XCTAssertEqual(t1.rows, [[[t("1")], [t("2")]], [[t("still row")], []]])
        } else { XCTFail() }
        XCTAssertEqual(blocks[2], p(t("After")))
        if case .table(let t2) = blocks[3] { XCTAssertEqual(t2.rows, [[[t("y")]]]) } else { XCTFail() }
        XCTAssertEqual(blocks[4], h(1, t("Heading")))
    }

    func testTableInListAndQuote() {
        let listBlocks = MarkdownParser.parse("- Options:\n  | k | v |\n  |---|---|\n  | a | 1 |\n- next")
        guard case .list(let list)? = listBlocks.first else { return XCTFail(dump(listBlocks)) }
        XCTAssertEqual(list.items.count, 2)
        guard case .table(let tbl) = list.items[0].content.last! else { return XCTFail(dump(listBlocks)) }
        XCTAssertEqual(tbl.rows, [[[t("a")], [t("1")]]])

        let quoteBlocks = MarkdownParser.parse("> | k | v |\n> |---|---|\n> | a | 1 |")
        guard case .quote(let children)? = quoteBlocks.first, case .table(let qt)? = children.first else {
            return XCTFail(dump(quoteBlocks))
        }
        XCTAssertEqual(qt.header, [[t("k")], [t("v")]])
    }

    func testTableWithInlineCodeAndMath() {
        let tbl = table("| Symbol | Meaning |\n|:---:|---|\n| $\\alpha$ | learning rate, e.g. `0.01` |")
        XCTAssertEqual(tbl?.rows, [[[math("\\alpha")], [t("learning rate, e.g. "), code("0.01")]]])
    }

    // MARK: Strikethrough

    func testStrikethrough() {
        assertInlines("~~gone~~", [del(t("gone"))])
        assertInlines("a ~~b **c**~~ d", [t("a "), del(t("b "), strong(t("c"))), t(" d")])
        assertInlines("~single~", [t("~single~")])
        assertInlines("~~~triple~~~", [t("~~~triple~~~")])
        assertInlines("~~ spaced ~~", [t("~~ spaced ~~")])
        assertInlines("~~unclosed", [t("~~unclosed")])
    }

    // MARK: Autolinks

    func testExtendedAutolinks() {
        assertInlines("Visit https://example.com.", [t("Visit "), autolink("https://example.com"), t(".")])
        assertInlines("(see https://example.com/a)", [t("(see "), autolink("https://example.com/a"), t(")")])
        assertInlines("https://en.wikipedia.org/wiki/Foo_(bar)", [autolink("https://en.wikipedia.org/wiki/Foo_(bar)")])
        assertInlines("www.example.com/path?q=1, ok", [autolink("www.example.com/path?q=1", dest: "http://www.example.com/path?q=1"), t(", ok")])
        assertInlines("http://localhost:3000/api!", [autolink("http://localhost:3000/api"), t("!")])
        assertInlines("**https://a.com**", [strong(autolink("https://a.com"))])
        assertInlines("xhttps://a.com", [t("xhttps://a.com")])
        assertInlines("https://", [t("https://")])
        assertInlines("访问https://example.com。谢谢", [t("访问"), autolink("https://example.com"), t("。谢谢")])
        assertInlines("<https://a.com/x y>", [t("<https://a.com/x y>")])
        assertInlines("[see https://a.com]", [t("[see "), autolink("https://a.com"), t("]")])
    }

    func testAngleAutolinks() {
        assertInlines("<https://a.com/b?c=d>", [autolink("https://a.com/b?c=d")])
        assertInlines("<mailto:me@x.org>", [autolink("mailto:me@x.org")])
        assertInlines("<me@x.org>", [autolink("me@x.org", dest: "mailto:me@x.org")])
    }

    func testAutolinkInsideLinkTextIsFlattened() {
        assertInlines("[https://a.com](https://b.com)", [link("https://b.com", t("https://a.com"))])
    }

    // MARK: Task lists

    func testTaskListInsideNestedList() {
        assertParse("- Project\n  - [x] done\n  - [ ] open", [
            ul([p(t("Project")), tasks((true, [p(t("done"))]), (false, [p(t("open"))]))]),
        ])
    }
}
