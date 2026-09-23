import SwiftUI
import AppKit

/// The app's colours. Every accessor reads the active `ThemePalette`, which `/theme` swaps;
/// the main window rebuilds its views when it does (see `ExtrasFeatureModel.themeRevision`).
enum Theme {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color { Color(nsColor: adaptiveNS(light, dark)) }
    static func adaptiveNS(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? rgb(dark) : rgb(light)
        }
    }
    static func rgb(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
    }

    /// Written on the main thread only, when a theme is applied or previewed.
    private(set) static var palette = ThemePalette.auto

    static func apply(_ theme: GrokTheme) { palette = ThemePalette.palette(for: theme) }

    static var canvas: Color { palette.canvas }
    static var sidebar: Color { palette.sidebar }
    static var surface: Color { palette.surface }
    static var input: Color { palette.input }
    static var hover: Color { palette.hover }
    static var line: Color { palette.line }
    static var ink: Color { palette.ink }
    static var muted: Color { palette.muted }
    static var accentNS: NSColor { palette.accentNS }
    static var greenNS: NSColor { palette.greenNS }
    static var redNS: NSColor { palette.redNS }
    static var accent: Color { palette.accent }
    static var green: Color { palette.green }
    static var red: Color { palette.red }
    static var codeBackgroundNS: NSColor { palette.codeBackgroundNS }
    static var inlineCodeNS: NSColor { palette.inlineCodeNS }
    static var tableHeaderNS: NSColor { palette.tableHeaderNS }
    static var codeBackground: Color { palette.codeBackground }
    static var inlineCode: Color { palette.inlineCode }
    static var tableHeader: Color { palette.tableHeader }
    static var tableStripe: Color { palette.tableStripe }
}

/// One theme's colours. A class, so reading a colour through `Theme` copies a single reference.
final class ThemePalette {
    let theme: GrokTheme
    /// Only the default look uses translucent system materials; the terminal palettes are opaque.
    let usesSystemMaterials: Bool
    let canvasNS, sidebarNS, surfaceNS, inputNS, hoverNS, lineNS, inkNS, mutedNS: NSColor
    let accentNS, greenNS, redNS, codeBackgroundNS, inlineCodeNS, tableHeaderNS, tableStripeNS: NSColor
    let canvas, sidebar, surface, input, hover, line, ink, muted: Color
    let accent, green, red, codeBackground, inlineCode, tableHeader, tableStripe: Color

    init(theme: GrokTheme, usesSystemMaterials: Bool = false,
         canvas: NSColor, sidebar: NSColor, surface: NSColor, input: NSColor, hover: NSColor, line: NSColor, ink: NSColor, muted: NSColor,
         accent: NSColor, green: NSColor, red: NSColor, codeBackground: NSColor, inlineCode: NSColor, tableHeader: NSColor, tableStripe: NSColor) {
        self.theme = theme
        self.usesSystemMaterials = usesSystemMaterials
        canvasNS = canvas; sidebarNS = sidebar; surfaceNS = surface; inputNS = input; hoverNS = hover; lineNS = line; inkNS = ink; mutedNS = muted
        accentNS = accent; greenNS = green; redNS = red; codeBackgroundNS = codeBackground; inlineCodeNS = inlineCode
        tableHeaderNS = tableHeader; tableStripeNS = tableStripe
        self.canvas = Color(nsColor: canvas); self.sidebar = Color(nsColor: sidebar); self.surface = Color(nsColor: surface)
        self.input = Color(nsColor: input); self.hover = Color(nsColor: hover); self.line = Color(nsColor: line)
        self.ink = Color(nsColor: ink); self.muted = Color(nsColor: muted); self.accent = Color(nsColor: accent)
        self.green = Color(nsColor: green); self.red = Color(nsColor: red); self.codeBackground = Color(nsColor: codeBackground)
        self.inlineCode = Color(nsColor: inlineCode); self.tableHeader = Color(nsColor: tableHeader); self.tableStripe = Color(nsColor: tableStripe)
    }

    /// Terminal palettes are opaque colours from the pager's themes
    /// (`xai-grok-pager-render/src/theme/*.rs`), in the roles the desktop draws.
    private convenience init(_ theme: GrokTheme, canvas: UInt32, sidebar: UInt32, surface: UInt32, input: UInt32, hover: UInt32, line: UInt32,
                             ink: UInt32, muted: UInt32, accent: UInt32, green: UInt32, red: UInt32,
                             codeBackground: UInt32, inlineCode: UInt32, tableHeader: UInt32, tableStripe: UInt32) {
        self.init(theme: theme, canvas: Theme.rgb(canvas), sidebar: Theme.rgb(sidebar), surface: Theme.rgb(surface), input: Theme.rgb(input),
                  hover: Theme.rgb(hover), line: Theme.rgb(line), ink: Theme.rgb(ink), muted: Theme.rgb(muted), accent: Theme.rgb(accent),
                  green: Theme.rgb(green), red: Theme.rgb(red), codeBackground: Theme.rgb(codeBackground), inlineCode: Theme.rgb(inlineCode),
                  tableHeader: Theme.rgb(tableHeader), tableStripe: Theme.rgb(tableStripe))
    }

    /// The desktop's own look, following the system appearance. It is unchanged for anyone who never picks a theme.
    static let auto = ThemePalette(
        theme: .auto, usesSystemMaterials: true,
        canvas: Theme.adaptiveNS(0xFAFAFC, 0x1C1C1E), sidebar: .windowBackgroundColor, surface: Theme.adaptiveNS(0xFFFFFF, 0x28282B),
        input: Theme.adaptiveNS(0xF5F5F7, 0x222225), hover: Theme.adaptiveNS(0xE9E9ED, 0x353538), line: .separatorColor,
        ink: .labelColor, muted: .secondaryLabelColor, accent: Theme.adaptiveNS(0x41634C, 0xA1BFA8), green: Theme.adaptiveNS(0x3B7751, 0x91C5A1),
        red: Theme.adaptiveNS(0xB3261E, 0xF2877E), codeBackground: Theme.adaptiveNS(0xF3F3F6, 0x252528), inlineCode: Theme.adaptiveNS(0xEBEBEF, 0x333337),
        tableHeader: Theme.adaptiveNS(0xF1F1F4, 0x2B2B2F), tableStripe: Theme.adaptiveNS(0xF9F9FB, 0x232326))

    /// Grok Night: neutral grays with TokyoNight accents (groknight.rs).
    static let grokNight = ThemePalette(
        .groknight, canvas: 0x141414, sidebar: 0x111111, surface: 0x242424, input: 0x1C1C1C, hover: 0x2C2C2C, line: 0x323237,
        ink: 0xE1E1E1, muted: 0x787878, accent: 0xBB9AF7, green: 0x9ECE6A, red: 0xF7768E,
        codeBackground: 0x1C1C1C, inlineCode: 0x242424, tableHeader: 0x242424, tableStripe: 0x1C1C1C)

    /// Grok Day: the light counterpart (grokday.rs).
    static let grokDay = ThemePalette(
        .grokday, canvas: 0xEEEEEE, sidebar: 0xE4E4E4, surface: 0xF5F5F5, input: 0xEEEEEE, hover: 0xDEDEDE, line: 0xC8C8CD,
        ink: 0x262626, muted: 0x626262, accent: 0x7D4BC6, green: 0x378E23, red: 0xCD3048,
        codeBackground: 0xE4E4E4, inlineCode: 0xDEDEDE, tableHeader: 0xE4E4E4, tableStripe: 0xEAEAEA)

    /// Tokyo Night Storm (tokyonight.rs).
    static let tokyoNight = ThemePalette(
        .tokyonight, canvas: 0x24283B, sidebar: 0x1F2335, surface: 0x292E42, input: 0x1F2335, hover: 0x283457, line: 0x3B4261,
        ink: 0xC0CAF5, muted: 0x737AA2, accent: 0xBB9AF7, green: 0x9ECE6A, red: 0xF7768E,
        codeBackground: 0x292E42, inlineCode: 0x292E42, tableHeader: 0x292E42, tableStripe: 0x1F2335)

    /// Rosé Pine Moon (rosepine.rs).
    static let rosePineMoon = ThemePalette(
        .rosepineMoon, canvas: 0x232136, sidebar: 0x2A273F, surface: 0x393552, input: 0x232136, hover: 0x44415A, line: 0x44415A,
        ink: 0xE0DEF4, muted: 0x908CAA, accent: 0xC4A7E7, green: 0x9CCFD8, red: 0xEB6F92,
        codeBackground: 0x2A273F, inlineCode: 0x393552, tableHeader: 0x393552, tableStripe: 0x2A283E)

    /// Oscura Midnight: near-black with purple hints (oscura.rs).
    static let oscuraMidnight = ThemePalette(
        .oscuraMidnight, canvas: 0x030304, sidebar: 0x0F1216, surface: 0x0F1216, input: 0x040507, hover: 0x242034, line: 0x343048,
        ink: 0xE4E4E4, muted: 0x81868F, accent: 0x9B7ECE, green: 0x50B48C, red: 0xDC5A64,
        codeBackground: 0x26292F, inlineCode: 0x26292F, tableHeader: 0x0F1216, tableStripe: 0x12101C)

    static func palette(for theme: GrokTheme) -> ThemePalette {
        switch theme {
        case .auto: return auto
        case .groknight: return grokNight
        case .grokday: return grokDay
        case .tokyonight: return tokyoNight
        case .rosepineMoon: return rosePineMoon
        case .oscuraMidnight: return oscuraMidnight
        }
    }
}

extension View {
    /// Liquid Glass belongs to controls above content, rather than the transcript itself.
    func glassSurface(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius))
    }
}

extension View {
    /// Paints the window toolbar in a terminal palette's canvas colour; the default look keeps the system's.
    @ViewBuilder
    func themedToolbarBackground() -> some View {
        if Theme.palette.usesSystemMaterials { self }
        else { toolbarBackground(Theme.canvas, for: .windowToolbar).toolbarBackground(.visible, for: .windowToolbar) }
    }
}

private struct GlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        // Glass tints itself from the system; a terminal palette keeps its own surface colour.
        if reduceTransparency || !Theme.palette.usesSystemMaterials {
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
        if reduceTransparency || !Theme.palette.usesSystemMaterials { Theme.sidebar }
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
    var size: CGFloat = 32
    var action: () -> Void
    @State private var isHovered = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size * 0.47, weight: .medium)).frame(width: size, height: size)
                .background(isHovered ? Theme.hover.opacity(0.8) : .clear, in: RoundedRectangle(cornerRadius: size / 4))
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
