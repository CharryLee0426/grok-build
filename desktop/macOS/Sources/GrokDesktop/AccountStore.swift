import Foundation
import Combine

enum AccountProvider: String, CaseIterable, Identifiable {
    case xai, openrouter
    case codex = "openai-codex"

    var id: String { rawValue }
    var name: String {
        switch self {
        case .xai: return "xAI"
        case .openrouter: return "OpenRouter"
        case .codex: return "OpenAI Codex"
        }
    }
}

/// Presentation-only metadata. Credential values never leave the reader.
struct AccountStatus: Equatable {
    enum State: Equatable { case signedOut, connected, expired, unreadable }
    var state: State = .signedOut
    var identity: String?
    var detail: String = "Sign in with your browser"
    var isConnected: Bool { state == .connected }
}

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [AccountProvider: AccountStatus] = [:]
    private let reader: AccountStatusReader

    init(reader: AccountStatusReader = AccountStatusReader()) {
        self.reader = reader
        refresh()
    }

    func status(for provider: AccountProvider) -> AccountStatus { accounts[provider] ?? AccountStatus() }

    func refresh() { accounts = reader.read() }

    /// Recheck the shared CLI credentials at the action boundary as they may have
    /// changed since this view last rendered (for example, a CLI browser sign-in).
    @discardableResult
    func signIn(provider: AccountProvider, loginRunning: Bool, perform: (String) -> Void) -> Bool {
        refresh()
        guard !loginRunning, !status(for: provider).isConnected else { return false }
        perform(provider.rawValue)
        return true
    }
}

struct AccountStatusReader {
    private let home: URL
    private let environment: [String: String]
    private let now: () -> Date

    init(home: URL? = nil, environment: [String: String] = ProcessInfo.processInfo.environment, now: @escaping () -> Date = Date.init) {
        self.environment = environment
        self.home = home ?? environment["GROK_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok", isDirectory: true)
        self.now = now
    }

    func read() -> [AccountProvider: AccountStatus] {
        [.xai: readXAI(), .openrouter: readProvider(.openrouter), .codex: readProvider(.codex)]
    }

    private func readProvider(_ provider: AccountProvider) -> AccountStatus {
        if provider == .openrouter, validSecret(environment["OPENROUTER_API_KEY"]) {
            return AccountStatus(state: .connected, detail: "API key from environment · account name unavailable")
        }
        let url = home.appendingPathComponent("provider-auth/\(provider.rawValue).json")
        do {
            guard let data = try readData(url) else { return AccountStatus() }
            let credential = try JSONDecoder().decode(ProviderCredential.self, from: data)
            guard credential.provider == provider.rawValue, validSecret(credential.access_token) else { return unreadable() }
            if provider == .openrouter {
                return AccountStatus(state: .connected, detail: "API key connected · account name unavailable")
            }
            // Mirror the harness's required Codex OAuth fields. A refresh token
            // means an expired access token can be renewed without signing in again.
            guard validSecret(credential.refresh_token), let accountID = displayText(credential.account_id),
                  let expiry = credential.expires_at, expiry.isFinite, expiry > 0 else { return unreadable() }
            let identity = profileEmail(from: credential.access_token) ?? "Account \(accountID)"
            return AccountStatus(state: .connected, identity: identity,
                                 detail: expiry <= now().timeIntervalSince1970 ? "Signed in · session renews automatically" : "Signed in")
        } catch { return unreadable() }
    }

    private func readXAI() -> AccountStatus {
        let url = environment["GROK_AUTH_PATH"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent("auth.json")
        do {
            let entries: [String: XAICredential]
            if let data = try readData(url) {
                entries = try JSONDecoder().decode([String: XAICredential].self, from: data)
            } else { entries = [:] }
            let apiKeyStatus = xaiAPIKeyStatus(entries: entries)
            // Prefer the active first-party OAuth scope over historical logins.
            let issuer = environment["GROK_LOCAL_AUTH"].map { !$0.isEmpty && $0 != "0" } == true
                ? "http://localhost:22255" : "https://auth.x.ai"
            let defaultScope = "\(issuer)::b1a00492-073a-47ea-816f-4c329264a828"
            let credential = entries[defaultScope] ?? entries["https://accounts.x.ai/sign-in"]
            if let credential, validSecret(credential.key) {
                guard ["oidc", "external", "web_login", "grok", "api_key"].contains(credential.auth_mode),
                      let created = parseDate(credential.create_time) else { return apiKeyStatus ?? unreadable() }
                if let expiration = credential.expires_at, parseDate(expiration) == nil { return apiKeyStatus ?? unreadable() }
                let identity = displayText(credential.email)
                    ?? displayText([credential.first_name, credential.last_name].compactMap { $0 }.joined(separator: " "))
                    ?? displayText(credential.user_id).map { "Account \($0)" }
                let expiry = parseDate(credential.expires_at)
                    ?? created.addingTimeInterval(30 * 24 * 60 * 60)
                let canRefresh = validSecret(credential.refresh_token)
                    && ["oidc", "external"].contains(credential.auth_mode)
                    && displayText(credential.oidc_issuer) != nil && displayText(credential.oidc_client_id) != nil
                if expiry <= now() && !canRefresh {
                    return apiKeyStatus ?? AccountStatus(state: .expired, identity: identity, detail: "Session expired · sign in to reconnect")
                }
                return AccountStatus(state: .connected, identity: identity,
                                     detail: expiry <= now() ? "Signed in · session renews automatically"
                                        : (identity == nil ? "Signed in · account name unavailable" : "Signed in"))
            }
            return apiKeyStatus ?? AccountStatus()
        } catch { return xaiAPIKeyStatus(entries: [:]) ?? unreadable() }
    }

    private func xaiAPIKeyStatus(entries: [String: XAICredential]) -> AccountStatus? {
        let disabled = environment["GROK_DISABLE_API_KEY_AUTH"].map { !["", "0", "false", "off", "no"].contains($0.lowercased()) } ?? false
        guard !disabled, displayText(environment["GROK_FORCE_LOGIN_TEAM_ID"]) == nil else { return nil }
        if validSecret(environment["XAI_API_KEY"]) || validSecret(environment["GROK_CODE_XAI_API_KEY"]) {
            return AccountStatus(state: .connected, detail: "API key from environment · account name unavailable")
        }
        if let apiKey = entries["xai::api_key"], validSecret(apiKey.key) {
            return AccountStatus(state: .connected, detail: "API key connected · account name unavailable")
        }
        return nil
    }

    private func unreadable() -> AccountStatus {
        AccountStatus(state: .unreadable, detail: "Saved sign-in is incomplete · sign in to reconnect")
    }

    private func readData(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: 1_048_577) ?? Data()
        guard data.count <= 1_048_576 else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }

    private func validSecret(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.rangeOfCharacter(from: .controlCharacters) == nil
    }

    private func displayText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 320, trimmed.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        return trimmed
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    /// Decode only a display email. JWT claims are not used to establish trust or
    /// select credentials; the harness performs actual authentication.
    private func profileEmail(from token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let profile = object["https://api.openai.com/profile"] as? [String: Any]
        return displayText(profile?["email"] as? String) ?? displayText(object["email"] as? String)
    }

    private struct ProviderCredential: Decodable {
        var provider: String
        var access_token: String
        var refresh_token: String?
        var expires_at: Double?
        var account_id: String?
    }

    private struct XAICredential: Decodable {
        var key: String
        var auth_mode: String
        var create_time: String
        var user_id: String
        var email: String?
        var first_name: String?
        var last_name: String?
        var refresh_token: String?
        var expires_at: String?
        var oidc_issuer: String?
        var oidc_client_id: String?
    }
}
