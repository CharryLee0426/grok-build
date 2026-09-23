import Foundation

/// HTML entity references: numeric (`&#123;`, `&#x1F600;`) and a table of common named ones.
enum MarkdownEntities {
    /// Decodes an entity starting at `s[i] == "&"`; returns the UTF-8 bytes and the consumed length.
    static func decode(_ s: [UInt8], at i: Int) -> (bytes: [UInt8], length: Int)? {
        let n = s.count
        guard i + 2 < n, s[i] == 0x26 else { return nil }
        var j = i + 1
        if s[j] == 0x23 { // '#'
            j += 1
            var value: UInt32 = 0
            var digits = 0
            if j < n, s[j] == 0x78 || s[j] == 0x58 { // hex
                j += 1
                while j < n, MarkdownChar.isHexDigit(s[j]), digits < 6 {
                    let c = s[j]
                    let d: UInt32 = MarkdownChar.isDigit(c) ? UInt32(c - 0x30) : UInt32(MarkdownChar.lowercased(c) - 0x61 + 10)
                    value = value * 16 + d
                    digits += 1
                    j += 1
                }
            } else {
                while j < n, MarkdownChar.isDigit(s[j]), digits < 7 {
                    value = value * 10 + UInt32(s[j] - 0x30)
                    digits += 1
                    j += 1
                }
            }
            guard digits > 0, j < n, s[j] == 0x3B else { return nil }
            let scalar = (value == 0 ? nil : Unicode.Scalar(value)) ?? Unicode.Scalar(0xFFFD)!
            return (Array(String(Character(scalar)).utf8), j + 1 - i)
        }
        let start = j
        while j < n, MarkdownChar.isAlphanumeric(s[j]), j - start < 32 { j += 1 }
        guard j > start, j < n, s[j] == 0x3B else { return nil }
        let name = MarkdownChar.string(s[start..<j])
        guard let value = named[name] else { return nil }
        return (Array(value.utf8), j + 1 - i)
    }

    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "copy": "©", "reg": "®", "trade": "™", "hellip": "…", "mdash": "—", "ndash": "–",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "sbquo": "‚", "bdquo": "„",
        "laquo": "«", "raquo": "»", "lsaquo": "‹", "rsaquo": "›", "bull": "•", "middot": "·",
        "deg": "°", "plusmn": "±", "times": "×", "divide": "÷", "micro": "µ", "para": "¶",
        "sect": "§", "cent": "¢", "pound": "£", "euro": "€", "yen": "¥", "curren": "¤",
        "iexcl": "¡", "iquest": "¿", "shy": "\u{00AD}", "ensp": "\u{2002}", "emsp": "\u{2003}",
        "thinsp": "\u{2009}", "zwj": "\u{200D}", "zwnj": "\u{200C}", "lrm": "\u{200E}", "rlm": "\u{200F}",
        "dagger": "†", "Dagger": "‡", "permil": "‰", "prime": "′", "Prime": "″", "oline": "‾",
        "frasl": "⁄", "frac12": "½", "frac14": "¼", "frac34": "¾", "sup1": "¹", "sup2": "²", "sup3": "³",
        "ordf": "ª", "ordm": "º", "not": "¬", "macr": "¯", "acute": "´", "cedil": "¸", "uml": "¨",
        "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓", "harr": "↔", "crarr": "↵",
        "lArr": "⇐", "rArr": "⇒", "uArr": "⇑", "dArr": "⇓", "hArr": "⇔",
        "le": "≤", "ge": "≥", "ne": "≠", "asymp": "≈", "equiv": "≡", "infin": "∞", "sum": "∑",
        "prod": "∏", "radic": "√", "part": "∂", "nabla": "∇", "isin": "∈", "notin": "∉", "ni": "∋",
        "cap": "∩", "cup": "∪", "sub": "⊂", "sup": "⊃", "sube": "⊆", "supe": "⊇", "and": "∧", "or": "∨",
        "forall": "∀", "exist": "∃", "empty": "∅", "minus": "−", "lowast": "∗", "prop": "∝",
        "ang": "∠", "int": "∫", "there4": "∴", "sim": "∼", "cong": "≅", "perp": "⊥", "sdot": "⋅",
        "lceil": "⌈", "rceil": "⌉", "lfloor": "⌊", "rfloor": "⌋", "loz": "◊",
        "spades": "♠", "clubs": "♣", "hearts": "♥", "diams": "♦", "check": "✓", "cross": "✗", "star": "☆",
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "zeta": "ζ", "eta": "η",
        "theta": "θ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ",
        "omicron": "ο", "pi": "π", "rho": "ρ", "sigma": "σ", "sigmaf": "ς", "tau": "τ", "upsilon": "υ",
        "phi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Alpha": "Α", "Beta": "Β", "Gamma": "Γ", "Delta": "Δ", "Epsilon": "Ε", "Zeta": "Ζ", "Eta": "Η",
        "Theta": "Θ", "Iota": "Ι", "Kappa": "Κ", "Lambda": "Λ", "Mu": "Μ", "Nu": "Ν", "Xi": "Ξ",
        "Omicron": "Ο", "Pi": "Π", "Rho": "Ρ", "Sigma": "Σ", "Tau": "Τ", "Upsilon": "Υ", "Phi": "Φ",
        "Chi": "Χ", "Psi": "Ψ", "Omega": "Ω",
        "Agrave": "À", "Aacute": "Á", "Acirc": "Â", "Atilde": "Ã", "Auml": "Ä", "Aring": "Å", "AElig": "Æ",
        "Ccedil": "Ç", "Egrave": "È", "Eacute": "É", "Ecirc": "Ê", "Euml": "Ë", "Igrave": "Ì", "Iacute": "Í",
        "Icirc": "Î", "Iuml": "Ï", "Ntilde": "Ñ", "Ograve": "Ò", "Oacute": "Ó", "Ocirc": "Ô", "Otilde": "Õ",
        "Ouml": "Ö", "Oslash": "Ø", "Ugrave": "Ù", "Uacute": "Ú", "Ucirc": "Û", "Uuml": "Ü", "Yacute": "Ý",
        "szlig": "ß", "agrave": "à", "aacute": "á", "acirc": "â", "atilde": "ã", "auml": "ä", "aring": "å",
        "aelig": "æ", "ccedil": "ç", "egrave": "è", "eacute": "é", "ecirc": "ê", "euml": "ë", "igrave": "ì",
        "iacute": "í", "icirc": "î", "iuml": "ï", "ntilde": "ñ", "ograve": "ò", "oacute": "ó", "ocirc": "ô",
        "otilde": "õ", "ouml": "ö", "oslash": "ø", "ugrave": "ù", "uacute": "ú", "ucirc": "û", "uuml": "ü",
        "yacute": "ý", "yuml": "ÿ", "eth": "ð", "thorn": "þ", "ETH": "Ð", "THORN": "Þ",
        "OElig": "Œ", "oelig": "œ", "Scaron": "Š", "scaron": "š", "Yuml": "Ÿ", "fnof": "ƒ",
        "circ": "ˆ", "tilde": "˜", "brvbar": "¦",
    ]
}
