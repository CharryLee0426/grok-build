import XCTest
@testable import GrokDesktop

/// Random and pathological input must never crash, hang, or take super-linear time.
final class MarkdownFuzzTests: MarkdownTestCase {
    static let alphabet: [String] = [
        "*", "_", "~", "`", "$", "\\", "[", "]", "(", ")", "!", "<", ">", "&", "#", "|", "-", "+", "=", ":",
        ";", "^", "{", "}", "\"", "'", ".", "1", "2", "a", "b", "x", "w", "h", "t", "p", "s", "/", "@",
        " ", " ", " ", "  ", "\t", "\n", "\n", "\n\n", "\r\n", "\r", "    ",
        "é", "中", "😀", "\u{0301}", "\u{200D}", "\u{05D0}", "\u{0}", "\u{FEFF}", "·", "。",
        "```", "~~~", "$$", "\\(", "\\)", "\\[", "\\]", "- ", "1. ", "> ", "[!NOTE]", "- [ ] ", "| a |", "|---|",
        "&amp;", "&#x1F600;", "<br>", "<div>", "</div>", "<!--", "-->", "http://", "www.", "[^1]", "[^1]: ",
        "\\begin{align}", "\\end{align}", "**", "__", "***", "~~",
    ]

    func randomDocument(_ rng: inout MarkdownTestRNG, maxPieces: Int) -> String {
        let count = Int.random(in: 0...maxPieces, using: &rng)
        var s = ""
        for _ in 0..<count { s += Self.alphabet[Int.random(in: 0..<Self.alphabet.count, using: &rng)] }
        return s
    }

    func testRandomPunctuationSoup() {
        var rng = MarkdownTestRNG(seed: 42)
        let start = Date()
        for i in 0..<3_000 {
            let doc = randomDocument(&rng, maxPieces: i % 10 == 0 ? 1_500 : 150)
            let blocks = MarkdownParser.parse(doc)
            _ = MarkdownBlock.plainText(blocks)
            _ = MarkdownParser.parseInlines(doc)
        }
        let elapsed = Date().timeIntervalSince(start)
        print("FUZZ 3000 random documents in \(String(format: "%.2f", elapsed)) s")
        XCTAssertLessThan(elapsed, 30)
    }

    func testRandomSoupStreamingEquivalence() {
        var rng = MarkdownTestRNG(seed: 7)
        for _ in 0..<300 {
            let doc = randomDocument(&rng, maxPieces: 120)
            let scalars = Array(doc.unicodeScalars)
            let cache = MarkdownDocumentCache()
            var prefix = String.UnicodeScalarView()
            var i = 0
            while i < scalars.count {
                let end = min(i + Int.random(in: 1...6, using: &rng), scalars.count)
                prefix.append(contentsOf: scalars[i..<end])
                i = end
                let text = String(prefix)
                let cached = cache.blocks(for: text)
                let fresh = MarkdownParser.parse(text)
                if cached != fresh {
                    return XCTFail("mismatch for prefix \(text.debugDescription)\nCACHED \(dump(cached))\nFRESH \(dump(fresh))")
                }
            }
        }
    }

    func testTruncationsOfRealSamples() {
        let doc = MarkdownTestDocuments.mixed(bytes: 6_000)
        let scalars = Array(doc.unicodeScalars)
        let start = Date()
        var i = 0
        while i <= scalars.count {
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars[0..<i])
            _ = MarkdownParser.parse(String(view))
            i += 3
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 30)
    }

    func testPathologicalInputsAreFast() {
        let cases: [(String, String)] = [
            ("open brackets", String(repeating: "[", count: 20_000)),
            ("close brackets", String(repeating: "]", count: 20_000)),
            ("bracket pairs", String(repeating: "[a]", count: 10_000)),
            ("nested brackets", String(repeating: "[", count: 5_000) + String(repeating: "]", count: 5_000)),
            ("links with refs", "[a]: /u\n\n" + String(repeating: "[", count: 3_000) + "a" + String(repeating: "]", count: 3_000)),
            ("link openers", String(repeating: "[a](", count: 5_000)),
            ("unclosed titles", String(repeating: "[a](b \"", count: 5_000)),
            ("unclosed single titles", String(repeating: "[a](b '", count: 5_000)),
            ("links after brackets", String(repeating: "[", count: 5_000) + String(repeating: "[a](b)", count: 5_000)),
            ("image openers", String(repeating: "![", count: 10_000)),
            ("stars", String(repeating: "*", count: 20_000)),
            ("star words", String(repeating: "*a ", count: 10_000)),
            ("nested emphasis", String(repeating: "*a ", count: 5_000) + String(repeating: " a*", count: 5_000)),
            ("mixed delimiters", String(repeating: "_a *b ", count: 5_000) + String(repeating: "c* d_ ", count: 5_000)),
            ("underscores", String(repeating: "a_", count: 20_000)),
            ("tildes", String(repeating: "~~a ", count: 10_000)),
            ("backticks", String(repeating: "`", count: 10_000)),
            ("backtick runs", (1...300).map { String(repeating: "`", count: $0) + "a" }.joined()),
            ("dollars", String(repeating: "$", count: 20_000)),
            ("dollar words", String(repeating: "$a ", count: 10_000)),
            ("dollar digits", String(repeating: "$5 ", count: 10_000)),
            ("double dollars", String(repeating: "$$a ", count: 10_000)),
            ("math parens", String(repeating: "\\(a ", count: 10_000)),
            ("math brackets", String(repeating: "\\[a ", count: 10_000)),
            ("code then dollars", String(repeating: "$a `b` ", count: 5_000)),
            ("less-thans", String(repeating: "<", count: 20_000)),
            ("tag openers", String(repeating: "<a ", count: 10_000)),
            ("ampersands", String(repeating: "&#", count: 10_000)),
            ("url schemes", String(repeating: "http://", count: 5_000)),
            ("www", String(repeating: "www.", count: 5_000)),
            ("url parens", "https://a.com/" + String(repeating: ")", count: 20_000)),
            ("deep quotes", String(repeating: "> ", count: 5_000) + "a"),
            ("deep lists", String(repeating: "- ", count: 5_000) + "a"),
            ("deep ordered lists", String(repeating: "1. ", count: 3_000) + "a"),
            ("indented lines", (0..<2_000).map { String(repeating: " ", count: $0 % 40) + "- a" }.joined(separator: "\n")),
            ("pipes", String(repeating: "|", count: 20_000)),
            ("wide table", String(repeating: "|a", count: 5_000) + "\n" + String(repeating: "|-", count: 5_000) + "\n" + String(repeating: "|b", count: 5_000)),
            ("hashes", String(repeating: "#", count: 20_000)),
            ("short lines", String(repeating: "a\n", count: 50_000)),
            ("unbalanced code lines", String(repeating: "`a\n", count: 20_000)),
            ("currency lines", String(repeating: "$5\n", count: 20_000)),
            ("many fences", String(repeating: "```\n", count: 20_000)),
            ("many math blocks", String(repeating: "$$\n", count: 20_000)),
            ("setext attempts", String(repeating: "a\n=\n", count: 20_000)),
            ("ref definitions", (0..<5_000).map { "[l\($0)]: /u\($0)" }.joined(separator: "\n") + "\n\n[l1] [l4999]"),
            ("html comments", String(repeating: "<!-- ", count: 10_000)),
            ("single long line", String(repeating: "word **bold** `code` $m$ ", count: 5_000)),
        ]
        var worst = ("", 0.0)
        for (name, input) in cases {
            let start = Date()
            let blocks = MarkdownParser.parse(input)
            _ = MarkdownBlock.plainText(blocks)
            _ = blocks == blocks
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > worst.1 { worst = (name, elapsed) }
            XCTAssertLessThan(elapsed, MarkdownPerformanceTests.isOptimized ? 0.5 : 5, name)
        }
        print("FUZZ pathological worst case: \(worst.0) \(String(format: "%.1f", worst.1 * 1000)) ms")
    }

    func testDeepNestingIsCapped() {
        func depth(_ blocks: [MarkdownBlock]) -> Int {
            var d = 0
            for b in blocks {
                switch b {
                case .quote(let c), .callout(_, _, let c), .footnoteDefinition(_, let c): d = max(d, 1 + depth(c))
                case .list(let l): for item in l.items { d = max(d, 2 + depth(item.content)) }
                default: break
                }
            }
            return d
        }
        XCTAssertLessThanOrEqual(depth(MarkdownParser.parse(String(repeating: ">", count: 10_000) + " a")), MarkdownBlockParser.maxContainerDepth)
        XCTAssertLessThanOrEqual(depth(MarkdownParser.parse(String(repeating: "- ", count: 10_000) + "a")), MarkdownBlockParser.maxContainerDepth)

        func inlineDepth(_ inlines: [MarkdownInline]) -> Int {
            inlines.map { MarkdownInlineParser.depth(of: $0) }.max() ?? 0
        }
        let nested = String(repeating: "*a ", count: 3_000) + "b" + String(repeating: " c*", count: 3_000)
        XCTAssertLessThanOrEqual(inlineDepth(MarkdownParser.parseInlines(nested)), MarkdownInlineParser.maxInlineDepth + 1)
    }
}
