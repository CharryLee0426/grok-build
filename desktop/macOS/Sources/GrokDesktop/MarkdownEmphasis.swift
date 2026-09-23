import Foundation

extension MarkdownInlineParser {
    /// Resolves emphasis/strong/strikethrough delimiters in `tokens` (CommonMark "process
    /// emphasis") and returns the finished inlines with adjacent text merged.
    ///
    /// Implemented as a left-to-right scan with a stack of potential openers: when a closer
    /// finds a matching opener, everything emitted after the opener becomes the children of
    /// the new node and the openers above it turn into literal text.
    /// Emphasis is not nested deeper than this (pathological input like `*a *a *a …`).
    static let maxInlineDepth = 32

    static func depth(of inline: MarkdownInline) -> Int {
        switch inline {
        case .emphasis(let c), .strong(let c), .strikethrough(let c), .link(_, _, let c):
            var d = 0
            for child in c { d = max(d, depth(of: child)) }
            return d + 1
        default:
            return 0
        }
    }

    static func resolve(_ tokens: ArraySlice<Token>) -> [MarkdownInline] {
        struct Opener {
            let char: UInt8
            var count: Int
            let original: Int
            let canClose: Bool
            let outIndex: Int
        }
        enum Out {
            case inline(MarkdownInline, depth: Int)
            case opener(Int)
        }

        // Fast path: no delimiters at all.
        if !tokens.contains(where: { if case .delimiter = $0 { return true } else { return false } }) {
            var out: [MarkdownInline] = []
            out.reserveCapacity(tokens.count)
            var text: String?
            for token in tokens {
                switch token {
                case .text(let t): text = (text ?? "") + t
                case .bracket(let image): text = (text ?? "") + (image ? "![" : "[")
                case .node(let node):
                    if let t = text { out.append(.text(t)); text = nil }
                    out.append(node)
                case .delimiter: break
                }
            }
            if let t = text { out.append(.text(t)) }
            return out
        }

        var out: [Out] = []
        out.reserveCapacity(tokens.count)
        var openers: [Opener] = []
        var stack: [Int] = []
        // openers_bottom per (delimiter char, closer can-open, closer length % 3), as stack heights.
        var bottoms = [Int](repeating: 0, count: 18)

        func materialize(_ entries: ArraySlice<Out>) -> [MarkdownInline] {
            var result: [MarkdownInline] = []
            result.reserveCapacity(entries.count)
            var text: String?
            for entry in entries {
                switch entry {
                case .inline(.text(let t), _):
                    text = (text ?? "") + t
                case .inline(let node, _):
                    if let t = text { result.append(.text(t)); text = nil }
                    result.append(node)
                case .opener(let index):
                    let o = openers[index]
                    text = (text ?? "") + String(repeating: Character(Unicode.Scalar(o.char)), count: o.count)
                }
            }
            if let t = text { result.append(.text(t)) }
            return result
        }

        func clampBottoms() {
            let height = stack.count
            for i in bottoms.indices where bottoms[i] > height { bottoms[i] = height }
        }

        for token in tokens {
            switch token {
            case .text(let t):
                out.append(.inline(.text(t), depth: 0))
            case .node(let node):
                out.append(.inline(node, depth: depth(of: node)))
            case .bracket(let image):
                out.append(.inline(.text(image ? "![" : "["), depth: 0))
            case .delimiter(let c, let originalCount, let canOpen, let canClose):
                var count = originalCount
                if canClose {
                    let charIndex = c == 0x2A ? 0 : (c == 0x5F ? 1 : 2)
                    let key = charIndex * 6 + (canOpen ? 3 : 0) + originalCount % 3
                    while count > 0 {
                        let bottom = min(bottoms[key], stack.count)
                        var found = -1
                        var k = stack.count - 1
                        while k >= bottom {
                            let o = openers[stack[k]]
                            if o.char == c {
                                if c == 0x7E {
                                    found = k
                                    break
                                }
                                // "Rule of 3" for runs that can both open and close.
                                let oddMatch = (o.canClose || canOpen) && (o.original + originalCount) % 3 == 0
                                    && !(o.original % 3 == 0 && originalCount % 3 == 0)
                                if !oddMatch {
                                    found = k
                                    break
                                }
                            }
                            k -= 1
                        }
                        var childDepth = 0
                        if found >= 0 {
                            for entry in out[(openers[stack[found]].outIndex + 1)...] {
                                if case .inline(_, let d) = entry, d > childDepth { childDepth = d }
                            }
                        }
                        if found < 0 || childDepth >= maxInlineDepth {
                            bottoms[key] = stack.count
                            break
                        }
                        let openerIndex = stack[found]
                        if found + 1 < stack.count {
                            stack.removeSubrange((found + 1)...)
                            clampBottoms()
                        }
                        let use = c == 0x7E ? 2 : (openers[openerIndex].count >= 2 && count >= 2 ? 2 : 1)
                        openers[openerIndex].count -= use
                        count -= use
                        let start = openers[openerIndex].outIndex + 1
                        let children = materialize(out[start...])
                        out.removeSubrange(start...)
                        let node: MarkdownInline
                        if c == 0x7E {
                            node = .strikethrough(children)
                        } else {
                            node = use == 2 ? .strong(children) : .emphasis(children)
                        }
                        if openers[openerIndex].count == 0 {
                            out.removeLast()
                            stack.removeLast()
                            clampBottoms()
                        }
                        out.append(.inline(node, depth: childDepth + 1))
                    }
                }
                if count > 0 {
                    if canOpen {
                        openers.append(Opener(char: c, count: count, original: originalCount, canClose: canClose, outIndex: out.count))
                        stack.append(openers.count - 1)
                        out.append(.opener(openers.count - 1))
                    } else {
                        out.append(.inline(.text(String(repeating: Character(Unicode.Scalar(c)), count: count)), depth: 0))
                    }
                }
            }
        }
        return materialize(out[...])
    }
}
