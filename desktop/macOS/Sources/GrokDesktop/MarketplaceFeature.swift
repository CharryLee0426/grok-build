import Foundation

/// A plugin offered by a marketplace source (`MarketplacePluginEntry`, camelCase).
struct MarketplacePluginItem: Identifiable, Equatable {
    let source: String
    let name: String
    let relativePath: String
    let version: String?
    let description: String?
    let category: String?
    let author: String?
    let homepage: String?
    let tags: [String]
    let skillCount: Int
    let hasHooks: Bool
    let hasAgents: Bool
    let hasMcp: Bool
    /// `installed`, `update_available`, or `not_installed`.
    let installStatus: String
    let installedVersion: String?
    /// "3 skills · 1 MCP server" from the catalog inventory, when the source publishes one.
    let components: String?
    var id: String { source + "\u{1}" + relativePath }

    init?(_ value: [String: Any], source: String) {
        guard let name = value["name"] as? String else { return nil }
        self.source = source
        self.name = name
        relativePath = value["relativePath"] as? String ?? name
        version = value["version"] as? String
        description = value["description"] as? String
        category = value["category"] as? String
        author = value["author"] as? String
        homepage = value["homepage"] as? String
        tags = value["tags"] as? [String] ?? []
        skillCount = (value["skillCount"] as? NSNumber)?.intValue ?? 0
        hasHooks = value["hasHooks"] as? Bool ?? false
        hasAgents = value["hasAgents"] as? Bool ?? false
        hasMcp = value["hasMcp"] as? Bool ?? false
        installStatus = value["installStatus"] as? String ?? "not_installed"
        installedVersion = value["installedVersion"] as? String
        components = Self.summary(value["components"] as? [String: Any])
    }

    var isInstalled: Bool { installStatus != "not_installed" }
    var hasUpdate: Bool { installStatus == "update_available" }

    static func summary(_ components: [String: Any]?) -> String? {
        guard let components else { return nil }
        let categories = [("skills", "skill", "skills"), ("commands", "command", "commands"), ("agents", "agent", "agents"),
                          ("mcpServers", "MCP server", "MCP servers"), ("hooks", "hook", "hooks"), ("lspServers", "LSP server", "LSP servers")]
        let parts = categories.compactMap { key, singular, plural -> String? in
            let count = (components[key] as? [Any])?.count ?? 0
            return count == 0 ? nil : "\(count) \(count == 1 ? singular : plural)"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{b7} ")
    }
}

/// One marketplace source and what scanning it found.
struct MarketplaceSourceItem: Identifiable, Equatable {
    let name: String
    let kind: String
    let urlOrPath: String
    let plugins: [MarketplacePluginItem]
    let error: String?
    var id: String { urlOrPath.isEmpty ? name : urlOrPath }

    static func parse(_ result: [String: Any]) -> [MarketplaceSourceItem] {
        (result["sources"] as? [[String: Any]] ?? []).map { value in
            let url = value["sourceUrlOrPath"] as? String ?? ""
            return MarketplaceSourceItem(name: value["sourceName"] as? String ?? url, kind: value["sourceKind"] as? String ?? "",
                urlOrPath: url, plugins: (value["plugins"] as? [[String: Any]] ?? []).compactMap { MarketplacePluginItem($0, source: url) },
                error: value["error"] as? String)
        }
    }
}

/// State behind the Marketplace panel. Loading and errors go through the store's feature state like the other panels.
@MainActor
final class MarketplacePanelModel: ObservableObject {
    weak var store: AppStore?
    @Published var sources: [MarketplaceSourceItem] = []
    @Published var loaded = false
    /// "Installing..." while an action runs.
    @Published var pending: String?
    @Published var collapsed: Set<String> = []

    init(store: AppStore) { self.store = store }

    func apply(_ result: [String: Any]) {
        sources = MarketplaceSourceItem.parse(result)
        loaded = true
    }

    /// Runs an action; a successful update is announced to the session like the terminal's automatic
    /// updates. When the harness asks for confirmation, the user is asked and the action is sent again
    /// marked `confirmed`.
    func perform(_ action: MarketplaceWireAction, plugin: MarketplacePluginItem? = nil, confirmed: Bool = false) {
        guard let store, !store.featureLoading else { return }
        let extensions = store.features.extensions
        extensions.notice = nil
        pending = action.pendingLabel
        var wire = action.wire
        if confirmed { wire["confirmed"] = true }
        store.performFeatureAction(.marketplace) { [weak self] client, _, session in
            defer { self?.pending = nil }
            let outcome = try ExtensionActionOutcome.parse(try await client.request("_x.ai/marketplace/action", params: ["sessionId": session, "action": wire], timeout: 600))
            if outcome.needsConfirmation, !confirmed {
                extensions.pendingConfirmation = ExtensionConfirmation(panel: .marketplace, message: outcome.message, confirmTitle: "Continue") { [weak self] in
                    self?.perform(action, plugin: plugin, confirmed: true)
                }
                return
            }
            guard outcome.succeeded else {
                throw DesktopError.message(outcome.message.isEmpty ? outcome.status.replacingOccurrences(of: "_", with: " ") : outcome.message)
            }
            if outcome.requiresReload {
                _ = try? await client.request("_x.ai/plugins/action", params: ["sessionId": session, "action": PluginsWireAction.reload.wire], timeout: 120)
            }
            if case .update = action, let plugin {
                let update = [plugin.name, plugin.installedVersion ?? "?", plugin.version ?? "?"]
                _ = try? await client.request("_x.ai/plugins/notify-updates", params: ["sessionId": session, "updates": [update]])
            }
            if !outcome.message.isEmpty { extensions.notice = ExtensionNotice(panel: .marketplace, text: outcome.message) }
        }
    }
}
