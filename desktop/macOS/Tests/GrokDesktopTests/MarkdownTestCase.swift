import XCTest
@testable import GrokDesktop

/// Base class with terse AST builders for writing expected trees.
class MarkdownTestCase: XCTestCase {
    func t(_ s: String) -> MarkdownInline { .text(s) }
    func em(_ c: MarkdownInline...) -> MarkdownInline { .emphasis(c) }
    func strong(_ c: MarkdownInline...) -> MarkdownInline { .strong(c) }
    func del(_ c: MarkdownInline...) -> MarkdownInline { .strikethrough(c) }
    func code(_ s: String) -> MarkdownInline { .code(s) }
    func math(_ s: String) -> MarkdownInline { .math(s) }
    func dmath(_ s: String) -> MarkdownInline { .displayMath(s) }
    func link(_ dest: String, _ c: MarkdownInline..., title: String? = nil) -> MarkdownInline {
        .link(destination: dest, title: title, content: c)
    }
    func autolink(_ url: String, dest: String? = nil) -> MarkdownInline {
        .link(destination: dest ?? url, title: nil, content: [.text(url)])
    }
    var soft: MarkdownInline { .softBreak }
    var hard: MarkdownInline { .lineBreak }

    func p(_ c: MarkdownInline...) -> MarkdownBlock { .paragraph(c) }
    func h(_ level: Int, _ c: MarkdownInline...) -> MarkdownBlock { .heading(level: level, content: c) }
    func fence(_ language: String?, _ code: String, closed: Bool = true) -> MarkdownBlock {
        .code(language: language, code: code, isClosed: closed)
    }
    func ul(tight: Bool = true, _ items: [MarkdownBlock]...) -> MarkdownBlock {
        .list(MarkdownList(ordered: false, start: 1, isTight: tight, items: items.map { MarkdownListItem(task: nil, content: $0) }))
    }
    func ol(start: Int = 1, tight: Bool = true, _ items: [MarkdownBlock]...) -> MarkdownBlock {
        .list(MarkdownList(ordered: true, start: start, isTight: tight, items: items.map { MarkdownListItem(task: nil, content: $0) }))
    }
    func tasks(tight: Bool = true, _ items: (Bool?, [MarkdownBlock])...) -> MarkdownBlock {
        .list(MarkdownList(ordered: false, start: 1, isTight: tight, items: items.map { MarkdownListItem(task: $0.0, content: $0.1) }))
    }
    func quote(_ c: MarkdownBlock...) -> MarkdownBlock { .quote(c) }

    func assertParse(_ markdown: String, _ expected: [MarkdownBlock], file: StaticString = #filePath, line: UInt = #line) {
        let actual = MarkdownParser.parse(markdown)
        if actual != expected {
            XCTFail("\nINPUT:\n\(markdown)\nEXPECTED:\n\(dump(expected))\nACTUAL:\n\(dump(actual))", file: file, line: line)
        }
    }

    func assertInlines(_ markdown: String, _ expected: [MarkdownInline], file: StaticString = #filePath, line: UInt = #line) {
        let actual = MarkdownParser.parseInlines(markdown)
        if actual != expected {
            XCTFail("\nINPUT: \(markdown.debugDescription)\nEXPECTED: \(expected)\nACTUAL:   \(actual)", file: file, line: line)
        }
    }

    func dump(_ blocks: [MarkdownBlock]) -> String {
        blocks.map { "\($0)" }.joined(separator: "\n").replacingOccurrences(of: "MarkdownKit.", with: "")
    }
}
