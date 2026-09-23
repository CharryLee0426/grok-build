import AppKit
import SwiftUI

/// Semantic class of a highlighted range. Colours come from `SyntaxTheme`.
enum SyntaxTokenKind: Int, CaseIterable {
    case keyword, type, function, string, number, comment, attribute, variable, constant, tag, property,
         operatorSymbol, punctuation, regex, escape, inserted, deleted, heading, emphasis, link, plain
}

struct SyntaxToken: Equatable {
    /// UTF-16 range into the highlighted code.
    let range: NSRange
    let kind: SyntaxTokenKind
}

struct SyntaxLanguage: Hashable {
    /// Canonical id, e.g. "python".
    let id: String
    /// Human readable name, e.g. "Python"; used as the code block header label.
    let displayName: String
}

/// Native, dependency-free syntax highlighter for fenced code blocks.
enum SyntaxHighlighter {
    /// Inputs longer than this (UTF-16 units) are returned as plain monospaced text.
    static let highlightLimit = 300_000

    static let swiftUIPalette: [Color] = SyntaxTheme.palette.map { Color(nsColor: $0) }

    /// Resolves a fence info string ("py", "c++", "shell-session", "python {.x}", "main.rs", …) to a language.
    static func language(for fenceInfo: String) -> SyntaxLanguage? {
        SyntaxLanguageRegistry.resolve(fenceInfo)
    }

    /// Best-effort, conservative guess for a fence without a language; nil when unsure.
    static func detectLanguage(_ code: String) -> SyntaxLanguage? {
        SyntaxLanguageDetector.detect(code)
    }

    /// Non-overlapping tokens sorted by location. Unclassified text is not covered.
    static func tokens(_ code: String, language: SyntaxLanguage) -> [SyntaxToken] {
        guard let kind = SyntaxLanguageRegistry.lexerKind(forId: language.id), !code.isEmpty else { return [] }
        return tokens(units: Array(code.utf16), kind: kind)
    }

    static func tokens(units: [UInt16], kind: SyntaxLexerKind) -> [SyntaxToken] {
        guard !units.isEmpty else { return [] }
        let sink = SyntaxTokenSink(capacity: units.count / 8)
        units.withUnsafeBufferPointer { buffer in
            SyntaxLexer(s: buffer, lo: 0, hi: buffer.count, sink: sink, depth: 0).run(kind)
        }
        return sink.tokens
    }

    /// Attributed string for AppKit text views: `font` everywhere, token colours from `SyntaxTheme`.
    static func attributedString(_ code: String, language: SyntaxLanguage?, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString(string: code, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        guard let language, code.utf16.count <= highlightLimit else { return result }
        let tokens = tokens(code, language: language)
        guard !tokens.isEmpty else { return result }
        let palette = SyntaxTheme.palette
        result.beginEditing()
        for token in tokens {
            result.addAttribute(.foregroundColor, value: palette[token.kind.rawValue], range: token.range)
        }
        result.endEditing()
        return result
    }

    /// Attributed string for SwiftUI `Text`. Only token runs carry a foreground colour, so plain text
    /// inherits the view's foreground style; the caller applies the monospaced font.
    static func swiftUIAttributedString(_ code: String, language: SyntaxLanguage?) -> AttributedString {
        guard let language, code.utf16.count <= highlightLimit else { return AttributedString(code) }
        let tokens = tokens(code, language: language)
        guard !tokens.isEmpty else { return AttributedString(code) }
        let palette = swiftUIPalette
        let key = NSAttributedString.Key(AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.name)
        let ns = NSMutableAttributedString(string: code)
        ns.beginEditing()
        for token in tokens {
            ns.addAttribute(key, value: palette[token.kind.rawValue], range: token.range)
        }
        ns.endEditing()
        return (try? AttributedString(ns, including: \.swiftUI)) ?? AttributedString(code)
    }
}
