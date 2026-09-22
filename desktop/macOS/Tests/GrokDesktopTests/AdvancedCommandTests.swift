import Foundation
import XCTest
@testable import GrokDesktop

final class AdvancedCommandTests: XCTestCase {
    private var home: URL!
    private let sessionID = "64382932-0bf2-4a25-b197-4bb3f8fddf6c"

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("grok-advanced-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }

    func testSavedPlanUsesEncodedWorkspaceAndCurrentSessionOnly() throws {
        let directory = home.appendingPathComponent("sessions/%2FUsers%2Ffixture%2Fproject%20with%20spaces/\(sessionID)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "# Saved plan\n\nInspect then implement.".write(to: directory.appendingPathComponent("plan.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try SavedPlanArtifact.read(home: home.path, cwd: "/Users/fixture/project with spaces", sessionID: sessionID), "# Saved plan\n\nInspect then implement.")
        XCTAssertNil(try SavedPlanArtifact.read(home: home.path, cwd: "/Users/fixture/other", sessionID: sessionID))
        XCTAssertNil(try SavedPlanArtifact.read(home: home.path, cwd: "/Users/fixture/project with spaces", sessionID: UUID().uuidString))
    }

    func testLongWorkspaceUsesExactCwdSidecar() throws {
        let cwd = "/Users/fixture/" + String(repeating: "long-project/", count: 24)
        let directory = home.appendingPathComponent("sessions/project-abc123")
        let session = directory.appendingPathComponent(sessionID)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try cwd.write(to: directory.appendingPathComponent(".cwd"), atomically: true, encoding: .utf8)
        try "Long path plan".write(to: session.appendingPathComponent("plan.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try SavedPlanArtifact.read(home: home.path, cwd: cwd, sessionID: sessionID), "Long path plan")
        XCTAssertNil(try SavedPlanArtifact.read(home: home.path, cwd: cwd + "different", sessionID: sessionID))
    }

    func testSavedPlanRejectsTraversalAndOversizeInsteadOfShowingPartialPlan() throws {
        XCTAssertThrowsError(try SavedPlanArtifact.read(home: home.path, cwd: "/project", sessionID: "../other"))
        let directory = home.appendingPathComponent("sessions/%2Fproject/\(sessionID)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 65, count: SavedPlanArtifact.maximumBytes + 1).write(to: directory.appendingPathComponent("plan.md"))
        XCTAssertThrowsError(try SavedPlanArtifact.read(home: home.path, cwd: "/project", sessionID: sessionID))
        try " \n ".write(to: directory.appendingPathComponent("plan.md"), atomically: true, encoding: .utf8)
        XCTAssertNil(try SavedPlanArtifact.read(home: home.path, cwd: "/project", sessionID: sessionID))
    }

    func testUsageRespectsTicksAndNeverClaimsIncompleteCostIsComplete() {
        let complete = AdvancedCommandFormatting.usage(["inputTokens": 450, "outputTokens": 60, "costUsdTicks": 12_345_670_000])
        XCTAssertTrue(complete.contains("Input tokens: 450"))
        XCTAssertTrue(complete.contains("Cost: $1.234567"))
        for flag in ["costIsPartial", "usageIsIncomplete"] {
            let incomplete = AdvancedCommandFormatting.usage([flag: true, "costUsdTicks": 12_345_670_000])
            XCTAssertTrue(incomplete.contains("Cost: incomplete"))
            XCTAssertFalse(incomplete.contains("$1.234567"))
        }
        XCTAssertTrue(AdvancedCommandFormatting.usage([:]).contains("Cost: unavailable"))
    }

    func testRewindPreviewAcceptsDryRunAndRejectsCommittedOrMismatchedResponses() throws {
        let point = RewindCheckpoint(promptIndex: 3, createdAt: "", snapshotCount: 1, hasFileChanges: true, prompt: "Edit")
        let raw: [String: Any] = ["success": false, "target_prompt_index": 3, "mode": "all", "clean_files": ["source.swift"], "conflicts": [[String: Any]]()]
        let preview = try RewindPreview.parse(raw, point: point, mode: .all)
        XCTAssertTrue(preview.matches(point, mode: .all))
        XCTAssertFalse(preview.matches(point, mode: .filesOnly))
        XCTAssertEqual(preview.cleanFiles, ["source.swift"])
        XCTAssertTrue(preview.conflicts.isEmpty)
        for change: [String: Any] in [["success": true], ["target_prompt_index": 2], ["mode": "files_only"], ["error": "Session is busy"]] {
            XCTAssertThrowsError(try RewindPreview.parse(raw.merging(change) { _, new in new }, point: point, mode: .all))
        }
    }

    func testRewindPreviewPreservesExternalConflictsAndCheckpointIdentity() throws {
        let points = try RewindCheckpoint.parse(["rewind_points": [
            ["prompt_index": 2, "has_file_changes": true, "num_file_snapshots": 1, "prompt_preview": "Edit"],
            ["prompt_index": 0, "prompt_preview": "Inspect"],
            ["prompt_index": 2, "prompt_preview": "Duplicate"],
            ["prompt_index": -1, "prompt_preview": "Invalid"]
        ]])
        XCTAssertEqual(points.map(\.promptIndex), [2, 0])
        XCTAssertFalse(points[1].hasFileChanges)
        let preview = try RewindPreview.parse([
            "success": false, "target_prompt_index": 2, "mode": "all", "clean_files": [String](),
            "conflicts": [["path": "source.swift", "conflict_type": "modified_externally"]],
            "error": "External modifications detected. Confirm to revert anyway."
        ], point: points[0], mode: .all)
        XCTAssertEqual(preview.conflicts, ["source.swift · modified externally"])
        XCTAssertTrue(preview.summary.contains("restore is unavailable"))
        XCTAssertFalse(preview.summary.contains("preview is ready"))
    }
}
