import SwiftUI

/// The same quiet, inset surface is used for search, short answers, and forms.
struct InputSurface: ViewModifier {
    var focused: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .background(Theme.input, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(focused ? Theme.accent.opacity(0.65) : Theme.line.opacity(hovered ? 0.6 : 0.3), lineWidth: focused ? 1.5 : 1)
            }
            .opacity(isEnabled ? 1 : 0.55)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

struct DesktopTextField: View {
    let placeholder: String
    @Binding var text: String
    var title: String?
    var symbol: String?
    var hint: String?
    var multiline: Bool
    @FocusState private var focused: Bool

    init(_ placeholder: String, text: Binding<String>, title: String? = nil, symbol: String? = nil, hint: String? = nil, multiline: Bool = false) {
        self.placeholder = placeholder
        _text = text
        self.title = title
        self.symbol = symbol
        self.hint = hint
        self.multiline = multiline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted) }
            HStack(alignment: multiline ? .top : .center, spacing: 10) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(Theme.muted)
                        .frame(width: 18, height: 20)
                        .accessibilityHidden(true)
                }
                Group {
                    if multiline {
                        TextField(placeholder, text: $text, axis: .vertical).lineLimit(3...6)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(Theme.ink)
                .tint(Theme.accent).focused($focused).accessibilityLabel(title ?? placeholder)
            }
            .padding(.horizontal, 13).padding(.vertical, 12)
            .frame(minHeight: multiline ? 86 : 44, alignment: .topLeading)
            .modifier(InputSurface(focused: focused))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture { focused = true }
            if let hint { Text(hint).font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct ComposerControlLabel: View {
    let title: String
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 7) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(Theme.muted)
                    .frame(width: 18).accessibilityHidden(true)
            }
            Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
        }.padding(.horizontal, 11).frame(height: 40).contentShape(Capsule())
    }
}

struct ComposerControlStyle: ButtonStyle {
    var filled = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.ink)
            .background(Theme.hover.opacity(configuration.isPressed ? 1 : hovered ? 0.85 : filled ? 0.55 : 0), in: Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

struct PopoverRowStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovered || configuration.isPressed ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .onHover { hovered = $0 }
    }
}
