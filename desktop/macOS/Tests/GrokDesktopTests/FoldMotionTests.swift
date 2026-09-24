import AppKit
import SwiftUI
import XCTest
@testable import GrokDesktop

/// Folds uncover their content from the top with a growing clip instead of laying it out again.
@MainActor
final class FoldMotionTests: XCTestCase {
    private var window: NSWindow?

    override func tearDown() async throws {
        window?.close()
        window = nil
    }

    private func render<V: View>(_ view: V, size: CGSize) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        self.window = window
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private final class FoldModel: ObservableObject { @Published var open = false }
    private final class FoldProbe { var heights: [CGFloat] = []; var toggle: (() -> Void)? }

    private struct FoldHarness: View {
        @ObservedObject var model: FoldModel
        let probe: FoldProbe
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Fold(isExpanded: $model.open) { toggle, isOpen in
                    Text(isOpen ? "Open" : "Closed").frame(height: 44).onAppear { probe.toggle = toggle }
                } content: {
                    ReadOnlyTextView(text: (1...30).map { "Line \($0)" }.joined(separator: "\n"), style: .prose, sizing: .fitContent(maxHeight: 300))
                }
                .background(GeometryReader { geometry in Color.clear.preference(key: FoldHeight.self, value: geometry.size.height) })
                Spacer(minLength: 0)
            }
            .frame(width: 400, height: 500)
            .onPreferenceChange(FoldHeight.self) { probe.heights.append($0) }
        }
    }

    private struct FoldHeight: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }

    /// Closing animates in layout like opening, so what sits below follows the fold both ways.
    func testFoldsOpenAndCloseThroughTheHeightsBetween() throws {
        let model = FoldModel(), probe = FoldProbe()
        let host = NSHostingView(rootView: FoldHarness(model: model, probe: probe))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        self.window = window
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let toggle = try XCTUnwrap(probe.toggle)
        let animated = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        func run(_ expectedOpen: Bool, _ phase: String) {
            probe.heights.removeAll()
            toggle()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            XCTAssertEqual(model.open, expectedOpen, phase)
            if animated { XCTAssertGreaterThan(Set(probe.heights.map { Int($0) }).count, 10, "\(phase) passes through the heights between") }
        }
        run(true, "Opening")
        run(false, "Closing")
        run(true, "Opening again")
        guard animated else { return }
        // Clicking again before a close finishes opens the fold back up.
        toggle()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        toggle()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertTrue(model.open)
        XCTAssertEqual(probe.heights.last ?? 0, 344, accuracy: 1)
    }

    func testARevealTakesItsShareOfTheContentHeight() {
        for (progress, height) in [(0.0, 0.0), (0.25, 50.0), (1.0, 200.0)] {
            let host = NSHostingView(rootView: RevealLayout(progress: progress) { Color.blue.frame(width: 100, height: 200) })
            XCTAssertEqual(host.fittingSize.height, height, accuracy: 0.5, "progress \(progress)")
        }
    }

    /// Thinking and tool output are AppKit text views; a half-open fold must hide their lower half too.
    func testHalfOpenFoldClipsTextViews() throws {
        let text = (1...40).map { "Line \($0) of reasoning that fills the whole width of the view" }.joined(separator: "\n")
        func fold(_ progress: CGFloat) -> some View {
            VStack(spacing: 0) {
                ReadOnlyTextView(text: text, style: .body, sizing: .fitContent(maxHeight: 400))
                    .frame(width: 400)
                    .modifier(FoldReveal(progress: progress))
                Spacer(minLength: 0)
            }
            .frame(width: 400, height: 600, alignment: .top)
            .background(Color.white)
        }
        let open = try render(fold(1), size: CGSize(width: 400, height: 600))
        let scale = CGFloat(open.pixelsHigh) / 600
        XCTAssertGreaterThan(inkRows(open, in: Int(230 * scale)..<Int(400 * scale)), 10, "An open fold shows all of its text")
        let bitmap = try render(fold(0.5), size: CGSize(width: 400, height: 600))
        XCTAssertGreaterThan(inkRows(bitmap, in: 0..<Int(150 * scale)), 10, "The top of the text shows")
        XCTAssertEqual(inkRows(bitmap, in: Int(230 * scale)..<Int(400 * scale)), 0, "Text below the fold is clipped")
    }

    /// Rows holding dark text pixels.
    private func inkRows(_ bitmap: NSBitmapImageRep, in rows: Range<Int>) -> Int {
        var count = 0
        for y in rows {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.redComponent + color.greenComponent + color.blueComponent < 2.4 && color.alphaComponent > 0.5 { count += 1; break }
            }
        }
        return count
    }
}
