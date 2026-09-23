import Foundation

// MARK: - Block AST

indirect enum MarkdownBlock: Equatable, Sendable {
    /// ATX (`# Title`) and setext (`Title\n===`) headings.
    case heading(level: Int, content: [MarkdownInline])
    /// A paragraph. Very long paragraphs are split into several consecutive
    /// `.paragraph` blocks (see `MarkdownParser.paragraphChunkLimit`).
    case paragraph([MarkdownInline])
    /// Fenced or indented code. `isClosed == false` means the fence is still open at
    /// the end of the input (streaming), or the block is an unterminated display-math
    /// block reported as `language: "latex"` (see `MarkdownParser` docs).
    case code(language: String?, code: String, isClosed: Bool)
    /// Display math. For `$$`/`\[` blocks this is the inner LaTeX (trimmed); for
    /// `\begin{env}…\end{env}` blocks the environment itself is kept.
    case math(String)
    case quote([MarkdownBlock])
    /// GitHub alert (`> [!NOTE]`); `kind` is lowercased (note, tip, important, warning, caution).
    case callout(kind: String, title: String?, content: [MarkdownBlock])
    case list(MarkdownList)
    case table(MarkdownTable)
    case thematicBreak
    /// Raw HTML block, verbatim (without the trailing newline).
    case html(String)
    case footnoteDefinition(label: String, content: [MarkdownBlock])
}

struct MarkdownList: Equatable, Sendable {
    var ordered: Bool
    var start: Int
    var isTight: Bool
    var items: [MarkdownListItem]

    init(ordered: Bool, start: Int = 1, isTight: Bool = true, items: [MarkdownListItem]) {
        self.ordered = ordered
        self.start = start
        self.isTight = isTight
        self.items = items
    }
}

struct MarkdownListItem: Equatable, Sendable {
    /// `nil` = not a task item, `true` = `[x]`, `false` = `[ ]`.
    var task: Bool?
    var content: [MarkdownBlock]

    init(task: Bool? = nil, content: [MarkdownBlock]) {
        self.task = task
        self.content = content
    }
}

enum MarkdownTableAlignment: Equatable, Sendable {
    case none, left, center, right
}

struct MarkdownTable: Equatable, Sendable {
    var alignments: [MarkdownTableAlignment]
    var header: [[MarkdownInline]]
    /// Every row has exactly `header.count` cells (padded with empty cells or truncated).
    var rows: [[[MarkdownInline]]]
}

// MARK: - Inline AST

indirect enum MarkdownInline: Equatable, Sendable {
    case text(String)
    case emphasis([MarkdownInline])
    case strong([MarkdownInline])
    case strikethrough([MarkdownInline])
    case code(String)
    /// Inline math: `$…$` or `\(…\)`. Raw LaTeX, no escape processing.
    case math(String)
    /// Display math occurring inside a paragraph: `$$…$$` or `\[…\]`.
    case displayMath(String)
    case link(destination: String, title: String?, content: [MarkdownInline])
    case image(source: String, title: String?, alt: String)
    case footnoteReference(String)
    /// Inline raw HTML other than `<br>` (which becomes `.lineBreak`).
    case html(String)
    case softBreak
    case lineBreak
}

// MARK: - Plain text

extension MarkdownInline {
    /// Flattens inlines to plain text for copy / accessibility: math becomes `$latex$`
    /// (`$$latex$$` for display math), links their text, images their alt text,
    /// soft breaks a space and hard breaks a newline.
    static func plainText(_ inlines: [MarkdownInline]) -> String {
        var out = ""
        appendPlainText(inlines, to: &out)
        return out
    }

    static func appendPlainText(_ inlines: [MarkdownInline], to out: inout String) {
        for inline in inlines {
            switch inline {
            case .text(let s), .code(let s), .html(let s):
                out += s
            case .emphasis(let c), .strong(let c), .strikethrough(let c):
                appendPlainText(c, to: &out)
            case .link(_, _, let c):
                appendPlainText(c, to: &out)
            case .math(let s):
                out += "$" + s + "$"
            case .displayMath(let s):
                out += "$$" + s + "$$"
            case .image(_, _, let alt):
                out += alt
            case .footnoteReference(let label):
                out += "[^" + label + "]"
            case .softBreak:
                out += " "
            case .lineBreak:
                out += "\n"
            }
        }
    }
}

extension MarkdownBlock {
    /// Plain-text rendering of whole blocks (blocks separated by blank lines).
    static func plainText(_ blocks: [MarkdownBlock]) -> String {
        var parts: [String] = []
        for block in blocks {
            switch block {
            case .heading(_, let content), .paragraph(let content):
                parts.append(MarkdownInline.plainText(content))
            case .code(_, let code, _):
                parts.append(code)
            case .math(let latex):
                parts.append("$$" + latex + "$$")
            case .quote(let children):
                parts.append(plainText(children))
            case .callout(_, let title, let children):
                let body = plainText(children)
                if let title { parts.append(body.isEmpty ? title : title + "\n" + body) } else { parts.append(body) }
            case .list(let list):
                var lines: [String] = []
                for (i, item) in list.items.enumerated() {
                    let marker = list.ordered ? "\(list.start + i). " : "- "
                    let box: String
                    switch item.task {
                    case .some(true): box = "[x] "
                    case .some(false): box = "[ ] "
                    case .none: box = ""
                    }
                    lines.append(marker + box + plainText(item.content))
                }
                parts.append(lines.joined(separator: "\n"))
            case .table(let table):
                var lines = [table.header.map { MarkdownInline.plainText($0) }.joined(separator: "\t")]
                for row in table.rows { lines.append(row.map { MarkdownInline.plainText($0) }.joined(separator: "\t")) }
                parts.append(lines.joined(separator: "\n"))
            case .thematicBreak:
                parts.append("---")
            case .html(let raw):
                parts.append(raw)
            case .footnoteDefinition(let label, let children):
                parts.append("[^" + label + "]: " + plainText(children))
            }
        }
        return parts.joined(separator: "\n\n")
    }
}
