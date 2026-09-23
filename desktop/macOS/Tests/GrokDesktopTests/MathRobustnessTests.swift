import AppKit
import XCTest
@testable import GrokDesktop

/// Hostile and partial input must never crash or hang.
final class MathRobustnessTests: XCTestCase {
    /// Every prefix of every corpus formula (what a streaming chat shows mid-message).
    func testAllPrefixesOfCorpus() {
        var rendered = 0
        for formula in MathCorpusTests.corpus {
            let scalars = Array(formula.unicodeScalars)
            for end in stride(from: 1, through: scalars.count, by: 1) {
                var prefix = ""
                prefix.unicodeScalars.append(contentsOf: scalars[0..<end])
                if MathRenderer.render(prefix, fontSize: 13, color: .black, display: end % 2 == 0) != nil { rendered += 1 }
            }
        }
        XCTAssertGreaterThan(rendered, 1000)
    }

    func testRandomTokenSoup() {
        let vocabulary = [
            "{", "}", "^", "_", "&", "\\\\", "x", "2", "+", "=", "(", ")", "[", "]", "|", "\\left(", "\\right)",
            "\\left.", "\\right|", "\\middle|", "\\frac", "\\sqrt", "\\sqrt[3]", "\\sum", "\\int", "\\limits",
            "\\begin{matrix}", "\\end{matrix}", "\\begin{cases}", "\\end{cases}", "\\begin{array}{c|c}", "\\end{array}",
            "\\hline", "\\text{", "$", "\\hat", "\\overbrace", "\\underbrace", "\\not", "\\color{red}", "\\textcolor{blue}",
            "\\mathbf", "\\mathbb", "\\operatorname", "\\big(", "\\Bigg]", "\\xrightarrow[a]", "\\binom", "\\over", "'",
            "\\tag{1}", "\\newcommand{\\a}{\\a}", "\\def\\b#1{#1#1}", "\\b", "\\a", "%", "\n", " ", "\\,", "\\!", "\\foo",
            "\\substack{", "\\\\[2pt]", "\\overset", "\\boxed", "\\cancel", "\\phantom", "\\smash[t]", "α", "√", "²", "ᵢ",
            "\\hspace{", "1em", "-3mu", "\\kern", "\\middle", "\\right", "\\left", "\\end{", "\\begin{", "\\dots",
        ]
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<4000 {
            let count = Int.random(in: 1...30, using: &generator)
            var source = ""
            for _ in 0..<count { source += vocabulary.randomElement(using: &generator)! }
            _ = MathRenderer.render(source, fontSize: 12, color: .black, display: Bool.random(using: &generator))
        }
    }

    func testDeepNestingIsRejectedNotCrashing() {
        let deep = [
            String(repeating: "{", count: 5000) + "x" + String(repeating: "}", count: 5000),
            String(repeating: "\\sqrt", count: 5000) + "x",
            String(repeating: "\\left(", count: 3000) + "x" + String(repeating: "\\right)", count: 3000),
            String(repeating: "x^", count: 3000) + "x",
            String(repeating: "\\frac{1}{", count: 2000) + "x" + String(repeating: "}", count: 2000),
            String(repeating: "\\begin{matrix}", count: 1000) + "x" + String(repeating: "\\end{matrix}", count: 1000),
            String(repeating: "\\text{$", count: 1000) + "x" + String(repeating: "$}", count: 1000),
        ]
        // Run on a thread with a small (1 MB) stack; the main thread has 8 MB.
        let done = expectation(description: "deep")
        let thread = Thread {
            for source in deep {
                _ = MathRenderer.render(source, fontSize: 12, color: .black, display: true)
            }
            // Realistic nesting (20 levels) still renders.
            let nested = String(repeating: "\\frac{1}{1+", count: 20) + "x" + String(repeating: "}", count: 20)
            XCTAssertNotNil(MathRenderer.render(nested, fontSize: 12, color: .black, display: true))
            done.fulfill()
        }
        thread.stackSize = 1024 * 1024
        thread.start()
        wait(for: [done], timeout: 60)
    }

    func testMacroBombsTerminate() {
        let bombs = [
            "\\def\\a{\\a\\a}\\a",
            "\\newcommand{\\x}{\\x x}\\x",
            "\\def\\a{\\b}\\def\\b{\\a}\\a",
            "\\begin{array}{*{50}{*{50}{c}}} x \\end{array}",
        ]
        for source in bombs {
            _ = MathRenderer.render(source, fontSize: 12, color: .black, display: true)
        }
    }

    func testHugeButValidInputIsFast() {
        let row = (1...20).map { "a_{\($0)}" }.joined(separator: " & ")
        let matrix = "\\begin{pmatrix}" + Array(repeating: row, count: 40).joined(separator: " \\\\ ") + "\\end{pmatrix}"
        let start = CFAbsoluteTimeGetCurrent()
        XCTAssertNotNil(MathRenderer.render(matrix, fontSize: 12, color: .black, display: true))
        XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - start, 0.5)
    }
}
