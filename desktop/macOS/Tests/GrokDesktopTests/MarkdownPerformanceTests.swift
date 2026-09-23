import XCTest
@testable import GrokDesktop

/// Run with `swift test -c release --filter PerformanceTests` for meaningful numbers.
/// Time bounds are only asserted in optimized builds.
final class MarkdownPerformanceTests: XCTestCase {
    static func milliseconds(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    static var isOptimized: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    func testParse100KBMeasure() {
        let doc = MarkdownTestDocuments.mixed(bytes: 100_000)
        for _ in 0..<30 { _ = MarkdownParser.parse(doc) } // warm up (CPU clock, allocator)
        measure {
            _ = MarkdownParser.parse(doc)
        }
    }

    func testParse100KBUnder10ms() {
        let doc = MarkdownTestDocuments.mixed(bytes: 100_000)
        for _ in 0..<30 { _ = MarkdownParser.parse(doc) }
        var samples: [Double] = []
        for _ in 0..<15 {
            samples.append(Self.milliseconds { _ = MarkdownParser.parse(doc) })
        }
        samples.sort()
        let median = samples[samples.count / 2]
        print("PERF parse \(doc.utf8.count) bytes: median \(String(format: "%.2f", median)) ms, min \(String(format: "%.2f", samples[0])) ms")
        if Self.isOptimized { XCTAssertLessThan(median, 10) }
    }

    func testParseLongThinkingParagraph() {
        let doc = MarkdownTestDocuments.thinking(lines: 2_000) // ~140 KB, no blank lines
        _ = MarkdownParser.parse(doc)
        var samples: [Double] = []
        for _ in 0..<7 {
            samples.append(Self.milliseconds { _ = MarkdownParser.parse(doc) })
        }
        samples.sort()
        let median = samples[samples.count / 2]
        print("PERF parse thinking \(doc.utf8.count) bytes: median \(String(format: "%.2f", median)) ms")
        if Self.isOptimized { XCTAssertLessThan(median, 15) }
    }

    func testStreaming200KBIn50CharChunks() {
        let doc = MarkdownTestDocuments.mixed(bytes: 200_000)
        let scalars = Array(doc.unicodeScalars)
        let cache = MarkdownDocumentCache()
        var steps = 0
        var prefix = String.UnicodeScalarView()
        var last: [MarkdownBlock] = []
        let total = Self.milliseconds {
            var i = 0
            while i < scalars.count {
                let end = min(i + 50, scalars.count)
                prefix.append(contentsOf: scalars[i..<end])
                last = cache.blocks(for: String(prefix))
                steps += 1
                i = end
            }
        }
        XCTAssertEqual(last, MarkdownParser.parse(doc))
        let fullParse = Self.milliseconds { _ = MarkdownParser.parse(doc) }
        print("PERF streaming \(doc.utf8.count) bytes in \(steps) chunks: total \(String(format: "%.1f", total)) ms, " +
              "\(String(format: "%.3f", total / Double(steps))) ms/step (one full parse: \(String(format: "%.2f", fullParse)) ms)")
        if Self.isOptimized { XCTAssertLessThan(total, 1_500) }
    }

    func testStreamingThinkingIn50CharChunks() {
        let doc = MarkdownTestDocuments.thinking(lines: 1_500)
        let scalars = Array(doc.unicodeScalars)
        let cache = MarkdownDocumentCache()
        var steps = 0
        var prefix = String.UnicodeScalarView()
        var last: [MarkdownBlock] = []
        let total = Self.milliseconds {
            var i = 0
            while i < scalars.count {
                let end = min(i + 50, scalars.count)
                prefix.append(contentsOf: scalars[i..<end])
                last = cache.blocks(for: String(prefix))
                steps += 1
                i = end
            }
        }
        XCTAssertEqual(last, MarkdownParser.parse(doc))
        print("PERF streaming thinking \(doc.utf8.count) bytes in \(steps) chunks: total \(String(format: "%.1f", total)) ms")
        if Self.isOptimized { XCTAssertLessThan(total, 1_500) }
    }
}
