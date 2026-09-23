import Foundation

// The `/gboom` world simulation, ported from `xai-grok-gboom/src/game.rs`: the map, momentum-based
// player movement, imp AI, and hitscan combat. `step(dt)` advances by wall-clock time, so the game
// plays the same at any frame rate. All arithmetic is `Float` (Rust `f32`) so runs replay exactly.

/// The one hand-authored level. Digits are walls and pick the texture (`1` brick, `2` stone, `3` tech,
/// `4` hellstone), `.` is floor, `P` the player start, `I` an imp spawn.
let gboomMapArt = [
    "1111111111111111111111",
    "1P...1....2......2...1",
    "1....1.22.2.3333.2.I.1",
    "1....1.2..2.3..3.2...1",
    "1.11.1.2.I2.3.I3.222.1",
    "1.1..1.2..2.33.3...2.1",
    "1.1..1.22.2....3.2.2.1",
    "1.1......2..33.3.2...1",
    "1.111111.2.I3..32222.1",
    "1......1.2..3333.....1",
    "144444.1.2........11.1",
    "1....4.1.22222222..1.1",
    "1.I..4.1........2.I1.1",
    "1....4.11111111.2..1.1",
    "1.4444.......41.2222.1",
    "1.4..444444..41......1",
    "1.4.I......I.41.111111",
    "1.4..444444..4....I..1",
    "1.444........4.11....1",
    "1...44444444.4.1..1111",
    "1............4.1.....1",
    "1111111111111111111111",
]

enum GboomTuning {
    /// Collision radii, in tiles. The player's is a touch under a quarter tile so one-tile corridors have clearance.
    static let playerRadius: Float = 0.20
    static let impRadius: Float = 0.30
    static let moveSpeed: Float = 3.3
    static let turnSpeed: Float = 2.2
    /// Velocity smoothing time constants: a snappy response with just enough ramp to read as momentum.
    static let moveAccelTau: Float = 0.08
    static let turnAccelTau: Float = 0.07
    /// How long a press keeps a control held when the input source reports no key releases.
    static let holdWindow: Float = 0.16
    static let playerMaxHP = 100
    static let fireCooldown: Float = 0.32
    static let muzzleTime: Float = 0.09
    /// Hitscan half-width: an imp is hit when its centre is within this distance of the aim ray.
    static let hitWidth: Float = 0.33
    static let pistolDamage = 11
    static let impHP = 30
    static let impSpeed: Float = 1.55
    static let impSightRange: Float = 9.0
    static let impMeleeRange: Float = 0.95
    static let impWindup: Float = 0.38
    static let impAttackCooldown: Float = 0.95
    static let impPainTime: Float = 0.28
    static let impDeathTime: Float = 0.55
    static let impBiteDamage = 7
    static let gameSeed: UInt64 = 0x9E37_79B9_7F4A_7C15
}

/// Grid map with texture-id cells: 0 is floor, 1–4 a wall texture.
struct GboomMap {
    let width: Int
    let height: Int
    let cells: [UInt8]

    /// The wall texture at a cell, or 0 for floor. Out of bounds is solid.
    @inline(__always) func cell(_ x: Int, _ y: Int) -> UInt8 {
        guard x >= 0, y >= 0, x < width, y < height else { return 1 }
        return cells[y * width + x]
    }

    @inline(__always) func solid(_ x: Int, _ y: Int) -> Bool { cell(x, y) != 0 }

    /// Whether a circle of `radius` at `(x, y)` overlaps a solid cell.
    func blocked(_ x: Float, _ y: Float, radius: Float) -> Bool {
        let minX = gboomI32((x - radius).rounded(.down)), maxX = gboomI32((x + radius).rounded(.down))
        let minY = gboomI32((y - radius).rounded(.down)), maxY = gboomI32((y + radius).rounded(.down))
        guard minX <= maxX, minY <= maxY else { return false }
        for cy in minY...maxY { for cx in minX...maxX where solid(cx, cy) { return true } }
        return false
    }

    /// Line of sight between two points (walls only), a DDA over grid cells.
    func lineOfSight(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float) -> Bool {
        let dx = x1 - x0, dy = y1 - y0
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance < 1e-4 { return true }
        let rdx = dx / distance, rdy = dy / distance
        var mapX = gboomI32(x0.rounded(.down)), mapY = gboomI32(y0.rounded(.down))
        let deltaX: Float = rdx == 0 ? .greatestFiniteMagnitude : abs(1 / rdx)
        let deltaY: Float = rdy == 0 ? .greatestFiniteMagnitude : abs(1 / rdy)
        let stepX: Int, stepY: Int
        var sideX: Float, sideY: Float
        if rdx < 0 { stepX = -1; sideX = (x0 - Float(mapX)) * deltaX } else { stepX = 1; sideX = (Float(mapX) + 1 - x0) * deltaX }
        if rdy < 0 { stepY = -1; sideY = (y0 - Float(mapY)) * deltaY } else { stepY = 1; sideY = (Float(mapY) + 1 - y0) * deltaY }
        while true {
            let travelled: Float
            if sideX < sideY { mapX += stepX; travelled = sideX; sideX += deltaX }
            else { mapY += stepY; travelled = sideY; sideY += deltaY }
            if travelled >= distance { return true }
            if solid(mapX, mapY) { return false }
        }
    }
}

struct GboomPlayer {
    var x: Float
    var y: Float
    var angle: Float = 0
    /// Forward velocity (negative backpedals), tiles/s.
    var velForward: Float = 0
    /// Strafe velocity (positive is right), tiles/s.
    var velStrafe: Float = 0
    /// Angular velocity, rad/s (positive turns right).
    var velRot: Float = 0
    var hp = GboomTuning.playerMaxHP
    /// Seconds until the pistol can fire again.
    var fireCooldown: Float = 0
    /// Remaining muzzle-flash time.
    var muzzle: Float = 0
    /// Damage flash intensity, decaying to 0.
    var damageFlash: Float = 0
    /// Accumulated distance for view and gun bob.
    var bob: Float = 0

    @inline(__always) var direction: (Float, Float) { (cos(angle), sin(angle)) }
}

/// Movement controls. The raw values index `GboomGame.hold`.
enum GboomControl: Int, CaseIterable {
    case forward, back, turnLeft, turnRight, strafeLeft, strafeRight
}

enum GboomImpState: Equatable {
    case idle
    case chasing
    /// Winding up a bite; `t` counts down.
    case attacking(t: Float)
    case pain(t: Float)
    case dying(t: Float)
    case dead
}

/// Which sprite frame an imp shows.
enum GboomImpVisual: Equatable { case walkA, walkB, attack, pain, dieA, dieB, corpse }

struct GboomImp {
    var x: Float
    var y: Float
    var hp = GboomTuning.impHP
    var state: GboomImpState = .idle
    /// Walk-cycle clock.
    var anim: Float
    /// Seconds until the next bite is allowed.
    var attackCooldown: Float = 0

    var alive: Bool {
        switch state { case .dying, .dead: return false; default: return true }
    }

    /// Walk-cycle bob phase in `[-1, 1]`, or nil when not walking.
    var walkBob: Float? { state == .chasing ? sin(anim * 9) : nil }

    var visual: GboomImpVisual {
        switch state {
        case .idle: return .walkA
        case .chasing: return gboomU32(anim * 3) % 2 == 0 ? .walkA : .walkB
        case .attacking: return .attack
        case .pain: return .pain
        case .dying(let t): return t > GboomTuning.impDeathTime * 0.5 ? .dieA : .dieB
        case .dead: return .corpse
        }
    }
}

struct GboomGame {
    let map: GboomMap
    var player: GboomPlayer
    var imps: [GboomImp]
    var kills = 0
    var time: Float = 0
    /// Per-control hold countdown, indexed by `GboomControl.rawValue`; positive means held. When the
    /// input reports releases (always on macOS), a press latches it until `release`.
    private(set) var hold = [Float](repeating: 0, count: GboomControl.allCases.count)
    /// True when key releases are reported, so several controls can be held at once.
    var releaseAware = false
    /// Set by `queueFire`, consumed by the next `step`.
    private var fireQueued = false
    private var rng = GboomXorShift64(seed: GboomTuning.gameSeed)

    init(art: [String] = gboomMapArt) {
        let height = art.count
        let width = art.first?.utf8.count ?? 0
        var cells = [UInt8](repeating: 0, count: width * height)
        var start: (Float, Float) = (1.5, 1.5)
        var imps: [GboomImp] = []
        for (y, row) in art.enumerated() {
            for (x, character) in row.utf8.enumerated() where x < width {
                let center = (Float(x) + 0.5, Float(y) + 0.5)
                switch character {
                case UInt8(ascii: "1")...UInt8(ascii: "4"): cells[y * width + x] = character - UInt8(ascii: "0")
                case UInt8(ascii: "P"): start = center
                // Seeding the walk clock from the spawn cell desyncs the imps' gaits.
                case UInt8(ascii: "I"): imps.append(GboomImp(x: center.0, y: center.1, anim: Float(x * 7 + y * 13) * 0.1))
                default: break
                }
            }
        }
        map = GboomMap(width: width, height: height, cells: cells)
        player = GboomPlayer(x: start.0, y: start.1)
        self.imps = imps
    }

    var totalImps: Int { imps.count }
    var won: Bool { kills == totalImps }
    var dead: Bool { player.hp <= 0 }
    var anyHeld: Bool { hold.contains { $0 > 0 } }

    /// A press latches the control when releases are reported; otherwise it holds for `holdWindow`.
    mutating func press(_ control: GboomControl) {
        hold[control.rawValue] = releaseAware ? .infinity : GboomTuning.holdWindow
    }

    mutating func release(_ control: GboomControl) { hold[control.rawValue] = 0 }

    /// Un-latches everything, so a release missed while unfocused cannot leave the player walking.
    mutating func releaseAll() { hold = [Float](repeating: 0, count: hold.count) }

    /// Fires on the next `step` if the pistol is off cooldown.
    mutating func queueFire() { fireQueued = true }

    mutating func step(_ dt: Float) {
        time += dt
        stepPlayer(dt)
        if fireQueued {
            fireQueued = false
            tryFire()
        }
        stepImps(dt)
    }

    private mutating func stepPlayer(_ dt: Float) {
        for index in hold.indices { hold[index] = max(hold[index] - dt, 0) }
        let held = hold.map { $0 > 0 }
        func axis(_ positive: GboomControl, _ negative: GboomControl) -> Float {
            Float((held[positive.rawValue] ? 1 : 0) - (held[negative.rawValue] ? 1 : 0))
        }
        // Diagonal movement is clamped to unit length so it is not faster than moving straight.
        var forward = axis(.forward, .back)
        var strafe = axis(.strafeRight, .strafeLeft)
        let magnitude = (forward * forward + strafe * strafe).squareRoot()
        if magnitude > 1 { forward /= magnitude; strafe /= magnitude }
        let targetForward = forward * GboomTuning.moveSpeed
        let targetStrafe = strafe * GboomTuning.moveSpeed
        let targetRot = axis(.turnRight, .turnLeft) * GboomTuning.turnSpeed

        // Frame-rate-independent exponential smoothing: a steady target while held, gliding to rest after.
        let moveBlend: Float = 1 - exp(-dt / GboomTuning.moveAccelTau)
        let turnBlend: Float = 1 - exp(-dt / GboomTuning.turnAccelTau)
        player.velForward += (targetForward - player.velForward) * moveBlend
        player.velStrafe += (targetStrafe - player.velStrafe) * moveBlend
        player.velRot += (targetRot - player.velRot) * turnBlend

        player.angle += player.velRot * dt
        let (dx, dy) = player.direction
        let (sx, sy) = (-dy, dx)
        let stepX = (dx * player.velForward + sx * player.velStrafe) * dt
        let stepY = (dy * player.velForward + sy * player.velStrafe) * dt
        // Moving each axis separately lets the player slide along walls.
        if !map.blocked(player.x + stepX, player.y, radius: GboomTuning.playerRadius) { player.x += stepX }
        if !map.blocked(player.x, player.y + stepY, radius: GboomTuning.playerRadius) { player.y += stepY }

        player.bob += (abs(player.velForward) + abs(player.velStrafe)) * dt
        player.fireCooldown = max(player.fireCooldown - dt, 0)
        player.muzzle = max(player.muzzle - dt, 0)
        player.damageFlash = max(player.damageFlash - dt * 1.8, 0)
    }

    /// The live imp the pistol would hit now: the nearest within `hitWidth` of the aim ray, in front,
    /// with a clear line of sight. Firing and the crosshair feedback share it.
    func targetInCrosshair() -> Int? {
        let (px, py) = (player.x, player.y)
        let (dx, dy) = player.direction
        var best: (index: Int, along: Float)?
        for (index, imp) in imps.enumerated() where imp.alive {
            let (rx, ry) = (imp.x - px, imp.y - py)
            let along = rx * dx + ry * dy
            if along <= 0 { continue }
            if abs(rx * dy - ry * dx) > GboomTuning.hitWidth { continue }
            if !map.lineOfSight(px, py, imp.x, imp.y) { continue }
            if let current = best, along >= current.along { continue }
            best = (index, along)
        }
        return best?.index
    }

    private mutating func tryFire() {
        if player.fireCooldown > 0 { return }
        player.fireCooldown = GboomTuning.fireCooldown
        player.muzzle = GboomTuning.muzzleTime
        guard let index = targetInCrosshair() else { return }
        imps[index].hp -= GboomTuning.pistolDamage + gboomI32(rng.nextFloat() * 7)
        if imps[index].hp <= 0 {
            imps[index].state = .dying(t: GboomTuning.impDeathTime)
            kills += 1
        } else {
            imps[index].state = .pain(t: GboomTuning.impPainTime)
        }
    }

    private mutating func stepImps(_ dt: Float) {
        let (px, py) = (player.x, player.y)
        var playerDamage = 0
        for index in imps.indices {
            let (ix, iy, state) = (imps[index].x, imps[index].y, imps[index].state)
            // Corpses never act; skipping them avoids the distance sqrt in the corpse-heavy late game.
            if state == .dead { continue }
            let dxp = px - ix, dyp = py - iy
            let distance = (dxp * dxp + dyp * dyp).squareRoot()
            switch state {
            case .idle:
                if distance < GboomTuning.impSightRange && map.lineOfSight(ix, iy, px, py) { imps[index].state = .chasing }
            case .chasing:
                imps[index].attackCooldown = max(imps[index].attackCooldown - dt, 0)
                if distance < GboomTuning.impMeleeRange {
                    if imps[index].attackCooldown <= 0 { imps[index].state = .attacking(t: GboomTuning.impWindup) }
                } else {
                    // The walk cycle only advances while moving, so an imp waiting out its cooldown does not march in place.
                    imps[index].anim += dt
                    chaseStep(index, px, py, distance, dt)
                }
            case .attacking(let t):
                let remaining = t - dt
                if remaining <= 0 {
                    imps[index].state = .chasing
                    imps[index].attackCooldown = GboomTuning.impAttackCooldown
                    // The bite lands only if the player is still close.
                    if distance < GboomTuning.impMeleeRange * 1.25 {
                        playerDamage += GboomTuning.impBiteDamage + gboomI32(rng.nextFloat() * 5)
                    }
                } else {
                    imps[index].state = .attacking(t: remaining)
                }
            case .pain(let t):
                let remaining = t - dt
                imps[index].state = remaining <= 0 ? .chasing : .pain(t: remaining)
            case .dying(let t):
                let remaining = t - dt
                imps[index].state = remaining <= 0 ? .dead : .dying(t: remaining)
            case .dead:
                break
            }
        }
        if playerDamage > 0 {
            player.hp = max(player.hp - playerDamage, 0)
            player.damageFlash = 1
        }
    }

    /// Moves imp `index` toward the player with wall sliding and a little separation from other live imps.
    private mutating func chaseStep(_ index: Int, _ px: Float, _ py: Float, _ distance: Float, _ dt: Float) {
        let (ix, iy) = (imps[index].x, imps[index].y)
        var mx = (px - ix) / distance
        var my = (py - iy) / distance
        // Push away from live imps closer than 0.7 tiles (0.49 = 0.7²) so a pack does not collapse into one sprite.
        for (other, imp) in imps.enumerated() where other != index && imp.alive {
            let (ox, oy) = (ix - imp.x, iy - imp.y)
            let d2 = ox * ox + oy * oy
            if d2 < 0.49 && d2 > 1e-6 {
                let d = d2.squareRoot()
                mx += (ox / d) * 0.6
                my += (oy / d) * 0.6
            }
        }
        let magnitude = max((mx * mx + my * my).squareRoot(), 1e-4)
        let step = GboomTuning.impSpeed * dt
        let (sx, sy) = (mx / magnitude * step, my / magnitude * step)
        if !map.blocked(imps[index].x + sx, imps[index].y, radius: GboomTuning.impRadius) { imps[index].x += sx }
        if !map.blocked(imps[index].x, imps[index].y + sy, radius: GboomTuning.impRadius) { imps[index].y += sy }
    }
}
