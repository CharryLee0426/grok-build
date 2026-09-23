import SwiftUI
import AppKit

/// Selectable, read-only text for long or streaming content: reasoning, tool output, and diffs.
///
/// SwiftUI `Text` lays out its whole string again on every change and draws it as one
/// layer, so a long reasoning stream stalls the main thread, and resizing it (expanding or
/// collapsing it) can bring the app down. This view uses TextKit 1 with a height cap: streamed
/// suffixes are appended, only new text is laid out, and only the visible region is drawn.
struct ReadOnlyTextView: NSViewRepresentable {
    enum Style {
        /// Secondary 14 pt text, as for reasoning.
        case prose
        /// Primary 16 pt text, as for prompts.
        case body
        case monospaced
        /// Monospaced unified diff with coloured additions, removals, and hunk headers.
        case diff
    }
    enum Sizing: Equatable {
        /// Grow with the content up to a cap, then scroll internally.
        case fitContent(maxHeight: CGFloat)
        /// Take the space offered by the parent.
        case fill
    }

    var text: String
    var style: Style = .prose
    var wrapsLines = true
    var sizing: Sizing = .fitContent(maxHeight: 320)
    /// Keep the newest text in view as it streams, until the reader scrolls away from the end.
    var followsTail = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layoutManager = style == .diff ? DiffLayoutManager() : NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        // Diff lines are inset inside their full-width background.
        container.lineFragmentPadding = style == .diff ? 12 : 0
        layoutManager.addTextContainer(container)

        let textView = NSTextView(frame: .zero, textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true

        let scroll = PassthroughScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = textView
        context.coordinator.attach(scroll: scroll, textView: textView)
        configureWrapping(context.coordinator)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.wrapsLines != wrapsLines { configureWrapping(coordinator) }
        coordinator.update(text: text, style: style, followsTail: followsTail)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        switch sizing {
        case .fill:
            let size = proposal.replacingUnspecifiedDimensions(by: CGSize(width: 320, height: 240))
            return CGSize(width: size.width.isFinite ? size.width : 320, height: size.height.isFinite ? size.height : 240)
        case .fitContent(let maxHeight):
            let width = min(proposal.width ?? 480, 4_000)
            guard width > 1 else { return CGSize(width: max(0, width), height: 0) }
            return CGSize(width: width, height: context.coordinator.height(forWidth: width, cap: maxHeight))
        }
    }

    private func configureWrapping(_ coordinator: Coordinator) {
        guard let scroll = coordinator.scroll, let textView = coordinator.textView, let container = textView.textContainer else { return }
        coordinator.wrapsLines = wrapsLines
        coordinator.measuredHeights.removeAll()
        scroll.hasHorizontalScroller = !wrapsLines
        textView.isHorizontallyResizable = !wrapsLines
        textView.autoresizingMask = wrapsLines ? [.width] : []
        container.widthTracksTextView = wrapsLines
        if !wrapsLines {
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    @MainActor
    final class Coordinator {
        weak var scroll: PassthroughScrollView?
        weak var textView: NSTextView?
        var wrapsLines = true
        var measuredHeights: [CGFloat: CGFloat] = [:]
        private var applied = ""
        private var appliedStyle: Style?
        private var pendingScrollToEnd = false
        /// Sizes the view without touching the displayed layout, whose container follows the
        /// text view's width (zero, and so unbounded, until SwiftUI first places it). Only a
        /// prefix is measured: far less text than this already fills any height cap, and laying
        /// out a megabyte just to learn that it is taller than the cap takes a noticeable pause.
        private let measuringStorage = NSTextStorage()
        private let measuringLayout = NSLayoutManager()
        private let measuringContainer = NSTextContainer(containerSize: .zero)
        private static let measuredPrefix = 16_384

        func attach(scroll: PassthroughScrollView, textView: NSTextView) {
            self.scroll = scroll
            self.textView = textView
            scroll.onTile = { [weak self] in self?.didTile() }
            measuringContainer.lineFragmentPadding = textView.textContainer?.lineFragmentPadding ?? 0
            measuringLayout.addTextContainer(measuringContainer)
            measuringStorage.addLayoutManager(measuringLayout)
        }

        func update(text: String, style: Style, followsTail: Bool) {
            guard let textView, let storage = textView.textStorage, let layoutManager = textView.layoutManager else { return }
            // Contiguous layout keeps appends incremental and tail-following exact. Static
            // text only needs its visible region laid out, however long it is.
            if layoutManager.allowsNonContiguousLayout == followsTail { layoutManager.allowsNonContiguousLayout = !followsTail }
            guard style != appliedStyle || text != applied else { return }
            // Following text starts at its end, then stays there until the reader scrolls away.
            let wasAtEnd = appliedStyle == nil || isScrolledToEnd
            let appended = style == appliedStyle && style != .diff ? TextDelta.appendedSuffix(from: applied, to: text) : nil
            if let appended {
                storage.append(NSAttributedString(string: appended, attributes: Self.attributes(for: style)))
            } else {
                storage.setAttributedString(Self.attributedString(text, style: style))
            }
            // The measured text is the displayed text's first `measuredPrefix` characters. Appends
            // extend it until it is full, and after that leave it and its layout untouched.
            let prefix = min(storage.length, Self.measuredPrefix)
            if appended == nil {
                measuringStorage.setAttributedString(storage.attributedSubstring(from: NSRange(location: 0, length: prefix)))
                measuredHeights.removeAll()
            } else if measuringStorage.length < prefix {
                let start = measuringStorage.length
                measuringStorage.append(storage.attributedSubstring(from: NSRange(location: start, length: prefix - start)))
                measuredHeights.removeAll()
            }
            applied = text
            appliedStyle = style
            if followsTail && wasAtEnd { scrollToEnd() }
        }

        func height(forWidth width: CGFloat, cap: CGFloat) -> CGFloat {
            guard let textView else { return 0 }
            // Text beyond the prefix can only add height, so a partial measurement means the cap.
            if (textView.textStorage?.length ?? 0) > measuringStorage.length { return cap }
            if let cached = measuredHeights[width] { return min(cap, cached) }
            let size = NSSize(width: wrapsLines ? width : CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            if measuringContainer.containerSize != size { measuringContainer.containerSize = size }
            measuringLayout.ensureLayout(for: measuringContainer)
            let used = measuringLayout.usedRect(for: measuringContainer)
            var height = used.height + textView.textContainerInset.height * 2
            if !wrapsLines, used.width > width, let scroll, scroll.scrollerStyle == .legacy, let scroller = scroll.horizontalScroller {
                height += scroller.frame.height
            }
            measuredHeights[width] = ceil(height)
            return min(cap, ceil(height))
        }

        private var isScrolledToEnd: Bool {
            guard let scroll, let textView else { return true }
            // Not placed yet, or still waiting to reach the end after being placed.
            if pendingScrollToEnd || scroll.frame.height < 1 { return true }
            return scroll.contentView.bounds.maxY >= textView.frame.height - 8
        }

        private func didTile() {
            guard pendingScrollToEnd else { return }
            scrollToEnd()
        }

        private func scrollToEnd() {
            guard let scroll, let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
            // Laying out at zero width would put every character on its own line.
            guard scroll.frame.width > 1, container.containerSize.width > 1 else { pendingScrollToEnd = true; return }
            pendingScrollToEnd = false
            layoutManager.ensureLayout(for: container)
            textView.sizeToFit()
            let clip = scroll.contentView
            // Scroll this clip view only: scrollRangeToVisible would also move the transcript.
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: max(0, textView.frame.height - clip.bounds.height)))
            scroll.reflectScrolledClipView(clip)
        }

        static func attributes(for style: Style) -> [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            switch style {
            case .prose:
                paragraph.lineSpacing = 3
                return [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph]
            case .body:
                paragraph.lineSpacing = 3
                return [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
            case .monospaced, .diff:
                paragraph.lineSpacing = 2
                return [.font: NSFont.monospacedSystemFont(ofSize: style == .diff ? 12 : 13, weight: .regular), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
            }
        }

        static func attributedString(_ text: String, style: Style) -> NSAttributedString {
            let result = NSMutableAttributedString(string: text, attributes: attributes(for: style))
            guard style == .diff else { return result }
            let source = result.string as NSString
            source.enumerateSubstrings(in: NSRange(location: 0, length: source.length), options: [.byParagraphs, .substringNotRequired]) { _, range, enclosing, _ in
                guard range.length > 0 else { return }
                let line = DiffLine(source.substring(with: NSRange(location: range.location, length: min(2, range.length))))
                result.addAttribute(.foregroundColor, value: line.foreground, range: range)
                if let background = line.background { result.addAttribute(.diffLineBackground, value: background, range: enclosing) }
            }
            return result
        }
    }
}

/// How streamed text changed since it was last shown.
enum TextDelta {
    /// The text added to the end of `old`, or nil when `new` does not continue it.
    static func appendedSuffix(from old: String, to new: String) -> String? {
        let oldBytes = old.utf8, newBytes = new.utf8
        guard !old.isEmpty, newBytes.count > oldBytes.count else { return nil }
        let contiguous = newBytes.withContiguousStorageIfAvailable { newBuffer in
            oldBytes.withContiguousStorageIfAvailable { oldBuffer in
                memcmp(newBuffer.baseAddress!, oldBuffer.baseAddress!, oldBuffer.count) == 0
            }
        } ?? nil
        guard contiguous ?? newBytes.starts(with: oldBytes) else { return nil }
        // `old` is valid UTF-8, so its length falls on a scalar boundary within `new`.
        return String(decoding: newBytes.dropFirst(oldBytes.count), as: UTF8.self)
    }
}

private struct DiffLine {
    var foreground: NSColor
    var background: NSColor?

    init(_ prefix: String) {
        if prefix.hasPrefix("+") { foreground = Theme.greenNS; background = Theme.greenNS.withAlphaComponent(0.08) }
        else if prefix.hasPrefix("-") { foreground = NSColor.systemRed.withAlphaComponent(0.85); background = NSColor.systemRed.withAlphaComponent(0.07) }
        else if prefix.hasPrefix("@@") { foreground = Theme.accentNS; background = nil }
        else { foreground = .secondaryLabelColor; background = nil }
    }
}

private extension NSAttributedString.Key {
    static let diffLineBackground = NSAttributedString.Key("GrokDiffLineBackground")
}

/// Fills added and removed diff lines across the full width, not only behind their glyphs.
private final class DiffLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if let storage = textStorage, let textView = firstTextView {
            let width = max(textView.bounds.width, textView.enclosingScrollView?.contentView.bounds.width ?? 0)
            enumerateLineFragments(forGlyphRange: glyphsToShow) { rect, _, _, glyphRange, _ in
                let index = self.characterIndexForGlyph(at: glyphRange.location)
                guard index < storage.length,
                      let color = storage.attribute(.diffLineBackground, at: index, effectiveRange: nil) as? NSColor else { return }
                color.setFill()
                NSRect(x: 0, y: origin.y + rect.minY, width: width, height: rect.height).fill(using: .sourceOver)
            }
        }
        // Selection highlights draw on top of the line colour.
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }
}

/// Hands scrolling to the transcript when there is nothing to scroll here.
final class PassthroughScrollView: NSScrollView {
    var onTile: (() -> Void)?

    override func tile() {
        super.tile()
        onTile?()
    }

    override func scrollWheel(with event: NSEvent) {
        guard let document = documentView else { return super.scrollWheel(with: event) }
        let visible = contentView.bounds
        let vertical = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
        let canScroll = vertical
            ? document.frame.height > visible.height + 1
            : hasHorizontalScroller && document.frame.width > visible.width + 1
        if canScroll { super.scrollWheel(with: event) } else { nextResponder?.scrollWheel(with: event) }
    }
}
