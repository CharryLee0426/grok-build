import AppKit
import SwiftUI
import XCTest
@testable import GrokDesktop

final class SyntaxRobustnessTests: XCTestCase {
    /// Deterministic PRNG so failures are reproducible.
    struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static var allLanguageIds: [String] { SyntaxLanguageRegistry.entries.map(\.id) }

    func testSamplesAreWellFormed() {
        for (id, code) in SyntaxSamples.all {
            let tokens = SyntaxTestSupport.tokens(code, id)
            XCTAssertFalse(tokens.isEmpty, id)
            SyntaxTestSupport.assertWellFormed(tokens, length: code.utf16.count)
        }
    }

    /// Every language over random slices of every sample, random bytes and random unicode.
    func testFuzz() {
        var rng = SplitMix(state: UInt64(ProcessInfo.processInfo.environment["SYNTAX_FUZZ_SEED"] ?? "") ?? 42)
        let corpus = SyntaxSamples.all.map { Array($0.1.utf16) }
        let alphabet = Array("\"'`$#@{}[]()<>/\\*+-=;:,.!?%&|^~\n\t 0123456789abcxyzXYZ_é😀\u{0}\r".utf16)
        for id in Self.allLanguageIds {
            let language = SyntaxTestSupport.language(id)
            let rounds = Int(ProcessInfo.processInfo.environment["SYNTAX_FUZZ_ROUNDS"] ?? "") ?? 30
            for round in 0..<rounds {
                var units: [UInt16]
                switch round % 3 {
                case 0:
                    let source = corpus[Int.random(in: 0..<corpus.count, using: &rng)]
                    let a = Int.random(in: 0..<source.count, using: &rng)
                    let b = Int.random(in: a...source.count, using: &rng)
                    units = Array(source[a..<b])
                case 1:
                    units = (0..<Int.random(in: 0..<400, using: &rng)).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &rng)] }
                default:
                    units = (0..<Int.random(in: 0..<300, using: &rng)).map { _ in UInt16.random(in: 0...UInt16.max, using: &rng) }
                }
                guard let kind = SyntaxLanguageRegistry.lexerKind(forId: language.id) else { continue }
                let tokens = SyntaxHighlighter.tokens(units: units, kind: kind)
                SyntaxTestSupport.assertWellFormed(tokens, length: units.count)
            }
        }
    }

    /// Streaming: every prefix (cut at arbitrary points) must lex without crashing, and an
    /// unterminated string at the end must not swallow earlier lines.
    func testStreamingPrefixes() {
        for (id, code) in SyntaxSamples.all {
            let units = Array(code.utf16)
            guard let kind = SyntaxLanguageRegistry.lexerKind(forId: SyntaxTestSupport.language(id).id) else { continue }
            var cut = 0
            while cut <= units.count {
                let tokens = SyntaxHighlighter.tokens(units: Array(units[0..<cut]), kind: kind)
                SyntaxTestSupport.assertWellFormed(tokens, length: cut)
                cut += Int(ProcessInfo.processInfo.environment["SYNTAX_STREAM_STEP"] ?? "") ?? 7
            }
        }
        let partial = "let a = 1\nlet s = \"unterminated"
        XCTAssertEqual(SyntaxTestSupport.kind(of: "let", in: partial, "swift", occurrence: 2), .keyword)
        XCTAssertEqual(SyntaxTestSupport.kind(of: "\"unterminated", in: partial, "swift"), .string)
        let partialPy = "x = f\"{value"
        XCTAssertEqual(SyntaxTestSupport.kind(of: "f\"", in: partialPy, "python"), .string)
        let partialJS = "const t = `a ${b\nconst c = 1"
        XCTAssertFalse(SyntaxTestSupport.tokens(partialJS, "js").isEmpty)
        let partialBlock = "int x; /* open comment\nint y;"
        XCTAssertEqual(SyntaxTestSupport.kind(of: "int", in: partialBlock, "c"), .type)
        XCTAssertEqual(SyntaxTestSupport.kind(of: "int y;", in: partialBlock, "c"), .comment)
    }

    /// Pathological nesting and repetition must stay fast and must not overflow the stack.
    func testPathologicalInputs() {
        let deepTemplate = String(repeating: "`${", count: 5_000)
        let deepSwift = String(repeating: "\"\\(", count: 5_000)
        let deepShell = String(repeating: "$(", count: 5_000) + String(repeating: "\"", count: 100)
        let deepJSX = String(repeating: "(<a b={", count: 3_000)
        let stars = String(repeating: "*", count: 50_000)
        let brackets = String(repeating: "[", count: 50_000)
        let lt = String(repeating: "x = <a ", count: 5_000)
        let heredocs = String(repeating: "cat <<EOF\n", count: 2_000)
        let quotes = String(repeating: "'\"`", count: 20_000)
        let cases: [(String, String)] = [
            (deepTemplate, "js"), (deepSwift, "swift"), (deepShell, "bash"), (deepJSX, "jsx"), (stars, "markdown"),
            (brackets, "markdown"), (lt, "tsx"), (heredocs, "bash"), (heredocs, "ruby"), (quotes, "python"),
            (quotes, "rust"), (quotes, "yaml"), (stars, "css"), (brackets, "json"), (deepShell, "powershell"),
            (brackets, "lua"), (String(repeating: "{{", count: 20_000), "vue"), (String(repeating: "<%", count: 20_000), "erb"),
            (String(repeating: "(", count: 50_000), "clojure"), (String(repeating: "\\begin{x}", count: 5_000), "latex"),
            (String(repeating: "/", count: 50_000), "js"), (String(repeating: "= /", count: 20_000), "ruby"),
            (String(repeating: "#[derive(\n", count: 5_000), "rust"), (String(repeating: "[a](", count: 10_000), "markdown"),
            (String(repeating: "\\foo{", count: 10_000), "latex"), (String(repeating: "[a,", count: 10_000), "powershell"),
            (String(repeating: "- ", count: 30_000), "yaml"), (String(repeating: "f\"{", count: 10_000), "python"),
            (String(repeating: "#\"", count: 10_000), "swift"), (String(repeating: "/*", count: 30_000), "c"),
            (String(repeating: "<div ", count: 10_000), "html"), (String(repeating: "{% ", count: 10_000), "jinja"),
            (String(repeating: "a *b ", count: 20_000), "markdown"), (String(repeating: "x = `", count: 10_000), "go"),
            (String(repeating: "$ x\n", count: 20_000), "console"), (String(repeating: "@@ -1 +1 @@\n", count: 10_000), "diff")
        ]
        for (code, id) in cases {
            let start = Date()
            let tokens = SyntaxTestSupport.tokens(code, id)
            SyntaxTestSupport.assertWellFormed(tokens, length: code.utf16.count)
            XCTAssertLessThan(Date().timeIntervalSince(start), 2.0, "\(id) too slow on pathological input")
        }
    }

    func testAttributedStrings() throws {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let code = "let x = \"hi\" // note"
        let swift = SyntaxTestSupport.language("swift")
        let ns = SyntaxHighlighter.attributedString(code, language: swift, font: font)
        XCTAssertEqual(ns.string, code)
        XCTAssertEqual(ns.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, font)
        let keywordColor = try XCTUnwrap(ns.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let plainColor = try XCTUnwrap(ns.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor)
        XCTAssertNotEqual(keywordColor, plainColor)
        XCTAssertEqual(plainColor, NSColor.labelColor)

        // No language: plain monospaced text.
        let plain = SyntaxHighlighter.attributedString(code, language: nil, font: font)
        var runs = 0
        plain.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: plain.length)) { _, _, _ in runs += 1 }
        XCTAssertEqual(runs, 1)

        // Over the size limit: plain.
        let huge = String(repeating: "let value = \"string\" // comment\n", count: 12_000)
        XCTAssertGreaterThan(huge.utf16.count, SyntaxHighlighter.highlightLimit)
        let big = SyntaxHighlighter.attributedString(huge, language: swift, font: font)
        runs = 0
        big.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: big.length)) { _, _, _ in runs += 1 }
        XCTAssertEqual(runs, 1)

        // SwiftUI: token runs carry SwiftUI colours; plain runs inherit.
        let attributed = SyntaxHighlighter.swiftUIAttributedString(code, language: swift)
        XCTAssertEqual(String(attributed.characters), code)
        let colored = attributed.runs.filter { $0.foregroundColor != nil }
        XCTAssertGreaterThanOrEqual(colored.count, 3)
        XCTAssertNotNil(attributed.runs.first?.foregroundColor)
        XCTAssertEqual(SyntaxHighlighter.swiftUIAttributedString(code, language: nil), AttributedString(code))
    }

    func testThemeResolvesPerAppearance() throws {
        for kind in SyntaxTokenKind.allCases {
            let color = SyntaxTheme.color(for: kind)
            var light = NSColor.clear, dark = NSColor.clear
            try XCTUnwrap(NSAppearance(named: .aqua)).performAsCurrentDrawingAppearance { light = color.usingColorSpace(.sRGB) ?? .clear }
            try XCTUnwrap(NSAppearance(named: .darkAqua)).performAsCurrentDrawingAppearance { dark = color.usingColorSpace(.sRGB) ?? .clear }
            if kind != .plain && kind != .operatorSymbol {
                XCTAssertNotEqual(light, dark, "\(kind) should adapt to appearance")
                // Contrast against the code block backgrounds (WCAG ratio ≥ 3 for all, ≥ 4.5 for most).
                XCTAssertGreaterThanOrEqual(Self.contrast(light, SyntaxTheme.srgb(0xF3F3F6)), 4.0, "\(kind) light contrast")
                XCTAssertGreaterThanOrEqual(Self.contrast(dark, SyntaxTheme.srgb(0x252528)), 4.0, "\(kind) dark contrast")
            }
        }
    }

    static func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        func luminance(_ c: NSColor) -> CGFloat {
            let c = c.usingColorSpace(.sRGB) ?? c
            func channel(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
        }
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// 5,000+ lines of mixed code. Debug builds are slow, so the hard bound here is generous; see
    /// `SYNTAX_PERF_STRICT` for the release-mode bound.
    func testPerformance() {
        var chunks: [(SyntaxLanguage, String)] = []
        var lines = 0
        while lines < 5_000 {
            for (id, code) in SyntaxSamples.all where lines < 5_000 {
                chunks.append((SyntaxTestSupport.language(id), code))
                lines += code.split(separator: "\n", omittingEmptySubsequences: false).count
            }
        }
        let totalUnits = chunks.reduce(0) { $0 + $1.1.utf16.count }
        var tokenCount = 0
        let start = Date()
        for (language, code) in chunks { tokenCount += SyntaxHighlighter.tokens(code, language: language).count }
        let tokensTime = Date().timeIntervalSince(start)

        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        // Warm up font/attribute caches once, as a running app would have.
        _ = SyntaxHighlighter.attributedString(SyntaxSamples.swift, language: chunks[0].0, font: font)
        _ = SyntaxHighlighter.swiftUIAttributedString(SyntaxSamples.swift, language: chunks[0].0)
        let attrStart = Date()
        for (language, code) in chunks { _ = SyntaxHighlighter.attributedString(code, language: language, font: font) }
        let attrTime = Date().timeIntervalSince(attrStart)

        let swiftUIStart = Date()
        for (language, code) in chunks { _ = SyntaxHighlighter.swiftUIAttributedString(code, language: language) }
        let swiftUITime = Date().timeIntervalSince(swiftUIStart)

        // One big single-language document too.
        let bigSwift = String(repeating: SyntaxSamples.swift + "\n", count: 5_000 / 30)
        let bigStart = Date()
        _ = SyntaxHighlighter.tokens(bigSwift, language: SyntaxTestSupport.language("swift"))
        let bigTime = Date().timeIntervalSince(bigStart)

        print(String(format: "PERF lines=%d units=%d tokens=%d tokenize=%.1fms attributed=%.1fms swiftui=%.1fms swift5k=%.1fms",
                     lines, totalUnits, tokenCount, tokensTime * 1000, attrTime * 1000, swiftUITime * 1000, bigTime * 1000))
        let strict = ProcessInfo.processInfo.environment["SYNTAX_PERF_STRICT"] != nil
        XCTAssertLessThan(tokensTime, strict ? 0.05 : 1.0)
        XCTAssertLessThan(bigTime, strict ? 0.05 : 1.0)
    }
}
