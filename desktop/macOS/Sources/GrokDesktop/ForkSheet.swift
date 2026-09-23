import SwiftUI

/// "Run this fork in an isolated git worktree?", asked when `/fork` runs in a git repository
/// without a flag and `[hints].fork_worktree_mode` is `ask`.
struct ForkSheet: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var sessions: SessionFeatureModel
    let arguments: String

    private var directive: String? { (try? SessionForkArguments.parse(arguments))?.directive }

    var body: some View {
        DesktopPanel(title: "Fork", subtitle: "Run this fork in an isolated git worktree?", width: 540, onClose: { store.sheet = nil }) {
            VStack(alignment: .leading, spacing: 16) {
                if let parent = store.conversation {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch").foregroundStyle(Theme.muted).accessibilityHidden(true)
                        Text(parent.title).lineLimit(1).truncationMode(.tail)
                        if let project = store.project {
                            Text("·").foregroundStyle(Theme.muted)
                            Text(project.name).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                    }.font(.system(size: 12, weight: .medium))
                }
                if let directive {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("First prompt").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                        Text(directive).font(.system(size: 13)).lineLimit(4).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(Theme.input, in: RoundedRectangle(cornerRadius: 10))
                }
                VStack(spacing: 6) {
                    ForEach(Array(SessionForkChoice.allCases.enumerated()), id: \.element) { index, choice in
                        ForkChoiceRow(choice: choice, number: index + 1, isDefault: choice == .yes) {
                            sessions.resolveFork(choice, arguments: arguments)
                        }
                    }
                }
            }.padding(24)
        } footer: {
            Text("A worktree keeps the fork's file changes apart from this task.").font(.system(size: 12)).foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
            Button("Cancel") { store.sheet = nil }
        }
    }
}

private struct ForkChoiceRow: View {
    let choice: SessionForkChoice
    let number: Int
    let isDefault: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        let button = Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: choice.symbol).font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isDefault ? Theme.accent : Theme.muted).frame(width: 22).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(choice.title).font(.system(size: 14, weight: .semibold))
                    Text(choice.detail).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                Text(isDefault ? "↩" : "\(number)").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Theme.muted)
                    .frame(minWidth: 20, minHeight: 20).background(Theme.hover.opacity(0.8), in: RoundedRectangle(cornerRadius: 5))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovered ? Theme.hover.opacity(0.7) : isDefault ? Theme.hover.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isDefault ? Theme.accent.opacity(0.45) : Theme.line.opacity(0.3), lineWidth: isDefault ? 1 : 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("\(choice.title): \(choice.detail)")
        if isDefault { button.keyboardShortcut(.defaultAction) }
        else { button.keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: []) }
    }
}
