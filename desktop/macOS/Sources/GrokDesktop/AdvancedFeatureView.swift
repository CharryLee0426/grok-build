import SwiftUI
import AppKit

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
                    if let content = store.advancedContent { MarkdownContent(text: content, style: .panel) }
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
        }.frame(width: 700).glassSheetBackground()
            .confirmationDialog("Restore this checkpoint?", isPresented: $confirmRewind, titleVisibility: .visible) {
                if let checkpoint { Button("Restore \(rewindMode.title)", role: .destructive) { Task { await store.restoreRewind(checkpoint, mode: rewindMode) }; self.checkpoint = nil } }
            } message: { Text(rewindMode == .conversationOnly ? "Later conversation turns will be removed from this task." : rewindMode == .filesOnly ? "The previewed files will be replaced with their checkpoint contents." : "Later conversation turns will be removed and the previewed files will be replaced with their checkpoint contents.") }
    }
}
