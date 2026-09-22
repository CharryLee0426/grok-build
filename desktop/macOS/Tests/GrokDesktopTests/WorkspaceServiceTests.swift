import Foundation
import XCTest
@testable import GrokDesktop

final class WorkspaceServiceTests: XCTestCase {
    private var directory: URL!
    private let service = WorkspaceService()

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("grok-workspace-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try git(["init", "-b", "fixture"])
        try git(["config", "user.email", "fixture@example.invalid"])
        try git(["config", "user.name", "Fixture"])
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testUnbornBranchAndUntrackedTextBinaryAndSymlink() async throws {
        try write("first\nsecond", to: "new file.txt")
        try Data([0, 1, 2]).write(to: directory.appendingPathComponent("binary.dat"))
        try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent("link").path, withDestinationPath: "/etc/hosts")
        let snapshot = await service.inspect(path: directory.path)
        XCTAssertNil(snapshot.error)
        XCTAssertEqual(snapshot.branch, "fixture")
        XCTAssertEqual(snapshot.changes.first { $0.path == "new file.txt" }?.additions, 2)
        XCTAssertEqual(snapshot.changes.first { $0.path == "binary.dat" }?.isBinary, true)
        XCTAssertEqual(snapshot.changes.first { $0.path == "link" }?.additions, 1)
        let linkDiff = await service.diff(path: directory.path, file: "link")
        XCTAssertEqual(linkDiff, "New symbolic link\n\n+/etc/hosts")
    }

    func testStagedAndUnstagedChangesRemainVisibleFromSubdirectory() async throws {
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try write("original\n", to: "nested/sample.txt")
        try git(["add", "."])
        try git(["commit", "-m", "fixture"])
        try write("original\nstaged\n", to: "nested/sample.txt")
        try git(["add", "."])
        try write("original\nstaged\nunstaged\n", to: "nested/sample.txt")
        let nested = directory.appendingPathComponent("nested").path
        let snapshot = await service.inspect(path: nested)
        XCTAssertEqual(snapshot.changes.count, 1)
        XCTAssertEqual(snapshot.changes.first?.status, "MM")
        XCTAssertEqual(snapshot.changes.first?.additions, 2)
        let diff = await service.diff(path: nested, file: "nested/sample.txt")
        XCTAssertTrue(diff.contains("Staged changes"))
        XCTAssertTrue(diff.contains("Working tree changes"))
        XCTAssertTrue(diff.contains("+staged"))
        XCTAssertTrue(diff.contains("+unstaged"))
    }

    func testRenameAndLiteralPathspecNames() async throws {
        try write("original\n", to: "before.txt")
        try git(["add", "."])
        try git(["commit", "-m", "fixture"])
        try git(["mv", "before.txt", "after\nname.txt"])
        try write("literal only\n", to: "[ab].txt")
        try write("other file\n", to: "a.txt")
        let snapshot = await service.inspect(path: directory.path)
        XCTAssertEqual(snapshot.changes.count, 3)
        XCTAssertTrue(snapshot.changes.contains { $0.path == "after\nname.txt" && $0.status == "R " })
        let diff = await service.diff(path: directory.path, file: "[ab].txt")
        XCTAssertTrue(diff.contains("+literal only"))
        XCTAssertFalse(diff.contains("other file"))
        let traversal = await service.diff(path: directory.path, file: "../outside.txt")
        XCTAssertEqual(traversal, "The selected file is outside the workspace.")
    }

    func testInvalidWorkspaceIsReported() async throws {
        let snapshot = await service.inspect(path: directory.appendingPathComponent("missing").path)
        XCTAssertNotNil(snapshot.error)
        XCTAssertTrue(snapshot.changes.isEmpty)
    }

    private func write(_ value: String, to file: String) throws {
        try Data(value.utf8).write(to: directory.appendingPathComponent(file))
    }

    private func git(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments)")
    }
}
