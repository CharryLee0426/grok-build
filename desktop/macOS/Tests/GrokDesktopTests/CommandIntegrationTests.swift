import XCTest
@testable import GrokDesktop

/// Process-backed coverage of the same command transport used by the desktop UI.
@MainActor
final class CommandIntegrationTests: XCTestCase {
    @MainActor
    private final class Fixture {
        let directory: URL
        let defaultsName = "GrokDesktopCommands.\(UUID().uuidString)"
        let defaults: UserDefaults
        let store: AppStore

        init(failingExtension: String = "", mediaTools: Bool = true, rewindConflicts: Bool = false) throws {
            guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else { throw XCTSkip("Requires /usr/bin/python3") }
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("grok-command-tests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defaults = UserDefaults(suiteName: defaultsName)!
            let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Fixtures/mock-grok.py")
            let original = try String(contentsOf: fixtureURL, encoding: .utf8)
            let source = original.components(separatedBy: "if __name__ == \"__main__\":")[0]
                .replacingOccurrences(of: "#!/usr/bin/env python3", with: "#!/usr/bin/python3")
            let recording = #"""
class RecordingHarness(MockHarness):
    def handle(self, message):
        with open(os.path.join(os.path.dirname(__file__), "requests.jsonl"), "a") as log:
            log.write(json.dumps(message) + "\n")
        if message.get("method") == FAILING_EXTENSION:
            self.result(message["id"], {"result": None, "error": {"code": "fixture_error", "message": "Fixture extension unavailable"}})
            return
        super().handle(message)
fixture = RecordingHarness()
fixture.advertised_tools = ADVERTISED_TOOLS
fixture.rewind_conflicts = REWIND_CONFLICTS
fixture.run()
"""#.replacingOccurrences(of: "FAILING_EXTENSION", with: String(decoding: try JSONSerialization.data(withJSONObject: failingExtension, options: [.fragmentsAllowed, .withoutEscapingSlashes]), as: UTF8.self))
                .replacingOccurrences(of: "ADVERTISED_TOOLS", with: mediaTools ? #"["read_fixture", "image_gen", "image_to_video"]"# : #"["read_fixture"]"#)
                .replacingOccurrences(of: "REWIND_CONFLICTS", with: rewindConflicts ? #"[{"path": "fixture.txt", "conflict_type": "modified_externally"}]"# : "[]")
            let executable = directory.appendingPathComponent("fixture-grok")
            try (source + recording).write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            store = AppStore(stateFile: directory.appendingPathComponent("state.json"), defaults: defaults, binaryPath: executable.path)
            let project = Project(path: directory.path)
            store.state = DesktopState(projects: [project], selectedProjectID: project.id)
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

    func testCommandCatalogLoadsBeforeSessionAndNativeCommandsStayLocal() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        await store.refreshCommands()
        XCTAssertTrue(store.availableCommands.contains { $0.name == "fixture-review" && $0.isSkill })
        XCTAssertTrue(store.availableCommands.contains { $0.name == "goal" })
        XCTAssertTrue(store.availableCommands.contains { $0.name == "plan" })
        XCTAssertNil(store.conversation)
        XCTAssertTrue(fixture.params(for: "session/new").isEmpty)
        store.draft = "/skills"
        store.send()
        XCTAssertEqual(store.featurePanel, .skills)
        XCTAssertTrue(fixture.prompts.isEmpty)
        XCTAssertNil(store.conversation)
        store.executeCommand(name: "help")
        XCTAssertTrue(store.showCommandPalette)
        XCTAssertTrue(fixture.prompts.isEmpty)
    }

    func testHarnessCommandAndSkillPreserveExactSlashArguments() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        await store.refreshCommands()
        store.executeCommand(name: "fixture-echo")
        try await eventually { fixture.prompts.count == 1 && !store.run.isRunning }
        XCTAssertEqual(fixture.prompts, ["/fixture-echo"])
        store.executeCommand(name: "fixture-review", arguments: "the new command picker")
        try await eventually { fixture.prompts.count == 2 && !store.run.isRunning }
        XCTAssertEqual(fixture.prompts.last, "/fixture-review the new command picker")
        XCTAssertTrue(store.conversation?.messages.contains { $0.text.contains("Offline fixture command: /fixture-review") } == true)
    }

    func testPaletteCommandPreservesOrdinaryDraftButConsumesStagedSlash() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try await startTask(fixture)
        let store = fixture.store
        store.draft = "Unsent follow-up"
        store.executeCommand(name: "fixture-echo")
        try await eventually { !store.run.isRunning && fixture.prompts.count == 2 }
        XCTAssertEqual(store.draft, "Unsent follow-up")
        XCTAssertEqual(fixture.prompts.last, "/fixture-echo")
        store.draft = "/fixture-echo"
        store.executeCommand(name: "fixture-echo")
        try await eventually { !store.run.isRunning && fixture.prompts.count == 3 }
        XCTAssertEqual(store.draft, "")
    }

    func testUnknownCommandDoesNotBecomePromptAndExecutionFailureRecovers() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        await store.refreshCommands()
        store.draft = "/command-that-does-not-exist something"
        store.send()
        XCTAssertTrue(fixture.prompts.isEmpty)
        XCTAssertNotNil(store.banner)
        store.executeCommand(name: "fixture-fail")
        try await eventually { fixture.prompts.count == 1 && !store.run.isRunning }
        XCTAssertTrue(store.banner?.contains("command execution failed") == true)
        store.executeCommand(name: "fixture-echo")
        try await eventually { fixture.prompts.count == 2 && !store.run.isRunning }
        XCTAssertEqual(store.run.phase, "Ready")
        XCTAssertEqual(fixture.prompts, ["/fixture-fail", "/fixture-echo"])
    }

    func testUseSkillStagesQualifiedInvocationUntilExplicitSend() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        await store.refreshCommands()
        await store.refreshFeatures(.skills)
        let row = try XCTUnwrap(store.featureRows.first { $0.payload["plugin_name"] as? String == "fixture-tools" })
        store.invokeFeature(row, panel: .skills, action: "Use", arguments: "PR #42")
        XCTAssertEqual(store.draft, "/fixture-tools:review PR #42")
        XCTAssertTrue(fixture.prompts.isEmpty)
        XCTAssertNil(store.conversation)
        store.send()
        try await eventually { fixture.prompts.count == 1 && !store.run.isRunning }
        XCTAssertEqual(fixture.prompts, ["/fixture-tools:review PR #42"])
        XCTAssertEqual(store.run.phase, "Ready")
    }

    func testMediaCommandSendsHarnessInstructionAndKeepsReadableDisplayText() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        await store.refreshCommands()
        XCTAssertTrue(store.availableCommands.contains { $0.name == "imagine" })
        store.generateMedia(kind: "image", description: "An orange kite over a lake")
        try await eventually { !store.run.isRunning && fixture.prompts.count == 1 }
        XCTAssertTrue(fixture.prompts[0].hasPrefix("Call the image_gen tool immediately"))
        XCTAssertTrue(fixture.prompts[0].hasSuffix("Prompt: An orange kite over a lake"))
        let block = try XCTUnwrap((fixture.params(for: "session/prompt").first?["prompt"] as? [[String: Any]])?.first)
        XCTAssertEqual((block["_meta"] as? [String: Any])?["displayText"] as? String, "/imagine An orange kite over a lake")
        XCTAssertEqual(store.conversation?.messages.first(where: { $0.kind == .user })?.text, "/imagine An orange kite over a lake")
        store.generateMedia(kind: "video", description: "The kite glides left")
        try await eventually { !store.run.isRunning && fixture.prompts.count == 2 }
        XCTAssertTrue(fixture.prompts[1].contains("image_to_video"))
        XCTAssertTrue(fixture.prompts[1].hasSuffix("User prompt: The kite glides left"))
    }

    func testUnavailableMediaToolsAreHiddenAndCannotPrompt() async throws {
        let fixture = try Fixture(mediaTools: false)
        defer { fixture.cleanup() }
        let store = fixture.store
        await store.refreshCommands()
        XCTAssertFalse(store.availableCommands.contains { ["imagine", "imagine-video"].contains($0.name) })
        store.generateMedia(kind: "image", description: "An orange kite")
        XCTAssertTrue(store.banner?.contains("does not provide the image_gen tool") == true)
        XCTAssertTrue(fixture.prompts.isEmpty)
        XCTAssertNil(store.conversation)
    }

    func testMCPListAndToggleUseSessionScopedRustWireFields() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try await startTask(fixture)
        let store = fixture.store
        await store.refreshFeatures(.mcps)
        let row = try XCTUnwrap(store.featureRows.first { $0.id == "fixture-files" })
        XCTAssertEqual(row.enabled, true)
        store.toggleFeature(row, panel: .mcps)
        try await eventually { fixture.params(for: "_x.ai/mcp/toggle").count == 1 && !store.featureLoading }
        let params = try XCTUnwrap(fixture.params(for: "_x.ai/mcp/toggle").first)
        XCTAssertEqual(params["session_id"] as? String, store.conversation?.sessionID)
        XCTAssertEqual(params["server_name"] as? String, "fixture-files")
        XCTAssertEqual(params["enabled"] as? Bool, false)
        XCTAssertNil(params["sessionId"])
        try await eventually { fixture.params(for: "_x.ai/mcp/list").count >= 2 && !store.featureLoading && store.featureRows.first?.enabled == false }
        XCTAssertEqual(fixture.prompts.count, 1, "Managing MCPs must not send incidental model prompts")
    }

    func testSkillToggleRefreshesLiveSlashCatalog() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try await startTask(fixture)
        let store = fixture.store
        await store.refreshFeatures(.skills)
        let row = try XCTUnwrap(store.featureRows.first { $0.id == "fixture-review" })
        XCTAssertEqual(row.title, "Fixture review")
        store.toggleFeature(row, panel: .skills)
        try await eventually { fixture.params(for: "_x.ai/skills/toggle").count == 1 && !store.featureLoading }
        try await eventually { !store.availableCommands.contains { $0.name == "fixture-review" } }
        let params = try XCTUnwrap(fixture.params(for: "_x.ai/skills/toggle").first)
        XCTAssertEqual(params["name"] as? String, "fixture-review")
        XCTAssertEqual(params["enabled"] as? Bool, false)
        XCTAssertEqual(params["cwd"] as? String, fixture.directory.path)
        XCTAssertEqual(fixture.prompts.count, 1)
    }

    func testRestartMCPDisablesThenEnablesWithoutModelPrompt() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try await startTask(fixture)
        let store = fixture.store
        await store.refreshFeatures(.mcps)
        let row = try XCTUnwrap(store.featureRows.first)
        store.invokeFeature(row, panel: .mcps, action: "Restart")
        try await eventually { fixture.params(for: "_x.ai/mcp/toggle").count == 2 && !store.featureLoading }
        XCTAssertEqual(fixture.params(for: "_x.ai/mcp/toggle").compactMap { $0["enabled"] as? Bool }, [false, true])
        try await eventually { fixture.params(for: "_x.ai/mcp/list").count >= 2 && !store.featureLoading && store.featureRows.first?.enabled == true }
        XCTAssertEqual(fixture.prompts.count, 1)
    }

    func testExtensionManagementUsesExactWireContractsWithoutPrompting() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        await store.refreshFeatures(.mcps)
        store.addMCPServer(name: "new-fixture", transport: "stdio", endpoint: "/fixture/command", arguments: "--root\n/tmp/a folder")
        try await eventually { !store.featureLoading && store.featureRows.contains { $0.id == "new-fixture" } }
        let upsert = try XCTUnwrap(fixture.params(for: "_x.ai/mcp/upsert").first)
        XCTAssertEqual(upsert["session_id"] as? String, store.conversation?.sessionID)
        XCTAssertEqual(upsert["server_name"] as? String, "new-fixture")
        XCTAssertEqual(upsert["command"] as? String, "/fixture/command")
        XCTAssertEqual(upsert["args"] as? [String], ["--root", "/tmp/a folder"])
        XCTAssertNil(upsert["config"], "The harness expects flattened MCP configuration")
        store.toggleMCPTool(server: "fixture-files", tool: "read_fixture", enabled: false)
        try await eventually { !store.featureLoading && fixture.params(for: "_x.ai/mcp/toggle_tool").count == 1 }
        let tool = try XCTUnwrap(fixture.params(for: "_x.ai/mcp/toggle_tool").first)
        XCTAssertEqual(tool["server_name"] as? String, "fixture-files")
        XCTAssertEqual(tool["tool_name"] as? String, "read_fixture")
        XCTAssertEqual(tool["enabled"] as? Bool, false)
        let server = try XCTUnwrap(store.featureRows.first { $0.id == "fixture-files" })
        XCTAssertEqual(MCPToolChoice.from(server).first?.enabled, false)
        store.removeMCPServer("new-fixture")
        try await eventually { !store.featureLoading && fixture.params(for: "_x.ai/mcp/delete").count == 1 }
        XCTAssertFalse(store.featureRows.contains { $0.id == "new-fixture" })
        XCTAssertEqual(fixture.params(for: "_x.ai/mcp/delete").first?["server_name"] as? String, "new-fixture")
        let skillPath = fixture.directory.appendingPathComponent("added-skill").path
        store.addSkillPath(skillPath)
        try await eventually { !store.featureLoading && fixture.params(for: "_x.ai/skills/add").count == 1 }
        XCTAssertEqual(fixture.params(for: "_x.ai/skills/add").first?["cwd"] as? String, fixture.directory.path)
        XCTAssertEqual(fixture.params(for: "_x.ai/skills/add").first?["path"] as? String, skillPath)
        XCTAssertTrue(store.availableCommands.contains { $0.name == "added-skill" })
        XCTAssertTrue(store.featureRows.contains { $0.id == "added-skill" })
        XCTAssertTrue(fixture.prompts.isEmpty)
    }

    func testAgentDefinitionsAndPersonasCanBeBrowsedBeforeSession() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        await store.refreshFeatures(.agentDefinitions)
        XCTAssertTrue(store.featureRows.contains { $0.id == "bundled:fixture-explorer" })
        await store.refreshFeatures(.personas)
        let row = try XCTUnwrap(store.featureRows.first { $0.id == "bundled:fixture-researcher" })
        XCTAssertEqual(row.detail, "Investigate offline fixture data")
        XCTAssertNil(store.conversation)
        XCTAssertTrue(fixture.params(for: "session/new").isEmpty)
        XCTAssertTrue(fixture.prompts.isEmpty)
    }

    func testNestedExtensionErrorAppearsInPanelWithoutPrompting() async throws {
        let fixture = try Fixture(failingExtension: "_x.ai/skills/list")
        defer { fixture.cleanup() }
        await fixture.store.refreshFeatures(.skills)
        XCTAssertEqual(fixture.store.featureError, "Fixture extension unavailable")
        XCTAssertTrue(fixture.store.featureRows.isEmpty)
        XCTAssertFalse(fixture.store.featureLoading)
        XCTAssertTrue(fixture.prompts.isEmpty)
    }

    func testInspectBundledAgentUsesSingularKindAndDisplaysSource() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        await store.refreshFeatures(.agentDefinitions)
        let row = try XCTUnwrap(store.featureRows.first { $0.id == "bundled:fixture-explorer" })
        store.invokeFeature(row, panel: .agentDefinitions, action: "Inspect")
        try await eventually { !fixture.params(for: "_x.ai/bundle/entry/get").isEmpty && !store.featureLoading }
        XCTAssertEqual(fixture.params(for: "_x.ai/bundle/entry/get").last?["kind"] as? String, "agent")
        XCTAssertTrue(store.featureRows.first(where: { $0.id == row.id })?.detail.contains("Inspect simulated data only") == true)
        XCTAssertTrue(fixture.prompts.isEmpty)
    }

    func testRecapNotificationAndRewindRestoreUseDedicatedACPRequests() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try await startTask(fixture)
        let store = fixture.store
        await store.requestRecap()
        try await eventually { !store.advancedLoading && store.advancedContent?.contains("Offline fixture recap") == true }
        XCTAssertEqual(fixture.params(for: "_x.ai/recap").last?["auto"] as? Bool, false)
        await store.loadRewindPoints()
        let point = try XCTUnwrap(store.rewindPoints.first)
        XCTAssertEqual(point.promptIndex, 0)
        XCTAssertEqual(point.prompt, "Original fixture prompt")
        XCTAssertEqual(point.snapshotCount, 1)
        await store.previewRewind(point, mode: .conversationOnly)
        XCTAssertEqual(fixture.params(for: "_x.ai/rewind/execute").first?["force"] as? Bool, false)
        XCTAssertTrue(fixture.params(for: "session/load").isEmpty, "Preview must not change or reload the conversation")
        await store.restoreRewind(point, mode: .conversationOnly)
        XCTAssertNil(store.advancedError)
        let restore = try XCTUnwrap(fixture.params(for: "_x.ai/rewind/execute").last)
        XCTAssertEqual(restore["targetPromptIndex"] as? Int, 0)
        XCTAssertEqual(restore["mode"] as? String, "conversation_only")
        XCTAssertEqual(restore["force"] as? Bool, true)
        XCTAssertEqual(fixture.params(for: "_x.ai/rewind/execute").compactMap { $0["force"] as? Bool }, [false, false, true], "Explicit restore must repeat the conflict check before committing")
        XCTAssertFalse(fixture.params(for: "session/load").isEmpty, "A restored conversation must reload authoritative history")
        XCTAssertEqual(store.draft, "Original fixture prompt")
        XCTAssertEqual(fixture.prompts.count, 1, "Recap and rewind controls must not enter the model prompt lane")
    }

    func testRewindConflictingPreviewCannotCommitOrReloadHistory() async throws {
        let fixture = try Fixture(rewindConflicts: true)
        defer { fixture.cleanup() }
        try await startTask(fixture)
        let store = fixture.store
        await store.loadRewindPoints()
        let point = try XCTUnwrap(store.rewindPoints.first)
        await store.previewRewind(point, mode: .all)
        await store.restoreRewind(point, mode: .all)
        XCTAssertNotNil(store.advancedError)
        let requests = fixture.params(for: "_x.ai/rewind/execute")
        XCTAssertFalse(requests.isEmpty)
        XCTAssertTrue(requests.allSatisfy { $0["force"] as? Bool == false })
        XCTAssertTrue(fixture.params(for: "session/load").isEmpty)
        XCTAssertEqual(fixture.prompts.count, 1)
    }

    func testPlanModeBeforeFirstTaskUsesSetModeAndApprovalRoundTrip() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        store.enterPlanMode()
        try await eventually { !fixture.params(for: "session/set_mode").isEmpty && !store.run.isConfiguring }
        XCTAssertEqual(fixture.params(for: "session/set_mode").last?["modeId"] as? String, "plan")
        XCTAssertEqual(store.run.modeID, "plan")
        XCTAssertTrue(fixture.prompts.isEmpty)
        store.draft = "fixture:plan"
        store.send()
        try await eventually { !store.run.approvals.isEmpty }
        let approval = try XCTUnwrap(store.run.approvals.first)
        let accept = try XCTUnwrap(approval.options.first { $0.id == "plan:approved" })
        XCTAssertTrue(approval.detail.contains("Offline fixture plan"))
        store.approve(approval, option: accept)
        try await eventually { !store.run.isRunning }
        XCTAssertTrue(fixture.requests.contains { ($0["result"] as? [String: Any])?["outcome"] as? String == "approved" })
        XCTAssertTrue(store.run.approvals.isEmpty)
    }

    func testGoalLifecycleComesFromLiveHarnessUpdates() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        await store.refreshCommands()
        store.createGoal(objective: "Implement desktop commands", tokenBudget: 5000)
        try await eventually { store.run.goal?.status == "active" && !store.run.isRunning }
        XCTAssertEqual(store.run.goal?.objective, "Implement desktop commands")
        XCTAssertEqual(store.run.goal?.tokenBudget, 5000)
        XCTAssertEqual(store.run.goal?.tokensUsed, 256)
        XCTAssertEqual(fixture.prompts.last, "/goal Implement desktop commands --budget 5000")
        store.goalAction("pause")
        try await eventually { store.run.goal?.status == "user_paused" && !store.run.isRunning }
        store.goalAction("resume")
        try await eventually { store.run.goal?.status == "active" && !store.run.isRunning }
        store.goalAction("clear")
        try await eventually { (store.run.goal == nil || store.run.goal?.status == "cleared") && !store.run.isRunning }
        XCTAssertEqual(fixture.prompts.suffix(3), ["/goal pause", "/goal resume", "/goal clear"])
    }

    func testPlanDescriptionChangesModeBeforeSendingOnlyDescription() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.store.enterPlanMode(description: "Plan the fixture schema")
        try await eventually { !fixture.store.run.isRunning && fixture.prompts.count == 1 }
        let methods = fixture.requests.compactMap { $0["method"] as? String }.filter { ["session/set_mode", "session/prompt"].contains($0) }
        XCTAssertEqual(methods, ["session/set_mode", "session/prompt"])
        XCTAssertEqual(fixture.prompts, ["Plan the fixture schema"])
        XCTAssertEqual(fixture.store.run.modeID, "plan")
    }

    func testActiveGoalPauseAndClearUseImmediateCancelBeforeControlPrompt() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        await store.refreshCommands()
        store.createGoal(objective: "Exercise goal controls")
        try await eventually { !store.run.isRunning && store.run.goal?.status == "active" }
        store.draft = "fixture:wait"
        store.send()
        try await eventually { fixture.prompts.count == 2 && store.run.phase == "Working" }
        store.goalAction("pause")
        try await eventually { !store.run.isRunning && store.run.goal?.status == "user_paused" }
        XCTAssertEqual(fixture.params(for: "session/cancel").count, 1)
        XCTAssertEqual(fixture.prompts.count, 2, "Pause must cancel immediately, not queue /goal pause behind the running turn")
        store.goalAction("resume")
        try await eventually { !store.run.isRunning && store.run.goal?.status == "active" }
        store.draft = "fixture:wait"
        store.send()
        try await eventually { fixture.prompts.count == 4 && store.run.phase == "Working" }
        store.goalAction("clear")
        try await eventually { !store.run.isRunning && store.run.goal?.status == "cleared" }
        XCTAssertEqual(fixture.params(for: "session/cancel").count, 2)
        XCTAssertEqual(fixture.prompts.last, "/goal clear")
        XCTAssertNil(store.featureError)
    }

    func testSubagentNotificationsUpdateCountersAndCompletion() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        store.draft = "fixture:subagents"
        store.send()
        try await eventually { store.run.subagents.first?.status == "completed" && !store.run.isRunning }
        let child = try XCTUnwrap(store.run.subagents.first)
        XCTAssertEqual(child.id, "fixture-child-1")
        XCTAssertEqual(child.title, "Inspect offline fixtures")
        XCTAssertEqual(child.agentType, "explore")
        XCTAssertEqual(child.tokensUsed, 480)
        XCTAssertEqual(child.toolCalls, 2)
        XCTAssertEqual(child.turns, 1)
        XCTAssertEqual(child.address, "fixture-child-address")
        XCTAssertTrue(child.detail.contains("inspection completed"))
        XCTAssertEqual(store.run.subagents.count, 1)
    }

    func testRunningSubagentCanBeListedAndStoppedWhileParentIsActive() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = fixture.store
        store.draft = "fixture:subagents fixture:wait"
        store.send()
        try await eventually { store.run.subagents.first?.status == "running" }
        await store.refreshFeatures(.agents)
        let row = try XCTUnwrap(store.featureRows.first)
        XCTAssertTrue(row.actions.contains("Stop"))
        XCTAssertEqual(fixture.params(for: "_x.ai/subagent/list_running").last?["sessionId"] as? String, store.conversation?.sessionID)
        store.invokeFeature(row, panel: .agents, action: "Stop")
        try await eventually { store.run.subagents.first?.status == "cancelled" && !store.featureLoading }
        XCTAssertEqual(fixture.params(for: "_x.ai/subagent/cancel").last?["subagentId"] as? String, "fixture-child-1")
        XCTAssertTrue(store.run.isRunning, "Stopping a child must leave the parent turn active")
        store.cancel()
        try await eventually { !store.run.isRunning }
    }

    func testCommandSearchRanksAliasesAndRetainsQualifiedSkillIdentity() {
        let skills = SlashCommand.parse([
            ["name": "review", "description": "Review with a workspace skill", "_meta": ["path": "/project/review/SKILL.md", "scope": "local"]],
            ["name": "acme:review", "description": "Review from a plugin", "input": ["hint": "pull request"], "_meta": ["path": "/plugins/acme/review/SKILL.md", "scope": "plugin", "pluginName": "acme"]]
        ])
        let commands = DesktopCommands.catalog + skills
        XCTAssertEqual(DesktopCommands.matches(commands, query: "m").first?.name, "model")
        XCTAssertEqual(DesktopCommands.matches(commands, query: "mcp").first?.name, "mcps")
        XCTAssertEqual(DesktopCommands.matches(commands, query: "acme:review").first?.name, "acme:review")
        XCTAssertTrue(DesktopCommands.matches(commands, query: "skls").contains { $0.name == "skills" })
        XCTAssertEqual(skills.last?.argumentHint, "pull request")
        XCTAssertEqual(skills.last?.source, "acme")
        XCTAssertTrue(skills.allSatisfy(\.isSkill))
        XCTAssertEqual(SlashCommand.split(" /acme:review  PR #42 ")?.arguments, "PR #42")
    }
}
