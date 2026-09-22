import XCTest
@testable import GrokDesktop

@MainActor
final class AppStoreTests: XCTestCase {
    @MainActor
    private final class Fixture {
        let directory: URL
        let defaultsName = "GrokDesktopTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let store: AppStore
        let conversationID: UUID

        init(firstLoad: String, existingMessages: [Message] = [], advertiseAuth: Bool = true) throws {
            guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else { throw XCTSkip("Requires /usr/bin/python3") }
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("grok-store-tests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defaults = UserDefaults(suiteName: defaultsName)!
            let executable = directory.appendingPathComponent("fixture-grok")
            let source = #"""
#!/usr/bin/python3
import json, pathlib, sys, time
root = pathlib.Path(__file__).parent
counter = root / "attempt"
attempt = int(counter.read_text()) + 1 if counter.exists() else 1
counter.write_text(str(attempt))
def emit(value):
    print(json.dumps(value), flush=True)
def reply(request, value):
    emit({"jsonrpc": "2.0", "id": request["id"], "result": value})
def chunk(kind, text):
    emit({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": "existing-session", "update": {"sessionUpdate": kind, "content": {"type": "text", "text": text}}}})
for line in sys.stdin:
    request = json.loads(line)
    with (root / "requests.jsonl").open("a") as log:
        log.write(json.dumps(request) + "\n")
    method = request.get("method")
    if method == "initialize":
        reply(request, {"authMethods": [{"id": "cached_token"}] if ADVERTISE_AUTH else []})
    elif method == "authenticate":
        reply(request, {})
    elif method == "session/load":
        if attempt == 1:
            FIRST_LOAD
        chunk("user_message_chunk", "Original question")
        chunk("agent_message_chunk", "Complete answer")
        reply(request, {})
    elif method == "session/prompt":
        chunk("agent_message_chunk", "New answer")
        reply(request, {"stopReason": "end_turn"})
"""#
                .replacingOccurrences(of: "ADVERTISE_AUTH", with: advertiseAuth ? "True" : "False")
                .replacingOccurrences(of: "FIRST_LOAD", with: firstLoad.replacingOccurrences(of: "\n", with: "\n            "))
            try source.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            store = AppStore(stateFile: directory.appendingPathComponent("state.json"), defaults: defaults)
            let project = Project(path: directory.path)
            let conversation = Conversation(projectID: project.id, sessionID: "existing-session", messages: existingMessages)
            conversationID = conversation.id
            store.state = DesktopState(projects: [project], conversations: [conversation], selectedProjectID: project.id, selectedConversationID: conversation.id)
            store.binaryPath = executable.path
        }

        var requests: [[String: Any]] {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("requests.jsonl")) else { return [] }
            return data.split(separator: 10).compactMap { (try? JSONSerialization.jsonObject(with: Data($0))) as? [String: Any] }
        }

        func cleanup() {
            store.shutdown()
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func eventually(_ predicate: () -> Bool, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(predicate(), "Condition was not reached before timeout", file: file, line: line)
    }

    func testCancelDuringReconnectCannotPromptOrCleanUpNextSend() async throws {
        let fixture = try Fixture(firstLoad: "time.sleep(20)", existingMessages: [Message(kind: .assistant, text: "Prior turn")])
        defer { fixture.cleanup() }
        let store = fixture.store
        store.draft = "Cancelled prompt"
        store.send()
        try await eventually { fixture.requests.contains { $0["method"] as? String == "session/load" } }
        store.cancel()
        XCTAssertFalse(store.run.isRunning)
        XCTAssertEqual(store.run.phase, "Stopped")
        // Restart immediately, before the cancelled continuation has had a chance to unwind.
        store.draft = "Next prompt"
        store.send()
        try await eventually { !store.run.isRunning }
        XCTAssertEqual(store.run.phase, "Ready")
        XCTAssertFalse(store.conversation!.messages.contains { $0.kind == .system })
        let prompts = fixture.requests.filter { $0["method"] as? String == "session/prompt" }
        XCTAssertEqual(prompts.count, 1)
        let prompt = ((prompts.first?["params"] as? [String: Any])?["prompt"] as? [[String: Any]])?.first?["text"] as? String
        XCTAssertEqual(prompt, "Next prompt")
        for authentication in fixture.requests.filter({ $0["method"] as? String == "authenticate" }) {
            XCTAssertEqual(((authentication["params"] as? [String: Any])?["_meta"] as? [String: Any])?["headless"] as? Bool, true)
        }
    }

    func testFailedImportDiscardsPartialReplayAndCanReloadWithoutDuplicates() async throws {
        let fixture = try Fixture(firstLoad: #"""
chunk("user_message_chunk", "Partial question")
chunk("agent_message_chunk", "Partial answer")
emit({"jsonrpc": "2.0", "id": request["id"], "error": {"code": -32603, "message": "Fixture load failed"}})
continue
"""#)
        defer { fixture.cleanup() }
        let store = fixture.store
        await store.loadImportedConversation()
        XCTAssertTrue(store.conversation!.messages.isEmpty)
        XCTAssertEqual(store.run.phase, "Needs attention")
        XCTAssertFalse(store.run.isRunning)
        XCTAssertEqual(store.banner, "Fixture load failed")
        await store.loadImportedConversation()
        XCTAssertEqual(store.conversation!.messages.map(\.text), ["Original question", "Complete answer"])
        XCTAssertEqual(store.run.phase, "Ready")
        XCTAssertNil(store.banner)
        XCTAssertEqual(fixture.requests.filter { $0["method"] as? String == "session/load" }.count, 2)
    }

    func testCancellingImportClearsPendingApprovalAndAllowsRetry() async throws {
        let fixture = try Fixture(firstLoad: #"""
chunk("agent_message_chunk", "Partial answer")
emit({"jsonrpc": "2.0", "id": "trust-1", "method": "x.ai/folder_trust/request", "params": {"cwd": str(root), "configKinds": ["agents"]}})
time.sleep(20)
"""#)
        defer { fixture.cleanup() }
        let store = fixture.store
        let importing = Task { await store.loadImportedConversation() }
        try await eventually { !store.run.approvals.isEmpty }
        store.cancel()
        await importing.value
        XCTAssertEqual(store.run.phase, "Stopped")
        XCTAssertFalse(store.run.isRunning)
        XCTAssertTrue(store.run.approvals.isEmpty)
        XCTAssertTrue(store.run.questions.isEmpty)
        XCTAssertTrue(store.conversation!.messages.isEmpty)
        XCTAssertNil(store.banner)
        await store.loadImportedConversation()
        XCTAssertEqual(store.conversation!.messages.map(\.text), ["Original question", "Complete answer"])
    }

    func testUnavailableAuthenticationExplainsHowToRecover() async throws {
        let fixture = try Fixture(firstLoad: "pass", advertiseAuth: false)
        defer { fixture.cleanup() }
        let store = fixture.store
        await store.loadImportedConversation()
        XCTAssertEqual(store.run.phase, "Needs attention")
        XCTAssertTrue(store.banner?.contains("Open Settings and sign in") == true)
        XCTAssertFalse(fixture.requests.contains { $0["method"] as? String == "session/load" })
    }

    func testTaskDraftsSurviveRepeatedClicksAndTaskSwitching() async throws {
        let fixture = try Fixture(firstLoad: "pass")
        defer { fixture.cleanup() }
        let store = fixture.store
        let first = store.conversation!
        let second = Conversation(projectID: first.projectID, title: "Second task")
        store.state.conversations.append(second)
        store.draft = "First task draft"
        store.selectConversation(first)
        XCTAssertEqual(store.draft, "First task draft")
        store.selectConversation(second)
        XCTAssertEqual(store.draft, "")
        store.draft = "Second task draft"
        store.selectConversation(first)
        XCTAssertEqual(store.draft, "First task draft")
        store.selectConversation(second)
        XCTAssertEqual(store.draft, "Second task draft")
    }

    func testNewTaskDraftsArePerProjectAndSendingClearsOriginalDraft() async throws {
        let fixture = try Fixture(firstLoad: "pass")
        defer { fixture.cleanup() }
        let store = fixture.store
        let firstProject = store.project!
        let secondProject = Project(path: fixture.directory.appendingPathComponent("second-project").path)
        store.state.projects.append(secondProject)
        store.newTask()
        store.draft = "First project idea"
        store.newTask()
        XCTAssertEqual(store.draft, "First project idea")
        store.selectProject(secondProject.id)
        XCTAssertEqual(store.draft, "")
        store.draft = "Second project idea"
        store.selectProject(firstProject.id)
        XCTAssertEqual(store.draft, "First project idea")
        store.send()
        store.cancel()
        XCTAssertEqual(store.draft, "")
        store.newTask()
        XCTAssertEqual(store.draft, "", "Sending must clear the source new-task draft")
        store.selectProject(secondProject.id)
        XCTAssertEqual(store.draft, "Second project idea")
    }

    func testCrossProjectTaskSelectionImmediatelyClearsOldInspector() async throws {
        let fixture = try Fixture(firstLoad: "pass")
        defer { fixture.cleanup() }
        let store = fixture.store
        let secondProject = Project(path: fixture.directory.appendingPathComponent("second-project").path)
        let second = Conversation(projectID: secondProject.id)
        store.state.projects.append(secondProject)
        store.state.conversations.append(second)
        store.workspace = GitWorkspaceSnapshot(branch: "previous-branch", changes: [])
        store.selectedFile = "previous-file.swift"
        store.diffText = "Previous project changes"
        store.selectConversation(second)
        XCTAssertEqual(store.workspace.branch, "")
        XCTAssertNil(store.selectedFile)
        XCTAssertEqual(store.diffText, "")
    }

    func testReconnectRestoresHarnessTranscriptAndPreservesUnsentPrompt() async throws {
        let fixture = try Fixture(firstLoad: "pass", existingMessages: [Message(kind: .assistant, text: "Interrupted local output")])
        defer { fixture.cleanup() }
        let store = fixture.store
        store.draft = "Follow up"
        store.send()
        try await eventually { !store.run.isRunning }
        XCTAssertEqual(store.run.phase, "Ready")
        XCTAssertEqual(store.conversation!.messages.map(\.text), ["Original question", "Complete answer", "Follow up", "New answer"])
        XCTAssertEqual(fixture.requests.filter { $0["method"] as? String == "session/prompt" }.count, 1)
    }
}
