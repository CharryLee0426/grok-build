import SwiftUI

/// Permission mode, input, and voice preferences in Settings. Everything except multiline input is
/// shared with the terminal through `config.toml`.
struct BehaviorSettingsSection: View {
    @EnvironmentObject var composer: ComposerFeatureModel
    @AppStorage("composerMultiline") private var multiline = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Behavior", systemImage: "slider.horizontal.3").font(.system(size: 15, weight: .semibold))
            row("Permissions", detail: composer.permissionMode.detail, warning: composer.permissionMode.isAlwaysApprove) {
                Picker("Permissions", selection: Binding(get: { composer.permissionMode }, set: { composer.setPermissionMode($0) })) {
                    ForEach(permissionModes) { mode in Text(mode.title).tag(mode) }
                }.labelsHidden().pickerStyle(.menu).fixedSize()
            }
            Divider()
            row("Multiline input", detail: multiline ? "Return inserts a new line; ⌘Return sends." : "Return sends; ⇧Return inserts a new line.") {
                Toggle("Multiline input", isOn: $multiline).toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            Divider()
            row("While Grok is working", detail: composer.followUpBehavior.detail) {
                Picker("While Grok is working", selection: Binding(get: { composer.followUpBehavior }, set: { composer.setFollowUpBehavior($0) })) {
                    ForEach(ComposerFollowUpBehavior.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            Divider()
            row("Dictation shortcut", detail: "\(ComposerFeatureModel.voiceShortcut) starts and stops dictation.") {
                Toggle("Dictation shortcut", isOn: Binding(get: { composer.voiceShortcutEnabled }, set: { composer.setVoiceShortcutEnabled($0) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            row("Dictation language", detail: "Automatic follows your Mac's language.") {
                Picker("Dictation language", selection: Binding(get: { composer.voiceLanguage }, set: { composer.setVoiceLanguage($0) })) {
                    Text("Automatic").tag("auto")
                    Divider()
                    ForEach(VoiceSTTSettings.languages, id: \.code) { Text($0.name).tag($0.code) }
                }.labelsHidden().pickerStyle(.menu).fixedSize()
            }
        }
        .settingsCard()
    }

    private var permissionModes: [ComposerPermissionMode] {
        ComposerPermissionMode.allCases.filter { $0 != .auto || composer.autoModeAvailable || composer.permissionMode == .auto }
    }

    private func row<Control: View>(_ title: String, detail: String, warning: Bool = false, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(warning ? ComposerPalette.warning : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control()
        }
    }
}
