import Foundation
import AppKit

extension AppStore {
    func addMCPServer(name: String, transport: String, endpoint: String, arguments: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !endpoint.isEmpty else { featureError = "Enter a server name and connection details."; return }
        var configuration: [String: Any] = ["server_name": name, "enabled": true]
        if transport == "http" {
            guard let url = URL(string: endpoint), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                featureError = "Enter an HTTP or HTTPS server URL."; return
            }
            configuration["url"] = endpoint
        } else {
            configuration["command"] = endpoint
            // One argument per line avoids silently invoking a shell or guessing quoting.
            configuration["args"] = arguments.components(separatedBy: .newlines).filter { !$0.isEmpty }
        }
        performFeatureAction(.mcps) { client, _, session in
            var params = configuration; params["session_id"] = session
            _ = try ExtensionResponse.unwrap(try await client.request("_x.ai/mcp/upsert", params: params, timeout: 60))
        }
    }

    func removeMCPServer(_ name: String) {
        performFeatureAction(.mcps) { client, _, session in
            _ = try ExtensionResponse.unwrap(try await client.request("_x.ai/mcp/delete", params: ["session_id": session, "server_name": name]))
        }
    }

    func toggleMCPTool(server: String, tool: String, enabled: Bool) {
        performFeatureAction(.mcps) { client, _, session in
            _ = try ExtensionResponse.unwrap(try await client.request("_x.ai/mcp/toggle_tool", params: ["session_id": session, "server_name": server, "tool_name": tool, "enabled": enabled]))
        }
    }

    func addSkillFolder() {
        let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = true
        picker.message = "Choose a skill folder or SKILL.md file."; picker.prompt = "Add skill"
        guard picker.runModal() == .OK, let url = picker.url else { return }
        addSkillPath(url.path)
    }

    func addSkillPath(_ path: String) {
        guard let cwd = project?.path else { featureError = "Open a project first."; return }
        performFeatureAction(.skills) { client, _, _ in
            _ = try ExtensionResponse.unwrap(try await client.request("_x.ai/skills/add", params: ["cwd": cwd, "path": path]))
        }
    }
}

struct MCPToolChoice: Identifiable {
    var id: String { name }
    let name: String
    let description: String
    let enabled: Bool

    static func from(_ row: FeatureRow) -> [MCPToolChoice] {
        let session = row.payload["session"] as? [String: Any] ?? [:]
        return (session["tools"] as? [[String: Any]] ?? []).compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            return MCPToolChoice(name: name, description: item["description"] as? String ?? "", enabled: item["enabled"] as? Bool ?? true)
        }
    }
}
