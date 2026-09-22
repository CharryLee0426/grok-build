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
    @Published var showCommandPalette = false
    @Published var featurePanel: FeaturePanel?
    @Published var featureRows: [FeatureRow] = []
    @Published var featureLoading = false
    @Published var featureError: String?
    @Published var savedPlanContent: String?
    @Published var savedPlanLoading = false
    @Published var savedPlanError: String?
    @Published var advancedContent: String?
    @Published var advancedLoading = false
    @Published var advancedError: String?
    @Published var advancedTitle = "Details"
    @Published var showAdvancedPanel = false
    var advancedRequestID: UUID?
    var savedPlanRequestID: UUID?
    @Published var rewindPoints: [RewindCheckpoint] = []
    @Published var rewindPreview: RewindPreview?
    var rewindConversationID: UUID?
    var pendingRecap: (conversationID: UUID, requestID: UUID)?
    private var featureRequestID: UUID?
    private var featureNotificationRefresh: Task<Void, Never>?
    private var auxiliaryClients: [UUID: ACPClient] = [:]
    private var pendingModes: [UUID: String] = [:]
    private(set) var binaryPath: String = ""
    @Published private var catalogRun = RunState()
    private var catalogProjectID: UUID?
    private var commandCatalogProjectID: UUID?
    private var catalogLoadingProjectID: UUID?
    private var catalogClient: ACPClient?
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
    var run: RunState {
        var catalog = catalogRun
        if commandCatalogProjectID != state.selectedProjectID { catalog.commands = []; catalog.commandsLoaded = false; catalog.availableTools = nil }
        if let id = state.selectedConversationID {
            if let existing = runs[id] { return existing }
            var initial = catalog
            initial.isConfiguring = false
            initial.modelID = task(id)?.modelID ?? initial.modelID
            initial.reasoningID = task(id)?.reasoningID ?? initial.reasoningID
            return initial
        }
        return catalog
    }
    var visibleConversations: [Conversation] {
        state.conversations.filter {
            $0.isArchived == showArchived && (search.isEmpty ? $0.projectID == state.selectedProjectID : $0.title.localizedCaseInsensitiveContains(search))
        }.sorted { $0.isPinned == $1.isPinned ? $0.updatedAt > $1.updatedAt : $0.isPinned }
    }

    init(stateFile: URL = DesktopPaths.stateFile, defaults: UserDefaults = .standard, binaryPath: String? = nil) {
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
        self.binaryPath = binaryPath ?? ProcessInfo.processInfo.environment["GROK_DESKTOP_HARNESS"] ?? DesktopPaths.findHarness(in: state.projects.first?.path)
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

    func deleteConversation(_ id: UUID) {
        guard runs[id]?.isRunning != true, runs[id]?.isConfiguring != true,
              let conversation = task(id) else { return }
        if let session = conversation.sessionID { state.deletedSessionIDs.insert(session) }
        stopOperation(id, phase: "Ready")
        drafts.removeValue(forKey: .conversation(id))
        runs.removeValue(forKey: id)
        state.conversations.removeAll { $0.id == id }
        if state.selectedConversationID == id {
            state.selectedConversationID = nil
            draft = drafts[draftLocation] ?? ""
        }
        // A tombstone must reach disk before a later history import can discover this session.
        flush()
    }

    func prepareSessionOptions() async {
        guard let project else { return }
        if conversation != nil {
            await loadImportedConversation()
            return
        }
        guard !(catalogRun.isConfiguring && catalogLoadingProjectID == project.id),
              catalogProjectID != project.id || catalogRun.models.isEmpty else { return }
        catalogRun.isConfiguring = true
        catalogLoadingProjectID = project.id
        let client = ACPClient()
        catalogClient?.stop(); catalogClient = client
        defer {
            client.stop()
            if catalogClient === client { catalogClient = nil; catalogLoadingProjectID = nil; catalogRun.isConfiguring = false }
        }
        do {
            try client.start(executable: binaryPath, cwd: project.path)
            let initial = try await initialize(client)
            try await authenticate(client, initial: initial)
            let response = try await client.request("_x.ai/models/list", timeout: 60)
            if let error = response["error"] as? String { throw DesktopError.message(error) }
            if let error = response["error"] as? [String: Any] {
                throw DesktopError.message(error["message"] as? String ?? "The runtime could not load its models.")
            }
            guard let models = response["result"] as? [String: Any] else {
                throw DesktopError.message("The runtime returned an invalid model catalog.")
            }
            try Task.checkCancellation()
            guard self.project?.id == project.id else { return }
            catalogProjectID = project.id
            catalogRun.models = SessionOptions.models(models)
            let preferred = state.selectedModelID.flatMap { selected in
                catalogRun.models.first { $0.id == selected }?.id
            }
            catalogRun.modelID = preferred ?? models["currentModelId"] as? String ?? ""
            updateCatalogReasoning(preferred: state.selectedReasoningID)
            state.selectedModelID = catalogRun.modelID.isEmpty ? nil : catalogRun.modelID
            state.selectedReasoningID = catalogRun.reasoningID.isEmpty ? nil : catalogRun.reasoningID
            do {
                let commands = try ExtensionResponse.unwrap(try await client.request("_x.ai/commands/list", params: ["cwd": project.path]))
                guard self.project?.id == project.id else { return }
                catalogRun.commands = SlashCommand.parse(commands["commands"] as? [[String: Any]] ?? [])
                catalogRun.commandsLoaded = true
                catalogRun.availableTools = commands["tools"] as? [String]
                commandCatalogProjectID = project.id
            } catch { /* Model selection still works with an older harness. */ }
            save()
        } catch {
            if !(error is CancellationError), self.project?.id == project.id {
                banner = "Could not load model choices: \(error.localizedDescription)"
            }
        }
    }

    func send(displayText: String? = nil, promptText: String? = nil, requiredTool: String? = nil) {
        let prompt = (displayText ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        let commandDraftLocation = draftLocation
        if promptText == nil, let command = SlashCommand.split(prompt), handleDesktopCommand(command.name, arguments: command.arguments) {
            drafts.removeValue(forKey: commandDraftLocation)
            if draftLocation == commandDraftLocation, draft.trimmingCharacters(in: .whitespacesAndNewlines) == prompt { draft = "" }
            return
        }
        if let command = SlashCommand.split(prompt), command.name == "goal", run.isRunning,
           ["status", "pause", "resume", "clear"].contains(command.arguments) {
            draft = ""; drafts.removeValue(forKey: commandDraftLocation)
            goalAction(command.arguments); return
        }
        guard !prompt.isEmpty, let project, !run.isRunning, !run.isConfiguring else { return }
        if promptText == nil, let command = SlashCommand.split(prompt), run.commandsLoaded,
           !run.commands.contains(where: { $0.name == command.name || $0.aliases.contains(command.name) }) {
            banner = "Unknown command /\(command.name). Open the command menu to see commands available in this project."
            return
        }
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            banner = "The bundled Grok runtime is missing. Reinstall Grok Desktop to start a task."; return
        }
        let sentDraftLocation = draftLocation
        var id = state.selectedConversationID
        if id == nil {
            let task = Conversation(projectID: project.id, title: String(prompt.prefix(64)), modelID: state.selectedModelID, reasoningID: state.selectedReasoningID)
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
                if let requiredTool, runs[id]?.availableTools?.contains(requiredTool) != true {
                    throw DesktopError.message("This runtime does not provide the \(requiredTool) tool required by \(prompt.components(separatedBy: " ").first ?? "this command").")
                }
                if promptText == nil, let command = SlashCommand.split(prompt),
                   runs[id]?.commands.contains(where: { $0.name == command.name || $0.aliases.contains(command.name) }) != true {
                    throw DesktopError.message("Command /\(command.name) is not available in this session.")
                }
                pendingPrompts.removeValue(forKey: id)
                runs[id]?.phase = "Working"
                var block: [String: Any] = ["type": "text", "text": promptText ?? prompt]
                if promptText != nil { block["_meta"] = ["displayText": prompt] }
                let result = try await client.request("session/prompt", params: ["sessionId": session, "prompt": [block]], timeout: nil)
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
                if !stopped {
                    append(Message(kind: .system, text: error.localizedDescription), to: id)
                    if SlashCommand.split(prompt) != nil { banner = error.localizedDescription }
                }
                discardConnection(id)
            }
        }
    }

    private func connect(id: UUID, project: Project, operationID: UUID) async throws -> ACPClient {
        try checkOperation(id, operationID: operationID)
        if let client = clients[id], loaded.contains(id) {
            if let mode = pendingModes[id] {
                _ = try await client.request("session/set_mode", params: ["sessionId": task(id)?.sessionID ?? "", "modeId": mode])
                try checkOperation(id, operationID: operationID)
                pendingModes.removeValue(forKey: id); runs[id]?.modeID = mode
            }
            return client
        }
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
        if let commands = (initial["_meta"] as? [String: Any])?["availableCommands"] as? [[String: Any]] {
            runs[id, default: RunState()].commands = SlashCommand.parse(commands)
        }
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
        if let options = result["configOptions"] as? [[String: Any]] { applyConfigOptions(options, id: id) }
        if let desired = task(id)?.modelID, desired != runs[id]?.modelID {
            try await updateConfig(client, id: id, key: "model", value: desired)
            try checkOperation(id, operationID: operationID)
        }
        if let desired = task(id)?.reasoningID, desired != runs[id]?.reasoningID,
           runs[id]?.reasoningOptions.contains(where: { $0.id == desired }) == true {
            try await updateConfig(client, id: id, key: "reasoning_effort", value: desired)
            try checkOperation(id, operationID: operationID)
        }
        if let mode = pendingModes.removeValue(forKey: id) {
            _ = try await client.request("session/set_mode", params: ["sessionId": task(id)?.sessionID ?? "", "modeId": mode])
            try checkOperation(id, operationID: operationID)
            runs[id]?.modeID = mode
        }
        do { try await loadCommands(client, id: id, project: project) }
        catch { /* AvailableCommandsUpdate remains authoritative if pull is unsupported. */ }
        loaded.insert(id); persistSessionOptions(id); save(); return client
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
        let method = method.hasPrefix("_") ? String(method.dropFirst()) : method
        if let session = params["sessionId"] as? String, let expected = task(id)?.sessionID, session != expected { return }
        if receiveFeatureNotification(method, params: params, id: id) { return }
        if method == "x.ai/models/update" {
            runs[id, default: RunState()].models = SessionOptions.models(params)
            return
        }
        guard method == "session/update", let update = params["update"] as? [String: Any] else { return }
        let kind = update["sessionUpdate"] as? String ?? ""
        if kind == "available_commands_update" {
            runs[id, default: RunState()].commands = SlashCommand.parse(update["availableCommands"] as? [[String: Any]] ?? [])
            runs[id]?.commandsLoaded = true
            runs[id]?.availableTools = (update["_meta"] as? [String: Any])?["tools"] as? [String]
            return
        }
        if kind == "config_option_update", let options = update["configOptions"] as? [[String: Any]] {
            applyConfigOptions(options, id: id)
            if loaded.contains(id) { persistSessionOptions(id) }
        }
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
        let method = method.hasPrefix("_") ? String(method.dropFirst()) : method
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
        runs[id]?.isRunning = false; runs[id]?.isConfiguring = false
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
        runs[id]?.isRunning = false; runs[id]?.isConfiguring = false; runs[id]?.phase = phase
    }

    func setModel(_ model: ModelOption) {
        guard !run.isRunning, !run.isConfiguring else { return }
        guard run.models.contains(where: { $0.id == model.id }) else {
            banner = "That model is no longer available. Reload the model choices and try again."; return
        }
        if state.selectedConversationID == nil {
            catalogRun.modelID = model.id
            state.selectedModelID = model.id
            updateCatalogReasoning(preferred: state.selectedReasoningID)
            state.selectedReasoningID = catalogRun.reasoningID.isEmpty ? nil : catalogRun.reasoningID
            save()
        } else {
            setSessionOption(key: "model", value: model.id)
        }
    }

    func setReasoning(_ option: ModelOption) {
        guard !run.isRunning, !run.isConfiguring else { return }
        guard run.reasoningOptions.contains(where: { $0.id == option.id }) else {
            banner = "That thinking level is not supported by this model."; return
        }
        if state.selectedConversationID == nil {
            catalogRun.reasoningID = option.id
            state.selectedReasoningID = option.id
            save()
        } else {
            setSessionOption(key: "reasoning_effort", value: option.id)
        }
    }

    func setMode(_ mode: ModelOption) {
        if state.selectedConversationID == nil { _ = ensureConversation(title: "New task") }
        setSessionOption(key: "mode", value: mode.id)
    }

    private func updateCatalogReasoning(preferred: String?) {
        let model = catalogRun.models.first { $0.id == catalogRun.modelID }
        catalogRun.reasoningOptions = model?.reasoningOptions ?? []
        catalogRun.reasoningID = preferred.flatMap { candidate in
            catalogRun.reasoningOptions.first { $0.id == candidate }?.id
        } ?? model?.defaultReasoningID ?? ""
    }

    private func setSessionOption(key: String, value: String) {
        guard let id = state.selectedConversationID, let project, !run.isRunning, !run.isConfiguring else { return }
        let operationID = beginOperation(id, phase: "Updating settings")
        runs[id]?.isConfiguring = true
        banner = nil
        operations[id] = Task {
            defer { finishOperation(id, operationID: operationID) }
            do {
                let client = try await connect(id: id, project: project, operationID: operationID)
                try checkOperation(id, operationID: operationID)
                if key == "mode" {
                    guard let session = task(id)?.sessionID else { throw DesktopError.message("The task has no session.") }
                    _ = try await client.request("session/set_mode", params: ["sessionId": session, "modeId": value])
                    try checkOperation(id, operationID: operationID)
                    runs[id]?.modeID = value
                } else {
                    try await updateConfig(client, id: id, key: key, value: value)
                    try checkOperation(id, operationID: operationID)
                    persistSessionOptions(id)
                    state.selectedModelID = runs[id]?.modelID
                    state.selectedReasoningID = runs[id]?.reasoningID.isEmpty == false ? runs[id]?.reasoningID : nil
                    catalogProjectID = project.id
                    catalogRun.models = runs[id]?.models ?? []
                    catalogRun.modelID = runs[id]?.modelID ?? ""
                    updateCatalogReasoning(preferred: state.selectedReasoningID)
                }
                runs[id]?.phase = "Ready"; save()
            } catch {
                guard operationIDs[id] == operationID else { return }
                runs[id]?.phase = "Needs attention"
                if !(error is CancellationError) { banner = "Could not change task settings: \(error.localizedDescription)" }
                // A timeout may have applied remotely. Reconnect before the next prompt to reconcile.
                discardConnection(id)
            }
        }
    }

    private func updateConfig(_ client: ACPClient, id: UUID, key: String, value: String) async throws {
        guard let session = task(id)?.sessionID else { throw DesktopError.message("The task has no session.") }
        let result = try await client.request("session/set_config_option", params: [
            "sessionId": session, "configId": key, "value": value
        ])
        guard task(id) != nil, clients[id] === client else { throw CancellationError() }
        guard let options = result["configOptions"] as? [[String: Any]] else {
            throw DesktopError.message("The runtime did not confirm the updated task settings.")
        }
        applyConfigOptions(options, id: id)
        let confirmed = key == "model" ? runs[id]?.modelID : runs[id]?.reasoningID
        guard confirmed == value else { throw DesktopError.message("The runtime did not apply the selected setting. Try another option.") }
    }

    private func persistSessionOptions(_ id: UUID) {
        guard let index = state.conversations.firstIndex(where: { $0.id == id }), let run = runs[id] else { return }
        state.conversations[index].modelID = run.modelID.isEmpty ? nil : run.modelID
        state.conversations[index].reasoningID = run.reasoningID.isEmpty ? nil : run.reasoningID
        save()
    }

    private func applyModels(_ models: [String: Any], id: UUID) {
        runs[id, default: RunState()].models = SessionOptions.models(models)
        runs[id]?.modelID = models["currentModelId"] as? String ?? ""
        let selected = runs[id]?.models.first { $0.id == runs[id]?.modelID }
        runs[id]?.reasoningOptions = selected?.reasoningOptions ?? []
        runs[id]?.reasoningID = selected?.defaultReasoningID ?? ""
    }

    private func applyConfigOptions(_ options: [[String: Any]], id: UUID) {
        if let model = options.first(where: { $0["id"] as? String == "model" }) {
            let catalog = runs[id]?.models ?? []
            runs[id, default: RunState()].models = SessionOptions.choices(model).map { option in
                catalog.first(where: { $0.id == option.id }) ?? option
            }
            runs[id]?.modelID = model["currentValue"] as? String ?? ""
        }
        let effort = options.first { $0["id"] as? String == "reasoning_effort" }
        runs[id, default: RunState()].reasoningOptions = effort.map(SessionOptions.choices) ?? []
        runs[id]?.reasoningID = effort?["currentValue"] as? String ?? ""
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
                              !state.deletedSessionIDs.contains(sessionID),
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
        guard let task = conversation, !loaded.contains(task.id), let project, runs[task.id]?.isRunning != true else { return }
        banner = nil
        let operationID = beginOperation(task.id, phase: "Loading history")
        importing.insert(task.id)
        importBuffers[task.id] = []
        defer { finishOperation(task.id, operationID: operationID) }
        do {
            _ = try await connect(id: task.id, project: project, operationID: operationID)
            try checkOperation(task.id, operationID: operationID)
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
    func login(provider: String) {
        guard !loginRunning else { return }
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else { loginLog = "The bundled Grok runtime is missing. Reinstall Grok Desktop."; return }
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
                if process.terminationStatus == 0 { self?.refreshModelsAfterLogin() }
            }
        }
        do { try process.run() } catch { output.fileHandleForReading.readabilityHandler = nil; loginRunning = false; loginLog = error.localizedDescription }
    }
    private func refreshModelsAfterLogin() {
        catalogProjectID = nil
        commandCatalogProjectID = nil
        catalogClient?.stop(); catalogClient = nil
        catalogRun.isConfiguring = false; catalogLoadingProjectID = nil
        for id in Array(clients.keys) where runs[id]?.isRunning != true { discardConnection(id) }
        Task { await prepareSessionOptions() }
    }
    func cancelLogin() { loginProcess?.terminate() }
    func shutdown() {
        saveTask?.cancel(); flush()
        featureNotificationRefresh?.cancel()
        for client in auxiliaryClients.values { client.stop() }
        auxiliaryClients.removeAll()
        for id in Set(clients.keys).union(operationIDs.keys) { stopOperation(id, phase: "Stopped") }
        historyClient?.stop(); historyClient = nil
        catalogClient?.stop(); catalogClient = nil
        loginProcess?.terminate()
    }
    private func task(_ id: UUID) -> Conversation? { state.conversations.first { $0.id == id } }
    func append(_ message: Message, to id: UUID) {
        guard let i = state.conversations.firstIndex(where: { $0.id == id }) else { return }
        state.conversations[i].messages.append(message); state.conversations[i].updatedAt = Date(); save()
    }
}

enum DesktopError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

extension AppStore {
    var availableCommands: [SlashCommand] {
        var commands = DesktopCommands.catalog.filter { command in
            guard let tool = MediaCommand.requiredTool(command.name) else { return true }
            return run.availableTools?.contains(tool) == true
        }
        for command in run.commands {
            if let index = commands.firstIndex(where: { $0.name == command.name }) {
                // Keep native panels, but show the runtime's argument contract.
                if commands[index].argumentHint == nil { commands[index].argumentHint = command.argumentHint }
            } else { commands.append(command) }
        }
        return commands
    }

    func executeCommand(name: String, arguments: String = "") {
        if handleDesktopCommand(name, arguments: arguments) { return }
        if name == "goal", ["status", "pause", "resume", "clear"].contains(arguments), run.isRunning {
            goalAction(arguments); return
        }
        guard !run.isRunning, !run.isConfiguring else { banner = "Wait for the current turn to finish or stop it before running /\(name)."; return }
        let previousDraft = draft
        let previousProjectID = state.selectedProjectID
        draft = "/\(name)" + (arguments.isEmpty ? "" : " \(arguments)")
        send()
        if !previousDraft.isEmpty, SlashCommand.split(previousDraft) == nil,
           state.selectedProjectID == previousProjectID, draft.isEmpty {
            draft = previousDraft; drafts[draftLocation] = previousDraft
        }
    }

    private func loadCommands(_ client: ACPClient, id: UUID, project: Project) async throws {
        var params: [String: Any] = ["cwd": project.path]
        if let session = task(id)?.sessionID { params["sessionId"] = session }
        let response = try ExtensionResponse.unwrap(try await client.request("_x.ai/commands/list", params: params))
        guard clients[id] === client else { throw CancellationError() }
        runs[id, default: RunState()].commands = SlashCommand.parse(response["commands"] as? [[String: Any]] ?? [])
        runs[id]?.commandsLoaded = true
        runs[id]?.availableTools = response["tools"] as? [String] ?? runs[id]?.availableTools
    }

    func refreshCommands() async {
        guard let project else { return }
        do {
            if let id = state.selectedConversationID, let client = clients[id], loaded.contains(id) {
                try await loadCommands(client, id: id, project: project)
            } else {
                let client = ACPClient()
                let clientID = UUID(); auxiliaryClients[clientID] = client
                defer { client.stop(); auxiliaryClients.removeValue(forKey: clientID) }
                try client.start(executable: binaryPath, cwd: project.path)
                let initial = try await initialize(client)
                try await authenticate(client, initial: initial)
                let response = try ExtensionResponse.unwrap(try await client.request("_x.ai/commands/list", params: ["cwd": project.path]))
                guard self.project?.id == project.id else { return }
                catalogRun.commands = SlashCommand.parse(response["commands"] as? [[String: Any]] ?? [])
                catalogRun.commandsLoaded = true
                catalogRun.availableTools = response["tools"] as? [String]
                commandCatalogProjectID = project.id
            }
        } catch { banner = "Could not load commands: \(error.localizedDescription)" }
    }

    @discardableResult
    private func ensureConversation(title: String) -> UUID? {
        if let id = state.selectedConversationID { return id }
        guard let project else { return nil }
        let item = Conversation(projectID: project.id, title: title, modelID: state.selectedModelID, reasoningID: state.selectedReasoningID)
        state.conversations.insert(item, at: 0)
        state.selectedConversationID = item.id
        save()
        return item.id
    }

    func featureSession() async throws -> (ACPClient, UUID, String) {
        guard let project, let id = ensureConversation(title: "New task") else { throw DesktopError.message("Open a project first.") }
        if let client = clients[id], loaded.contains(id), let session = task(id)?.sessionID { return (client, id, session) }
        guard runs[id]?.isRunning != true else { throw DesktopError.message("The task is still connecting. Try again when it is ready.") }
        let operationID = beginOperation(id, phase: "Connecting")
        runs[id]?.isConfiguring = true
        defer { finishOperation(id, operationID: operationID) }
        do {
            let client = try await connect(id: id, project: project, operationID: operationID)
            try checkOperation(id, operationID: operationID)
            guard let session = task(id)?.sessionID else { throw DesktopError.message("The runtime did not create a session.") }
            runs[id]?.phase = "Ready"
            return (client, id, session)
        } catch {
            if operationIDs[id] == operationID { discardConnection(id); runs[id]?.phase = "Needs attention" }
            throw error
        }
    }

    func enterPlanMode(description: String = "") {
        guard !run.isRunning, !run.isConfiguring, let id = ensureConversation(title: description.isEmpty ? "Plan" : String(description.prefix(64))) else { return }
        if description.isEmpty {
            if let command = SlashCommand.split(draft), command.name == "plan", command.arguments.isEmpty { draft = "" }
            setSessionOption(key: "mode", value: "plan")
        }
        else {
            pendingModes[id] = "plan"
            draft = description; send()
        }
    }

    func createGoal(objective: String, tokenBudget: Int? = nil) {
        let text = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { featureError = "Enter a goal objective."; return }
        guard tokenBudget == nil || tokenBudget! > 0 else { featureError = "The token budget must be positive."; return }
        executeCommand(name: "goal", arguments: text + (tokenBudget.map { " --budget \($0)" } ?? ""))
    }

    func goalAction(_ action: String) {
        guard ["status", "pause", "resume", "clear"].contains(action) else { return }
        guard run.isRunning else { executeCommand(name: "goal", arguments: action); return }
        if action == "status" { featureRows = goalRows(); return }
        if action == "resume" { featureError = "The goal is already running."; return }
        guard let id = state.selectedConversationID, let project, run.goal != nil else { featureError = "This task does not have an active goal."; return }
        // The harness queues prompt requests behind a running turn. Cancel is its
        // immediate control path and durably pauses the active goal.
        let previousOperation = operations[id]
        cancel()
        guard action == "clear" else { return }
        Task {
            await previousOperation?.value
            guard task(id) != nil, runs[id]?.isRunning != true else { return }
            let operationID = beginOperation(id, phase: "Clearing goal")
            defer { finishOperation(id, operationID: operationID) }
            do {
                let client = try await connect(id: id, project: project, operationID: operationID)
                guard let session = task(id)?.sessionID else { return }
                _ = try await client.request("session/prompt", params: ["sessionId": session, "prompt": [["type": "text", "text": "/goal clear"]]], timeout: 60)
                try checkOperation(id, operationID: operationID)
                runs[id]?.phase = "Ready"
            } catch {
                if operationIDs[id] == operationID { runs[id]?.phase = "Needs attention"; featureError = "Could not clear goal: \(error.localizedDescription)" }
            }
        }
    }

    func refreshFeatures(_ panel: FeaturePanel) async {
        let requestID = UUID()
        featureRequestID = requestID; featureLoading = true; featureError = nil; featureRows = []
        defer { if featureRequestID == requestID { featureLoading = false } }
        guard let project else { featureError = "Open a project first."; return }
        do {
            if [.plan, .models, .reasoning, .history, .transcript].contains(panel) { return }
            if panel == .goals { featureRows = goalRows(); return }
            var temporary: ACPClient?
            let temporaryID = UUID()
            defer { temporary?.stop(); auxiliaryClients.removeValue(forKey: temporaryID) }
            let client: ACPClient
            var session: String?
            var id = state.selectedConversationID
            if [.skills, .personas, .agentDefinitions].contains(panel), id == nil {
                let fresh = ACPClient(); temporary = fresh; client = fresh
                auxiliaryClients[temporaryID] = fresh
                try fresh.start(executable: binaryPath, cwd: project.path)
                let initial = try await initialize(fresh)
                try await authenticate(fresh, initial: initial)
            } else {
                let context = try await featureSession(); client = context.0; id = context.1; session = context.2
            }
            var params: [String: Any] = ["cwd": project.path]
            if let session { params["sessionId"] = session }
            let method: String
            switch panel {
            case .mcps: method = "mcp/list"
            case .skills: method = "skills/list"
            case .agents: method = "subagent/list_running"
            case .plugins: method = "plugins/list"
            case .hooks: method = "hooks/list"
            case .memory: method = "memory/list"
            case .workflows: method = "workflows/list"
            case .personas, .agentDefinitions: method = "bundle/status"
            default: return
            }
            let result = try ExtensionResponse.unwrap(try await client.request("_x.ai/\(method)", params: params, timeout: 60))
            guard featureRequestID == requestID, self.project?.id == project.id, state.selectedConversationID == id else { return }
            if let id, panel == .agents {
                for item in result["subagents"] as? [[String: Any]] ?? [] { updateSubagent(item, id: id) }
                featureRows = runs[id]?.subagents.map(\.row) ?? []
            } else { featureRows = rows(for: panel, result: result, project: project) }
        } catch {
            if featureRequestID == requestID { featureError = error.localizedDescription }
        }
    }

    private func rows(for panel: FeaturePanel, result: [String: Any], project: Project) -> [FeatureRow] {
        switch panel {
        case .mcps:
            return (result["servers"] as? [[String: Any]] ?? []).compactMap { item in
                guard let name = item["name"] as? String else { return nil }
                let session = item["session"] as? [String: Any] ?? [:]
                let tools = session["tools"] as? [[String: Any]] ?? []
                let detail = ([item["url"] as? String ?? item["command"] as? String ?? "", session["blockedReason"] as? String ?? ""] + tools.map { "\($0["name"] as? String ?? "Tool"): \($0["description"] as? String ?? "")" }).filter { !$0.isEmpty }.joined(separator: "\n")
                return FeatureRow(id: name, title: item["displayName"] as? String ?? name,
                    subtitle: "\(session["status"] as? String ?? "Configured") · \(tools.count) tools", detail: detail,
                    enabled: session["enabled"] as? Bool, actions: ["Restart"] + (session["authRequired"] as? Bool == true ? ["Sign in"] : []), payload: item)
            }
        case .skills:
            let skills = result["skills"] as? [[String: Any]] ?? []
            return skills.compactMap { item in
                guard let name = item["name"] as? String else { return nil }
                let plugin = item["plugin_name"] as? String
                let path = item["path"] as? String
                let invocation = run.commands.first(where: { path != nil && $0.skillPath == path })?.name ?? "\(plugin ?? item["scope"] as? String ?? "user"):\(name)"
                var payload = item; payload["invocation"] = invocation
                let uniqueID = skills.filter { $0["name"] as? String == name }.count > 1 ? (path ?? invocation) : name
                return FeatureRow(id: uniqueID, title: item["display_name"] as? String ?? name,
                    subtitle: item["short_description"] as? String ?? item["description"] as? String ?? "",
                    detail: [plugin ?? item["scope"] as? String ?? "", item["path"] as? String ?? ""].filter { !$0.isEmpty }.joined(separator: " · "),
                    enabled: item["enabled"] as? Bool ?? true,
                    actions: item["user_invocable"] as? Bool == false || item["enabled"] as? Bool == false ? [] : ["Use"], payload: payload)
            }
        case .plugins, .hooks, .workflows:
            let key = panel.rawValue
            return (result[key] as? [[String: Any]] ?? []).enumerated().map { index, item in
                let name = item["name"] as? String ?? item["id"] as? String ?? "\(key) \(index + 1)"
                let enabled = panel == .workflows ? nil : item["enabled"] as? Bool ?? !(item["disabled"] as? Bool ?? false)
                return FeatureRow(id: item["id"] as? String ?? name, title: name,
                    subtitle: item["description"] as? String ?? item["event"] as? String ?? "",
                    detail: item["path"] as? String ?? item["root"] as? String ?? item["command"] as? String ?? "",
                    enabled: enabled, actions: panel == .workflows ? ["Use"] : ["Reload"], payload: item)
            }
        case .memory:
            let enabled = result["enabled"] as? Bool ?? true
            return [FeatureRow(id: "memory-setting", title: "Conversation memory", subtitle: enabled ? "Enabled" : "Disabled", enabled: enabled)] +
                (result["files"] as? [[String: Any]] ?? []).compactMap { item in
                    guard let path = item["path"] as? String else { return nil }
                    return FeatureRow(id: path, title: item["title"] as? String ?? URL(fileURLWithPath: path).lastPathComponent,
                        subtitle: item["source"] as? String ?? "", detail: path, actions: ["Open"], payload: item)
                }
        case .agentDefinitions, .personas:
            let kind = panel == .personas ? "personas" : "agents"
            let details = result["personaDetails"] as? [[String: Any]] ?? []
            var rows = (result[kind] as? [String] ?? []).map { name in
                FeatureRow(id: "bundled:\(name)", title: name, subtitle: "Bundled",
                    detail: details.first(where: { $0["name"] as? String == name })?["description"] as? String ?? "",
                    actions: ["Inspect"], payload: ["kind": panel == .personas ? "persona" : "agent", "name": name])
            }
            let roots = [URL(fileURLWithPath: project.path).appendingPathComponent(".grok/\(kind)"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/\(kind)")]
            for root in roots {
                for file in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where ["md", "toml", "yaml", "yml"].contains(file.pathExtension) {
                    rows.append(FeatureRow(id: file.path, title: file.deletingPathExtension().lastPathComponent, subtitle: root == roots.first ? "Project" : "User", detail: file.path, actions: ["Open"], payload: ["path": file.path]))
                }
            }
            return rows
        default: return []
        }
    }

    private func goalRows() -> [FeatureRow] {
        guard let goal = run.goal, goal.status != "cleared" else { return [] }
        return [FeatureRow(id: goal.id, title: goal.objective, subtitle: "\(goal.status) · \(goal.phase)",
            detail: "\(goal.tokensUsed) tokens" + (goal.tokenBudget.map { " of \($0)" } ?? "") + (goal.detail.isEmpty ? "" : "\n\(goal.detail)"),
            actions: ["Status"] + (goal.isActive ? ["Pause"] : goal.isPaused ? ["Resume"] : []) + ["Clear"])]
    }

    func toggleFeature(_ row: FeatureRow, panel: FeaturePanel) {
        guard let enabled = row.enabled else { return }
        let cwd = project?.path ?? ""
        performFeatureAction(panel) { client, _, session in
            var params: [String: Any]
            let method: String
            switch panel {
            case .mcps: method = "mcp/toggle"; params = ["session_id": session, "server_name": row.id, "enabled": !enabled]
            case .skills: method = "skills/toggle"; params = ["name": row.payload["name"] as? String ?? row.id, "enabled": !enabled, "cwd": cwd]
            case .plugins: method = "plugins/action"; params = ["sessionId": session, "action": ["type": enabled ? "disable" : "enable", "plugin_id": row.id]]
            case .hooks: method = "hooks/action"; params = ["sessionId": session, "action": ["type": enabled ? "disable" : "enable", "hook_name": row.id]]
            case .memory: method = "memory/toggle"; params = ["sessionId": session, "enabled": !enabled]
            default: return
            }
            _ = try ExtensionResponse.unwrap(try await client.request("_x.ai/\(method)", params: params))
        }
    }

    func invokeFeature(_ row: FeatureRow, panel: FeaturePanel, action: String, arguments: String = "") {
        let action = action.lowercased()
        if panel == .goals { goalAction(action); return }
        if action == "run" || action == "use" {
            featurePanel = nil
            if panel == .skills { draft = "/\(row.payload["invocation"] as? String ?? row.id) " + arguments }
            else if panel == .workflows { draft = "/workflow \(row.title) " + arguments }
            return
        }
        if action == "open", let path = row.payload["path"] as? String {
            NSWorkspace.shared.open(URL(fileURLWithPath: path)); return
        }
        performFeatureAction(panel, refresh: action != "inspect") { client, id, session in
            var result: [String: Any] = [:]
            switch (panel, action) {
            case (.mcps, "restart"):
                _ = try ExtensionResponse.unwrap(try await client.request("_x.ai/mcp/toggle", params: ["session_id": session, "server_name": row.id, "enabled": false]))
                result = try ExtensionResponse.unwrap(try await client.request("_x.ai/mcp/toggle", params: ["session_id": session, "server_name": row.id, "enabled": true]))
            case (.mcps, "sign in"):
                result = try ExtensionResponse.unwrap(try await client.request("_x.ai/mcp/auth_trigger", params: ["session_id": session, "server_name": row.id], timeout: 120))
            case (.agents, "stop"):
                result = try ExtensionResponse.unwrap(try await client.request("_x.ai/subagent/cancel", params: ["subagentId": row.id]))
                if let outcome = result["outcome"] as? [String: Any], let index = self.runs[id]?.subagents.firstIndex(where: { $0.id == row.id }) {
                    if outcome["kind"] as? String == "already_finished" { self.runs[id]?.subagents[index].status = outcome["status"] as? String ?? "completed" }
                    else if outcome["kind"] as? String == "not_found" { self.runs[id]?.subagents[index].status = "unavailable" }
                }
            case (.agents, "inspect"):
                result = try ExtensionResponse.unwrap(try await client.request("_x.ai/subagent/get", params: ["subagentId": row.id, "block": false]))
                if let snapshot = result["snapshot"] as? [String: Any] { self.updateSubagent(snapshot, id: id) }
            case (.agents, "message"):
                guard !arguments.isEmpty, let address = self.runs[id]?.subagents.first(where: { $0.id == row.id })?.address else { throw DesktopError.message("Enter a message for an active subagent.") }
                result = try ExtensionResponse.unwrap(try await client.request("_x.ai/subagent/message", params: ["sessionId": session, "agentAddress": address, "content": [["type": "text", "text": arguments]]]))
                guard result["kind"] as? String == "accepted" else { throw DesktopError.message("The subagent did not accept the message (\(result["kind"] as? String ?? "unknown outcome")).") }
            case (.personas, "inspect"), (.agentDefinitions, "inspect"):
                result = try ExtensionResponse.unwrap(try await client.request("_x.ai/bundle/entry/get", params: ["kind": row.payload["kind"] as? String ?? "agents", "name": row.payload["name"] as? String ?? row.title]))
                if let content = result["content"] as? String, let index = self.featureRows.firstIndex(where: { $0.id == row.id }) { self.featureRows[index].detail = content }
            case (.hooks, "reload"), (.plugins, "reload"):
                result = try ExtensionResponse.unwrap(try await client.request("_x.ai/\(panel.rawValue)/action", params: ["sessionId": session, "action": ["type": "reload"]]))
            default: throw DesktopError.message("This action is not available for \(panel.title).")
            }
            if let message = result["message"] as? String { self.banner = message }
        }
    }

    func performFeatureAction(_ panel: FeaturePanel, refresh: Bool = true, action: @escaping (ACPClient, UUID, String) async throws -> Void) {
        guard !featureLoading else { return }
        let requestID = UUID()
        featureRequestID = requestID
        let project = self.project
        let selectedID = state.selectedConversationID
        let selectedPanel = featurePanel
        featureLoading = true; featureError = nil
        Task {
            defer { if featureRequestID == requestID { featureLoading = false } }
            do {
                guard self.project?.id == project?.id, self.state.selectedConversationID == selectedID else { throw CancellationError() }
                let context = try await featureSession()
                guard self.project?.id == project?.id, self.state.selectedConversationID == context.1 else { throw CancellationError() }
                try await action(context.0, context.1, context.2)
                guard featureRequestID == requestID, self.project?.id == project?.id, self.state.selectedConversationID == context.1, self.featurePanel == selectedPanel else { return }
                if let project { try await loadCommands(context.0, id: context.1, project: project) }
                guard featureRequestID == requestID, self.state.selectedConversationID == context.1, self.featurePanel == selectedPanel else { return }
                if refresh { await refreshFeatures(panel) }
                else if panel == .agents { featureRows = runs[context.1]?.subagents.map(\.row) ?? [] }
            } catch {
                if featureRequestID == requestID, !(error is CancellationError), self.featurePanel == selectedPanel { featureError = error.localizedDescription }
            }
        }
    }

    private func updateSubagent(_ value: [String: Any], id: UUID) {
        guard let agentID = value["subagent_id"] as? String ?? value["subagentId"] as? String else { return }
        var agents = runs[id]?.subagents ?? []
        if let index = agents.firstIndex(where: { $0.id == agentID }) {
            let incomingAttempt = value["attempt_id"] as? String ?? value["attemptId"] as? String
            if value["sessionUpdate"] as? String == "subagent_spawned" {
                if incomingAttempt != agents[index].attemptID { agents[index] = SubagentState(id: agentID) }
                agents[index].status = "running"
            } else if let incomingAttempt, let currentAttempt = agents[index].attemptID, incomingAttempt != currentAttempt { return }
            agents[index].update(value)
        }
        else { var agent = SubagentState(id: agentID); agent.update(value); agents.append(agent) }
        runs[id, default: RunState()].subagents = agents
    }

    private func receiveFeatureNotification(_ method: String, params: [String: Any], id: UUID) -> Bool {
        if ["x.ai/mcp/servers_updated", "x.ai/mcp/tools_changed", "x.ai/mcp/server_status"].contains(method) {
            if state.selectedConversationID == id, featurePanel == .mcps, !featureLoading {
                featureNotificationRefresh?.cancel()
                featureNotificationRefresh = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
                    guard let self, self.state.selectedConversationID == id, self.featurePanel == .mcps, !self.featureLoading else { return }
                    await self.refreshFeatures(.mcps)
                }
            }
            return true
        }
        if method == "x.ai/session_notification", let nested = params["params"] as? [String: Any] {
            return receiveFeatureNotification(method, params: nested, id: id)
        }
        if let session = params["sessionId"] as? String, let expected = task(id)?.sessionID, session != expected { return true }
        guard ["x.ai/session/update", "x.ai/session_notification", "session/update"].contains(method), let update = params["update"] as? [String: Any] else { return false }
        if consumeAdvancedUpdate(update, id: id) { return true }
        switch update["sessionUpdate"] as? String {
        case "goal_updated":
            runs[id, default: RunState()].goal = GoalState(update)
            if state.selectedConversationID == id, featurePanel == .goals { featureRows = goalRows() }
            return true
        case "subagent_spawned", "subagent_progress", "subagent_finished":
            updateSubagent(update, id: id)
            if state.selectedConversationID == id, featurePanel == .agents { featureRows = runs[id]?.subagents.map(\.row) ?? [] }
            return true
        default: return false
        }
    }

    func forkSession() async {
        guard !run.isRunning, let source = conversation, let project else { banner = "Select a stopped task to fork."; return }
        do {
            let (client, _, session) = try await featureSession()
            let result = try ExtensionResponse.unwrap(try await client.request("_x.ai/session/fork", params: ["sourceSessionId": session, "sourceCwd": project.path, "newCwd": project.path]))
            guard let sessionID = result["newSessionId"] as? String else { throw DesktopError.message("The runtime did not return the forked session.") }
            let fork = Conversation(projectID: project.id, title: source.title + " (fork)", sessionID: sessionID, modelID: source.modelID, reasoningID: source.reasoningID)
            state.conversations.insert(fork, at: 0); selectConversation(fork)
            await loadImportedConversation()
        } catch { banner = "Could not fork task: \(error.localizedDescription)" }
    }

    func refreshAfterRewind(id: UUID, conversationChanged: Bool) async {
        let projectID = task(id)?.projectID
        if conversationChanged {
            discardConnection(id)
            runs[id]?.plan = []; runs[id]?.subagents = []; runs[id]?.goal = nil
            if state.selectedConversationID == id {
                savedPlanContent = nil; savedPlanError = nil
                await loadImportedConversation()
            }
        }
        if projectID == state.selectedProjectID { await refreshWorkspace() }
    }
}
