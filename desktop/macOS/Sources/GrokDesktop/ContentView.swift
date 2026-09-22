import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @State private var showSidebar = true

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar { SidebarView().frame(width: 246); Divider().overlay(Theme.line) }
            VStack(spacing: 0) {
                header
                if let banner = store.banner {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle")
                        Text(banner).textSelection(.enabled)
                        Spacer(minLength: 4)
                        IconButton(icon: "xmark", help: "Dismiss") { store.banner = nil }
                    }.font(.system(size: 12)).padding(.horizontal, 24).padding(.vertical, 9).background(Theme.hover.opacity(0.7))
                }
                HStack(spacing: 0) {
                    ConversationView().frame(maxWidth: .infinity)
                    if store.showInspector { Divider().overlay(Theme.line); ChangesView().frame(width: 330) }
                }
            }
        }
        .foregroundStyle(Theme.ink).background(Theme.canvas)
        .frame(minWidth: 920, minHeight: 650)
        .sheet(isPresented: $store.showSettings) { SettingsView().environmentObject(store) }
        .onChange(of: store.showSearch) { _, visible in
            if visible { showSidebar = true } else { store.search = "" }
        }
        .task {
            await store.refreshWorkspace()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled else { break }
                await store.refreshWorkspace()
            }
        }
        .background(Button("") { showSidebar.toggle() }.keyboardShortcut("b").hidden())
    }

    private var header: some View {
        HStack(spacing: 12) {
            IconButton(icon: "sidebar.left", help: "Toggle sidebar · ⌘B") { withAnimation(.easeInOut(duration: 0.15)) { showSidebar.toggle() } }
            if let project = store.project {
                Text(project.name).font(.system(size: 13, weight: .medium))
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Theme.muted)
                Text(store.conversation?.title ?? "New task").font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
            } else { Text("Your workspace").font(.system(size: 13, weight: .medium)) }
            Spacer()
            if store.project != nil {
                Menu {
                    Button("Reveal in Finder", systemImage: "folder") { store.revealProject() }
                    Button("Open in Terminal", systemImage: "terminal") { store.openTerminal() }
                } label: { Label("Open", systemImage: "arrow.up.right.square").font(.system(size: 12)) }
                .menuStyle(.borderlessButton).fixedSize().foregroundStyle(Theme.muted)
                Rectangle().fill(Theme.line).frame(width: 1, height: 17)
                Button { withAnimation(.easeInOut(duration: 0.15)) { store.showInspector.toggle() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.split.2x1")
                        if !store.workspace.changes.isEmpty { Text("\(store.workspace.changes.count)").font(.system(size: 11, weight: .medium, design: .monospaced)) }
                    }.padding(7).background(store.showInspector ? Theme.hover : .clear).clipShape(RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).foregroundStyle(Theme.muted).help("Changes · ⌘J").accessibilityLabel("Show changes")
            }
        }.padding(.leading, showSidebar ? 20 : 80).padding(.trailing, 22).frame(height: 58)
        .overlay(alignment: .bottom) { Theme.line.opacity(0.6).frame(height: 1) }
    }
}

struct SidebarView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) { GrokMark(size: 25); Text("Grok").font(.system(size: 19, weight: .semibold)); Text("BUILD").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.4).foregroundStyle(Theme.muted); Spacer() }
                .padding(.horizontal, 22).padding(.top, 48).padding(.bottom, 24)
            VStack(spacing: 5) {
                navigationButton("New task", icon: "square.and.pencil", shortcut: "⌘N") { store.newTask() }
                navigationButton("Search tasks", icon: "magnifyingglass", shortcut: "⌘K") { store.showSearch.toggle() }
            }.padding(.horizontal, 12)
            if store.showSearch {
                NativeSearchField(text: $store.search, placeholder: "Search all tasks", onEscape: { store.showSearch = false })
                    .frame(height: 25).padding(.horizontal, 16).padding(.top, 10)
            }
            HStack {
                Text("PROJECTS").font(.system(size: 10, weight: .medium)).tracking(1.2)
                Spacer()
                IconButton(icon: "plus", help: "Open project · ⇧⌘O") { store.addProject() }
            }.foregroundStyle(Theme.muted).padding(.leading, 22).padding(.trailing, 13).padding(.top, 25).padding(.bottom, 5)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(store.state.projects) { project in
                        Button { store.selectProject(project.id) } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "folder").font(.system(size: 13))
                                Text(project.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Spacer()
                                if project.id == store.state.selectedProjectID { Image(systemName: "chevron.down").font(.system(size: 9)) }
                            }.padding(.horizontal, 10).padding(.vertical, 10).contentShape(Rectangle())
                        }.buttonStyle(.plain).background(project.id == store.state.selectedProjectID ? Theme.hover.opacity(0.65) : .clear).clipShape(RoundedRectangle(cornerRadius: 7))
                        .help(project.path)
                    }
                    if store.state.projects.isEmpty {
                        Button { store.addProject() } label: { Label("Open your first project", systemImage: "plus").font(.system(size: 12)).padding(10) }.buttonStyle(.plain).foregroundStyle(Theme.muted)
                    }
                    HStack {
                        Text(store.showArchived ? "Archived tasks" : "Recent tasks").font(.system(size: 11, weight: .medium))
                        Spacer()
                        if store.syncing { ProgressView().controlSize(.mini) }
                        else { IconButton(icon: "arrow.triangle.2.circlepath", help: "Import tasks from the harness") { store.syncHistory() } }
                    }.foregroundStyle(Theme.muted).padding(.leading, 10).padding(.top, 18)
                    ForEach(store.visibleConversations) { task in
                        Button { store.selectConversation(task) } label: {
                            HStack(alignment: .top, spacing: 8) {
                                if store.runs[task.id]?.isRunning == true {
                                    Circle().fill(Theme.green).frame(width: 5, height: 5).padding(.top, 6)
                                } else { Image(systemName: task.isPinned ? "pin" : "bubble.left").font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.top, 2) }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(task.title).font(.system(size: 12)).lineLimit(2).multilineTextAlignment(.leading)
                                    Text(task.updatedAt, style: .relative).font(.system(size: 10)).foregroundStyle(Theme.muted)
                                }
                                Spacer(minLength: 0)
                                if !(store.runs[task.id]?.approvals.isEmpty ?? true) { Image(systemName: "hand.raised").font(.system(size: 11)).foregroundStyle(.orange) }
                            }.padding(.horizontal, 10).padding(.vertical, 10).contentShape(Rectangle())
                        }.buttonStyle(.plain).background(task.id == store.state.selectedConversationID ? Theme.hover : .clear).clipShape(RoundedRectangle(cornerRadius: 7))
                            .contextMenu {
                                Button(task.isPinned ? "Unpin task" : "Pin task") { store.togglePin(task.id) }
                                Button(task.isArchived ? "Restore task" : "Archive task") { store.archive(task.id) }.disabled(store.runs[task.id]?.isRunning == true)
                            }
                    }
                    if store.visibleConversations.isEmpty {
                        Text(store.search.isEmpty ? "Your tasks will appear here." : "No matching tasks.").font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.horizontal, 10).padding(.top, 8)
                    }
                }.padding(.horizontal, 12)
            }
            Spacer(minLength: 10)
            VStack(spacing: 4) {
                navigationButton(store.showArchived ? "Back to tasks" : "Archived tasks", icon: "archivebox") { store.showArchived.toggle() }
                navigationButton("Settings", icon: "gearshape", shortcut: "⌘,") { store.showSettings = true }
            }.padding(.horizontal, 12).padding(.bottom, 12)
            HStack(spacing: 7) {
                Circle().fill(store.binaryPath.isEmpty ? Theme.muted : Theme.green).frame(width: 5, height: 5)
                Text(store.binaryPath.isEmpty ? "Connect your harness" : "Local harness").font(.system(size: 10, weight: .medium))
                Spacer()
                Text("ACP").font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.muted)
            }.foregroundStyle(Theme.muted).padding(.horizontal, 22).padding(.vertical, 16).overlay(alignment: .top) { Theme.line.frame(height: 1) }
        }.background(Theme.sidebar)
    }

    private func navigationButton(_ title: String, icon: String, shortcut: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) { Image(systemName: icon).frame(width: 16); Text(title); Spacer(); Text(shortcut).font(.system(size: 10)).foregroundStyle(Theme.muted) }
                .font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
