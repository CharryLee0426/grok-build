import Foundation

/// The persona fields the terminal's detail view shows and edits (`<scope>/personas/<name>.toml`).
struct PersonaFields: Equatable {
    var name = ""
    var description = ""
    var model = ""
    var reasoningEffort = ""
    var defaultIsolation = ""
    var instructions = ""
    var instructionsFile = ""
    var hasInputs = false
    var hasOutputs = false

    /// TOML key for each editable field, in the order they are written.
    static let keys: [(String, WritableKeyPath<PersonaFields, String>)] = [
        ("name", \.name), ("description", \.description), ("instructions", \.instructions), ("instructions_file", \.instructionsFile),
        ("model", \.model), ("reasoning_effort", \.reasoningEffort), ("default_isolation", \.defaultIsolation),
    ]
}

enum PersonaScope: String, CaseIterable, Identifiable {
    case user, project
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum PersonaStoreError: LocalizedError, Equatable {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum PersonaStore {
    static func directory(_ scope: PersonaScope, cwd: URL, home: URL = GrokPaths.home) -> URL {
        scope == .user ? home.appendingPathComponent("personas", isDirectory: true) : cwd.appendingPathComponent(".grok/personas", isDirectory: true)
    }

    /// Letters, digits, `-`, and `_` are kept; anything else becomes `-`.
    static func sanitize(_ name: String) throws -> String {
        let allowed = CharacterSet.alphanumerics
        var result = ""
        for scalar in name.unicodeScalars {
            result.unicodeScalars.append(allowed.contains(scalar) || scalar == "-" || scalar == "_" ? scalar : "-")
        }
        guard result.unicodeScalars.contains(where: { allowed.contains($0) }) else {
            throw PersonaStoreError.message("Name must contain at least one alphanumeric character")
        }
        return result
    }

    /// "Create New Persona": description and instructions only, like the terminal's template.
    @discardableResult
    static func create(name: String, description: String, instructions: String, scope: PersonaScope, cwd: URL, home: URL = GrokPaths.home) throws -> URL {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PersonaStoreError.message("Name is required") }
        let sanitized = try sanitize(trimmed)
        let directory = directory(scope, cwd: cwd, home: home)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { throw PersonaStoreError.message("Failed to create personas directory: \(error.localizedDescription)") }
        let url = directory.appendingPathComponent("\(sanitized).toml")
        guard !FileManager.default.fileExists(atPath: url.path) else { throw PersonaStoreError.message("Persona '\(sanitized)' already exists") }
        var lines: [String] = []
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty { lines.append("description = \(PersonaTOML.encode(description))") }
        if !instructions.isEmpty { lines.append("instructions = \(PersonaTOML.encode(instructions))") }
        do { try Data((lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")).utf8).write(to: url, options: .withoutOverwriting) }
        catch { throw PersonaStoreError.message("Failed to write persona file: \(error.localizedDescription)") }
        return url
    }

    static func read(_ url: URL) -> PersonaFields? {
        guard let text = try? String(contentsOf: url, encoding: .utf8), let document = PersonaTOML(text) else { return nil }
        var fields = PersonaFields()
        for (key, path) in PersonaFields.keys { fields[keyPath: path] = document.string(key) ?? "" }
        if fields.name.isEmpty { fields.name = url.deletingPathExtension().lastPathComponent }
        fields.hasInputs = document.hasArray("inputs")
        fields.hasOutputs = document.hasArray("outputs")
        return fields
    }

    /// Writes the fields that changed, keeping every other line; empty values remove the key.
    static func update(_ url: URL, from original: PersonaFields, to fields: PersonaFields) throws {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw PersonaStoreError.message("Failed to read file") }
        guard var document = PersonaTOML(text) else { throw PersonaStoreError.message("Failed to parse TOML") }
        for (key, path) in PersonaFields.keys where original[keyPath: path] != fields[keyPath: path] {
            document.set(key, fields[keyPath: path])
        }
        do { try Data(document.text.utf8).write(to: url, options: .atomic) }
        catch { throw PersonaStoreError.message("Failed to write file: \(error.localizedDescription)") }
    }

    /// Only user or project persona files, never bundled ones.
    static func isDeletable(_ path: String, home: URL = GrokPaths.home) -> Bool {
        let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard FileManager.default.fileExists(atPath: canonical.path), !canonical.pathComponents.contains("bundled") else { return false }
        let user = home.appendingPathComponent("personas").resolvingSymlinksInPath().standardizedFileURL.path + "/"
        if canonical.path.hasPrefix(user) { return true }
        let components = canonical.deletingLastPathComponent().pathComponents
        return components.count >= 2 && components.suffix(2) == [".grok", "personas"]
    }

    static func delete(_ path: String, home: URL = GrokPaths.home) throws {
        guard isDeletable(path, home: home) else {
            if URL(fileURLWithPath: path).resolvingSymlinksInPath().pathComponents.contains("bundled") {
                throw PersonaStoreError.message("Cannot delete bundled personas")
            }
            throw PersonaStoreError.message("Persona file is not in a known personas directory")
        }
        do { try FileManager.default.removeItem(atPath: path) }
        catch { throw PersonaStoreError.message("Failed to delete persona file: \(error.localizedDescription)") }
    }
}

/// Just enough TOML for persona files: top-level `key = value` entries (including multi-line strings
/// and arrays) before the first table header. Everything else is kept verbatim.
struct PersonaTOML {
    private(set) var lines: [String]
    var text: String { lines.joined(separator: "\n") }

    init?(_ text: String) {
        lines = text.components(separatedBy: "\n")
        guard spans() != nil else { return nil }
    }

    /// Top-level entries as (key, first line, last line).
    private func spans() -> [(key: String, start: Int, end: Int)]? {
        var result: [(String, Int, Int)] = []
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { break }
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { index += 1; continue }
            guard let (key, value) = GrokConfig.keyValue(lines[index]) else { return nil }
            let start = index
            guard let end = Self.valueEnd(value, lines: lines, from: index) else { return nil }
            result.append((key, start, end))
            index = end + 1
        }
        return result
    }

    /// The last line of a value that may continue over several lines.
    private static func valueEnd(_ value: String, lines: [String], from start: Int) -> Int? {
        for delimiter in ["\"\"\"", "'''"] where value.hasPrefix(delimiter) {
            let rest = value.dropFirst(3)
            if rest.contains(delimiter) { return start }
            var index = start + 1
            while index < lines.count { if lines[index].contains(delimiter) { return index }; index += 1 }
            return nil
        }
        if value.hasPrefix("[") || value.hasPrefix("{") {
            var depth = 0, index = start
            var text = value
            while true {
                depth += bracketBalance(text)
                if depth <= 0 { return index }
                index += 1
                guard index < lines.count else { return nil }
                text = lines[index]
            }
        }
        return start
    }

    /// Opening minus closing brackets outside strings.
    private static func bracketBalance(_ text: String) -> Int {
        var balance = 0
        var quote: Character?
        var escaped = false
        for character in text {
            if let open = quote {
                if escaped { escaped = false } else if character == "\\" && open == "\"" { escaped = true } else if character == open { quote = nil }
            } else if character == "\"" || character == "'" { quote = character }
            else if character == "#" { break }
            else if character == "[" || character == "{" { balance += 1 }
            else if character == "]" || character == "}" { balance -= 1 }
        }
        return balance
    }

    func string(_ key: String) -> String? {
        guard let span = spans()?.first(where: { $0.key == key }) else { return nil }
        let raw = lines[span.start...span.end].joined(separator: "\n")
        guard let equals = raw.firstIndex(of: "=") else { return nil }
        return Self.decode(raw[raw.index(after: equals)...].trimmingCharacters(in: .whitespaces))
    }

    func hasArray(_ key: String) -> Bool {
        if lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "[[\(key)]]" }) { return true }
        guard let span = spans()?.first(where: { $0.key == key }) else { return false }
        let raw = lines[span.start...span.end].joined(separator: "\n")
        return raw.contains("{") || raw.range(of: #"\[\s*\S"#, options: .regularExpression).map { !raw[$0].hasSuffix("]") } ?? false
    }

    mutating func set(_ key: String, _ value: String) {
        let spans = spans() ?? []
        if let span = spans.first(where: { $0.key == key }) {
            if value.isEmpty { lines.removeSubrange(span.start...span.end) }
            else { lines.replaceSubrange(span.start...span.end, with: ["\(key) = \(Self.encode(value))"]) }
            return
        }
        guard !value.isEmpty else { return }
        let insertion = spans.last.map { $0.end + 1 } ?? 0
        lines.insert("\(key) = \(Self.encode(value))", at: insertion)
    }

    /// A basic string, or a multi-line basic string for text with line breaks.
    static func encode(_ value: String) -> String {
        guard value.contains("\n") else { return GrokConfig.quote(value) }
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n", "\t": escaped.unicodeScalars.append(scalar)
            case "\r": escaped += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F { escaped += String(format: "\\u%04X", scalar.value) }
                else { escaped.unicodeScalars.append(scalar) }
            }
        }
        return "\"\"\"\n" + escaped + "\"\"\""
    }

    static func decode(_ raw: String) -> String? {
        if raw.hasPrefix("\"\"\"") || raw.hasPrefix("'''") {
            let delimiter = String(raw.prefix(3))
            guard let close = raw.range(of: delimiter, options: .backwards), close.lowerBound >= raw.index(raw.startIndex, offsetBy: 3) else { return nil }
            var body = String(raw[raw.index(raw.startIndex, offsetBy: 3)..<close.lowerBound])
            // A newline right after the opening delimiter is not part of the string.
            if body.hasPrefix("\n") { body.removeFirst() } else if body.hasPrefix("\r\n") { body.removeFirst(2) }
            return delimiter == "'''" ? body : unescape(body, multiline: true)
        }
        let value = stripComment(raw)
        if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 { return String(value.dropFirst().dropLast()) }
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 { return unescape(String(value.dropFirst().dropLast()), multiline: false) }
        return nil
    }

    private static func stripComment(_ raw: String) -> String {
        var quote: Character?
        var escaped = false
        for index in raw.indices {
            let character = raw[index]
            if let open = quote {
                if escaped { escaped = false } else if character == "\\" && open == "\"" { escaped = true } else if character == open { quote = nil }
            } else if character == "\"" || character == "'" { quote = character }
            else if character == "#" { return String(raw[..<index]).trimmingCharacters(in: .whitespaces) }
        }
        return raw.trimmingCharacters(in: .whitespaces)
    }

    private static func unescape(_ body: String, multiline: Bool) -> String {
        var result = ""
        var scalars = Array(body.unicodeScalars)[...]
        while let scalar = scalars.popFirst() {
            guard scalar == "\\", let next = scalars.popFirst() else { result.unicodeScalars.append(scalar); continue }
            switch next {
            case "n": result += "\n"
            case "t": result += "\t"
            case "r": result += "\r"
            case "b": result += "\u{08}"
            case "f": result += "\u{0C}"
            case "\"": result += "\""
            case "\\": result += "\\"
            case "u", "U":
                let count = next == "u" ? 4 : 8
                let hex = String(String.UnicodeScalarView(scalars.prefix(count)))
                scalars = scalars.dropFirst(count)
                if let value = UInt32(hex, radix: 16), let decoded = Unicode.Scalar(value) { result.unicodeScalars.append(decoded) }
            case "\n" where multiline, " " where multiline, "\t" where multiline:
                // A line-ending backslash trims the following whitespace.
                while let peek = scalars.first, peek == " " || peek == "\t" || peek == "\n" || peek == "\r" { scalars = scalars.dropFirst() }
            default: result.unicodeScalars.append(next)
            }
        }
        return result
    }
}
