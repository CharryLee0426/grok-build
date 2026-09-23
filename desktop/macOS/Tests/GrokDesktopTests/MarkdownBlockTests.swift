import XCTest
@testable import GrokDesktop

final class MarkdownBlockTests: MarkdownTestCase {
    // MARK: Headings

    func testATXHeadings() {
        assertParse("# One\n## Two ##\n###### Six\n####### Seven", [
            h(1, t("One")), h(2, t("Two")), h(6, t("Six")), p(t("####### Seven")),
        ])
        assertParse("#NoSpace", [p(t("#NoSpace"))])
        assertParse("# Title #not closing", [h(1, t("Title #not closing"))])
        assertParse("#", [h(1)])
    }

    func testSetextHeadings() {
        assertParse("Title\n=====\n\nSub *title*\n---", [h(1, t("Title")), h(2, t("Sub "), em(t("title")))])
        assertParse("Multi\nline\n===", [h(1, t("Multi"), soft, t("line"))])
    }

    func testSetextVersusThematicBreakAndList() {
        assertParse("para\n\n---", [p(t("para")), .thematicBreak])
        assertParse("- - -", [.thematicBreak])
        assertParse("* * *\n___", [.thematicBreak, .thematicBreak])
        assertParse("- a\n---", [ul([p(t("a"))]), .thematicBreak])
    }

    func testLoneDashAtEndOfStreamIsNotAnUnderline() {
        // While streaming "Intro:\n- item", the "-" alone must not flash a heading.
        assertParse("Intro:\n-", [p(t("Intro:"), soft, t("-"))])
        assertParse("Intro:\n-\n", [h(2, t("Intro:"))])
        assertParse("Intro:\n- item", [p(t("Intro:")), ul([p(t("item"))])])
    }

    // MARK: Code blocks

    func testFencedCode() {
        assertParse("```python {.x}\nprint(1)\n```", [fence("python", "print(1)")])
        assertParse("``` js title=\"a\"\nx\n```", [fence("js", "x")])
        assertParse("~~~\n```\n~~~", [fence(nil, "```")])
        assertParse("````md\n```\ninner\n```\n````", [fence("md", "```\ninner\n```")])
        assertParse("```\n\n  indented\n```", [fence(nil, "\n  indented")])
    }

    func testFenceIndentationIsStripped() {
        assertParse("   ```\n   a\n     b\n  c\n   ```", [fence(nil, "a\n  b\nc")])
    }

    func testUnclosedFenceIsStreaming() {
        assertParse("```swift\nlet x = 1\n", [fence("swift", "let x = 1", closed: false)])
        assertParse("```", [fence(nil, "", closed: false)])
    }

    func testClosingFenceMustBeLongEnough() {
        assertParse("````\na\n```\n````", [fence(nil, "a\n```")])
    }

    func testIndentedCode() {
        assertParse("    let a = 1\n\n    let b = 2\n\nText", [fence(nil, "let a = 1\n\nlet b = 2"), p(t("Text"))])
        assertParse("Para\n    not code", [p(t("Para"), soft, t("not code"))])
    }

    func testFenceInsideListAndQuote() {
        assertParse("- Step:\n  ```sh\n  make\n  ```\n- Next", [
            ul([p(t("Step:")), fence("sh", "make")], [p(t("Next"))]),
        ])
        assertParse("> ```\n> code\n> ```", [quote(fence(nil, "code"))])
    }

    // MARK: Lists

    func testBulletAndOrderedLists() {
        assertParse("- a\n- b", [ul([p(t("a"))], [p(t("b"))])])
        assertParse("3. three\n4. four", [ol(start: 3, [p(t("three"))], [p(t("four"))])])
        assertParse("1) a\n2) b", [ol([p(t("a"))], [p(t("b"))])])
    }

    func testChangingBulletCharStartsNewList() {
        assertParse("- a\n+ b\n* c", [ul([p(t("a"))]), ul([p(t("b"))]), ul([p(t("c"))])])
        assertParse("1. a\n2) b", [ol([p(t("a"))]), ol(start: 2, [p(t("b"))])])
    }

    func testLooseAndTight() {
        assertParse("- a\n\n- b", [ul(tight: false, [p(t("a"))], [p(t("b"))])])
        assertParse("- a\n\n  more\n- b", [ul(tight: false, [p(t("a")), p(t("more"))], [p(t("b"))])])
        assertParse("- a\n  - b\n\n  - c\n- d", [
            ul([p(t("a")), ul(tight: false, [p(t("b"))], [p(t("c"))])], [p(t("d"))]),
        ])
    }

    func testNestingTwoSpacesUnderBullet() {
        assertParse("- a\n  - b\n    - c\n- d", [
            ul([p(t("a")), ul([p(t("b")), ul([p(t("c"))])])], [p(t("d"))]),
        ])
    }

    func testNestingThreeSpacesUnderOrdered() {
        assertParse("1. First\n   - sub a\n   - sub b\n2. Second\n   1. nested\n   2. nested", [
            ol([p(t("First")), ul([p(t("sub a"))], [p(t("sub b"))])],
               [p(t("Second")), ol([p(t("nested"))], [p(t("nested"))])]),
        ])
    }

    func testNestingFourSpacesAndTabs() {
        assertParse("- a\n    - b\n- c", [ul([p(t("a")), ul([p(t("b"))])], [p(t("c"))])])
        assertParse("1. a\n    - b\n2. c", [ol([p(t("a")), ul([p(t("b"))])], [p(t("c"))])])
        assertParse("- a\n\t- b\n\t\t- c", [ul([p(t("a")), ul([p(t("b")), ul([p(t("c"))])])])])
        assertParse("1. a\n\t- b", [ol([p(t("a")), ul([p(t("b"))])])])
    }

    func testTwoSpaceBulletUnderOrderedNests() {
        // Deviation from CommonMark (which would end the ordered list here).
        assertParse("1. **Step one**\n  - detail\n  - detail 2\n2. **Step two**", [
            ol([p(strong(t("Step one"))), ul([p(t("detail"))], [p(t("detail 2"))])], [p(strong(t("Step two")))]),
        ])
    }

    func testContinuationParagraphIndentedFourSpacesIsNotCode() {
        assertParse("1. Step one\n\n    Explanation text.\n\n2. Step two", [
            ol(tight: false, [p(t("Step one")), p(t("Explanation text."))], [p(t("Step two"))]),
        ])
        assertParse("- item\n\n    continued", [ul(tight: false, [p(t("item")), p(t("continued"))])])
    }

    func testListInterruptingParagraph() {
        assertParse("Steps:\n- one\n- two", [p(t("Steps:")), ul([p(t("one"))], [p(t("two"))])])
        assertParse("Steps:\n1. one", [p(t("Steps:")), ol([p(t("one"))])])
        assertParse("The year\n2024. was good", [p(t("The year"), soft, t("2024. was good"))])
        assertParse("text\n-\nmore", [h(2, t("text")), p(t("more"))])
    }

    func testLazyContinuationInList() {
        assertParse("- a\nlazy\n- b", [ul([p(t("a"), soft, t("lazy"))], [p(t("b"))])])
    }

    func testTaskItems() {
        assertParse("- [ ] todo\n- [x] done\n- [X] Done\n- [y] not a task\n- []no", [
            tasks((false, [p(t("todo"))]), (true, [p(t("done"))]), (true, [p(t("Done"))]),
                  (nil, [p(t("[y] not a task"))]), (nil, [p(t("[]no"))])),
        ])
        assertParse("1. [x] ordered task", [.list(MarkdownList(ordered: true, start: 1, isTight: true, items: [
            MarkdownListItem(task: true, content: [p(t("ordered task"))]),
        ]))])
        assertParse("- [ ]", [tasks((false, []))])
    }

    func testItemWithMultipleBlocks() {
        let src = """
        1. Install:

           ```bash
           npm i
           ```

           > note

           | a | b |
           |---|---|
           | 1 | 2 |
        2. Done
        """
        let blocks = MarkdownParser.parse(src)
        guard case .list(let list)? = blocks.first, blocks.count == 1 else { return XCTFail(dump(blocks)) }
        XCTAssertTrue(list.ordered)
        XCTAssertFalse(list.isTight)
        XCTAssertEqual(list.items.count, 2)
        XCTAssertEqual(list.items[0].content.count, 4)
        XCTAssertEqual(list.items[0].content[1], fence("bash", "npm i"))
        XCTAssertEqual(list.items[0].content[2], quote(p(t("note"))))
        guard case .table(let table) = list.items[0].content[3] else { return XCTFail("table expected") }
        XCTAssertEqual(table.rows, [[[t("1")], [t("2")]]])
    }

    // MARK: Quotes and callouts

    func testBlockQuotes() {
        assertParse("> a\n> > b\n> c", [quote(p(t("a")), quote(p(t("b"), soft, t("c"))))])
        assertParse("> a\nlazy", [quote(p(t("a"), soft, t("lazy")))])
        assertParse("> a\n\n> b", [quote(p(t("a"))), quote(p(t("b")))])
        assertParse(">", [quote()])
    }

    func testCallouts() {
        assertParse("> [!NOTE]\n> Be careful.", [.callout(kind: "note", title: nil, content: [p(t("Be careful."))])])
        assertParse("> [!warning] Heads up\n> text", [.callout(kind: "warning", title: "Heads up", content: [p(t("text"))])])
        assertParse("> [!TIP]\n> - a\n> - b", [.callout(kind: "tip", title: nil, content: [ul([p(t("a"))], [p(t("b"))])])])
        assertParse("> [!IMPORTANT]", [.callout(kind: "important", title: nil, content: [])])
        assertParse("> [!CAUTION]\n>\n> para", [.callout(kind: "caution", title: nil, content: [p(t("para"))])])
        assertParse("> [!OTHER]\n> x", [quote(p(t("[!OTHER]"), soft, t("x")))])
    }

    // MARK: HTML, references, footnotes

    func testHTMLBlocks() {
        assertParse("<div class=\"x\">\n*hi*\n</div>\n\ntext", [.html("<div class=\"x\">\n*hi*\n</div>"), p(t("text"))])
        assertParse("<details>\n<summary>More</summary>\n\nBody\n\n</details>", [
            .html("<details>\n<summary>More</summary>"), p(t("Body")), .html("</details>"),
        ])
        assertParse("<!-- comment\nmore -->\nafter", [.html("<!-- comment\nmore -->"), p(t("after"))])
        assertParse("<br>", [p(hard)])
        assertParse("<custom-tag>\n\ntext", [.html("<custom-tag>"), p(t("text"))])
    }

    func testReferenceDefinitions() {
        assertParse("[id]: https://a.com \"Title\"\n\nSee [the site][id], [ID][] and [id].", [
            p(t("See "), link("https://a.com", t("the site"), title: "Title"), t(", "),
              link("https://a.com", t("ID"), title: "Title"), t(" and "), link("https://a.com", t("id"), title: "Title"), t(".")),
        ])
        assertParse("[a]: /x\n[b]: /y", [])
        assertParse("[missing] ref", [p(t("[missing] ref"))])
        assertParse("[x]\n\n[x]: /late", [p(link("/late", t("x")))])
    }

    func testFootnotes() {
        assertParse("Text[^1] and[^note].\n\n[^1]: First.\n[^note]: Second\n    continued.", [
            p(t("Text"), .footnoteReference("1"), t(" and"), .footnoteReference("note"), t(".")),
            .footnoteDefinition(label: "1", content: [p(t("First."))]),
            .footnoteDefinition(label: "note", content: [p(t("Second"), soft, t("continued."))]),
        ])
        // Non-numeric labels without a definition stay literal (e.g. regex classes).
        assertParse("Match [^a-z] here", [p(t("Match [^a-z] here"))])
    }

    // MARK: Tabs, blank lines, misc

    func testTabsExpandForIndentation() {
        assertParse("\tcode", [fence(nil, "code")])
        assertParse(">\t\tcode", [quote(fence(nil, "  code"))])
        assertParse("-\tfoo\n\n\tbar", [ul(tight: false, [p(t("foo")), p(t("bar"))])])
    }

    func testWindowsLineEndings() {
        assertParse("# T\r\n\r\npara\r\nline\r\n", [h(1, t("T")), p(t("para"), soft, t("line"))])
    }

    func testEmptyInput() {
        assertParse("", [])
        assertParse("\n\n  \n", [])
    }

    // MARK: More containers

    func testNestedContainers() {
        assertParse("- > quoted in list\n  > ```\n  > code\n  > ```", [
            ul([quote(p(t("quoted in list")), fence(nil, "code"))]),
        ])
        assertParse("1. Step\n   > [!WARNING]\n   > Careful", [
            ol([p(t("Step")), .callout(kind: "warning", title: nil, content: [p(t("Careful"))])]),
        ])
        assertParse("> - a\n>   - b\n> - c", [quote(ul([p(t("a")), ul([p(t("b"))])], [p(t("c"))]))])
    }

    func testLazyParagraphClosesInlineDisplayMath() {
        assertParse("- The formula $$\nx = 1\n$$ holds", [ul([p(t("The formula "), dmath("x = 1"), t(" holds"))])])
    }

    func testHTMLBlockTypes() {
        assertParse("<pre>\n*raw*\n\nstill pre\n</pre>\nafter", [.html("<pre>\n*raw*\n\nstill pre\n</pre>"), p(t("after"))])
        assertParse("<script>\nlet a = 1 < 2;\n</script>", [.html("<script>\nlet a = 1 < 2;\n</script>")])
        assertParse("text\n<span>\nmore", [p(t("text"), soft, .html("<span>"), soft, t("more"))])
    }

    func testHeadingWithInlineContent() {
        assertParse("## The $O(n)$ **fast** path ##", [h(2, t("The "), math("O(n)"), t(" "), strong(t("fast")), t(" path"))])
        assertParse("# `code` heading", [h(1, code("code"), t(" heading"))])
    }

    func testReferenceTitleForms() {
        assertParse("[a]: <b c> (paren title)\n\n[a]", [p(link("b c", t("a"), title: "paren title"))])
        assertParse("[A B]:\n  /multi\n  'line'\n\n[a   b]", [p(link("/multi", t("a   b"), title: "line"))])
    }

    func testThematicBreakInterruptsParagraph() {
        assertParse("para\n***\nmore", [p(t("para")), .thematicBreak, p(t("more"))])
    }
}
