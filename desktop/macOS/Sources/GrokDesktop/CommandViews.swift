import SwiftUI
import AppKit

extension Notification.Name {
    static let grokFocusComposer = Notification.Name("ai.grok.desktop.focus-composer")
}

struct CommandList: View {
    let commands: [SlashCommand]
    var selected: Int
    var onSelect: (SlashCommand) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                        Button { onSelect(command) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: command.symbol).font(.system(size: 16)).foregroundStyle(Theme.muted).frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text("/" + command.name).font(.system(size: 14, weight: .medium))
                                        if let hint = command.argumentHint { Text(hint).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1) }
                                    }
                                    Text(command.description).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2)
                                }
                                Spacer(minLength: 4)
                                Text(command.source).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted)
                                    .padding(.horizontal, 6).padding(.vertical, 3).background(Theme.sidebar, in: Capsule())
                            }.padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(index == selected ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).id(command.id)
                            .accessibilityLabel("/\(command.name). \(command.description). \(command.source)")
                    }
                    if commands.isEmpty { Text("No matching commands").font(.system(size: 14)).foregroundStyle(Theme.muted).padding(30) }
                }.padding(6)
            }
            .onChange(of: selected) { _, value in
                if commands.indices.contains(value) { proxy.scrollTo(commands[value].id) }
            }
        }
    }
}

struct CommandPalette: View {
    @EnvironmentObject var store: AppStore
    @State private var query = ""
    @State private var selected = 0
    private var commands: [SlashCommand] { DesktopCommands.matches(store.availableCommands, query: query) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                NativeSearchField(text: $query, placeholder: "Search commands and skills", onEscape: { store.showCommandPalette = false },
                                  onSubmit: accept, onMove: move).frame(height: 40)
                Text("esc").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 5))
            }.padding(20)
            Divider()
            CommandList(commands: commands, selected: selected, onSelect: choose).frame(height: 370)
            Divider()
            HStack {
                Text("\(commands.count) commands")
                Spacer()
                Text("↑↓ Navigate   ↵ Select")
            }.font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.horizontal, 20).padding(.vertical, 14)
        }.frame(width: 660).background(Theme.surface)
            .onChange(of: query) { _, _ in selected = 0 }
            .task { await store.refreshCommands() }
    }

    private func move(_ delta: Int) { selected = min(max(0, selected + delta), max(0, commands.count - 1)) }
    private func accept() { if commands.indices.contains(selected) { choose(commands[selected]) } }
    private func choose(_ command: SlashCommand) {
        store.showCommandPalette = false
        if command.argumentHint != nil && !["plan", "plugins", "model", "effort", "theme", "cd"].contains(command.name) {
            store.draft = "/\(command.name) "
            DispatchQueue.main.async { NotificationCenter.default.post(name: .grokFocusComposer, object: nil) }
        } else {
            // Dismiss this sheet before presenting a destination sheet.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { store.executeCommand(name: command.name) }
        }
    }
}

extension FeaturePanel {
    var subtitle: String {
        switch self {
        case .mcps: return "Connect Grok to tools and data in your workspace."
        case .skills: return "Reusable instructions, discovered from your project and plugins."
        case .agents: return "Follow the agents working alongside this task."
        case .agentDefinitions: return "Agent roles available to the harness."
        case .personas: return "Specialized instructions for agents."
        case .goals: return "Keep working toward an objective across turns."
        case .plan: return "Review the steps before implementation."
        case .workflows: return "Launch a workflow or check its progress."
        case .plugins: return "Extensions loaded by your Grok harness."
        case .hooks: return "Actions triggered by events in the harness."
        case .memory: return "Saved knowledge available to this task."
        case .models: return "Choose the model for your next message."
        case .reasoning: return "Control how much the selected model thinks."
        case .history: return "Choose a prompt to reuse it in the composer."
        case .transcript: return "Search the messages in this task."
        }
    }
    var isLocal: Bool { [.plan, .models, .reasoning, .history, .transcript].contains(self) }
}

struct FeatureBrowser: View {
    @EnvironmentObject var store: AppStore
    let panel: FeaturePanel
    @State private var search = ""
    @State private var objective = ""
    @State private var budget = ""
    @State private var actionInput = ""
    @State private var expanded: Set<String> = []
    @State private var messageRecipient: String?
    @State private var showAddMCP = false
    @State private var mcpName = ""
    @State private var mcpTransport = "http"
    @State private var mcpEndpoint = ""
    @State private var mcpArguments = ""
    @State private var removeServer: FeatureRow?

    private var rows: [FeatureRow] {
        store.featureRows.filter { search.isEmpty || "\($0.title) \($0.subtitle) \($0.detail)".localizedCaseInsensitiveContains(search) }
    }
    private var controlsDisabled: Bool { store.featureLoading || store.run.isConfiguring }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(panel.title).font(.system(size: 23, weight: .semibold))
                    Text(panel.subtitle).font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                if !panel.isLocal {
                    IconButton(icon: "arrow.clockwise", help: "Refresh \(panel.title)") {
                        Task { await store.refreshFeatures(panel) }
                    }.disabled(controlsDisabled)
                }
                IconButton(icon: "xmark", help: "Close") { store.featurePanel = nil }.keyboardShortcut(.cancelAction)
            }.padding(24)
            if panel != .goals && panel != .plan {
                NativeSearchField(text: $search, placeholder: "Search \(panel.title.lowercased())", onEscape: { store.featurePanel = nil })
                    .frame(height: 40).padding(.horizontal, 24).padding(.bottom, 20)
            }
            Divider()
            if let error = store.featureError, !panel.isLocal {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error).textSelection(.enabled)
                    Spacer()
                    Button("Retry") { Task { await store.refreshFeatures(panel) } }
                        .buttonStyle(SubtleButtonStyle())
                }.font(.system(size: 13)).padding(.horizontal, 24).padding(.vertical, 16).background(Theme.hover.opacity(0.55))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !panel.isLocal {
                        ForEach(store.run.approvals) { ApprovalCard(approval: $0) }
                        ForEach(store.run.questions) { QuestionCard(request: $0) }
                    }
                    if panel.isLocal { localContent }
                    else {
                        if panel == .goals { goalForm }
                        if panel == .mcps && showAddMCP { mcpForm }
                        if store.featureLoading { ProgressView("Loading \(panel.title.lowercased())…").frame(maxWidth: .infinity).padding(25) }
                        ForEach(rows) { row in featureRow(row) }
                        if rows.isEmpty && !store.featureLoading && store.featureError == nil {
                            VStack(spacing: 10) {
                                Image(systemName: search.isEmpty ? "tray" : "magnifyingglass").font(.system(size: 25)).foregroundStyle(Theme.muted)
                                Text(search.isEmpty ? emptyLabel : "No matching results").font(.system(size: 14)).foregroundStyle(Theme.muted)
                            }.frame(maxWidth: .infinity).padding(35)
                        }
                    }
                }.padding(24)
            }.frame(height: panel == .mcps && showAddMCP ? 430 : 360)
            Divider()
            footer.padding(.horizontal, 24).padding(.vertical, 20)
        }.frame(width: 720).background(Theme.surface)
            .task(id: panel) {
                if panel == .plan { await store.loadSavedPlan() }
                else if !panel.isLocal { await store.refreshFeatures(panel) }
            }
            .confirmationDialog("Remove this MCP server?", isPresented: Binding(get: { removeServer != nil }, set: { if !$0 { removeServer = nil } }), titleVisibility: .visible) {
                if let server = removeServer { Button("Remove \(server.title)", role: .destructive) { store.removeMCPServer(server.id); removeServer = nil } }
            } message: { Text("The server will be removed from your Grok configuration. You can add it again later.") }
    }

    private var emptyLabel: String {
        panel == .agents ? "No subagents are running in this task." : panel == .goals ? "No goal has been set for this task." : "No \(panel.title.lowercased()) available in this workspace."
    }

    @ViewBuilder private var localContent: some View {
        switch panel {
        case .models, .reasoning:
            let options = panel == .models ? store.run.models : store.run.reasoningOptions
            ForEach(options.filter { search.isEmpty || "\($0.name) \($0.id)".localizedCaseInsensitiveContains(search) }) { option in
                Button {
                    if panel == .models { store.setModel(option) } else { store.setReasoning(option) }
                    store.featurePanel = nil
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) { Text(option.name).fontWeight(.medium); Text(option.id).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted) }
                        Spacer()
                        if option.id == (panel == .models ? store.run.modelID : store.run.reasoningID) { Image(systemName: "checkmark") }
                    }.padding(13).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(store.run.isRunning || controlsDisabled)
            }
            if options.isEmpty { Text("No choices are available for this session.").foregroundStyle(Theme.muted).padding(20) }
        case .plan:
            if store.savedPlanLoading { ProgressView("Loading saved plan…").padding(20) }
            if let error = store.savedPlanError { Text(error).foregroundStyle(Theme.muted).padding(10) }
            if let content = store.savedPlanContent { MarkdownContent(text: content).padding(10) }
            if store.run.plan.isEmpty && store.savedPlanContent == nil && !store.savedPlanLoading { Text("No saved plan yet. Use /plan to ask Grok to prepare a plan.").foregroundStyle(Theme.muted).padding(20) }
            ForEach(store.run.plan) { entry in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: entry.status == "completed" ? "checkmark.circle.fill" : "circle")
                    Text(entry.content).textSelection(.enabled)
                    Spacer()
                    Text(entry.status.replacingOccurrences(of: "_", with: " ")).font(.system(size: 11)).foregroundStyle(Theme.muted)
                }.padding(10)
            }
            ForEach(store.run.approvals.filter { $0.options.contains { $0.id.hasPrefix("plan:") } }) { ApprovalCard(approval: $0) }
        case .history, .transcript:
            let messages = (store.conversation?.messages ?? []).filter { (panel != .history || $0.kind == .user) && (search.isEmpty || $0.text.localizedCaseInsensitiveContains(search)) }
            if messages.isEmpty { Text("No matching messages.").foregroundStyle(Theme.muted).padding(20) }
            ForEach(messages) { message in
                if panel == .history {
                    Button { store.draft = message.text; store.featurePanel = nil; focusComposer() } label: {
                        Text(message.text).lineLimit(4).frame(maxWidth: .infinity, alignment: .leading).padding(12).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                } else { MessageView(message: message).padding(.vertical, 8) }
            }
        default: EmptyView()
        }
    }

    private var goalForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            DesktopTextField("What should Grok work toward?", text: $objective, title: "Objective", symbol: "scope", multiline: true)
            HStack(alignment: .bottom, spacing: 16) {
                DesktopTextField("e.g. 100000", text: $budget, title: "Token budget (optional)", symbol: "number")
                    .frame(width: 250)
                Spacer()
                Button {
                    let suffix = budget.isEmpty ? "" : " --budget \(budget)"
                    store.featurePanel = nil
                    store.executeCommand(name: "goal", arguments: objective + suffix)
                } label: { Text("Start goal").frame(height: 28) }
                    .buttonStyle(SubtleButtonStyle()).disabled(objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!budget.isEmpty && (Int(budget) ?? 0) <= 0) || store.run.isRunning || controlsDisabled)
            }
        }.padding(20).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line.opacity(0.35), lineWidth: 0.5))
    }

    private func featureRow(_ row: FeatureRow) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.title).font(.system(size: 15, weight: .semibold)).textSelection(.enabled)
                    if !row.subtitle.isEmpty { Text(row.subtitle).font(.system(size: 12)).foregroundStyle(Theme.muted).textSelection(.enabled) }
                }
                Spacer()
                if let enabled = row.enabled {
                    Toggle("Enabled", isOn: Binding(get: { enabled }, set: { _ in store.toggleFeature(row, panel: panel) }))
                        .toggleStyle(.switch).labelsHidden().controlSize(.small).disabled(controlsDisabled)
                        .accessibilityLabel("Enable \(row.title)")
                }
            }
            if !row.detail.isEmpty {
                DisclosureGroup(isExpanded: Binding(get: { expanded.contains(row.id) }, set: { if $0 { expanded.insert(row.id) } else { expanded.remove(row.id) } })) {
                    Text(row.detail).font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                } label: { Text("Details").font(.system(size: 12)).foregroundStyle(Theme.muted) }
            }
            if panel == .mcps {
                let tools = MCPToolChoice.from(row)
                if !tools.isEmpty {
                    DisclosureGroup("Tools · \(tools.count)") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(tools) { tool in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(tool.name).font(.system(size: 12, weight: .medium, design: .monospaced))
                                        Text(tool.description).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(3)
                                    }
                                    Spacer()
                                    Toggle("Enable \(tool.name)", isOn: Binding(get: { tool.enabled }, set: { enabled in store.toggleMCPTool(server: row.id, tool: tool.name, enabled: enabled) }))
                                        .toggleStyle(.switch).labelsHidden().controlSize(.mini).disabled(controlsDisabled || row.enabled == false)
                                }
                            }
                        }.padding(.top, 8)
                    }.font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
            if !row.actions.isEmpty || (panel == .mcps && row.payload["source"] as? String == "local") {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    rowActions(row)
                }.buttonStyle(SubtleButtonStyle()).font(.system(size: 12, weight: .medium))
            }
            if messageRecipient == row.id {
                Divider().padding(.vertical, 2)
                DesktopTextField("Add context or give a follow-up instruction", text: $actionInput,
                                 title: "Message to subagent", symbol: "text.bubble", multiline: true)
                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel") { messageRecipient = nil }
                    Button("Send message") {
                        store.invokeFeature(row, panel: panel, action: "Message", arguments: actionInput)
                        actionInput = ""; messageRecipient = nil
                    }.disabled(actionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controlsDisabled)
                }
                .buttonStyle(SubtleButtonStyle())
            }
        }.padding(18).background(Theme.canvas.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line.opacity(0.3), lineWidth: 0.5))
    }

    @ViewBuilder private func rowActions(_ row: FeatureRow) -> some View {
        ForEach(row.actions, id: \.self) { action in
            if action == "Message" {
                Button("Message") { messageRecipient = row.id; actionInput = "" }.disabled(controlsDisabled)
            } else {
                Button(action) {
                    store.invokeFeature(row, panel: panel, action: action)
                    if ["Use", "Run"].contains(action) { store.featurePanel = nil; focusComposer() }
                }.disabled(controlsDisabled || (["Use", "Run", "Restart"].contains(action) && row.enabled == false))
            }
        }
        if panel == .mcps, row.payload["source"] as? String == "local" {
            IconButton(icon: "trash", help: "Remove server") { removeServer = row }.disabled(controlsDisabled)
        }
    }

    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 16) {
            if panel == .plugins {
                HStack(alignment: .bottom, spacing: 12) {
                    DesktopTextField("Plugin source or name", text: $actionInput, title: "Plugin source", symbol: "puzzlepiece.extension")
                    Button { runArgumentCommand("plugins", "install " + actionInput) } label: {
                        Text("Install").frame(height: 28)
                    }.disabled(actionInput.isEmpty || store.run.isRunning)
                }
            }
            HStack(spacing: 12) {
                if panel == .mcps {
                    Button(showAddMCP ? "Cancel adding" : "Add server") { showAddMCP.toggle() }.disabled(controlsDisabled)
                    Text("Changes are saved by the harness.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                } else if panel == .skills {
                    Button("Add skill…") { store.addSkillFolder() }.disabled(controlsDisabled)
                } else if panel == .plugins {
                    Button("Reload plugins") { runArgumentCommand("plugins", "reload") }.disabled(store.run.isRunning)
                } else if panel == .workflows {
                    Button("View running workflows") { runArgumentCommand("workflow", "runs") }
                } else if panel == .goals {
                    Text("Goal availability and budgets are controlled by the harness.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                } else if panel == .plan {
                    Button("Start planning") { store.featurePanel = nil; store.executeCommand(name: "plan") }
                } else {
                    Text(store.project?.name ?? "No project selected").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                Button("Done") { store.featurePanel = nil }.keyboardShortcut(.defaultAction)
            }
        }.buttonStyle(SubtleButtonStyle()).font(.system(size: 13, weight: .medium))
    }

    private func runArgumentCommand(_ name: String, _ arguments: String) {
        store.featurePanel = nil; store.executeCommand(name: name, arguments: arguments)
    }
    private func focusComposer() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NotificationCenter.default.post(name: .grokFocusComposer, object: nil) }
    }

    private var mcpForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add MCP server").font(.system(size: 15, weight: .semibold))
            DesktopTextField("e.g. team-docs", text: $mcpName, title: "Server name", symbol: "server.rack")
            VStack(alignment: .leading, spacing: 8) {
                Text("Connection type").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                Picker("Connection type", selection: $mcpTransport) {
                    Text("Remote URL").tag("http")
                    Text("Local command").tag("stdio")
                }.pickerStyle(.segmented).controlSize(.large).labelsHidden()
            }
            DesktopTextField(mcpTransport == "http" ? "https://example.com/mcp" : "e.g. npx", text: $mcpEndpoint,
                             title: mcpTransport == "http" ? "Server URL" : "Executable", symbol: mcpTransport == "http" ? "link" : "terminal")
            if mcpTransport == "stdio" {
                DesktopTextField("Enter each argument on a separate line", text: $mcpArguments, title: "Arguments (optional)",
                                 symbol: "text.alignleft", hint: "Spaces within an argument are preserved.", multiline: true)
            }
            HStack(alignment: .center, spacing: 16) {
                Text("Configure credentials through your harness environment.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button { store.addMCPServer(name: mcpName, transport: mcpTransport, endpoint: mcpEndpoint, arguments: mcpArguments) } label: {
                    Text("Save server").frame(height: 28)
                }.buttonStyle(SubtleButtonStyle())
                    .disabled(mcpName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || mcpEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controlsDisabled)
            }
        }.padding(20).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line.opacity(0.35), lineWidth: 0.5))
    }
}

struct AdvancedFeatureView: View {
    @EnvironmentObject var store: AppStore
    @State private var checkpoint: RewindCheckpoint?
    @State private var rewindMode: RewindSelection = .conversationOnly
    @State private var confirmRewind = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Text(store.advancedTitle).font(.system(size: 22, weight: .semibold))
                Spacer()
                IconButton(icon: "xmark", help: "Close") { store.showAdvancedPanel = false }.keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(store.run.approvals) { ApprovalCard(approval: $0) }
                    if store.advancedLoading { ProgressView("Loading…").padding(20) }
                    if let error = store.advancedError { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(Theme.muted).textSelection(.enabled) }
                    if let content = store.advancedContent { MarkdownContent(text: content) }
                    if store.advancedTitle == "Rewind" {
                        ForEach(store.rewindPoints) { point in
                            Button { checkpoint = point; rewindMode = .conversationOnly } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: checkpoint?.id == point.id ? "checkmark.circle.fill" : "circle")
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(point.prompt).lineLimit(3).font(.system(size: 14))
                                        Text("\(point.createdAt) · \(point.snapshotCount) file snapshots").font(.system(size: 12)).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line.opacity(checkpoint?.id == point.id ? 0.8 : 0.3), lineWidth: 1))
                            }.buttonStyle(.plain).disabled(store.advancedLoading)
                        }
                        if let checkpoint {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Restore the state before this prompt").font(.system(size: 13, weight: .medium))
                                Picker("Restore", selection: $rewindMode) {
                                    ForEach(RewindSelection.allCases) { mode in Text(mode.title).tag(mode).disabled(mode != .conversationOnly && !checkpoint.hasFileChanges) }
                                }.pickerStyle(.segmented).controlSize(.large)
                                HStack(spacing: 10) {
                                    Text("Preview the affected files before restoring.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    Button("Preview") { Task { await store.previewRewind(checkpoint, mode: rewindMode) } }.disabled(store.advancedLoading || store.run.isRunning)
                                    Button("Restore checkpoint…") { confirmRewind = true }.disabled(store.advancedLoading || store.run.isRunning || !store.canRestoreRewind(checkpoint, mode: rewindMode))
                                }.buttonStyle(SubtleButtonStyle())
                            }.padding(18).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 240, maxHeight: 500)
            Divider()
            HStack {
                Button("Copy") {
                    if let content = store.advancedContent { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(content, forType: .string) }
                }.disabled(store.advancedContent == nil)
                Spacer()
                Button("Done") { store.showAdvancedPanel = false }.keyboardShortcut(.defaultAction)
            }.buttonStyle(SubtleButtonStyle()).padding(.horizontal, 24).padding(.vertical, 20)
        }.frame(width: 700).background(Theme.surface)
            .confirmationDialog("Restore this checkpoint?", isPresented: $confirmRewind, titleVisibility: .visible) {
                if let checkpoint { Button("Restore \(rewindMode.title)", role: .destructive) { Task { await store.restoreRewind(checkpoint, mode: rewindMode) }; self.checkpoint = nil } }
            } message: { Text(rewindMode == .conversationOnly ? "Later conversation turns will be removed from this task." : rewindMode == .filesOnly ? "The previewed files will be replaced with their checkpoint contents." : "Later conversation turns will be removed and the previewed files will be replaced with their checkpoint contents.") }
    }
}
