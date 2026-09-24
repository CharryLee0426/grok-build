import AppKit
import SwiftUI

/// AppKit focus is explicit here because the composer is a native text view and
/// menu keyboard shortcuts can otherwise return first responder to the composer.
struct NativeSearchField: View {
    @Binding var text: String
    var placeholder: String
    var onEscape: () -> Void
    var onSubmit: (() -> Void)? = nil
    var onMove: ((Int) -> Void)? = nil
    /// Sheets and popovers take the keyboard as they open; a field in a panel waits to be clicked.
    var focusesOnAppear = true
    @State private var focused = false
    @State private var focusRequest = 0

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            NativeSearchInput(text: $text, focused: $focused, focusRequest: focusRequest, placeholder: placeholder, onEscape: onEscape, onSubmit: onSubmit, onMove: onMove,
                              focusesOnAppear: focusesOnAppear)
                .frame(height: 20)
            if !text.isEmpty {
                Button { text = ""; focusRequest += 1 } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(Theme.muted)
                        .frame(width: 22, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain).help("Clear search").accessibilityLabel("Clear search")
            }
        }.padding(.horizontal, 12).frame(minHeight: 40)
            .modifier(InputSurface(focused: focused))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture { focusRequest += 1 }
    }
}

private struct NativeSearchInput: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var focusRequest: Int
    var placeholder: String
    var onEscape: () -> Void
    var onSubmit: (() -> Void)?
    var onMove: ((Int) -> Void)?
    var focusesOnAppear: Bool

    func makeNSView(context: Context) -> FocusedSearchField {
        let field = FocusedSearchField()
        field.focusesOnAppear = focusesOnAppear
        field.delegate = context.coordinator
        field.onFocus = { context.coordinator.parent.focused = true }
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 14)
        field.focusRingType = .none
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        if let cell = field.cell as? NSSearchFieldCell {
            cell.searchButtonCell = nil
            cell.cancelButtonCell = nil
        }
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.setAccessibilityLabel(placeholder)
        return field
    }

    func updateNSView(_ field: FocusedSearchField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isShowingText = true
        field.showText(text)
        context.coordinator.isShowingText = false
        field.placeholderString = placeholder
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            field.window?.makeFirstResponder(field)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchInput
        var focusRequest = 0
        var isShowingText = false
        init(_ parent: NativeSearchInput) { self.parent = parent }
        func controlTextDidBeginEditing(_ notification: Notification) { parent.focused = true }
        func controlTextDidEndEditing(_ notification: Notification) { parent.focused = false }
        func controlTextDidChange(_ notification: Notification) {
            guard !isShowingText, let field = notification.object as? NSSearchField else { return }
            parent.text = (field.currentEditor() as? NSTextView)?.committedString ?? field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) { parent.onEscape(); return true }
            if commandSelector == #selector(NSResponder.insertNewline(_:)), let submit = parent.onSubmit { submit(); return true }
            if commandSelector == #selector(NSResponder.moveDown(_:)), let move = parent.onMove { move(1); return true }
            if commandSelector == #selector(NSResponder.moveUp(_:)), let move = parent.onMove { move(-1); return true }
            return false
        }
    }
}

final class FocusedSearchField: NSSearchField {
    var onFocus: (() -> Void)?
    var focusesOnAppear = true
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { DispatchQueue.main.async { [weak self] in self?.onFocus?() } }
        return accepted
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, focusesOnAppear else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }
}

// MARK: - Input method composition

// While an input method composes (pinyin before a character is chosen), the text holds marked
// text but no change is reported until it is committed, so bindings lag behind what is shown.

extension NSTextView {
    /// The text without its marked text: what has been committed so far.
    var committedString: String {
        let marked = markedRange()
        let text = string as NSString
        guard hasMarkedText(), marked.location != NSNotFound, NSMaxRange(marked) <= text.length else { return string }
        return text.replacingCharacters(in: marked, with: "")
    }
}

extension NSTextField {
    /// Shows `text` unless the field already does, keeping a composition unless `text` itself changed.
    func showText(_ text: String) {
        if let editor = currentEditor() as? NSTextView, editor.hasMarkedText() {
            guard editor.committedString != text else { return }
            editor.inputContext?.discardMarkedText()
        }
        if stringValue != text { stringValue = text }
    }
}
