import SwiftUI
import AppKit

enum Theme {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color { Color(nsColor: adaptiveNS(light, dark)) }
    static func adaptiveNS(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
        }
    }
    static let canvas = adaptive(0xFAFAFC, 0x1C1C1E)
    static let sidebar = Color(nsColor: .windowBackgroundColor)
    static let surface = adaptive(0xFFFFFF, 0x28282B)
    static let input = adaptive(0xF5F5F7, 0x222225)
    static let hover = adaptive(0xE9E9ED, 0x353538)
    static let line = Color(nsColor: .separatorColor)
    static let ink = Color(nsColor: .labelColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let accentNS = adaptiveNS(0x41634C, 0xA1BFA8)
    static let greenNS = adaptiveNS(0x3B7751, 0x91C5A1)
    static let accent = Color(nsColor: accentNS)
    static let green = Color(nsColor: greenNS)
}

extension View {
    /// Liquid Glass belongs to controls above content, rather than the transcript itself.
    func glassSurface(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius))
    }
}

private struct GlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Theme.line, lineWidth: 1))
        } else {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                materialSurface(content)
            }
            #else
            materialSurface(content)
            #endif
        }
    }

    private func materialSurface(_ content: Content) -> some View {
        content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Theme.line.opacity(0.6), lineWidth: 0.5))
    }
}

struct SidebarMaterial: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency { Theme.sidebar }
        else { NativeSidebarMaterial() }
    }
}

private struct NativeSidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct IconButton: View {
    var icon: String
    var help: String
    var action: () -> Void
    @State private var isHovered = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .medium)).frame(width: 32, height: 32)
                .background(isHovered ? Theme.hover.opacity(0.8) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
            .buttonStyle(.plain).foregroundStyle(Theme.muted).help(help).accessibilityLabel(help)
            .onHover { isHovered = $0 }
    }
}

struct GrokMark: View {
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29).fill(Theme.ink)
            GrokSymbol().fill(Theme.canvas).frame(width: size * 0.76, height: size * 0.76)
        }.frame(width: size, height: size).accessibilityLabel("Grok")
    }
}

struct SubtleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 13).padding(.vertical, 8)
            .background(configuration.isPressed || hovered ? Theme.hover : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 0.5))
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovered = $0 }
    }
}
