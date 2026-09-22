import SwiftUI
import AppKit

struct ConversationView: View {
    @EnvironmentObject var store: AppStore
    @State private var followOutput = true
    @State private var showModels = false
    @State private var modelSearch = ""

    var body: some View {
        VStack(spacing: 0) {
            if store.conversation == nil { welcome.frame(maxHeight: .infinity) }
            else { transcript }
            VStack(spacing: 10) {
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
                        }.font(.system(size: 12)).padding(.vertical, 8)
                    } label: {
                        HStack {
                            Image(systemName: "list.bullet.clipboard")
                            Text("Plan")
                            Spacer()
                            Text("\(store.run.plan.filter { $0.status == "completed" }.count) of \(store.run.plan.count)").foregroundStyle(Theme.muted)
                        }.font(.system(size: 11, weight: .medium))
                    }.padding(12).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                composer
                HStack(spacing: 7) {
                    if !store.workspace.branch.isEmpty {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 10))
                        Text(store.workspace.branch).font(.system(size: 10, weight: .medium)).lineLimit(1)
                        Text("·")
                    }
                    Text(store.project == nil ? "Choose a project to get started" : "Local workspace").font(.system(size: 10))
                    Spacer()
                    Text("↵ Send  ·  ⇧↵ New line").font(.system(size: 10))
                }.foregroundStyle(Theme.muted).padding(.horizontal, 5)
            }.frame(maxWidth: 760).padding(.horizontal, 32).padding(.bottom, 20).padding(.top, 12)
        }
        .task(id: store.state.selectedConversationID) { await store.loadImportedConversation() }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            GrokMark(size: 47).padding(.bottom, 24)
            Text("What will you build?").font(.system(size: 31, weight: .medium, design: .serif)).tracking(-0.6)
            HStack(spacing: 5) {
                Text("A little curiosity. A lot of possibility.")
            }.font(.system(size: 13)).foregroundStyle(Theme.muted).padding(.top, 12)
            if let project = store.project {
                HStack(spacing: 7) { Image(systemName: "folder"); Text(project.name); Image(systemName: "chevron.down").font(.system(size: 8)) }
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.muted).padding(.horizontal, 12).padding(.vertical, 8)
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
                    Text(title).font(.system(size: 12, weight: .medium))
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(17).background(Theme.surface.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.line, lineWidth: 1)).contentShape(RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain).disabled(store.project == nil)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 23) {
                    ForEach(store.conversation?.messages ?? []) { message in MessageView(message: message) }
                    if store.run.isRunning {
                        HStack(spacing: 9) {
                            ProgressView().controlSize(.mini)
                            Text(store.run.approvals.isEmpty && store.run.questions.isEmpty ? store.run.phase + "…" : "Waiting for your response")
                                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }.padding(.vertical, 5)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.frame(maxWidth: 710, alignment: .leading).padding(.horizontal, 36).padding(.top, 34).padding(.bottom, 15).frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: store.conversation?.messages.last?.text) { _, _ in if followOutput { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: store.conversation?.messages.count) { _, _ in if followOutput { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: store.state.selectedConversationID) { _, _ in followOutput = true; proxy.scrollTo("bottom", anchor: .bottom) }
            .overlay(alignment: .bottomTrailing) {
                if store.run.isRunning {
                    Button { followOutput.toggle(); if followOutput { proxy.scrollTo("bottom", anchor: .bottom) } } label: {
                        Label(followOutput ? "Following" : "Follow output", systemImage: followOutput ? "arrow.down.to.line" : "arrow.down")
                            .font(.system(size: 10)).padding(7).background(Theme.surface).clipShape(Capsule())
                    }.buttonStyle(.plain).foregroundStyle(Theme.muted).padding(.trailing, 22)
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if store.draft.isEmpty {
                    Text(store.conversation == nil ? "Ask Grok to build, fix, or explore anything…" : "Continue the conversation…")
                        .font(.system(size: 14)).foregroundStyle(Theme.muted).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                }
                PromptEditor(text: $store.draft, onSubmit: { store.send() })
                    .frame(height: store.draft.components(separatedBy: "\n").count > 3 ? 112 : 70)
                    .accessibilityLabel("Message Grok")
            }
            HStack(spacing: 12) {
                Menu {
                    Button("Open project…", systemImage: "folder.badge.plus") { store.addProject() }
                    Button("Reveal project in Finder", systemImage: "folder") { store.revealProject() }.disabled(store.project == nil)
                } label: { Image(systemName: "plus").font(.system(size: 16, weight: .light)) }
                    .menuStyle(.borderlessButton).fixedSize().help("Project actions")
                if store.run.models.isEmpty {
                    Text("Harness default").font(.system(size: 11)).foregroundStyle(Theme.muted).help("Uses the model configured in Grok. Available models appear after connecting.")
                } else {
                    Button { modelSearch = ""; showModels.toggle() } label: {
                        HStack(spacing: 5) {
                            Text(store.run.models.first { $0.id == store.run.modelID }?.name ?? store.run.modelID).font(.system(size: 11)).lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 8))
                        }
                    }.buttonStyle(.plain).disabled(store.run.isRunning).popover(isPresented: $showModels, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                NativeSearchField(text: $modelSearch, placeholder: "Find a model or provider…", onEscape: { showModels = false }).frame(height: 25)
                            }.font(.system(size: 12)).padding(14)
                            Divider()
                            ScrollView {
                                LazyVStack(spacing: 2) {
                                    ForEach(store.run.models.filter { modelSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(modelSearch) || $0.id.localizedCaseInsensitiveContains(modelSearch) }) { model in
                                        Button {
                                            store.setModel(model); showModels = false
                                        } label: {
                                            HStack(spacing: 10) {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(model.name).font(.system(size: 12)).foregroundStyle(Theme.ink)
                                                    Text(model.id).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.muted).lineLimit(1)
                                                }
                                                Spacer(minLength: 0)
                                                if model.id == store.run.modelID { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                                            }.padding(10).contentShape(Rectangle())
                                        }.buttonStyle(.plain).background(model.id == store.run.modelID ? Theme.hover : .clear).clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }.padding(6)
                            }.frame(height: 300)
                            Divider()
                            Text("\(store.run.models.count) models from your harness").font(.system(size: 10)).foregroundStyle(Theme.muted).padding(12)
                        }.frame(width: 350).background(Theme.canvas)
                    }
                }
                if !store.run.modes.isEmpty {
                    Menu {
                        ForEach(store.run.modes) { mode in Button(mode.name) { store.setMode(mode) } }
                    } label: { Text(store.run.modes.first { $0.id == store.run.modeID }?.name ?? "Mode").font(.system(size: 11)) }
                        .menuStyle(.borderlessButton).fixedSize().disabled(store.run.isRunning)
                }
                Spacer(minLength: 0)
                if store.run.isRunning {
                    Button { store.cancel() } label: { Image(systemName: "stop.fill").font(.system(size: 11)).foregroundStyle(Theme.canvas).frame(width: 31, height: 31).background(Theme.ink).clipShape(Circle()) }
                        .buttonStyle(.plain).help("Stop task · ⌘.").accessibilityLabel("Stop task")
                } else {
                    Button { store.send() } label: {
                        Image(systemName: "arrow.up").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.canvas).frame(width: 31, height: 31)
                            .background(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.muted.opacity(0.35) : Theme.ink).clipShape(Circle())
                    }.buttonStyle(.plain).disabled(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.project == nil).help("Send message").accessibilityLabel("Send message")
                }
            }.foregroundStyle(Theme.muted).padding(.horizontal, 5)
        }.padding(13).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(Theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.025), radius: 10, y: 3)
    }
}

struct PromptEditor: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let editor = SubmitTextView(); editor.delegate = context.coordinator; editor.onSubmit = onSubmit
        editor.isRichText = false; editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.font = .systemFont(ofSize: 14); editor.textColor = .labelColor; editor.backgroundColor = .clear
        editor.textContainerInset = NSSize(width: 0, height: 7); editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.setAccessibilityLabel("Message Grok")
        scroll.documentView = editor; return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? SubmitTextView else { return }
        if editor.string != text { editor.string = text }
        editor.onSubmit = onSubmit
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
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) && !hasMarkedText() { onSubmit?() }
        else { super.keyDown(with: event) }
    }
}

struct MessageView: View {
    let message: Message
    var body: some View {
        switch message.kind {
        case .user:
            HStack { Spacer(minLength: 48); Text(message.text).font(.system(size: 14)).textSelection(.enabled).padding(.horizontal, 17).padding(.vertical, 13).background(Theme.sidebar).clipShape(RoundedRectangle(cornerRadius: 16)) }
        case .assistant:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) { GrokMark(size: 18); Text("Grok").font(.system(size: 11, weight: .semibold)) }
                MarkdownContent(text: message.text)
            }
        case .thought:
            DisclosureGroup { Text(message.text).font(.system(size: 12)).foregroundStyle(Theme.muted).textSelection(.enabled).padding(.top, 8) }
                label: { Label("Thinking", systemImage: "sparkle").font(.system(size: 11)).foregroundStyle(Theme.muted) }
        case .tool:
            DisclosureGroup {
                if let detail = message.detail, !detail.isEmpty {
                    ScrollView([.horizontal, .vertical]) { Text(detail).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 230).padding(.top, 10)
                } else { Text("No additional output.").font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.top, 8) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: message.status == "completed" ? "checkmark.circle" : message.status == "failed" ? "xmark.circle" : "terminal")
                        .foregroundStyle(message.status == "failed" ? .red : Theme.muted)
                    Text(message.text).lineLimit(2)
                    Spacer()
                    Text((message.status ?? "pending").replacingOccurrences(of: "_", with: " ")).font(.system(size: 10)).foregroundStyle(Theme.muted)
                }.font(.system(size: 12))
            }.padding(13).background(Theme.sidebar.opacity(0.65)).clipShape(RoundedRectangle(cornerRadius: 9))
        case .system:
            HStack(alignment: .top, spacing: 9) { Image(systemName: "exclamationmark.circle"); Text(message.text).textSelection(.enabled) }.font(.system(size: 12)).foregroundStyle(Theme.muted).padding(13).background(Theme.sidebar).clipShape(RoundedRectangle(cornerRadius: 9))
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
                            Text(lines.first ?? "code").font(.system(size: 10, design: .monospaced))
                            Spacer()
                            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) } label: { Label("Copy", systemImage: "doc.on.doc").font(.system(size: 10)) }.buttonStyle(.plain)
                        }.foregroundStyle(Theme.muted).padding(11)
                        Divider()
                        ScrollView(.horizontal) { Text(code).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(13).frame(maxWidth: .infinity, alignment: .leading) }
                    }.background(Theme.sidebar).clipShape(RoundedRectangle(cornerRadius: 9))
                } else if !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 13) {
                        ForEach(Array(part.trimmingCharacters(in: .newlines).components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                            if paragraph.hasPrefix("#") {
                                let marks = paragraph.prefix(while: { $0 == "#" }).count
                                Text(tryAttributed(String(paragraph.dropFirst(marks)).trimmingCharacters(in: .whitespaces)))
                                    .font(.system(size: marks == 1 ? 22 : marks == 2 ? 18 : 15, weight: .semibold)).padding(.top, 4)
                            } else if paragraph.hasPrefix("> ") {
                                Text(tryAttributed(paragraph.components(separatedBy: "\n").map { $0.hasPrefix("> ") ? String($0.dropFirst(2)) : $0 }.joined(separator: "\n")))
                                    .font(.system(size: 14)).foregroundStyle(Theme.muted).padding(.leading, 13)
                                    .overlay(alignment: .leading) { Theme.accent.opacity(0.4).frame(width: 2) }
                            } else {
                                Text(tryAttributed(paragraph)).font(.system(size: 14))
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
            Label(approval.title, systemImage: "hand.raised").font(.system(size: 13, weight: .semibold))
            ScrollView { Text(approval.detail).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 120)
            HStack {
                Spacer()
                ForEach(approval.options) { option in
                    Button(option.name) { store.approve(approval, option: option) }.buttonStyle(SubtleButtonStyle()).font(.system(size: 11, weight: .medium))
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
            Label("A question from Grok", systemImage: "bubble.left.and.bubble.right").font(.system(size: 13, weight: .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(request.questions) { question in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(question.question).font(.system(size: 12, weight: .medium))
                            ForEach(question.options, id: \.self) { option in
                                Button {
                                    if question.multiSelect {
                                        if selections[question.question, default: []].contains(option) { selections[question.question]?.remove(option) }
                                        else { selections[question.question, default: []].insert(option) }
                                    } else { selections[question.question] = [option] }
                                } label: {
                                    Label(option, systemImage: selections[question.question, default: []].contains(option) ? "checkmark.circle.fill" : "circle").font(.system(size: 11))
                                }.buttonStyle(.plain)
                            }
                            TextField("Or write a response…", text: Binding(get: { notes[question.question] ?? "" }, set: { notes[question.question] = $0 })).textFieldStyle(.roundedBorder).font(.system(size: 12))
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
            }.font(.system(size: 11))
        }.padding(16).background(Theme.sidebar).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
