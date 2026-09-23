import Foundation

/// Math letter styles (`\mathbf`, `\mathbb`, …). `.normal` is TeX's default math
/// font: italic Latin and lowercase Greek, upright digits and uppercase Greek.
enum MathFontStyle: Equatable {
    case normal
    case roman
    case italic
    case bold
    case boldItalic
    /// `\boldsymbol` / `\bm`: bold version of the *normal* style.
    case boldSymbol
    /// `\mathcal`: the font's default (chancery) script letters.
    case script
    /// `\mathscr`: script letters with the roundhand stylistic alternates.
    case roundhandScript
    case boldScript
    case fraktur
    case boldFraktur
    case doubleStruck
    case sansSerif
    case sansSerifBold
    case sansSerifItalic
    case sansSerifBoldItalic
    case monospace
}

/// Maps ASCII letters, digits and Greek to the Unicode Mathematical Alphanumeric
/// Symbols block (U+1D400…), including the holes that were encoded earlier in the
/// Letterlike Symbols block (ℎ, ℬ, ℂ, …).
enum MathAlphabet {
    /// Flag bit on a mapped code point asking the typesetter for the roundhand
    /// (`ss01`) alternate glyph. Unicode has no separate code points for it.
    static let roundhandFlag: UInt32 = 0x0100_0000
    private static let scriptExceptions: [UInt32: UInt32] = [
        0x42: 0x212C, 0x45: 0x2130, 0x46: 0x2131, 0x48: 0x210B, 0x49: 0x2110,
        0x4C: 0x2112, 0x4D: 0x2133, 0x52: 0x211B,
        0x65: 0x212F, 0x67: 0x210A, 0x6F: 0x2134,
    ]
    private static let frakturExceptions: [UInt32: UInt32] = [
        0x43: 0x212D, 0x48: 0x210C, 0x49: 0x2111, 0x52: 0x211C, 0x5A: 0x2128,
    ]
    private static let doubleStruckExceptions: [UInt32: UInt32] = [
        0x43: 0x2102, 0x48: 0x210D, 0x4E: 0x2115, 0x50: 0x2119, 0x51: 0x211A,
        0x52: 0x211D, 0x5A: 0x2124,
    ]

    /// Index of an uppercase Greek letter (or ∇) within a math Greek alphabet.
    private static func upperGreekIndex(_ c: UInt32) -> UInt32? {
        switch c {
        case 0x391...0x3A9: return c - 0x391
        case 0x3F4: return 17  // ϴ
        case 0x2207: return 25  // ∇
        default: return nil
        }
    }

    /// Index of a lowercase Greek letter (or ∂ and the "var" forms) within the block.
    private static func lowerGreekIndex(_ c: UInt32) -> UInt32? {
        switch c {
        case 0x3B1...0x3C9: return c - 0x3B1
        case 0x2202: return 25  // ∂
        case 0x3F5: return 26  // ϵ
        case 0x3D1: return 27  // ϑ
        case 0x3F0: return 28  // ϰ
        case 0x3D5: return 29  // ϕ
        case 0x3F1: return 30  // ϱ
        case 0x3D6: return 31  // ϖ
        default: return nil
        }
    }

    static func isLatinLetter(_ c: UInt32) -> Bool {
        (0x41...0x5A).contains(c) || (0x61...0x7A).contains(c)
    }

    static func isGreek(_ c: UInt32) -> Bool {
        upperGreekIndex(c) != nil || lowerGreekIndex(c) != nil
    }

    private static func latin(_ c: UInt32, upper: UInt32, lower: UInt32, exceptions: [UInt32: UInt32] = [:]) -> UInt32? {
        if let e = exceptions[c] { return e }
        if (0x41...0x5A).contains(c) { return upper + (c - 0x41) }
        if (0x61...0x7A).contains(c) { return lower + (c - 0x61) }
        return nil
    }

    private static func digit(_ c: UInt32, base: UInt32) -> UInt32? {
        (0x30...0x39).contains(c) ? base + (c - 0x30) : nil
    }

    private static func greek(_ c: UInt32, upper: UInt32?, lower: UInt32?) -> UInt32? {
        if let i = upperGreekIndex(c), let u = upper { return u + i }
        if let i = lowerGreekIndex(c), let l = lower { return l + i }
        return nil
    }

    /// Returns the styled code point for `c`, or `c` itself when the style has no
    /// variant for it.
    static func map(_ c: UInt32, style: MathFontStyle) -> UInt32 {
        switch style {
        case .normal:
            if c == 0x68 { return 0x210E }  // Planck constant ℎ fills the italic-h hole
            if c == 0x131 { return 0x1D6A4 }  // dotless ı → 𝚤
            if c == 0x237 { return 0x1D6A5 }  // dotless ȷ → 𝚥
            if let v = latin(c, upper: 0x1D434, lower: 0x1D44E) { return v }
            if let v = greek(c, upper: nil, lower: 0x1D6FC) { return v }
            return c
        case .roman:
            return c
        case .italic:
            if c == 0x68 { return 0x210E }
            if let v = latin(c, upper: 0x1D434, lower: 0x1D44E) { return v }
            if let v = greek(c, upper: 0x1D6E2, lower: 0x1D6FC) { return v }
            return c
        case .bold:
            if let v = latin(c, upper: 0x1D400, lower: 0x1D41A) { return v }
            if let v = digit(c, base: 0x1D7CE) { return v }
            if let v = greek(c, upper: 0x1D6A8, lower: 0x1D6C2) { return v }
            return c
        case .boldItalic:
            if let v = latin(c, upper: 0x1D468, lower: 0x1D482) { return v }
            if let v = digit(c, base: 0x1D7CE) { return v }
            if let v = greek(c, upper: 0x1D71C, lower: 0x1D736) { return v }
            return c
        case .boldSymbol:
            if let v = latin(c, upper: 0x1D468, lower: 0x1D482) { return v }
            if let v = digit(c, base: 0x1D7CE) { return v }
            if let v = greek(c, upper: 0x1D6A8, lower: 0x1D736) { return v }
            return c
        case .script:
            return latin(c, upper: 0x1D49C, lower: 0x1D4B6, exceptions: scriptExceptions) ?? c
        case .roundhandScript:
            return latin(c, upper: 0x1D49C, lower: 0x1D4B6, exceptions: scriptExceptions).map { $0 | roundhandFlag } ?? c
        case .boldScript:
            return latin(c, upper: 0x1D4D0, lower: 0x1D4EA) ?? c
        case .fraktur:
            return latin(c, upper: 0x1D504, lower: 0x1D51E, exceptions: frakturExceptions) ?? c
        case .boldFraktur:
            return latin(c, upper: 0x1D56C, lower: 0x1D586) ?? c
        case .doubleStruck:
            if let v = latin(c, upper: 0x1D538, lower: 0x1D552, exceptions: doubleStruckExceptions) { return v }
            return digit(c, base: 0x1D7D8) ?? c
        case .sansSerif:
            if let v = latin(c, upper: 0x1D5A0, lower: 0x1D5BA) { return v }
            return digit(c, base: 0x1D7E2) ?? c
        case .sansSerifBold:
            if let v = latin(c, upper: 0x1D5D4, lower: 0x1D5EE) { return v }
            if let v = digit(c, base: 0x1D7EC) { return v }
            return greek(c, upper: 0x1D756, lower: 0x1D770) ?? c
        case .sansSerifItalic:
            return latin(c, upper: 0x1D608, lower: 0x1D622) ?? c
        case .sansSerifBoldItalic:
            if let v = latin(c, upper: 0x1D63C, lower: 0x1D656) { return v }
            return greek(c, upper: 0x1D790, lower: 0x1D7AA) ?? c
        case .monospace:
            if let v = latin(c, upper: 0x1D670, lower: 0x1D68A) { return v }
            return digit(c, base: 0x1D7F6) ?? c
        }
    }
}
