import AppKit
import SwiftUI

/// Usage, context, session info, feedback, privacy, sign-out, release notes, and announcements.
@MainActor
final class AccountFeatureModel: ObservableObject {
    weak var store: AppStore?

    /// The usage sheet's tab. `/usage`, `/context`, and `/session-info` switch it in place when the sheet is open.
    @Published var usageTab: UsageTab = .limit
    @Published private(set) var usage = UsageSheetState()
    @Published private(set) var privacy = AccountPrivacyState()
    @Published private(set) var releaseNotes = ReleaseNotesState()
    @Published private(set) var announcements: [GrokAnnouncement] = []
    @Published private(set) var hiddenAnnouncementKeys: Set<String> = []
    @Published private(set) var feedbackDrafts: FeedbackDraftListState = .idle
    @Published private(set) var isSigningOut = false

    /// Opens links in the browser. Tests replace it so nothing leaves the process.
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// `$GROK_HOME`, read when needed. Tests point it at a temporary directory.
    var grokHome: () -> URL = { GrokPaths.home }
    /// Downloads release notes. Tests replace it so no request reaches the network.
    var downloadText: (URL, TimeInterval) async -> String? = ReleaseNotesLoader.download

    private var usageRequestID: UUID?
    private var releaseNotesRequestID: UUID?
    private var draftsRequestID: UUID?
    private var privacyRequestID: UUID?
    private var privacyWriteSeq = 0
    /// The choice of the coding-data write in flight and the value to restore if it fails.
    private var pendingPrivacyWrite: (optedIn: Bool, rollbackOptOut: Bool?)?
    private var announcementsGeneration: UInt64 = 0
    private var announcementExpiry: Task<Void, Never>?
    private let announcementWrites = DispatchQueue(label: "ai.grok.desktop.announcements", qos: .utility)
    /// "No, and don't ask again" applies to the rest of this run even before config.toml is read again.
    private var feedbackTraceLatched = false
    private var showResolvedModel = false
    private var accountClient: ACPClient?
    private var accountClientKey: UUID?
    private var accountClientStart: Task<ACPClient, Error>?
    private var accountReleaseGeneration = 0

    init(store: AppStore) { self.store = store }

    // MARK: Notifications

    /// Return true to consume a harness notification (see `DesktopFeatures.handle`).
    func handle(method: String, params: [String: Any], update: [String: Any]?, conversationID: UUID) -> Bool {
        handleGlobal(method: method, params: params)
    }

    /// Notifications that do not depend on a task (for example `x.ai/announcements/update`).
    func handleGlobal(method: String, params: [String: Any]) -> Bool {
        switch method {
        case "x.ai/announcements/update":
            applyAnnouncementsUpdate(params)
            return true
        case "x.ai/settings/update":
            // Other features read the same push; only note what the session-info model row needs.
            let settings = params["settings"] as? [String: Any] ?? params
            if let value = settings["show_resolved_model"] as? Bool { showResolvedModel = value }
            return false
        default:
            return false
        }
    }

    // MARK: Command entry points

    /// `/usage [show|manage]`, alias `/cost`.
    func usage(_ arguments: String) {
        guard let store else { return }
        switch UsageCommandRules.parse(arguments, commandVisible: store.harnessMeta.allowsUsageCommand,
                                       billingVisible: store.harnessMeta.showsConsumerBilling) {
        case .show: presentUsage(.limit)
        case .manage: if let url = URL(string: UsageCommandRules.manageBillingURL) { openURL(url) }
        case .failure(let message): store.banner = message
        }
    }
    /// `/context`. The shell's own `/context` prompt does nothing, so it is never forwarded.
    func openContext() { presentUsage(.context) }
    /// `/session-info`, aliases `/status` and `/info`.
    func openSessionInfo() { presentUsage(.session) }
    /// `/feedback [text]`: text is sent at once, as in the terminal; bare opens the form.
    func feedback(_ arguments: String) {
        let text = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { store?.sheet = .feedback(text: "") } else { sendInlineFeedback(text) }
    }
    /// `/privacy`.
    func openPrivacy() { store?.sheet = .privacy }
    /// `/logout`. Like the terminal, the command signs out without asking; the Settings button confirms first.
    func logout() { Task { await signOut() } }
    /// `/release-notes`, alias `/changelog`.
    func openReleaseNotes() {
        store?.open(.releaseNotes)
        if !releaseNotes.isLoading { loadReleaseNotes() }
    }
    /// `/announcements hide|show`.
    func announcements(_ arguments: String) {
        switch arguments.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "" {
        case "hide": hideCurrentAnnouncement()
        case "show": showAllAnnouncements()
        default: store?.banner = "Usage: /announcements hide | show"
        }
    }

    private func presentUsage(_ tab: UsageTab) {
        guard let store else { return }
        usageTab = tab
        // An open sheet only changes tabs, as the terminal's modal does; reopening would refetch.
        if case .usage = store.sheet { return }
        store.sheet = .usage(tab)
    }

    // MARK: Connections

    /// A connected harness for account-wide requests (billing, privacy, sign-out): the selected
    /// task's live connection, or a private one, so reading them never creates a task.
    func accountConnection() async throws -> ACPClient {
        guard let store else { throw DesktopError.message("Grok Desktop is closing.") }
        accountReleaseGeneration += 1
        if let id = store.state.selectedConversationID, store.loaded.contains(id), let client = store.clients[id], client.isRunning {
            return client
        }
        if let client = accountClient, client.isRunning { return client }
        if let pending = accountClientStart { return try await pending.value }
        guard FileManager.default.isExecutableFile(atPath: store.binaryPath) else {
            throw DesktopError.message("The bundled Grok runtime is missing. Reinstall Grok Desktop.")
        }
        let cwd = store.project?.path ?? FileManager.default.homeDirectoryForCurrentUser.path
        let start = Task { @MainActor [weak store] () throws -> ACPClient in
            guard let store else { throw CancellationError() }
            let client = ACPClient()
            client.onNotification = { [weak store] method, params in
                store?.features.handleGlobal(method: method.hasPrefix("_") ? String(method.dropFirst()) : method, params: params)
            }
            do {
                try client.start(executable: store.binaryPath, cwd: cwd)
                let initial = try await store.initialize(client)
                try await store.authenticate(client, initial: initial)
                return client
            } catch {
                client.stop()
                throw error
            }
        }
        accountClientStart = start
        do {
            let client = try await start.value
            accountClientStart = nil
            releaseAccountConnection()
            let key = UUID()
            accountClient = client; accountClientKey = key
            // Registered with the store so quitting stops it with the other helper processes.
            store.auxiliaryClients[key] = client
            return client
        } catch {
            accountClientStart = nil
            throw error
        }
    }

    /// Stops the private connection a little after account views close, unless a request is still
    /// in flight or another view needs it again first.
    func releaseAccountConnectionSoon(after seconds: Double = 20) {
        accountReleaseGeneration += 1
        let generation = accountReleaseGeneration
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, self.accountReleaseGeneration == generation,
                  self.pendingPrivacyWrite == nil, !self.isSigningOut else { return }
            self.releaseAccountConnection()
        }
    }

    /// Stops the private account connection, if one was started.
    func releaseAccountConnection() {
        accountClient?.stop(); accountClient = nil
        if let key = accountClientKey { store?.auxiliaryClients.removeValue(forKey: key) }
        accountClientKey = nil
    }

    /// The selected task's session, when there is a task. Nothing is created without one.
    private func selectedSession() async throws -> (ACPClient, UUID, String)? {
        guard let store, store.state.selectedConversationID != nil else { return nil }
        return try await store.featureSession()
    }

    // MARK: Usage sheet

    /// Loads all three tabs. Results from an earlier load are dropped.
    func refreshUsage() {
        guard let store else { return }
        let requestID = UUID()
        usageRequestID = requestID
        let conversation = store.conversation
        var state = UsageSheetState()
        state.hasSession = conversation != nil
        state.billingVisible = store.harnessMeta.showsConsumerBilling
        if conversation != nil {
            state.context = .loading; state.sessionInfo = .loading; state.sessionUsage = .loading
        } else {
            state.context = .unavailable("No active session.")
            state.sessionInfo = .unavailable("No active session.")
            state.sessionUsage = .idle
        }
        state.billing = state.billingVisible ? .loading : .idle
        usage = state
        Task { await loadUsage(requestID: requestID, title: conversation?.title) }
    }

    private func loadUsage(requestID: UUID, title: String?) async {
        guard let store else { return }
        let session: (ACPClient, UUID, String)?
        do { session = try await selectedSession() } catch {
            guard usageRequestID == requestID else { return }
            let message = AccountErrorText.describe(error)
            usage.context = .failed(message); usage.sessionInfo = .failed(message); usage.sessionUsage = .failed(message)
            await loadBilling(requestID: requestID, client: nil)
            return
        }
        guard usageRequestID == requestID else { return }
        // The account is known once a connection exists; team and API-key accounts have no billing.
        usage.billingVisible = store.harnessMeta.showsConsumerBilling
        usage.subscriptionTier = store.harnessMeta.subscriptionTier
        if !usage.billingVisible { usage.billing = .idle }
        guard case let (client, _, sessionID)? = session else {
            await loadBilling(requestID: requestID, client: nil)
            return
        }
        async let info: Void = loadSessionInfo(requestID: requestID, client: client, sessionID: sessionID, title: title)
        async let totals: Void = loadSessionUsage(requestID: requestID, client: client, sessionID: sessionID)
        async let billing: Void = loadBilling(requestID: requestID, client: client)
        _ = await (info, totals, billing)
    }

    private func loadSessionInfo(requestID: UUID, client: ACPClient, sessionID: String, title: String?) async {
        do {
            let result = try ExtensionResponse.unwrap(try await client.request("_x.ai/session/info", params: ["sessionId": sessionID]))
            guard usageRequestID == requestID, let store else { return }
            let info = UsageSessionInfo(result)
            usage.context = .loaded(info.context)
            usage.contextModel = info.model ?? "unknown"
            usage.sessionInfo = .loaded(UsageFormatting.sessionInfoRows(
                info, title: title, shellVersion: store.harnessMeta.agentVersion,
                auth: store.harnessMeta.sessionInfoAuthMethod, showResolvedModel: showResolvedModel))
        } catch {
            guard usageRequestID == requestID else { return }
            let message = AccountErrorText.describe(error)
            usage.context = .failed(message); usage.sessionInfo = .failed(message)
        }
    }

    private func loadSessionUsage(requestID: UUID, client: ACPClient, sessionID: String) async {
        do {
            let result = try ExtensionResponse.unwrap(try await client.request("_x.ai/session/usage", params: ["sessionId": sessionID]))
            guard usageRequestID == requestID else { return }
            guard let totals = result["usage"] as? [String: Any] else { throw DesktopError.message("The harness did not return session usage.") }
            usage.sessionUsage = .loaded(UsageSessionSummary(totals))
        } catch {
            guard usageRequestID == requestID else { return }
            usage.sessionUsage = .failed(AccountErrorText.describe(error))
        }
    }

    private func loadBilling(requestID: UUID, client: ACPClient?) async {
        guard let store, store.harnessMeta.showsConsumerBilling else {
            if usageRequestID == requestID { usage.billing = .idle }
            return
        }
        do {
            let connection: ACPClient
            if let client { connection = client } else { connection = try await accountConnection() }
            guard usageRequestID == requestID else { return }
            // A private connection learns the account only now.
            usage.billingVisible = store.harnessMeta.showsConsumerBilling
            usage.subscriptionTier = store.harnessMeta.subscriptionTier
            guard usage.billingVisible else { usage.billing = .idle; return }
            let response = try ExtensionResponse.unwrap(try await connection.request("_x.ai/billing", timeout: 20))
            guard usageRequestID == requestID else { return }
            var billing = UsageBilling(response)
            if let tier = billing.subscriptionTier { usage.subscriptionTier = tier }
            if billing.balance?.hasPrepaidCredits == true {
                // A failed rule fetch leaves the rule unknown rather than "disabled".
                if let rule = try? ExtensionResponse.unwrap(try await connection.request("_x.ai/auto-topup-rule", timeout: 15)) {
                    billing.autoTopup = UsageAutoTopup(rule)
                }
                guard usageRequestID == requestID else { return }
            }
            usage.billing = .loaded(billing)
        } catch {
            guard usageRequestID == requestID else { return }
            usage.billing = .failed(AccountErrorText.describe(error))
        }
    }

    /// `/usage manage` and the sheet's Manage billing button.
    func manageBilling() {
        if let url = URL(string: UsageCommandRules.manageBillingURL) { openURL(url) }
    }

    // MARK: Feedback

    /// Whether to ask about attaching the session trace, following the terminal's gates:
    /// offered by the harness, coding data opted in, not Zero Data Retention, not on a team,
    /// and not declined with "don't ask again".
    var feedbackTraceOffered: Bool {
        guard let store, store.harnessMeta.feedbackTraceOffer, !feedbackTraceLatched else { return false }
        let optOut = privacy.optOut ?? store.harnessMeta.codingDataRetentionOptOut ?? true
        let config = GrokConfig(url: grokHome().appendingPathComponent("config.toml"))
        return !optOut && !store.harnessMeta.isZDR && store.harnessMeta.teamName == nil
            && config.bool("feedback_trace_card", in: "features") != false
    }

    /// `/feedback <text>`: thanks at once, send in the background, and keep the text as a draft if it fails.
    func sendInlineFeedback(_ text: String) {
        guard let store else { return }
        // Feedback is sent with a session's details; don't start an empty task for it.
        guard store.state.selectedConversationID != nil else { store.banner = FeedbackCopy.needsTask; return }
        store.banner = FeedbackCopy.thanks
        let projectPath = store.project?.path
        Task {
            var sessionID: String?
            do {
                let (client, _, session) = try await store.featureSession()
                sessionID = session
                let params = FeedbackRequests.write(sessionID: session, text: text, images: [], taxonomy: FeedbackTaxonomySelection(),
                                                    requestTraceUploadToken: false, clientVersion: FeedbackRequests.clientVersion)
                let response = FeedbackResponse(try await client.request("_x.ai/feedback", params: params, timeout: FeedbackRequests.sendTimeout))
                if response.outcome == .outcomeUnknown { store.banner = FeedbackCopy.enqueuedUnknown }
            } catch ACPClientError.timedOut {
                store.banner = FeedbackCopy.enqueuedUnknown
            } catch {
                let failure = "Couldn't send feedback: \(AccountErrorText.describe(error))"
                store.banner = await keepUnsentFeedback(text: text, failure: failure, projectPath: projectPath, sessionID: sessionID)
            }
        }
    }

    /// Saves unsent inline feedback as a draft beside the session, as the terminal does.
    private func keepUnsentFeedback(text: String, failure: String, projectPath: String?, sessionID: String?) async -> String {
        let home = grokHome()
        // Harness messages often end in a period; the notice adds its own.
        let failure = failure.hasSuffix(".") ? String(failure.dropLast()) : failure
        guard let projectPath, let sessionID else { return "\(failure). Not sent: \(text)" }
        return await Task.detached(priority: .utility) { () -> String in
            guard let directory = GrokPaths.sessionDirectory(cwd: projectPath, sessionID: sessionID, home: home) else {
                return "\(failure). Not sent: \(text)"
            }
            do {
                try FeedbackPredraftStore.append(sessionDirectory: directory, title: FeedbackText.deriveTitle(text), details: text)
                return "\(failure). Saved to Drafts; open `/feedback` to retry."
            } catch {
                return "\(failure). Could not save it as a draft (\(error.localizedDescription)). Not sent: \(text)"
            }
        }.value
    }

    /// Sends the feedback form. The sheet stays open on failure so nothing typed is lost.
    func submitFeedback(_ composition: FeedbackComposition) async -> FeedbackSubmitResult {
        guard let store else { return .failed("Grok Desktop is closing.") }
        guard store.state.selectedConversationID != nil else { return .failed(FeedbackCopy.needsTask) }
        let text = composition.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !composition.images.isEmpty else { return .failed(FeedbackCopy.emptySubmit) }
        if composition.draft != nil, composition.taxonomy.type == nil { return .failed(FeedbackCopy.draftNeedsType) }
        if composition.traceChoice == .neverAsk { persistFeedbackTraceDecline() }
        let wantsTrace = composition.traceChoice == .sendThisSession
        let client: ACPClient, session: String
        do { (client, _, session) = try await store.featureSession() } catch {
            return .failed("Couldn't send feedback: \(AccountErrorText.describe(error))")
        }
        let params: [String: Any]
        if let draft = composition.draft, let type = composition.taxonomy.type {
            params = FeedbackRequests.draft(sessionID: session, draftID: draft.id, title: draft.title, details: text, area: draft.area,
                                            type: type, taxonomy: composition.taxonomy, images: composition.images,
                                            requestTraceUploadToken: wantsTrace, clientVersion: FeedbackRequests.clientVersion)
        } else {
            params = FeedbackRequests.write(sessionID: session, text: text, images: composition.images, taxonomy: composition.taxonomy,
                                            requestTraceUploadToken: wantsTrace, clientVersion: FeedbackRequests.clientVersion)
        }
        let response: FeedbackResponse
        do {
            response = FeedbackResponse(try await client.request("_x.ai/feedback", params: params, timeout: FeedbackRequests.sendTimeout))
        } catch ACPClientError.timedOut {
            response = FeedbackResponse(success: false, outcome: .outcomeUnknown, traceUploadToken: nil)
        } catch {
            let failure = "Couldn't send feedback: \(AccountErrorText.describe(error))"
            return .failed(composition.draft == nil ? failure : "\(failure). The draft was kept.")
        }
        if wantsTrace, response.posted, let token = response.traceUploadToken { uploadFeedbackTrace(client: client, sessionID: session, token: token) }
        guard let draft = composition.draft else {
            if response.outcome == .outcomeUnknown { store.banner = FeedbackCopy.enqueuedUnknown } else { store.banner = FeedbackCopy.thanks }
            return .sent
        }
        switch response.outcome {
        case .submitted:
            store.banner = FeedbackCopy.thanks
            return .sent
        case .submittedCleanupFailed:
            return .settled(FeedbackCopy.draftCleanupFailed)
        case .localOnly:
            return .failed(FeedbackCopy.draftLocalOnly)
        case .outcomeUnknown, .other:
            // Never resend: copy the latest text and save it back to the draft instead.
            let copy = FeedbackText.postText(title: draft.title, details: text)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copy, forType: .string)
            guard let type = composition.taxonomy.type else { return .settled(FeedbackCopy.unknownNotSaved) }
            let update = FeedbackRequests.update(sessionID: session, draftID: draft.id, title: draft.title, details: text, area: draft.area,
                                                 type: type, taxonomy: composition.taxonomy)
            let saved = (try? await client.request("_x.ai/feedback/drafts/update", params: update, timeout: 15))?["updated"] as? Bool == true
            return .settled(saved ? FeedbackCopy.unknownSaved : FeedbackCopy.unknownSaveFailed)
        }
    }

    private func uploadFeedbackTrace(client: ACPClient, sessionID: String, token: String) {
        Task { [weak self] in
            do {
                _ = try ExtensionResponse.unwrap(try await client.request("_x.ai/feedback/upload-trace", params: [
                    "sessionId": sessionID, "intent": "send_this_session", "traceUploadToken": token,
                ], timeout: 150))
            } catch {
                self?.store?.banner = "Couldn't upload a session trace; your feedback was still sent. \(AccountErrorText.describe(error))"
            }
        }
    }

    /// "No, and don't ask again": `[features] feedback_trace_card = false`, shared with the terminal.
    private func persistFeedbackTraceDecline() {
        feedbackTraceLatched = true
        let url = grokHome().appendingPathComponent("config.toml")
        Task { [weak self] in
            let failure = await Task.detached(priority: .utility) { () -> String? in
                do {
                    try GrokConfig.update(url: url) { try $0.set("feedback_trace_card", to: .bool(false), in: "features") }
                    return nil
                } catch { return error.localizedDescription }
            }.value
            if let failure { self?.store?.banner = "✗ Could not save feedback_trace_card: \(failure)" }
        }
    }

    /// Loads the selected task's saved feedback drafts.
    func loadFeedbackDrafts() async {
        guard let store else { return }
        guard store.state.selectedConversationID != nil else {
            feedbackDrafts = .unavailable("Feedback drafts are saved with a task. Select a task to see its drafts.")
            return
        }
        let requestID = UUID()
        draftsRequestID = requestID
        feedbackDrafts = .loading
        do {
            let (client, _, session) = try await store.featureSession()
            let result = try ExtensionResponse.unwrap(try await client.request("_x.ai/feedback/drafts/list", params: ["session_id": session], timeout: 15))
            guard draftsRequestID == requestID else { return }
            feedbackDrafts = .loaded((result["drafts"] as? [[String: Any]] ?? []).compactMap(FeedbackDraftRecord.init))
        } catch {
            guard draftsRequestID == requestID else { return }
            feedbackDrafts = .failed(AccountErrorText.describe(error))
        }
    }

    func loadFeedbackDraft(id: String) async throws -> FeedbackDraftRecord {
        guard let store else { throw CancellationError() }
        let (client, _, session) = try await store.featureSession()
        let result = try ExtensionResponse.unwrap(try await client.request("_x.ai/feedback/drafts/get", params: ["session_id": session, "draft_id": id], timeout: 15))
        guard let draft = (result["draft"] as? [String: Any]).flatMap(FeedbackDraftRecord.init) else {
            throw DesktopError.message("The harness did not return the feedback draft.")
        }
        return draft
    }

    func deleteFeedbackDraft(id: String) async throws {
        guard let store else { throw CancellationError() }
        let (client, _, session) = try await store.featureSession()
        let result = try ExtensionResponse.unwrap(try await client.request("_x.ai/feedback/drafts/delete", params: ["session_id": session, "draft_id": id], timeout: 15))
        guard result["deleted"] as? Bool == true else { throw DesktopError.message("The draft was already deleted.") }
        if case .loaded(let rows) = feedbackDrafts { feedbackDrafts = .loaded(rows.filter { $0.id != id }) }
    }

    // MARK: Privacy

    /// Reads the coding-data choice and whether the account may change it. The sign-in reply
    /// already carries it; a private connection is started only when nothing is known yet.
    func refreshPrivacy() {
        guard let store else { return }
        guard pendingPrivacyWrite == nil else { return }
        let meta = store.harnessMeta
        privacy.isZDR = meta.isZDR
        privacy.teamName = meta.teamName
        privacy.teamRole = meta.teamRole
        if let optOut = meta.codingDataRetentionOptOut { privacy.optOut = optOut }
        let live = store.state.selectedConversationID.map { store.loaded.contains($0) && store.clients[$0] != nil } ?? false
        guard privacy.optOut == nil || live || accountClient?.isRunning == true else { return }
        let requestID = UUID()
        privacyRequestID = requestID
        privacy.loading = privacy.optOut == nil
        Task {
            defer { if privacyRequestID == requestID { privacy.loading = false } }
            do {
                let client = try await accountConnection()
                let info = try ExtensionResponse.unwrap(try await client.request("_x.ai/auth/info", timeout: 15))
                guard privacyRequestID == requestID, pendingPrivacyWrite == nil else { return }
                privacy.optOut = info["codingDataRetentionOptOut"] as? Bool ?? privacy.optOut
                privacy.teamName = (info["teamName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                privacy.teamRole = info["teamRole"] as? String
                privacy.isZDR = store.harnessMeta.isZDR
                privacy.error = nil
            } catch {
                guard privacyRequestID == requestID, privacy.optOut == nil else { return }
                privacy.error = "Couldn't read your privacy setting: \(AccountErrorText.describe(error))"
            }
        }
    }

    /// Applies the choice at once and rolls it back if the account service rejects it.
    func setCodingDataSharing(optedIn: Bool) {
        guard let store else { return }
        if let lock = privacy.lock {
            store.banner = lock.blockedNotice
            return
        }
        if pendingPrivacyWrite?.optedIn == optedIn { return }
        let currentlyOptedIn = privacy.optOut == false
        // Only an idle opt-in can be skipped: a displayed "out" may be the unconfirmed default.
        if optedIn, currentlyOptedIn, pendingPrivacyWrite == nil { return }
        let rollback = pendingPrivacyWrite?.rollbackOptOut ?? privacy.optOut
        pendingPrivacyWrite = (optedIn, rollback)
        privacyWriteSeq += 1
        let seq = privacyWriteSeq
        privacyRequestID = nil
        privacy.loading = false
        privacy.optOut = !optedIn
        privacy.pending = true
        privacy.error = nil
        Task {
            do {
                let client = try await accountConnection()
                let result = try ExtensionResponse.unwrap(try await client.request("_x.ai/privacy/setCodingDataRetention",
                                                                                   params: ["codingDataRetentionOptOut": !optedIn]))
                // Writes can finish out of order; only the newest may settle the value.
                guard seq == privacyWriteSeq else { return }
                let confirmed = result["codingDataRetentionOptOut"] as? Bool ?? !optedIn
                pendingPrivacyWrite = nil
                privacy.optOut = confirmed
                privacy.pending = false
                store.harnessMeta.authenticate["coding_data_retention_opt_out"] = confirmed
            } catch {
                guard seq == privacyWriteSeq else { return }
                pendingPrivacyWrite = nil
                privacy.optOut = rollback
                privacy.pending = false
                let message = "✗ Couldn't update coding data sharing: \(AccountErrorText.scrubbedForNotice(AccountErrorText.describe(error)))"
                privacy.error = message
                store.banner = message
            }
        }
    }

    // MARK: Sign out

    /// Signs out through the harness, which clears the credentials the CLI and Grok Desktop share.
    func signOut() async {
        guard let store, !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        do {
            let client = try await accountConnection()
            let result = try ExtensionResponse.unwrap(try await client.request("_x.ai/auth/logout", timeout: 30))
            store.banner = LogoutSummary(result).message
            // Idle connections still hold the old sign-in; the next prompt starts a fresh one and signs in again.
            for id in Array(store.clients.keys) where store.runs[id]?.isRunning != true && store.runs[id]?.isConfiguring != true {
                store.discardConnection(id)
            }
            releaseAccountConnection()
            store.catalogProjectID = nil
            store.commandCatalogProjectID = nil
            store.harnessMeta.authenticate = [:]
            privacy = AccountPrivacyState()
            pendingPrivacyWrite = nil
        } catch {
            store.banner = "Couldn't sign out: \(AccountErrorText.describe(error))"
        }
    }

    // MARK: Release notes

    func loadReleaseNotes() {
        guard let store else { return }
        let requestID = UUID()
        releaseNotesRequestID = requestID
        releaseNotes.isLoading = true
        releaseNotes.message = nil
        let knownVersion = store.harnessMeta.agentVersion
        let binary = store.binaryPath
        let home = grokHome()
        let download = downloadText
        Task {
            var version = knownVersion
            if version == nil { version = await ReleaseNotesLoader.cliVersion(binary: binary) }
            let loaded = await ReleaseNotesLoader.load(version: version, home: home, download: download)
            guard releaseNotesRequestID == requestID else { return }
            releaseNotes = ReleaseNotesState(version: version, markdown: loaded?.markdown, source: loaded?.source, isLoading: false,
                                             message: loaded == nil ? "No release notes available (offline)." : nil)
        }
    }

    // MARK: Announcements

    /// The banner's announcement: the first live critical one, else the first promo, skipping hidden ones.
    var currentAnnouncement: GrokAnnouncement? {
        AnnouncementRules.current(announcements, hidden: hiddenAnnouncementKeys, now: Date())
    }

    /// Whether `/announcements` has anything to act on. Hidden ones count, so `show` stays reachable.
    var hasSessionAnnouncements: Bool { !AnnouncementRules.sessionHideKeys(announcements, now: Date()).isEmpty }

    func applyAnnouncementsUpdate(_ params: [String: Any], now: Date = Date()) {
        let generation = (params["gen"] as? NSNumber)?.uint64Value ?? 0
        guard generation > announcementsGeneration else { return }
        announcementsGeneration = generation
        let list = (params["announcements"] as? [[String: Any]] ?? []).map(GrokAnnouncement.init).filter { !$0.isExpired(at: now) }
        announcements = list
        var hidden = readHiddenAnnouncements()
        if AnnouncementRules.prune(&hidden, active: list) { persistHiddenAnnouncements(hidden) }
        hiddenAnnouncementKeys = hidden
        scheduleAnnouncementExpiry()
    }

    /// Takes an announcement down when it expires, as the terminal's per-frame check does.
    private func scheduleAnnouncementExpiry() {
        announcementExpiry?.cancel()
        guard let next = announcements.compactMap(\.expiresAt).filter({ $0 > Date() }).min() else { return }
        announcementExpiry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, next.timeIntervalSinceNow) * 1_000_000_000) + 50_000_000)
            guard !Task.isCancelled, let self else { return }
            self.announcements = self.announcements.filter { !$0.isExpired(at: Date()) }
            self.scheduleAnnouncementExpiry()
        }
    }

    /// Hides the shown announcement when the server allows it. The terminal's hides are read first.
    func hideCurrentAnnouncement() {
        var hidden = readHiddenAnnouncements()
        guard let shown = AnnouncementRules.current(announcements, hidden: hidden, now: Date()), shown.isDismissible else {
            hiddenAnnouncementKeys = hidden
            return
        }
        hidden.insert(shown.hideKey)
        hiddenAnnouncementKeys = hidden
        persistHiddenAnnouncements(hidden)
    }

    /// Shows every current announcement again.
    func showAllAnnouncements() {
        let keys = Set(AnnouncementRules.sessionHideKeys(announcements, now: Date()))
        var hidden = readHiddenAnnouncements()
        let changed = !hidden.isDisjoint(with: keys)
        hidden.subtract(keys)
        hiddenAnnouncementKeys = hidden
        if changed { persistHiddenAnnouncements(hidden) }
    }

    func openAnnouncementAction(_ announcement: GrokAnnouncement) {
        guard let url = announcement.action?.url else { return }
        openURL(url)
    }

    /// The hidden set the terminal and Grok Desktop share, after this app's own queued writes.
    private func readHiddenAnnouncements() -> Set<String> {
        announcementWrites.sync {}
        return AnnouncementHiddenFile.read(home: grokHome())
    }

    private func persistHiddenAnnouncements(_ keys: Set<String>) {
        let home = grokHome()
        announcementWrites.async {
            do { try AnnouncementHiddenFile.write(keys, home: home) }
            catch { NSLog("Grok Desktop could not save hidden announcements: \(error.localizedDescription)") }
        }
    }

    /// Waits for queued writes to `announcements.json`; used by tests.
    func flushAnnouncementWrites() { announcementWrites.sync {} }
}

#if DEBUG
extension AccountFeatureModel {
    /// Puts panels into a given state without a harness, for snapshot tests.
    func showPreviewState(usage: UsageSheetState? = nil, privacy: AccountPrivacyState? = nil, releaseNotes: ReleaseNotesState? = nil,
                          drafts: FeedbackDraftListState? = nil, announcements: [GrokAnnouncement]? = nil) {
        if let usage { self.usage = usage }
        if let privacy { self.privacy = privacy }
        if let releaseNotes { self.releaseNotes = releaseNotes }
        if let drafts { feedbackDrafts = drafts }
        if let announcements { self.announcements = announcements; hiddenAnnouncementKeys = [] }
    }
}
#endif

// MARK: - Account facts

extension HarnessMeta {
    /// API-key sign-ins, whether reported by the account or implied by the offered methods.
    var usesAPIKeySignIn: Bool {
        if authenticate.isEmpty { return authMethods.contains { $0["id"] as? String == "xai.api_key" } }
        return [authMode, subscriptionTier].contains { $0.map(Self.isAPIKeyAuthLabel) ?? false }
    }
    /// A personal subscription: not a team, not billed by a backend, not an API key or an external sign-in.
    var showsConsumerBilling: Bool { teamName == nil && !backendBilled && !usesAPIKeySignIn && !usesExternalProvider }
    /// External sign-in providers never reach grok.com billing, so `/usage` is refused there.
    var allowsUsageCommand: Bool { !usesExternalProvider }
    var sessionInfoAuthMethod: AccountAuthDescription {
        guard usesAPIKeySignIn else { return AccountAuthDescription(method: "OAuth", note: nil) }
        let fromEnvironment = !(ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        return AccountAuthDescription(method: fromEnvironment ? "API key (XAI_API_KEY)" : "API key",
                                      note: "Run `grok login` to use your SuperGrok subscription instead.")
    }

    static func isAPIKeyAuthLabel(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "") == "apikey"
    }
}

struct AccountAuthDescription: Equatable {
    var method: String
    var note: String?
}

/// Error text for notices. Harness errors carry their detail in JSON-RPC `data`.
enum AccountErrorText {
    static func describe(_ error: Error) -> String {
        if case ACPClientError.remote(_, let message, let data) = error {
            if let text = data as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
            if let object = data as? [String: Any], let text = object["message"] as? String ?? object["error"] as? String, !text.isEmpty { return text }
            return message
        }
        return error.localizedDescription
    }

    /// The terminal's rule for server text in a one-line notice: long or control-laden text is replaced.
    static func scrubbedForNotice(_ error: String) -> String {
        let unsafe = error.unicodeScalars.contains { scalar in
            scalar.properties.generalCategory == .control || (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
        }
        return error.utf8.count > 120 || unsafe ? "server error (see logs for details)" : error
    }
}

/// `_x.ai/auth/logout` reply, summarised the way `grok logout` does.
struct LogoutSummary: Equatable {
    var wasLoggedIn: Bool
    var email: String?
    var apiKeyStillSet: Bool

    init(_ result: [String: Any]) {
        wasLoggedIn = result["was_logged_in"] as? Bool ?? false
        email = (result["email"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        apiKeyStillSet = result["api_key_still_set"] as? Bool ?? false
    }

    var message: String {
        var parts: [String]
        if !wasLoggedIn {
            parts = ["No cached session to log out of."]
            if apiKeyStillSet { parts.append("You are authenticated via XAI_API_KEY (environment variable).") }
        } else {
            parts = [email.map { "Logged out (was signed in as \($0))." } ?? "Logged out."]
            if apiKeyStillSet { parts.append("XAI_API_KEY is still set and will be used for authentication.") }
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Settings

/// Privacy and sign-out rows in the Accounts section of Settings.
struct AccountSettingsExtras: View {
    @EnvironmentObject var account: AccountFeatureModel
    @State private var confirmSignOut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            PrivacyChoiceView(compact: true)
            Divider()
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 20)).foregroundStyle(Theme.muted).frame(width: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sign out of xAI").font(.system(size: 14, weight: .semibold))
                    Text("Removes the saved sign-in that Grok Desktop shares with the Grok CLI.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(account.isSigningOut ? "Signing out…" : "Sign Out…") { confirmSignOut = true }
                    .buttonStyle(.bordered).controlSize(.regular)
                    .disabled(account.isSigningOut)
            }
        }
        .onAppear { account.refreshPrivacy() }
        .onDisappear { account.releaseAccountConnectionSoon() }
        .alert("Sign out of xAI?", isPresented: $confirmSignOut) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) { Task { await account.signOut() } }
        } message: {
            Text("Grok Desktop and the Grok CLI share this sign-in. Running tasks keep going; new prompts will ask you to sign in again.")
        }
    }
}
