import Foundation
import XCTest
@testable import GrokDesktop

final class AccountStoreTests: XCTestCase {
    private var directory: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let xaiScope = "https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("grok-account-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("provider-auth"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func write(_ object: Any, to path: String) throws {
        try JSONSerialization.data(withJSONObject: object).write(to: directory.appendingPathComponent(path))
    }

    private var reader: AccountStatusReader { AccountStatusReader(home: directory, environment: [:], now: { self.now }) }

    private func xaiCredential(key: String, email: String, expiry: String) -> [String: String] {
        ["key": key, "email": email, "user_id": "user-1", "expires_at": expiry,
         "auth_mode": "oidc", "create_time": "2026-01-01T00:00:00Z"]
    }

    func testReadsXAIEmailAndCodexJWTProfileWithoutExposingTokens() throws {
        try write([xaiScope: xaiCredential(key: "secret-xai-token", email: "alice@example.invalid", expiry: "2030-01-01T00:00:00Z")], to: "auth.json")
        let claims = ["https://api.openai.com/profile": ["email": "bob@example.invalid"]]
        let payload = try JSONSerialization.data(withJSONObject: claims).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let bearer = "header.\(payload).secret-signature"
        try write(["provider": "openai-codex", "access_token": bearer, "refresh_token": "secret-refresh", "account_id": "account-1", "expires_at": now.timeIntervalSince1970 + 3600], to: "provider-auth/openai-codex.json")
        let statuses = reader.read()
        XCTAssertEqual(statuses[.xai]?.identity, "alice@example.invalid")
        XCTAssertEqual(statuses[.codex]?.identity, "bob@example.invalid")
        XCTAssertTrue(statuses[.codex]!.isConnected)
        let presentation = String(describing: statuses)
        XCTAssertFalse(presentation.contains("secret-xai-token"))
        XCTAssertFalse(presentation.contains("secret-refresh"))
        XCTAssertFalse(presentation.contains(bearer))
    }

    func testCodexFallsBackToAccountIDAndKeepsRefreshableSessionConnected() throws {
        try write(["provider": "openai-codex", "access_token": "opaque-secret", "refresh_token": "refresh-secret", "account_id": "account-42", "expires_at": now.timeIntervalSince1970 - 3600], to: "provider-auth/openai-codex.json")
        let status = reader.read()[.codex]!
        XCTAssertTrue(status.isConnected)
        XCTAssertEqual(status.identity, "Account account-42")
        XCTAssertEqual(status.detail, "Signed in · session renews automatically")
    }

    func testExpiredXAITokenWithoutRefreshAllowsSignIn() throws {
        try write([xaiScope: xaiCredential(key: "expired-secret", email: "old@example.invalid", expiry: "2020-01-01T00:00:00Z")], to: "auth.json")
        let status = reader.read()[.xai]!
        XCTAssertEqual(status.state, .expired)
        XCTAssertFalse(status.isConnected)
        XCTAssertEqual(status.identity, "old@example.invalid")
    }

    func testExpiredXAITokenFallsThroughToAPIKeyButLiveSessionKeepsIdentity() throws {
        let environment = ["XAI_API_KEY": "fallback-secret"]
        let statusReader = AccountStatusReader(home: directory, environment: environment, now: { self.now })
        try write([xaiScope: xaiCredential(key: "expired-secret", email: "old@example.invalid", expiry: "2020-01-01T00:00:00Z")], to: "auth.json")
        let expired = statusReader.read()[.xai]!
        XCTAssertTrue(expired.isConnected)
        XCTAssertNil(expired.identity)
        XCTAssertTrue(expired.detail.contains("API key from environment"))
        try write([xaiScope: xaiCredential(key: "live-secret", email: "current@example.invalid", expiry: "2030-01-01T00:00:00Z")], to: "auth.json")
        XCTAssertEqual(statusReader.read()[.xai]?.identity, "current@example.invalid")
    }

    func testMalformedAndWrongProviderCredentialsNeverBecomeConnected() throws {
        try Data("{invalid secret-value".utf8).write(to: directory.appendingPathComponent("auth.json"))
        try write(["provider": "openai-codex", "access_token": "secret-other-provider"], to: "provider-auth/openrouter.json")
        try write(["provider": "openai-codex", "access_token": "secret-incomplete", "account_id": "account-42"], to: "provider-auth/openai-codex.json")
        let statuses = reader.read()
        XCTAssertTrue(statuses.values.allSatisfy { $0.state == .unreadable && !$0.isConnected })
        XCTAssertFalse(String(describing: statuses).contains("secret"))
    }

    func testOpenRouterEnvironmentKeyTakesPrecedenceWithoutDisplayingKey() throws {
        try write(["provider": "invalid", "access_token": "bad-secret"], to: "provider-auth/openrouter.json")
        let statuses = AccountStatusReader(home: directory, environment: ["OPENROUTER_API_KEY": "environment-secret"]).read()
        XCTAssertTrue(statuses[.openrouter]!.isConnected)
        XCTAssertNil(statuses[.openrouter]?.identity)
        XCTAssertEqual(statuses[.openrouter]?.detail, "API key from environment · account name unavailable")
        XCTAssertFalse(String(describing: statuses).contains("environment-secret"))
    }

    func testHistoricalUnrelatedXAIAuthScopeDoesNotBlockCurrentLogin() throws {
        try write(["https://auth.example.invalid::another-client": xaiCredential(key: "unrelated-secret", email: "unrelated@example.invalid", expiry: "2030-01-01T00:00:00Z")], to: "auth.json")
        XCTAssertEqual(reader.read()[.xai]?.state, .signedOut)
    }

    func testXAIIncompleteOrInvalidSavedSessionDoesNotBlockLogin() throws {
        try write([xaiScope: ["key": "secret", "expires_at": "2030-01-01T00:00:00Z"]], to: "auth.json")
        XCTAssertEqual(reader.read()[.xai]?.state, .unreadable)
        var invalid = xaiCredential(key: "secret", email: "user@example.invalid", expiry: "2030-01-01T00:00:00Z")
        invalid["auth_mode"] = "unknown"
        try write([xaiScope: invalid], to: "auth.json")
        XCTAssertEqual(reader.read()[.xai]?.state, .unreadable)
        invalid["auth_mode"] = "oidc"
        invalid["expires_at"] = "invalid"
        try write([xaiScope: invalid], to: "auth.json")
        XCTAssertEqual(reader.read()[.xai]?.state, .unreadable)
    }

    @MainActor
    func testSignInGuardRefreshesSharedCredentialsBeforeStartingAndAfterRemoval() throws {
        let store = AccountStore(reader: reader)
        var calls: [String] = []
        XCTAssertFalse(store.status(for: .openrouter).isConnected)
        // A browser sign-in in another process finishes after the settings view opens.
        try write(["provider": "openrouter", "access_token": "new-secret"], to: "provider-auth/openrouter.json")
        XCTAssertFalse(store.signIn(provider: .openrouter, loginRunning: false) { calls.append($0) })
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(store.status(for: .openrouter).isConnected)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("provider-auth/openrouter.json"))
        XCTAssertFalse(store.signIn(provider: .openrouter, loginRunning: true) { calls.append($0) })
        XCTAssertTrue(store.signIn(provider: .openrouter, loginRunning: false) { calls.append($0) })
        XCTAssertEqual(calls, ["openrouter"])
        XCTAssertFalse(store.status(for: .openrouter).isConnected)
    }
}
