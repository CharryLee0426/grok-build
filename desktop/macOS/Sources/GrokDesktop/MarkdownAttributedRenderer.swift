import AppKit

/// Renders Markdown blocks into TextKit 1 attributed text: tables become `NSTextTable`s,
/// code blocks and quotes are `NSTextBlock`s, and math is typeset into attachments.
/// Used where text must stay in one scrolling text view, such as streamed reasoning.
///
/// Each top-level block renders independently, and every block after the first begins with
/// the newline that ends the previous one, so a streaming update can replace just the tail.
struct MarkdownAttributedRenderer {
    var fontSize: CGFloat = 14
    var color: NSColor = .secondaryLabelColor
    /// The appearance math images are drawn for; text colours stay dynamic.
    var dark = false

    static let latexAttribute = NSAttributedString.Key("GrokMarkdownLaTeX")

    func render(_ block: MarkdownBlock, isFirst: Bool) -> NSAttributedString {
        let output = NSMutableAttributedString()
        if !isFirst { output.append(NSAttributedString(string: "\n", attributes: baseAttributes(Context()))) }
        append(block, context: Context(), to: output)
        return output
    }

    func render(_ blocks: [MarkdownBlock]) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() { output.append(render(block, isFirst: index == 0)) }
        return output
    }

    // MARK: Context

    private struct Context {
        var indent: CGFloat = 0
        var textBlocks: [NSTextBlock] = []
        var quoted = false
        var tight = false
    }

    private var lineSpacing: CGFloat { (fontSize * 0.22).rounded() }
    private var spacing: CGFloat { (fontSize * 0.6).rounded() }

    private func paragraphStyle(_ context: Context, firstIndent: CGFloat? = nil, headIndent: CGFloat? = nil,
                                alignment: NSTextAlignment = .natural, spacingAfter: CGFloat? = nil, spacingBefore: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.firstLineHeadIndent = firstIndent ?? context.indent
        style.headIndent = headIndent ?? context.indent
        style.paragraphSpacing = spacingAfter ?? (context.tight ? fontSize * 0.2 : spacing)
        style.paragraphSpacingBefore = spacingBefore
        style.alignment = alignment
        style.textBlocks = context.textBlocks
        if let headIndent { style.tabStops = [NSTextTab(textAlignment: .left, location: headIndent)] }
        return style
    }

    private func baseAttributes(_ context: Context, font: NSFont? = nil) -> [NSAttributedString.Key: Any] {
        [.font: font ?? NSFont.systemFont(ofSize: fontSize), .foregroundColor: context.quoted ? NSColor.tertiaryLabelColor : color,
         .paragraphStyle: paragraphStyle(context)]
    }

    // MARK: Blocks

    private func append(_ block: MarkdownBlock, context: Context, to output: NSMutableAttributedString) {
        switch block {
        case .heading(let level, let content):
            let size = (fontSize * [1.35, 1.2, 1.1, 1.0, 1.0, 0.95][min(max(level, 1), 6) - 1]).rounded()
            let text = inlines(content, context: context, font: .systemFont(ofSize: size, weight: .semibold))
            text.addAttribute(.paragraphStyle, value: paragraphStyle(context, spacingAfter: spacing * 0.6, spacingBefore: spacing * 0.5), range: NSRange(location: 0, length: text.length))
            output.append(text)
        case .paragraph(let content):
            output.append(inlines(content, context: context))
        case .code(let language, let code, _):
            appendCode(code, language: language, context: context, to: output)
        case .math(let latex):
            appendDisplayMath(latex, context: context, to: output)
        case .quote(let blocks):
            var inner = boxed(quoteBlock(color: .separatorColor), in: context)
            inner.quoted = true
            appendBlocks(blocks, context: inner, to: output)
        case .callout(let kind, let title, let blocks):
            let inner = boxed(quoteBlock(color: Self.calloutColor(kind)), in: context)
            let label = title ?? kind.capitalized
            output.append(NSAttributedString(string: label, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize * 0.92, weight: .semibold), .foregroundColor: Self.calloutColor(kind),
                .paragraphStyle: paragraphStyle(inner, spacingAfter: fontSize * 0.25)
            ]))
            if !blocks.isEmpty { output.append(newline(inner)); appendBlocks(blocks, context: inner, to: output) }
        case .list(let list):
            appendList(list, context: context, to: output)
        case .table(let table):
            appendTable(table, context: context, to: output)
        case .thematicBreak:
            let rule = NSTextBlock()
            rule.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxY)
            rule.setBorderColor(.separatorColor, for: .maxY)
            let inner = boxed(rule, in: context)
            output.append(NSAttributedString(string: "\u{00A0}", attributes: [.font: NSFont.systemFont(ofSize: 4), .paragraphStyle: paragraphStyle(inner)]))
        case .html(let html):
            appendCode(html, language: "html", context: context, to: output)
        case .footnoteDefinition(let label, let blocks):
            output.append(NSAttributedString(string: "\(label). ", attributes: baseAttributes(context, font: .systemFont(ofSize: fontSize * 0.85, weight: .medium))))
            let smaller = MarkdownAttributedRenderer(fontSize: fontSize * 0.85, color: color, dark: dark)
            for (index, child) in blocks.enumerated() {
                if index > 0 { output.append(newline(context)) }
                smaller.append(child, context: context, to: output)
            }
        }
    }

    private func appendBlocks(_ blocks: [MarkdownBlock], context: Context, to output: NSMutableAttributedString) {
        for (index, block) in blocks.enumerated() {
            if index > 0 { output.append(newline(context)) }
            append(block, context: context, to: output)
        }
    }

    private func newline(_ context: Context) -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: baseAttributes(context))
    }

    private func quoteBlock(color: NSColor) -> NSTextBlock {
        let block = NSTextBlock()
        block.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
        block.setBorderColor(color, for: .minX)
        block.setWidth(10, type: .absoluteValueType, for: .padding, edge: .minX)
        return block
    }

    /// Places a decorated block in the current context. A text block without an explicit
    /// width collapses and draws nothing, and its margin does not inset its background, so
    /// indentation (inside list items) comes from an undecorated outer block instead.
    private func boxed(_ block: NSTextBlock, in context: Context) -> Context {
        var inner = context
        if context.indent > 0 {
            let indent = NSTextBlock()
            indent.setValue(100, type: .percentageValueType, for: .width)
            indent.setWidth(context.indent, type: .absoluteValueType, for: .padding, edge: .minX)
            inner.textBlocks.append(indent)
        }
        block.setValue(100, type: .percentageValueType, for: .width)
        inner.textBlocks.append(block)
        inner.indent = 0
        return inner
    }

    private static func calloutColor(_ kind: String) -> NSColor {
        switch kind {
        case "tip": return Theme.greenNS
        case "important": return .systemPurple
        case "warning": return .systemOrange
        case "caution": return .systemRed
        default: return .systemBlue
        }
    }

    private func appendCode(_ code: String, language: String?, context: Context, to output: NSMutableAttributedString) {
        let box = NSTextBlock()
        box.backgroundColor = Theme.codeBackgroundNS
        box.setWidth(8, type: .absoluteValueType, for: .padding)
        box.setWidth(2, type: .absoluteValueType, for: .margin, edge: .minY)
        let inner = boxed(box, in: context)
        let font = NSFont.monospacedSystemFont(ofSize: (fontSize * 0.9).rounded(), weight: .regular)
        let resolved = language.flatMap(SyntaxHighlighter.language(for:))
        let text = NSMutableAttributedString(attributedString: SyntaxHighlighter.attributedString(code.isEmpty ? " " : code, language: resolved, font: font))
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.textBlocks = inner.textBlocks
        style.paragraphSpacing = 0
        let whole = NSRange(location: 0, length: text.length)
        text.addAttribute(.paragraphStyle, value: style, range: whole)
        text.enumerateAttribute(.foregroundColor, in: whole) { value, range, _ in
            if value == nil { text.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range) }
        }
        output.append(text)
        // Spacing after the box belongs to its last paragraph.
        let last = (text.string as NSString).paragraphRange(for: NSRange(location: max(0, text.length - 1), length: 0))
        let closing = style.mutableCopy() as! NSMutableParagraphStyle
        closing.paragraphSpacing = spacing
        output.addAttribute(.paragraphStyle, value: closing, range: NSRange(location: output.length - text.length + last.location, length: last.length))
    }

    private func appendDisplayMath(_ latex: String, context: Context, to output: NSMutableAttributedString) {
        guard let attachment = mathAttachment(latex, display: true) else {
            appendCode(latex, language: "latex", context: context, to: output)
            return
        }
        let text = NSMutableAttributedString(attachment: attachment)
        text.addAttributes([.paragraphStyle: paragraphStyle(context, alignment: .center), Self.latexAttribute: "$$\(latex)$$"],
                           range: NSRange(location: 0, length: text.length))
        output.append(text)
    }

    private func mathAttachment(_ latex: String, display: Bool, size: CGFloat? = nil) -> NSTextAttachment? {
        let resolved = MarkdownColors.resolved(color, dark: dark)
        guard let math = MathRenderer.render(latex, fontSize: (size ?? fontSize) * (display ? 1.1 : 1.05), color: resolved, display: display) else { return nil }
        let attachment = NSTextAttachment()
        attachment.image = math.image
        attachment.bounds = CGRect(x: 0, y: -math.descent, width: math.width, height: math.height)
        return attachment
    }

    private func appendList(_ list: MarkdownList, context: Context, to output: NSMutableAttributedString) {
        let markerWidth = list.ordered ? fontSize * (list.start + list.items.count > 9 ? 1.9 : 1.5) : fontSize * 1.2
        let depth = Int(context.indent / (fontSize * 1.5))
        for (index, item) in list.items.enumerated() {
            if index > 0 { output.append(newline(context)) }
            var inner = context
            inner.indent = context.indent + markerWidth
            inner.tight = list.isTight
            let marker: String
            if let done = item.task { marker = done ? "☑\t" : "☐\t" }
            else if list.ordered { marker = "\(list.start + index).\t" }
            else { marker = ["•", "◦", "▪"][depth % 3] + "\t" }
            let markerStyle = paragraphStyle(inner, firstIndent: context.indent, headIndent: inner.indent)
            var first = true
            for (blockIndex, block) in item.content.enumerated() {
                if blockIndex > 0 { output.append(newline(inner)) }
                let piece = NSMutableAttributedString()
                append(block, context: inner, to: piece)
                if first, case .paragraph = block {
                    // The marker hangs in the indent of the item's first paragraph.
                    let prefix = NSAttributedString(string: marker, attributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.tertiaryLabelColor, .paragraphStyle: markerStyle])
                    piece.insert(prefix, at: 0)
                    let firstParagraph = (piece.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
                    piece.addAttribute(.paragraphStyle, value: markerStyle, range: firstParagraph)
                } else if first {
                    output.append(NSAttributedString(string: marker.trimmingCharacters(in: .whitespaces) + "\n", attributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.tertiaryLabelColor, .paragraphStyle: markerStyle]))
                }
                first = false
                output.append(piece)
            }
            if item.content.isEmpty {
                output.append(NSAttributedString(string: marker, attributes: [.font: NSFont.systemFont(ofSize: fontSize), .paragraphStyle: markerStyle]))
            }
        }
    }

    private func appendTable(_ table: MarkdownTable, context: Context, to output: NSMutableAttributedString) {
        let columns = max(1, table.header.count)
        let textTable = NSTextTable()
        textTable.numberOfColumns = columns
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm
        textTable.collapsesBorders = true
        textTable.hidesEmptyCells = false
        textTable.setWidth(4, type: .absoluteValueType, for: .margin, edge: .minY)
        var outer = context.textBlocks
        if context.indent > 0 {
            let indent = NSTextBlock()
            indent.setValue(100, type: .percentageValueType, for: .width)
            indent.setWidth(context.indent, type: .absoluteValueType, for: .padding, edge: .minX)
            outer.append(indent)
        }
        let rows = [table.header] + table.rows
        for (rowIndex, row) in rows.enumerated() {
            for column in 0..<columns {
                let cell = NSTextTableBlock(table: textTable, startingRow: rowIndex, rowSpan: 1, startingColumn: column, columnSpan: 1)
                cell.setWidth(0.5, type: .absoluteValueType, for: .border)
                cell.setBorderColor(.separatorColor)
                cell.setWidth(6, type: .absoluteValueType, for: .padding)
                if rowIndex == 0 { cell.backgroundColor = Theme.tableHeaderNS }
                var inner = context
                inner.indent = 0
                inner.textBlocks = outer + [cell]
                let alignment: NSTextAlignment = {
                    switch column < table.alignments.count ? table.alignments[column] : .none {
                    case .center: return .center
                    case .right: return .right
                    default: return .natural
                    }
                }()
                let content = column < row.count ? row[column] : []
                let text = inlines(content.isEmpty ? [.text(" ")] : content, context: inner,
                                   font: rowIndex == 0 ? .systemFont(ofSize: fontSize * 0.92, weight: .semibold) : .systemFont(ofSize: fontSize * 0.92))
                let style = paragraphStyle(inner, firstIndent: 0, alignment: alignment, spacingAfter: 0)
                text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
                if rowIndex > 0 || column > 0 { output.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style])) }
                output.append(text)
            }
        }
        // A table's own bottom margin is not honoured, so a short empty paragraph separates it from what follows.
        output.append(NSAttributedString(string: "\n\u{200B}", attributes: [.font: NSFont.systemFont(ofSize: 2), .paragraphStyle: paragraphStyle(context, spacingAfter: spacing * 0.5)]))
    }

    // MARK: Inlines

    private struct Traits {
        var bold = false, italic = false, code = false, strike = false, superscript = false
        var link: URL?
    }

    private func inlines(_ content: [MarkdownInline], context: Context, font base: NSFont? = nil) -> NSMutableAttributedString {
        let output = NSMutableAttributedString()
        let baseFont = base ?? .systemFont(ofSize: fontSize)
        let attributes = baseAttributes(context, font: baseFont)
        func font(_ traits: Traits) -> NSFont {
            if traits.code { return .monospacedSystemFont(ofSize: (baseFont.pointSize * 0.9).rounded(), weight: .regular) }
            var result = traits.superscript ? NSFont.systemFont(ofSize: baseFont.pointSize * 0.72) : baseFont
            if traits.bold { result = NSFontManager.shared.convert(result, toHaveTrait: .boldFontMask) }
            if traits.italic { result = NSFontManager.shared.convert(result, toHaveTrait: .italicFontMask) }
            return result
        }
        func add(_ text: String, _ traits: Traits) {
            var run = attributes
            run[.font] = font(traits)
            if traits.code { run[.backgroundColor] = Theme.inlineCodeNS }
            if traits.strike { run[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if traits.superscript { run[.baselineOffset] = baseFont.pointSize * 0.35 }
            if let link = traits.link { run[.link] = link }
            output.append(NSAttributedString(string: text, attributes: run))
        }
        func visit(_ nodes: [MarkdownInline], _ traits: Traits) {
            for node in nodes {
                switch node {
                case .text(let text): add(text, traits)
                case .emphasis(let children): var next = traits; next.italic = true; visit(children, next)
                case .strong(let children): var next = traits; next.bold = true; visit(children, next)
                case .strikethrough(let children): var next = traits; next.strike = true; visit(children, next)
                case .code(let code): var next = traits; next.code = true; add(code, next)
                case .math(let latex), .displayMath(let latex):
                    if let attachment = mathAttachment(latex, display: false, size: baseFont.pointSize) {
                        let piece = NSMutableAttributedString(attachment: attachment)
                        piece.addAttributes(attributes, range: NSRange(location: 0, length: piece.length))
                        piece.addAttribute(Self.latexAttribute, value: "$\(latex)$", range: NSRange(location: 0, length: piece.length))
                        output.append(piece)
                    } else {
                        var next = traits; next.code = true; add("$\(latex)$", next)
                    }
                case .link(let destination, _, let children):
                    var next = traits; next.link = MarkdownInlineBuilder.url(destination)
                    if children.isEmpty { add(destination, next) } else { visit(children, next) }
                case .image(let source, _, let alt):
                    var next = traits; next.link = MarkdownInlineBuilder.url(source)
                    add("🖼 " + (alt.isEmpty ? source : alt), next)
                case .footnoteReference(let label): var next = traits; next.superscript = true; add("[\(label)]", next)
                case .html(let html): add(html, traits)
                case .softBreak, .lineBreak: add("\u{2028}", traits)
                }
            }
        }
        visit(content, Traits())
        if output.length == 0 { output.append(NSAttributedString(string: "", attributes: attributes)) }
        return output
    }
}
