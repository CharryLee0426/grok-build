import AppKit
import CoreGraphics
import CoreText

/// A laid-out box in TeX's sense: a width, a height above the baseline and a depth
/// below it, plus something to draw. Coordinates are y-up with the origin at the
/// left end of the baseline.
final class MathBox {
    var width: CGFloat
    var height: CGFloat
    var depth: CGFloat
    /// Italic correction of a single-glyph box (superscripts attach after it).
    var italicCorrection: CGFloat = 0
    /// Where a top accent attaches (x); nil means "center of the box".
    var topAccentAttachment: CGFloat?
    /// True when this box is a single math glyph (TeX's "character box" for scripts).
    var isCharacter = false
    /// Glyph/size of a single-glyph box, for cut-in kerning of scripts.
    var kernGlyph: CGGlyph?
    var content: MathBoxContent

    init(width: CGFloat = 0, height: CGFloat = 0, depth: CGFloat = 0, content: MathBoxContent = .empty) {
        self.width = width
        self.height = height
        self.depth = depth
        self.content = content
    }

    static func kern(_ width: CGFloat) -> MathBox {
        MathBox(width: width)
    }

    /// Horizontal concatenation on a common baseline.
    static func hbox(_ boxes: [MathBox]) -> MathBox {
        var children: [MathPlacedBox] = []
        var x: CGFloat = 0
        for b in boxes {
            children.append(MathPlacedBox(box: b, x: x, y: 0))
            x += b.width
        }
        return group(children, width: x)
    }

    /// A container whose height/depth are computed from its children.
    static func group(_ children: [MathPlacedBox], width: CGFloat) -> MathBox {
        var height: CGFloat = 0
        var depth: CGFloat = 0
        for c in children {
            height = max(height, c.y + c.box.height)
            depth = max(depth, c.box.depth - c.y)
        }
        return MathBox(width: width, height: height, depth: depth, content: .group(children))
    }

    /// Returns a box that draws `self` raised by `dy` (negative lowers it).
    func shifted(by dy: CGFloat) -> MathBox {
        guard dy != 0 else { return self }
        let box = MathBox(width: width, height: height + dy, depth: depth - dy,
                          content: .group([MathPlacedBox(box: self, x: 0, y: dy)]))
        box.italicCorrection = italicCorrection
        box.topAccentAttachment = topAccentAttachment
        return box
    }
}

struct MathPlacedBox {
    let box: MathBox
    let x: CGFloat
    let y: CGFloat
}

enum MathBoxContent {
    case empty
    /// A glyph of the math font; `ink` is its bounding box relative to the origin.
    case glyph(CGGlyph, size: CGFloat, color: CGColor, ink: CGRect)
    /// A filled rectangle covering the box.
    case rule(CGColor)
    /// A stroked path (relative to the origin).
    case stroke(CGPath, lineWidth: CGFloat, color: CGColor)
    /// A CoreText line (text mode, fallback characters).
    case text(CTLine, color: CGColor, ink: CGRect)
    case group([MathPlacedBox])
}

/// Flattened drawing commands with absolute positions.
enum MathDrawOp {
    case glyphs(font: CTFont, glyphs: [CGGlyph], positions: [CGPoint], color: CGColor)
    case rect(CGRect, CGColor)
    case stroke(CGPath, origin: CGPoint, lineWidth: CGFloat, color: CGColor)
    case line(CTLine, origin: CGPoint, color: CGColor)
}

/// An immutable, ready-to-draw formula.
final class MathDisplayList {
    let ops: [MathDrawOp]
    /// Union of advance boxes and ink, relative to the baseline origin.
    let bounds: CGRect
    let glyphCount: Int

    /// Accumulates ops while walking the box tree, merging consecutive glyphs that
    /// share a size and color into a single CTFontDrawGlyphs call.
    private final class Builder {
        var ops: [MathDrawOp] = []
        var bounds: CGRect
        var glyphCount = 0
        private var runSize: CGFloat = 0
        private var runColor: CGColor?
        private var runGlyphs: [CGGlyph] = []
        private var runPositions: [CGPoint] = []
        let font: MathFont

        init(font: MathFont, bounds: CGRect) {
            self.font = font
            self.bounds = bounds
        }

        func addGlyph(_ glyph: CGGlyph, at point: CGPoint, size: CGFloat, color: CGColor) {
            guard glyph != 0 else {
                font.recordMissing(0)  // never draw .notdef
                return
            }
            glyphCount += 1
            if runColor == nil || runSize != size || runColor != color { flushRun() }
            runSize = size
            runColor = color
            runGlyphs.append(glyph)
            runPositions.append(point)
        }

        func add(_ op: MathDrawOp) {
            flushRun()
            ops.append(op)
        }

        func flushRun() {
            guard let color = runColor, !runGlyphs.isEmpty else { return }
            ops.append(.glyphs(font: font.ctFont(size: runSize), glyphs: runGlyphs, positions: runPositions, color: color))
            runGlyphs.removeAll()
            runPositions.removeAll()
            runColor = nil
        }
    }

    init(box: MathBox, font: MathFont) {
        let builder = Builder(font: font, bounds: CGRect(x: 0, y: -box.depth, width: box.width, height: box.height + box.depth))
        MathDisplayList.flatten(box, at: .zero, into: builder)
        builder.flushRun()
        ops = builder.ops
        bounds = builder.bounds.mathOutsetToGrid
        glyphCount = builder.glyphCount
    }

    private static func flatten(_ box: MathBox, at origin: CGPoint, into b: Builder) {
        switch box.content {
        case .empty:
            break
        case let .glyph(glyph, size, color, ink):
            b.bounds = b.bounds.union(ink.offsetBy(dx: origin.x, dy: origin.y))
            b.addGlyph(glyph, at: origin, size: size, color: color)
        case .rule(let color):
            let rect = CGRect(x: origin.x, y: origin.y - box.depth, width: box.width, height: box.height + box.depth)
            guard rect.width > 0, rect.height > 0 else { return }
            b.bounds = b.bounds.union(rect)
            b.add(.rect(rect, color))
        case let .stroke(path, lineWidth, color):
            let rect = path.boundingBoxOfPath.insetBy(dx: -lineWidth, dy: -lineWidth).offsetBy(dx: origin.x, dy: origin.y)
            b.bounds = b.bounds.union(rect)
            b.add(.stroke(path, origin: origin, lineWidth: lineWidth, color: color))
        case let .text(line, color, ink):
            if !ink.isEmpty { b.bounds = b.bounds.union(ink.offsetBy(dx: origin.x, dy: origin.y)) }
            b.add(.line(line, origin: origin, color: color))
        case .group(let children):
            for child in children {
                let p = CGPoint(x: origin.x + child.x, y: origin.y + child.y)
                let c = child.box
                // Every child's advance box counts toward the image bounds.
                if c.width != 0 || c.height != 0 || c.depth != 0 {
                    b.bounds = b.bounds.union(CGRect(x: p.x, y: p.y - c.depth, width: max(c.width, 0), height: c.height + c.depth))
                }
                flatten(c, at: p, into: b)
            }
        }
    }

    func draw(in context: CGContext) {
        context.textMatrix = .identity
        for op in ops {
            switch op {
            case let .glyphs(font, glyphs, positions, color):
                // Glyph positions are in text space, whose origin is the text position
                // that CTLineDraw advances; reset it so positions are absolute.
                context.textMatrix = .identity
                context.textPosition = .zero
                context.setFillColor(color)
                CTFontDrawGlyphs(font, glyphs, positions, glyphs.count, context)
            case let .rect(rect, color):
                context.setFillColor(color)
                context.fill(rect)
            case let .stroke(path, origin, lineWidth, color):
                context.saveGState()
                context.translateBy(x: origin.x, y: origin.y)
                context.setStrokeColor(color)
                context.setLineWidth(lineWidth)
                context.setLineCap(.round)
                context.addPath(path)
                context.strokePath()
                context.restoreGState()
            case let .line(line, origin, _):
                context.textPosition = origin
                CTLineDraw(line, context)
            }
        }
    }
}

extension CGRect {
    /// Rounds outward to 1/64 pt so tiny float noise never clips antialiased edges.
    var mathOutsetToGrid: CGRect {
        let q: CGFloat = 64
        let minX = (self.minX * q).rounded(.down) / q
        let minY = (self.minY * q).rounded(.down) / q
        let maxX = (self.maxX * q).rounded(.up) / q
        let maxY = (self.maxY * q).rounded(.up) / q
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
