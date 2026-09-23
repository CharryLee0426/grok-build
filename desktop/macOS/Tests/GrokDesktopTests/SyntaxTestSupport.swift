import Foundation
import XCTest
@testable import GrokDesktop

enum SyntaxTestSupport {
    static func language(_ name: String, file: StaticString = #filePath, line: UInt = #line) -> SyntaxLanguage {
        guard let language = SyntaxHighlighter.language(for: name) else {
            XCTFail("unknown language \(name)", file: file, line: line)
            return SyntaxLanguage(id: name, displayName: name)
        }
        return language
    }

    static func tokens(_ code: String, _ lang: String) -> [SyntaxToken] {
        SyntaxHighlighter.tokens(code, language: language(lang))
    }

    /// Kind of the single token that covers the `occurrence`-th match of `needle` (nil when uncovered or split).
    /// Identifier-like needles only match whole words.
    static func kind(of needle: String, in code: String, _ lang: String, occurrence: Int = 1) -> SyntaxTokenKind? {
        let ns = code as NSString
        let wholeWord = needle.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" }
        func isWordUnit(_ i: Int) -> Bool {
            guard i >= 0, i < ns.length else { return false }
            let c = ns.character(at: i)
            return c == 95 || (c < 128 && (CharacterSet.alphanumerics.contains(Unicode.Scalar(c)!)))
        }
        var searchRange = NSRange(location: 0, length: ns.length)
        var found = NSRange(location: NSNotFound, length: 0)
        var remaining = occurrence
        while remaining > 0 {
            found = ns.range(of: needle, options: [], range: searchRange)
            guard found.location != NSNotFound else { return nil }
            searchRange = NSRange(location: found.location + 1, length: ns.length - found.location - 1)
            if wholeWord && (isWordUnit(found.location - 1) || isWordUnit(NSMaxRange(found))) { continue }
            remaining -= 1
        }
        for token in tokens(code, lang) where token.range.location <= found.location && NSMaxRange(token.range) >= NSMaxRange(found) {
            return token.kind
        }
        return nil
    }

    /// Human readable dump used when debugging a lexer.
    static func dump(_ code: String, _ lang: String) -> String {
        let ns = code as NSString
        return tokens(code, lang).map { "\($0.kind): \(ns.substring(with: $0.range).debugDescription)" }.joined(separator: "\n")
    }

    static func assertKind(_ needle: String, in code: String, _ lang: String, _ expected: SyntaxTokenKind?, occurrence: Int = 1, file: StaticString = #filePath, line: UInt = #line) {
        let actual = kind(of: needle, in: code, lang, occurrence: occurrence)
        XCTAssertEqual(actual, expected, "\(lang): `\(needle)` expected \(String(describing: expected)), got \(String(describing: actual))\n\(dump(code, lang))", file: file, line: line)
    }

    static func assertWellFormed(_ tokens: [SyntaxToken], length: Int, file: StaticString = #filePath, line: UInt = #line) {
        var last = 0
        for token in tokens {
            XCTAssertGreaterThanOrEqual(token.range.location, last, "overlapping or unsorted token", file: file, line: line)
            XCTAssertGreaterThan(token.range.length, 0, "empty token", file: file, line: line)
            XCTAssertLessThanOrEqual(NSMaxRange(token.range), length, "token past end", file: file, line: line)
            XCTAssertNotEqual(token.kind, .plain, file: file, line: line)
            last = NSMaxRange(token.range)
        }
    }
}
