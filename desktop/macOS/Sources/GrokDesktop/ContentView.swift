import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 264, max: 340)
        } detail: {
            VStack(spacing: 0) {
                if let banner = store.banner {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle")
                        Text(banner).textSelection(.enabled)
                        Spacer(minLength: 4)
                        IconButton(icon: "xmark", help: "Dismiss") { store.banner = nil }
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(Theme.hover.opacity(0.7))
                }
                HStack(spacing: 0) {
                    ConversationView().frame(maxWidth: .infinity)
                    if store.showInspector {
                        Divider().overlay(Theme.line)
                        ChangesView().frame(width: 330)
                    }
                }
            }
            .background(Theme.canvas)
            .navigationTitle(store.conversation?.title ?? "New task")
            .navigationSubtitle(store.project?.name ?? "Your workspace")
            .toolbar { workspaceToolbar }
        }
        .navigationSplitViewStyle(.balanced)
        .foregroundStyle(Theme.ink)
        .frame(minWidth: 920, minHeight: 650)
        .sheet(isPresented: $store.showSettings) { SettingsView().environmentObject(store) }
        .sheet(isPresented: $store.showCommandPalette) { CommandPalette().environmentObject(store) }
        .sheet(item: $store.featurePanel) { panel in FeatureBrowser(panel: panel).environmentObject(store) }
        .sheet(isPresented: $store.showAdvancedPanel) { AdvancedFeatureView().environmentObject(store) }
        .onChange(of: store.showSearch) { _, visible in
            if visible { columnVisibility = .all } else { store.search = "" }
        }
        .task {
            await store.refreshWorkspace()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled else { break }
                await store.refreshWorkspace()
            }
        }
        .background(Button("") {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            }
        }.keyboardShortcut("b").hidden())
    }

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if store.project != nil {
                Menu {
                    Button("Reveal in Finder", systemImage: "folder") { store.revealProject() }
                    Button("Open in Terminal", systemImage: "terminal") { store.openTerminal() }
                } label: { Label("Open", systemImage: "arrow.up.right.square") }
                .help("Open project")
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { store.showInspector.toggle() }
                } label: {
                    Label {
                        Text(store.workspace.changes.isEmpty ? "Changes" : "Changes (\(store.workspace.changes.count))")
                    } icon: {
                        Image(systemName: "sidebar.right")
                    }
                }.help("Show changes · ⌘J")
            }
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                GrokMark(size: 28)
                Text("Grok").font(.system(size: 21, weight: .semibold))
                Text("BUILD").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.4).foregroundStyle(Theme.muted)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 22)
            VStack(spacing: 5) {
                navigationButton("New task", icon: "square.and.pencil", shortcut: "⌘N") { store.newTask() }
                navigationButton("Search tasks", icon: "magnifyingglass", shortcut: "⌘K") { store.showSearch.toggle() }
                navigationButton("Commands", icon: "command", shortcut: "⇧⌘P") { store.showCommandPalette = true }
                navigationButton("Skills & tools", icon: "square.grid.2x2", shortcut: "") { store.featurePanel = .skills }
            }.padding(.horizontal, 12)
            if store.showSearch {
                NativeSearchField(text: $store.search, placeholder: "Search all tasks", onEscape: { store.showSearch = false })
                    .frame(height: 40).padding(.horizontal, 16).padding(.top, 10)
            }
            HStack {
                Text("Projects").font(.system(size: 12, weight: .semibold))
                Spacer()
                IconButton(icon: "plus", help: "Open project · ⇧⌘O") { store.addProject() }
            }
            .foregroundStyle(Theme.muted).padding(.leading, 22).padding(.trailing, 13).padding(.top, 25).padding(.bottom, 5)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(store.state.projects) { project in
                        Button { store.selectProject(project.id) } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "folder").font(.system(size: 14))
                                Text(project.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Spacer()
                                if project.id == store.state.selectedProjectID { Image(systemName: "chevron.down").font(.system(size: 10)) }
                            }.padding(.horizontal, 10).padding(.vertical, 10).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(project.id == store.state.selectedProjectID ? Theme.hover.opacity(0.65) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .help(project.path)
                    }
                    if store.state.projects.isEmpty {
                        Button { store.addProject() } label: {
                            Label("Open your first project", systemImage: "plus").font(.system(size: 13)).padding(10)
                        }.buttonStyle(.plain).foregroundStyle(Theme.muted)
                    }
                    HStack {
                        Text(store.showArchived ? "Archived tasks" : "Recent tasks").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        if store.syncing { ProgressView().controlSize(.mini) }
                        else {
                            IconButton(icon: "arrow.triangle.2.circlepath", help: "Import tasks from the harness") { store.syncHistory() }
                        }
                    }.foregroundStyle(Theme.muted).padding(.leading, 10).padding(.top, 18)
                    ForEach(store.visibleConversations) { task in
                        TaskSidebarRow(task: task)
                    }
                    if store.visibleConversations.isEmpty {
                        Text(store.search.isEmpty ? "Your tasks will appear here." : "No matching tasks.")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.horizontal, 10).padding(.top, 8)
                    }
                }.padding(.horizontal, 12)
            }
            Spacer(minLength: 10)
            VStack(spacing: 4) {
                navigationButton(store.showArchived ? "Back to tasks" : "Archived tasks", icon: "archivebox") { store.showArchived.toggle() }
                navigationButton("Settings", icon: "gearshape", shortcut: "⌘,") { store.showSettings = true }
            }.padding(.horizontal, 12).padding(.bottom, 12)
            HStack(spacing: 7) {
                Circle().fill(store.binaryPath.isEmpty ? Theme.muted : Theme.green).frame(width: 6, height: 6)
                Text(store.binaryPath.isEmpty ? "Engine unavailable" : "Runs on your Mac").font(.system(size: 11, weight: .medium))
                Spacer()
                Image(systemName: "desktopcomputer").font(.system(size: 12))
            }
            .foregroundStyle(Theme.muted).padding(.horizontal, 22).padding(.vertical, 16)
            .overlay(alignment: .top) { Theme.line.opacity(0.5).frame(height: 0.5) }
        }.background { SidebarMaterial().ignoresSafeArea() }
    }

    private func navigationButton(_ title: String, icon: String, shortcut: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 16)
                Text(title)
                Spacer()
                Text(shortcut).font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            .font(.system(size: 13)).padding(.horizontal, 10).padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct TaskSidebarRow: View {
    @EnvironmentObject var store: AppStore
    @State private var isHovered = false
    let task: Conversation

    private var isRunning: Bool { store.runs[task.id]?.isRunning == true }
    private var isBusy: Bool { isRunning || store.runs[task.id]?.isConfiguring == true }
    private var isSelected: Bool { task.id == store.state.selectedConversationID }
    private var needsApproval: Bool { !(store.runs[task.id]?.approvals.isEmpty ?? true) }

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            Button { store.selectConversation(task) } label: {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: isRunning ? "circle.fill" : task.isPinned ? "pin" : "bubble.left")
                        .font(.system(size: isRunning ? 7 : 12))
                        .foregroundStyle(isRunning ? Theme.green : Theme.muted)
                        .frame(width: 14, height: 18)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(task.title).font(.system(size: 13)).lineLimit(2).multilineTextAlignment(.leading)
                        if needsApproval {
                            Label("Needs approval", systemImage: "hand.raised").foregroundStyle(.orange)
                        } else if isRunning {
                            Text("Working…").foregroundStyle(Theme.green)
                        } else {
                            Text(task.updatedAt.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(Theme.muted)
                        }
                    }.font(.system(size: 11))
                    Spacer(minLength: 0)
                }
                .padding(.leading, 10).padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Menu { taskActions } label: {
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .medium)).frame(width: 28, height: 30)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .foregroundStyle(Theme.muted).opacity(isHovered || isSelected ? 1 : 0.45)
            .padding(.top, 4).padding(.trailing, 4)
            .help("Task actions").accessibilityLabel("Actions for \(task.title)")
        }
        .background(isSelected ? Theme.hover : isHovered ? Theme.hover.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .onHover { isHovered = $0 }
        .contextMenu { taskActions }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var taskActions: some View {
        Button(task.isPinned ? "Unpin task" : "Pin task", systemImage: task.isPinned ? "pin.slash" : "pin") { store.togglePin(task.id) }
        Button(task.isArchived ? "Restore task" : "Archive task", systemImage: "archivebox") { store.archive(task.id) }
            .disabled(isBusy)
        Divider()
        Button("Delete task", systemImage: "trash", role: .destructive) { store.deleteConversation(task.id) }
            .disabled(isBusy)
    }
}
