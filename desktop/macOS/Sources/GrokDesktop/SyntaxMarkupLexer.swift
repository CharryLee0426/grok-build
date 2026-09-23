import Foundation

extension SyntaxLexer {
    /// HTML / XML with embedded `<script>`/`<style>`, entities, comments and template tags.
    func lexMarkup(_ flavor: SyntaxMarkupFlavor) {
        var i = lo
        while i < hi {
            let c = s[i]
            if c == 60 { // <
                let n = at(i + 1)
                if n == 33 { // <!
                    if has(i, "<!--") {
                        let e = (find("-->", from: i + 4)).map { $0 + 3 } ?? hi
                        emit(i, e, .comment)
                        i = e
                        continue
                    }
                    if has(i, "<![CDATA[") {
                        emit(i, i + 9, .punctuation)
                        let close = find("]]>", from: i + 9) ?? hi
                        emit(i + 9, close, .string)
                        emit(close, close + 3, .punctuation)
                        i = Swift.min(close + 3, hi)
                        continue
                    }
                    let e = markupDeclarationEnd(i)
                    emit(i, i + 2, .punctuation)
                    let w = identEnd(i + 2)
                    emit(i + 2, w, .keyword)
                    lexTagAttributes(w, e, flavor: flavor)
                    i = e
                    continue
                }
                if n == 63 { // <? processing instruction / XML declaration
                    let close = find("?>", from: i + 2) ?? hi
                    emit(i, i + 2, .punctuation)
                    let w = markupNameEnd(i + 2)
                    emit(i + 2, w, .tag)
                    lexTagAttributes(w, close, flavor: flavor)
                    emit(close, close + 2, .punctuation)
                    i = Swift.min(close + 2, hi)
                    continue
                }
                if n == 37, flavor == .erb || flavor == .ejs || flavor == .eex { // <% ... %>
                    i = templateBlock(i, open: 2, close: "%>", flavor: flavor)
                    continue
                }
                if n == 47 || SyntaxChar.isLetter(n) {
                    i = lexTag(i, flavor: flavor)
                    continue
                }
                i += 1
                continue
            }
            if c == 38 { // &entity;
                let e = entityEnd(i)
                if e > i {
                    emit(i, e, .escape)
                    i = e
                    continue
                }
            }
            if c == 123 {
                if (flavor == .vue || flavor == .mustache) && at(i + 1) == 123 {
                    i = templateBlock(i, open: 2, close: "}}", flavor: flavor)
                    continue
                }
                if flavor == .mustache && (at(i + 1) == 37 || at(i + 1) == 35) {
                    i = at(i + 1) == 35 ? mustacheComment(i) : templateBlock(i, open: 2, close: "%}", flavor: flavor)
                    continue
                }
                if flavor == .svelte {
                    i = templateBlock(i, open: 1, close: "}", flavor: flavor)
                    continue
                }
            }
            i += 1
        }
    }

    func markupNameEnd(_ i: Int) -> Int {
        var j = i
        while j < hi && (SyntaxChar.isIdentPart(s[j]) || s[j] == 45 || s[j] == 58 || s[j] == 46) { j += 1 }
        return j
    }

    func markupDeclarationEnd(_ i: Int) -> Int {
        var j = i + 2
        var bracket = 0
        while j < hi {
            let c = s[j]
            if c == 91 { bracket += 1 } else if c == 93 { bracket -= 1 } else if c == 62 && bracket <= 0 { return j + 1 }
            j += 1
        }
        return hi
    }

    func entityEnd(_ i: Int) -> Int {
        var j = i + 1
        if at(j) == 35 { j += 1 }
        let start = j
        while j < hi && j < i + 12 && SyntaxChar.isAlnum(s[j]) { j += 1 }
        return (j > start && at(j) == 59) ? j + 1 : i
    }

    /// Lexes `<tag …>` or `</tag>` at `i`; handles raw-text elements (`script`, `style`). Returns the new index.
    func lexTag(_ i: Int, flavor: SyntaxMarkupFlavor) -> Int {
        var j = i + 1
        let closing = at(j) == 47
        if closing { j += 1 }
        emit(i, j, .punctuation)
        let ns = j
        j = markupNameEnd(j)
        let ne = j
        emit(ns, ne, flavor == .xml || !SyntaxChar.isUpper(at(ns)) ? .tag : .type)
        var typeValue: (Int, Int)?
        var langValue: (Int, Int)?
        var selfClosed = false
        while j < hi {
            j = skipSpace(j)
            guard j < hi else { break }
            let c = s[j]
            if c == 62 {
                emit(j, j + 1, .punctuation)
                j += 1
                break
            }
            if c == 47 && at(j + 1) == 62 {
                emit(j, j + 2, .punctuation)
                j += 2
                selfClosed = true
                break
            }
            if c == 60 && at(j + 1) == 37 && (flavor == .erb || flavor == .ejs || flavor == .eex) {
                j = templateBlock(j, open: 2, close: "%>", flavor: flavor)
                continue
            }
            if c == 60 { break } // malformed: let the next tag start here
            if c == 123 && (flavor == .svelte || flavor == .mustache) {
                if at(j + 1) == 37 {
                    j = templateBlock(j, open: 2, close: "%}", flavor: flavor)
                } else if at(j + 1) == 123 {
                    j = templateBlock(j, open: 2, close: "}}", flavor: flavor)
                } else {
                    j = templateBlock(j, open: 1, close: "}", flavor: flavor)
                }
                continue
            }
            // attribute name
            let an = j
            while j < hi {
                let a = s[j]
                if SyntaxChar.isSpace(a) || a == 61 || a == 62 || a == 34 || a == 39 || a == 60 || (a == 47 && at(j + 1) == 62) { break }
                j += 1
            }
            if j == an {
                j += 1
                continue
            }
            let ae = j
            emit(an, ae, .attribute)
            let eq = skipSpace(j)
            guard at(eq) == 61 else { continue }
            j = skipSpace(eq + 1)
            let q = at(j)
            let vs: Int, ve: Int
            if q == 34 || q == 39 {
                let e = quotedEnd(j, quote: q, escapes: false, multiline: true)
                vs = j + 1
                ve = e > vs && at(e - 1) == q ? e - 1 : e
                let script = flavor == .vue && (at(an) == 58 || at(an) == 64 || has(an, "v-"))
                if script && depth < SyntaxLexer.maxDepth {
                    emit(j, vs, .string)
                    sub(vs, ve).run(.code("javascript"))
                    emit(ve, e, .string)
                } else {
                    emit(j, e, .string)
                    var k = vs
                    while k < ve {
                        if s[k] == 38 {
                            let x = entityEnd(k)
                            if x > k { emit(k, x, .escape); k = x; continue }
                        }
                        k += 1
                    }
                }
                j = e
            } else if q == 123 && (flavor == .svelte || flavor == .vue) {
                j = templateBlock(j, open: 1, close: "}", flavor: flavor)
                continue
            } else {
                vs = j
                while j < hi && !SyntaxChar.isSpace(s[j]) && s[j] != 62 && !(s[j] == 47 && at(j + 1) == 62) { j += 1 }
                ve = j
                emit(vs, ve, .string)
            }
            if word(an, ae, is: "type", ci: true) { typeValue = (vs, ve) }
            if word(an, ae, is: "lang", ci: true) { langValue = (vs, ve) }
        }
        guard !closing, !selfClosed else { return j }
        let isScript = word(ns, ne, is: "script", ci: true)
        let isStyle = word(ns, ne, is: "style", ci: true)
        guard isScript || isStyle else { return j }
        let close = (isScript ? findCI("</script", from: j) : findCI("</style", from: j)) ?? hi
        guard depth < SyntaxLexer.maxDepth else { return close }
        let embedded = sub(j, close)
        if isStyle {
            let lang = langValue.map { string($0.0, $0.1).lowercased() } ?? ""
            embedded.run(.css(lang == "scss" ? .scss : lang == "less" ? .less : lang == "sass" ? .sass : .css))
        } else {
            let type = typeValue.map { string($0.0, $0.1).lowercased() } ?? ""
            let lang = langValue.map { string($0.0, $0.1).lowercased() } ?? ""
            if type.contains("json") {
                embedded.run(.json(.json))
            } else if type.contains("html") || type.contains("template") {
                embedded.run(.markup(flavor))
            } else if lang == "ts" || lang == "typescript" || lang == "tsx" || type.contains("typescript") {
                embedded.run(.code("typescript"))
            } else if type.isEmpty || type.contains("javascript") || type.contains("module") || type.contains("babel") || type.contains("jsx") {
                embedded.run(.code("javascript"))
            }
        }
        return close
    }

    /// Attributes in declarations and processing instructions (`<?xml version="1.0"?>`).
    func lexTagAttributes(_ a: Int, _ b: Int, flavor: SyntaxMarkupFlavor) {
        var j = a
        while j < b {
            let c = s[j]
            if c == 34 || c == 39 {
                let e = Swift.min(quotedEnd(j, quote: c, escapes: false, multiline: true), b)
                emit(j, e, .string)
                j = e
                continue
            }
            if SyntaxChar.isIdentStart(c) {
                let e = markupNameEnd(j)
                if at(skipBlanks(e)) == 61 { emit(j, e, .attribute) }
                j = e
                continue
            }
            j += 1
        }
    }

    func mustacheComment(_ i: Int) -> Int {
        let e = (find("#}", from: i + 2)).map { $0 + 2 } ?? hi
        emit(i, e, .comment)
        return e
    }

    /// `{{ … }}`, `{% … %}`, `<% … %>`, `{ … }` template regions; the inside is lexed as code.
    func templateBlock(_ i: Int, open: Int, close: StaticString, flavor: SyntaxMarkupFlavor) -> Int {
        var start = i + open
        // `<%#` comments in ERB/EJS, `{{!` in Handlebars.
        if (at(start) == 35 && open == 2 && at(i) == 60) || (at(start) == 33 && flavor == .mustache) {
            let e = (find(close, from: start)).map { $0 + close.utf8CodeUnitCount } ?? hi
            emit(i, e, .comment)
            return e
        }
        while start < hi && (s[start] == 61 || s[start] == 45 || s[start] == 126 || s[start] == 35 || s[start] == 47 || s[start] == 58 || s[start] == 64) {
            start += 1
        }
        let end: Int
        if open == 1 {
            let e = matchingClose(i, open: 123, close: 125)
            end = Swift.max(e >= hi && at(hi - 1) != 125 ? hi : e - 1, start)
        } else {
            end = find(close, from: start) ?? hi
        }
        var innerEnd = end
        while innerEnd > start && (s[innerEnd - 1] == 45 || s[innerEnd - 1] == 126) { innerEnd -= 1 }
        emit(i, start, .keyword)
        if depth < SyntaxLexer.maxDepth && start < innerEnd {
            let inner = sub(start, innerEnd)
            switch flavor {
            case .erb: inner.run(.code("ruby"))
            case .eex: inner.run(.code("elixir"))
            case .mustache: inner.run(.code("jinja"))
            default: inner.run(.code("javascript"))
            }
        }
        let closeEnd = Swift.min(end + (open == 1 ? 1 : close.utf8CodeUnitCount), hi)
        emit(innerEnd, closeEnd, .keyword)
        return closeEnd
    }

    /// PHP files: HTML outside `<?php … ?>`; plain PHP when no open tag is present.
    func lexPHPDocument() {
        guard let firstOpen = phpOpen(from: lo) else {
            var lexer = SyntaxCodeLexer(self, SyntaxSpecs.php)
            lexer.lexAll()
            return
        }
        var i = lo
        var open: Int? = firstOpen
        while i < hi {
            let o = open ?? hi
            if o > i && depth < SyntaxLexer.maxDepth { sub(i, o).lexMarkup(.html) }
            guard o < hi else { break }
            let tagEnd = has(o, "<?php") ? o + 5 : (has(o, "<?=") ? o + 3 : o + 2)
            emit(o, tagEnd, .attribute)
            var lexer = SyntaxCodeLexer(self, SyntaxSpecs.php)
            lexer.stopAtPHPClose = true
            var j = tagEnd
            lexer.run(&j, closer: 0, opener: 0, stopAtNewline: false)
            if j < hi {
                emit(j, j + 2, .attribute)
                i = j + 2
            } else {
                i = hi
            }
            open = phpOpen(from: i)
        }
    }

    func phpOpen(from i: Int) -> Int? {
        var j = i
        while j + 1 < hi {
            if s[j] == 60 && s[j + 1] == 63 {
                if has(j, "<?php") || has(j, "<?=") || SyntaxChar.isSpace(at(j + 2)) { return j }
            }
            j += 1
        }
        return nil
    }
}
