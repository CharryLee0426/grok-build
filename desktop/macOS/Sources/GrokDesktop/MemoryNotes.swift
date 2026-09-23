import Darwin
import Foundation

/// Which persistent-memory store a session uses (`_meta["x.ai/memoryMode"]`).
enum MemoryNoteMode: String, Equatable {
    case legacy, v2
}

enum MemoryNoteError: LocalizedError, Equatable {
    case empty
    case tooLarge(actual: Int, limit: Int)
    case unsafePath(String)
    case io(String)

    var errorDescription: String? {
        switch self {
        case .empty: return "Please provide a memory note."
        case .tooLarge(let actual, let limit): return "memory observation is \(actual) bytes, exceeding the \(limit)-byte limit"
        case .unsafePath(let path): return "symbolic links are not allowed: \(path)"
        case .io(let detail): return detail
        }
    }
}

/// Saves `/remember` notes the way the terminal does. The harness has no ACP method for this:
/// legacy memory appends to `MEMORY.md`, v2 publishes an immutable observation in the global inbox.
enum MemoryNoteStore {
    /// v2 refuses manual observations larger than what it reads per source.
    static let maxObservationBytes = 64 * 1024

    /// Gives a note the Markdown heading the memory chunker expects: a leading `#` is kept, a single
    /// line becomes the heading, and a short first line heads the rest (a long one gets `## Note`).
    static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.utf8.first == UInt8(ascii: "#") { return trimmed }
        // Byte-level search: Swift treats "\r\n" as one Character, the terminal splits at "\n".
        let bytes = Array(trimmed.utf8)
        guard let newline = bytes.firstIndex(of: 0x0A) else { return "## \(trimmed)" }
        let first = String(decoding: bytes[..<newline], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = String(decoding: bytes[newline...], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return first.utf8.count <= 80 ? "## \(first)\n\n\(rest)" : "## Note\n\n\(trimmed)"
    }

    static func legacyFile(home: URL = GrokPaths.home) -> URL {
        home.appendingPathComponent("memory", isDirectory: true).appendingPathComponent("MEMORY.md")
    }

    static func v2Inbox(home: URL = GrokPaths.home) -> URL {
        home.appendingPathComponent("memory-v2/global/observations/_inbox", isDirectory: true)
    }

    /// Where a note will be written, for display.
    static func destination(_ mode: MemoryNoteMode, home: URL = GrokPaths.home) -> String {
        let path = mode == .legacy ? legacyFile(home: home).path : v2Inbox(home: home).path + "/"
        return (path as NSString).abbreviatingWithTildeInPath
    }

    /// Saves a note and returns the file written. Blocking; call off the main thread.
    @discardableResult
    static func save(_ text: String, mode: MemoryNoteMode, home: URL = GrokPaths.home) throws -> URL {
        let normalized = normalize(text)
        if mode == .v2, normalized.utf8.count > maxObservationBytes {
            throw MemoryNoteError.tooLarge(actual: normalized.utf8.count, limit: maxObservationBytes)
        }
        guard !normalized.isEmpty else { throw MemoryNoteError.empty }
        return mode == .legacy ? try appendLegacy(normalized, home: home) : try publishObservation(normalized, home: home)
    }

    private static func appendLegacy(_ note: String, home: URL) throws -> URL {
        let file = legacyFile(home: home)
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            let size = try handle.seekToEnd()
            try handle.write(contentsOf: Data(((size > 0 ? "\n\n" : "") + note).utf8))
        } catch {
            throw MemoryNoteError.io(error.localizedDescription)
        }
        return file
    }

    /// Mirrors `persist_observation`: write a private temporary file, sync it, then publish it under
    /// its final name without overwriting. The harness regenerates the scope's `MEMORY.md` index the
    /// next time it initializes memory; browsing sees the note immediately. Dream consolidates only
    /// captured observations, so a remembered note is not merged into topics — the same as in the terminal.
    private static func publishObservation(_ note: String, home: URL) throws -> URL {
        let root = home.appendingPathComponent("memory-v2", isDirectory: true)
        let scope = root.appendingPathComponent("global", isDirectory: true)
        for path in [root, scope] { try rejectSymlink(path) }
        for relative in ["topics", "observations", "observations/_inbox", "archive"] {
            let directory = scope.appendingPathComponent(relative, isDirectory: true)
            try rejectSymlink(directory)
            do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            catch { throw MemoryNoteError.io("failed to create v2 memory directory at \(directory.path): \(error.localizedDescription)") }
        }
        let inbox = v2Inbox(home: home)
        let data = Data(note.utf8)
        for _ in 0..<16 {
            let token = randomToken()
            let temporary = inbox.appendingPathComponent(".remember-\(token).tmp")
            let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            if descriptor < 0 {
                if errno == EEXIST { continue }
                throw MemoryNoteError.io("failed to create temporary v2 observation: \(String(cString: strerror(errno)))")
            }
            defer { unlink(temporary.path) }
            let written = data.withUnsafeBytes { buffer in write(descriptor, buffer.baseAddress, buffer.count) }
            let synced = fsync(descriptor)
            close(descriptor)
            guard written == data.count, synced == 0 else { throw MemoryNoteError.io("failed to write temporary v2 observation") }
            let final = inbox.appendingPathComponent("remember-\(token).md")
            // A hard link publishes atomically and fails instead of replacing an existing note.
            guard link(temporary.path, final.path) == 0 else {
                throw MemoryNoteError.io("failed to publish v2 observation at \(final.path): \(String(cString: strerror(errno)))")
            }
            return final
        }
        throw MemoryNoteError.io("failed to create temporary v2 observation")
    }

    private static func rejectSymlink(_ url: URL) throws {
        if let type = try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType, type == .typeSymbolicLink {
            throw MemoryNoteError.unsafePath(url.path)
        }
    }

    /// Six alphanumeric characters, like the `tempfile` names the terminal produces.
    private static func randomToken() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }

    // MARK: Mode

    /// A session's listed files live under the root of the store it uses.
    static func mode(forListedPaths paths: [String], home: URL = GrokPaths.home) -> MemoryNoteMode? {
        let roots = [home, home.resolvingSymlinksInPath()].map { $0.standardizedFileURL.path }
        for path in paths {
            let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
            for root in roots {
                if normalized.hasPrefix(root + "/memory-v2/") { return .v2 }
                if normalized.hasPrefix(root + "/memory/") { return .legacy }
            }
        }
        return nil
    }

    /// Without a session listing: `[memory_v2] enabled` decides, as in the shell. Remote settings can
    /// also select v2; the harness then initializes the v2 global scope, so a v2 state database that is
    /// newer than the legacy notes file is taken as the sign of it.
    static func inferMode(home: URL = GrokPaths.home, config: GrokConfig) -> MemoryNoteMode {
        if let enabled = config.bool("enabled", in: "memory_v2") { return enabled ? .v2 : .legacy }
        let manager = FileManager.default
        let state = home.appendingPathComponent("memory-v2/global/memory_state.sqlite")
        guard let stateDate = (try? manager.attributesOfItem(atPath: state.path))?[.modificationDate] as? Date else { return .legacy }
        guard let legacyDate = (try? manager.attributesOfItem(atPath: legacyFile(home: home).path))?[.modificationDate] as? Date else { return .v2 }
        return stateDate >= legacyDate ? .v2 : .legacy
    }
}

/// The `contextSummary` the terminal sends with `memory/rewrite`, so the model can resolve
/// references such as "this file" or "the bug we just fixed".
enum RememberContext {
    static func summary(cwd: String, branch: String?, prompts: [String], files: [String]) -> String {
        var parts = ["CWD: \(cwd)"]
        if let branch, !branch.isEmpty { parts.append("Branch: \(branch)") }
        let recentPrompts = prompts.suffix(5).map(truncatePrompt)
        if !recentPrompts.isEmpty {
            parts.append("Recent prompts:")
            parts += recentPrompts.map { "- \($0)" }
        }
        // Newest first, at most twenty tool calls, then duplicates dropped keeping the newest.
        var seen = Set<String>()
        let recentFiles = files.reversed().prefix(20).filter { seen.insert($0).inserted }
        if !recentFiles.isEmpty {
            parts.append("Recent files:")
            parts += recentFiles.map { "- \($0)" }
        }
        return parts.joined(separator: "\n")
    }

    /// Prompts over 200 bytes keep the longest prefix that ends on a character boundary at or
    /// before byte 200, followed by "...".
    static func truncatePrompt(_ text: String) -> String {
        guard text.utf8.count > 200 else { return text }
        var end = 0, offset = 0
        for scalar in text.unicodeScalars {
            if offset > 200 { break }
            end = offset
            offset += scalar.utf8.count
        }
        return String(decoding: Array(text.utf8.prefix(end)), as: UTF8.self) + "..."
    }

    private static let fileTools: Set<String> = ["read_file", "read", "search_replace", "edit", "apply_patch", "strreplace", "write", "list_dir", "ls"]

    /// The path of a Read, Edit, or ListDir tool call, from the `x.ai/tool` name the shell stamps
    /// (or the ACP kind when it is missing).
    static func toolFilePath(_ update: [String: Any]) -> String? {
        let tool = ((update["_meta"] as? [String: Any])?["x.ai/tool"] as? [String: Any])?["name"] as? String
        if let tool { guard fileTools.contains(tool.lowercased()) else { return nil } }
        else { guard ["read", "edit"].contains(update["kind"] as? String ?? "") else { return nil } }
        if let path = (update["locations"] as? [[String: Any]])?.first?["path"] as? String, !path.isEmpty { return path }
        let input = update["rawInput"] as? [String: Any] ?? [:]
        for key in ["path", "file_path", "target_file", "target_directory", "directory", "filePath"] {
            if let value = input[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }
}
