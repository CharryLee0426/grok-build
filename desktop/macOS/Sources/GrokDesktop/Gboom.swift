import AppKit
import SwiftUI

// `/gboom`: the hidden raycasting easter egg, ported from `xai-grok-gboom`. The session below is
// `lib.rs` (phases, input, the fire title and end screens); the game, renderer, and art live in
// GboomGame.swift, GboomEngine.swift, and GboomAssets.swift. The terminal streams PNG frames into
// a modal; here the same RGB frames go straight into a layer with nearest-neighbour scaling.

/// Where the player is in the easter egg's flow.
enum GboomPhase: Equatable { case title, playing, won, dead }

/// A key, reduced to what the game distinguishes.
enum GboomKey: Equatable {
    case character(Character)
    case up, down, left, right, escape, space, enter, other
}

enum GboomKeyOutcome: Equatable { case close, changed }

/// The status bar's values.
struct GboomHUD: Equatable {
    var hp = GboomTuning.playerMaxHP
    var kills = 0
    var total = 0
    var playing = false

    /// `" HP <n> · KILLS k/total "`, the terminal's HUD text (health left-aligned in three columns).
    var statsText: String {
        let health = String(hp)
        return " HP \(health)\(String(repeating: " ", count: max(0, 3 - health.count))) · KILLS \(kills)/\(total) "
    }

    var hint: String { playing ? " WASD/←→ move · SPACE fire · ESC quit " : " ESC quit " }

    /// Green when comfortable, amber when hurting, GBOOM red when critical.
    var healthColor: GboomRGB {
        hp > 60 ? GboomRGB(126, 200, 96) : hp > 30 ? GboomRGB(235, 198, 82) : GboomPalette.red
    }
}

/// One play-through: the phase machine around the game, the fire screens, and the frame renderer.
final class GboomSession {
    static let maxFrameWidth = 480
    static let maxFrameHeight = 320
    /// Longest simulation step; longer gaps (lag, a paused window) are clamped.
    static let maxStep: Float = 0.1
    /// End screens ignore keys this long so a key held at the moment of death does not dismiss them.
    static let endScreenGrace: Float = 0.8
    /// Radians of yaw per terminal column of mouse motion, and the jump beyond which motion is ignored.
    static let mouseAimSensitivity: Float = 0.06
    static let maxMouseAimColumns: Float = 12
    /// The terminal renders 8 frame pixels per cell column; desktop mouse motion is scaled to match.
    static let pixelsPerColumn: Float = 8
    static let textOutline = GboomRGB(16, 6, 6)

    var game = GboomGame()
    private(set) var phase: GboomPhase = .title
    /// Time spent in the current phase.
    private(set) var phaseTime: Float = 0
    private(set) var fire = GboomFireSim()
    let framebuffer = GboomFrameBuffer()
    private let renderer = GboomRenderer()
    private let clock: () -> TimeInterval
    private var lastTick: TimeInterval

    init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
        lastTick = clock()
        // macOS reports key releases, so controls latch on press and clear on release, letting the
        // player move and turn at once (the terminal's release-aware mode).
        game.releaseAware = true
    }

    var hud: GboomHUD { GboomHUD(hp: game.player.hp, kills: game.kills, total: game.totalImps, playing: phase == .playing) }

    /// Advances by wall-clock time since the last tick, capped at `maxStep`.
    func tick() {
        let now = clock()
        let dt = Float(min(max(now - lastTick, 0), Double(Self.maxStep)))
        lastTick = now
        advance(dt)
    }

    /// Restarts the wall clock, so a pause does not count as elapsed game time.
    func resetClock() { lastTick = clock() }

    /// Advances the phase machine by `dt` seconds.
    func advance(_ dt: Float) {
        phaseTime += dt
        switch phase {
        case .title, .won, .dead:
            fire.step()
        case .playing:
            game.step(dt)
            if game.dead { setPhase(.dead) }
            // Waiting for every corpse to settle lets the last death animation play out before the win screen.
            else if game.won && game.imps.allSatisfy({ $0.state == .dead }) { setPhase(.won) }
        }
    }

    private func setPhase(_ phase: GboomPhase) {
        self.phase = phase
        phaseTime = 0
    }

    static func control(for key: GboomKey) -> GboomControl? {
        switch key {
        case .character(let c) where c == "w" || c == "W": return .forward
        case .up: return .forward
        case .character(let c) where c == "s" || c == "S": return .back
        case .down: return .back
        case .character(let c) where c == "a" || c == "A": return .strafeLeft
        case .character(let c) where c == "d" || c == "D": return .strafeRight
        case .left: return .turnLeft
        case .right: return .turnRight
        default: return nil
        }
    }

    /// A key press. `isRepeat` marks auto-repeats, which never start or dismiss a screen.
    @discardableResult
    func handleKeyDown(_ key: GboomKey, isRepeat: Bool = false) -> GboomKeyOutcome {
        // Esc and q quit in every phase.
        if key == .escape || key == .character("q") || key == .character("Q") { return .close }
        switch phase {
        case .title:
            guard !isRepeat else { break }
            setPhase(.playing)
            resetClock()
        case .playing:
            if let control = Self.control(for: key) { game.press(control) }
            else if key == .space || key == .enter { game.queueFire() }
        case .won, .dead:
            if !isRepeat && phaseTime > Self.endScreenGrace { return .close }
        }
        return .changed
    }

    /// A key release stops that motion.
    func handleKeyUp(_ key: GboomKey) {
        guard phase == .playing, let control = Self.control(for: key) else { return }
        game.release(control)
    }

    /// Mouse motion aims while playing. `columns` is the motion in terminal columns (8 frame pixels);
    /// a jump beyond `maxMouseAimColumns` is treated as a discontinuity and ignored.
    func aim(columns: Float) {
        guard phase == .playing, columns != 0, abs(columns) <= Self.maxMouseAimColumns else { return }
        game.player.angle += columns * Self.mouseAimSensitivity
    }

    /// A left click fires while playing, through the same queue as Space.
    func click() {
        if phase == .playing { game.queueFire() }
    }

    /// Un-latches every control, for focus loss.
    func releaseAll() { game.releaseAll() }

    /// The internal frame size for a view: the view's aspect ratio scaled into the 480×320 box.
    static func frameSize(for size: CGSize) -> (width: Int, height: Int) {
        let width = max(Double(size.width), 64), height = max(Double(size.height), 64)
        let scale = min(Double(maxFrameWidth) / width, Double(maxFrameHeight) / height)
        return (max(Int((width * scale).rounded()), 64), max(Int((height * scale).rounded()), 64))
    }

    /// Renders the current phase into `framebuffer`.
    func render(width: Int, height: Int, paused: Bool = false) {
        guard width >= 8, height >= 8 else { return }
        framebuffer.resize(width, height)
        switch phase {
        case .title: renderTitle()
        case .playing: renderer.renderGame(framebuffer, game)
        case .won: renderEnd("VICTORY!", color: GboomRGB(255, 214, 80))
        case .dead: renderEnd("YOU DIED", color: GboomPalette.red)
        }
        if paused && phase == .playing { renderPaused() }
    }

    private func renderTitle() {
        framebuffer.clear(GboomRGB(7, 7, 9))
        fire.draw(framebuffer, fraction: 0.62)
        let h = framebuffer.height
        let titleScale = min(max(framebuffer.width / 36, 2), 10)
        let smallScale = max(titleScale / 3, 1)
        GboomText.drawCenteredOutlined(framebuffer, "GBOOM", y0: h / 6, scale: titleScale, color: GboomPalette.red, outline: Self.textOutline)
        GboomText.drawCenteredOutlined(framebuffer, "KNEE-DEEP IN THE TOKENS", y0: h / 6 + 8 * titleScale, scale: smallScale, color: GboomRGB(212, 168, 92), outline: Self.textOutline)
        // The prompt blinks.
        if gboomU32(phaseTime * 1.6) % 2 == 0 {
            GboomText.drawCenteredOutlined(framebuffer, "PRESS ANY KEY", y0: h / 6 + 8 * titleScale + 10 * smallScale, scale: smallScale, color: GboomRGB(220, 210, 190), outline: Self.textOutline)
        }
    }

    private func renderEnd(_ text: String, color: GboomRGB) {
        framebuffer.clear(GboomRGB(7, 7, 9))
        fire.draw(framebuffer, fraction: 0.5)
        let h = framebuffer.height
        let scale = min(max(framebuffer.width / 40, 2), 8)
        GboomText.drawCenteredOutlined(framebuffer, text, y0: h / 5, scale: scale, color: color, outline: Self.textOutline)
        // The dismissal hint blinks once the grace period is over.
        if phaseTime > Self.endScreenGrace && gboomU32(phaseTime * 1.6) % 2 == 0 {
            GboomText.drawCenteredOutlined(framebuffer, "PRESS ANY KEY", y0: h / 5 + 10 * scale, scale: max(scale / 3, 1), color: GboomRGB(220, 210, 190), outline: Self.textOutline)
        }
    }

    /// Desktop addition: a dimmed frame and "PAUSED" while the window is in the background.
    private func renderPaused() {
        framebuffer.pixels.withUnsafeMutableBufferPointer { buffer in
            for index in buffer.indices { buffer[index] /= 2 }
        }
        let scale = min(max(framebuffer.width / 40, 2), 8)
        GboomText.drawCenteredOutlined(framebuffer, "PAUSED", y0: framebuffer.height / 2 - 7 * scale / 2, scale: scale, color: GboomRGB(220, 210, 190), outline: Self.textOutline)
    }

    /// The framebuffer as an sRGB image.
    func makeImage() -> CGImage? {
        let width = framebuffer.width, height = framebuffer.height
        guard width > 0, height > 0, let provider = CGDataProvider(data: Data(framebuffer.pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: width * 3,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

// MARK: - Window

/// The GBOOM window: the game, and the terminal overlay's HUD as a status bar.
struct GboomWindow: View {
    @StateObject private var model = GboomWindowModel()

    var body: some View {
        VStack(spacing: 0) {
            GboomGameView(model: model)
                .accessibilityLabel("GBOOM")
                .accessibilityHint("Arrow keys or W A S D to move, Space to fire, Escape to quit")
            GboomStatusBar(hud: model.hud, paused: model.paused)
        }
        .background(Color(red: 7 / 255, green: 7 / 255, blue: 9 / 255))
        .frame(minWidth: 520, minHeight: 380)
        .environment(\.colorScheme, .dark)
    }
}

@MainActor
final class GboomWindowModel: ObservableObject {
    @Published var hud = GboomHUD(total: GboomGame().totalImps)
    @Published var paused = true
}

struct GboomStatusBar: View {
    let hud: GboomHUD
    let paused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(hud.statsText)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(gboom: hud.healthColor))
                .accessibilityLabel("Health \(hud.hp), kills \(hud.kills) of \(hud.total)")
            Spacer(minLength: 12)
            Text(paused ? " PAUSED · click to resume " : hud.hint)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(white: paused ? 0.75 : 0.5))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color(red: 14 / 255, green: 14 / 255, blue: 17 / 255))
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
    }
}

private extension Color {
    init(gboom color: GboomRGB) {
        self.init(.sRGB, red: Double(color.r) / 255, green: Double(color.g) / 255, blue: Double(color.b) / 255)
    }
}

private struct GboomGameView: NSViewRepresentable {
    let model: GboomWindowModel

    func makeNSView(context: Context) -> GboomGameNSView {
        let view = GboomGameNSView()
        view.onStatus = { [weak model] hud, paused in
            guard let model else { return }
            if model.hud != hud { model.hud = hud }
            if model.paused != paused { model.paused = paused }
        }
        return view
    }

    func updateNSView(_ view: GboomGameNSView, context: Context) {}

    static func dismantleNSView(_ view: GboomGameNSView, coordinator: ()) { view.stop() }
}

/// Hosts the game: takes keyboard focus, turns key and mouse events into game input, and drives the
/// simulation at about 30 frames a second while its window is key. Frames go into a sublayer whose
/// contents scale with nearest-neighbour filtering, aspect-fit.
final class GboomGameNSView: NSView {
    private(set) var session = GboomSession()
    var onStatus: ((GboomHUD, Bool) -> Void)?
    private let imageLayer = CALayer()
    private var timer: Timer?
    private(set) var paused = true
    private var needsNewSession = false
    private var windowObservers: [NSObjectProtocol] = []
    private var tracking: NSTrackingArea?
    private var lastStatus: (hud: GboomHUD, paused: Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.magnificationFilter = .nearest
        imageLayer.minificationFilter = .nearest
        imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull()]
        layer?.addSublayer(imageLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        CATransaction.commit()
        if paused { renderFrame() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers = []
        guard let window else { stop(); return }
        // The terminal draws GBOOM in a dark modal; keep the window dark whatever the app theme.
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(srgbRed: 7 / 255, green: 7 / 255, blue: 9 / 255, alpha: 1)
        let center = NotificationCenter.default
        windowObservers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume() }
            },
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pause() }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                // Each `/gboom` starts a fresh game, even if SwiftUI keeps this view for the next opening.
                MainActor.assumeIsolated { self?.stop(); self?.needsNewSession = true }
            },
        ]
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
            if window.isKeyWindow { self.resume() } else { self.renderFrame() }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    // MARK: Running

    private func resume() {
        if needsNewSession { session = GboomSession(); needsNewSession = false }
        window?.makeFirstResponder(self)
        guard timer == nil else { return }
        paused = false
        session.resetClock()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        timer.tolerance = 0.004
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        renderFrame()
    }

    /// Losing focus pauses the game and releases held keys, since their key-up events will go elsewhere.
    private func pause() {
        session.releaseAll()
        timer?.invalidate()
        timer = nil
        paused = true
        renderFrame()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        paused = true
        session.releaseAll()
    }

    private func step() {
        session.tick()
        renderFrame()
    }

    private func renderFrame() {
        let size = GboomSession.frameSize(for: bounds.size)
        session.render(width: size.width, height: size.height, paused: paused)
        imageLayer.contents = session.makeImage()
        let status = (hud: session.hud, paused: paused)
        guard lastStatus?.hud != status.hud || lastStatus?.paused != status.paused else { return }
        lastStatus = status
        // Layout can run inside a SwiftUI update, where publishing is not allowed; report afterwards.
        DispatchQueue.main.async { [weak self] in self?.onStatus?(status.hud, status.paused) }
    }

    private func close() {
        stop()
        window?.performClose(nil)
    }

    // MARK: Input

    static func key(for event: NSEvent) -> GboomKey {
        switch event.keyCode {
        case 126: return .up
        case 125: return .down
        case 123: return .left
        case 124: return .right
        case 53: return .escape
        case 49: return .space
        case 36, 76: return .enter
        default:
            guard let character = event.charactersIgnoringModifiers?.first else { return .other }
            return .character(character)
        }
    }

    override func keyDown(with event: NSEvent) {
        // Command shortcuts (⌘W, ⌘Q, ⌘`) belong to the app.
        if event.modifierFlags.contains(.command) { super.keyDown(with: event); return }
        if session.handleKeyDown(Self.key(for: event), isRepeat: event.isARepeat) == .close { close() }
    }

    /// Releases are handled whatever the modifiers, so pressing ⌘ mid-stride cannot leave a key held.
    override func keyUp(with event: NSEvent) {
        session.handleKeyUp(Self.key(for: event))
    }

    override func resignFirstResponder() -> Bool {
        session.releaseAll()
        return super.resignFirstResponder()
    }

    override func mouseMoved(with event: NSEvent) { aim(event) }
    override func mouseDragged(with event: NSEvent) { aim(event) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if paused { resume() }
        session.click()
    }

    /// Converts pointer motion to the terminal's column units: frame pixels on screen, eight per column.
    private func aim(_ event: NSEvent) {
        guard !paused, bounds.width > 0, framebuffer.width > 0 else { return }
        let frame = framebuffer
        let fit = min(bounds.width / CGFloat(frame.width), bounds.height / CGFloat(frame.height))
        guard fit > 0 else { return }
        session.aim(columns: Float(event.deltaX / fit) / GboomSession.pixelsPerColumn)
    }

    private var framebuffer: GboomFrameBuffer { session.framebuffer }
}
