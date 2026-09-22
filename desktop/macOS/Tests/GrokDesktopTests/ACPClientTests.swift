import XCTest
@testable import GrokDesktop

@MainActor
final class ACPClientTests: XCTestCase {
    private func startFixture(_ source: String) throws -> ACPClient {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else {
            throw XCTSkip("The process transport fixture requires /usr/bin/python3.")
        }
        let client = ACPClient()
        try client.start(executable: "/usr/bin/python3", cwd: NSTemporaryDirectory(), arguments: ["-u", "-c", source])
        return client
    }

    func testFragmentsNotificationsServerRequestsAndClientReplies() async throws {
        let client = try startFixture(#"""
import json, sys, time
request = json.loads(sys.stdin.readline())
messages = [
    {"jsonrpc": "2.0", "method": "session/update", "params": {"text": "hello 🦊"}},
    {"jsonrpc": "2.0", "id": "permission-1", "method": "session/request_permission", "params": {"options": []}},
]
wire = ("\n".join(json.dumps(message, ensure_ascii=False) for message in messages) + "\n").encode()
# Split in the middle of a multibyte UTF-8 character and combine multiple frames.
split = wire.index("🦊".encode()) + 2
sys.stdout.buffer.write(wire[:split]); sys.stdout.buffer.flush()
time.sleep(0.02)
sys.stdout.buffer.write(wire[split:]); sys.stdout.buffer.flush()
reply = json.loads(sys.stdin.readline())
notification = json.loads(sys.stdin.readline())
result = {"reply": reply["result"]["outcome"], "notification": notification["method"], "requestMethod": request["method"]}
print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": result}), flush=True)
sys.stdin.read()
"""#)
        defer { client.stop() }
        var streamedText = ""
        client.onNotification = { method, params in
            XCTAssertEqual(method, "session/update")
            streamedText += params["text"] as? String ?? ""
        }
        client.onRequest = { id, method, _ in
            XCTAssertEqual(method, "session/request_permission")
            XCTAssertEqual(id as? String, "permission-1")
            do {
                try client.respond(id: id, result: ["outcome": "selected"])
                try client.notify("session/cancel", params: ["sessionId": "test-session"])
            } catch { XCTFail(error.localizedDescription) }
        }
        let result = try await client.request("session/prompt", params: ["prompt": "hi"], timeout: 5)
        XCTAssertEqual(result["reply"] as? String, "selected")
        XCTAssertEqual(result["notification"] as? String, "session/cancel")
        XCTAssertEqual(result["requestMethod"] as? String, "session/prompt")
        XCTAssertEqual(streamedText, "hello 🦊")
    }

    func testExitDrainsFinalResponseAndBoundsStderr() async throws {
        let client = try startFixture(#"""
import json, sys
request = json.loads(sys.stdin.readline())
sys.stderr.write("x" * 40000 + " final diagnostic\n"); sys.stderr.flush()
print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": {"done": True}}), flush=True)
sys.exit(7)
"""#)
        defer { client.stop() }
        let disconnected = expectation(description: "Process exit reported after pipe drain")
        var exitReason = ""
        client.onDisconnect = { reason in
            exitReason = reason
            disconnected.fulfill()
        }
        let result = try await client.request("test", timeout: 5)
        XCTAssertEqual(result["done"] as? Bool, true)
        await fulfillment(of: [disconnected], timeout: 5)
        XCTAssertTrue(exitReason.contains("status 7"))
        XCTAssertTrue(exitReason.contains("final diagnostic"))
        XCTAssertLessThan(exitReason.utf8.count, 17_000)
    }

    func testProcessDeathFailsPendingRequest() async throws {
        let client = try startFixture(#"""
import sys
sys.stdin.readline()
sys.stderr.write("fixture crashed\n"); sys.stderr.flush()
sys.exit(9)
"""#)
        defer { client.stop() }
        do {
            _ = try await client.request("session/prompt", timeout: 5)
            XCTFail("A dead process must fail its pending request")
        } catch ACPClientError.disconnected(let reason) {
            XCTAssertTrue(reason.contains("status 9"))
            XCTAssertTrue(reason.contains("fixture crashed"))
        }
        XCTAssertFalse(client.isRunning)
    }

    func testTimeoutAndCancellationLeaveConnectionUsable() async throws {
        let client = try startFixture(#"""
import json, sys
for line in sys.stdin:
    request = json.loads(line)
    if request.get("method") == "ping":
        print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": {"pong": True}}), flush=True)
"""#)
        defer { client.stop() }
        do {
            _ = try await client.request("unanswered", timeout: 0.05)
            XCTFail("An unanswered request must time out")
        } catch ACPClientError.timedOut(let method) {
            XCTAssertEqual(method, "unanswered")
        }
        let pending = Task { try await client.request("cancelled", timeout: nil) }
        await Task.yield()
        pending.cancel()
        do {
            _ = try await pending.value
            XCTFail("A cancelled task must cancel its local wait")
        } catch is CancellationError { }
        let result = try await client.request("ping", timeout: 5)
        XCTAssertEqual(result["pong"] as? Bool, true)
    }

    func testRemoteErrorRetainsCodeAndData() async throws {
        let client = try startFixture(#"""
import json, sys
request = json.loads(sys.stdin.readline())
print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "error": {"code": -32000, "message": "Sign in required", "data": {"auth": True}}}), flush=True)
sys.stdin.read()
"""#)
        defer { client.stop() }
        do {
            _ = try await client.request("initialize", timeout: 5)
            XCTFail("Remote JSON-RPC errors must throw")
        } catch ACPClientError.remote(let code, let message, let data) {
            XCTAssertEqual(code, -32000)
            XCTAssertEqual(message, "Sign in required")
            XCTAssertEqual((data as? [String: Any])?["auth"] as? Bool, true)
        }
    }

    func testMalformedOutputDisconnectsWithoutWaitingForTimeout() async throws {
        let client = try startFixture(#"""
import sys
sys.stdin.readline()
print("not JSON", flush=True)
sys.stdin.read()
"""#)
        defer { client.stop() }
        do {
            _ = try await client.request("initialize", timeout: 5)
            XCTFail("Malformed protocol output must fail the connection")
        } catch ACPClientError.disconnected(let reason) {
            XCTAssertTrue(reason.contains("malformed JSON"))
        }
    }
}
