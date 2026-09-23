import Foundation

/// Markdown parser: CommonMark + GitHub Flavored Markdown (tables, task lists,
/// strikethrough, extended autolinks, alerts, footnotes) + LaTeX math.
///
/// Behaviour worth knowing when rendering:
/// - Display math: `$$…$$`, `\[…\]` and `\begin{env}…\end{env}` blocks become `.math`.
///   While such a block is still unterminated (streaming), or if a blank line/container end
///   interrupts it, it is returned as `.code(language: "latex", code: <raw source>,
///   isClosed: false)` so the text does not flicker between math and paragraphs.
/// - Long paragraphs: a paragraph is ended at a line boundary once it reaches
///   `paragraphChunkLimit` UTF-16 units, provided no inline code/math span is open at that
///   point (otherwise it keeps growing, up to three times the limit), so a huge "thinking"
///   paragraph arrives as several consecutive `.paragraph` blocks that can be laid out
///   independently. The following line then starts a fresh block.
///
/// Deliberate deviations from CommonMark/GFM:
/// - Inline `$…$` follows Pandoc's rules, except that the first `$` after an opener decides:
///   if it cannot close (space before it, digit after it) the opener is literal text.
/// - A list marker of a different type/character indented at least two columns past its
///   parent's marker nests (`1. a` + `  - b`), where CommonMark would end the list.
/// - A lone `-`/`--` on the last, unterminated line is not a setext underline yet.
/// - Footnote references `[^x]` are recognised when `x` is numeric or has a definition.
/// - Bare `http(s)://` autolinks do not need a dotted domain (`http://localhost:3000`), may
///   follow CJK text, and stop at CJK/fullwidth punctuation.
/// - Only common named entities are decoded; container nesting is capped at
///   `MarkdownBlockParser.maxContainerDepth` and emphasis nesting at 32.
enum MarkdownParser {
    /// Target maximum size of one `.paragraph` block, in UTF-16 units.
    static let paragraphChunkLimit = MarkdownBlockParser.paragraphSoftLimit

    static func parse(_ text: String) -> [MarkdownBlock] {
        parseDocument(Array(text.utf8), from: 0, inheritedDefinitions: [:]).blocks
    }

    /// Parses inline content only (no block structure, no reference definitions).
    static func parseInlines(_ text: String) -> [MarkdownInline] {
        let bytes = Array(text.utf8)
        let r = MarkdownChar.trimmedRange(bytes, 0, bytes.count)
        if r.isEmpty { return [] }
        return MarkdownInlineParser.parse(r.count == bytes.count ? bytes : Array(bytes[r]), refs: [:])
    }

    static func plainText(_ inlines: [MarkdownInline]) -> String {
        MarkdownInline.plainText(inlines)
    }

    static func plainText(_ blocks: [MarkdownBlock]) -> String {
        MarkdownBlock.plainText(blocks)
    }

    // MARK: Incremental support

    /// A line start at which the block parser had no open blocks besides the document;
    /// parsing can restart there with a fresh parser (given the earlier definitions).
    struct Checkpoint {
        var offset: Int
        var blockCount: Int
    }

    struct DefinitionEntry {
        var offset: Int
        var key: String
        var definition: MarkdownLinkDefinition
    }

    struct DocumentResult {
        var blocks: [MarkdownBlock]
        var checkpoints: [Checkpoint]
        /// All definitions visible to the inline parser (first definition wins).
        var definitions: [String: MarkdownLinkDefinition]
        /// Definitions in document order with the offset of the block defining them.
        var definitionLog: [DefinitionEntry]
    }

    /// Parses `bytes[start...]` as a document. `inheritedDefinitions` are the definitions
    /// found before `start` (they take precedence over later ones).
    static func parseDocument(_ bytes: [UInt8], from start: Int, inheritedDefinitions: [String: MarkdownLinkDefinition]) -> DocumentResult {
        let parser = MarkdownBlockParser(bytes: bytes, definitions: inheritedDefinitions)
        parser.run(from: start)
        let converter = MarkdownBlockConverter(parser: parser, refs: parser.definitions)
        let children = parser.document.children
        var blocks: [MarkdownBlock] = []
        blocks.reserveCapacity(children.count)
        var countBefore: [Int] = []
        countBefore.reserveCapacity(children.count + 1)
        for child in children {
            countBefore.append(blocks.count)
            if let block = converter.convert(child) { blocks.append(block) }
        }
        countBefore.append(blocks.count)
        return DocumentResult(
            blocks: blocks,
            checkpoints: parser.checkpoints.map { Checkpoint(offset: $0.offset, blockCount: countBefore[$0.childIndex]) },
            definitions: parser.definitions,
            definitionLog: parser.addedDefinitions.map { DefinitionEntry(offset: $0.offset, key: $0.key, definition: $0.definition) }
        )
    }
}
