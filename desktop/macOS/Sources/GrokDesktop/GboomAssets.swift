import Foundation

// Procedural art for `/gboom`, ported from `xai-grok-gboom/src/assets.rs`. Everything is generated in
// code exactly as the terminal generates it: hash-noise wall textures, char-map sprites, a 5×7 font.

/// One RGB pixel, the unit the renderer draws with.
struct GboomRGB: Equatable, Hashable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
}

enum GboomPalette {
    /// The signature crimson shared by the title, the death screen, and the window chrome.
    static let red = GboomRGB(235, 40, 32)
    /// Imp eyes. The renderer exempts exactly this colour from distance fog so the eyes glow.
    static let eyeGlow = GboomRGB(255, 216, 0)
}

/// Wall texture side length (square).
let gboomTextureSize = 64

// MARK: - Rust numeric casts

// Rust's float-to-int `as` casts truncate toward zero and saturate (NaN becomes 0); Swift's trap
// instead, so every cast in the port goes through these.

@inline(__always) func gboomU8(_ value: Float) -> UInt8 {
    guard value > 0 else { return 0 }
    return value >= 255 ? 255 : UInt8(value)
}

@inline(__always) func gboomI32(_ value: Float) -> Int {
    guard !value.isNaN else { return 0 }
    if value >= 2_147_483_648 { return Int(Int32.max) }
    if value <= -2_147_483_648 { return Int(Int32.min) }
    return Int(value)
}

@inline(__always) func gboomUsize(_ value: Float) -> Int {
    guard value > 0 else { return 0 }
    return value >= 9_223_372_036_854_775_808 ? Int.max : Int(value)
}

@inline(__always) func gboomU32(_ value: Float) -> UInt32 {
    guard value > 0 else { return 0 }
    return value >= 4_294_967_296 ? .max : UInt32(value)
}

/// Rust's `f32::rem_euclid`.
@inline(__always) func gboomRemEuclid(_ value: Float, _ divisor: Float) -> Float {
    let remainder = value.truncatingRemainder(dividingBy: divisor)
    return remainder < 0 ? remainder + abs(divisor) : remainder
}

// MARK: - Randomness

/// The game's xorshift64* generator. Damage rolls and the fire effect each own a seeded stream so
/// the simulation replays identically to the terminal's.
struct GboomXorShift64 {
    private(set) var state: UInt64

    init(seed: UInt64) { state = max(seed, 1) }

    mutating func nextU32() -> UInt32 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return UInt32(truncatingIfNeeded: (state &* 0x2545_F491_4F6C_DD1D) >> 33)
    }

    /// Uniform in `[0, 1)`.
    mutating func nextFloat() -> Float { Float(nextU32() >> 8) / Float(1 << 24) }
}

/// Deterministic 2D integer hash into `[0, 1)`, for texture noise.
func gboomHash01(_ x: UInt32, _ y: UInt32, _ seed: UInt32) -> Float {
    var h = (x &* 0x9E37_79B9) &+ (y &* 0x85EB_CA6B) &+ (seed &* 0xC2B2_AE35)
    h ^= h >> 16
    h = h &* 0x7FEB_352D
    h ^= h >> 15
    h = h &* 0x846C_A68B
    h ^= h >> 16
    return Float(h & 0xFFFF) / 65536
}

private func gboomScale(_ c: GboomRGB, _ f: Float) -> GboomRGB {
    func channel(_ v: UInt8) -> UInt8 { gboomU8(min(max(Float(v) * f, 0), 255)) }
    return GboomRGB(channel(c.r), channel(c.g), channel(c.b))
}

// MARK: - Textures

/// A generated 64×64 wall, floor, or ceiling texture, row-major.
struct GboomTexture {
    let pixels: [GboomRGB]

    @inline(__always) func sample(_ x: Int, _ y: Int) -> GboomRGB {
        pixels[(y & (gboomTextureSize - 1)) * gboomTextureSize + (x & (gboomTextureSize - 1))]
    }

    fileprivate static func generate(_ pixel: (Int, Int) -> GboomRGB) -> GboomTexture {
        var pixels: [GboomRGB] = []
        pixels.reserveCapacity(gboomTextureSize * gboomTextureSize)
        for y in 0..<gboomTextureSize { for x in 0..<gboomTextureSize { pixels.append(pixel(x, y)) } }
        return GboomTexture(pixels: pixels)
    }

    /// The wall set, indexed by map cell value - 1: brick, stone, tech, hellstone.
    static func walls() -> [GboomTexture] { [brick(), stone(), tech(), hellstone()] }

    /// Red-brown 16×8 bricks, offset every other row, with mortar gaps.
    static func brick() -> GboomTexture {
        let base = GboomRGB(148, 64, 44), mortar = GboomRGB(78, 60, 54)
        return generate { x, y in
            let row = y / 8
            let offset = row % 2 == 0 ? 0 : 8
            if y % 8 == 0 || (x + offset) % 16 == 0 { return mortar }
            let brickID = UInt32(row) &* 31 &+ UInt32((x + offset) / 16)
            let tone: Float = 0.82 + 0.30 * gboomHash01(brickID, 7, 1)
            let grain: Float = 0.92 + 0.16 * gboomHash01(UInt32(x), UInt32(y), 2)
            return gboomScale(base, tone * grain)
        }
    }

    /// Large grey 32×16 stone blocks with grout.
    static func stone() -> GboomTexture {
        let base = GboomRGB(118, 118, 126), grout = GboomRGB(58, 58, 64)
        return generate { x, y in
            let row = y / 16
            let offset = row % 2 == 0 ? 0 : 16
            if y % 16 == 0 || (x + offset) % 32 == 0 { return grout }
            let blockID = UInt32(row) &* 17 &+ UInt32((x + offset) / 32)
            let tone: Float = 0.80 + 0.28 * gboomHash01(blockID, 3, 3)
            let grain: Float = 0.90 + 0.20 * gboomHash01(UInt32(x), UInt32(y), 4)
            return gboomScale(base, tone * grain)
        }
    }

    /// Dark metal panels with seams and green light dots.
    static func tech() -> GboomTexture {
        let base = GboomRGB(74, 82, 92), seam = GboomRGB(38, 42, 48), light = GboomRGB(110, 240, 130)
        return generate { x, y in
            let inSeam = y % 16 == 0 || y % 16 == 15 || x % 32 == 0
            let isLight = y % 16 == 8 && x % 8 == 4 && gboomHash01(UInt32(x / 8), UInt32(y / 16), 5) > 0.35
            if isLight { return light }
            if inSeam { return seam }
            let grain: Float = 0.88 + 0.22 * gboomHash01(UInt32(x), UInt32(y), 6)
            return gboomScale(base, grain)
        }
    }

    /// Dark red marbled stone for accent walls.
    static func hellstone() -> GboomTexture {
        let base: (Float, Float, Float) = (120, 30, 28), vein: (Float, Float, Float) = (200, 80, 50)
        let size = Float(gboomTextureSize)
        return generate { x, y in
            let fx = Float(x) / size, fy = Float(y) / size
            let noise = gboomHash01(UInt32(x / 4), UInt32(y / 4), 7)
            let wave: Float = sin(fx * 9 + fy * 4 + noise * 3) * 0.5 + 0.5
            let v = wave * wave * wave
            let grain: Float = 0.85 + 0.25 * gboomHash01(UInt32(x), UInt32(y), 8)
            return GboomRGB(gboomU8((base.0 * (1 - v) + vein.0 * v) * grain),
                            gboomU8((base.1 * (1 - v) + vein.1 * v) * grain),
                            gboomU8((base.2 * (1 - v) + vein.2 * v) * grain))
        }
    }

    /// Worn 32-pixel stone floor tiles with grime, dark so the fog gradient reads.
    static func floor() -> GboomTexture {
        let base = GboomRGB(96, 86, 74), grout = GboomRGB(44, 40, 36)
        return generate { x, y in
            if y % 32 == 0 || x % 32 == 0 { return grout }
            let tileID = UInt32(y / 32) &* 5 &+ UInt32(x / 32)
            let tone: Float = 0.78 + 0.30 * gboomHash01(tileID, 11, 9)
            let grime: Float = gboomHash01(UInt32(x / 6), UInt32(y / 6), 10) > 0.72 ? 0.78 : 1.0
            let grain: Float = 0.90 + 0.20 * gboomHash01(UInt32(x), UInt32(y), 11)
            return gboomScale(base, tone * grime * grain)
        }
    }

    /// Dark metal ceiling panels; about one in six carries a lamp that stays bright through fog.
    static func ceiling() -> GboomTexture {
        let base = GboomRGB(52, 56, 66), seam = GboomRGB(30, 32, 38), lamp = GboomRGB(232, 226, 198)
        return generate { x, y in
            let inSeam = y % 16 == 0 || x % 16 == 0
            let hasLamp = gboomHash01(UInt32(x / 16), UInt32(y / 16), 12) > 0.84
            if hasLamp && (4..<12).contains(x % 16) && (4..<12).contains(y % 16) { return lamp }
            if inSeam { return seam }
            let grain: Float = 0.88 + 0.20 * gboomHash01(UInt32(x), UInt32(y), 13)
            return gboomScale(base, grain)
        }
    }
}

// MARK: - Sprites

/// A char-map sprite; `.` is transparent.
struct GboomSprite {
    let width: Int
    let height: Int
    let pixels: [GboomRGB?]

    init(_ art: [String]) {
        height = art.count
        width = art.first?.utf8.count ?? 0
        var pixels: [GboomRGB?] = []
        pixels.reserveCapacity(width * height)
        for row in art {
            assert(row.utf8.count == width, "sprite rows must be equal length")
            for character in row.utf8 { pixels.append(Self.color(character)) }
        }
        self.pixels = pixels
    }

    /// Samples with normalized coordinates in `[0, 1)`.
    @inline(__always) func sample(_ u: Float, _ v: Float) -> GboomRGB? {
        let x = min(gboomUsize(u * Float(width)), width - 1)
        let y = min(gboomUsize(v * Float(height)), height - 1)
        return pixels[y * width + x]
    }

    static func color(_ character: UInt8) -> GboomRGB? {
        switch character {
        case UInt8(ascii: "B"): return GboomRGB(146, 90, 50)    // imp body
        case UInt8(ascii: "b"): return GboomRGB(104, 62, 34)    // imp body, shaded
        case UInt8(ascii: "H"): return GboomRGB(222, 214, 188)  // horn, bone
        case UInt8(ascii: "E"): return GboomPalette.eyeGlow     // glowing eye
        case UInt8(ascii: "M"): return GboomRGB(34, 20, 16)     // mouth
        case UInt8(ascii: "T"): return GboomRGB(236, 232, 220)  // teeth
        case UInt8(ascii: "C"): return GboomRGB(214, 196, 160)  // claw
        case UInt8(ascii: "R"): return GboomRGB(186, 28, 24)    // blood
        case UInt8(ascii: "r"): return GboomRGB(120, 16, 14)    // blood, dark
        case UInt8(ascii: "G"): return GboomRGB(96, 104, 112)   // gunmetal
        case UInt8(ascii: "g"): return GboomRGB(52, 58, 66)     // gunmetal, dark
        case UInt8(ascii: "W"): return GboomRGB(224, 228, 232)  // highlight
        case UInt8(ascii: "S"): return GboomRGB(212, 160, 116)  // skin
        case UInt8(ascii: "s"): return GboomRGB(164, 116, 80)   // skin, shaded
        case UInt8(ascii: "F"): return GboomRGB(255, 244, 160)  // muzzle flash core
        case UInt8(ascii: "f"): return GboomRGB(255, 168, 48)   // muzzle flash fringe
        default: return nil
        }
    }
}

/// The seven 16×20 imp frames.
struct GboomImpSprites {
    let walkA, walkB, attack, pain, dieA, dieB, corpse: GboomSprite

    init() {
        walkA = GboomSprite([
            "..H..........H..",
            "..HH........HH..",
            "...bBBBBBBBBb...",
            "...BBBBBBBBBB...",
            "..BBEEBBBBEEBB..",
            "..BBEEBBBBEEBB..",
            "...BBBBBBBBBB...",
            "...BbMTMTMTbB...",
            "....bBBBBBBb....",
            "..bBBBBBBBBBBb..",
            ".CBBb.BBBB.bBBC.",
            ".CBB..BBBB..BBC.",
            ".CC...BBBB...CC.",
            "......bBBb......",
            ".....BB..BB.....",
            "....BB....BB....",
            "....BB.....BB...",
            "...bB.......Bb..",
            "...BB.......BB..",
            "..CC.........CC.",
        ])
        walkB = GboomSprite([
            "..H..........H..",
            "..HH........HH..",
            "...bBBBBBBBBb...",
            "...BBBBBBBBBB...",
            "..BBEEBBBBEEBB..",
            "..BBEEBBBBEEBB..",
            "...BBBBBBBBBB...",
            "...BbMTMTMTbB...",
            "....bBBBBBBb....",
            "..bBBBBBBBBBBb..",
            ".CBBb.BBBB.bBBC.",
            ".CBB..BBBB..BBC.",
            ".CC...BBBB...CC.",
            "......bBBb......",
            ".....BB..BB.....",
            "....BB.....BB...",
            "...BB.......BB..",
            "...Bb.......bB..",
            "...BB........BB.",
            "..CC..........CC",
        ])
        attack = GboomSprite([
            ".CC.H......H.CC.",
            ".CBBHH....HHBBC.",
            ".CBBbBBBBBBbBBC.",
            "..BBBBBBBBBBBB..",
            "..BBEEBBBBEEBB..",
            "..bBEEBBBBEEBb..",
            "...BBBBBBBBBB...",
            "...BbMMMMMMbB...",
            "...BbMTMTMTbB...",
            "....bBBBBBBb....",
            "...BBBBBBBBBB...",
            "...BBBBBBBBBB...",
            "....BBBBBBBB....",
            "......bBBb......",
            ".....BB..BB.....",
            "....BB....BB....",
            "....BB....BB....",
            "...bB......Bb...",
            "...BB......BB...",
            "..CC........CC..",
        ])
        pain = GboomSprite([
            "....H......H....",
            "...HH.....HH....",
            "..bBBBBBBBBb....",
            ".RBBBBBBBBBB....",
            ".RBBMMBBBMMBB...",
            "..rBBBBBBBBBR...",
            "...BBBBBBBBBB...",
            "...BbMMMMMMbB...",
            "....bBBBBBBbR...",
            "..bBBBBBBBBBBb..",
            ".CBBb.BBBB.bBBC.",
            ".CBB..BBBB..BBC.",
            ".CC...BBBB...CC.",
            "......bBBb......",
            ".....BB..BB.....",
            "....BB....BB....",
            "....BB....BB....",
            "...bB......Bb...",
            "...BB......BB...",
            "..CC........CC..",
        ])
        dieA = GboomSprite([
            "................",
            "................",
            "................",
            "...H........H...",
            "...HHBBBBBBHH...",
            "..bBBBBBBBBBBb..",
            "..RBMMBBBBMMBR..",
            "..rBBBBBBBBBBr..",
            "...BbMMMMMMbB...",
            "..RbBBBBBBBBbR..",
            ".CBBBBBBBBBBBBC.",
            ".CBb.BBBBBB.bBC.",
            ".CC..BBBBBB..CC.",
            "....bBBBBBBb....",
            "...RBB....BBR...",
            "...BB......BB...",
            "..rB........Br..",
            "..BB........BB..",
            ".RCC........CCR.",
            "................",
        ])
        dieB = GboomSprite([
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "....H......H....",
            "...HHBBBBBHH....",
            "..RbBBBBBBBbR...",
            "..rBMMBBBMMBr...",
            "..RBBBBBBBBBR...",
            ".RbBBBBBBBBBbR..",
            ".CBBBBBBBBBBBC..",
            ".CBbRBBBBBBRbC..",
            "..RR.BBBBB.RR...",
            "...RbBBBBBbR....",
            "..RRBBBBBBRR....",
            ".rRRRbBBbRRRr...",
            "................",
        ])
        corpse = GboomSprite([
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "....rr..r.......",
            "..rRRrrRRr.r....",
            ".rRbBBBBbRRrr...",
            "rRRBbHbBBbRRRr..",
            ".rrRRbBBbRRrr...",
            "..r.rRRRRr.r....",
            "................",
        ])
    }

    func sprite(_ visual: GboomImpVisual) -> GboomSprite {
        switch visual {
        case .walkA: return walkA
        case .walkB: return walkB
        case .attack: return attack
        case .pain: return pain
        case .dieA: return dieA
        case .dieB: return dieB
        case .corpse: return corpse
        }
    }
}

/// The 24×18 view-model pistol, idle and firing.
struct GboomGunSprites {
    let idle = GboomSprite([
        "........................",
        "..........WGG...........",
        ".........GGGGG..........",
        ".........gGGGGg.........",
        ".........gGGGGg.........",
        ".........gGGGGg.........",
        "........gGGGGGGg........",
        "........gGGGGGGg........",
        ".......gGGGGGGGGg.......",
        ".......sSGGGGGGSs.......",
        "......sSSSGGGGSSSs......",
        ".....sSSSSSGGSSSSSs.....",
        "....sSSSSSSSSSSSSSSs....",
        "....sSSSSSSSSSSSSSs.....",
        "...sSSSSSSSSSSSSSSs.....",
        "...sSSSSSSSSSSSSSs......",
        "..sSSSSSSSSSSSSSSs......",
        "..sSSSSSSSSSSSSSs.......",
    ])
    let fire = GboomSprite([
        ".........fFFf...........",
        "........fFFFFf..........",
        ".......fFFFFFFf.........",
        "........fFFFFf..........",
        ".........FGGF...........",
        ".........gGGGGg.........",
        "........gGGGGGGg........",
        "........gGGGGGGg........",
        ".......gGGGGGGGGg.......",
        ".......sSGGGGGGSs.......",
        "......sSSSGGGGSSSs......",
        ".....sSSSSSGGSSSSSs.....",
        "....sSSSSSSSSSSSSSSs....",
        "....sSSSSSSSSSSSSSs.....",
        "...sSSSSSSSSSSSSSSs.....",
        "...sSSSSSSSSSSSSSs......",
        "..sSSSSSSSSSSSSSSs......",
        "..sSSSSSSSSSSSSSs.......",
    ])
}

// MARK: - 5×7 font

/// Glyph rows for the few characters the screens use, MSB-left in the low five bits; others are blank.
func gboomGlyph(_ character: Character) -> [UInt8] {
    switch character.uppercased().first ?? character {
    case "A": return [0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001]
    case "B": return [0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110]
    case "C": return [0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110]
    case "D": return [0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110]
    case "E": return [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111]
    case "G": return [0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01111]
    case "H": return [0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001]
    case "I": return [0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b11111]
    case "K": return [0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001]
    case "L": return [0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111]
    case "M": return [0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001]
    case "N": return [0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001]
    case "O": return [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110]
    case "P": return [0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000]
    case "R": return [0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001]
    case "S": return [0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110]
    case "T": return [0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100]
    case "U": return [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110]
    case "V": return [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100]
    case "Y": return [0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100]
    case "!": return [0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00000, 0b00100]
    case "-": return [0b00000, 0b00000, 0b00000, 0b01110, 0b00000, 0b00000, 0b00000]
    default: return [0, 0, 0, 0, 0, 0, 0]
    }
}
