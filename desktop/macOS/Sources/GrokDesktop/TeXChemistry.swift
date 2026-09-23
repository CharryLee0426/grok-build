import Foundation

/// Translates mhchem's `\ce{…}` / `\pu{…}` notation into plain LaTeX math.
enum TeXChemistry {
    /// A small subset of mhchem's `\ce{…}`: upright element symbols, digits after an
    /// element or group become subscripts, charges (`^{2-}`, `H+`, `Ca2+`), reaction
    /// arrows, `+`, `*` (·) and state symbols like `(aq)`.
    static func latex(from raw: String) -> String {
        let chars = Array(raw)
        var out = ""
        var i = 0
        var afterFormulaPart = false  // an element, ) or ] was just emitted
        let arrows: [(String, String)] = [("<=>", "\\rightleftharpoons"), ("<->", "\\leftrightarrow"),
                                          ("->", "\\rightarrow"), ("<-", "\\leftarrow")]
        func hasPrefix(_ p: String) -> Bool {
            let pc = Array(p)
            return i + pc.count <= chars.count && Array(chars[i..<i + pc.count]) == pc
        }
        /// A `+`/`-` at index j ends a species (so it is a charge, not an operator).
        func isChargeSign(at j: Int) -> Bool {
            guard j < chars.count, chars[j] == "+" || chars[j] == "-" else { return false }
            if chars[j] == "-", j + 1 < chars.count, chars[j + 1] == ">" { return false }
            return j + 1 >= chars.count || chars[j + 1] == " " || chars[j + 1] == ")" || chars[j + 1] == "]"
        }
        outer: while i < chars.count {
            let c = chars[i]
            for (token, command) in arrows where hasPrefix(token) {
                out += "\\mathrel{" + command + "}"
                i += token.count
                afterFormulaPart = false
                continue outer
            }
            if c.isLetter, c.isUppercase {
                var element = String(c)
                i += 1
                while i < chars.count, chars[i].isLetter, chars[i].isLowercase {
                    element.append(chars[i])
                    i += 1
                }
                out += "\\mathrm{" + element + "}"
                afterFormulaPart = true
            } else if c.isNumber {
                var number = ""
                while i < chars.count, chars[i].isNumber || chars[i] == "." {
                    number.append(chars[i])
                    i += 1
                }
                if afterFormulaPart, isChargeSign(at: i) {
                    out += "^{" + number + String(chars[i]) + "}"
                    i += 1
                } else {
                    out += afterFormulaPart ? "_{" + number + "}" : number
                }
            } else if c == "^" {
                i += 1
                var charge = ""
                if i < chars.count, chars[i] == "{" {
                    i += 1
                    while i < chars.count, chars[i] != "}" {
                        charge.append(chars[i])
                        i += 1
                    }
                    i += 1
                } else {
                    while i < chars.count, chars[i].isNumber || chars[i] == "+" || chars[i] == "-" {
                        charge.append(chars[i])
                        i += 1
                    }
                }
                out += "^{" + charge + "}"
                afterFormulaPart = false
            } else if (c == "+" || c == "-"), afterFormulaPart, isChargeSign(at: i) {
                out += "^{" + String(c) + "}"
                i += 1
                afterFormulaPart = false
            } else if c == ")" || c == "]" {
                out.append(c)
                i += 1
                afterFormulaPart = true
            } else if c == "(" {
                // State symbols like (aq), (s), (g) stay upright.
                var j = i + 1
                var inner = ""
                while j < chars.count, chars[j].isLowercase {
                    inner.append(chars[j])
                    j += 1
                }
                if j < chars.count, chars[j] == ")", !inner.isEmpty {
                    out += "(\\mathrm{" + inner + "})"
                    i = j + 1
                } else {
                    out.append(c)
                    i += 1
                }
                afterFormulaPart = false
            } else if c == "*" || c == "." {
                out += "\\cdot "
                i += 1
                afterFormulaPart = false
            } else if c == "\\" {
                // Pass LaTeX commands (\Delta, \alpha, …) through untouched.
                var command = "\\"
                i += 1
                while i < chars.count, chars[i].isLetter {
                    command.append(chars[i])
                    i += 1
                }
                out += command + " "
                afterFormulaPart = false
            } else {
                if c != " " { out.append(c) }
                i += 1
                afterFormulaPart = false
            }
        }
        return out
    }
}
