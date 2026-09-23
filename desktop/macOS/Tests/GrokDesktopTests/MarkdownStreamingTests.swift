import XCTest
@testable import GrokDesktop

/// Deterministic RNG (SplitMix64) so fuzz/streaming failures are reproducible.
struct MarkdownTestRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class MarkdownStreamingTests: MarkdownTestCase {
    /// Feeds `doc` to a cache in chunks (sizes from `chunkSize`), asserting after every
    /// step that the cached result equals a from-scratch parse of the prefix.
    func assertStreamingEquivalence(_ doc: String, chunkSize: (inout MarkdownTestRNG) -> Int, seed: UInt64 = 1,
                                    file: StaticString = #filePath, line: UInt = #line) {
        var rng = MarkdownTestRNG(seed: seed)
        let scalars = Array(doc.unicodeScalars)
        let cache = MarkdownDocumentCache()
        var prefix = String.UnicodeScalarView()
        var i = 0
        var steps = 0
        while i < scalars.count {
            let end = min(i + max(1, chunkSize(&rng)), scalars.count)
            prefix.append(contentsOf: scalars[i..<end])
            i = end
            steps += 1
            let text = String(prefix)
            let cached = cache.blocks(for: text)
            let fresh = MarkdownParser.parse(text)
            if cached != fresh {
                XCTFail("streaming mismatch at step \(steps), prefix length \(text.utf8.count):\n...\(text.suffix(200))\nCACHED:\n\(dump(cached))\nFRESH:\n\(dump(fresh))", file: file, line: line)
                return
            }
        }
    }

    func testEveryStepWith50CharChunks() {
        assertStreamingEquivalence(MarkdownTestDocuments.mixed(bytes: 12_000), chunkSize: { _ in 50 })
    }

    func testEveryStepWithRandomChunks() {
        for seed: UInt64 in 1...4 {
            assertStreamingEquivalence(MarkdownTestDocuments.mixed(bytes: 8_000), chunkSize: { Int.random(in: 1...120, using: &$0) }, seed: seed)
        }
    }

    func testEveryStepCharacterByCharacter() {
        assertStreamingEquivalence(MarkdownTestDocuments.mixed(bytes: 2_500), chunkSize: { _ in 1 })
    }

    func testEveryStepOnTrickyConstructs() {
        let docs = [
            "Title\n-\n- item\n\nPara\n===\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nafter\n",
            "[x] and [y][z]\n\ntext\n\n[x]: /one\n\nmore [x]\n\n[z]: /two \"t\"\n",
            "Footnote[^n] here.\n\nMore text.\n\n[^n]: defined late\n",
            "```js\nlet a = 1\n\n\nlet b = 2\n```\n\n~~~\nunclosed\n",
            "$$\na\n\nb\n$$\n\n\\begin{align}\nx\n\\end{align}\n\n\\[\ny\n\\]\n",
            "> quote\ncontinued\n\n> [!NOTE] t\n> body\n\n1. a\n   - b\n\n     c\n2. d\n",
            "<div>\n\nhtml\n\n</div>\n<!--\ncomment\n-->\n    code\n\n    more\ntext\n",
            "a  \nb\\\nc<br>\n**bold *nested* text** ~~x~~ $m$ \\(n\\) https://x.y/z.\n\n***\n",
            "- [ ] a\n- [x] b\n\n10. ten\n11. eleven\n\n* star\n+ plus\n",
            "Setext\n--\nTable?\n| a |\n| - |\n\nPara\n    indented\n# h\n",
            "😀 *émphasis* 中文**粗体**测试。https://例子.com/路径\n\n| 列 | 值 |\n|---|---|\n| 一 | 二 |\n",
        ]
        for (i, doc) in docs.enumerated() {
            assertStreamingEquivalence(doc, chunkSize: { _ in 1 }, seed: UInt64(i))
            assertStreamingEquivalence(doc, chunkSize: { Int.random(in: 1...7, using: &$0) }, seed: UInt64(i))
        }
    }

    func testEveryStepOnLongThinkingParagraph() {
        let doc = MarkdownTestDocuments.thinking(lines: 300)
        assertStreamingEquivalence(doc, chunkSize: { Int.random(in: 20...90, using: &$0) }, seed: 7)
    }

    func testNonExtendingEditsFallBackToFullParse() {
        let cache = MarkdownDocumentCache()
        let texts = [
            "# A\n\npara one\n\npara two",
            "# A\n\npara one\n\npara two\n\n- x",
            "# B\n\npara one\n\npara two\n\n- x", // edit in the middle
            "# B\n\npara",                        // shorter
            "",
            "[l]: /u\n\n[l]",
            "[l]: /u\n\n[l]\n\n[m]",
            "[l]: /u\n\n[l]\n\n[m]\n\n[m]: /v",   // new definition affects an earlier block
        ]
        for text in texts {
            XCTAssertEqual(cache.blocks(for: text), MarkdownParser.parse(text), text)
        }
    }

    func testRepeatedTextReturnsSameBlocks() {
        let cache = MarkdownDocumentCache()
        let text = MarkdownTestDocuments.mixed(bytes: 3_000)
        let first = cache.blocks(for: text)
        XCTAssertEqual(cache.blocks(for: text), first)
        XCTAssertEqual(first, MarkdownParser.parse(text))
    }

    func testCheckpointsAreReused() {
        // The re-parse after appending should start at the last block, not the beginning.
        let base = MarkdownTestDocuments.mixed(bytes: 20_000)
        let result = MarkdownParser.parseDocument(Array(base.utf8), from: 0, inheritedDefinitions: [:])
        XCTAssertGreaterThan(result.checkpoints.count, 20)
        let last = result.checkpoints.last!
        XCTAssertGreaterThan(last.offset, base.utf8.count - 1_000)
        XCTAssertLessThanOrEqual(last.blockCount, result.blocks.count)
    }
}
