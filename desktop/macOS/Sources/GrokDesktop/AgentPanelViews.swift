import AppKit
import SwiftUI

// MARK: - Agent definitions (/config-agents)

struct AgentDefinitionsPanelView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var extensions: ExtensionFeatureModel
    let rows: [FeatureRow]
    let disabled: Bool
    @State private var expanded: Set<String> = []

    private var available: [String] { store.featureRows.filter { $0.payload["plugin"] == nil }.map(\.title) }
    private var resolvedDefault: String { AgentConfigWriter.resolvedDefault(configured: extensions.agentConfig.configuredDefault, available: available) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !store.featureRows.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 11)).foregroundStyle(Theme.accent).accessibilityHidden(true)
                    Text("New sessions start with ").foregroundStyle(Theme.muted) + Text(resolvedDefault).fontWeight(.medium) + Text(extensions.agentConfig.configuredDefault == nil ? " (the harness default)." : ".").foregroundStyle(Theme.muted)
                }.font(.system(size: 12))
                if let configured = extensions.agentConfig.configuredDefault, configured != resolvedDefault {
                    Label("config.toml names '\(configured)', which wasn't found.", systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange)
                }
            }
            ForEach(rows) { row in card(row) }
        }
    }

    private func card(_ row: FeatureRow) -> some View {
        let name = row.payload["name"] as? String ?? row.title
        let scope = row.payload["scope"] as? String ?? ""
        let isActive = extensions.activeAgent == name
        let content = row.payload["content"] as? String
        let showing = expanded.contains(row.id) && content != nil
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(name).font(.system(size: 14, weight: .semibold)).textSelection(.enabled)
                        ExtensionBadge(text: scope)
                        if name == resolvedDefault { ExtensionBadge(text: "Default", symbol: "star.fill", tone: .accent) }
                        if isActive { ExtensionBadge(text: "Active in this task", symbol: "circle.fill", tone: .accent) }
                    }
                    if !row.subtitle.isEmpty { Text(row.subtitle).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2).textSelection(.enabled) }
                    if let path = row.payload["path"] as? String { ExtensionPathLine(path: path) }
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Button(showing ? "Hide" : "View") {
                        if expanded.remove(row.id) == nil {
                            expanded.insert(row.id)
                            if content == nil { store.invokeFeature(row, panel: .agentDefinitions, action: "Inspect") }
                        }
                    }.disabled(disabled && content == nil).help("View the agent definition")
                    Button(extensions.agentConfig.configuredDefault == name ? "Clear default" : "Set as default") {
                        extensions.toggleDefaultAgent(row, available: available)
                    }.disabled(disabled)
                    Toggle("Enabled", isOn: Binding(get: { row.enabled ?? true }, set: { _ in store.toggleFeature(row, panel: .agentDefinitions) }))
                        .toggleStyle(.switch).labelsHidden().controlSize(.small).disabled(disabled)
                        .help("Whether new sessions can use '\(name)'").accessibilityLabel("Enable \(name)")
                }.buttonStyle(SubtleButtonStyle()).font(.system(size: 12, weight: .medium))
            }
            if showing, let content { AgentDefinitionBox(text: content) }
        }.extensionCard(highlighted: isActive)
    }
}

/// A read-only definition file shown inside a row.
struct AgentDefinitionBox: View {
    let text: String
    var body: some View {
        ScrollView { Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
            .frame(maxHeight: 220).background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - Personas

struct PersonasPanelView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var extensions: ExtensionFeatureModel
    let rows: [FeatureRow]
    let disabled: Bool
    @Binding var creating: Bool
    @State private var editing: String?
    @State private var viewing: Set<String> = []

    init(rows: [FeatureRow], disabled: Bool, creating: Binding<Bool>, editing: String? = nil) {
        self.rows = rows; self.disabled = disabled; _creating = creating
        _editing = State(initialValue: editing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Personas shape subagent behavior via the persona parameter on spawn_subagent.")
                Text("Used by skills (e.g. /implement) and by the model when spawning subagents.")
            }.font(.system(size: 12)).foregroundStyle(Theme.muted)
            if creating { PersonaCreateForm(creating: $creating) }
            ForEach(rows) { row in
                if editing == row.id, let path = row.payload["path"] as? String {
                    PersonaEditForm(row: row, url: URL(fileURLWithPath: path), editable: row.payload["editable"] as? Bool == true) { editing = nil }
                } else {
                    card(row)
                }
            }
        }
    }

    private func card(_ row: FeatureRow) -> some View {
        let editable = row.payload["editable"] as? Bool == true
        let content = row.payload["content"] as? String
        let description = row.payload["description"] as? String ?? row.detail
        let showing = viewing.contains(row.id) && content != nil
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(row.title).font(.system(size: 14, weight: .semibold)).textSelection(.enabled)
                        ExtensionBadge(text: row.subtitle, symbol: editable ? nil : "lock.fill")
                    }
                    if !description.isEmpty { Text(description).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2).textSelection(.enabled) }
                    if let path = row.payload["path"] as? String, editable { ExtensionPathLine(path: path) }
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    if editable {
                        Button("Edit") { editing = row.id }
                    } else {
                        Button(showing ? "Hide" : "View") {
                            if viewing.remove(row.id) == nil {
                                viewing.insert(row.id)
                                if content == nil { store.invokeFeature(row, panel: .personas, action: "Inspect") }
                            }
                        }.disabled(disabled && content == nil)
                    }
                    Button("Delete…") {
                        guard editable else { extensions.notice = ExtensionNotice(panel: .personas, text: "Cannot delete bundled personas", isError: true); return }
                        extensions.pendingConfirmation = ExtensionConfirmation(panel: .personas, message: "Delete persona '\(row.title)'?",
                            detail: row.payload["path"] as? String, confirmTitle: "Delete") { deletePersona(row) }
                    }
                }.buttonStyle(SubtleButtonStyle()).font(.system(size: 12, weight: .medium))
            }
            if showing, let content { AgentDefinitionBox(text: content) }
        }.extensionCard()
    }

    private func deletePersona(_ row: FeatureRow) {
        guard let path = row.payload["path"] as? String else {
            extensions.notice = ExtensionNotice(panel: .personas, text: "Persona has no source file", isError: true); return
        }
        do {
            try PersonaStore.delete(path)
            extensions.notice = ExtensionNotice(panel: .personas, text: "Deleted persona '\(row.title)'")
            Task { await store.refreshFeatures(.personas) }
        } catch {
            extensions.notice = ExtensionNotice(panel: .personas, text: error.localizedDescription, isError: true)
        }
    }
}

/// "Create New Persona": Name, Description, Instructions, and user or project scope.
private struct PersonaCreateForm: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var extensions: ExtensionFeatureModel
    @Binding var creating: Bool
    @State private var name = ""
    @State private var description = ""
    @State private var instructions = ""
    @State private var scope = PersonaScope.user
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create New Persona").font(.system(size: 15, weight: .semibold))
            DesktopTextField("e.g. security-reviewer", text: $name, title: "Name", symbol: "person.crop.square")
            DesktopTextField("What this persona is for", text: $description, title: "Description", symbol: "text.quote")
            VStack(alignment: .leading, spacing: 8) {
                Text("Instructions").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                MemoryNoteEditor(text: $instructions, placeholder: "How a subagent with this persona should work…").frame(height: 110)
            }
            HStack(spacing: 12) {
                Picker("Scope", selection: $scope) { ForEach(PersonaScope.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .help("User personas are available everywhere; project personas live in this repository.")
                if let error { Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.red).lineLimit(2) }
                else {
                    Text((PersonaStore.directory(scope, cwd: URL(fileURLWithPath: store.project?.path ?? "/")).path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Cancel") { creating = false }
                Button("Create") { create() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.buttonStyle(SubtleButtonStyle()).font(.system(size: 13, weight: .medium))
        }.padding(20).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line.opacity(0.35), lineWidth: 0.5))
    }

    private func create() {
        guard let project = store.project else { error = "Open a project first."; return }
        do {
            let url = try PersonaStore.create(name: name, description: description, instructions: instructions, scope: scope, cwd: URL(fileURLWithPath: project.path))
            extensions.notice = ExtensionNotice(panel: .personas, text: "Created persona '\(url.deletingPathExtension().lastPathComponent)'")
            creating = false
            Task { await store.refreshFeatures(.personas) }
        } catch let failure {
            error = failure.localizedDescription
        }
    }
}

/// The terminal's persona detail view: every field, editable for user and project personas.
private struct PersonaEditForm: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var extensions: ExtensionFeatureModel
    let row: FeatureRow
    let url: URL
    let editable: Bool
    let onClose: () -> Void
    @State private var original: PersonaFields?
    @State private var fields = PersonaFields()
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("persona: \(fields.name.isEmpty ? row.title : fields.name)").font(.system(size: 15, weight: .semibold))
                ExtensionBadge(text: row.subtitle)
                if fields.hasInputs { ExtensionBadge(text: "Inputs") }
                if fields.hasOutputs { ExtensionBadge(text: "Outputs") }
                Spacer()
            }
            if original == nil, error == nil { ProgressView().controlSize(.small) }
            HStack(spacing: 14) {
                DesktopTextField("Name", text: $fields.name, title: "Name")
                DesktopTextField("Inherit", text: $fields.model, title: "Model")
            }
            DesktopTextField("—", text: $fields.description, title: "Description")
            HStack(spacing: 14) {
                DesktopTextField("e.g. high", text: $fields.reasoningEffort, title: "Effort")
                DesktopTextField("e.g. worktree", text: $fields.defaultIsolation, title: "Isolation")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Instructions").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                MemoryNoteEditor(text: $fields.instructions, placeholder: "(empty)").frame(height: 140)
            }
            if !fields.instructionsFile.isEmpty {
                Text("Instructions file: \(fields.instructionsFile)").font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 12) {
                if let error { Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.red).lineLimit(2) }
                else { Text("Empty fields are removed from the file.").font(.system(size: 12)).foregroundStyle(Theme.muted) }
                Spacer()
                Button("Open file") { NSWorkspace.shared.open(url) }
                Button("Cancel") { onClose() }
                Button("Save") { save() }.disabled(!editable || original == nil || original == fields)
            }.buttonStyle(SubtleButtonStyle()).font(.system(size: 13, weight: .medium))
        }
        .padding(20).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1))
        .task {
            guard let loaded = PersonaStore.read(url) else { error = "Failed to parse TOML"; return }
            original = loaded; fields = loaded
        }
    }

    private func save() {
        guard let original else { return }
        do {
            try PersonaStore.update(url, from: original, to: fields)
            extensions.notice = ExtensionNotice(panel: .personas, text: "Saved persona '\(fields.name.isEmpty ? row.title : fields.name)'")
            onClose()
            Task { await store.refreshFeatures(.personas) }
        } catch let failure {
            error = failure.localizedDescription
        }
    }
}
