import Foundation

/// Converts the parser's mutable block tree into `MarkdownBlock` values, running the
/// inline parser on paragraphs, headings and table cells.
struct MarkdownBlockConverter {
    let parser: MarkdownBlockParser
    let refs: [String: MarkdownLinkDefinition]

    static let calloutKinds: Set<String> = ["note", "tip", "important", "warning", "caution"]

    func convert(_ nodes: [MarkdownBlockNode]) -> [MarkdownBlock] {
        var out: [MarkdownBlock] = []
        out.reserveCapacity(nodes.count)
        for node in nodes {
            if let block = convert(node) { out.append(block) }
        }
        return out
    }

    func inlines(_ bytes: [UInt8]) -> [MarkdownInline] {
        let r = MarkdownChar.trimmedRange(bytes, 0, bytes.count)
        if r.isEmpty { return [] }
        return MarkdownInlineParser.parse(r.count == bytes.count ? bytes : Array(bytes[r]), refs: refs)
    }

    func paragraph(_ bytes: [UInt8]) -> MarkdownBlock? {
        let content = inlines(bytes)
        return content.isEmpty ? nil : .paragraph(content)
    }

    func convert(_ node: MarkdownBlockNode) -> MarkdownBlock? {
        switch node.kind {
        case .paragraph:
            return paragraph(node.content)
        case .heading:
            return .heading(level: node.level, content: inlines(node.content))
        case .fencedCode:
            return .code(language: node.info, code: MarkdownChar.string(parser.joinedLines(node.lines)), isClosed: node.closed)
        case .indentedCode:
            return .code(language: nil, code: MarkdownChar.string(parser.joinedLines(node.lines)), isClosed: true)
        case .html:
            var raw = parser.joinedLines(node.lines)
            while let last = raw.last, MarkdownChar.isWhitespace(last) { raw.removeLast() }
            return .html(MarkdownChar.string(raw))
        case .math:
            let raw = parser.joinedLines(node.lines)
            guard node.closed else {
                // Unterminated display math (streaming, or never closed): show the source.
                return .code(language: "latex", code: MarkdownChar.string(raw), isClosed: false)
            }
            return .math(latex(of: node, raw: raw))
        case .thematicBreak:
            return .thematicBreak
        case .blockQuote:
            return quote(node)
        case .list:
            return .list(list(node))
        case .table:
            return .table(table(node))
        case .footnote:
            return .footnoteDefinition(label: node.label, content: convert(node.children))
        case .item:
            return .list(MarkdownList(ordered: node.ordered, start: 1, isTight: true, items: [item(node)]))
        case .document:
            return nil
        }
    }

    func latex(of node: MarkdownBlockNode, raw: [UInt8]) -> String {
        var r = MarkdownChar.trimmedRange(raw, 0, raw.count)
        switch node.mathStyle {
        case .dollars, .brackets:
            // Strip the two-byte opener (`$$` / `\[`) and closer (`$$` / `\]`).
            if r.count >= 2 { r = (r.lowerBound + 2)..<r.upperBound }
            if r.count >= 2 { r = r.lowerBound..<(r.upperBound - 2) }
            r = MarkdownChar.trimmedRange(raw, r.lowerBound, r.upperBound)
        case .environment:
            break
        }
        return MarkdownChar.string(raw[r])
    }

    func quote(_ node: MarkdownBlockNode) -> MarkdownBlock {
        if let first = node.children.first, first.kind == .paragraph, let callout = calloutHeader(first.content) {
            var content: [MarkdownBlock] = []
            if let rest = callout.rest, let p = paragraph(rest) { content.append(p) }
            content.append(contentsOf: convert(Array(node.children.dropFirst())))
            return .callout(kind: callout.kind, title: callout.title, content: content)
        }
        return .quote(convert(node.children))
    }

    /// Parses a GitHub alert marker (`[!NOTE] optional title`) at the start of a paragraph.
    func calloutHeader(_ c: [UInt8]) -> (kind: String, title: String?, rest: [UInt8]?)? {
        var i = 0
        while i < c.count && MarkdownChar.isWhitespace(c[i]) { i += 1 }
        guard i + 3 < c.count, c[i] == 0x5B, c[i + 1] == 0x21 else { return nil }
        var j = i + 2
        while j < c.count && MarkdownChar.isLetter(c[j]) { j += 1 }
        guard j < c.count, c[j] == 0x5D, j > i + 2 else { return nil }
        let kind = MarkdownChar.string(c[(i + 2)..<j]).lowercased()
        guard MarkdownBlockConverter.calloutKinds.contains(kind) else { return nil }
        var lineEnd = j + 1
        while lineEnd < c.count && c[lineEnd] != MarkdownChar.newline { lineEnd += 1 }
        let titleRange = MarkdownChar.trimmedRange(c, j + 1, lineEnd)
        let title = titleRange.isEmpty ? nil : MarkdownInline.plainText(inlines(Array(c[titleRange])))
        let rest = lineEnd < c.count ? Array(c[(lineEnd + 1)...]) : nil
        return (kind, title, rest)
    }

    func list(_ node: MarkdownBlockNode) -> MarkdownList {
        MarkdownList(ordered: node.ordered, start: node.listStart, isTight: node.tight, items: node.children.map(item))
    }

    func item(_ node: MarkdownBlockNode) -> MarkdownListItem {
        guard let first = node.children.first, first.kind == .paragraph else {
            return MarkdownListItem(task: nil, content: convert(node.children))
        }
        let c = first.content
        // GFM task list item: `[ ]`, `[x]` or `[X]` followed by whitespace (or nothing).
        if c.count >= 3, c[0] == 0x5B, c[2] == 0x5D, c[1] == 0x20 || c[1] == 0x78 || c[1] == 0x58,
           c.count == 3 || MarkdownChar.isWhitespace(c[3]) {
            var content: [MarkdownBlock] = []
            if let p = paragraph(Array(c[3...])) { content.append(p) }
            content.append(contentsOf: convert(Array(node.children.dropFirst())))
            return MarkdownListItem(task: c[1] != 0x20, content: content)
        }
        return MarkdownListItem(task: nil, content: convert(node.children))
    }

    func table(_ node: MarkdownBlockNode) -> MarkdownTable {
        let columns = node.alignments.count
        func row(_ line: MarkdownLineSlice) -> [[MarkdownInline]] {
            var cells = MarkdownBlockParser.splitTableRow(parser.joinedLines([line]))
            if cells.count > columns { cells.removeLast(cells.count - columns) }
            var out = cells.map { inlines($0) }
            while out.count < columns { out.append([]) }
            return out
        }
        let header = node.lines.first.map(row) ?? []
        let rows = node.lines.dropFirst().map(row)
        return MarkdownTable(alignments: node.alignments, header: header, rows: rows)
    }
}
