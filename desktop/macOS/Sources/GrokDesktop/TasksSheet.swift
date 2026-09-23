import AppKit
import SwiftUI

/// `/tasks`: everything the selected task has running in the background: workflows,
/// subagents, shell tasks and monitors, and scheduled prompts such as `/loop`.
struct TasksSheet: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var sessions: SessionFeatureModel

    var body: some View {
        let id = store.state.selectedConversationID
        // Background work lives in the task's harness process; without a connection it has stopped.
        let isLive = id.map { store.clients[$0] != nil && store.loaded.contains($0) } ?? false
        let board = isLive ? sessions.board(for: id) : SessionTaskBoard()
        let subagents = (id.flatMap { store.runs[$0]?.subagents } ?? []).map { TasksSubagent($0, stopping: sessions.stoppingSubagents.contains($0.id)) }
        let total = board.workflows.count + subagents.count + board.background.count + board.scheduled.count
        DesktopPanel(title: "Tasks", subtitle: subtitle, width: 720, height: 600, onClose: close) {
            VStack(spacing: 0) {
                if let error = sessions.tasksError {
                    SessionErrorStrip(message: error) { sessions.tasksError = nil; Task { await sessions.refreshBackgroundTasks() } }
                }
                ScrollView {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        TasksBoardView(board: board, subagents: subagents, conversationID: id, now: context.date, sessions: sessions,
                                       openWorkflows: { store.sheet = .workflowRuns }).equatable()
                    }.padding(24)
                }
            }
        } footer: {
            Text("Tasks (\(total))").font(.system(size: 12)).foregroundStyle(Theme.muted)
            if sessions.tasksLoading { ProgressView().controlSize(.small) }
            Spacer(minLength: 0)
            Button("Workflow runs…") { store.sheet = .workflowRuns }.disabled(board.workflows.isEmpty)
            Button("Refresh") { Task { await sessions.refreshBackgroundTasks() } }.disabled(sessions.tasksLoading)
            Button("Done", action: close).keyboardShortcut(.defaultAction)
        }
        .task(id: id) { await sessions.refreshBackgroundTasks() }
    }

    private var subtitle: String {
        guard let task = store.conversation else { return "Background tasks, workflows, and subagents for the selected task." }
        return "Running alongside “\(task.title)”."
    }

    private func close() { store.sheet = nil }
}

/// A subagent reduced to the values the list shows.
struct TasksSubagent: Identifiable, Equatable {
    let id: String
    var title: String
    var agentType: String
    var status: String
    var detail: String

    init(_ agent: SubagentState, stopping: Bool) {
        id = agent.id
        title = agent.title
        agentType = agent.agentType
        status = stopping && agent.status == "running" ? "stopping" : agent.status
        var parts: [String] = []
        if agent.turns > 0 { parts.append("\(agent.turns) turn\(agent.turns == 1 ? "" : "s")") }
        if agent.toolCalls > 0 { parts.append("\(agent.toolCalls) tool call\(agent.toolCalls == 1 ? "" : "s")") }
        if agent.tokensUsed > 0 { parts.append("\(SessionFormat.tokens(agent.tokensUsed)) tokens") }
        detail = parts.joined(separator: " · ")
    }

    var isRunning: Bool { status == "running" }
}

private struct TasksBoardView: View, Equatable {
    let board: SessionTaskBoard
    let subagents: [TasksSubagent]
    let conversationID: UUID?
    let now: Date
    let sessions: SessionFeatureModel
    let openWorkflows: () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        // Elapsed times only tick while something runs.
        lhs.board == rhs.board && lhs.subagents == rhs.subagents && lhs.conversationID == rhs.conversationID
            && (lhs.now == rhs.now || !(lhs.board.hasLiveWork || lhs.subagents.contains(where: \.isRunning)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if board.isEmpty && subagents.isEmpty {
                SessionEmptyState(symbol: "checklist", title: "No background tasks, workflows, or subagents.",
                                  detail: conversationID == nil ? "Select a task to see what it is running." : nil)
            }
            if !board.workflows.isEmpty {
                section("Workflows", count: board.workflows.count, symbol: "arrow.triangle.branch") {
                    ForEach(board.sortedWorkflows) { run in
                        TasksItemRow(status: run.isActive ? "running" : run.status.replacingOccurrences(of: "_", with: " "),
                                     tone: WorkflowTone.tone(for: run.status), spinning: run.isActive, kind: "Workflow", title: run.name,
                                     detail: run.activityLabel, elapsed: SessionFormat.duration(run.liveElapsed(now: now))) {
                            Button("View", action: openWorkflows)
                        }
                    }
                }
            }
            if !subagents.isEmpty {
                section("Subagents", count: subagents.count, symbol: "person.2") {
                    ForEach(subagents) { agent in
                        TasksItemRow(status: agent.status, tone: tone(forStatus: agent.status), spinning: agent.isRunning,
                                     kind: agent.agentType.isEmpty ? "Subagent" : agent.agentType, title: agent.title, detail: agent.detail, elapsed: nil) {
                            if agent.isRunning, let conversationID {
                                Button("Stop") { sessions.stopSubagent(agent.id, conversationID: conversationID) }
                            }
                        }
                    }
                }
            }
            if !board.background.isEmpty {
                section("Background tasks", count: board.background.count, symbol: "terminal") {
                    ForEach(board.sortedBackground) { task in
                        let stopping = board.stopping.contains(task.id) && task.isRunning
                        let status = stopping ? "stopping" : task.isRunning ? "running" : task.status == "completed" ? "done" : task.status
                        TasksItemRow(status: status, tone: tone(forStatus: status), spinning: task.isRunning && !stopping,
                                     kind: task.isMonitor ? "Monitor" : "Task", title: task.title, detail: detail(for: task), elapsed: elapsed(task)) {
                            if let file = task.outputFile {
                                IconButton(icon: "doc.text.magnifyingglass", help: "Show output file", size: 26) {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file)])
                                }
                            }
                            if task.isRunning, let conversationID {
                                Button("Stop") { sessions.stopBackgroundTask(task.id, conversationID: conversationID) }.disabled(stopping)
                            }
                        }
                    }
                }
            }
            if !board.scheduled.isEmpty {
                section("Scheduled", count: board.scheduled.count, symbol: "clock.arrow.2.circlepath") {
                    ForEach(board.sortedScheduled) { task in
                        TasksItemRow(status: "scheduled", tone: .accent, spinning: false, kind: task.tag + (task.schedule.isEmpty ? "" : " · \(task.schedule)"),
                                     title: SessionBackgroundTask.oneLine(task.prompt), detail: nextFire(task), elapsed: nil) {
                            if let conversationID {
                                Button("Delete") { sessions.deleteScheduledTask(task.id, conversationID: conversationID) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, count: Int, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SessionSectionTitle(title: title, count: count, symbol: symbol)
            content()
        }
    }

    private func tone(forStatus status: String) -> SessionTone {
        switch status {
        case "running", "initializing": return .accent
        case "done", "completed": return .green
        case "failed": return .red
        case "stopping": return .orange
        default: return .muted
        }
    }

    private func detail(for task: SessionBackgroundTask) -> String {
        var parts: [String] = []
        if task.title != SessionBackgroundTask.oneLine(task.command) { parts.append(SessionBackgroundTask.oneLine(task.command)) }
        if let code = task.exitCode, !task.isRunning { parts.append("exit \(code)") }
        return parts.joined(separator: " · ")
    }

    private func elapsed(_ task: SessionBackgroundTask) -> String? {
        guard let start = task.startedAt else { return nil }
        return SessionFormat.duration((task.endedAt ?? now).timeIntervalSince(start))
    }

    private func nextFire(_ task: SessionScheduledTask) -> String {
        var parts: [String] = []
        if let next = task.nextFireAt {
            parts.append(next > now ? "Next run in \(SessionFormat.duration(next.timeIntervalSince(now)))" : "Running now")
        }
        if task.firesCount > 0 { parts.append("ran \(task.firesCount)×") }
        return parts.joined(separator: " · ")
    }
}

private struct TasksItemRow<Actions: View>: View {
    let status: String
    let tone: SessionTone
    let spinning: Bool
    let kind: String
    let title: String
    let detail: String
    let elapsed: String?
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SessionStatusPill(text: status, tone: tone, spinning: spinning).frame(width: 96, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(kind).foregroundStyle(Theme.muted)
                    Text(title).fontWeight(.semibold).lineLimit(1).truncationMode(.tail)
                }.font(.system(size: 13))
                if !detail.isEmpty { Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2) }
            }
            Spacer(minLength: 8)
            if let elapsed { Text(elapsed).font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.muted) }
            HStack(spacing: 6) { actions() }.buttonStyle(SubtleButtonStyle()).font(.system(size: 12, weight: .medium))
        }
        .sessionCard(padding: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(kind) \(title), \(status)")
    }
}

enum WorkflowTone {
    static func tone(for status: String) -> SessionTone {
        switch status {
        case "active": return .accent
        case "complete": return .green
        case "failed", "interrupted": return .red
        case "cancelled": return .muted
        default: return .orange
        }
    }
}

/// `/workflow runs`: the selected task's workflow runs with their phases and agents, and the
/// terminal's pause, resume, stop, and save controls.
struct WorkflowRunsSheet: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var sessions: SessionFeatureModel

    var body: some View {
        let runs = sessions.board(for: store.state.selectedConversationID).sortedWorkflows
        let managed = sessions.workflowManagementAvailable
        let busy = store.run.isRunning || store.run.isConfiguring
        DesktopPanel(title: "Workflow runs", subtitle: "Pause, resume, stop, or save the workflows running in this task.", width: 760, height: 640, onClose: close) {
            ScrollView {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(runs) { run in
                            WorkflowRunCard(run: run, managed: managed, busy: busy, now: context.date) { operation in
                                sessions.workflowAction(operation, run: run)
                            }
                        }
                        if runs.isEmpty {
                            SessionEmptyState(symbol: "arrow.triangle.branch", title: "No workflow runs in this session yet.",
                                              detail: "Start one with /deep-research <query> or ask for a workflow.")
                        }
                    }
                }.padding(24)
            }
        } footer: {
            Text(runs.isEmpty ? "No runs" : "\(runs.count) run\(runs.count == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(Theme.muted)
            if busy && !runs.isEmpty {
                Text("Controls wait for the current turn to finish.").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Button("Done", action: close).keyboardShortcut(.defaultAction)
        }
    }

    private func close() { store.sheet = nil }
}

private struct WorkflowRunCard: View {
    let run: SessionWorkflowRun
    let managed: Bool
    let busy: Bool
    let now: Date
    let perform: (String) -> Void
    @State private var showsAgents: Bool

    init(run: SessionWorkflowRun, managed: Bool, busy: Bool, now: Date, perform: @escaping (String) -> Void) {
        self.run = run; self.managed = managed; self.busy = busy; self.now = now; self.perform = perform
        // An active run shows who is working; finished runs start folded.
        _showsAgents = State(initialValue: run.isActive)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                SessionStatusPill(text: run.isActive ? "running" : run.status.replacingOccurrences(of: "_", with: " "), tone: WorkflowTone.tone(for: run.status), spinning: run.isActive)
                Text(run.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 8)
                Text(meta).font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            if !run.objective.isEmpty {
                Text(run.objective).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(3).textSelection(.enabled)
            }
            if let note = run.statusNote {
                Label(note, systemImage: run.status == "failed" ? "xmark.octagon" : "pause.circle")
                    .font(.system(size: 12)).foregroundStyle(run.status == "failed" ? Color.red : Color.orange)
            }
            if !run.phases.isEmpty { phaseRail }
            if let summary = run.resultSummary {
                Text(summary).font(.system(size: 12)).textSelection(.enabled).padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading).background(Theme.input, in: RoundedRectangle(cornerRadius: 8))
            }
            if !run.agents.isEmpty {
                Button {
                    withTransaction(Transaction(animation: nil)) { showsAgents.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted)
                            .rotationEffect(.degrees(showsAgents ? 90 : 0)).frame(width: 12)
                        Text("Agents").font(.system(size: 12, weight: .semibold))
                        Text(budget).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showsAgents ? "Expanded" : "Collapsed")
                if showsAgents {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(run.agents) { agent in agentRow(agent) }
                    }.padding(.leading, 18)
                }
            } else {
                Text(budget).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Pause") { perform("pause") }.disabled(!run.canPause(managed: managed) || busy)
                Button("Resume") { perform("resume") }.disabled(!run.canResume(managed: managed) || busy)
                Button("Stop") { perform("stop") }.disabled(!run.canStop(managed: managed) || busy)
                Button("Save") { perform("save") }.disabled(!run.canSave(managed: managed) || busy)
                    .help("Save this run's workflow so it can be launched again")
            }.buttonStyle(SubtleButtonStyle()).font(.system(size: 12, weight: .medium))
        }
        .sessionCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workflow \(run.name), \(run.activityLabel)")
    }

    private var meta: String {
        let count = run.agents.count
        return "\(run.finishedAgents)/\(count) agent\(count == 1 ? "" : "s") · \(SessionFormat.duration(run.liveElapsed(now: now)))"
    }

    private var budget: String {
        var text = "\(run.agentsUsed) used"
        if let limit = run.agentBudget { text += " of \(limit)" }
        if run.agentsReserved > 0 { text += " · \(run.agentsReserved) reserved" }
        if run.agentUsageIncomplete { text += " · usage incomplete" }
        return text
    }

    private var phaseRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(run.phases.enumerated()), id: \.offset) { index, phase in
                    if index > 0 { Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.muted.opacity(0.6)) }
                    HStack(spacing: 5) {
                        phaseGlyph(phase.state)
                        Text(phase.title).font(.system(size: 11, weight: phase.title == run.currentPhase ? .semibold : .regular)).lineLimit(1)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(phase.title == run.currentPhase ? Theme.accent.opacity(0.12) : Theme.hover.opacity(0.5), in: Capsule())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(phase.title), \(phase.state)")
                }
            }
        }
    }

    @ViewBuilder private func phaseGlyph(_ state: String) -> some View {
        switch state {
        case "complete", "completed", "done": Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.green)
        case "failed": Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.red)
        case "active", "running": Circle().fill(Theme.accent).frame(width: 6, height: 6)
        case "skipped", "cancelled": Image(systemName: "minus").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.muted)
        default: Circle().strokeBorder(Theme.muted, lineWidth: 1).frame(width: 6, height: 6)
        }
    }

    private func agentRow(_ agent: SessionWorkflowRun.Agent) -> some View {
        HStack(spacing: 8) {
            phaseGlyph(agent.state).frame(width: 10)
            Text(agent.label).font(.system(size: 12, weight: .medium)).lineLimit(1)
            if let phase = agent.phase { Text(phase).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1) }
            Spacer(minLength: 6)
            Text([agent.model, agent.tokensUsed > 0 ? "\(SessionFormat.tokens(agent.tokensUsed)) tokens" : nil,
                  agent.durationMS > 0 ? SessionFormat.duration(Double(agent.durationMS) / 1000) : nil].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
        }
    }
}
