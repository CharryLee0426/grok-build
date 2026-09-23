import Foundation

extension MarkdownBlockParser {
    enum StartResult { case none, container, leaf, consumed }

    /// First characters that may begin a block other than a paragraph.
    static let maybeSpecial: [Bool] = {
        var t = [Bool](repeating: false, count: 256)
        for c in "#`~*+_=<>-0123456789$\\|:[".utf8 { t[Int(c)] = true }
        return t
    }()

    static let mathEnvironments: Set<String> = [
        "equation", "equation*", "align", "align*", "aligned", "alignat", "alignat*", "alignedat",
        "gather", "gather*", "gathered", "multline", "multline*", "split", "cases", "dcases", "rcases",
        "matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix", "smallmatrix", "array",
        "flalign", "flalign*", "eqnarray", "eqnarray*", "displaymath", "math", "subequations", "CD",
    ]

    static let htmlBlockTags: Set<String> = [
        "address", "article", "aside", "base", "basefont", "blockquote", "body", "caption", "center",
        "col", "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption",
        "figure", "footer", "form", "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head",
        "header", "hr", "html", "iframe", "legend", "li", "link", "main", "menu", "menuitem", "nav",
        "noframes", "ol", "optgroup", "option", "p", "param", "search", "section", "summary", "table",
        "tbody", "td", "tfoot", "th", "thead", "title", "tr", "track", "ul",
    ]

    func tryBlockStarts(_ container: MarkdownBlockNode) -> StartResult {
        guard !blank else { return .none }
        let c = s[nextNonspace]
        // Nesting is capped so pathological input cannot build arbitrarily deep trees.
        let canNest = stack.count + 2 <= MarkdownBlockParser.maxContainerDepth
        if !indented {
            switch c {
            case 0x3E:
                if canNest { return blockQuoteStart() }
            case 0x23:
                if let r = atxHeadingStart() { return r }
            case 0x60, 0x7E:
                if let r = fencedCodeStart() { return r }
            case 0x24, 0x5C:
                if let r = mathBlockStart() { return r }
            case 0x3C:
                if let r = htmlBlockStart(container) { return r }
            default:
                break
            }
            if container.kind == .paragraph {
                if c == 0x7C || c == 0x3A || c == 0x2D, let r = tableStart(container) { return r }
                if c == 0x3D || c == 0x2D, let r = setextHeadingStart(container) { return r }
            }
            if c == 0x2A || c == 0x2D || c == 0x5F, let r = thematicBreakStart() { return r }
            if c == 0x5B, canNest, let r = footnoteDefinitionStart(container) { return r }
        }
        if canNest && (!indented || container.kind == .list), let r = listItemStart(container) { return r }
        if indented {
            let tip = stack[stack.count - 1]
            if tip.kind != .paragraph && tip.kind != .table {
                advanceOffset(4, columns: true)
                closeUnmatchedBlocks()
                addChild(.indentedCode)
                return .leaf
            }
        }
        return .none
    }

    func blockQuoteStart() -> StartResult {
        advanceNextNonspace()
        advanceOffset(1, columns: false)
        if let c = peek(offset), MarkdownChar.isSpaceOrTab(c) { advanceOffset(1, columns: true) }
        closeUnmatchedBlocks()
        addChild(.blockQuote)
        return .container
    }

    func atxHeadingStart() -> StartResult? {
        var j = nextNonspace
        while j < lineEnd && s[j] == 0x23 && j - nextNonspace < 7 { j += 1 }
        let level = j - nextNonspace
        guard level <= 6, j == lineEnd || MarkdownChar.isSpaceOrTab(s[j]) else { return nil }
        closeUnmatchedBlocks()
        let heading = addChild(.heading)
        heading.level = level
        var a = j
        while a < lineEnd && MarkdownChar.isSpaceOrTab(s[a]) { a += 1 }
        var b = lineEnd
        while b > a && MarkdownChar.isSpaceOrTab(s[b - 1]) { b -= 1 }
        var k = b
        while k > a && s[k - 1] == 0x23 { k -= 1 }
        if k == a {
            b = a
        } else if k < b && MarkdownChar.isSpaceOrTab(s[k - 1]) {
            b = k
            while b > a && MarkdownChar.isSpaceOrTab(s[b - 1]) { b -= 1 }
        }
        heading.content = Array(s[a..<b])
        finalize(heading, endLine: lineNumber)
        stack.removeLast()
        return .consumed
    }

    func fencedCodeStart() -> StartResult? {
        let ch = s[nextNonspace]
        var j = nextNonspace
        while j < lineEnd && s[j] == ch { j += 1 }
        let length = j - nextNonspace
        guard length >= 3 else { return nil }
        if ch == MarkdownChar.backtick && s[j..<lineEnd].contains(MarkdownChar.backtick) { return nil }
        closeUnmatchedBlocks()
        let fence = addChild(.fencedCode)
        fence.fenceChar = ch
        fence.fenceLength = length
        fence.fenceOffset = indent
        let r = MarkdownChar.trimmedRange(s, j, lineEnd)
        if !r.isEmpty {
            var e = r.lowerBound
            while e < r.upperBound && !MarkdownChar.isSpaceOrTab(s[e]) { e += 1 }
            let language = MarkdownChar.unescape(s[r.lowerBound..<e])
            fence.info = language.isEmpty ? nil : language
        }
        return .consumed
    }

    // MARK: Display math

    func mathBlockStart() -> StartResult? {
        let st = nextNonspace
        var end = lineEnd
        while end > st && MarkdownChar.isWhitespace(s[end - 1]) { end -= 1 }
        let style: MarkdownBlockNode.MathStyle
        var environment: [UInt8] = []
        var singleLine = false
        if s[st] == MarkdownChar.dollar {
            guard st + 1 < end, s[st + 1] == MarkdownChar.dollar else { return nil }
            style = .dollars
            if let inner = MarkdownBlockParser.firstIndex(of: "$$", in: s, from: st + 2, to: end) {
                // `$$ x $$` on one line is a block; `$$a$$ and $$b$$` is paragraph text.
                guard inner == end - 2 else { return nil }
                singleLine = true
            }
            // A `$$` line that closes an inline `$$` opened in the open (possibly lazy) paragraph.
            let tip = stack[stack.count - 1]
            if tip.kind == .paragraph && hasOpenDisplayDollar(tip) { return nil }
        } else {
            guard st + 1 < end else { return nil }
            if s[st + 1] == 0x5B {
                style = .brackets
                if let inner = MarkdownBlockParser.firstIndex(of: "\\]", in: s, from: st + 2, to: end) {
                    guard inner == end - 2 else { return nil }
                    singleLine = true
                } else if end != st + 2 {
                    return nil // `\[` opens a block only when alone on its line (`\[foo]` is text)
                }
            } else if MarkdownChar.matches(s, at: st, lowercase: "\\begin{") {
                var j = st + 7
                while j < end && s[j] != 0x7D { j += 1 }
                guard j < end else { return nil }
                environment = Array(s[(st + 7)..<j])
                guard MarkdownBlockParser.mathEnvironments.contains(MarkdownChar.string(environment)) else { return nil }
                style = .environment
                singleLine = MarkdownBlockParser.firstIndex(of: "\\end{" + MarkdownChar.string(environment) + "}", in: s, from: j, to: end) != nil
            } else {
                return nil
            }
        }
        closeUnmatchedBlocks()
        let math = addChild(.math)
        math.mathStyle = style
        math.environment = environment
        math.fenceOffset = indent
        advanceNextNonspace()
        if singleLine {
            addLine(to: math)
            math.closed = true
            finalize(math, endLine: lineNumber)
            stack.removeLast()
            return .consumed
        }
        return .leaf
    }

    func mathLineCloses(_ node: MarkdownBlockNode, from o: Int) -> Bool {
        var e = lineEnd
        while e > o && MarkdownChar.isWhitespace(s[e - 1]) { e -= 1 }
        switch node.mathStyle {
        case .dollars:
            return e - o >= 2 && s[e - 1] == MarkdownChar.dollar && s[e - 2] == MarkdownChar.dollar
        case .brackets:
            return e - o >= 2 && s[e - 1] == 0x5D && s[e - 2] == MarkdownChar.backslash
        case .environment:
            let closer = "\\end{" + MarkdownChar.string(node.environment) + "}"
            return MarkdownBlockParser.firstIndex(of: closer, in: s, from: o, to: e) != nil
        }
    }

    /// Whether the paragraph contains an odd number of (unescaped) `$$`.
    func hasOpenDisplayDollar(_ paragraph: MarkdownBlockNode) -> Bool {
        var count = 0
        for line in paragraph.lines {
            var j = line.start
            while j + 1 < line.end {
                if s[j] == MarkdownChar.backslash {
                    j += 2
                } else if s[j] == MarkdownChar.dollar && s[j + 1] == MarkdownChar.dollar {
                    count += 1
                    j += 2
                } else {
                    j += 1
                }
            }
        }
        return count % 2 == 1
    }

    static func firstIndex(of literal: String, in s: [UInt8], from: Int, to: Int) -> Int? {
        let lit = Array(literal.utf8)
        guard !lit.isEmpty, to - from >= lit.count else { return nil }
        var j = from
        while j <= to - lit.count {
            if s[j] == lit[0] {
                var k = 1
                while k < lit.count && s[j + k] == lit[k] { k += 1 }
                if k == lit.count { return j }
            }
            j += 1
        }
        return nil
    }

    // MARK: HTML blocks

    func htmlBlockStart(_ container: MarkdownBlockNode) -> StartResult? {
        let st = nextNonspace
        guard let type = htmlBlockType(at: st) else { return nil }
        if type == 7 {
            let tip = stack[stack.count - 1]
            let maybeLazy = !allClosed && !blank && tip.kind == .paragraph
            if container.kind == .paragraph || container.kind == .table || maybeLazy { return nil }
        }
        closeUnmatchedBlocks()
        let html = addChild(.html)
        html.htmlType = type
        return .leaf
    }

    func lowercasedTagName(at i: Int) -> (name: String, end: Int)? {
        var j = i
        guard j < lineEnd, MarkdownChar.isLetter(s[j]) else { return nil }
        var bytes: [UInt8] = []
        while j < lineEnd && (MarkdownChar.isAlphanumeric(s[j]) || s[j] == 0x2D) {
            bytes.append(MarkdownChar.lowercased(s[j]))
            j += 1
        }
        return (MarkdownChar.string(bytes), j)
    }

    func htmlBlockType(at st: Int) -> Int? {
        guard st + 1 < lineEnd else { return nil }
        let c1 = s[st + 1]
        if c1 == 0x21 { // <!
            if MarkdownChar.matches(s, at: st, lowercase: "<!--") { return 2 }
            if st + 8 < lineEnd && MarkdownChar.string(s[st..<(st + 9)]) == "<![CDATA[" { return 5 }
            if st + 2 < lineEnd && MarkdownChar.isLetter(s[st + 2]) { return 4 }
            return nil
        }
        if c1 == 0x3F { return 3 }
        let closing = c1 == 0x2F
        guard let (name, end) = lowercasedTagName(at: st + (closing ? 2 : 1)) else { return nil }
        let atBoundary = end == lineEnd || MarkdownChar.isSpaceOrTab(s[end]) || s[end] == 0x3E
        if !closing && atBoundary && (name == "script" || name == "pre" || name == "style" || name == "textarea") {
            return 1
        }
        if MarkdownBlockParser.htmlBlockTags.contains(name) {
            if atBoundary || (s[end] == 0x2F && end + 1 < lineEnd && s[end + 1] == 0x3E) { return 6 }
        }
        // Type 7: a complete tag alone on the line (`<br>` stays inline).
        if name == "br" || name == "script" || name == "pre" || name == "style" || name == "textarea" { return nil }
        let line = Array(s[st..<lineEnd])
        guard let tagEnd = closing ? MarkdownLinkScanner.closingTag(line, at: 0) : MarkdownLinkScanner.openTag(line, at: 0) else { return nil }
        for k in tagEnd..<line.count where !MarkdownChar.isWhitespace(line[k]) { return nil }
        return 7
    }

    func htmlBlockEnds(_ type: Int, from o: Int) -> Bool {
        let line = Array(s[o..<lineEnd].map { MarkdownChar.lowercased($0) })
        let n = line.count
        func has(_ literal: String) -> Bool { MarkdownBlockParser.firstIndex(of: literal, in: line, from: 0, to: n) != nil }
        switch type {
        case 1: return has("</script>") || has("</pre>") || has("</style>") || has("</textarea>")
        case 2: return has("-->")
        case 3: return has("?>")
        case 4: return has(">")
        case 5: return has("]]>")
        default: return false
        }
    }

    // MARK: Tables

    func tableStart(_ paragraph: MarkdownBlockNode) -> StartResult? {
        guard let alignments = parseDelimiterRow(from: nextNonspace, to: lineEnd),
              let headerLine = paragraph.lines.last else { return nil }
        let header = MarkdownBlockParser.splitTableRow(Array(paragraph.content[paragraph.lastLineStart...]))
        guard header.count == alignments.count else { return nil }
        closeUnmatchedBlocks()
        stack.removeLast()
        let parent = stack[stack.count - 1]
        if paragraph.lines.count > 1 {
            paragraph.lines.removeLast()
            paragraph.content.removeSubrange((paragraph.lastLineStart - 1)...)
            finalize(paragraph, endLine: lineNumber - 2)
        } else {
            parent.children.removeLast()
        }
        let table = MarkdownBlockNode(kind: .table, startLine: lineNumber - 1, startOffset: lineStart)
        table.alignments = alignments
        table.lines = [headerLine]
        parent.children.append(table)
        stack.append(table)
        return .consumed
    }

    func parseDelimiterRow(from: Int, to: Int) -> [MarkdownTableAlignment]? {
        var e = to
        while e > from && MarkdownChar.isWhitespace(s[e - 1]) { e -= 1 }
        var j = from
        var pipes = 0
        if j < e && s[j] == 0x7C {
            j += 1
            pipes += 1
        }
        var alignments: [MarkdownTableAlignment] = []
        while j < e {
            while j < e && MarkdownChar.isSpaceOrTab(s[j]) { j += 1 }
            if j >= e { break }
            var left = false, right = false
            if s[j] == 0x3A {
                left = true
                j += 1
            }
            var dashes = 0
            while j < e && s[j] == 0x2D {
                dashes += 1
                j += 1
            }
            guard dashes >= 1 else { return nil }
            if j < e && s[j] == 0x3A {
                right = true
                j += 1
            }
            while j < e && MarkdownChar.isSpaceOrTab(s[j]) { j += 1 }
            alignments.append(left && right ? .center : (left ? .left : (right ? .right : .none)))
            if j < e {
                guard s[j] == 0x7C else { return nil }
                pipes += 1
                j += 1
            }
        }
        guard !alignments.isEmpty, pipes >= 1 else { return nil }
        return alignments
    }

    /// Splits a table row into trimmed cell contents. `\|` becomes a literal pipe (even
    /// inside code spans, as in GFM); unescaped pipes always separate cells.
    static func splitTableRow(_ row: [UInt8]) -> [[UInt8]] {
        let r = MarkdownChar.trimmedRange(row, 0, row.count)
        var i = r.lowerBound
        let e = r.upperBound
        if i < e && row[i] == 0x7C { i += 1 }
        var cells: [[UInt8]] = []
        var cell: [UInt8] = []
        var endedWithSeparator = false
        while i < e {
            let c = row[i]
            if c == MarkdownChar.backslash && i + 1 < e {
                if row[i + 1] == 0x7C {
                    cell.append(0x7C)
                } else {
                    cell.append(c)
                    cell.append(row[i + 1])
                }
                i += 2
                endedWithSeparator = false
            } else if c == 0x7C {
                cells.append(cell)
                cell = []
                i += 1
                endedWithSeparator = true
            } else {
                cell.append(c)
                i += 1
                endedWithSeparator = false
            }
        }
        if !endedWithSeparator || cells.isEmpty { cells.append(cell) }
        return cells.map { c in
            let t = MarkdownChar.trimmedRange(c, 0, c.count)
            return t.count == c.count ? c : Array(c[t])
        }
    }

    // MARK: Setext headings, thematic breaks, footnotes

    func setextHeadingStart(_ paragraph: MarkdownBlockNode) -> StartResult? {
        let ch = s[nextNonspace]
        var j = nextNonspace
        while j < lineEnd && s[j] == ch { j += 1 }
        let count = j - nextNonspace
        while j < lineEnd && MarkdownChar.isSpaceOrTab(s[j]) { j += 1 }
        guard j == lineEnd else { return nil }
        // Streaming: a lone "-"/"--" at the very end of the input is probably the start of
        // a list item, not an underline; don't flash a heading.
        if ch == 0x2D && count < 3 && !lineTerminated { return nil }
        let (content, defs) = paragraphContent(paragraph)
        guard !MarkdownChar.trimmedRange(content, 0, content.count).isEmpty else { return nil }
        commit(defs, offset: paragraph.startOffset)
        stack.removeLast()
        let parent = stack[stack.count - 1]
        let heading = MarkdownBlockNode(kind: .heading, startLine: paragraph.startLine, startOffset: paragraph.startOffset)
        heading.level = ch == 0x3D ? 1 : 2
        heading.content = content
        heading.endLine = lineNumber
        parent.children[parent.children.count - 1] = heading
        return .consumed
    }

    func thematicBreakStart() -> StartResult? {
        guard isThematicBreak(from: nextNonspace) else { return nil }
        closeUnmatchedBlocks()
        let rule = addChild(.thematicBreak)
        finalize(rule, endLine: lineNumber)
        stack.removeLast()
        return .consumed
    }

    func isThematicBreak(from st: Int) -> Bool {
        let ch = s[st]
        guard ch == 0x2A || ch == 0x2D || ch == 0x5F else { return false }
        var count = 0
        var j = st
        while j < lineEnd {
            let c = s[j]
            if c == ch {
                count += 1
            } else if !MarkdownChar.isSpaceOrTab(c) {
                return false
            }
            j += 1
        }
        return count >= 3
    }

    func footnoteDefinitionStart(_ container: MarkdownBlockNode) -> StartResult? {
        let st = nextNonspace
        guard container.kind != .paragraph, st + 3 < lineEnd, s[st + 1] == 0x5E else { return nil }
        var j = st + 2
        while j < lineEnd {
            let c = s[j]
            if c == 0x5D || c == 0x5B || MarkdownChar.isWhitespace(c) { break }
            j += 1
        }
        guard j < lineEnd, s[j] == 0x5D, j > st + 2, j + 1 < lineEnd, s[j + 1] == 0x3A else { return nil }
        let label = MarkdownChar.string(s[(st + 2)..<j])
        closeUnmatchedBlocks()
        let footnote = addChild(.footnote)
        footnote.label = label
        let key = MarkdownInlineParser.footnoteKeyPrefix + MarkdownChar.normalizeLabel(s[(st + 2)..<j])
        commit([(key, MarkdownLinkDefinition(destination: "", title: nil))], offset: lineStart)
        advanceNextNonspace()
        advanceOffset(j + 2 - st, columns: false)
        return .container
    }

    // MARK: Lists

    func listItemStart(_ container: MarkdownBlockNode) -> StartResult? {
        guard indent < 4 else { return nil }
        let markerOffset = indent
        let st = nextNonspace
        let c = s[st]
        var ordered = false
        var marker = c
        var start = 1
        var markerLength = 1
        if c == 0x2D || c == 0x2B || c == 0x2A {
            // bullet
        } else if MarkdownChar.isDigit(c) {
            var j = st
            var value = 0
            while j < lineEnd && MarkdownChar.isDigit(s[j]) && j - st < 9 {
                value = value * 10 + Int(s[j] - 0x30)
                j += 1
            }
            guard j < lineEnd, s[j] == 0x2E || s[j] == 0x29 else { return nil }
            guard container.kind != .paragraph || value == 1 else { return nil }
            ordered = true
            marker = s[j]
            start = value
            markerLength = j - st + 1
        } else {
            return nil
        }
        let after = st + markerLength
        if after < lineEnd && !MarkdownChar.isSpaceOrTab(s[after]) { return nil }
        if container.kind == .paragraph {
            var k = after
            while k < lineEnd && MarkdownChar.isSpaceOrTab(s[k]) { k += 1 }
            if k == lineEnd { return nil }
        }
        advanceNextNonspace()
        advanceOffset(markerLength, columns: true)
        let spacesStartColumn = column
        let spacesStartOffset = offset
        repeat {
            advanceOffset(1, columns: true)
        } while column - spacesStartColumn < 5 && offset < lineEnd && MarkdownChar.isSpaceOrTab(s[offset])
        let blankItem = offset >= lineEnd
        let spacesAfterMarker = column - spacesStartColumn
        let padding: Int
        if spacesAfterMarker >= 5 || spacesAfterMarker < 1 || blankItem {
            padding = markerLength + 1
            column = spacesStartColumn
            offset = spacesStartOffset
            partiallyConsumedTab = false
            if let c = peek(offset), MarkdownChar.isSpaceOrTab(c) { advanceOffset(1, columns: true) }
        } else {
            padding = markerLength + spacesAfterMarker
        }
        closeUnmatchedBlocks()
        let tip = stack[stack.count - 1]
        if !(tip.kind == .list && tip.ordered == ordered && tip.marker == marker) {
            let list = addChild(.list)
            list.ordered = ordered
            list.marker = marker
            list.listStart = start
        }
        let item = addChild(.item)
        item.ordered = ordered
        item.marker = marker
        item.markerOffset = markerOffset
        item.padding = padding
        return .container
    }

    /// For the nesting deviation in `continueBlock(.item)`: does the line start with a list
    /// marker of a different type/character than `item`'s list?
    func startsDifferentListMarker(_ item: MarkdownBlockNode) -> Bool {
        let st = nextNonspace
        let c = s[st]
        if c == 0x2D || c == 0x2B || c == 0x2A {
            guard st + 1 >= lineEnd || MarkdownChar.isSpaceOrTab(s[st + 1]), !isThematicBreak(from: st) else { return false }
            return item.ordered || item.marker != c
        }
        guard MarkdownChar.isDigit(c) else { return false }
        var j = st
        while j < lineEnd && MarkdownChar.isDigit(s[j]) && j - st < 9 { j += 1 }
        guard j < lineEnd, s[j] == 0x2E || s[j] == 0x29, j + 1 >= lineEnd || MarkdownChar.isSpaceOrTab(s[j + 1]) else { return false }
        // Must be able to interrupt the item's paragraph (ordered lists must start at 1).
        guard j - st == 1 && s[st] == 0x31 else { return false }
        return !item.ordered || item.marker != s[j]
    }
}
