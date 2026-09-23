import AppKit
import AVFoundation
import Speech
import SwiftUI

// Dictation (`/voice`) streams 16 kHz mono PCM16LE to xAI speech-to-text, as the terminal does
// (crates/codegen/xai-grok-voice), with on-device Speech recognition when there is no xAI credential.

// MARK: - Speech-to-text protocol

/// A server message from `wss://api.x.ai/v1/stt` (xai-grok-voice stt/types.rs).
enum VoiceSTTEvent: Equatable {
    case created
    case partial(text: String, isFinal: Bool, speechFinal: Bool)
    case done(text: String)
    case error(String)
    case unknown

    static func parse(_ text: String) -> VoiceSTTEvent {
        guard let data = text.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .error("parse error: expected a JSON object")
        }
        guard let type = object["type"] as? String else { return .error("parse error: missing field `type`") }
        switch type {
        case "transcript.created": return .created
        case "transcript.partial":
            return .partial(text: object["text"] as? String ?? "", isFinal: object["is_final"] as? Bool ?? false,
                            speechFinal: object["speech_final"] as? Bool ?? false)
        case "transcript.done": return .done(text: object["text"] as? String ?? "")
        case "error": return .error(object["message"] as? String ?? "")
        default: return .unknown
        }
    }
}

/// Turns partial transcripts into the grey preview and the finalized text inserted in the prompt.
/// Chunk deltas marked `is_final` are stitched into the preview so a long, pauseless utterance keeps
/// growing; the prompt only receives `speech_final` (or `transcript.done`) text (pipeline.rs).
struct VoiceTranscriptAssembler {
    enum Update: Equatable {
        case interim(String)
        case final(String)
    }
    private(set) var lockedPrefix = ""

    mutating func apply(_ event: VoiceSTTEvent) -> Update? {
        switch event {
        case .partial(let text, let isFinal, let speechFinal):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if speechFinal { lockedPrefix = ""; return .final(trimmed) }
            if isFinal {
                if !lockedPrefix.isEmpty { lockedPrefix += " " }
                lockedPrefix += trimmed
                return .interim(lockedPrefix)
            }
            return .interim(lockedPrefix.isEmpty ? trimmed : lockedPrefix + " " + trimmed)
        case .done(let text):
            lockedPrefix = ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .final(trimmed)
        case .created, .error, .unknown:
            return nil
        }
    }
}

/// Where and how dictated text lands in the prompt (P/voice/handle.rs).
enum VoiceTextInsertion {
    /// Adds a leading and/or trailing space around `fragment` only where the neighbouring
    /// character at `location` (UTF-16) is not whitespace, so the fragment reads as its own words.
    static func spaced(_ fragment: String, in text: String, at location: Int) -> String {
        let string = text as NSString
        let location = min(max(0, location), string.length)
        let whitespace = CharacterSet.whitespacesAndNewlines
        func isSpace(_ index: Int) -> Bool {
            guard let scalar = UnicodeScalar(string.character(at: index)) else { return false }
            return whitespace.contains(scalar)
        }
        let leading = location > 0 && !isSpace(location - 1)
        let trailing = location < string.length && !isSpace(location)
        return (leading ? " " : "") + fragment + (trailing ? " " : "")
    }

    /// The prompt after replacing `range` (the selection, or the caret) with `fragment`, and the
    /// caret after it. A blank draft is replaced outright.
    static func merge(_ fragment: String, into existing: String, replacing range: NSRange?) -> (text: String, caret: Int) {
        if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return (fragment, (fragment as NSString).length) }
        let string = existing as NSString
        let start = min(max(0, range?.location ?? string.length), string.length)
        let end = min(string.length, start + max(0, range?.length ?? 0))
        let base = string.replacingCharacters(in: NSRange(location: start, length: end - start), with: "")
        let insertion = spaced(fragment, in: base, at: start)
        let merged = (base as NSString).replacingCharacters(in: NSRange(location: start, length: 0), with: insertion)
        return (merged, start + (insertion as NSString).length)
    }
}

/// Endpoint and language settings (`[voice]`, `[endpoints].xai_api_base_url`, `[ui].voice_stt_language`).
struct VoiceSTTSettings: Equatable {
    var apiBase = "https://api.x.ai"
    var path = "/v1/stt"
    var language = "en"
    var sampleRate = 16_000
    var endpointingMS = 400
    var interimResults = true

    static let clientIdentifier = "grok-desktop"

    init() {}

    init(config: GrokConfig) {
        let base = config.string("api_base", in: "voice")?.trimmingCharacters(in: .whitespaces)
        let endpoints = config.string("xai_api_base_url", in: "endpoints")?.trimmingCharacters(in: .whitespaces)
        if let value = [base, endpoints].compactMap({ $0 }).first(where: { !$0.isEmpty }) {
            apiBase = String(value.reversed().drop(while: { $0 == "/" }).reversed())
        }
        if let value = config.string("stt_ws_path", in: "voice"), !value.isEmpty { path = value }
        language = config.string("voice_stt_language", in: "ui") ?? config.string("language", in: "voice") ?? "en"
        if let value = config.int("sample_rate", in: "voice"), value > 0 { sampleRate = value }
        if let value = config.int("stt_endpointing_ms", in: "voice"), value >= 0 { endpointingMS = value }
        if let value = config.bool("stt_interim_results", in: "voice") { interimResults = value }
    }

    /// The WebSocket URL. Plaintext bases are refused so the bearer never travels unencrypted (config.rs).
    func url() throws -> URL {
        let base = apiBase.trimmingCharacters(in: .whitespaces)
        let trimmedBase = String(base.reversed().drop(while: { $0 == "/" }).reversed())
        let lower = trimmedBase.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("ws://") {
            throw ComposerCommandMessage("insecure voice api_base \"\(apiBase)\": voice requires a TLS endpoint (https:// / wss://). Refusing to send the bearer token over a plaintext connection.")
        }
        var rest = trimmedBase
        for scheme in ["https://", "wss://"] where lower.hasPrefix(scheme) { rest = String(trimmedBase.dropFirst(scheme.count)) }
        var path = String(self.path.trimmingCharacters(in: .whitespaces).drop(while: { $0 == "/" }))
        if rest.hasSuffix("/v1"), path.hasPrefix("v1/") { path = String(path.dropFirst(3)) }
        guard var components = URLComponents(string: "wss://\(rest)/\(path)") else {
            throw ComposerCommandMessage("bad STT URL: wss://\(rest)/\(path)")
        }
        components.queryItems = [
            URLQueryItem(name: "sample_rate", value: String(sampleRate)),
            URLQueryItem(name: "encoding", value: "pcm"),
            URLQueryItem(name: "interim_results", value: interimResults ? "true" : "false"),
            URLQueryItem(name: "language", value: Self.languageForAPI(language)),
            URLQueryItem(name: "endpointing", value: String(endpointingMS)),
        ]
        guard let url = components.url else { throw ComposerCommandMessage("bad STT URL: wss://\(rest)/\(path)") }
        return url
    }

    /// Grok speech-to-text languages (xai-grok-voice language.rs), sorted by English name.
    static let languages: [(code: String, name: String)] = [
        ("ar", "Arabic"), ("cs", "Czech"), ("da", "Danish"), ("nl", "Dutch"), ("en", "English"), ("fil", "Filipino"),
        ("fr", "French"), ("de", "German"), ("hi", "Hindi"), ("id", "Indonesian"), ("it", "Italian"), ("ja", "Japanese"),
        ("ko", "Korean"), ("mk", "Macedonian"), ("ms", "Malay"), ("fa", "Persian"), ("pl", "Polish"), ("pt", "Portuguese"),
        ("ro", "Romanian"), ("ru", "Russian"), ("es", "Spanish"), ("sv", "Swedish"), ("th", "Thai"), ("tr", "Turkish"),
        ("vi", "Vietnamese"),
    ]

    /// A catalog code, or "auto"; blank and unknown values become "en" (canonicalize_stt_language).
    static func canonicalLanguage(_ value: String?) -> String {
        let raw = (value ?? "").trimmingCharacters(in: .whitespaces)
        if raw.isEmpty { return "en" }
        if raw.lowercased() == "auto" { return "auto" }
        func match(_ code: String) -> String? { languages.first { $0.code.caseInsensitiveCompare(code) == .orderedSame }?.code }
        if let code = match(raw) { return code }
        let primary = raw.split(whereSeparator: { "_-.".contains($0) }).first.map(String.init) ?? ""
        if let code = match(primary) { return code }
        return primary.lowercased() == "tl" ? "fil" : "en"
    }

    /// The concrete code sent to the API; "auto" follows the system language.
    static func languageForAPI(_ stored: String, preferred: [String] = Locale.preferredLanguages) -> String {
        let canonical = canonicalLanguage(stored)
        guard canonical == "auto" else { return canonical }
        for identifier in preferred {
            let code = canonicalLanguage(identifier)
            if code != "en" || identifier.lowercased().hasPrefix("en") { return code }
        }
        return "en"
    }
}

// MARK: - Audio

/// Converts microphone buffers to 16 kHz mono signed 16-bit little-endian PCM.
final class VoicePCMConverter {
    let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private let inputFormat: AVAudioFormat

    init?(inputFormat: AVAudioFormat, sampleRate: Double = 16_000) {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: output) else { return nil }
        converter.downmix = true
        self.inputFormat = inputFormat
        self.outputFormat = output
        self.converter = converter
    }

    /// Converts one buffer; the resampler keeps its state between calls, as a stream needs.
    func convert(_ buffer: AVAudioPCMBuffer) -> Data {
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard buffer.frameLength > 0, let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return Data() }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied { inputStatus.pointee = .noDataNow; return nil }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let samples = output.int16ChannelData, output.frameLength > 0 else { return Data() }
        var data = Data(capacity: Int(output.frameLength) * 2)
        for index in 0..<Int(output.frameLength) {
            var little = samples[0][index].littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// Clamps a float sample to the signed 16-bit range.
    static func int16(_ sample: Float) -> Int16 {
        let clamped = max(-1, min(1, sample))
        return Int16(clamped < 0 ? clamped * 32_768 : clamped * 32_767)
    }
}

/// Groups PCM into ~64 ms frames (1,024 samples at 16 kHz) for the socket.
struct VoicePCMChunker {
    let frameBytes: Int
    private var pending = Data()

    init(frameBytes: Int = 2_048) { self.frameBytes = frameBytes }

    mutating func append(_ data: Data) -> [Data] {
        pending.append(data)
        var frames: [Data] = []
        while pending.count >= frameBytes {
            frames.append(Data(pending.prefix(frameBytes)))
            pending = Data(pending.dropFirst(frameBytes))
        }
        return frames
    }

    mutating func flush() -> Data? {
        defer { pending = Data() }
        return pending.isEmpty ? nil : pending
    }
}

/// The microphone tap. Its block runs on a real-time audio thread.
final class VoiceAudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var running = false

    func start(_ onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw ComposerCommandMessage("No microphone is available.") }
        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { buffer, _ in onBuffer(buffer) }
        engine.prepare()
        do { try engine.start() } catch { input.removeTap(onBus: 0); throw error }
        running = true
    }

    func stop() {
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}

/// Converts and frames audio on the capture thread, then hands frames to the socket.
private final class VoiceAudioPipe: @unchecked Sendable {
    private let lock = NSLock()
    private var converter: VoicePCMConverter?
    private var chunker = VoicePCMChunker()
    private let sampleRate: Double
    private let send: (Data) -> Void

    init(sampleRate: Double, send: @escaping (Data) -> Void) {
        self.sampleRate = sampleRate
        self.send = send
    }

    func push(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        if converter == nil { converter = VoicePCMConverter(inputFormat: buffer.format, sampleRate: sampleRate) }
        let frames = converter.map { chunker.append($0.convert(buffer)) } ?? []
        lock.unlock()
        frames.forEach(send)
    }

    func flush() {
        lock.lock()
        let rest = chunker.flush()
        lock.unlock()
        if let rest { send(rest) }
    }
}

// MARK: - Socket

/// One streaming session with xAI speech-to-text: audio captured before `transcript.created`
/// waits in a bounded backlog, then streams in order; `audio.done` ends the utterance.
private final class VoiceSTTConnection: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var ready = false
    private var ended = false
    private var closed = false
    private var backlog: [Data] = []
    private let onOpen: () -> Void
    private let onEvent: (VoiceSTTEvent) -> Void
    private let onFailure: (String) -> Void

    init(onOpen: @escaping () -> Void, onEvent: @escaping (VoiceSTTEvent) -> Void, onFailure: @escaping (String) -> Void) {
        self.onOpen = onOpen
        self.onEvent = onEvent
        self.onFailure = onFailure
    }

    func connect(url: URL, token: String) {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(VoiceSTTSettings.clientIdentifier, forHTTPHeaderField: "x-grok-client-identifier")
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        lock.lock(); self.session = session; self.task = task; lock.unlock()
        task.resume()
        receive(task)
    }

    private func receive(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.string(let text)):
                self.onEvent(VoiceSTTEvent.parse(text))
                self.receive(task)
            case .success:
                self.receive(task)
            case .failure(let error):
                self.lock.lock(); let closed = self.closed; self.lock.unlock()
                // Tearing the socket down ends the receive loop with an error; that is not news.
                if !closed { self.onFailure("connection lost: \(error.localizedDescription)") }
            }
        }
    }

    func markReady() {
        lock.lock()
        ready = true
        let queued = backlog
        backlog = []
        let task = self.task
        let ended = self.ended
        lock.unlock()
        for frame in queued { task?.send(.data(frame)) { _ in } }
        if ended { task?.send(.string(#"{"type":"audio.done"}"#)) { _ in } }
    }

    func send(_ frame: Data) {
        lock.lock()
        guard !ended, !closed else { lock.unlock(); return }
        if !ready {
            if backlog.count == 1_024 { backlog.removeFirst() }
            backlog.append(frame)
            lock.unlock()
            return
        }
        let task = self.task
        lock.unlock()
        task?.send(.data(frame)) { _ in }
    }

    /// Stop accepting audio and tell the server the utterance is over.
    func finishAudio() {
        lock.lock()
        guard !ended else { lock.unlock(); return }
        ended = true
        let task = ready ? self.task : nil
        lock.unlock()
        task?.send(.string(#"{"type":"audio.done"}"#)) { _ in }
    }

    func close() {
        lock.lock()
        closed = true
        let task = self.task, session = self.session
        self.task = nil; self.session = nil; backlog = []
        lock.unlock()
        task?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) { onOpen() }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let closed = self.closed; let wasReady = ready; lock.unlock()
        guard !closed, let error else { return }
        if let response = task.response as? HTTPURLResponse, response.statusCode >= 400 {
            onFailure("connect: HTTP \(response.statusCode)")
        } else {
            onFailure(wasReady ? "connection lost: \(error.localizedDescription)" : "connect: \(error.localizedDescription)")
        }
    }
}

// MARK: - Dictation controller

/// Microphone capture and transcription for the composer. Everything published here changes only
/// while dictating, and only the recording row and microphone button observe it.
@MainActor
final class VoiceDictationController: ObservableObject {
    enum Phase: Equatable { case idle, starting, recording, finishing }
    enum Engine: Equatable { case xai, onDevice }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var engine: Engine = .xai
    /// Words heard but not final yet, shown in grey.
    @Published private(set) var interim = ""

    var isActive: Bool { phase != .idle }

    /// Receives finalized text to insert at the cursor.
    var insertFinal: ((String) -> Void)?
    /// Receives a one-line message for the banner.
    var report: ((String) -> Void)?

    static let noSpeechTimeout: TimeInterval = 10
    private var session = UUID()
    private var capture: VoiceAudioCapture?
    private var pipe: VoiceAudioPipe?
    private var connection: VoiceSTTConnection?
    private var assembler = VoiceTranscriptAssembler()
    private var heardSpeech = false
    private var timers: [Task<Void, Never>] = []
    private var recognition: VoiceOnDeviceRecognition?

    /// The app bundle declares why it needs the microphone. Without it macOS terminates the
    /// process on the first capture, so an unbundled build must not touch the microphone.
    static var canRequestMicrophone: Bool { infoBundle.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") is String }
    static var canRequestSpeechRecognition: Bool { infoBundle.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") is String }
    /// The bundle whose Info.plist declares the usage descriptions.
    static var infoBundle = Bundle.main

    /// Asks for microphone access when macOS has not asked yet.
    static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// Whether this Mac can transcribe `language` without sending audio anywhere, asking for
    /// speech recognition access when macOS has not asked yet.
    static func prepareOnDeviceRecognition(language: String) async -> Bool {
        guard canRequestSpeechRecognition, VoiceOnDeviceRecognition.isAvailable(language: language) else { return false }
        let status: SFSpeechRecognizerAuthorizationStatus
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        } else {
            status = SFSpeechRecognizer.authorizationStatus()
        }
        return status == .authorized
    }

    /// Marks the controller as preparing (fetching a token and permissions) so the UI responds at once.
    func beginStarting() {
        session = UUID()
        phase = .starting
        interim = ""
    }

    /// Stops without keeping anything that has not been finalized.
    func cancel() {
        session = UUID()
        teardown()
    }

    /// Streams to xAI speech-to-text.
    func startXAI(token: String, settings: VoiceSTTSettings) {
        let id = UUID()
        session = id
        do {
            let url = try settings.url()
            engine = .xai
            assembler = VoiceTranscriptAssembler()
            heardSpeech = false
            readyForAudio = false
            let connection = VoiceSTTConnection(
                onOpen: { [weak self] in DispatchQueue.main.async { self?.socketOpened(session: id) } },
                onEvent: { [weak self] event in DispatchQueue.main.async { self?.receive(event, session: id) } },
                onFailure: { [weak self] message in DispatchQueue.main.async { self?.fail(message, session: id) } })
            self.connection = connection
            connection.connect(url: url, token: token)
            // Open the microphone while the socket connects; frames wait in the backlog.
            let pipe = VoiceAudioPipe(sampleRate: Double(settings.sampleRate)) { [weak connection] frame in connection?.send(frame) }
            self.pipe = pipe
            let capture = VoiceAudioCapture()
            try capture.start { buffer in pipe.push(buffer) }
            self.capture = capture
            phase = .recording
            armNoSpeechWatchdog(session: id)
            // The handshake may take up to 15 s and `transcript.created` 10 s more (streaming.rs).
            schedule(after: 25, session: id) { controller in
                if !controller.readyForAudio { controller.fail("STT: timed out waiting for transcript.created", session: id) }
            }
        } catch {
            fail((error as? ComposerCommandMessage)?.text ?? error.localizedDescription, session: id)
        }
    }

    /// Transcribes on this Mac with the Speech framework.
    func startOnDevice(language: String) {
        let id = UUID()
        session = id
        engine = .onDevice
        heardSpeech = false
        let recognition = VoiceOnDeviceRecognition(language: language) { [weak self] update in
            DispatchQueue.main.async { self?.receiveOnDevice(update, session: id) }
        }
        do {
            try recognition.start()
            self.recognition = recognition
            phase = .recording
            armNoSpeechWatchdog(session: id)
        } catch {
            fail((error as? ComposerCommandMessage)?.text ?? error.localizedDescription, session: id)
        }
    }

    /// Stops listening but keeps the words still being transcribed; they land when final.
    func stop() {
        guard phase == .recording || phase == .starting else { return }
        guard phase == .recording else { cancel(); return }
        phase = .finishing
        capture?.stop()
        pipe?.flush()
        connection?.finishAudio()
        recognition?.finish()
        let id = session
        schedule(after: 5, session: id) { controller in controller.completeFinishing() }
    }

    /// Enter while dictating: take the pending words now and stop without waiting for a final.
    func stopForSubmit() -> String? {
        let pending = interim.trimmingCharacters(in: .whitespacesAndNewlines)
        cancel()
        return pending.isEmpty ? nil : pending
    }

    private var readyForAudio = false

    private func socketOpened(session id: UUID) {
        guard id == session else { return }
        // The server must say `transcript.created` within ten seconds of the handshake.
        schedule(after: 10, session: id) { controller in
            if !controller.readyForAudio { controller.fail("STT: timed out waiting for transcript.created", session: id) }
        }
    }

    private func receive(_ event: VoiceSTTEvent, session id: UUID) {
        guard id == session else { return }
        switch event {
        case .created:
            readyForAudio = true
            connection?.markReady()
        case .error(let message):
            fail(message.isEmpty ? "STT error" : message, session: id)
        default:
            if let update = assembler.apply(event) { apply(update) }
            if case .done = event, phase == .finishing { completeFinishing() }
        }
    }

    private func receiveOnDevice(_ update: VoiceOnDeviceRecognition.Update, session id: UUID) {
        guard id == session else { return }
        switch update {
        case .partial(let text): apply(.interim(text))
        case .final(let text):
            if !text.isEmpty { apply(.final(text)) }
            if phase == .finishing { completeFinishing() }
        case .failed(let message):
            if phase == .finishing { completeFinishing() } else { fail(message, session: id) }
        }
    }

    private func apply(_ update: VoiceTranscriptAssembler.Update) {
        switch update {
        case .interim(let text):
            heardSpeech = true
            if interim != text { interim = text }
        case .final(let text):
            heardSpeech = true
            interim = ""
            insertFinal?(text)
        }
    }

    private func completeFinishing() {
        guard phase == .finishing else { return }
        // Words still pending when the service goes quiet are kept rather than lost.
        let pending = interim.trimmingCharacters(in: .whitespacesAndNewlines)
        interim = ""
        if !pending.isEmpty { insertFinal?(pending) }
        session = UUID()
        teardown()
    }

    private func armNoSpeechWatchdog(session id: UUID) {
        schedule(after: Self.noSpeechTimeout, session: id) { controller in
            guard !controller.heardSpeech, controller.phase == .recording else { return }
            controller.fail("No speech was detected. Voice stopped.", session: id)
        }
    }

    private func fail(_ message: String, session id: UUID) {
        guard id == session, phase != .idle else { return }
        session = UUID()
        teardown()
        report?("Voice: \(message)")
    }

    private func schedule(after seconds: TimeInterval, session id: UUID, _ action: @escaping (VoiceDictationController) -> Void) {
        timers.append(Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.session == id else { return }
            action(self)
        })
    }

    private func teardown() {
        timers.forEach { $0.cancel() }
        timers = []
        capture?.stop(); capture = nil
        pipe = nil
        connection?.close(); connection = nil
        recognition?.cancel(); recognition = nil
        readyForAudio = false
        interim = ""
        phase = .idle
    }

    /// Shows a fixed recording state, for rendering snapshots of the composer.
    func showPreview(phase: Phase, engine: Engine = .xai, interim: String = "") {
        self.phase = phase
        self.engine = engine
        self.interim = interim
    }
}

/// On-device speech recognition, used when the account has no xAI credential for voice.
private final class VoiceOnDeviceRecognition: @unchecked Sendable {
    enum Update { case partial(String), final(String), failed(String) }

    private let lock = NSLock()
    private let language: String
    private let deliver: (Update) -> Void
    private let capture = VoiceAudioCapture()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finishing = false

    init(language: String, deliver: @escaping (Update) -> Void) {
        self.language = language
        self.deliver = deliver
    }

    static func isAvailable(language: String) -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: locale(for: language)) else { return false }
        return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
    }

    /// Speech models are per region: prefer the Mac's own region for the language, then any.
    static func locale(for language: String) -> Locale {
        let supported = SFSpeechRecognizer.supportedLocales()
        let current = Locale.current
        func code(_ locale: Locale) -> String? { locale.language.languageCode?.identifier }
        let candidates = supported.filter { code($0) == language }
        if code(current) == language, let match = candidates.first(where: { $0.region == current.region }) { return match }
        // Otherwise the language's most likely region, such as en → US or pt → BR.
        let likely = Locale.Language(identifier: Locale.Language(identifier: language).maximalIdentifier).region
        return candidates.first { $0.region == likely } ?? candidates.min { $0.identifier < $1.identifier } ?? Locale(identifier: language)
    }

    func start() throws {
        guard let recognizer = SFSpeechRecognizer(locale: Self.locale(for: language)), recognizer.supportsOnDeviceRecognition else {
            throw ComposerCommandMessage("on-device dictation is not available for this language")
        }
        self.recognizer = recognizer
        beginTask()
        try capture.start { [weak self] buffer in
            guard let self else { return }
            self.lock.lock(); let request = self.request; self.lock.unlock()
            request?.append(buffer)
        }
    }

    private func beginTask() {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Audio never leaves this Mac on the fallback path.
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        lock.lock(); self.request = request; lock.unlock()
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                if result.isFinal {
                    self.deliver(.final(text))
                    self.lock.lock(); let finishing = self.finishing; self.lock.unlock()
                    // Recognition ends an utterance after a long pause; keep listening with a new one.
                    if !finishing { self.beginTask() }
                } else if !text.isEmpty {
                    self.deliver(.partial(text))
                }
            } else if let error {
                self.deliver(.failed(error.localizedDescription))
            }
        }
        lock.lock(); self.task = task; lock.unlock()
    }

    func finish() {
        lock.lock(); finishing = true; let request = self.request; lock.unlock()
        capture.stop()
        request?.endAudio()
    }

    func cancel() {
        lock.lock(); finishing = true; let task = self.task; lock.unlock()
        capture.stop()
        task?.cancel()
    }
}

// MARK: - Recording row

/// "Recording" above the prompt: a pulsing dot, the words heard so far, and Stop.
struct VoiceRecordingRow: View {
    @ObservedObject var voice: VoiceDictationController
    var onStop: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        if voice.isActive {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Circle().fill(ComposerPalette.recording).frame(width: 8, height: 8)
                    .opacity(voice.phase == .recording && pulse ? 0.35 : 1)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
                    .accessibilityHidden(true)
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink).fixedSize()
                Text(voice.interim.isEmpty ? placeholder : voice.interim)
                    .font(.system(size: 13)).foregroundStyle(Theme.muted.opacity(voice.interim.isEmpty ? 0.7 : 1))
                    .lineLimit(2).truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onStop) {
                    Label("Stop", systemImage: "stop.fill").labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Theme.hover, in: Capsule())
                }.buttonStyle(.plain).help("Stop dictation · esc").accessibilityLabel("Stop dictation")
                    .disabled(voice.phase == .finishing)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(ComposerPalette.recording.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ComposerPalette.recording.opacity(0.25), lineWidth: 0.5))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Dictation: \(title)")
        }
    }

    private var title: String {
        switch voice.phase {
        case .starting: return "Starting…"
        case .finishing: return "Finishing…"
        default: return voice.engine == .onDevice ? "Recording · On this Mac" : "Recording"
        }
    }

    private var placeholder: String {
        voice.phase == .starting ? "Getting the microphone ready" : "Speak — words appear at the cursor. ↵ sends, esc stops."
    }
}

/// The microphone button in the composer controls.
struct VoiceMicButton: View {
    @ObservedObject var voice: VoiceDictationController
    var shortcut: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: voice.isActive ? "mic.fill" : "mic")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(voice.isActive ? ComposerPalette.recording : Theme.ink)
                .frame(width: 36, height: 40).contentShape(Circle())
        }
        .buttonStyle(ComposerControlStyle())
        .help(voice.isActive ? "Stop dictation" : "Dictate" + (shortcut.map { " · \($0)" } ?? ""))
        .accessibilityLabel(voice.isActive ? "Stop dictation" : "Dictate")
    }
}
