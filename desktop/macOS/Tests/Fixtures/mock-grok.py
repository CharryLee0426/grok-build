#!/usr/bin/env python3
"""Offline ACP fixture for Grok Desktop tests and manual UI inspection.

Select this executable as the harness in Settings. It never runs tools, writes
project files, contacts a service, or reads credentials. Every response is marked
as fixture data. Prompts containing `fixture:permission`, `fixture:question`,
`fixture:plan`, or `fixture:trust` display the corresponding interaction;
`fixture:wait` waits for Stop and `fixture:error` returns a protocol error.
The ordinary scenario streams Markdown, a plan, and a simulated tool result.
"""

import json
import os
import queue
import sys
import threading


class MockHarness:
    def __init__(self):
        self.output_lock = threading.Lock()
        self.state_lock = threading.RLock()
        self.authenticated = False
        self.sequence = 0
        self.reverse_sequence = 0
        self.pending = {}
        self.turns = {}
        self.sessions = {
            "fixture-history-001": {
                "sessionId": "fixture-history-001",
                "cwd": os.getcwd(),
                "title": "Explore the desktop harness (fixture)",
                "updatedAt": "2026-09-21T12:00:00Z",
            }
        }
        self.history = {
            "fixture-history-001": [
                {"sessionUpdate": "user_message_chunk", "content": {"type": "text", "text": "Show the desktop workflow."}},
                {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "This is **offline fixture history**. The real app connects to `grok agent stdio`."}},
            ]
        }
        self.model_id = "fixture-grok-build"
        self.mode_id = "build"

    def emit(self, message):
        with self.output_lock:
            try:
                sys.stdout.write(json.dumps({"jsonrpc": "2.0", **message}, ensure_ascii=False) + "\n")
                sys.stdout.flush()
            except BrokenPipeError:
                os._exit(0)

    def result(self, request_id, value):
        self.emit({"id": request_id, "result": value})

    def error(self, request_id, code, message):
        self.emit({"id": request_id, "error": {"code": code, "message": message}})

    def update(self, session_id, update, remember=True):
        if remember:
            with self.state_lock:
                self.history.setdefault(session_id, []).append(update)
        self.emit({"method": "session/update", "params": {"sessionId": session_id, "update": update}})

    def models(self):
        return {
            "currentModelId": self.model_id,
            "availableModels": [
                {"modelId": "fixture-grok-build", "name": "Grok Build (fixture)"},
                {"modelId": "fixture-grok-fast", "name": "Grok Fast (fixture)"},
            ],
        }

    def session_state(self):
        return {
            "models": self.models(),
            "modes": {"currentModeId": self.mode_id, "availableModes": [
                {"id": "build", "name": "Build"}, {"id": "plan", "name": "Plan"},
            ]},
        }

    def ask(self, session_id, method, params, stop):
        with self.state_lock:
            self.reverse_sequence += 1
            request_id = "fixture-request-{}".format(self.reverse_sequence)
            replies = queue.Queue(maxsize=1)
            self.pending[request_id] = replies
        self.emit({"id": request_id, "method": method, "params": {"sessionId": session_id, **params}})
        try:
            while not stop.is_set():
                try:
                    reply = replies.get(timeout=0.05)
                    if "error" in reply:
                        return {"outcome": "unsupported"}
                    return reply.get("result", {})
                except queue.Empty:
                    pass
            return {"outcome": "cancelled"}
        finally:
            with self.state_lock:
                self.pending.pop(request_id, None)

    def prompt(self, request_id, params, stop):
        session_id = params["sessionId"]
        prompt = "".join(block.get("text", "") for block in params.get("prompt", []) if block.get("type") == "text")
        def finish(stop_reason):
            # Remove the old turn before replying so an immediate next prompt is
            # never rejected merely because the worker is finishing its cleanup.
            with self.state_lock:
                if self.turns.get(session_id) is stop:
                    self.turns.pop(session_id, None)
            self.result(request_id, {"stopReason": stop_reason})
        try:
            if "fixture:error" in prompt:
                self.error(request_id, -32000, "Offline fixture: a recoverable harness error.")
                return
            self.update(session_id, {"sessionUpdate": "user_message_chunk", "content": {"type": "text", "text": prompt}})
            self.update(session_id, {"sessionUpdate": "agent_thought_chunk", "content": {"type": "text", "text": "Preparing the offline desktop fixture."}})
            self.update(session_id, {"sessionUpdate": "plan", "entries": [
                {"content": "Inspect the fixture", "priority": "medium", "status": "in_progress"},
                {"content": "Summarize the result", "priority": "medium", "status": "pending"},
            ]})
            tool_id = "fixture-tool-{}".format(request_id)
            self.update(session_id, {"sessionUpdate": "tool_call", "toolCallId": tool_id, "title": "Preview desktop fixture", "kind": "read", "status": "in_progress", "rawInput": {"fixture": True}})
            interaction = None
            if "fixture:permission" in prompt:
                interaction = self.ask(session_id, "session/request_permission", {
                    "toolCall": {"toolCallId": tool_id, "title": "Allow the simulated fixture tool?", "rawInput": {"fixture": True, "command": "No command will execute"}},
                    "options": [
                        {"optionId": "deny", "name": "Decline", "kind": "reject_once"},
                        {"optionId": "allow", "name": "Allow once", "kind": "allow_once"},
                    ],
                }, stop)
            if "fixture:question" in prompt and not stop.is_set():
                interaction = self.ask(session_id, "x.ai/ask_user_question", {
                    "toolCallId": tool_id, "mode": "default",
                    "questions": [{"question": "Which fixture should we explore?", "header": "Preview", "multiSelect": False, "options": [
                        {"label": "Conversation", "description": "Review the streamed conversation."},
                        {"label": "Changes", "description": "Review the workspace inspector."},
                    ]}],
                }, stop)
            if "fixture:plan" in prompt and not stop.is_set():
                interaction = self.ask(session_id, "x.ai/exit_plan_mode", {
                    "toolCallId": tool_id,
                    "planContent": "# Offline fixture plan\n\n1. Show the approval UI.\n2. Return a simulated result.\n\nNo project files will change.",
                }, stop)
            if "fixture:trust" in prompt and not stop.is_set():
                cwd = self.sessions[session_id]["cwd"]
                interaction = self.ask(session_id, "x.ai/folder_trust/request", {"cwd": cwd, "workspace": cwd, "configKinds": ["mcp", "hooks"]}, stop)
            if "fixture:wait" in prompt:
                stop.wait(30)
            if stop.is_set():
                self.update(session_id, {"sessionUpdate": "tool_call_update", "toolCallId": tool_id, "status": "failed"})
                finish("cancelled")
                return
            detail = "Offline fixture completed. No commands were executed and no files were changed."
            if interaction is not None:
                detail += "\nClient reply: " + json.dumps(interaction, sort_keys=True)
            self.update(session_id, {"sessionUpdate": "tool_call_update", "toolCallId": tool_id, "status": "completed", "content": [{"type": "content", "content": {"type": "text", "text": detail}}]})
            answer = "## Ready to build\n\nThis is an **offline test fixture**, connected over the same ACP transport as Grok Build.\n\n- Streamed conversation and tool activity\n- Project-scoped tasks and session history\n- Native approvals, model selection, and workspace changes\n\n```swift\nlet nextStep = \"Build something useful\"\n```\n\nChoose your real `grok` executable in Settings to work with the harness."
            for offset in range(0, len(answer), 28):
                if stop.wait(0.012):
                    finish("cancelled")
                    return
                self.update(session_id, {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": answer[offset:offset + 28]}})
            self.update(session_id, {"sessionUpdate": "plan", "entries": [
                {"content": "Inspect the fixture", "priority": "medium", "status": "completed"},
                {"content": "Summarize the result", "priority": "medium", "status": "completed"},
            ]})
            finish("end_turn")
        finally:
            with self.state_lock:
                if self.turns.get(session_id) is stop:
                    self.turns.pop(session_id, None)

    def handle(self, message):
        method = message.get("method")
        request_id = message.get("id")
        params = message.get("params", {})
        if method is None:
            with self.state_lock:
                replies = self.pending.get(request_id)
            if replies is not None:
                replies.put_nowait(message)
            return
        if method == "initialize":
            self.result(request_id, {"protocolVersion": 1, "agentInfo": {"name": "grok-desktop-fixture", "version": "1.0.0"}, "agentCapabilities": {"loadSession": True, "sessionCapabilities": {"list": {}}}, "authMethods": [{"id": "cached_token", "name": "Offline fixture"}], "_meta": {"defaultAuthMethodId": "cached_token", "modelState": self.models()}})
        elif method == "authenticate":
            self.authenticated = True
            self.result(request_id, {})
        elif method == "session/cancel":
            with self.state_lock:
                stop = self.turns.get(params.get("sessionId"))
            if stop is not None:
                stop.set()
        elif not self.authenticated:
            self.error(request_id, -32000, "Authenticate the offline fixture first.")
        elif method == "session/list":
            sessions = [session for session in self.sessions.values() if not params.get("cwd") or params["cwd"] == session["cwd"]]
            self.result(request_id, {"sessions": sessions})
        elif method in ("session/new", "session/load"):
            if method == "session/new":
                self.sequence += 1
                session_id = "fixture-session-{}-{}".format(os.getpid(), self.sequence)
            else:
                session_id = params.get("sessionId")
            if not session_id or not os.path.isabs(params.get("cwd", "")):
                self.error(request_id, -32602, "An absolute cwd and session ID are required.")
                return
            self.sessions.setdefault(session_id, {"sessionId": session_id, "cwd": params["cwd"], "title": "Desktop task (fixture)", "updatedAt": "2026-09-21T12:00:00Z"})
            if method == "session/load":
                for update in list(self.history.get(session_id, [])):
                    self.update(session_id, update, remember=False)
            self.result(request_id, {"sessionId": session_id, **self.session_state()})
        elif method in ("session/set_model", "session/set_mode", "session/prompt"):
            session_id = params.get("sessionId")
            if session_id not in self.sessions:
                self.error(request_id, -32602, "Unknown fixture session.")
                return
            if method == "session/set_model":
                self.model_id = params["modelId"]
                self.result(request_id, {})
            elif method == "session/set_mode":
                self.mode_id = params["modeId"]
                self.update(session_id, {"sessionUpdate": "current_mode_update", "currentModeId": self.mode_id}, remember=False)
                self.result(request_id, {})
            else:
                with self.state_lock:
                    if session_id in self.turns:
                        self.error(request_id, -32600, "A fixture turn is already running.")
                        return
                    stop = threading.Event()
                    self.turns[session_id] = stop
                threading.Thread(target=self.prompt, args=(request_id, params, stop), daemon=True).start()
        elif request_id is not None:
            self.error(request_id, -32601, "Unsupported fixture method: " + method)

    def run(self):
        for line in sys.stdin:
            try:
                self.handle(json.loads(line))
            except (ValueError, KeyError, TypeError) as error:
                self.error(None, -32600, "Invalid fixture request: " + str(error))


if __name__ == "__main__":
    if sys.argv[1:] == ["agent", "stdio"]:
        MockHarness().run()
    elif sys.argv[1:] and sys.argv[1] == "login":
        print("Offline fixture: authentication is simulated. No credentials were used.")
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
