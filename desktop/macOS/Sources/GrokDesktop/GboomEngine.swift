import Foundation

// The `/gboom` software renderer, ported from `xai-grok-gboom/src/engine.rs`: a Lodev-style DDA
// raycaster with textured walls, perspective floor and ceiling, distance fog, and billboard imps
// clipped by a per-column depth buffer; then the view-model gun and full-frame effects. It also
// draws the fire title and end screens. Everything renders into a plain RGB8 buffer.

enum GboomRender {
    /// Distance fog: shade = 1 / (1 + distance × fog).
    static let fog: Float = 0.16
    /// Imp sprite height in world units (walls are 1 tall).
    static let impWorldHeight: Float = 0.72
    /// Camera half-FOV tangent (0.66 is the classic 66° field of view).
    static let planeLength: Float = 0.66
    /// Corner vignette strength.
    static let vignette: Float = 0.11
}

/// An RGB8 framebuffer plus the scratch buffers the renderer reuses every frame.
final class GboomFrameBuffer {
    private(set) var width = 0
    private(set) var height = 0
    /// RGB8, row-major.
    var pixels: [UInt8] = []
    /// Per-column wall depth.
    fileprivate(set) var depth: [Float] = []
    /// Per-column wall strip bounds `[top, bottom)`; the floor pass skips the rows walls cover.
    fileprivate var wallTop: [Int] = []
    fileprivate var wallBottom: [Int] = []
    fileprivate var spriteOrder: [(index: Int, distance: Float)] = []
    /// Separable vignette factors, rebuilt when the size changes.
    fileprivate var vignetteX: [Float] = []
    fileprivate var vignetteY: [Float] = []

    func resize(_ width: Int, _ height: Int) {
        guard width != self.width || height != self.height else { return }
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 3)
        depth = [Float](repeating: .greatestFiniteMagnitude, count: width)
        wallTop = [Int](repeating: 0, count: width)
        wallBottom = [Int](repeating: 0, count: width)
        func axis(_ i: Int, _ n: Int) -> Float {
            let t: Float = n <= 1 ? 0 : 2 * Float(i) / Float(n - 1) - 1
            return 1 - GboomRender.vignette * t * t
        }
        vignetteX = (0..<width).map { axis($0, width) }
        vignetteY = (0..<height).map { axis($0, height) }
    }

    func clear(_ color: GboomRGB) {
        pixels.withUnsafeMutableBufferPointer { buffer in
            var index = 0
            while index + 2 < buffer.count {
                buffer[index] = color.r; buffer[index + 1] = color.g; buffer[index + 2] = color.b
                index += 3
            }
        }
    }

    @inline(__always) func put(_ x: Int, _ y: Int, _ color: GboomRGB) {
        let index = (y * width + x) * 3
        guard index >= 0, index + 2 < pixels.count else { return }
        pixels[index] = color.r; pixels[index + 1] = color.g; pixels[index + 2] = color.b
    }
}

@inline(__always) private func gboomShade(_ c: GboomRGB, _ f: Float) -> GboomRGB {
    GboomRGB(gboomU8(Float(c.r) * f), gboomU8(Float(c.g) * f), gboomU8(Float(c.b) * f))
}

@inline(__always) private func gboomLerp(_ a: GboomRGB, _ b: GboomRGB, _ t: Float) -> GboomRGB {
    let t = min(max(t, 0), 1)
    func channel(_ x: UInt8, _ y: UInt8) -> UInt8 { gboomU8(Float(x) + (Float(y) - Float(x)) * t) }
    return GboomRGB(channel(a.r, b.r), channel(a.g, b.g), channel(a.b, b.b))
}

/// Writes one pixel through a raw buffer; callers guarantee the coordinates are on screen.
@inline(__always) private func gboomStore(_ buffer: UnsafeMutableBufferPointer<UInt8>, _ index: Int, _ c: GboomRGB) {
    buffer[index] = c.r; buffer[index + 1] = c.g; buffer[index + 2] = c.b
}

/// All immutable render resources, built once per game.
struct GboomRenderer {
    let walls = GboomTexture.walls()
    let floor = GboomTexture.floor()
    let ceiling = GboomTexture.ceiling()
    let impSprites = GboomImpSprites()
    let guns = GboomGunSprites()

    /// Renders one gameplay frame.
    func renderGame(_ fb: GboomFrameBuffer, _ game: GboomGame) {
        guard fb.width > 0, fb.height > 0 else { return }
        // The muzzle flash briefly lights the whole scene.
        let light: Float = game.player.muzzle > 0 ? 1.35 : 1.0
        // Walls first: they record strip bounds and depth so the floor pass skips what they cover.
        drawWalls(fb, game, light: light)
        drawFloorAndCeiling(fb, game, light: light)
        drawImps(fb, game, light: light)
        // The vignette darkens the world only; the gun stays crisp on top.
        applyVignette(fb)
        drawGun(fb, game)

        // Damage flash: a flat blend of the frame toward red that reads even at low resolution.
        if game.player.damageFlash > 0 {
            let t = min(game.player.damageFlash * 0.45, 0.45)
            fb.pixels.withUnsafeMutableBufferPointer { buffer in
                var index = 0
                while index + 2 < buffer.count {
                    let r = Float(buffer[index]), g = Float(buffer[index + 1]), b = Float(buffer[index + 2])
                    buffer[index] = gboomU8(r + (220 - r) * t)
                    buffer[index + 1] = gboomU8(g * (1 - t * 0.8))
                    buffer[index + 2] = gboomU8(b * (1 - t * 0.8))
                    index += 3
                }
            }
        }
        // Low-health pulse.
        if game.player.hp <= 25 && !game.dead {
            let pulse: Float = 0.10 + 0.06 * sin(game.time * 5)
            fb.pixels.withUnsafeMutableBufferPointer { buffer in
                var index = 0
                while index + 2 < buffer.count {
                    let r = Float(buffer[index])
                    buffer[index] = gboomU8(r + (160 - r) * pulse)
                    index += 3
                }
            }
        }
    }

    private func drawWalls(_ fb: GboomFrameBuffer, _ game: GboomGame, light: Float) {
        let w = fb.width, h = fb.height
        let p = game.player
        let (dirX, dirY) = p.direction
        let (planeX, planeY) = (-dirY * GboomRender.planeLength, dirX * GboomRender.planeLength)
        let size = gboomTextureSize
        fb.pixels.withUnsafeMutableBufferPointer { buffer in
            for x in 0..<w {
                let cameraX: Float = 2 * Float(x) / Float(w) - 1
                let rdX = dirX + planeX * cameraX
                let rdY = dirY + planeY * cameraX
                var mapX = gboomI32(p.x.rounded(.down)), mapY = gboomI32(p.y.rounded(.down))
                let deltaX: Float = rdX == 0 ? .greatestFiniteMagnitude : abs(1 / rdX)
                let deltaY: Float = rdY == 0 ? .greatestFiniteMagnitude : abs(1 / rdY)
                let stepX: Int, stepY: Int
                var sideX: Float, sideY: Float
                if rdX < 0 { stepX = -1; sideX = (p.x - Float(mapX)) * deltaX } else { stepX = 1; sideX = (Float(mapX) + 1 - p.x) * deltaX }
                if rdY < 0 { stepY = -1; sideY = (p.y - Float(mapY)) * deltaY } else { stepY = 1; sideY = (Float(mapY) + 1 - p.y) * deltaY }

                // DDA to the first solid cell. The border is solid, but the loop is bounded anyway.
                var side = 0
                var textureID: UInt8 = 1
                for _ in 0..<256 {
                    if sideX < sideY { sideX += deltaX; mapX += stepX; side = 0 }
                    else { sideY += deltaY; mapY += stepY; side = 1 }
                    let cell = game.map.cell(mapX, mapY)
                    if cell != 0 { textureID = cell; break }
                }

                var perpendicular: Float = side == 0
                    ? (Float(mapX) - p.x + Float(1 - stepX) / 2) / rdX
                    : (Float(mapY) - p.y + Float(1 - stepY) / 2) / rdY
                perpendicular = Float.maximum(perpendicular, 1e-4)
                fb.depth[x] = perpendicular

                let lineHeight = gboomI32(Float(h) / perpendicular)
                let drawStart = max((h - lineHeight) / 2, 0)
                let drawEnd = min((h + lineHeight) / 2, h)
                fb.wallTop[x] = drawStart
                fb.wallBottom[x] = drawEnd

                var wallX = side == 0 ? p.y + perpendicular * rdY : p.x + perpendicular * rdX
                wallX -= wallX.rounded(.down)
                var textureX = gboomUsize(wallX * Float(size))
                if (side == 0 && rdX > 0) || (side == 1 && rdY < 0) { textureX = size - 1 - min(textureX, size - 1) }

                let texture = walls[min(Int(textureID) - 1, walls.count - 1)]
                let sideShade: Float = side == 1 ? 0.72 : 1.0
                let fogShade = (1 / (1 + perpendicular * GboomRender.fog)) * sideShade * light
                let textureStep = Float(size) / Float(max(lineHeight, 1))
                var texturePosition = (Float(drawStart) - Float(h) / 2 + Float(lineHeight) / 2) * textureStep
                guard drawStart < drawEnd else { continue }
                texture.pixels.withUnsafeBufferPointer { texels in
                    for y in drawStart..<drawEnd {
                        let textureY = min(gboomUsize(texturePosition), size - 1)
                        texturePosition += textureStep
                        let texel = texels[(textureY & (size - 1)) * size + (textureX & (size - 1))]
                        gboomStore(buffer, (y * w + x) * 3, gboomShade(texel, fogShade))
                    }
                }
            }
        }
    }

    /// Perspective-correct floor and ceiling: each row below the horizon maps to one distance, and the
    /// ceiling row at the same distance mirrors it (the eye is at half wall height).
    private func drawFloorAndCeiling(_ fb: GboomFrameBuffer, _ game: GboomGame, light: Float) {
        let w = fb.width, h = fb.height
        let p = game.player
        let (dirX, dirY) = p.direction
        let (planeX, planeY) = (-dirY * GboomRender.planeLength, dirX * GboomRender.planeLength)
        let (ray0X, ray0Y) = (dirX - planeX, dirY - planeY)
        let (ray1X, ray1Y) = (dirX + planeX, dirY + planeY)
        let cameraZ: Float = 0.5 * Float(h)
        let size = Float(gboomTextureSize)
        let wallTop = fb.wallTop, wallBottom = fb.wallBottom
        floor.pixels.withUnsafeBufferPointer { floorTexels in
            ceiling.pixels.withUnsafeBufferPointer { ceilingTexels in
                fb.pixels.withUnsafeMutableBufferPointer { buffer in
                    for y in (h / 2)..<h {
                        // Rows at the horizon map to (near) infinite distance.
                        let rowDistance = cameraZ / Float(max(y - h / 2, 1))
                        let fog = (1 / (1 + rowDistance * GboomRender.fog)) * light
                        let stepX = rowDistance * (ray1X - ray0X) / Float(w)
                        let stepY = rowDistance * (ray1Y - ray0Y) / Float(w)
                        var worldX = p.x + rowDistance * ray0X
                        var worldY = p.y + rowDistance * ray0Y
                        let ceilingY = h - 1 - y
                        for x in 0..<w {
                            let (wx, wy) = (worldX, worldY)
                            worldX += stepX
                            worldY += stepY
                            let floorVisible = y >= wallBottom[x]
                            let ceilingVisible = ceilingY < wallTop[x]
                            if !floorVisible && !ceilingVisible { continue }
                            let tx = gboomUsize(gboomRemEuclid(wx, 1) * size) & (gboomTextureSize - 1)
                            let ty = gboomUsize(gboomRemEuclid(wy, 1) * size) & (gboomTextureSize - 1)
                            let texel = ty * gboomTextureSize + tx
                            if floorVisible { gboomStore(buffer, (y * w + x) * 3, gboomShade(floorTexels[texel], fog)) }
                            if ceilingVisible { gboomStore(buffer, (ceilingY * w + x) * 3, gboomShade(ceilingTexels[texel], fog)) }
                        }
                    }
                }
            }
        }
    }

    private func drawImps(_ fb: GboomFrameBuffer, _ game: GboomGame, light: Float) {
        let w = fb.width, h = fb.height
        let p = game.player
        let (dirX, dirY) = p.direction
        let (planeX, planeY) = (-dirY * GboomRender.planeLength, dirX * GboomRender.planeLength)
        let inverseDeterminant = 1 / (planeX * dirY - dirX * planeY)

        // Painter's order, far to near; ties keep map order, as the terminal's small-array sort does.
        fb.spriteOrder.removeAll(keepingCapacity: true)
        for (index, imp) in game.imps.enumerated() {
            let dx = imp.x - p.x, dy = imp.y - p.y
            fb.spriteOrder.append((index, dx * dx + dy * dy))
        }
        fb.spriteOrder.sort { $0.distance == $1.distance ? $0.index < $1.index : $0.distance > $1.distance }

        for (index, _) in fb.spriteOrder {
            let imp = game.imps[index]
            let relX = imp.x - p.x, relY = imp.y - p.y
            // Camera space: ty is depth, tx is lateral.
            let tx = inverseDeterminant * (dirY * relX - dirX * relY)
            let ty = inverseDeterminant * (-planeY * relX + planeX * relY)
            if ty <= 0.08 { continue }

            let visual = imp.visual
            let sprite = impSprites.sprite(visual)
            let screenX = (Float(w) / 2) * (1 + tx / ty)
            // Feet at world height 0 and head at impWorldHeight, with the eye at 0.5.
            let feetY = Float(h) / 2 + 0.5 * Float(h) / ty
            let headY = Float(h) / 2 + (0.5 - GboomRender.impWorldHeight) * Float(h) / ty
            let spriteHeight = Float.maximum(feetY - headY, 1)
            let spriteWidth = spriteHeight * Float(sprite.width) / Float(sprite.height)
            // A small vertical bob while walking sells the gait.
            let bob: Float = imp.walkBob.map { $0 * spriteHeight * 0.02 } ?? 0
            let x0 = gboomI32((screenX - spriteWidth / 2).rounded(.down))
            let x1 = gboomI32((screenX + spriteWidth / 2).rounded(.up))
            let y0 = gboomI32((headY + bob).rounded(.down))
            let y1 = gboomI32((feetY + bob).rounded(.up))
            let fogShade = (1 / (1 + ty * GboomRender.fog)) * light

            if visual != .corpse { drawContactShadow(fb, centerX: screenX, feetY: feetY, spriteWidth: spriteWidth, spriteHeight: spriteHeight, depth: ty) }

            // Pain frames flash toward white so hits register instantly.
            let painFlash = visual == .pain
            let columnSpan = Float(max(x1 - x0, 1)), rowSpan = Float(max(y1 - y0, 1))
            let startX = max(x0, 0), endX = min(x1, w), startY = max(y0, 0), endY = min(y1, h)
            guard startX < endX, startY < endY else { continue }
            let depth = fb.depth
            fb.pixels.withUnsafeMutableBufferPointer { buffer in
                for sx in startX..<endX {
                    if depth[sx] <= ty { continue }
                    let u = (Float(sx) - Float(x0)) / columnSpan
                    for sy in startY..<endY {
                        let v = (Float(sy) - Float(y0)) / rowSpan
                        guard let color = sprite.sample(u, v) else { continue }
                        // Glowing eyes ignore fog; everything else fades.
                        var lit = color == GboomPalette.eyeGlow ? color : gboomShade(color, fogShade)
                        if painFlash { lit = gboomLerp(lit, GboomRGB(255, 255, 255), 0.40) }
                        gboomStore(buffer, (sy * w + sx) * 3, lit)
                    }
                }
            }
        }
    }

    /// A soft elliptical shadow at an imp's feet, depth-tested per column like the body.
    private func drawContactShadow(_ fb: GboomFrameBuffer, centerX: Float, feetY: Float, spriteWidth: Float, spriteHeight: Float, depth: Float) {
        let w = fb.width, h = fb.height
        let rx = Float.maximum(spriteWidth * 0.38, 1)
        let ry = Float.maximum(spriteHeight * 0.05, 1.5)
        let x0 = gboomI32((centerX - rx).rounded(.down)), x1 = gboomI32((centerX + rx).rounded(.up))
        let y0 = gboomI32((feetY - ry).rounded(.down)), y1 = gboomI32((feetY + ry).rounded(.up))
        let startX = max(x0, 0), endX = min(x1, w), startY = max(y0, 0), endY = min(y1, h)
        guard startX < endX, startY < endY else { return }
        let depths = fb.depth
        fb.pixels.withUnsafeMutableBufferPointer { buffer in
            for sx in startX..<endX {
                if depths[sx] <= depth { continue }
                let nx = (Float(sx) - centerX) / rx
                for sy in startY..<endY {
                    let ny = (Float(sy) - feetY) / ry
                    let r2 = nx * nx + ny * ny
                    guard r2 < 1 else { continue }
                    // Darkest at the centre, fading toward the rim.
                    let f: Float = 0.55 + 0.45 * r2
                    let index = (sy * w + sx) * 3
                    buffer[index] = gboomU8(Float(buffer[index]) * f)
                    buffer[index + 1] = gboomU8(Float(buffer[index + 1]) * f)
                    buffer[index + 2] = gboomU8(Float(buffer[index + 2]) * f)
                }
            }
        }
    }

    private func applyVignette(_ fb: GboomFrameBuffer) {
        let w = fb.width
        let vignetteX = fb.vignetteX, vignetteY = fb.vignetteY
        fb.pixels.withUnsafeMutableBufferPointer { buffer in
            for y in 0..<fb.height {
                let vy = vignetteY[y]
                var index = y * w * 3
                for x in 0..<w {
                    let f = vignetteX[x] * vy
                    buffer[index] = gboomU8(Float(buffer[index]) * f)
                    buffer[index + 1] = gboomU8(Float(buffer[index + 1]) * f)
                    buffer[index + 2] = gboomU8(Float(buffer[index + 2]) * f)
                    index += 3
                }
            }
        }
    }

    private func drawGun(_ fb: GboomFrameBuffer, _ game: GboomGame) {
        let w = fb.width, h = fb.height
        let sprite = game.player.muzzle > 0 ? guns.fire : guns.idle
        // The gun fills about 42% of the frame height, bottom centre, and bobs as the player walks.
        let gunHeight = gboomI32(Float(h) * 0.42)
        let gunWidth = gunHeight * sprite.width / sprite.height
        let bobX = sin(game.player.bob * 1.7) * Float(w) * 0.012
        let bobY = abs(cos(game.player.bob * 3.4)) * Float(h) * 0.018
        let x0 = w / 2 - gunWidth / 2 + gboomI32(bobX)
        let y0 = h - gunHeight + gboomI32(bobY)
        let startX = max(x0, 0), endX = min(x0 + gunWidth, w), startY = max(y0, 0)
        if startX < endX && startY < h {
            fb.pixels.withUnsafeMutableBufferPointer { buffer in
                for sy in startY..<h {
                    let v = Float(sy - y0) / Float(max(gunHeight, 1))
                    for sx in startX..<endX {
                        let u = Float(sx - x0) / Float(max(gunWidth, 1))
                        if let color = sprite.sample(u, v) { gboomStore(buffer, (sy * w + sx) * 3, color) }
                    }
                }
            }
        }

        // Crosshair: red with a centre dot over a hittable imp.
        let (cx, cy) = (w / 2, h / 2)
        let onTarget = game.targetInCrosshair() != nil
        let color = onTarget ? GboomPalette.red : GboomRGB(210, 210, 210)
        for d in 2..<5 {
            if cx >= d && cx + d < w { fb.put(cx - d, cy, color); fb.put(cx + d, cy, color) }
            if cy >= d && cy + d < h { fb.put(cx, cy - d, color); fb.put(cx, cy + d, color) }
        }
        if onTarget { fb.put(cx, cy, color) }
    }
}

// MARK: - Title and end screens

/// The PSX-style fire: a cellular automaton on a coarse grid, upscaled when drawn. Heat 0–36 indexes a palette.
struct GboomFireSim {
    static let maxHeat: UInt8 = 36
    let width = 160
    let height = 84
    private(set) var heat: [UInt8]
    private var rng = GboomXorShift64(seed: 0xDEAD_BEEF_CAFE_F00D)

    init() {
        heat = [UInt8](repeating: 0, count: width * height)
        // The bottom row is the white-hot source.
        for x in 0..<width { heat[(height - 1) * width + x] = Self.maxHeat }
    }

    /// One step: heat rises a row with random cooling and a random left/right drift.
    mutating func step() {
        for y in 1..<height {
            for x in 0..<width {
                let r = rng.nextU32()
                let decay = Int(r & 1)
                let drift = Int((r >> 2) % 3)
                let target = ((x + drift - 1) % width + width) % width
                heat[(y - 1) * width + target] = UInt8(max(Int(heat[y * width + x]) - decay, 0))
            }
        }
    }

    static func color(_ heat: UInt8) -> GboomRGB {
        // Black through deep red, orange, and yellow to white.
        let t = Float(heat) / Float(maxHeat)
        if t < 0.02 { return GboomRGB(7, 7, 9) }
        if t < 0.4 { return gboomLerp(GboomRGB(24, 8, 6), GboomRGB(180, 30, 10), t / 0.4) }
        if t < 0.75 { return gboomLerp(GboomRGB(180, 30, 10), GboomRGB(240, 150, 30), (t - 0.4) / 0.35) }
        return gboomLerp(GboomRGB(240, 150, 30), GboomRGB(255, 250, 200), (t - 0.75) / 0.25)
    }

    /// Draws the fire across the bottom `fraction` of the frame.
    func draw(_ fb: GboomFrameBuffer, fraction: Float) {
        let w = fb.width, h = fb.height
        guard w > 0, h > 0 else { return }
        let fireHeight = gboomUsize(Float(h) * fraction)
        let startY = h - min(fireHeight, h)
        guard startY < h else { return }
        let palette = (0...Int(Self.maxHeat)).map { Self.color(UInt8($0)) }
        fb.pixels.withUnsafeMutableBufferPointer { buffer in
            for y in startY..<h {
                let fy = min((y - startY) * height / max(fireHeight, 1), height - 1)
                for x in 0..<w {
                    let fx = min(x * width / w, width - 1)
                    let value = heat[fy * width + fx]
                    if value > 1 { gboomStore(buffer, (y * w + x) * 3, palette[min(Int(value), palette.count - 1)]) }
                }
            }
        }
    }
}

enum GboomText {
    /// Pixel width of `text` at `scale` (5×7 glyphs, 1 px tracking).
    static func width(_ text: String, scale: Int) -> Int { text.count * 6 * scale }

    /// Draws 5×7 text with its top-left corner at `(x0, y0)`.
    static func draw(_ fb: GboomFrameBuffer, _ text: String, x0: Int, y0: Int, scale: Int, color: GboomRGB) {
        var penX = x0
        for character in text {
            for (row, bits) in gboomGlyph(character).enumerated() {
                for column in 0..<5 where bits & (1 << (4 - column)) != 0 {
                    for dy in 0..<scale {
                        for dx in 0..<scale {
                            let px = penX + column * scale + dx, py = y0 + row * scale + dy
                            if px >= 0 && py >= 0 && px < fb.width && py < fb.height { fb.put(px, py, color) }
                        }
                    }
                }
            }
            penX += 6 * scale
        }
    }

    /// Centred text with an eight-way outline, which keeps the chunky font legible over the fire.
    static func drawCenteredOutlined(_ fb: GboomFrameBuffer, _ text: String, y0: Int, scale: Int, color: GboomRGB, outline: GboomRGB) {
        let x0 = (fb.width - width(text, scale: scale)) / 2
        let o = max(scale / 2, 1)
        for (dx, dy) in [(-o, -o), (0, -o), (o, -o), (-o, 0), (o, 0), (-o, o), (0, o), (o, o)] {
            draw(fb, text, x0: x0 + dx, y0: y0 + dy, scale: scale, color: outline)
        }
        draw(fb, text, x0: x0, y0: y0, scale: scale, color: color)
    }
}
