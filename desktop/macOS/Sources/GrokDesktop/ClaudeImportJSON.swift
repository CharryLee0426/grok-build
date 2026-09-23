import Foundation

/// A JSON value that keeps object keys in document order, as the terminal's `serde_json` (built with
/// `preserve_order`) does, so imported items and rewritten hook files keep the order the user wrote.
indirect enum ClaudeJSON: Equatable {
    case null
    case bool(Bool)
    /// The number's text, kept verbatim so values round-trip unchanged.
    case number(String)
    case string(String)
    case array([ClaudeJSON])
    case object([(key: String, value: ClaudeJSON)])

    static func == (lhs: ClaudeJSON, rhs: ClaudeJSON) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case let (.bool(a), .bool(b)): return a == b
        case let (.number(a), .number(b)): return a == b
        case let (.string(a), .string(b)): return a == b
        case let (.array(a), .array(b)): return a == b
        case let (.object(a), .object(b)): return a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default: return false
        }
    }

    // MARK: Access

    /// The value for `key` in an object (the last one wins when a key repeats, as in `serde_json`).
    subscript(key: String) -> ClaudeJSON? {
        guard case .object(let pairs) = self else { return nil }
        return pairs.last { $0.key == key }?.value
    }

    /// An object's entries with repeated keys collapsed: first position, last value.
    var objectEntries: [(key: String, value: ClaudeJSON)]? {
        guard case .object(let pairs) = self else { return nil }
        var result: [(key: String, value: ClaudeJSON)] = []
        var positions: [String: Int] = [:]
        for pair in pairs {
            if let index = positions[pair.key] { result[index].value = pair.value }
            else { positions[pair.key] = result.count; result.append(pair) }
        }
        return result
    }

    var stringValue: String? { if case .string(let value) = self { return value }; return nil }
    var boolValue: Bool? { if case .bool(let value) = self { return value }; return nil }
    var arrayValue: [ClaudeJSON]? { if case .array(let value) = self { return value }; return nil }
    var isNull: Bool { self == .null }

    /// A non-negative integer that fits `u64`, as `serde_json`'s `as_u64` accepts.
    var uint64Value: UInt64? {
        guard case .number(let text) = self, !text.contains(where: { ".eE-+".contains($0) }) else { return nil }
        return UInt64(text)
    }

    // MARK: Parsing

    struct SyntaxError: Error, CustomStringConvertible {
        let message: String
        let offset: Int
        var description: String { "\(message) at byte \(offset)" }
    }

    static func parse(_ data: Data) throws -> ClaudeJSON {
        var parser = Parser(bytes: [UInt8](data))
        parser.skipWhitespace()
        let value = try parser.value(depth: 0)
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else { throw SyntaxError(message: "trailing characters", offset: parser.index) }
        return value
    }

    static func parse(_ text: String) throws -> ClaudeJSON { try parse(Data(text.utf8)) }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        init(bytes: [UInt8]) { self.bytes = bytes }

        mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        func fail(_ message: String) -> SyntaxError { SyntaxError(message: message, offset: index) }

        mutating func expect(_ literal: String) throws {
            for byte in literal.utf8 {
                guard index < bytes.count, bytes[index] == byte else { throw fail("expected \(literal)") }
                index += 1
            }
        }

        mutating func value(depth: Int) throws -> ClaudeJSON {
            guard depth < 128 else { throw fail("recursion limit exceeded") }
            guard index < bytes.count else { throw fail("EOF while parsing a value") }
            switch bytes[index] {
            case UInt8(ascii: "{"):
                index += 1
                var pairs: [(key: String, value: ClaudeJSON)] = []
                skipWhitespace()
                if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(pairs) }
                while true {
                    skipWhitespace()
                    guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw fail("key must be a string") }
                    let key = try string()
                    skipWhitespace()
                    try expect(":")
                    skipWhitespace()
                    pairs.append((key, try value(depth: depth + 1)))
                    skipWhitespace()
                    guard index < bytes.count else { throw fail("EOF while parsing an object") }
                    if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                    if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(pairs) }
                    throw fail("expected `,` or `}`")
                }
            case UInt8(ascii: "["):
                index += 1
                var items: [ClaudeJSON] = []
                skipWhitespace()
                if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
                while true {
                    skipWhitespace()
                    items.append(try value(depth: depth + 1))
                    skipWhitespace()
                    guard index < bytes.count else { throw fail("EOF while parsing a list") }
                    if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                    if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
                    throw fail("expected `,` or `]`")
                }
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try expect("true"); return .bool(true)
            case UInt8(ascii: "f"): try expect("false"); return .bool(false)
            case UInt8(ascii: "n"): try expect("null"); return .null
            default: return .number(try number())
            }
        }

        mutating func number() throws -> String {
            let start = index
            func digits() -> Int {
                let begin = index
                while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) { index += 1 }
                return index - begin
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "-") { index += 1 }
            guard index < bytes.count else { throw fail("invalid number") }
            if bytes[index] == UInt8(ascii: "0") { index += 1 } else if digits() == 0 { throw fail("expected value") }
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                index += 1
                guard digits() > 0 else { throw fail("invalid number") }
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
                index += 1
                if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
                guard digits() > 0 else { throw fail("invalid number") }
            }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }

        mutating func hex4() throws -> UInt32 {
            guard index + 4 <= bytes.count, let value = UInt32(String(decoding: bytes[index..<index + 4], as: UTF8.self), radix: 16) else {
                throw fail("invalid escape")
            }
            index += 4
            return value
        }

        mutating func string() throws -> String {
            index += 1
            var scalars = String.UnicodeScalarView()
            var chunkStart = index
            func flush(_ end: Int) { scalars.append(contentsOf: String(decoding: bytes[chunkStart..<end], as: UTF8.self).unicodeScalars) }
            while true {
                guard index < bytes.count else { throw fail("EOF while parsing a string") }
                let byte = bytes[index]
                if byte == UInt8(ascii: "\"") { flush(index); index += 1; return String(scalars) }
                if byte < 0x20 { throw fail("control character in string") }
                if byte != UInt8(ascii: "\\") { index += 1; continue }
                flush(index)
                index += 1
                guard index < bytes.count else { throw fail("EOF while parsing a string") }
                let escape = bytes[index]
                index += 1
                switch escape {
                case UInt8(ascii: "\""): scalars.append("\"")
                case UInt8(ascii: "\\"): scalars.append("\\")
                case UInt8(ascii: "/"): scalars.append("/")
                case UInt8(ascii: "b"): scalars.append("\u{08}")
                case UInt8(ascii: "f"): scalars.append("\u{0C}")
                case UInt8(ascii: "n"): scalars.append("\n")
                case UInt8(ascii: "r"): scalars.append("\r")
                case UInt8(ascii: "t"): scalars.append("\t")
                case UInt8(ascii: "u"):
                    var code = try hex4()
                    if (0xD800..<0xDC00).contains(code) {
                        // A high surrogate must pair with a low one.
                        guard index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") else { throw fail("lone leading surrogate") }
                        index += 2
                        let low = try hex4()
                        guard (0xDC00..<0xE000).contains(low) else { throw fail("invalid surrogate pair") }
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    }
                    guard let scalar = Unicode.Scalar(code) else { throw fail("invalid unicode code point") }
                    scalars.append(scalar)
                default: throw fail("invalid escape")
                }
                chunkStart = index
            }
        }
    }

    // MARK: Printing

    /// Pretty-printed like `serde_json::to_string_pretty`: two-space indent, `"key": value`, no trailing newline.
    var prettyPrinted: String {
        var output = ""
        write(to: &output, indent: 0)
        return output
    }

    private func write(to output: inout String, indent: Int) {
        let pad = String(repeating: "  ", count: indent + 1), closing = String(repeating: "  ", count: indent)
        switch self {
        case .null: output += "null"
        case .bool(let value): output += value ? "true" : "false"
        case .number(let text): output += text
        case .string(let value): output += Self.quote(value)
        case .array(let items):
            guard !items.isEmpty else { output += "[]"; return }
            output += "[\n"
            for (index, item) in items.enumerated() {
                output += pad
                item.write(to: &output, indent: indent + 1)
                output += index == items.count - 1 ? "\n" : ",\n"
            }
            output += closing + "]"
        case .object:
            let pairs = objectEntries ?? []
            guard !pairs.isEmpty else { output += "{}"; return }
            output += "{\n"
            for (index, pair) in pairs.enumerated() {
                output += pad + Self.quote(pair.key) + ": "
                pair.value.write(to: &output, indent: indent + 1)
                output += index == pairs.count - 1 ? "\n" : ",\n"
            }
            output += closing + "}"
        }
    }

    /// A JSON string literal escaped the way `serde_json` does it.
    static func quote(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            default:
                if scalar.value < 0x20 { result += String(format: "\\u%04x", scalar.value) }
                else { result.unicodeScalars.append(scalar) }
            }
        }
        return result + "\""
    }
}
