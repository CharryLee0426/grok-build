import AppKit

/// Xcode-inspired palette tuned for code block backgrounds around #F3F3F6 (light) and #252528 (dark).
enum SyntaxTheme {
    /// Dynamic (light/dark adaptive) colour for a token kind. Plain text and operators use `labelColor`.
    static func color(for kind: SyntaxTokenKind) -> NSColor { palette[kind.rawValue] }

    /// One cached dynamic colour per kind, indexed by `rawValue` (creating dynamic colours is not free).
    static let palette: [NSColor] = SyntaxTokenKind.allCases.map { kind in
        guard let (light, dark) = hex(for: kind) else { return .labelColor }
        return dynamic(light: light, dark: dark)
    }

    /// Light/dark sRGB hex pairs; nil means "use the label colour".
    static func hex(for kind: SyntaxTokenKind) -> (UInt32, UInt32)? {
        switch kind {
        case .keyword: return (0x9B2393, 0xFC5FA3)
        case .type: return (0x0B6F78, 0x5CCFE6)
        case .function: return (0x2A5BC0, 0x7CACF8)
        case .string: return (0xC41A16, 0xFC6A5D)
        case .number, .constant: return (0x1C00CF, 0xD0BF69)
        case .comment: return (0x5D6C79, 0x7F8C98)
        case .attribute: return (0x815F03, 0xCC9768)
        case .variable: return (0x6C36A9, 0xC9A6FF)
        case .tag: return (0x16732F, 0x72D98A)
        case .property: return (0x0B4F79, 0x9CDCFE)
        case .regex: return (0xA3470C, 0xF29D63)
        case .escape: return (0x1C00CF, 0xD0BF69)
        case .inserted: return (0x1A7F37, 0x56D364)
        case .deleted: return (0xCF222E, 0xF85149)
        case .heading: return (0x1F4FB0, 0x79B8FF)
        case .emphasis: return (0x6C36A9, 0xD2A8FF)
        case .link: return (0x1A40D8, 0x5C8DFF)
        case .punctuation: return (0x6E7781, 0x8B949E)
        case .operatorSymbol, .plain: return nil
        }
    }

    static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        let lightColor = srgb(light), darkColor = srgb(dark)
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
        }
    }

    static func srgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
