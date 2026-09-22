import AppKit
import SwiftUI

/// Desktop equivalents of the pager's frontend commands. Harness commands and
/// user-invocable skills are merged into this catalog by AppStore.
enum DesktopCommands {
    static let catalog: [SlashCommand] = [
        command("help", "Browse all commands and skills", aliases: ["commands", "?"]),
        command("new", "Start a new task", aliases: ["clear"]),
        command("resume", "Find and resume a saved task"),
        command("fork", "Branch this conversation into a new task"),
        command("rewind", "Restore a previous conversation checkpoint", aliases: ["undo"]),
        command("recap", "Summarize recent work in this task", aliases: ["summarize"]),
        command("plan", "Plan before making changes", hint: "[description]"),
        command("view-plan", "Read the current plan", aliases: ["show-plan", "plan-view"]),
        command("mcps", "Manage MCP servers and their tools", aliases: ["mcp"]),
        command("skills", "Browse, enable, and run skills"),
        command("subagents", "Inspect and stop running subagents", aliases: ["dashboard", "agents-dashboard", "sessions"]),
        command("btw", "Ask a side question without interrupting your task", hint: "<question>"),
        command("tasks", "Inspect background tasks and their output"),
        command("usage", "Inspect this session's token usage and cost", aliases: ["cost"]),
        command("imagine", "Generate an image", hint: "<description>"),
        command("imagine-video", "Generate a video", hint: "<description>"),
        command("config-agents", "Browse agent definitions", aliases: ["agents"]),
        command("personas", "Browse agent personas"),
        command("workflows", "Browse and launch saved workflows"),
        command("plugins", "Manage installed plugins", hint: "[list|install|uninstall|update|reload]", aliases: ["plugin", "marketplace"]),
        command("hooks", "Inspect configured hooks"),
        command("model", "Choose the model for this task", hint: "[model]", aliases: ["m"]),
        command("effort", "Choose the thinking level", hint: "[level]"),
        command("settings", "Open desktop settings", aliases: ["config", "preferences", "prefs"]),
        command("login", "Manage provider accounts"),
        command("logout", "Manage signed-in provider accounts"),
        command("theme", "Choose system, light, or dark appearance", hint: "[system|light|dark]", aliases: ["t"]),
        command("changes", "Inspect changes in this project", aliases: ["diff"]),
        command("history", "Reuse an earlier prompt"),
        command("transcript", "Browse and search this conversation", aliases: ["find", "f", "timeline", "jump", "log"]),
        command("compact-mode", "Toggle a denser conversation layout"),
        command("multiline", "Toggle Return for new lines and ⌘Return to send", aliases: ["ml"]),
        command("copy", "Copy the latest assistant response"),
        command("export", "Save this conversation as Markdown"),
        command("rename", "Rename this task", hint: "<title>", aliases: ["title"]),
        command("delete", "Delete this task from desktop history"),
        command("cd", "Switch the project folder", hint: "[path]"),
        command("home", "Return to a new task", aliases: ["welcome"]),
        command("docs", "Open the Grok Build documentation", aliases: ["howto", "guides", "tutorial", "tour", "onboarding"]),
        command("terminal", "Open this project in Terminal"),
        command("fullscreen", "Toggle the desktop window's full screen", aliases: ["full"]),
        command("exit", "Quit Grok Desktop", aliases: ["quit", "q"])
    ]

    private static func command(_ name: String, _ description: String, hint: String? = nil, aliases: [String] = []) -> SlashCommand {
        SlashCommand(name: name, description: description, argumentHint: hint, source: "Desktop", aliases: aliases)
    }

    static func canonical(_ name: String) -> String {
        catalog.first { $0.name == name || $0.aliases.contains(name) }?.name ?? name
    }

    static func matches(_ commands: [SlashCommand], query: String) -> [SlashCommand] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !query.isEmpty else { return commands }
        func rank(_ command: SlashCommand) -> Int? {
            let names = [command.name.lowercased()] + command.aliases.map { $0.lowercased() }
            if names.contains(query) { return 0 }
            if names.contains(where: { $0.hasPrefix(query) }) { return 1 }
            if names.contains(where: { $0.contains(query) }) { return 2 }
            if command.description.localizedCaseInsensitiveContains(query) { return 3 }
            for name in names {
                var remaining = query[...]
                for character in name where remaining.first == character { remaining = remaining.dropFirst() }
                if remaining.isEmpty { return 4 }
            }
            return nil
        }
        var ranked: [(score: Int, index: Int, command: SlashCommand)] = []
        for (index, command) in commands.enumerated() {
            if let score = rank(command) { ranked.append((score, index, command)) }
        }
        ranked.sort { lhs, rhs in lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score < rhs.score }
        return ranked.map { $0.command }
    }
}

extension SlashCommand {
    var symbol: String {
        switch DesktopCommands.canonical(name) {
        case "plan", "view-plan": return "list.bullet.clipboard"
        case "goal": return "scope"
        case "mcps": return "point.3.connected.trianglepath.dotted"
        case "skills": return "sparkles"
        case "subagents", "config-agents", "personas": return "person.2"
        case "workflows", "workflow": return "arrow.triangle.branch"
        case "plugins": return "puzzlepiece.extension"
        case "model", "effort": return "brain"
        case "settings", "hooks": return "slider.horizontal.3"
        case "new": return "square.and.pencil"
        case "resume", "history", "transcript": return "clock.arrow.circlepath"
        default: return isSkill ? "sparkles" : "command"
        }
    }
}

extension AppStore {
    /// Return false only for commands owned by the connected harness.
    func handleDesktopCommand(_ name: String, arguments: String) -> Bool {
        let command = DesktopCommands.canonical(name)
        switch command {
        case "help": showCommandPalette = true
        case "new", "home": newTask()
        case "resume": showSearch = true; syncHistory()
        case "fork":
            if arguments.isEmpty { Task { await forkSession() } }
            else { banner = "Desktop /fork branches into the same project. Use the terminal for /fork with worktree flags." }
        case "btw": askSideQuestion(arguments)
        case "recap": Task { await requestRecap() }
        case "rewind": Task { await loadRewindPoints() }
        case "imagine": generateMedia(kind: "image", description: arguments)
        case "imagine-video": generateMedia(kind: "video", description: arguments)
        case "tasks": Task { await showTasks() }
        case "usage": Task { await showUsage() }
        case "plan": enterPlanMode(description: arguments)
        case "view-plan": featurePanel = .plan
        case "mcps": featurePanel = .mcps
        case "skills": featurePanel = .skills
        case "subagents": featurePanel = .agents
        case "config-agents": featurePanel = .agentDefinitions
        case "personas": featurePanel = .personas
        case "workflows": featurePanel = .workflows
        case "plugins" where arguments.isEmpty: featurePanel = .plugins
        case "hooks": featurePanel = .hooks
        case "memory" where arguments.isEmpty, "mem" where arguments.isEmpty: featurePanel = .memory
        case "goal" where arguments.isEmpty: featurePanel = .goals
        case "model":
            if arguments.isEmpty { featurePanel = .models }
            else if let option = run.models.first(where: { $0.id == arguments || $0.name.lowercased() == arguments.lowercased() }) { setModel(option) }
            else { banner = "Model ‘\(arguments)’ is unavailable. Choose a model from /model." }
        case "effort":
            if arguments.isEmpty { featurePanel = .reasoning }
            else if let option = run.reasoningOptions.first(where: { $0.id == arguments || $0.name.lowercased() == arguments.lowercased() }) { setReasoning(option) }
            else { banner = "Thinking level ‘\(arguments)’ is unavailable for this model." }
        case "settings", "login", "logout": showSettings = true
        case "theme":
            if ["light", "dark", "system"].contains(arguments) { UserDefaults.standard.set(arguments, forKey: "appearance") }
            else { showSettings = true }
        case "changes": showInspector = true
        case "history": featurePanel = .history
        case "transcript": featurePanel = .transcript
        case "compact-mode": UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "compactConversation"), forKey: "compactConversation")
        case "multiline": UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "composerMultiline"), forKey: "composerMultiline")
        case "auto":
            if let mode = run.modes.first(where: { $0.id == "auto" }) { setMode(mode) }
            else { banner = "Auto permission mode is not available in this session." }
        case "copy":
            if let text = conversation?.messages.last(where: { $0.kind == .assistant })?.text {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
            } else { banner = "This task does not have an assistant response to copy yet." }
        case "export": exportConversation()
        case "rename":
            if let id = state.selectedConversationID, let index = state.conversations.firstIndex(where: { $0.id == id }), !arguments.isEmpty {
                state.conversations[index].title = arguments; save()
            } else { banner = "Use /rename <title> in an existing task." }
        case "delete":
            guard let id = state.selectedConversationID, !run.isRunning else { banner = "Select a stopped task first."; return true }
            let alert = NSAlert(); alert.messageText = "Delete this task?"
            alert.informativeText = "This removes the conversation from desktop history. Harness history is retained."
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Delete")
            if alert.runModal() == .alertSecondButtonReturn { deleteConversation(id) }
        case "cd":
            if arguments.isEmpty { addProject() }
            else {
                let expanded = (arguments as NSString).expandingTildeInPath
                let base = URL(fileURLWithPath: project?.path ?? FileManager.default.currentDirectoryPath)
                let path = URL(fileURLWithPath: expanded, relativeTo: base).standardizedFileURL.resolvingSymlinksInPath().path
                var directory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue else { banner = "Project folder does not exist: \(path)"; return true }
                let item = state.projects.first(where: { $0.path == path }) ?? Project(path: path)
                if !state.projects.contains(where: { $0.id == item.id }) { state.projects.append(item) }
                selectProject(item.id)
            }
        case "docs": NSWorkspace.shared.open(URL(string: "https://docs.x.ai/build/overview")!)
        case "terminal": openTerminal()
        case "fullscreen": NSApp.keyWindow?.toggleFullScreen(nil)
        case "exit": NSApp.terminate(nil)
        case "minimal", "vim-mode", "toggle-mouse-reporting", "scroll-debug", "debug", "gboom", "edit-prompt", "terminal-setup", "terminal-check", "terminal-info", "doctor", "expand":
            banner = "/\(name) controls the terminal interface. In Grok Desktop, use the native editor, scrolling, and window controls."
        case "remember", "privacy", "share", "voice", "import-claude", "queue", "announcements", "timestamps", "release-notes", "changelog":
            banner = "/\(name) requires a harness interface that this desktop version does not yet expose. Use Open in Terminal for this command."
        default: return false
        }
        return true
    }

    private func exportConversation() {
        guard let conversation else { banner = "Start a task before exporting a conversation."; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Grok conversation.md"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let markdown = "# \(conversation.title)\n\n" + conversation.messages.map { "## \($0.kind.rawValue.capitalized)\n\n\($0.text)" }.joined(separator: "\n\n")
        do { try markdown.write(to: destination, atomically: true, encoding: .utf8) }
        catch { banner = "Could not export the conversation: \(error.localizedDescription)" }
    }
}
