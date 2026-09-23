import Foundation

/// A line (or the rest of a line) belonging to a leaf block: `spaces` columns of
/// indentation left over from a partially consumed tab, then `s[start..<end]`.
struct MarkdownLineSlice {
    var spaces: Int
    var start: Int
    var end: Int
}

/// Mutable block node used while parsing; converted to `MarkdownBlock` afterwards.
final class MarkdownBlockNode {
    enum Kind { case document, blockQuote, list, item, footnote, paragraph, heading, fencedCode, indentedCode, html, math, thematicBreak, table }
    enum MathStyle { case dollars, brackets, environment }

    let kind: Kind
    var children: [MarkdownBlockNode] = []
    var lines: [MarkdownLineSlice] = []
    var startLine: Int
    var endLine: Int
    /// Byte offset of the line on which the block starts.
    let startOffset: Int

    // Lists and items
    var ordered = false
    var marker: UInt8 = 0 // bullet character, or `.` / `)` for ordered lists
    var listStart = 1
    var markerOffset = 0
    var padding = 0
    var tight = true
    // Headings and paragraphs (content is filled when the block is finalized)
    var level = 0
    var content: [UInt8] = [] // paragraphs: built line by line
    var lastLineStart = 0     // index in `content` where the last paragraph line starts
    var utf16Length = 0
    // Incremental scan state for long-paragraph splitting (see `spansBalanced`).
    var balancePosition = 0
    var pendingSpan = 0
    var pendingRun = 0
    var pendingContentStart = 0
    // Fenced code and math
    var fenceChar: UInt8 = 0
    var fenceLength = 0
    var fenceOffset = 0
    var info: String?
    var closed = false
    var mathStyle: MathStyle = .dollars
    var environment: [UInt8] = []
    // HTML blocks, tables, footnotes
    var htmlType = 0
    var alignments: [MarkdownTableAlignment] = []
    var label = ""

    init(kind: Kind, startLine: Int, startOffset: Int) {
        self.kind = kind
        self.startLine = startLine
        self.endLine = startLine
        self.startOffset = startOffset
    }

    var acceptsLinesAsLeaf: Bool {
        switch kind {
        case .fencedCode, .indentedCode, .html, .math: return true
        default: return false
        }
    }

    func canContain(_ child: Kind) -> Bool {
        switch kind {
        case .document, .blockQuote, .item, .footnote: return child != .item
        case .list: return child == .item
        default: return false
        }
    }
}

/// CommonMark block-structure parser (a port of the commonmark.js algorithm) extended
/// with GFM tables, footnote definitions, display-math blocks and long-paragraph chunking.
final class MarkdownBlockParser {
    /// Paragraphs are split at line boundaries once they reach this many UTF-16 units
    /// (if no code/math span is open), and unconditionally at `paragraphHardLimit`.
    static let paragraphSoftLimit = 2_000
    static let paragraphHardLimit = 6_000
    /// Maximum depth of nested containers (quotes, lists, footnotes).
    static let maxContainerDepth = 48

    let s: [UInt8]
    let document: MarkdownBlockNode
    var stack: [MarkdownBlockNode]

    // Current line state (offsets are absolute byte indices into `s`).
    var lineStart = 0
    var lineEnd = 0
    var lineNumber = 0
    var lineTerminated = false
    var offset = 0
    var column = 0
    var nextNonspace = 0
    var nextNonspaceColumn = 0
    var indent = 0
    var indented = false
    var blank = false
    var partiallyConsumedTab = false
    var allClosed = true
    var lastMatchedDepth = 0

    /// Link reference definitions (and footnote labels under `footnoteKeyPrefix`); first wins.
    var definitions: [String: MarkdownLinkDefinition]
    /// Definitions added by this parse, with the byte offset of their block.
    var addedDefinitions: [(offset: Int, key: String, definition: MarkdownLinkDefinition)] = []
    /// Offsets of line starts at which only the document was open, with the number of
    /// top-level blocks closed so far. Parsing can restart from any of them.
    var checkpoints: [(offset: Int, childIndex: Int)] = []

    init(bytes: [UInt8], definitions: [String: MarkdownLinkDefinition]) {
        s = bytes
        document = MarkdownBlockNode(kind: .document, startLine: 0, startOffset: 0)
        stack = [document]
        self.definitions = definitions
    }

    func run(from start: Int) {
        let n = s.count
        var p = start
        while p < n {
            if stack.count == 1 { checkpoints.append((p, document.children.count)) }
            var e = p
            while e < n {
                let c = s[e]
                if c == MarkdownChar.newline || c == MarkdownChar.carriageReturn { break }
                e += 1
            }
            var next = e
            if e < n {
                next = (s[e] == MarkdownChar.carriageReturn && e + 1 < n && s[e + 1] == MarkdownChar.newline) ? e + 2 : e + 1
            }
            lineTerminated = e < n
            processLine(start: p, end: e)
            p = next
        }
        if stack.count == 1, n > start, s[n - 1] == MarkdownChar.newline {
            checkpoints.append((n, document.children.count))
        }
        while stack.count > 1 {
            finalize(stack[stack.count - 1], endLine: lineNumber)
            stack.removeLast()
        }
    }

    // MARK: Line cursor

    func findNextNonspace() {
        var i = offset
        var cols = column
        while i < lineEnd {
            let c = s[i]
            if c == MarkdownChar.space {
                i += 1
                cols += 1
            } else if c == MarkdownChar.tab {
                i += 1
                cols += 4 - cols % 4
            } else {
                break
            }
        }
        blank = i >= lineEnd
        nextNonspace = i
        nextNonspaceColumn = cols
        indent = cols - column
        indented = indent >= 4
    }

    func advanceOffset(_ count: Int, columns: Bool) {
        var count = count
        while count > 0 && offset < lineEnd {
            if s[offset] == MarkdownChar.tab {
                let charsToTab = 4 - column % 4
                if columns {
                    partiallyConsumedTab = charsToTab > count
                    let advance = min(charsToTab, count)
                    column += advance
                    offset += partiallyConsumedTab ? 0 : 1
                    count -= advance
                } else {
                    partiallyConsumedTab = false
                    column += charsToTab
                    offset += 1
                    count -= 1
                }
            } else {
                partiallyConsumedTab = false
                offset += 1
                column += 1
                count -= 1
            }
        }
    }

    func advanceNextNonspace() {
        offset = nextNonspace
        column = nextNonspaceColumn
        partiallyConsumedTab = false
    }

    @inline(__always) func peek(_ i: Int) -> UInt8? { i < lineEnd ? s[i] : nil }

    // MARK: Line processing

    func processLine(start: Int, end: Int) {
        lineNumber += 1
        lineStart = start
        lineEnd = end
        offset = start
        column = 0
        blank = false
        partiallyConsumedTab = false

        var matched = 0
        var depth = 1
        matching: while depth < stack.count {
            findNextNonspace()
            switch continueBlock(stack[depth]) {
            case 0:
                matched = depth
                depth += 1
            case 1:
                break matching
            default:
                return // the line was fully consumed (e.g. a closing fence)
            }
        }
        allClosed = matched == stack.count - 1
        lastMatchedDepth = matched
        var container = stack[matched]
        var matchedLeaf = container.acceptsLinesAsLeaf

        while !matchedLeaf {
            findNextNonspace()
            if !indented && (blank || !MarkdownBlockParser.maybeSpecial[Int(s[nextNonspace])]) {
                advanceNextNonspace()
                break
            }
            let result = tryBlockStarts(container)
            if result == .none {
                advanceNextNonspace()
                break
            }
            if result == .consumed { return }
            container = stack[stack.count - 1]
            if result == .leaf { matchedLeaf = true }
        }

        let tip = stack[stack.count - 1]
        if !allClosed && !blank && tip.kind == .paragraph {
            addLine(to: tip) // lazy continuation
            sealParagraphIfNeeded(tip)
            return
        }
        closeUnmatchedBlocks()
        switch container.kind {
        case .fencedCode, .indentedCode, .math:
            addLine(to: container)
        case .html:
            addLine(to: container)
            if container.htmlType >= 1 && container.htmlType <= 5 && htmlBlockEnds(container.htmlType, from: offset) {
                finalize(container, endLine: lineNumber)
                stack.removeLast()
            }
        case .table:
            addLine(to: container)
        case .paragraph:
            addLine(to: container)
            sealParagraphIfNeeded(container)
        default:
            if offset < lineEnd && !blank {
                let paragraph = addChild(.paragraph)
                advanceNextNonspace()
                addLine(to: paragraph)
                sealParagraphIfNeeded(paragraph)
            }
        }
    }

    /// Returns 0 if the container continues on this line, 1 if not, 2 if the line was consumed.
    func continueBlock(_ node: MarkdownBlockNode) -> Int {
        switch node.kind {
        case .blockQuote:
            if !indented && peek(nextNonspace) == 0x3E {
                advanceNextNonspace()
                advanceOffset(1, columns: false)
                if let c = peek(offset), MarkdownChar.isSpaceOrTab(c) { advanceOffset(1, columns: true) }
                return 0
            }
            return 1
        case .item:
            if blank {
                if node.children.isEmpty { return 1 }
                advanceNextNonspace()
                return 0
            }
            if indent >= node.markerOffset + node.padding {
                advanceOffset(node.markerOffset + node.padding, columns: true)
                return 0
            }
            // LLM-friendly deviation: a *different kind* of list marker indented at least two
            // columns past the parent marker nests (e.g. "1. a\n  - b"), instead of ending the list.
            if indent >= node.markerOffset + 2 && !node.children.isEmpty && startsDifferentListMarker(node) {
                advanceNextNonspace()
                return 0
            }
            return 1
        case .footnote:
            if blank {
                advanceNextNonspace()
                return 0
            }
            if indent >= 4 {
                advanceOffset(4, columns: true)
                return 0
            }
            return 1
        case .document, .list:
            return 0
        case .paragraph, .table:
            return blank ? 1 : 0
        case .heading, .thematicBreak:
            return 1
        case .fencedCode:
            if indent <= 3, peek(nextNonspace) == node.fenceChar {
                var j = nextNonspace
                while j < lineEnd && s[j] == node.fenceChar { j += 1 }
                let length = j - nextNonspace
                while j < lineEnd && MarkdownChar.isSpaceOrTab(s[j]) { j += 1 }
                if length >= node.fenceLength && j == lineEnd {
                    node.closed = true
                    finalize(node, endLine: lineNumber)
                    stack.removeLast()
                    return 2
                }
            }
            var i = node.fenceOffset
            while i > 0, let c = peek(offset), MarkdownChar.isSpaceOrTab(c) {
                advanceOffset(1, columns: true)
                i -= 1
            }
            return 0
        case .indentedCode:
            if indent >= 4 {
                advanceOffset(4, columns: true)
                return 0
            }
            if blank {
                advanceNextNonspace()
                return 0
            }
            return 1
        case .html:
            return blank && (node.htmlType == 6 || node.htmlType == 7) ? 1 : 0
        case .math:
            if blank { return 1 } // LaTeX display math cannot contain blank lines
            var i = node.fenceOffset
            while i > 0, let c = peek(offset), MarkdownChar.isSpaceOrTab(c) {
                advanceOffset(1, columns: true)
                i -= 1
            }
            if mathLineCloses(node, from: offset) {
                addLine(to: node)
                node.closed = true
                finalize(node, endLine: lineNumber)
                stack.removeLast()
                return 2
            }
            return 0
        }
    }

    func closeUnmatchedBlocks() {
        guard !allClosed else { return }
        while stack.count - 1 > lastMatchedDepth {
            finalize(stack[stack.count - 1], endLine: lineNumber - 1)
            stack.removeLast()
        }
        allClosed = true
    }

    @discardableResult
    func addChild(_ kind: MarkdownBlockNode.Kind) -> MarkdownBlockNode {
        while !stack[stack.count - 1].canContain(kind) {
            finalize(stack[stack.count - 1], endLine: lineNumber - 1)
            stack.removeLast()
        }
        let node = MarkdownBlockNode(kind: kind, startLine: lineNumber, startOffset: lineStart)
        stack[stack.count - 1].children.append(node)
        stack.append(node)
        return node
    }

    func addLine(to node: MarkdownBlockNode) {
        var spaces = 0
        if partiallyConsumedTab {
            offset += 1
            spaces = 4 - column % 4
        }
        node.lines.append(MarkdownLineSlice(spaces: spaces, start: offset, end: lineEnd))
        if node.kind == .paragraph {
            if node.lines.count > 1 { node.content.append(MarkdownChar.newline) }
            node.lastLineStart = node.content.count
            if spaces > 0 { node.content.append(contentsOf: repeatElement(MarkdownChar.space, count: spaces)) }
            node.content.append(contentsOf: s[offset..<lineEnd])
            node.utf16Length += MarkdownChar.utf16Count(s, offset, lineEnd) + 1
        }
    }

    // MARK: Finalization

    func finalize(_ node: MarkdownBlockNode, endLine: Int) {
        node.endLine = max(endLine, node.startLine)
        switch node.kind {
        case .paragraph:
            let (content, defs) = paragraphContent(node)
            commit(defs, offset: node.startOffset)
            node.content = content
            node.lines = []
        case .indentedCode:
            while let last = node.lines.last, isBlank(last) {
                node.lines.removeLast()
                node.endLine -= 1
            }
        case .item:
            node.endLine = node.children.last?.endLine ?? node.startLine
        case .list:
            node.endLine = node.children.last?.endLine ?? node.startLine
            node.tight = !MarkdownBlockParser.hasBlankGap(node.children) &&
                !node.children.contains { MarkdownBlockParser.hasBlankGap($0.children) }
        default:
            break
        }
    }

    static func hasBlankGap(_ nodes: [MarkdownBlockNode]) -> Bool {
        guard nodes.count > 1 else { return false }
        for i in 0..<(nodes.count - 1) where nodes[i + 1].startLine > nodes[i].endLine + 1 { return true }
        return false
    }

    func isBlank(_ line: MarkdownLineSlice) -> Bool {
        var i = line.start
        while i < line.end {
            if !MarkdownChar.isSpaceOrTab(s[i]) { return false }
            i += 1
        }
        return true
    }

    func joinedLines(_ lines: [MarkdownLineSlice]) -> [UInt8] {
        var out: [UInt8] = []
        var total = 0
        for line in lines { total += line.spaces + line.end - line.start + 1 }
        out.reserveCapacity(total)
        for (i, line) in lines.enumerated() {
            if i > 0 { out.append(MarkdownChar.newline) }
            if line.spaces > 0 { out.append(contentsOf: repeatElement(MarkdownChar.space, count: line.spaces)) }
            out.append(contentsOf: s[line.start..<line.end])
        }
        return out
    }

    /// Paragraph text with leading link reference definitions removed (not yet committed).
    func paragraphContent(_ node: MarkdownBlockNode) -> ([UInt8], [(String, MarkdownLinkDefinition)]) {
        let content = node.content
        guard content.first == 0x5B else { return (content, []) }
        var defs: [(String, MarkdownLinkDefinition)] = []
        var p = 0
        while p < content.count && content[p] == 0x5B, let def = MarkdownLinkScanner.referenceDefinition(content, at: p) {
            defs.append((def.label, def.definition))
            p = def.end
        }
        return (p == 0 ? content : Array(content[p...]), defs)
    }

    func commit(_ defs: [(String, MarkdownLinkDefinition)], offset: Int) {
        for (key, def) in defs where definitions[key] == nil {
            definitions[key] = def
            addedDefinitions.append((offset, key, def))
        }
    }

    // MARK: Long paragraph chunking

    func sealParagraphIfNeeded(_ node: MarkdownBlockNode) {
        guard node.utf16Length >= MarkdownBlockParser.paragraphSoftLimit, lineTerminated,
              stack.last === node else { return }
        if node.utf16Length < MarkdownBlockParser.paragraphHardLimit {
            guard spansBalanced(node) else { return }
        }
        finalize(node, endLine: lineNumber)
        stack.removeLast()
    }

    /// True when no inline code span or math span (`` ` ``, `$`, `$$`, `\(`, `\[`) is left
    /// open at the end of the paragraph, i.e. splitting here cannot cut such a span.
    /// The scan is incremental: it resumes where the previous call stopped (lines are
    /// separated by `\n`, so no delimiter straddles the resume point).
    func spansBalanced(_ node: MarkdownBlockNode) -> Bool {
        let b = node.content
        let n = b.count
        var i = node.balancePosition
        if node.pendingSpan != 0 {
            guard let after = MarkdownBlockParser.spanCloser(node.pendingSpan, run: node.pendingRun, in: b, from: i,
                                                             contentStart: node.pendingContentStart) else {
                node.balancePosition = n
                return false
            }
            node.pendingSpan = 0
            i = after
        }
        while i < n {
            let c = b[i]
            var kind = 0
            var run = 0
            var searchFrom = 0
            if c == MarkdownChar.backslash {
                guard i + 1 < n, b[i + 1] == 0x28 || b[i + 1] == 0x5B else {
                    i += 2
                    continue
                }
                kind = b[i + 1] == 0x28 ? 4 : 5
                searchFrom = i + 2
            } else if c == MarkdownChar.backtick {
                var j = i
                while j < n && b[j] == MarkdownChar.backtick { j += 1 }
                kind = 1
                run = j - i
                searchFrom = j
            } else if c == MarkdownChar.dollar {
                if i + 1 < n && b[i + 1] == MarkdownChar.dollar {
                    kind = 2
                    searchFrom = i + 2
                } else if i + 1 < n && !MarkdownChar.isWhitespace(b[i + 1]) {
                    kind = 3
                    searchFrom = i + 1
                } else {
                    i += 1
                    continue
                }
            } else {
                i += 1
                continue
            }
            guard let after = MarkdownBlockParser.spanCloser(kind, run: run, in: b, from: searchFrom, contentStart: searchFrom) else {
                node.pendingSpan = kind
                node.pendingRun = run
                node.pendingContentStart = searchFrom
                node.balancePosition = n
                return false
            }
            i = after
        }
        node.balancePosition = i
        return true
    }

    /// Index to continue scanning from once the span is resolved (just past its closer), or
    /// `nil` if it is still open. Kinds: 1 = backtick run of length `run`, 2 = `$$`,
    /// 3 = single `$`, 4 = `\)`, 5 = `\]`.
    static func spanCloser(_ kind: Int, run: Int, in b: [UInt8], from: Int, contentStart: Int) -> Int? {
        let n = b.count
        var j = from
        while j < n {
            let c = b[j]
            if kind == 1 {
                if c == MarkdownChar.backtick {
                    let start = j
                    while j < n && b[j] == MarkdownChar.backtick { j += 1 }
                    if j - start == run { return j }
                    continue
                }
            } else if c == MarkdownChar.backslash {
                if j + 1 < n && ((kind == 4 && b[j + 1] == 0x29) || (kind == 5 && b[j + 1] == 0x5D)) { return j + 2 }
                j += 2
                continue
            } else if c == MarkdownChar.dollar {
                if kind == 2 && j + 1 < n && b[j + 1] == MarkdownChar.dollar { return j + 2 }
                if kind == 3 {
                    // Same rule as the inline parser: the first `$` closes or cancels the span
                    // (a cancelled opener is literal; scanning resumes right after it).
                    let valid = !MarkdownChar.isWhitespace(b[j - 1]) && !(j + 1 < n && MarkdownChar.isDigit(b[j + 1]))
                    return valid ? j + 1 : contentStart
                }
            }
            j += 1
        }
        return nil
    }
}
