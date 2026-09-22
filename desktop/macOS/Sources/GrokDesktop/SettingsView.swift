import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                GrokMark(size: 28)
                Text("Make yourself at home").font(.system(size: 20, weight: .medium, design: .serif))
                Spacer()
                IconButton(icon: "xmark", help: "Close settings") { dismiss() }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Appearance").font(.system(size: 12, weight: .semibold))
                Picker("Appearance", selection: $appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }.pickerStyle(.segmented).labelsHidden()
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("Grok harness").font(.system(size: 12, weight: .semibold)); Spacer(); Text("agent stdio · ACP v1").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted) }
                Text("Connect the Grok binary built from this repository, or an installed Grok CLI.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                HStack {
                    TextField("/path/to/grok", text: $store.binaryPath).textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
                    Button("Browse…") { store.chooseBinary() }.buttonStyle(SubtleButtonStyle())
                }
                HStack(spacing: 5) {
                    let valid = FileManager.default.isExecutableFile(atPath: store.binaryPath)
                    Image(systemName: valid ? "checkmark.circle" : "info.circle")
                    Text(valid ? "Executable found. Changes apply to new connections." : "Build the CLI first, then choose target/release/xai-grok-pager.")
                }.font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Accounts").font(.system(size: 12, weight: .semibold))
                Text("Uses the same accounts, models, MCP servers, and configuration as your CLI. Sign in through your browser to connect a provider.").font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(3)
                HStack(spacing: 8) {
                    Button("xAI") { store.login(provider: "xai") }.disabled(store.loginRunning)
                    Button("OpenRouter") { store.login(provider: "openrouter") }.disabled(store.loginRunning)
                    Button("OpenAI Codex") { store.login(provider: "openai-codex") }.disabled(store.loginRunning)
                    Spacer()
                    if store.loginRunning { ProgressView().controlSize(.small); Button("Cancel") { store.cancelLogin() } }
                }.buttonStyle(SubtleButtonStyle()).font(.system(size: 11))
                if !store.loginLog.isEmpty {
                    ScrollView { Text(store.loginLog).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 90).padding(10).background(Theme.sidebar).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            Divider()
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "internaldrive")
                Text("Tasks stay on this Mac. The harness manages execution, sandboxing, and credentials; approval requests appear in your conversation.").lineSpacing(3)
            }.font(.system(size: 11)).foregroundStyle(Theme.muted)
            HStack { Text("Grok Desktop · 0.1.0").font(.system(size: 10)).foregroundStyle(Theme.muted); Spacer(); Button("Done") { dismiss() }.buttonStyle(SubtleButtonStyle()).keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width: 580).foregroundStyle(Theme.ink).background(Theme.canvas)
    }
}
