import XCTest
@testable import GrokDesktop

/// Process-backed coverage of usage, feedback, privacy, sign-out, and announcements against the
/// offline fixture harness, extended here with the account methods the real shell implements.
@MainActor
final class AccountIntegrationTests: XCTestCase {
    @MainActor
    private final class Fixture {
        let directory: URL
        let home: URL
        let defaultsName = "GrokDesktopAccount.\(UUID().uuidString)"
        let defaults: UserDefaults
        let store: AppStore
        var account: AccountFeatureModel { store.features.account }
        var openedURLs: [URL] = []

        init(failFeedback: Bool = false, failPrivacyAfter: Int = 99) throws {
            guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else { throw XCTSkip("Requires /usr/bin/python3") }
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("grok-account-tests-\(UUID().uuidString)", isDirectory: true)
            home = directory.appendingPathComponent("grok-home", isDirectory: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            defaults = UserDefaults(suiteName: defaultsName)!
            let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Fixtures/mock-grok.py")
            let source = try String(contentsOf: fixtureURL, encoding: .utf8).components(separatedBy: "if __name__ == \"__main__\":")[0]
                .replacingOccurrences(of: "#!/usr/bin/env python3", with: "#!/usr/bin/python3")
            let harness = #"""
class AccountHarness(MockHarness):
    privacy_calls = 0

    def handle(self, message):
        with open(os.path.join(os.path.dirname(__file__), "requests.jsonl"), "a") as log:
            log.write(json.dumps(message) + "\n")
        method = message.get("method")
        rid = message.get("id")
        params = message.get("params", {})
        if method == "initialize":
            self.result(rid, {"protocolVersion": 1, "agentInfo": {"name": "grok-desktop-fixture", "version": "1.0.0"},
                              "agentCapabilities": {"loadSession": True, "sessionCapabilities": {"list": {}}},
                              "authMethods": [{"id": "cached_token", "name": "Offline fixture"}],
                              "_meta": {"defaultAuthMethodId": "cached_token", "modelState": self.models(),
                                        "agentVersion": "9.9.9-fixture", "feedbackTraceOffer": True}})
            self.emit({"method": "_x.ai/announcements/update", "params": {"gen": 1700000000, "announcements": [
                {"id": "fixture-incident", "title": "Fixture incident", "message": "Responses may be slow.", "severity": "critical"},
                {"id": "fixture-promo", "message": "Try the fixture", "severity": "promo", "cta": {"label": "Learn more", "url": "https://x.ai/fixture"}}]}})
            return
        if method == "authenticate":
            self.authenticated = True
            self.result(rid, {"_meta": {"subscription_tier": "SuperGrok", "email": "dev@example.com",
                                        "coding_data_retention_opt_out": True, "is_zdr": False}})
            return
        if not self.authenticated or rid is None:
            super().handle(message)
            return
        if method == "_x.ai/session/info":
            self.result(rid, {"result": {"sessionId": params.get("sessionId"), "cwd": os.getcwd(), "model": "fixture-grok-build",
                                         "modelDisplayName": "Grok Build (fixture)", "showModelFingerprint": False, "turns": 1, "turnIndex": 1,
                                         "context": {"used": 30000, "total": 200000, "systemPromptTokens": 9000, "messageTokens": 18000,
                                                     "toolDefinitionsCount": 12, "toolDefinitionsTokens": 5000, "turnCount": 1,
                                                     "toolCallCount": 2, "compactionCount": 0, "usagePct": 15, "autoCompactThresholdPercent": 85,
                                                     "usageCategories": [{"label": "Skills", "tokens": 700, "detail": "2 skills"}]}}})
        elif method == "_x.ai/session/usage":
            self.result(rid, {"usage": {"inputTokens": 1200, "outputTokens": 300, "totalTokens": 1500, "cachedReadTokens": 200,
                                        "reasoningTokens": 40, "modelCalls": 2, "apiDurationMs": 2400, "costUsdTicks": 25000000, "numTurns": 1}})
        elif method == "_x.ai/billing":
            self.result(rid, {"config": {"creditUsagePercent": 37.5, "prepaidBalance": {"val": -2500},
                                         "currentPeriod": {"type": "USAGE_PERIOD_TYPE_WEEKLY", "end": "2026-10-01T09:00:00Z"}},
                              "on_demand_enabled": False, "subscription_tier": "SuperGrok Heavy"})
        elif method == "_x.ai/auto-topup-rule":
            self.result(rid, {"rule": {"enabled": True, "topupAmount": {"val": 1000}, "maxAmountPerMonth": {"val": 5000}}})
        elif method == "_x.ai/feedback":
            if FAIL_FEEDBACK:
                self.emit({"id": rid, "error": {"code": -32603, "message": "Internal error",
                                                "data": "Feedback is disabled. To enable, set GROK_FEEDBACK_ENABLED=true or [features] feedback = true in config.toml."}})
                return
            reply = {"success": True, "outcome": "submitted"}
            if params.get("draft_id") == "draft-cleanup":
                reply = {"success": True, "outcome": "submitted_cleanup_failed"}
            elif params.get("draft_id") == "draft-local":
                reply = {"success": False, "outcome": "local_only"}
            if params.get("request_trace_upload_token"):
                reply["traceUploadToken"] = "fixture-trace-token"
            self.result(rid, reply)
        elif method == "_x.ai/feedback/upload-trace":
            self.result(rid, {"result": {"uploaded": True, "objectPath": params.get("sessionId", "") + "/feedback_trace.tar.gz"}})
        elif method == "_x.ai/feedback/drafts/list":
            self.result(rid, {"drafts": [{"id": "draft-1", "title": "Loop in tests", "details": "It retried the same command",
                                          "type": "bug", "task_category": "shell", "created_at": 1700000000, "revision": 1}]})
        elif method == "_x.ai/feedback/drafts/get":
            self.result(rid, {"draft": {"id": params.get("draft_id"), "title": "Loop in tests", "details": "It retried the same command",
                                        "type": "bug", "task_category": "shell", "created_at": 1700000000, "revision": 1}})
        elif method == "_x.ai/feedback/drafts/delete":
            self.result(rid, {"deleted": True})
        elif method == "_x.ai/privacy/setCodingDataRetention":
            AccountHarness.privacy_calls += 1
            if AccountHarness.privacy_calls > FAIL_PRIVACY_AFTER:
                self.emit({"id": rid, "error": {"code": -32603, "message": "Internal error", "data": "server returned HTTP 503"}})
                return
            self.result(rid, {"codingDataRetentionOptOut": params.get("codingDataRetentionOptOut")})
        elif method == "_x.ai/auth/info":
            self.result(rid, {"email": "dev@example.com", "teamName": None, "teamRole": None, "codingDataRetentionOptOut": True})
        elif method == "_x.ai/auth/logout":
            self.result(rid, {"ok": True, "was_logged_in": True, "email": "dev@example.com", "api_key_still_set": False})
        else:
            super().handle(message)
fixture = AccountHarness()
fixture.run()
"""#.replacingOccurrences(of: "FAIL_FEEDBACK", with: failFeedback ? "True" : "False")
                .replacingOccurrences(of: "FAIL_PRIVACY_AFTER", with: String(failPrivacyAfter))
            let executable = directory.appendingPathComponent("fixture-grok")
            try (source + harness).write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            store = AppStore(stateFile: directory.appendingPathComponent("state.json"), defaults: defaults, binaryPath: executable.path)
            let project = Project(path: directory.path)
            store.state = DesktopState(projects: [project], selectedProjectID: project.id)
            let homeURL = home
            account.grokHome = { homeURL }
            account.openURL = { [weak self] in self?.openedURLs.append($0) }
            account.downloadText = { _, _ in nil }
        }

        var requests: [[String: Any]] {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("requests.jsonl")) else { return [] }
            return data.split(separator: 10).compactMap { (try? JSONSerialization.jsonObject(with: Data($0))) as? [String: Any] }
        }

        func params(for method: String) -> [[String: Any]] {
            requests.filter { $0["method"] as? String == method }.compactMap { $0["params"] as? [String: Any] }
        }

        var prompts: [String] {
            params(for: "session/prompt").map { value in
                (value["prompt"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined()
            }
        }

        func cleanup() {
            account.releaseAccountConnection()
            store.shutdown()
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(8)
        while !predicate() && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(predicate(), "Condition was not reached before timeout", file: file, line: line)
    }

    private func startTask(_ fixture: Fixture) async throws {
        fixture.store.draft = "Inspect the offline fixture"
        fixture.store.send()
        try await eventually { !fixture.store.run.isRunning && !fixture.prompts.isEmpty }
        XCTAssertEqual(fixture.store.run.phase, "Ready")
    }

    func testUsageSheetLoadsAllThreeTabsWithoutPrompting() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try await startTask(fixture)
        let store = fixture.store, account = fixture.account
        let promptsBefore = fixture.prompts.count
        store.executeCommand(name: "context")
        XCTAssertEqual(store.sheet, .usage(.context))
        account.refreshUsage()
        try await eventually {
            account.usage.context.value != nil && account.usage.sessionInfo.value != nil
                && account.usage.sessionUsage.value != nil && account.usage.billing.value != nil
        }
        XCTAssertEqual(fixture.prompts.count, promptsBefore, "/context is answered natively, never as a prompt")
        let session = try XCTUnwrap(store.conversation?.sessionID)
        XCTAssertEqual(fixture.params(for: "_x.ai/session/info").last?["sessionId"] as? String, session)
        XCTAssertEqual(fixture.params(for: "_x.ai/session/usage").last?["sessionId"] as? String, session)
        let context = try XCTUnwrap(account.usage.context.value)
        XCTAssertEqual(context.summary, "30.0k / 200k tokens (15.00%)")
        XCTAssertEqual(context.window.overhead, 3_000)
        XCTAssertEqual(account.usage.contextModel, "fixture-grok-build")
        let rows = try XCTUnwrap(account.usage.sessionInfo.value)
        XCTAssertEqual(rows.first { $0.label == "Shell version" }?.value, "9.9.9-fixture")
        XCTAssertEqual(rows.first { $0.label == "Auth method" }?.value, "OAuth")
        XCTAssertEqual(rows.first { $0.label == "Session ID" }?.value, session)
        XCTAssertEqual(rows.first { $0.label == "Model" }?.value, "Grok Build (fixture)")
        XCTAssertEqual(rows.first?.value, "Inspect the offline fixture")
        let billing = try XCTUnwrap(account.usage.billing.value)
        XCTAssertEqual(billing.balance?.displayPercent, 37)
        XCTAssertEqual(billing.balance?.creditsText, "Credits: $25.00")
        XCTAssertEqual(billing.autoTopup?.lines, ["Auto top-up: $10", "Max monthly top-up: $50"])
        XCTAssertEqual(account.usage.subscriptionTier, "SuperGrok Heavy")
        XCTAssertEqual(account.usage.sessionUsage.value?.rows.last?.value, "$0.0025")
        XCTAssertEqual(fixture.params(for: "_x.ai/billing").count, 1)
        XCTAssertEqual(fixture.params(for: "_x.ai/auto-topup-rule").count, 1)
    }

    func testUsageWithoutATaskReadsBillingWithoutCreatingOne() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let account = fixture.account
        account.refreshUsage()
        XCTAssertEqual(account.usage.context, .unavailable("No active session."))
        XCTAssertEqual(account.usage.sessionInfo, .unavailable("No active session."))
        try await eventually { account.usage.billing.value != nil }
        XCTAssertTrue(fixture.store.state.conversations.isEmpty, "reading usage never creates a task")
        XCTAssertTrue(fixture.params(for: "session/new").isEmpty)
        XCTAssertEqual(fixture.store.auxiliaryClients.count, 1, "a private connection answers account requests")
        try await eventually { account.currentAnnouncement?.identifier == "fixture-incident" }
        account.releaseAccountConnection()
        XCTAssertTrue(fixture.store.auxiliaryClients.isEmpty)
    }

    func testInlineFeedbackSendsDesktopReportImmediately() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try await startTask(fixture)
        let promptsBefore = fixture.prompts.count
        fixture.store.executeCommand(name: "feedback", arguments: "The diff view is great")
        XCTAssertEqual(fixture.store.banner, "Thanks for the feedback! The Grok Build team is on it.")
        XCTAssertNil(fixture.store.sheet)
        try await eventually { !fixture.params(for: "_x.ai/feedback").isEmpty }
        let params = try XCTUnwrap(fixture.params(for: "_x.ai/feedback").first)
        XCTAssertEqual(params["session_id"] as? String, fixture.store.conversation?.sessionID)
        XCTAssertEqual(params["client_type"] as? String, "desktop")
        XCTAssertEqual(params["feedback_text"] as? String, "The diff view is great")
        XCTAssertEqual(params["request_trace_upload_token"] as? Bool, false)
        let envelope = (params["metadata"] as? [String: Any])?["structured_feedback"] as? [String: Any]
        XCTAssertEqual(envelope?["source"] as? String, "write")
        XCTAssertEqual(fixture.prompts.count, promptsBefore, "feedback never becomes a model turn")
        fixture.store.executeCommand(name: "feedback")
        XCTAssertEqual(fixture.store.sheet, .feedback(text: ""))
    }

    func testFailedInlineFeedbackIsSavedAsADraft() async throws {
        let fixture = try Fixture(failFeedback: true)
        defer { fixture.cleanup() }
        try await startTask(fixture)
        let session = try XCTUnwrap(fixture.store.conversation?.sessionID)
        let encoded = try XCTUnwrap(fixture.directory.path.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~")))
        let sessionDirectory = fixture.home.appendingPathComponent("sessions/\(encoded)/\(session)", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        fixture.account.feedback("Streaming stalls after tool calls")
        try await eventually { fixture.store.banner?.hasPrefix("Couldn't send feedback") == true }
        XCTAssertEqual(fixture.store.banner, "Couldn't send feedback: Feedback is disabled. To enable, set GROK_FEEDBACK_ENABLED=true or [features] feedback = true in config.toml. Saved to Drafts; open `/feedback` to retry.")
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: sessionDirectory.appendingPathComponent("feedback_drafts.json"))) as? [String: Any])
        let draft = try XCTUnwrap((document["drafts"] as? [[String: Any]])?.first)
        XCTAssertEqual(draft["title"] as? String, "Streaming stalls after tool calls")
        XCTAssertEqual(draft["details"] as? String, "Streaming stalls after tool calls")
    }

    func testFeedbackFormAttachesTheTraceOnlyWithConsent() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try await startTask(fixture)
        let account = fixture.account
        XCTAssertFalse(account.feedbackTraceOffered, "the account is opted out of coding-data sharing")
        account.setCodingDataSharing(optedIn: true)
        try await eventually { account.privacy.optOut == false && !account.privacy.pending }
        XCTAssertEqual(fixture.params(for: "_x.ai/privacy/setCodingDataRetention").last?["codingDataRetentionOptOut"] as? Bool, false)
        XCTAssertTrue(account.feedbackTraceOffered)
        let result = await account.submitFeedback(FeedbackComposition(text: "It deleted a file", taxonomy: FeedbackTaxonomySelection(type: .bug, taskCategory: .codeEdit, failureMode: .destructive),
                                                                      traceChoice: .sendThisSession))
        XCTAssertEqual(result, .sent)
        XCTAssertEqual(fixture.store.banner, FeedbackCopy.thanks)
        let sent = try XCTUnwrap(fixture.params(for: "_x.ai/feedback").last)
        XCTAssertEqual(sent["request_trace_upload_token"] as? Bool, true)
        let envelope = (sent["metadata"] as? [String: Any])?["structured_feedback"] as? [String: Any]
        XCTAssertEqual(envelope?["failure_mode"] as? String, "destructive")
        try await eventually { !fixture.params(for: "_x.ai/feedback/upload-trace").isEmpty }
        let upload = try XCTUnwrap(fixture.params(for: "_x.ai/feedback/upload-trace").first)
        XCTAssertEqual(upload["traceUploadToken"] as? String, "fixture-trace-token")
        XCTAssertEqual(upload["intent"] as? String, "send_this_session")
        XCTAssertEqual(upload["sessionId"] as? String, fixture.store.conversation?.sessionID)
        // "Don't ask again" is remembered in config.toml, shared with the terminal.
        let declined = await account.submitFeedback(FeedbackComposition(text: "Second report", traceChoice: .neverAsk))
        XCTAssertEqual(declined, .sent)
        try await eventually { GrokConfig(url: fixture.home.appendingPathComponent("config.toml")).bool("feedback_trace_card", in: "features") == false }
        XCTAssertFalse(account.feedbackTraceOffered)
        XCTAssertEqual(fixture.params(for: "_x.ai/feedback").last?["request_trace_upload_token"] as? Bool, false)
        XCTAssertEqual(fixture.params(for: "_x.ai/feedback/upload-trace").count, 1)
        let empty = await account.submitFeedback(FeedbackComposition(text: "   "))
        XCTAssertEqual(empty, .failed("Add feedback text or an image before sending."))
    }

    func testFeedbackDraftsListOpenSendAndDelete() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let account = fixture.account
        await account.loadFeedbackDrafts()
        XCTAssertEqual(account.feedbackDrafts, .unavailable("Feedback drafts are saved with a task. Select a task to see its drafts."))
        try await startTask(fixture)
        await account.loadFeedbackDrafts()
        guard case .loaded(let rows) = account.feedbackDrafts else { return XCTFail("drafts did not load") }
        XCTAssertEqual(rows.map(\.classification), ["Bug · Shell"])
        XCTAssertEqual(fixture.params(for: "_x.ai/feedback/drafts/list").last?["session_id"] as? String, fixture.store.conversation?.sessionID)
        let draft = try await account.loadFeedbackDraft(id: "draft-1")
        XCTAssertEqual(draft.details, "It retried the same command")
        let untyped = await account.submitFeedback(FeedbackComposition(text: draft.details, draft: FeedbackLoadedDraft(id: draft.id, title: draft.title, area: nil)))
        XCTAssertEqual(untyped, .failed("Choose a type before sending this draft."))
        let sent = await account.submitFeedback(FeedbackComposition(text: "It retried the same command 40 times",
                                                                   taxonomy: FeedbackTaxonomySelection(type: .bug, taskCategory: .shell),
                                                                   draft: FeedbackLoadedDraft(id: draft.id, title: draft.title, area: nil)))
        XCTAssertEqual(sent, .sent)
        let body = try XCTUnwrap(fixture.params(for: "_x.ai/feedback").last)
        XCTAssertEqual(body["draft_id"] as? String, "draft-1")
        XCTAssertNil(body["feedback_text"], "draft sends keep the text inside edited_body")
        XCTAssertEqual((body["edited_body"] as? [String: Any])?["details"] as? String, "It retried the same command 40 times")
        let typed = FeedbackTaxonomySelection(type: .idea)
        let cleanup = await account.submitFeedback(FeedbackComposition(text: "Sent", taxonomy: typed, draft: FeedbackLoadedDraft(id: "draft-cleanup", title: "T", area: nil)))
        XCTAssertEqual(cleanup, .settled("Feedback was sent, but the stored draft could not be deleted. Delete it manually; do not resend."))
        let local = await account.submitFeedback(FeedbackComposition(text: "Kept", taxonomy: typed, draft: FeedbackLoadedDraft(id: "draft-local", title: "T", area: nil)))
        XCTAssertEqual(local, .failed("Feedback was saved locally but was not sent. The draft was kept."), "a local-only result may be retried")
        try await account.deleteFeedbackDraft(id: "draft-1")
        XCTAssertEqual(account.feedbackDrafts, .loaded([]))
        XCTAssertEqual(fixture.params(for: "_x.ai/feedback/drafts/delete").last?["draft_id"] as? String, "draft-1")
    }

    func testPrivacyChangeRollsBackWhenTheServiceFails() async throws {
        let fixture = try Fixture(failPrivacyAfter: 0)
        defer { fixture.cleanup() }
        let account = fixture.account
        account.refreshPrivacy()
        try await eventually { account.privacy.optOut == true }
        XCTAssertFalse(fixture.params(for: "_x.ai/auth/info").isEmpty, "with nothing known, the choice is read from the account")
        account.setCodingDataSharing(optedIn: true)
        XCTAssertEqual(account.privacy.optOut, false, "applied at once")
        XCTAssertTrue(account.privacy.pending)
        try await eventually { !account.privacy.pending }
        XCTAssertEqual(account.privacy.optOut, true, "rolled back")
        XCTAssertEqual(fixture.store.banner, "✗ Couldn't update coding data sharing: server returned HTTP 503")
        XCTAssertTrue(fixture.store.state.conversations.isEmpty)
    }

    func testLogoutSignsOutAndDropsIdleConnections() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try await startTask(fixture)
        let id = try XCTUnwrap(fixture.store.state.selectedConversationID)
        XCTAssertNotNil(fixture.store.clients[id])
        fixture.store.executeCommand(name: "logout")
        try await eventually { fixture.store.banner == "Logged out (was signed in as dev@example.com)." }
        XCTAssertEqual(fixture.params(for: "_x.ai/auth/logout").count, 1)
        XCTAssertNil(fixture.store.clients[id], "the next prompt starts a fresh connection and signs in again")
        XCTAssertFalse(fixture.store.loaded.contains(id))
        XCTAssertTrue(fixture.store.harnessMeta.authenticate.isEmpty)
    }

    func testAnnouncementPushesReachTheBannerFromTaskConnections() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try await startTask(fixture)
        try await eventually { fixture.account.currentAnnouncement?.identifier == "fixture-incident" }
        fixture.store.executeCommand(name: "announcements", arguments: "hide")
        fixture.account.flushAnnouncementWrites()
        XCTAssertEqual(fixture.account.currentAnnouncement?.identifier, "fixture-promo")
        XCTAssertEqual(AnnouncementHiddenFile.read(home: fixture.home), ["fixture-incident"])
        fixture.account.openAnnouncementAction(try XCTUnwrap(fixture.account.currentAnnouncement))
        XCTAssertEqual(fixture.openedURLs.last?.absoluteString, "https://x.ai/fixture")
    }
}
