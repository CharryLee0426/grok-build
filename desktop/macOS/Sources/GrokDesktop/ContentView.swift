import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var extras: ExtrasFeatureModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        // Sheets are attached outside the rebuilt content, so a theme preview can
        // rebuild the window behind the theme picker without dismissing it.
        splitView
            .id(extras.themeRevision)
            .frame(minWidth: store.minimalMode ? 560 : 920, minHeight: 650)
            .sheet(isPresented: $store.showSettings) { SettingsView().desktopEnvironment(store) }
            .sheet(isPresented: $store.showCommandPalette) { CommandPalette().desktopEnvironment(store) }
            .sheet(item: $store.featurePanel) { panel in FeatureBrowser(panel: panel).desktopEnvironment(store) }
            .sheet(isPresented: $store.showAdvancedPanel) { AdvancedFeatureView().desktopEnvironment(store) }
            .sheet(isPresented: $store.showRename) { RenameTaskSheet().desktopEnvironment(store) }
            .sheet(item: $store.sheet) { sheet in sheet.content.desktopEnvironment(store) }
            .onChange(of: store.windowRequest) { _, window in
                guard let window else { return }
                openWindow(id: window.rawValue)
                store.windowRequest = nil
            }
            .onChange(of: store.minimalMode) { _, minimal in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { columnVisibility = minimal ? .detailOnly : .all }
            }
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 264, max: 340)
        } detail: {
            VStack(spacing: 0) {
                AnnouncementBanner()
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
            .overlay(alignment: .topTrailing) { DebugOverlay() }
            .background(Theme.canvas)
            .navigationTitle(store.conversation?.title ?? "New task")
            .navigationSubtitle(store.project?.name ?? "Your workspace")
            .toolbar { workspaceToolbar }
            .toolbar(store.minimalMode ? .hidden : .automatic, for: .windowToolbar)
            .themedToolbarBackground()
        }
        .navigationSplitViewStyle(.balanced)
        .foregroundStyle(Theme.ink)
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

struct RenameTaskSheet: View {
    @EnvironmentObject var store: AppStore
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Rename task").font(.system(size: 20, weight: .semibold))
                Text("The new title appears in the sidebar and the window title.").font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            DesktopTextField("Task title", text: $title, symbol: "pencil")
                .onSubmit(rename)
            HStack {
                Spacer()
                Button("Cancel") { store.showRename = false }.keyboardShortcut(.cancelAction)
                Button("Rename", action: rename).keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.buttonStyle(SubtleButtonStyle()).font(.system(size: 13, weight: .medium))
        }
        .padding(24).frame(width: 460).background(Theme.surface)
        .onAppear { title = store.conversation?.title ?? "" }
    }

    private func rename() {
        guard let id = store.state.selectedConversationID else { store.showRename = false; return }
        store.features.sessions.applyRename(id: id, title: title)
        store.showRename = false
    }
}
