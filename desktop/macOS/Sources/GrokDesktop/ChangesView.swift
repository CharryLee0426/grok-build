import SwiftUI

struct ChangesView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Changes").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("+\(store.workspace.changes.reduce(0) { $0 + $1.additions })").foregroundStyle(Theme.green)
                Text("−\(store.workspace.changes.reduce(0) { $0 + $1.deletions })").foregroundStyle(.red.opacity(0.75))
                IconButton(icon: "arrow.clockwise", help: "Refresh changes") { Task { await store.refreshWorkspace() } }
            }.font(.system(size: 13, design: .monospaced)).padding(.horizontal, 17).padding(.vertical, 15)
            if let error = store.workspace.error {
                empty(icon: "folder.badge.questionmark", title: "No Git repository", subtitle: error)
            } else if store.workspace.changes.isEmpty {
                empty(icon: "checkmark.circle", title: "All clear", subtitle: "Changes to your project will appear here as you work.")
            } else {
                HStack { Text("WORKING TREE").font(.system(size: 11, weight: .medium)).tracking(1); Spacer(); Text("\(store.workspace.changes.count) files").font(.system(size: 12)) }
                    .foregroundStyle(Theme.muted).padding(.horizontal, 19).padding(.bottom, 10)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.workspace.changes) { file in
                            Button { Task { await store.selectFile(file.path) } } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "doc.text").foregroundStyle(Theme.muted)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(URL(fileURLWithPath: file.path).lastPathComponent).font(.system(size: 13)).lineLimit(1)
                                        if file.path.contains("/") { Text((file.path as NSString).deletingLastPathComponent).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle) }
                                    }
                                    Spacer(minLength: 2)
                                    if file.isBinary { Text("binary").font(.system(size: 11)).foregroundStyle(Theme.muted) }
                                    else { Text("+\(file.additions)").foregroundStyle(Theme.green); Text("−\(file.deletions)").foregroundStyle(.red.opacity(0.7)) }
                                    Text(file.status.trimmingCharacters(in: .whitespaces)).foregroundStyle(Theme.muted).frame(minWidth: 14)
                                }.font(.system(size: 12, design: .monospaced)).padding(.horizontal, 10).padding(.vertical, 10).contentShape(Rectangle())
                            }.buttonStyle(.plain).background(store.selectedFile == file.path ? Theme.hover : .clear).clipShape(RoundedRectangle(cornerRadius: 7)).help(file.path)
                        }
                    }.padding(.horizontal, 9)
                }.frame(maxHeight: store.selectedFile == nil ? .infinity : 230)
                if let selected = store.selectedFile {
                    Divider().overlay(Theme.line)
                    HStack { Text(URL(fileURLWithPath: selected).lastPathComponent).font(.system(size: 13, weight: .medium)).lineLimit(1); Spacer(); IconButton(icon: "xmark", help: "Close diff") { store.selectedFile = nil } }.padding(.horizontal, 18).padding(.vertical, 8)
                    // Up to 1 MiB of diff: one text view draws only the visible lines.
                    ReadOnlyTextView(text: store.diffText, style: .diff, wrapsLines: false, sizing: .fill)
                        .frame(maxHeight: .infinity)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) { Image(systemName: "arrow.triangle.branch"); Text(store.workspace.branch.isEmpty ? "Workspace" : store.workspace.branch).lineLimit(1); Spacer(); Text("Read-only review") }.font(.system(size: 12)).foregroundStyle(Theme.muted).padding(18).overlay(alignment: .top) { Theme.line.frame(height: 1) }
        }.background(Theme.sidebar.opacity(0.35))
    }
    private func empty(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 25, weight: .ultraLight)).foregroundStyle(Theme.muted)
            Text(title).font(.system(size: 15, weight: .medium))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).lineSpacing(3)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
