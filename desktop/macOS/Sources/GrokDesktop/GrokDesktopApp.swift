import SwiftUI
import AppKit

@main
struct GrokDesktopApp: App {
    @StateObject private var store = AppStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        Window("Grok Desktop", id: "main") {
            ContentView().environmentObject(store)
                .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
                .onAppear { delegate.store = store; NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1240, height: 820)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") { store.newTask() }.keyboardShortcut("n")
                Button("Open Project…") { store.addProject() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Search Tasks") { store.showSearch.toggle() }.keyboardShortcut("k")
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { store.showSettings = true }.keyboardShortcut(",")
            }
            CommandMenu("Task") {
                Button("Stop") { store.cancel() }.keyboardShortcut(".").disabled(!store.run.isRunning)
                Button("Import Harness Tasks") { store.syncHistory() }.disabled(store.project == nil || store.syncing)
                Divider()
                Button("Show Changes") { store.showInspector.toggle() }.keyboardShortcut("j")
                Button("Open in Terminal") { store.openTerminal() }.disabled(store.project == nil)
                Button("Reveal Project in Finder") { store.revealProject() }.disabled(store.project == nil)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: AppStore?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if store?.runs.values.contains(where: { $0.isRunning }) == true {
            let alert = NSAlert()
            alert.messageText = "Quit while Grok is working?"
            alert.informativeText = "Active tasks will stop. Your conversations are saved and can be resumed."
            alert.addButton(withTitle: "Keep Working"); alert.addButton(withTitle: "Quit")
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
        }
        store?.shutdown(); return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
