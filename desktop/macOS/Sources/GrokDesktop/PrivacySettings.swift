import SwiftUI

/// The coding-data choice lives on the account, not in `config.toml`.
struct AccountPrivacyState: Equatable {
    /// `nil` until the harness reports it.
    var optOut: Bool?
    var teamName: String?
    var teamRole: String?
    var isZDR = false
    var loading = false
    /// A change is on its way to the account service.
    var pending = false
    var error: String?

    var lock: PrivacyLock? { PrivacyLock.for(isZDR: isZDR, teamName: teamName, teamRole: teamRole) }
    var optedIn: Bool? { optOut.map { !$0 } }
}

/// Why the coding-data choice cannot be changed here.
enum PrivacyLock: Equatable {
    case zeroDataRetention, teamManaged

    /// Zero Data Retention wins; otherwise team members who are not admins cannot change it.
    static func `for`(isZDR: Bool, teamName: String?, teamRole: String?) -> PrivacyLock? {
        if isZDR { return .zeroDataRetention }
        guard let teamName, !teamName.isEmpty else { return nil }
        return teamRole?.caseInsensitiveCompare("admin") == .orderedSame ? nil : .teamManaged
    }

    var reason: String {
        switch self {
        case .zeroDataRetention: return "Your team has Zero Data Retention."
        case .teamManaged: return "Managed by your team admin."
        }
    }

    /// The terminal's notice when a change is attempted anyway.
    var blockedNotice: String {
        switch self {
        case .zeroDataRetention: return "✗ Cannot change: Zero Data Retention enabled"
        case .teamManaged: return "✗ Data sharing is controlled by your team admin"
        }
    }
}

enum PrivacyCopy {
    static let label = "Coding data, retention, and training"
    static let description = "Opt-in to provide SpaceXAI the ability to retain and train on coding data, e.g., prompts, traces, & metrics, for training and debugging purposes. We may still collect simple user metrics, e.g. how many times you use the product or a feature."
    static let termsURL = URL(string: "https://x.ai/legal/terms-of-service")
    static let privacyURL = URL(string: "https://x.ai/legal/privacy-policy")
}

/// The Opt in / Opt out control, used by `/privacy` and in Settings → Accounts.
struct PrivacyChoiceView: View {
    var compact = false
    @EnvironmentObject var account: AccountFeatureModel

    private var state: AccountPrivacyState { account.privacy }

    private var selection: Binding<Bool?> {
        Binding(get: { state.optedIn }, set: { value in if let value { account.setCodingDataSharing(optedIn: value) } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack(alignment: .top, spacing: 12) {
                if compact {
                    Image(systemName: "hand.raised").font(.system(size: 20)).foregroundStyle(Theme.muted).frame(width: 34)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(PrivacyCopy.label).font(.system(size: compact ? 14 : 15, weight: .semibold))
                        if state.pending || state.loading { ProgressView().controlSize(.mini) }
                    }
                    Text(PrivacyCopy.description).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 12) {
                Picker(PrivacyCopy.label, selection: selection) {
                    Text("Opt in").tag(Bool?.some(true))
                    Text("Opt out").tag(Bool?.some(false))
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(compact ? .regular : .large)
                .fixedSize()
                .disabled(state.lock != nil || state.optOut == nil)
                if let lock = state.lock {
                    Label(lock.reason, systemImage: "lock.fill").font(.system(size: 12)).foregroundStyle(Theme.muted)
                } else if state.optOut == nil && state.loading {
                    Text("Loading…").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.leading, compact ? 46 : 0)
            if let error = state.error {
                Text(error).font(.system(size: 12)).foregroundStyle(UsagePalette.error)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    .padding(.leading, compact ? 46 : 0)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// `/privacy`.
struct PrivacySheet: View {
    var loadsOnAppear = true
    @EnvironmentObject var account: AccountFeatureModel

    var body: some View {
        DesktopPanel(title: "Privacy", subtitle: "Choose whether SpaceXAI may keep and learn from your coding data.",
                     width: 580, onClose: close) {
            VStack(alignment: .leading, spacing: 16) {
                PrivacyChoiceView().usageCard(padding: 20)
                HStack(spacing: 16) {
                    if let terms = PrivacyCopy.termsURL { Link("Terms of Service", destination: terms) }
                    if let policy = PrivacyCopy.privacyURL { Link("Privacy Policy", destination: policy) }
                }
                .font(.system(size: 12.5)).tint(Theme.accent)
            }
            .padding(24)
        } footer: {
            Text("Stored with your xAI account and shared with the Grok CLI.").font(.system(size: 12)).foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
            Button("Done", action: close).keyboardShortcut(.defaultAction)
        }
        .onAppear { if loadsOnAppear { account.refreshPrivacy() } }
        .onDisappear { account.releaseAccountConnectionSoon() }
    }

    private func close() { account.store?.sheet = nil }
}
