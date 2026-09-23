import Foundation

/// Byte-level character classification helpers (the parser works on UTF-8 bytes).
enum MarkdownChar {
    static let space: UInt8 = 0x20
    static let tab: UInt8 = 0x09
    static let newline: UInt8 = 0x0A
    static let carriageReturn: UInt8 = 0x0D
    static let backslash: UInt8 = 0x5C
    static let backtick: UInt8 = 0x60
    static let dollar: UInt8 = 0x24

    enum Class { case whitespace, punctuation, other }

    @inline(__always) static func isSpaceOrTab(_ c: UInt8) -> Bool { c == 0x20 || c == 0x09 }

    @inline(__always) static func isWhitespace(_ c: UInt8) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C || c == 0x0B
    }

    @inline(__always) static func isDigit(_ c: UInt8) -> Bool { c >= 0x30 && c <= 0x39 }

    @inline(__always) static func isLetter(_ c: UInt8) -> Bool {
        (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
    }

    @inline(__always) static func isAlphanumeric(_ c: UInt8) -> Bool { isLetter(c) || isDigit(c) }

    @inline(__always) static func isHexDigit(_ c: UInt8) -> Bool {
        isDigit(c) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66)
    }

    @inline(__always) static func lowercased(_ c: UInt8) -> UInt8 {
        (c >= 0x41 && c <= 0x5A) ? c + 32 : c
    }

    /// ASCII punctuation as defined by CommonMark (escapable characters).
    @inline(__always) static func isASCIIPunctuation(_ c: UInt8) -> Bool {
        (c >= 0x21 && c <= 0x2F) || (c >= 0x3A && c <= 0x40) || (c >= 0x5B && c <= 0x60) || (c >= 0x7B && c <= 0x7E)
    }

    /// Decodes the scalar starting at `i` (lenient: invalid sequences yield U+FFFD, length 1).
    static func scalar(in s: [UInt8], at i: Int) -> (value: UInt32, length: Int) {
        let b0 = s[i]
        if b0 < 0x80 { return (UInt32(b0), 1) }
        let n = s.count
        func cont(_ k: Int) -> UInt32? {
            guard i + k < n else { return nil }
            let b = s[i + k]
            return (b & 0xC0) == 0x80 ? UInt32(b & 0x3F) : nil
        }
        if b0 & 0xE0 == 0xC0, let c1 = cont(1) { return ((UInt32(b0 & 0x1F) << 6) | c1, 2) }
        if b0 & 0xF0 == 0xE0, let c1 = cont(1), let c2 = cont(2) {
            return ((UInt32(b0 & 0x0F) << 12) | (c1 << 6) | c2, 3)
        }
        if b0 & 0xF8 == 0xF0, let c1 = cont(1), let c2 = cont(2), let c3 = cont(3) {
            return ((UInt32(b0 & 0x07) << 18) | (c1 << 12) | (c2 << 6) | c3, 4)
        }
        return (0xFFFD, 1)
    }

    /// Classifies the character that ends right before byte index `i` (start of input counts as whitespace).
    static func classBefore(_ s: [UInt8], _ i: Int) -> Class {
        guard i > 0 else { return .whitespace }
        let b = s[i - 1]
        if b < 0x80 { return asciiClass(b) }
        var j = i - 1
        while j > 0 && (s[j] & 0xC0) == 0x80 && i - j < 4 { j -= 1 }
        return scalarClass(scalar(in: s, at: j).value)
    }

    /// Classifies the character starting at byte index `i` (end of input counts as whitespace).
    static func classAt(_ s: [UInt8], _ i: Int) -> Class {
        guard i < s.count else { return .whitespace }
        let b = s[i]
        if b < 0x80 { return asciiClass(b) }
        return scalarClass(scalar(in: s, at: i).value)
    }

    @inline(__always) static func asciiClass(_ b: UInt8) -> Class {
        if isWhitespace(b) { return .whitespace }
        if isASCIIPunctuation(b) { return .punctuation }
        return .other
    }

    static func scalarClass(_ v: UInt32) -> Class {
        guard let scalar = Unicode.Scalar(v) else { return .other }
        switch scalar.properties.generalCategory {
        case .spaceSeparator:
            return .whitespace
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation,
             .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            return .punctuation
        default:
            return .other
        }
    }

    /// Number of UTF-16 code units encoded by `s[from..<to]`.
    @inline(__always) static func utf16Count(_ s: [UInt8], _ from: Int, _ to: Int) -> Int {
        var count = 0
        var i = from
        while i < to {
            let b = s[i]
            if b & 0xC0 != 0x80 { count += b >= 0xF0 ? 2 : 1 }
            i += 1
        }
        return count
    }

    @inline(__always) static func string(_ s: ArraySlice<UInt8>) -> String {
        String(decoding: s, as: UTF8.self)
    }

    @inline(__always) static func string(_ s: [UInt8]) -> String {
        String(decoding: s, as: UTF8.self)
    }

    /// Returns `s[from..<to]` narrowed to exclude leading/trailing whitespace.
    static func trimmedRange(_ s: [UInt8], _ from: Int, _ to: Int) -> Range<Int> {
        var a = from, b = to
        while a < b && isWhitespace(s[a]) { a += 1 }
        while b > a && isWhitespace(s[b - 1]) { b -= 1 }
        return a..<b
    }

    /// Case-insensitive ASCII comparison of `s[at...]` with a lowercase literal.
    static func matches(_ s: [UInt8], at: Int, lowercase literal: StaticString) -> Bool {
        let count = literal.utf8CodeUnitCount
        guard at + count <= s.count else { return false }
        return literal.withUTF8Buffer { lit in
            for k in 0..<count where lowercased(s[at + k]) != lit[k] { return false }
            return true
        }
    }

    /// Resolves backslash escapes and entity references (used for link destinations,
    /// titles and info strings).
    static func unescape(_ s: ArraySlice<UInt8>) -> String {
        if !s.contains(where: { $0 == backslash || $0 == 0x26 }) { return string(s) }
        let bytes = Array(s)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var i = 0
        while i < bytes.count {
            let c = bytes[i]
            if c == backslash, i + 1 < bytes.count, isASCIIPunctuation(bytes[i + 1]) {
                out.append(bytes[i + 1])
                i += 2
            } else if c == 0x26, let (decoded, length) = MarkdownEntities.decode(bytes, at: i) {
                out.append(contentsOf: decoded)
                i += length
            } else {
                out.append(c)
                i += 1
            }
        }
        return string(out)
    }

    /// Normalizes a link label for reference matching: trim, collapse whitespace, case-fold.
    static func normalizeLabel(_ s: ArraySlice<UInt8>) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(s.count)
        var pendingSpace = false
        for c in s {
            if isWhitespace(c) {
                pendingSpace = !out.isEmpty
            } else {
                if pendingSpace { out.append(space); pendingSpace = false }
                out.append(c)
            }
        }
        let str = string(out)
        return str.lowercased().uppercased()
    }
}
