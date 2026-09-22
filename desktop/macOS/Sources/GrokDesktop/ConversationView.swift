import SwiftUI
import AppKit

struct ConversationView: View {
    @EnvironmentObject var store: AppStore
    @State private var followOutput = true
    @State private var showModels = false
    @State private var showTools = false
    @State private var showReasoning = false
    @State private var showModes = false
    @State private var showCompactOptions = false
    @State private var modelSearch = ""
    @State private var selectedCommand = 0
    @State private var dismissedCommandDraft: String?
    @AppStorage("compactConversation") private var compactConversation = false
    @AppStorage("composerMultiline") private var composerMultiline = false

    var body: some View {
        VStack(spacing: 0) {
            if store.conversation == nil { welcome.frame(maxHeight: .infinity) }
            else { transcript }
            VStack(spacing: 10) {
                if let goal = store.run.goal { goalStatus(goal) }
                if !store.run.subagents.isEmpty {
                    Button { store.featurePanel = .agents } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.2")
                            Text("\(store.run.subagents.count) subagents")
                            Spacer()
                            Text("View activity").foregroundStyle(Theme.muted)
                            Image(systemName: "chevron.right").font(.system(size: 10))
                        }.font(.system(size: 12, weight: .medium)).padding(11).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
                if let approval = store.run.approvals.first { ApprovalCard(approval: approval) }
                if let question = store.run.questions.first { QuestionCard(request: question).id(question.id) }
                if !store.run.plan.isEmpty {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(store.run.plan) { entry in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: entry.status == "completed" ? "checkmark.circle.fill" : entry.status == "in_progress" ? "circle.dotted" : "circle")
                                        .foregroundStyle(entry.status == "completed" ? Theme.green : Theme.muted)
                                    Text(entry.content)
                                }
                            }
                        }.font(.system(size: 14)).padding(.vertical, 8)
                    } label: {
                        HStack {
                            Image(systemName: "list.bullet.clipboard")
                            Text("Plan")
                            Spacer()
                            Text("\(store.run.plan.filter { $0.status == "completed" }.count) of \(store.run.plan.count)").foregroundStyle(Theme.muted)
                        }.font(.system(size: 13, weight: .medium))
                    }.padding(12).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                composer
                GeometryReader { geometry in
                    HStack(spacing: 7) {
                        if !store.workspace.branch.isEmpty {
                            Image(systemName: "arrow.triangle.branch")
                            Text(store.workspace.branch).fontWeight(.medium).truncationMode(.middle)
                        }
                        if geometry.size.width > 420 || store.workspace.branch.isEmpty {
                            if !store.workspace.branch.isEmpty { Text("·") }
                            Text(store.project == nil ? "Choose a project to get started" : "Local workspace")
                        }
                        Spacer(minLength: 4)
                        Text(geometry.size.width > 560
                             ? (composerMultiline ? "/ Commands  ·  ⌘↵ Send  ·  ↵ New line" : "/ Commands  ·  ↵ Send  ·  ⇧↵ New line")
                             : "/ Commands").fixedSize()
                    }.font(.system(size: 12)).lineLimit(1).foregroundStyle(Theme.muted)
                }.frame(height: 16).padding(.horizontal, 5)
            }.frame(maxWidth: 860).padding(.horizontal, 32).padding(.bottom, 20).padding(.top, 12)
        }
        .task(id: "\(store.state.selectedProjectID?.uuidString ?? "")/\(store.state.selectedConversationID?.uuidString ?? "")") {
            await store.prepareSessionOptions()
        }
        .onChange(of: store.state.selectedConversationID) { _, _ in
            showModels = false; showTools = false; showReasoning = false; showModes = false; showCompactOptions = false
        }
        .onChange(of: store.draft) { previous, value in
            selectedCommand = 0
            dismissedCommandDraft = nil
            if value.hasPrefix("/") && !previous.hasPrefix("/") { Task { await store.refreshCommands() } }
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            GrokMark(size: 47).padding(.bottom, 24)
            Text("What will you build?").font(.system(size: 32, weight: .semibold)).tracking(-0.6)
            HStack(spacing: 5) {
                Text("A little curiosity. A lot of possibility.")
            }.font(.system(size: 15)).foregroundStyle(Theme.muted).padding(.top, 12)
            if let project = store.project {
                HStack(spacing: 7) { Image(systemName: "folder"); Text(project.name); Image(systemName: "chevron.down").font(.system(size: 8)) }
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted).padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.sidebar).clipShape(Capsule()).padding(.top, 21)
            } else {
                Button("Open a project") { store.addProject() }.buttonStyle(SubtleButtonStyle()).padding(.top, 22)
            }
            Spacer().frame(height: 48)
            HStack(spacing: 10) {
                starter("Explore the codebase", subtitle: "Find your way around", icon: "square.stack.3d.up", prompt: "Explore this codebase. Explain its architecture, the main entry points, and how to run it.")
                starter("Build something", subtitle: "Turn an idea into code", icon: "hammer", prompt: "I'd like to build a new feature in this project. First, inspect the codebase and ask me what I want to create.")
                starter("Review changes", subtitle: "Get a second pair of eyes", icon: "checkmark.bubble", prompt: "Review the current uncommitted changes for bugs, regressions, and missing edge cases. Give concrete findings with file references.")
            }.frame(maxWidth: 650)
            Spacer()
            Spacer().frame(height: 4)
        }.padding(.horizontal, 32)
    }

    private func starter(_ title: String, subtitle: String, icon: String, prompt: String) -> some View {
        Button { store.draft = prompt } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .light)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 14, weight: .medium))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(17).background(Theme.surface.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.line, lineWidth: 1)).contentShape(RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain).disabled(store.project == nil)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: compactConversation ? 10 : 23) {
                    ForEach(store.conversation?.messages ?? []) { message in MessageView(message: message) }
                    if store.run.isRunning {
                        HStack(spacing: 9) {
                            ProgressView().controlSize(.mini)
                            Text(store.run.approvals.isEmpty && store.run.questions.isEmpty ? store.run.phase + "…" : "Waiting for your response")
                                .font(.system(size: 14)).foregroundStyle(Theme.muted)
                        }.padding(.vertical, 5)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.frame(maxWidth: 800, alignment: .leading).padding(.horizontal, 36).padding(.top, 34).padding(.bottom, 15).frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: store.conversation?.messages.last?.text) { _, _ in if followOutput { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: store.conversation?.messages.count) { _, _ in if followOutput { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: store.state.selectedConversationID) { _, _ in followOutput = true; proxy.scrollTo("bottom", anchor: .bottom) }
            .overlay(alignment: .bottomTrailing) {
                if store.run.isRunning {
                    Button { followOutput.toggle(); if followOutput { proxy.scrollTo("bottom", anchor: .bottom) } } label: {
                        Label(followOutput ? "Following" : "Follow output", systemImage: followOutput ? "arrow.down.to.line" : "arrow.down")
                            .font(.system(size: 12)).padding(7).background(Theme.surface).clipShape(Capsule())
                    }.buttonStyle(.plain).foregroundStyle(Theme.muted).padding(.trailing, 22)
                }
            }
        }
    }

    private var optionsDisabled: Bool { store.run.isRunning || store.run.isConfiguring }
    private var isLiveCommand: Bool {
        guard let command = SlashCommand.split(store.draft) else { return false }
        if command.name == "btw" { return !command.arguments.isEmpty }
        if command.name == "goal" { return ["status", "pause", "resume", "clear"].contains(command.arguments) }
        return ["help", "new", "home", "skills", "mcps", "subagents", "config-agents", "personas", "workflows", "settings", "history", "transcript", "view-plan", "tasks", "usage"].contains(DesktopCommands.canonical(command.name))
    }
    private var canSend: Bool {
        !store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.project != nil && (!optionsDisabled || (store.run.isRunning && isLiveCommand))
    }
    private var selectedModelName: String {
        store.run.models.first { $0.id == store.run.modelID }?.name ?? (store.run.modelID.isEmpty ? "Choose model" : store.run.modelID)
    }
    private var filteredModels: [ModelOption] {
        store.run.models.filter { modelSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(modelSearch) || $0.id.localizedCaseInsensitiveContains(modelSearch) }
    }
    private var reasoningName: String {
        if let option = store.run.reasoningOptions.first(where: { $0.id == store.run.reasoningID }) { return option.name }
        if !store.run.reasoningID.isEmpty { return store.run.reasoningID == "xhigh" ? "Extra high" : store.run.reasoningID.capitalized }
        return store.run.models.isEmpty || !store.run.reasoningOptions.isEmpty ? "Default" : "Not supported"
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if store.draft.isEmpty {
                    Text(store.conversation == nil ? "Ask Grok to build, fix, or explore anything…" : "Continue the conversation…")
                        .font(.system(size: 16)).foregroundStyle(Theme.muted).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                }
                PromptEditor(text: $store.draft, onSubmit: submitDraft, onCommandKey: handleComposerKey)
                    .frame(height: store.draft.components(separatedBy: "\n").count > 3 ? 120 : 76)
            }
            GeometryReader { geometry in
                HStack(alignment: .center, spacing: 6) {
                    toolsButton
                    if geometry.size.width < 460 {
                        compactOptionsButton(iconOnly: geometry.size.width < 260)
                    } else {
                        modelPicker
                        reasoningPicker(compact: geometry.size.width < 650)
                        modePicker
                    }
                    Spacer(minLength: 0)
                    if store.run.isConfiguring {
                        ProgressView().controlSize(.small).frame(width: 20, height: 40)
                            .help("Updating conversation settings…").accessibilityLabel("Updating conversation settings")
                    }
                    sendButton
                }
            }.frame(height: 40)
        }.padding(16).glassSurface(cornerRadius: 24)
            .overlay(alignment: .bottom) {
                if showSlashCommands {
                    VStack(spacing: 0) {
                        HStack { Text("Commands & skills").fontWeight(.medium); Spacer(); Text("↑↓ Select  ·  ⇥ Complete  ·  esc Close") }
                            .font(.system(size: 11)).foregroundStyle(Theme.muted).padding(12)
                        Divider()
                        CommandList(commands: slashCommands, selected: selectedCommand, onSelect: chooseCommand)
                            .frame(height: min(300, max(80, CGFloat(slashCommands.count) * 65)))
                    }.background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
                        .shadow(color: .black.opacity(0.12), radius: 18, y: 5)
                        .padding(.bottom, store.draft.components(separatedBy: "\n").count > 3 ? 219 : 175)
                }
            }
    }

    private var showSlashCommands: Bool {
        let value = store.draft
        return value.hasPrefix("/") && !value.dropFirst().contains(where: \.isWhitespace) && dismissedCommandDraft != value
    }
    private var slashCommands: [SlashCommand] { DesktopCommands.matches(store.availableCommands, query: store.draft) }
    private func submitDraft() {
        if showSlashCommands && slashCommands.indices.contains(selectedCommand) { chooseCommand(slashCommands[selectedCommand]) }
        else if let command = SlashCommand.split(store.draft), command.name == "btw" || (command.name == "goal" && ["status", "pause", "resume", "clear"].contains(command.arguments)) {
            store.draft = ""; store.executeCommand(name: command.name, arguments: command.arguments)
        }
        else if canSend { store.send() }
    }
    private func handleComposerKey(_ code: UInt16) -> Bool {
        guard showSlashCommands else { return false }
        switch code {
        case 125: selectedCommand = min(selectedCommand + 1, max(0, slashCommands.count - 1))
        case 126: selectedCommand = max(0, selectedCommand - 1)
        case 48:
            if slashCommands.indices.contains(selectedCommand) {
                store.draft = "/\(slashCommands[selectedCommand].name) "
            }
        case 53: dismissedCommandDraft = store.draft
        default: return false
        }
        return true
    }
    private func chooseCommand(_ command: SlashCommand) {
        if command.argumentHint != nil && !["plan", "plugins", "model", "effort", "theme", "cd"].contains(command.name) {
            store.draft = "/\(command.name) "
            NotificationCenter.default.post(name: .grokFocusComposer, object: nil)
        } else {
            store.draft = ""
            store.executeCommand(name: command.name)
        }
    }
    private func goalStatus(_ goal: GoalState) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "scope").foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(goal.objective).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text("\(goal.status.replacingOccurrences(of: "_", with: " ").capitalized) · \(goal.tokensUsed.formatted()) tokens")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if goal.isActive { Button("Pause") { store.executeCommand(name: "goal", arguments: "pause") }.font(.system(size: 12)) }
            if goal.isPaused { Button("Resume") { store.executeCommand(name: "goal", arguments: "resume") }.font(.system(size: 12)) }
            Button { store.featurePanel = .goals } label: { Image(systemName: "ellipsis") }.buttonStyle(.plain).help("Manage goal")
        }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 11))
    }

    private var toolsButton: some View {
        Button { showTools.toggle() } label: {
            Image(systemName: "plus").font(.system(size: 22, weight: .medium))
                .frame(width: 40, height: 40).contentShape(Circle())
        }.buttonStyle(ComposerControlStyle()).help("Commands, skills, and tools")
            .accessibilityLabel("Add tools and commands")
            .popover(isPresented: $showTools, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tools & commands").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted).padding(12)
                    toolAction("Commands", symbol: "command", shortcut: "⇧⌘P") { store.showCommandPalette = true }
                    Divider().padding(.vertical, 5)
                    toolAction("Plan mode", symbol: "list.bullet.clipboard") { store.executeCommand(name: "plan") }
                    toolAction("Goal", symbol: "scope") { store.featurePanel = .goals }
                    toolAction("MCP servers", symbol: "externaldrive.connected.to.line.below") { store.featurePanel = .mcps }
                    toolAction("Skills", symbol: "sparkles") { store.featurePanel = .skills }
                    toolAction("Subagents", symbol: "person.2") { store.featurePanel = .agents }
                    toolAction("Workflows", symbol: "arrow.triangle.branch") { store.featurePanel = .workflows }
                }.padding(6).frame(width: 252)
            }
    }

    private func toolAction(_ title: String, symbol: String, shortcut: String? = nil, action: @escaping () -> Void) -> some View {
        Button {
            showTools = false
            DispatchQueue.main.async { action() }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol).foregroundStyle(Theme.muted).frame(width: 19)
                Text(title)
                Spacer()
                if let shortcut { Text(shortcut).font(.system(size: 11)).foregroundStyle(Theme.muted) }
            }.font(.system(size: 14))
        }.buttonStyle(PopoverRowStyle())
    }

    private var modelPicker: some View {
        Button {
            modelSearch = ""
            showModels.toggle()
            if store.run.models.isEmpty { Task { await store.prepareSessionOptions() } }
        } label: {
            ComposerControlLabel(title: selectedModelName, symbol: "cpu")
        }.buttonStyle(ComposerControlStyle(filled: true)).disabled(optionsDisabled || store.project == nil)
            .help("Model: \(selectedModelName)").accessibilityLabel("Model: \(selectedModelName)")
            .popover(isPresented: $showModels, arrowEdge: .top) { modelPopover }
    }

    private func compactOptionsButton(iconOnly: Bool) -> some View {
        Button { showCompactOptions.toggle() } label: {
            if iconOnly {
                Image(systemName: "slider.horizontal.3").font(.system(size: 17))
                    .frame(width: 40, height: 40).contentShape(Circle())
            } else {
                ComposerControlLabel(title: selectedModelName, symbol: "slider.horizontal.3")
            }
        }.buttonStyle(ComposerControlStyle(filled: true)).disabled(optionsDisabled || store.project == nil)
            .help("Model, thinking level, and mode").accessibilityLabel("Model and thinking settings: \(selectedModelName), \(reasoningName)")
            .popover(isPresented: $showCompactOptions, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Conversation settings").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted).padding(12)
                    compactOptionRow("Model", value: selectedModelName, symbol: "cpu", panel: .models)
                    compactOptionRow("Thinking", value: reasoningName, symbol: "brain", panel: .reasoning)
                        .disabled(store.run.reasoningOptions.isEmpty)
                    if !store.run.modes.isEmpty {
                        Divider().padding(.vertical, 5)
                        Text("Mode").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted).padding(12)
                        ForEach(store.run.modes) { mode in
                            Button { showCompactOptions = false; store.setMode(mode) } label: {
                                HStack {
                                    Text(mode.name)
                                    Spacer()
                                    if mode.id == store.run.modeID { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                                }.font(.system(size: 14))
                            }.buttonStyle(PopoverRowStyle())
                        }
                    }
                }.padding(6).frame(width: 290)
            }
    }

    private func compactOptionRow(_ title: String, value: String, symbol: String, panel: FeaturePanel) -> some View {
        Button {
            showCompactOptions = false
            DispatchQueue.main.async { store.featurePanel = panel }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol).foregroundStyle(Theme.muted).frame(width: 19)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 14, weight: .medium))
                    Text(value).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
        }.buttonStyle(PopoverRowStyle())
    }

    private var modelPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose a model").font(.system(size: 16, weight: .semibold)).padding([.horizontal, .top], 16)
            NativeSearchField(text: $modelSearch, placeholder: "Search models or providers", onEscape: { showModels = false })
                .frame(height: 40).padding(12)
            Divider()
            ScrollView {
                LazyVStack(spacing: 3) {
                    if filteredModels.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").font(.system(size: 22)).foregroundStyle(Theme.muted)
                            Text(store.run.isConfiguring ? "Loading models…" : store.run.models.isEmpty ? "Models are unavailable" : "No matching models")
                                .font(.system(size: 14, weight: .medium))
                            if store.run.models.isEmpty && !store.run.isConfiguring {
                                Button("Try again") { Task { await store.prepareSessionOptions() } }
                            }
                        }.frame(maxWidth: .infinity).padding(.vertical, 48)
                    }
                    ForEach(filteredModels) { model in
                        Button {
                            store.setModel(model)
                            showModels = false
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(model.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink)
                                    Text(model.id).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer(minLength: 0)
                                if model.id == store.run.modelID { Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent) }
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(optionsDisabled)
                            .background(model.id == store.run.modelID ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }
                }.padding(7)
            }.frame(height: 320)
            Divider()
            Text("Model changes apply to your next message.").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(14)
        }.frame(width: 400)
    }

    private func reasoningPicker(compact: Bool) -> some View {
        Button { showReasoning.toggle() } label: {
            ComposerControlLabel(title: compact ? reasoningName : "Thinking · \(reasoningName)", symbol: "brain")
        }.buttonStyle(ComposerControlStyle()).fixedSize(horizontal: true, vertical: false)
            .disabled(optionsDisabled || store.run.reasoningOptions.isEmpty)
            .help(store.run.reasoningOptions.isEmpty ? "This model does not offer an adjustable thinking level." : "Choose how much the model thinks before answering.")
            .accessibilityLabel("Thinking level: \(reasoningName)")
            .popover(isPresented: $showReasoning, arrowEdge: .top) {
                optionPopover("Thinking level", options: store.run.reasoningOptions, selected: store.run.reasoningID) { option in
                    showReasoning = false
                    store.setReasoning(option)
                }
            }
    }

    @ViewBuilder
    private var modePicker: some View {
        if !store.run.modes.isEmpty {
            Button { showModes.toggle() } label: {
                ComposerControlLabel(title: store.run.modes.first { $0.id == store.run.modeID }?.name ?? "Mode")
            }.buttonStyle(ComposerControlStyle()).fixedSize(horizontal: true, vertical: false)
                .disabled(optionsDisabled).help("Conversation mode").accessibilityLabel("Conversation mode")
                .popover(isPresented: $showModes, arrowEdge: .top) {
                    optionPopover("Conversation mode", options: store.run.modes, selected: store.run.modeID) { mode in
                        showModes = false
                        store.setMode(mode)
                    }
                }
        }
    }

    private func optionPopover(_ title: String, options: [ModelOption], selected: String, choose: @escaping (ModelOption) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted).padding(12)
            ForEach(options) { option in
                Button { choose(option) } label: {
                    HStack(spacing: 12) {
                        Text(option.name).font(.system(size: 14))
                        Spacer()
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent).opacity(option.id == selected ? 1 : 0)
                    }
                }.buttonStyle(PopoverRowStyle()).disabled(optionsDisabled)
            }
        }.padding(6).frame(width: 240)
    }

    private var sendButton: some View {
        let stopping = store.run.isRunning && !isLiveCommand
        return Button {
            if stopping { store.cancel() } else if canSend { submitDraft() }
        } label: {
            Image(systemName: stopping ? "stop.fill" : "arrow.up")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.canvas)
                .frame(width: 40, height: 40)
                .background(store.run.isRunning || canSend ? Theme.ink : Theme.muted.opacity(0.35), in: Circle())
        }.buttonStyle(.plain).disabled(!store.run.isRunning && !canSend)
            .help(stopping ? "Stop task · ⌘." : "Send message")
            .accessibilityLabel(stopping ? "Stop task" : "Send message")
    }

}

struct PromptEditor: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onCommandKey: ((UInt16) -> Bool)? = nil
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let editor = SubmitTextView(); editor.delegate = context.coordinator; editor.onSubmit = onSubmit; editor.onCommandKey = onCommandKey
        editor.isRichText = false; editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.font = .systemFont(ofSize: 16); editor.textColor = .labelColor; editor.backgroundColor = .clear
        editor.textContainerInset = NSSize(width: 0, height: 7); editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.setAccessibilityLabel("Message Grok")
        scroll.documentView = editor; return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? SubmitTextView else { return }
        if editor.string != text { editor.string = text }
        editor.onSubmit = onSubmit
        editor.onCommandKey = onCommandKey
        context.coordinator.parent = self
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PromptEditor
        init(_ parent: PromptEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) { if let editor = notification.object as? NSTextView { parent.text = editor.string } }
    }
}

final class SubmitTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onCommandKey: ((UInt16) -> Bool)?
    private var focusObserver: NSObjectProtocol?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
        focusObserver = NotificationCenter.default.addObserver(forName: .grokFocusComposer, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }; self.window?.makeFirstResponder(self)
        }
    }
    deinit { if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) } }
    override func keyDown(with event: NSEvent) {
        if !hasMarkedText() && event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty && onCommandKey?(event.keyCode) == true { return }
        let multiline = UserDefaults.standard.bool(forKey: "composerMultiline")
        if (event.keyCode == 36 || event.keyCode == 76) && !event.modifierFlags.contains(.shift) && (!multiline || event.modifierFlags.contains(.command)) && !hasMarkedText() { onSubmit?() }
        else { super.keyDown(with: event) }
    }
}

struct MessageView: View {
    let message: Message
    var body: some View {
        switch message.kind {
        case .user:
            HStack { Spacer(minLength: 48); Text(message.text).font(.system(size: 16)).textSelection(.enabled).padding(.horizontal, 17).padding(.vertical, 13).background(Theme.sidebar).clipShape(RoundedRectangle(cornerRadius: 16)) }
        case .assistant:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) { GrokMark(size: 18); Text("Grok").font(.system(size: 13, weight: .semibold)) }
                MarkdownContent(text: message.text)
            }
        case .thought:
            DisclosureGroup { Text(message.text).font(.system(size: 14)).foregroundStyle(Theme.muted).textSelection(.enabled).padding(.top, 8) }
                label: { Label("Thinking", systemImage: "sparkle").font(.system(size: 13)).foregroundStyle(Theme.muted) }
        case .tool:
            DisclosureGroup {
                if let detail = message.detail, !detail.isEmpty {
                    ScrollView([.horizontal, .vertical]) { Text(detail).font(.system(size: 13, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 230).padding(.top, 10)
                } else { Text("No additional output.").font(.system(size: 13)).foregroundStyle(Theme.muted).padding(.top, 8) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: message.status == "completed" ? "checkmark.circle" : message.status == "failed" ? "xmark.circle" : "terminal")
                        .foregroundStyle(message.status == "failed" ? .red : Theme.muted)
                    Text(message.text).lineLimit(2)
                    Spacer()
                    Text((message.status ?? "pending").replacingOccurrences(of: "_", with: " ")).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }.font(.system(size: 14))
            }.padding(13).background(Theme.sidebar.opacity(0.65)).clipShape(RoundedRectangle(cornerRadius: 9))
        case .system:
            HStack(alignment: .top, spacing: 9) { Image(systemName: "exclamationmark.circle"); Text(message.text).textSelection(.enabled) }.font(.system(size: 14)).foregroundStyle(Theme.muted).padding(13).background(Theme.sidebar).clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }
}

struct MarkdownContent: View {
    var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(text.components(separatedBy: "```").enumerated()), id: \.offset) { index, part in
                if index % 2 == 1 {
                    let lines = part.components(separatedBy: "\n")
                    let code = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .newlines)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(lines.first ?? "code").font(.system(size: 12, design: .monospaced))
                            Spacer()
                            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) } label: { Label("Copy", systemImage: "doc.on.doc").font(.system(size: 12)) }.buttonStyle(.plain)
                        }.foregroundStyle(Theme.muted).padding(11)
                        Divider()
                        ScrollView(.horizontal) { Text(code).font(.system(size: 14, design: .monospaced)).textSelection(.enabled).padding(13).frame(maxWidth: .infinity, alignment: .leading) }
                    }.background(Theme.sidebar).clipShape(RoundedRectangle(cornerRadius: 9))
                } else if !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 13) {
                        ForEach(Array(part.trimmingCharacters(in: .newlines).components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                            if paragraph.hasPrefix("#") {
                                let marks = paragraph.prefix(while: { $0 == "#" }).count
                                Text(tryAttributed(String(paragraph.dropFirst(marks)).trimmingCharacters(in: .whitespaces)))
                                    .font(.system(size: marks == 1 ? 25 : marks == 2 ? 21 : 18, weight: .semibold)).padding(.top, 4)
                            } else if paragraph.hasPrefix("> ") {
                                Text(tryAttributed(paragraph.components(separatedBy: "\n").map { $0.hasPrefix("> ") ? String($0.dropFirst(2)) : $0 }.joined(separator: "\n")))
                                    .font(.system(size: 16)).foregroundStyle(Theme.muted).padding(.leading, 13)
                                    .overlay(alignment: .leading) { Theme.accent.opacity(0.4).frame(width: 2) }
                            } else {
                                Text(tryAttributed(paragraph)).font(.system(size: 16))
                            }
                        }
                    }.lineSpacing(5).textSelection(.enabled).tint(Theme.accent)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func tryAttributed(_ value: String) -> AttributedString {
        (try? AttributedString(markdown: value.trimmingCharacters(in: .newlines), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value)
    }
}

struct ApprovalCard: View {
    @EnvironmentObject var store: AppStore
    var approval: Approval
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(approval.title, systemImage: "hand.raised").font(.system(size: 15, weight: .semibold))
            ScrollView { Text(approval.detail).font(.system(size: 13, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 120)
            HStack {
                Spacer()
                ForEach(approval.options) { option in
                    Button(option.name) { store.approve(approval, option: option) }.buttonStyle(SubtleButtonStyle()).font(.system(size: 13, weight: .medium))
                }
            }
        }.padding(16).background(Theme.sidebar).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(0.4)))
    }
}

struct QuestionCard: View {
    @EnvironmentObject var store: AppStore
    var request: QuestionRequest
    @State private var selections: [String: Set<String>] = [:]
    @State private var notes: [String: String] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("A question from Grok", systemImage: "bubble.left.and.bubble.right").font(.system(size: 15, weight: .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(request.questions) { question in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(question.question).font(.system(size: 14, weight: .medium))
                            ForEach(question.options, id: \.self) { option in
                                Button {
                                    if question.multiSelect {
                                        if selections[question.question, default: []].contains(option) { selections[question.question]?.remove(option) }
                                        else { selections[question.question, default: []].insert(option) }
                                    } else { selections[question.question] = [option] }
                                } label: {
                                    Label(option, systemImage: selections[question.question, default: []].contains(option) ? "checkmark.circle.fill" : "circle").font(.system(size: 13))
                                }.buttonStyle(.plain)
                            }
                            DesktopTextField("Or write a response…", text: Binding(get: { notes[question.question] ?? "" }, set: { notes[question.question] = $0 }), symbol: "text.bubble")
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 220)
            HStack {
                Spacer()
                Button("Skip") { store.answer(request, answers: [:], cancelled: true) }.buttonStyle(.plain)
                Button("Continue") {
                    var answers: [String: [String]] = [:]
                    for question in request.questions {
                        answers[question.question] = question.options.filter { selections[question.question, default: []].contains($0) }
                    }
                    store.answer(request, answers: answers, notes: notes)
                }.buttonStyle(SubtleButtonStyle()).disabled(request.questions.contains { (selections[$0.question] ?? []).isEmpty && (notes[$0.question] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            }.font(.system(size: 13))
        }.padding(16).background(Theme.sidebar).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
