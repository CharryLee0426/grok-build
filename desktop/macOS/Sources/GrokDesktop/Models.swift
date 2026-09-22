import Foundation

struct Project: Identifiable, Codable, Equatable {
    var id = UUID()
    var path: String
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

struct Conversation: Identifiable, Codable {
    var id = UUID()
    var projectID: UUID
    var title: String = "New task"
    var sessionID: String?
    var messages: [Message] = []
    var updatedAt = Date()
    var isArchived = false
    var isPinned = false
}

struct Message: Identifiable, Codable {
    enum Kind: String, Codable { case user, assistant, thought, tool, system }
    var id = UUID()
    var kind: Kind
    var text: String
    var toolID: String?
    var status: String?
    var detail: String?
}

struct ModelOption: Identifiable, Equatable {
    var id: String
    var name: String
}

struct PermissionOption: Identifiable {
    var id: String
    var name: String
    var kind: String
}

struct Approval: Identifiable {
    var id = UUID()
    var requestID: Any
    var title: String
    var detail: String
    var options: [PermissionOption]
}

struct PlanEntry: Identifiable {
    var id: Int
    var content: String
    var status: String
}

struct AgentQuestion: Identifiable {
    var id: String { question }
    var question: String
    var options: [String]
    var multiSelect: Bool
}

struct QuestionRequest: Identifiable {
    var id = UUID()
    var requestID: Any
    var questions: [AgentQuestion]

    func response(answers: [String: [String]], notes: [String: String] = [:]) -> [String: Any] {
        var wireAnswers: [String: [String]] = [:]
        var annotations: [String: [String: String]] = [:]
        for question in questions {
            let supplied = answers[question.question] ?? []
            let selected = question.options.filter { supplied.contains($0) }
            let custom = supplied.filter { !question.options.contains($0) }
            let note = ([notes[question.question] ?? ""] + custom).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")
            wireAnswers[question.question] = selected.isEmpty && !note.isEmpty ? ["Other"] : selected
            if !note.isEmpty { annotations[question.question] = ["notes": note] }
        }
        return ["outcome": "accepted", "answers": wireAnswers, "annotations": annotations]
    }
}

struct RunState {
    var isRunning = false
    var phase = "Ready"
    var approvals: [Approval] = []
    var models: [ModelOption] = []
    var modes: [ModelOption] = []
    var modelID = ""
    var modeID = ""
    var plan: [PlanEntry] = []
    var questions: [QuestionRequest] = []
}

struct DesktopState: Codable {
    var projects: [Project] = []
    var conversations: [Conversation] = []
    var selectedProjectID: UUID?
    var selectedConversationID: UUID?
}

enum DesktopPaths {
    static var stateFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Grok Desktop", isDirectory: true).appendingPathComponent("state.json")
    }

    static func findHarness(in project: String? = nil) -> String {
        let fm = FileManager.default
        var candidates: [String] = []
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("grok").path { candidates.append(bundled) }
        for base in [project, ProcessInfo.processInfo.environment["GROK_BUILD_ROOT"], fm.currentDirectoryPath].compactMap({ $0 }) {
            candidates += ["\(base)/target/release/xai-grok-pager", "\(base)/target/debug/xai-grok-pager"]
        }
        let home = fm.homeDirectoryForCurrentUser.path
        candidates += ["\(home)/.local/bin/grok", "\(home)/.grok/bin/grok", "/opt/homebrew/bin/grok", "/usr/local/bin/grok"]
        candidates += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/grok" }
        return candidates.first(where: { fm.isExecutableFile(atPath: $0) }) ?? ""
    }
}

enum TranscriptReducer {
    static func text(from block: [String: Any]) -> String {
        if let text = block["text"] as? String { return text }
        if let resource = block["resource"] as? [String: Any] {
            return resource["text"] as? String ?? resource["uri"] as? String ?? ""
        }
        if block["type"] as? String == "image" { return "[Image]" }
        return ""
    }

    static func apply(_ update: [String: Any], to messages: inout [Message]) {
        let kind = update["sessionUpdate"] as? String ?? ""
        switch kind {
        case "agent_message_chunk", "agent_thought_chunk", "user_message_chunk":
            let role: Message.Kind = kind == "agent_message_chunk" ? .assistant : kind == "agent_thought_chunk" ? .thought : .user
            let content = text(from: update["content"] as? [String: Any] ?? [:])
            guard !content.isEmpty else { return }
            if messages.last?.kind == role { messages[messages.count - 1].text += content }
            else { messages.append(Message(kind: role, text: content)) }
        case "tool_call", "tool_call_update":
            guard let id = update["toolCallId"] as? String else { return }
            let contents = update["content"] as? [[String: Any]] ?? []
            let detail = contents.compactMap { item -> String? in
                if item["type"] as? String == "diff" {
                    return "\(item["path"] as? String ?? "File")\n\(item["newText"] as? String ?? "")"
                }
                if let content = item["content"] as? [String: Any] { return text(from: content) }
                return nil
            }.joined(separator: "\n")
            if let index = messages.firstIndex(where: { $0.toolID == id }) {
                if let title = update["title"] as? String { messages[index].text = title }
                if let status = update["status"] as? String { messages[index].status = status }
                if !detail.isEmpty { messages[index].detail = detail }
            } else {
                messages.append(Message(kind: .tool, text: update["title"] as? String ?? "Tool call", toolID: id,
                                        status: update["status"] as? String ?? "pending", detail: detail))
            }
        default: break
        }
    }
}
