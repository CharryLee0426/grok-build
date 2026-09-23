import XCTest
@testable import GrokDesktop

/// Long paragraphs are split into several `.paragraph` blocks at line boundaries.
final class MarkdownChunkingTests: MarkdownTestCase {
    func paragraphs(_ blocks: [MarkdownBlock]) -> [[MarkdownInline]] {
        blocks.compactMap { if case .paragraph(let c) = $0 { return c } else { return nil } }
    }

    func count(_ inlines: [MarkdownInline], where predicate: (MarkdownInline) -> Bool) -> Int {
        inlines.filter(predicate).count
    }

    func testThinkingParagraphIsChunked() {
        let lineCount = 400
        let doc = MarkdownTestDocuments.thinking(lines: lineCount)
        let blocks = MarkdownParser.parse(doc)
        let paras = paragraphs(blocks)
        XCTAssertEqual(paras.count, blocks.count, "only paragraphs expected")
        XCTAssertGreaterThan(paras.count, 5)
        // Every source line is preserved: line breaks become soft breaks or chunk boundaries.
        let softBreaks = paras.reduce(0) { $0 + count($1) { $0 == .softBreak } }
        XCTAssertEqual(softBreaks + paras.count - 1, lineCount - 1)
        for para in paras.dropLast() {
            let units = MarkdownInline.plainText(para).utf16.count
            XCTAssertGreaterThanOrEqual(units, 1_700)
            XCTAssertLessThanOrEqual(units, MarkdownBlockParser.paragraphHardLimit + 200)
        }
        // Inline spans survive the split.
        let mathCount = paras.reduce(0) { $0 + count($1) { if case .math = $0 { return true } else { return false } } }
        XCTAssertEqual(mathCount, lineCount / 5 * 2)
    }

    func testChunkBoundaryAvoidsOpenCodeSpan() {
        var lines = (0..<19).map { i in "Line \(i) " + String(repeating: "x", count: 95) }
        lines.append("this line opens a code span `let a =")    // crosses the 2,000 unit mark
        lines.append("b + c` that closes here")
        lines.append(contentsOf: (0..<5).map { "tail \($0)" })
        let paras = paragraphs(MarkdownParser.parse(lines.joined(separator: "\n")))
        guard paras.count == 2 else { return XCTFail("expected 2 paragraphs, got \(paras.count)") }
        XCTAssertTrue(paras[0].contains(.code("let a = b + c")), "\(paras[0].suffix(3))")
        XCTAssertEqual(paras[1].first, t("tail 0"))
    }

    func testChunkBoundaryAvoidsOpenMathSpan() {
        var lines = (0..<19).map { i in "Row \(i) " + String(repeating: "y", count: 97) }
        lines.append("math starts $x +")
        lines.append("y$ and ends")
        lines.append("after")
        let paras = paragraphs(MarkdownParser.parse(lines.joined(separator: "\n")))
        guard paras.count == 2 else { return XCTFail("expected 2 paragraphs, got \(paras.count)") }
        XCTAssertTrue(paras[0].contains(.math("x +\ny")))
        XCTAssertEqual(paras[1], [t("after")])
    }

    func testUnbalancedTextFallsBackToHardLimit() {
        // "$5" never closes, so the split is deferred up to the hard limit.
        let lines = (0..<200).map { i in "It costs $5 per unit, line \(i) " + String(repeating: "z", count: 60) }
        let paras = paragraphs(MarkdownParser.parse(lines.joined(separator: "\n")))
        XCTAssertGreaterThan(paras.count, 1)
        let first = MarkdownInline.plainText(paras[0]).utf16.count
        XCTAssertGreaterThanOrEqual(first, MarkdownBlockParser.paragraphHardLimit - 100)
    }

    func testSingleLongLineIsNotSplit() {
        let line = String(repeating: "word ", count: 2_000)
        XCTAssertEqual(paragraphs(MarkdownParser.parse(line)).count, 1)
    }

    func testChunkingInsideListItem() {
        let body = (0..<80).map { "  line \($0) " + String(repeating: "q", count: 50) }.joined(separator: "\n")
        let blocks = MarkdownParser.parse("- item\n" + body + "\n- next")
        guard case .list(let list)? = blocks.first, blocks.count == 1 else { return XCTFail(dump(blocks)) }
        XCTAssertEqual(list.items.count, 2)
        XCTAssertGreaterThan(list.items[0].content.count, 1)
        XCTAssertTrue(list.isTight)
    }

    func testShortParagraphsUnaffected() {
        assertParse("a\nb\nc", [p(t("a"), soft, t("b"), soft, t("c"))])
    }
}
