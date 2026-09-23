import CoreGraphics
import Foundation

/// Parses xcolor-style color specifications: named colors (`red`, `RoyalBlue`),
/// mixes (`red!30`, `blue!50!black`), `#RRGGBB`, and explicit models
/// (`[HTML]{FF8800}`, `[rgb]{1,0.5,0}`, `[RGB]{255,128,0}`, `[gray]{0.5}`).
enum MathColorParser {
    /// Base names use CSS values (what KaTeX/MathJax readers expect; xcolor's pure
    /// `green` is unreadable on white). dvipsnames are matched case-insensitively.
    private static let named: [String: (CGFloat, CGFloat, CGFloat)] = [
        "red": (1, 0, 0), "green": (0, 0.5, 0), "blue": (0, 0, 1), "cyan": (0, 1, 1),
        "magenta": (1, 0, 1), "yellow": (1, 1, 0), "black": (0, 0, 0), "white": (1, 1, 1),
        "gray": (0.5, 0.5, 0.5), "grey": (0.5, 0.5, 0.5), "darkgray": (0.25, 0.25, 0.25),
        "darkgrey": (0.25, 0.25, 0.25), "lightgray": (0.83, 0.83, 0.83), "lightgrey": (0.83, 0.83, 0.83),
        "brown": (0.65, 0.16, 0.16), "lime": (0, 1, 0), "olive": (0.5, 0.5, 0),
        "orange": (1, 0.65, 0), "pink": (1, 0.75, 0.8), "purple": (0.5, 0, 0.5),
        "teal": (0, 0.5, 0.5), "violet": (0.93, 0.51, 0.93), "navy": (0, 0, 0.5), "maroon": (0.5, 0, 0),
        "gold": (1, 0.84, 0), "silver": (0.75, 0.75, 0.75), "indigo": (0.29, 0, 0.51),
        "darkblue": (0, 0, 0.55), "darkred": (0.55, 0, 0), "darkgreen": (0, 0.39, 0),
        "royalblue": (0, 0.44, 0.74), "forestgreen": (0, 0.61, 0.33), "navyblue": (0, 0.43, 0.72),
        "orchid": (0.68, 0.36, 0.66), "salmon": (0.97, 0.58, 0.49), "goldenrod": (1, 0.87, 0.16),
        "brickred": (0.71, 0.2, 0.16), "emerald": (0, 0.66, 0.62), "aquamarine": (0, 0.71, 0.75),
        "skyblue": (0.46, 0.8, 0.94), "turquoise": (0, 0.71, 0.75), "crimson": (0.86, 0.08, 0.24),
        "redorange": (0.95, 0.38, 0.21), "bittersweet": (0.76, 0.19, 0), "cerulean": (0, 0.64, 0.89),
        "cornflowerblue": (0.25, 0.7, 0.9), "midnightblue": (0, 0.4, 0.57), "plum": (0.57, 0.15, 0.56),
        "rubinered": (0.87, 0, 0.53), "seagreen": (0.25, 0.73, 0.52), "junglegreen": (0, 0.66, 0.52),
        "tan": (0.86, 0.58, 0.44), "sepia": (0.4, 0.09, 0), "mahogany": (0.65, 0.2, 0.15),
        "periwinkle": (0.48, 0.51, 0.76), "lavender": (0.96, 0.62, 0.76), "coral": (1, 0.5, 0.31),
        "darkorange": (1, 0.55, 0), "orangered": (1, 0.27, 0), "limegreen": (0.2, 0.8, 0.2),
        "steelblue": (0.27, 0.51, 0.71), "slategray": (0.44, 0.5, 0.56), "dodgerblue": (0.12, 0.56, 1),
    ]

    static func color(_ spec: String, model: String? = nil) -> CGColor? {
        let spec = spec.trimmingCharacters(in: .whitespaces)
        if let raw = model?.trimmingCharacters(in: .whitespaces), !raw.isEmpty {
            // xcolor distinguishes `RGB` (0–255) from `rgb` (0–1) by case.
            return colorWithModel(spec, model: raw == "RGB" ? "rgb255" : raw.lowercased())
        }
        if spec.hasPrefix("#") { return hex(String(spec.dropFirst())) }
        if spec.contains("!") { return mix(spec) }
        if let rgb = named[spec.lowercased()] { return make(rgb) }
        // Bare six-digit hex is a common LLM shortcut.
        if spec.count == 6, let c = hex(spec) { return c }
        return nil
    }

    private static func make(_ rgb: (CGFloat, CGFloat, CGFloat), alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: alpha)
    }

    private static func hex(_ s: String) -> CGColor? {
        var digits = s
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, let v = UInt32(digits, radix: 16) else { return nil }
        return make((CGFloat((v >> 16) & 0xFF) / 255, CGFloat((v >> 8) & 0xFF) / 255, CGFloat(v & 0xFF) / 255))
    }

    private static func components(_ s: String) -> [CGFloat] {
        s.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0).map { CGFloat($0) } }
    }

    private static func colorWithModel(_ spec: String, model: String) -> CGColor? {
        switch model {
        case "html":
            return hex(spec)
        case "rgb":
            let c = components(spec)
            return c.count == 3 ? make((c[0], c[1], c[2])) : nil
        case "rgb255":
            let c = components(spec)
            return c.count == 3 ? make((c[0] / 255, c[1] / 255, c[2] / 255)) : nil
        case "gray":
            let c = components(spec)
            return c.count == 1 ? make((c[0], c[0], c[0])) : nil
        case "cmyk":
            let c = components(spec)
            guard c.count == 4 else { return nil }
            return make(((1 - c[0]) * (1 - c[3]), (1 - c[1]) * (1 - c[3]), (1 - c[2]) * (1 - c[3])))
        default:
            return nil
        }
    }

    /// `red!30` = 30% red + 70% white; `red!30!blue` = 30% red + 70% blue.
    private static func mix(_ spec: String) -> CGColor? {
        let parts = spec.split(separator: "!").map(String.init)
        guard let first = parts.first, var current = named[first.lowercased()] else { return nil }
        var i = 1
        while i < parts.count {
            guard let pct = Double(parts[i]) else { return nil }
            let other = i + 1 < parts.count ? named[parts[i + 1].lowercased()] ?? (1, 1, 1) : (1, 1, 1)
            let t = CGFloat(max(0, min(100, pct))) / 100
            current = (current.0 * t + other.0 * (1 - t), current.1 * t + other.1 * (1 - t), current.2 * t + other.2 * (1 - t))
            i += 2
        }
        return make(current)
    }
}
