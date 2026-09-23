import Foundation

/// Incremental parsing for streaming text.
///
/// `blocks(for:)` always returns exactly `MarkdownParser.parse(text)`. When `text` extends
/// the previously parsed text, parsing restarts from the last *checkpoint* of the previous
/// parse — the start of the last top-level block that began with no other block open
/// (after a blank line, a closed fence, a heading, a split long paragraph, …) — and the
/// blocks before it are reused. If the re-parsed tail changes the set of link reference /
/// footnote definitions (which can affect earlier blocks), it falls back to a full parse.
///
/// Not thread-safe; use one cache per message view.
final class MarkdownDocumentCache {
    private var bytes: [UInt8] = []
    private var result: MarkdownParser.DocumentResult?

    init() {}

    func blocks(for text: String) -> [MarkdownBlock] {
        let newBytes = Array(text.utf8)
        if let old = result, newBytes.count >= bytes.count, MarkdownDocumentCache.hasPrefix(newBytes, bytes) {
            if newBytes.count == bytes.count { return old.blocks }
            if let checkpoint = old.checkpoints.last, checkpoint.offset > 0,
               let updated = MarkdownDocumentCache.reparse(newBytes, from: checkpoint, old: old) {
                result = updated
                bytes = newBytes
                return updated.blocks
            }
        }
        let full = MarkdownParser.parseDocument(newBytes, from: 0, inheritedDefinitions: [:])
        result = full
        bytes = newBytes
        return full.blocks
    }

    private static func reparse(_ newBytes: [UInt8], from checkpoint: MarkdownParser.Checkpoint,
                                old: MarkdownParser.DocumentResult) -> MarkdownParser.DocumentResult? {
        var inherited: [String: MarkdownLinkDefinition] = [:]
        var log: [MarkdownParser.DefinitionEntry] = []
        for entry in old.definitionLog where entry.offset < checkpoint.offset {
            inherited[entry.key] = entry.definition
            log.append(entry)
        }
        let tail = MarkdownParser.parseDocument(newBytes, from: checkpoint.offset, inheritedDefinitions: inherited)
        // New or changed definitions may change how earlier blocks resolve links.
        guard tail.definitions == old.definitions else { return nil }
        var blocks = Array(old.blocks[0..<checkpoint.blockCount])
        blocks.append(contentsOf: tail.blocks)
        var checkpoints = Array(old.checkpoints.prefix { $0.offset < checkpoint.offset })
        for cp in tail.checkpoints {
            checkpoints.append(MarkdownParser.Checkpoint(offset: cp.offset, blockCount: cp.blockCount + checkpoint.blockCount))
        }
        log.append(contentsOf: tail.definitionLog)
        return MarkdownParser.DocumentResult(blocks: blocks, checkpoints: checkpoints, definitions: tail.definitions, definitionLog: log)
    }

    private static func hasPrefix(_ a: [UInt8], _ prefix: [UInt8]) -> Bool {
        guard a.count >= prefix.count else { return false }
        if prefix.isEmpty { return true }
        return a.withUnsafeBufferPointer { pa in
            prefix.withUnsafeBufferPointer { pb in
                memcmp(pa.baseAddress!, pb.baseAddress!, pb.count) == 0
            }
        }
    }
}
