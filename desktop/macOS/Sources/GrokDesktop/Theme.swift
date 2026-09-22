import SwiftUI
import AppKit

enum Theme {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
        })
    }
    static let canvas = adaptive(0xFCFBF8, 0x1B1C1E)
    static let sidebar = adaptive(0xF0EFEB, 0x141517)
    static let surface = adaptive(0xFFFFFF, 0x242528)
    static let hover = adaptive(0xE6E5E0, 0x2D2E31)
    static let line = adaptive(0xE5E3DD, 0x343539)
    static let ink = adaptive(0x242824, 0xE9EAE5)
    static let muted = adaptive(0x7B7F77, 0x90948D)
    static let accent = adaptive(0x41634C, 0xA1BFA8)
    static let green = adaptive(0x3B7751, 0x91C5A1)
}

struct IconButton: View {
    var icon: String
    var help: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 14, weight: .medium)).frame(width: 28, height: 28).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(Theme.muted).help(help).accessibilityLabel(help)
    }
}

struct GrokMark: View {
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29).fill(Theme.ink)
            Image(systemName: "asterisk").font(.system(size: size * 0.65, weight: .medium)).rotationEffect(.degrees(14)).foregroundStyle(Theme.canvas)
        }.frame(width: size, height: size).accessibilityLabel("Grok")
    }
}

struct SubtleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 11).padding(.vertical, 7)
            .background(configuration.isPressed ? Theme.hover : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line, lineWidth: 1))
    }
}
