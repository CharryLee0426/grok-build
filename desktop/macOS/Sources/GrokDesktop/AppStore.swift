import AppKit
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var state = DesktopState()
    @Published var runs: [UUID: RunState] = [:]
    @Published var draft = ""
    @Published var search = ""
    @Published var showSearch = false
    @Published var showSettings = false
    @Published var showInspector = false
    @Published var showArchived = false
    @Published var workspace = GitWorkspaceSnapshot(branch: "", changes: [])
    @Published var selectedFile: String?
    @Published var diffText = ""
    @Published var banner: String?
    @Published var syncing = false
    @Published var loginLog = ""
    @Published var loginRunning = false
    @Published var binaryPath: String = "" {
        didSet { defaults.set(binaryPath, forKey: "harnessPath") }
    }
    private let stateFile: URL
    private let defaults: UserDefaults
    private enum DraftLocation: Hashable {
        case conversation(UUID)
        case newTask(UUID?)
    }
    private var drafts: [DraftLocation: String] = [:]
    private var draftLocation: DraftLocation {
        state.selectedConversationID.map(DraftLocation.conversation) ?? .newTask(state.selectedProjectID)
    }
    private var clients: [UUID: ACPClient] = [:]
    private var loaded: Set<UUID> = []
    private var replaying: Set<UUID> = []
    private var operations: [UUID: Task<Void, Never>] = [:]
    private var operationIDs: [UUID: UUID] = [:]
    private var cancellationFallbacks: [UUID: Task<Void, Never>] = [:]
    private var cancellationRequested: Set<UUID> = []
    private var importBuffers: [UUID: [Message]] = [:]
    private var pendingPrompts: [UUID: Message] = [:]
    private var historyClient: ACPClient?
    private var saveTask: Task<Void, Never>?
    private var loginProcess: Process?
    private let git = WorkspaceService()

    var project: Project? { state.projects.first { $0.id == state.selectedProjectID } }
    var conversation: Conversation? { state.conversations.first { $0.id == state.selectedConversationID } }
    var run: RunState { state.selectedConversationID.flatMap { runs[$0] } ?? RunState() }
    var visibleConversations: [Conversation] {
        state.conversations.filter {
            $0.isArchived == showArchived && (search.isEmpty ? $0.projectID == state.selectedProjectID : $0.title.localizedCaseInsensitiveContains(search))
        }.sorted { $0.isPinned == $1.isPinned ? $0.updatedAt > $1.updatedAt : $0.isPinned }
    }

    init(stateFile: URL = DesktopPaths.stateFile, defaults: UserDefaults = .standard) {
        self.stateFile = stateFile
        self.defaults = defaults
        if let data = try? Data(contentsOf: stateFile), let saved = try? JSONDecoder().decode(DesktopState.self, from: data) { state = saved }
        if state.projects.isEmpty {
            var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            while directory.path != "/" {
                if FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git").path) {
                    let project = Project(path: directory.path)
                    state.projects = [project]; state.selectedProjectID = project.id
                    break
                }
                directory.deleteLastPathComponent()
            }
        }
        binaryPath = defaults.string(forKey: "harnessPath") ?? DesktopPaths.findHarness(in: state.projects.first?.path)
        if state.projects.contains(where: { $0.id == state.selectedProjectID }) == false { state.selectedProjectID = state.projects.first?.id }
    }

    func save() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        do {
            let file = stateFile
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch { banner = "Could not save task history: \(error.localizedDescription)" }
    }

    func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Open project"; panel.message = "Choose the folder Grok will work in."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.resolvingSymlinksInPath().path
        let project = state.projects.first(where: { $0.path == path }) ?? Project(path: path)
        if !state.projects.contains(where: { $0.id == project.id }) { state.projects.append(project) }
        selectProject(project.id)
        if binaryPath.isEmpty { binaryPath = DesktopPaths.findHarness(in: path) }
    }

    func selectProject(_ id: UUID) {
        drafts[draftLocation] = draft
        state.selectedProjectID = id; state.selectedConversationID = nil
        draft = drafts[draftLocation] ?? ""; search = ""; showArchived = false; selectedFile = nil; diffText = ""
        workspace = GitWorkspaceSnapshot(branch: "", changes: [])
        save(); Task { await refreshWorkspace() }
    }

    func selectConversation(_ task: Conversation) {
        drafts[draftLocation] = draft
        if state.selectedProjectID != task.projectID {
            workspace = GitWorkspaceSnapshot(branch: "", changes: [])
            selectedFile = nil; diffText = ""
        }
        state.selectedConversationID = task.id; state.selectedProjectID = task.projectID
        draft = drafts[draftLocation] ?? ""; save(); Task { await refreshWorkspace() }
    }

    func newTask() {
        drafts[draftLocation] = draft
        state.selectedConversationID = nil
        draft = drafts[draftLocation] ?? ""; showArchived = false; save()
    }
    func togglePin(_ id: UUID) {
        guard let i = state.conversations.firstIndex(where: { $0.id == id }) else { return }
        state.conversations[i].isPinned.toggle(); save()
    }
    func archive(_ id: UUID) {
        guard runs[id]?.isRunning != true, let i = state.conversations.firstIndex(where: { $0.id == id }) else { return }
        state.conversations[i].isArchived.toggle()
        if state.selectedConversationID == id { newTask() }
        stopOperation(id, phase: "Ready"); save()
    }

    func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, let project, !run.isRunning else { return }
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            banner = "Choose your Grok executable in Settings to start a task."; showSettings = true; return
        }
        let sentDraftLocation = draftLocation
        var id = state.selectedConversationID
        if id == nil {
            let task = Conversation(projectID: project.id, title: String(prompt.prefix(64)))
            state.conversations.insert(task, at: 0); id = task.id; state.selectedConversationID = task.id
        }
        guard let id else { return }
        let optimisticPrompt = Message(kind: .user, text: prompt)
        append(optimisticPrompt, to: id)
        pendingPrompts[id] = optimisticPrompt
        drafts.removeValue(forKey: sentDraftLocation)
        drafts.removeValue(forKey: .conversation(id))
        draft = ""; banner = nil
        let operationID = beginOperation(id, phase: "Connecting")
        operations[id] = Task {
            defer { finishOperation(id, operationID: operationID) }
            do {
                let client = try await connect(id: id, project: project, operationID: operationID)
                try checkOperation(id, operationID: operationID)
                guard let session = task(id)?.sessionID else { throw DesktopError.message("The harness did not return a session ID.") }
                pendingPrompts.removeValue(forKey: id)
                runs[id]?.phase = "Working"
                let result = try await client.request("session/prompt", params: ["sessionId": session, "prompt": [["type": "text", "text": prompt]]], timeout: nil)
                try checkOperation(id, operationID: operationID)
                let stopped = cancellationRequested.contains(id) || result["stopReason"] as? String == "cancelled"
                runs[id]?.phase = stopped ? "Stopped" : "Ready"
                runs[id]?.isRunning = false
                if let i = state.conversations.firstIndex(where: { $0.id == id }) { state.conversations[i].updatedAt = Date() }
                save(); await refreshWorkspace()
            } catch {
                guard operationIDs[id] == operationID else { return }
                let stopped = error is CancellationError || cancellationRequested.contains(id)
                runs[id]?.phase = stopped ? "Stopped" : "Needs attention"
                if !stopped { append(Message(kind: .system, text: error.localizedDescription), to: id) }
                discardConnection(id)
            }
        }
    }

    private func connect(id: UUID, project: Project, operationID: UUID) async throws -> ACPClient {
        try checkOperation(id, operationID: operationID)
        if let client = clients[id], loaded.contains(id) { return client }
        let client = ACPClient()
        client.onNotification = { [weak self, weak client] method, params in
            guard let self, let client, self.clients[id] === client else { return }
            self.receive(method, params: params, id: id)
        }
        client.onRequest = { [weak self, weak client] requestID, method, params in
            guard let self, let client, self.clients[id] === client else { return }
            self.handleRequest(requestID, method: method, params: params, id: id, client: client)
        }
        client.onDisconnect = { [weak self, weak client] _ in
            guard let self, let client, self.clients[id] === client else { return }
            self.loaded.remove(id)
            self.runs[id]?.phase = "Disconnected"
            self.runs[id]?.approvals = []; self.runs[id]?.questions = []
        }
        clients[id] = client
        try client.start(executable: binaryPath, cwd: project.path)
        let initial = try await initialize(client)
        try checkOperation(id, operationID: operationID)
        if let modelState = (initial["_meta"] as? [String: Any])?["modelState"] as? [String: Any] { applyModels(modelState, id: id) }
        try await authenticate(client, initial: initial)
        try checkOperation(id, operationID: operationID)
        var params: [String: Any] = ["cwd": project.path, "mcpServers": []]
        let result: [String: Any]
        if let session = task(id)?.sessionID {
            params["sessionId"] = session
            importBuffers[id] = []
            replaying.insert(id)
            defer { if operationIDs[id] == operationID { replaying.remove(id) } }
            result = try await client.request("session/load", params: params, timeout: 120)
            try checkOperation(id, operationID: operationID)
            if let index = state.conversations.firstIndex(where: { $0.id == id }) {
                // The harness owns persisted history. Keep the visible prompt that has not been sent yet.
                state.conversations[index].messages = (importBuffers[id] ?? []) + (pendingPrompts[id].map { [$0] } ?? [])
            }
        } else {
            result = try await client.request("session/new", params: params, timeout: 120)
            try checkOperation(id, operationID: operationID)
            guard let session = result["sessionId"] as? String else { throw DesktopError.message("The harness did not return a session ID.") }
            if let i = state.conversations.firstIndex(where: { $0.id == id }) { state.conversations[i].sessionID = session }
        }
        try checkOperation(id, operationID: operationID)
        if let models = result["models"] as? [String: Any] { applyModels(models, id: id) }
        if let modes = result["modes"] as? [String: Any] {
            runs[id, default: RunState()].modes = (modes["availableModes"] as? [[String: Any]] ?? []).compactMap {
                guard let value = $0["id"] as? String else { return nil }; return ModelOption(id: value, name: $0["name"] as? String ?? value)
            }
            runs[id]?.modeID = modes["currentModeId"] as? String ?? ""
        }
        loaded.insert(id); save(); return client
    }

    private func initialize(_ client: ACPClient) async throws -> [String: Any] {
        try await client.request("initialize", params: [
            "protocolVersion": 1,
            "clientInfo": ["name": "grok-desktop", "title": "Grok Desktop", "version": "0.1.0"],
            "clientCapabilities": ["fs": ["readTextFile": false, "writeTextFile": false], "terminal": false,
                                   "_meta": ["x.ai/folderTrust": ["interactive": true]]],
            "_meta": ["clientType": "grok_desktop", "clientIdentifier": "grok-desktop", "clientVersion": "0.1.0", "startupHints": ["nonInteractive": false]]
        ], timeout: 60)
    }

    private func authenticate(_ client: ACPClient, initial: [String: Any]) async throws {
        let methods = initial["authMethods"] as? [[String: Any]] ?? []
        let preferred = (initial["_meta"] as? [String: Any])?["defaultAuthMethodId"] as? String
        let offered = Set(methods.compactMap { $0["id"] as? String })
        let supported = ["xai.api_key", "cached_token"]
        let method = ([preferred].compactMap { $0 } + supported).first { supported.contains($0) && offered.contains($0) }
        guard let method else {
            throw DesktopError.message("No supported sign-in method is available. Open Settings and sign in to xAI, OpenRouter, or OpenAI Codex, then try again.")
        }
        _ = try await client.request("authenticate", params: ["methodId": method, "_meta": ["headless": true]], timeout: 60)
    }

    private func receive(_ method: String, params: [String: Any], id: UUID) {
        if method == "x.ai/models/update" { applyModels(params, id: id); return }
        guard method == "session/update", let update = params["update"] as? [String: Any] else { return }
        let kind = update["sessionUpdate"] as? String ?? ""
        if kind == "current_mode_update" { runs[id]?.modeID = update["currentModeId"] as? String ?? "" }
        if kind == "plan" {
            runs[id, default: RunState()].plan = (update["entries"] as? [[String: Any]] ?? []).enumerated().map {
                PlanEntry(id: $0.offset, content: $0.element["content"] as? String ?? "", status: $0.element["status"] as? String ?? "pending")
            }
        }
        guard let i = state.conversations.firstIndex(where: { $0.id == id }) else { return }
        if kind == "session_info_update", let title = update["title"] as? String, !title.isEmpty { state.conversations[i].title = title }
        // Commit authoritative replay only once session/load succeeds; failed loads keep the local copy.
        if replaying.contains(id) {
            TranscriptReducer.apply(update, to: &importBuffers[id, default: []])
            return
        }
        if importing.contains(id) { return }
        // The user message is optimistically inserted when sending.
        if kind == "user_message_chunk", !replaying.contains(id) { return }
        TranscriptReducer.apply(update, to: &state.conversations[i].messages)
        save()
    }

    private var importing: Set<UUID> = []
    private func handleRequest(_ requestID: Any, method: String, params: [String: Any], id: UUID, client: ACPClient) {
        if method == "session/request_permission" {
            let tool = params["toolCall"] as? [String: Any] ?? [:]
            let options = (params["options"] as? [[String: Any]] ?? []).compactMap { value -> PermissionOption? in
                guard let optionID = value["optionId"] as? String else { return nil }
                return PermissionOption(id: optionID, name: value["name"] as? String ?? optionID, kind: value["kind"] as? String ?? "")
            }
            let detail: String
            if let input = tool["rawInput"], let data = try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .fragmentsAllowed, .sortedKeys]) {
                detail = String(data: data, encoding: .utf8) ?? ""
            } else { detail = "Grok needs your permission to continue." }
            runs[id, default: RunState()].approvals.append(Approval(requestID: requestID, title: tool["title"] as? String ?? "Permission required", detail: detail, options: options))
        } else if method == "x.ai/folder_trust/request" {
            let kinds = (params["configKinds"] as? [String] ?? []).joined(separator: ", ")
            runs[id, default: RunState()].approvals.append(Approval(requestID: requestID, title: "Trust project configuration?",
                detail: "\(params["cwd"] as? String ?? "This project")\n\nThis folder contains \(kinds.isEmpty ? "local agent configuration" : kinds). Trust it only if you know its contents.",
                options: [PermissionOption(id: "folder:reject", name: "Skip configuration", kind: "reject_once"), PermissionOption(id: "folder:trust", name: "Trust project", kind: "allow_once")]))
        } else if method == "x.ai/exit_plan_mode" {
            runs[id, default: RunState()].approvals.append(Approval(requestID: requestID, title: "Ready to implement this plan?",
                detail: params["planContent"] as? String ?? "Grok has finished planning and is ready to make changes.",
                options: [PermissionOption(id: "plan:cancelled", name: "Keep planning", kind: "reject_once"), PermissionOption(id: "plan:approved", name: "Approve plan", kind: "allow_once")]))
        } else if method == "x.ai/ask_user_question" {
            let questions = (params["questions"] as? [[String: Any]] ?? []).compactMap { value -> AgentQuestion? in
                guard let question = value["question"] as? String else { return nil }
                return AgentQuestion(question: question, options: (value["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String }, multiSelect: value["multiSelect"] as? Bool ?? false)
            }
            runs[id, default: RunState()].questions.append(QuestionRequest(requestID: requestID, questions: questions))
        } else {
            try? client.respondError(id: requestID, code: -32601, message: "Unsupported client method: \(method)")
        }
    }

    func approve(_ approval: Approval, option: PermissionOption) {
        guard let id = state.selectedConversationID, let client = clients[id],
              runs[id]?.approvals.contains(where: { $0.id == approval.id }) == true else { return }
        do {
            if option.id.hasPrefix("folder:") { try client.respond(id: approval.requestID, result: ["outcome": option.id == "folder:trust" ? "trust" : "reject"]) }
            else if option.id.hasPrefix("plan:") { try client.respond(id: approval.requestID, result: ["outcome": String(option.id.dropFirst(5))]) }
            else { try client.respond(id: approval.requestID, result: ["outcome": ["outcome": "selected", "optionId": option.id]]) }
            runs[id]?.approvals.removeAll { $0.id == approval.id }
        } catch { banner = error.localizedDescription }
    }

    func answer(_ request: QuestionRequest, answers: [String: [String]], notes: [String: String] = [:], cancelled: Bool = false) {
        guard let id = state.selectedConversationID, let client = clients[id],
              runs[id]?.questions.contains(where: { $0.id == request.id }) == true else { return }
        do {
            try client.respond(id: request.requestID, result: cancelled ? ["outcome": "cancelled"] : request.response(answers: answers, notes: notes))
            runs[id]?.questions.removeAll { $0.id == request.id }
        } catch { banner = error.localizedDescription }
    }

    func cancel() {
        guard let id = state.selectedConversationID, runs[id]?.isRunning == true else { return }
        guard let client = clients[id], loaded.contains(id), !importing.contains(id), let session = task(id)?.sessionID else {
            stopOperation(id, phase: "Stopped")
            return
        }
        cancellationRequested.insert(id)
        do {
            try client.notify("session/cancel", params: ["sessionId": session])
            for approval in runs[id]?.approvals ?? [] {
                let folder = approval.options.contains { $0.id.hasPrefix("folder:") }
                let plan = approval.options.contains { $0.id.hasPrefix("plan:") }
                try? client.respond(id: approval.requestID, result: folder ? ["outcome": "reject"] : plan ? ["outcome": "cancelled"] : ["outcome": ["outcome": "cancelled"]])
            }
            for question in runs[id]?.questions ?? [] { try? client.respond(id: question.requestID, result: ["outcome": "cancelled"]) }
            runs[id]?.approvals = []; runs[id]?.questions = []; runs[id]?.phase = "Stopping"
            // Give ACP cancellation a chance to persist the turn, then recover from an unresponsive harness.
            let operationID = operationIDs[id]
            cancellationFallbacks[id]?.cancel()
            cancellationFallbacks[id] = Task { [weak self, weak client] in
                do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
                guard let self, let client, self.operationIDs[id] == operationID,
                      self.clients[id] === client, self.runs[id]?.isRunning == true else { return }
                self.stopOperation(id, phase: "Stopped")
            }
        } catch { stopOperation(id, phase: "Stopped") }
    }

    private func beginOperation(_ id: UUID, phase: String) -> UUID {
        let operationID = UUID()
        operationIDs[id] = operationID
        cancellationFallbacks.removeValue(forKey: id)?.cancel()
        cancellationRequested.remove(id)
        runs[id, default: RunState()].isRunning = true
        runs[id]?.phase = phase
        runs[id]?.approvals = []; runs[id]?.questions = []
        return operationID
    }

    private func checkOperation(_ id: UUID, operationID: UUID) throws {
        try Task.checkCancellation()
        guard operationIDs[id] == operationID else { throw CancellationError() }
    }

    private func finishOperation(_ id: UUID, operationID: UUID) {
        guard operationIDs[id] == operationID else { return }
        operationIDs.removeValue(forKey: id)
        operations.removeValue(forKey: id)
        cancellationFallbacks.removeValue(forKey: id)?.cancel()
        cancellationRequested.remove(id)
        runs[id]?.isRunning = false
        runs[id]?.approvals = []; runs[id]?.questions = []
        replaying.remove(id); importing.remove(id); importBuffers.removeValue(forKey: id); pendingPrompts.removeValue(forKey: id)
    }

    private func discardConnection(_ id: UUID) {
        clients.removeValue(forKey: id)?.stop()
        loaded.remove(id)
        runs[id]?.approvals = []; runs[id]?.questions = []
    }

    private func stopOperation(_ id: UUID, phase: String) {
        // Invalidate first: continuations from the old client must not clean up a new run.
        operationIDs.removeValue(forKey: id)
        operations.removeValue(forKey: id)?.cancel()
        cancellationFallbacks.removeValue(forKey: id)?.cancel()
        cancellationRequested.remove(id)
        discardConnection(id)
        replaying.remove(id); importing.remove(id); importBuffers.removeValue(forKey: id); pendingPrompts.removeValue(forKey: id)
        runs[id]?.isRunning = false; runs[id]?.phase = phase
    }

    func setModel(_ model: ModelOption) { setSessionOption(method: "session/set_model", key: "modelId", value: model.id) }
    func setMode(_ mode: ModelOption) { setSessionOption(method: "session/set_mode", key: "modeId", value: mode.id) }
    private func setSessionOption(method: String, key: String, value: String) {
        guard let id = state.selectedConversationID, let session = task(id)?.sessionID, let client = clients[id], !run.isRunning else { return }
        Task {
            do {
                _ = try await client.request(method, params: ["sessionId": session, key: value])
                if key == "modelId" { runs[id]?.modelID = value } else { runs[id]?.modeID = value }
            } catch { banner = error.localizedDescription }
        }
    }
    private func applyModels(_ models: [String: Any], id: UUID) {
        runs[id, default: RunState()].models = (models["availableModels"] as? [[String: Any]] ?? []).compactMap {
            guard let value = $0["modelId"] as? String else { return nil }; return ModelOption(id: value, name: $0["name"] as? String ?? value)
        }
        runs[id]?.modelID = models["currentModelId"] as? String ?? ""
    }

    func syncHistory() {
        guard let project, !syncing else { return }
        syncing = true
        Task {
            let client = ACPClient()
            historyClient = client
            defer { client.stop(); if historyClient === client { historyClient = nil }; syncing = false }
            do {
                try client.start(executable: binaryPath, cwd: project.path)
                let initial = try await initialize(client)
                try await authenticate(client, initial: initial)
                var cursor: String?
                repeat {
                    var params: [String: Any] = ["cwd": project.path]
                    if let cursor { params["cursor"] = cursor }
                    let response = try await client.request("session/list", params: params)
                    for session in response["sessions"] as? [[String: Any]] ?? [] {
                        guard let sessionID = session["sessionId"] as? String,
                              !state.conversations.contains(where: { $0.sessionID == sessionID }) else { continue }
                        let date = (session["updatedAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
                        state.conversations.append(Conversation(projectID: project.id, title: session["title"] as? String ?? "Grok task", sessionID: sessionID, updatedAt: date))
                    }
                    cursor = response["nextCursor"] as? String
                } while cursor != nil
                save()
            } catch { banner = "Could not import harness tasks: \(error.localizedDescription)" }
        }
    }

    func loadImportedConversation() async {
        guard let task = conversation, task.messages.isEmpty, task.sessionID != nil, let project, runs[task.id]?.isRunning != true else { return }
        banner = nil
        let operationID = beginOperation(task.id, phase: "Loading history")
        importing.insert(task.id)
        importBuffers[task.id] = []
        defer { finishOperation(task.id, operationID: operationID) }
        do {
            _ = try await connect(id: task.id, project: project, operationID: operationID)
            try checkOperation(task.id, operationID: operationID)
            if let index = state.conversations.firstIndex(where: { $0.id == task.id }) {
                state.conversations[index].messages = importBuffers[task.id] ?? []
            }
            runs[task.id]?.phase = "Ready"; save()
        } catch {
            guard operationIDs[task.id] == operationID else { return }
            runs[task.id]?.phase = error is CancellationError ? "Stopped" : "Needs attention"
            if !(error is CancellationError) { banner = error.localizedDescription }
            discardConnection(task.id)
        }
    }

    func refreshWorkspace() async {
        guard let project else { return }
        let snapshot = await git.inspect(path: project.path)
        guard self.project?.id == project.id else { return }
        workspace = snapshot
        if let file = selectedFile { await selectFile(file) }
    }
    func selectFile(_ file: String) async {
        guard let project else { return }
        selectedFile = file; diffText = "Loading changes…"
        let result = await git.diff(path: project.path, file: file)
        guard selectedFile == file, self.project?.id == project.id else { return }
        diffText = result
    }
    func revealProject() { if let project { NSWorkspace.shared.open(URL(fileURLWithPath: project.path)) } }
    func openTerminal() {
        guard let project else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: project.path)], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration())
    }
    func chooseBinary() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.prompt = "Use executable"
        guard panel.runModal() == .OK, let path = panel.url?.path else { return }
        if FileManager.default.isExecutableFile(atPath: path) { binaryPath = path } else { banner = "That file is not executable." }
    }
    func login(provider: String) {
        guard !loginRunning else { return }
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else { loginLog = "Choose a Grok executable first."; return }
        let process = Process(); process.executableURL = URL(fileURLWithPath: binaryPath)
        process.currentDirectoryURL = URL(fileURLWithPath: project?.path ?? FileManager.default.homeDirectoryForCurrentUser.path, isDirectory: true)
        process.arguments = provider == "xai" ? ["login", "--oauth"] : ["login", provider]
        let output = Pipe(); process.standardOutput = output; process.standardError = output; process.standardInput = FileHandle.nullDevice
        loginLog = "Opening browser sign-in…"; loginRunning = true; loginProcess = process
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.loginLog = String(((self?.loginLog ?? "") + "\n" + text).suffix(12_000)) }
        }
        process.terminationHandler = { [weak self] process in
            output.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                self?.loginRunning = false; self?.loginProcess = nil
                self?.loginLog += process.terminationStatus == 0 ? "\nSigned in. You can start a task." : "\nSign-in exited (\(process.terminationStatus))."
            }
        }
        do { try process.run() } catch { output.fileHandleForReading.readabilityHandler = nil; loginRunning = false; loginLog = error.localizedDescription }
    }
    func cancelLogin() { loginProcess?.terminate() }
    func shutdown() {
        saveTask?.cancel(); flush()
        for id in Set(clients.keys).union(operationIDs.keys) { stopOperation(id, phase: "Stopped") }
        historyClient?.stop(); historyClient = nil
        loginProcess?.terminate()
    }
    private func task(_ id: UUID) -> Conversation? { state.conversations.first { $0.id == id } }
    private func append(_ message: Message, to id: UUID) {
        guard let i = state.conversations.firstIndex(where: { $0.id == id }) else { return }
        state.conversations[i].messages.append(message); state.conversations[i].updatedAt = Date(); save()
    }
}

enum DesktopError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
