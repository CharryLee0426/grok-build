import AppKit
import ImageIO
import UniformTypeIdentifiers

// The SVG is the single source for both the lossless artwork and each ICNS size.
// Render into explicit pixel buffers: NSImage.lockFocus() otherwise inherits display scale.
struct IconError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

struct SVGShape {
    var data: String
    var path: CGPath
    var evenOdd: Bool
}

final class SVGReader: NSObject, XMLParserDelegate {
    private(set) var viewBox: CGRect?
    private(set) var shapes: [SVGShape] = []
    private(set) var failure: Error?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        do {
            guard attributes["transform"] == nil else {
                throw IconError(message: "Flatten SVG transforms before generating the icon.")
            }
            switch elementName {
            case "svg":
                guard let raw = attributes["viewBox"] else { throw IconError(message: "GrokMark.svg needs a viewBox.") }
                let values = raw.split { $0.isWhitespace || $0 == "," }.compactMap { Double($0) }
                guard values.count == 4, values.allSatisfy(\.isFinite), values[2] > 0, values[3] > 0 else {
                    throw IconError(message: "The SVG viewBox must contain four valid numbers.")
                }
                viewBox = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            case "path":
                guard let data = attributes["d"], !data.isEmpty else { throw IconError(message: "An SVG path has no geometry.") }
                guard attributes["fill"] != "none" else { throw IconError(message: "Use filled outlines rather than strokes for the logo.") }
                shapes.append(SVGShape(data: data, path: try parsePath(data), evenOdd: attributes["fill-rule"] == "evenodd"))
            case "g", "title", "desc", "metadata": break
            default: throw IconError(message: "Unsupported SVG element: \(elementName). Convert the logo to filled paths.")
            }
        } catch {
            failure = error
            parser.abortParsing()
        }
    }
}

func parsePath(_ data: String) throws -> CGPath {
    let expression = try NSRegularExpression(pattern: #"[A-Za-z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?"#)
    let raw = data as NSString
    let matches = expression.matches(in: data, range: NSRange(location: 0, length: raw.length))
    var previousEnd = 0
    var tokens: [String] = []
    for match in matches {
        let gap = raw.substring(with: NSRange(location: previousEnd, length: match.range.location - previousEnd))
        guard gap.allSatisfy({ $0.isWhitespace || $0 == "," }) else { throw IconError(message: "Invalid SVG path syntax.") }
        tokens.append(raw.substring(with: match.range))
        previousEnd = match.range.location + match.range.length
    }
    guard raw.substring(from: previousEnd).allSatisfy({ $0.isWhitespace || $0 == "," }) else {
        throw IconError(message: "Invalid SVG path suffix.")
    }
    let path = CGMutablePath()
    var index = 0
    var command = ""
    var point = CGPoint.zero
    var start = CGPoint.zero
    var lastCubicControl: CGPoint?
    var lastQuadraticControl: CGPoint?

    func number() throws -> CGFloat {
        guard index < tokens.count, let value = Double(tokens[index]), value.isFinite else {
            throw IconError(message: "Missing coordinate in SVG path command \(command).")
        }
        index += 1
        return CGFloat(value)
    }
    func coordinate(relative: Bool) throws -> CGPoint {
        let x = try number(), y = try number()
        return CGPoint(x: x + (relative ? point.x : 0), y: y + (relative ? point.y : 0))
    }
    func reflected(_ control: CGPoint?) -> CGPoint {
        guard let control else { return point }
        return CGPoint(x: point.x * 2 - control.x, y: point.y * 2 - control.y)
    }

    while index < tokens.count {
        if tokens[index].first?.isLetter == true { command = tokens[index]; index += 1 }
        let relative = command == command.lowercased()
        let previousCubic = lastCubicControl
        let previousQuadratic = lastQuadraticControl
        lastCubicControl = nil; lastQuadraticControl = nil
        switch command.uppercased() {
        case "M":
            point = try coordinate(relative: relative); start = point; path.move(to: point)
            command = relative ? "l" : "L"
        case "L":
            point = try coordinate(relative: relative); path.addLine(to: point)
        case "H":
            point.x = try number() + (relative ? point.x : 0); path.addLine(to: point)
        case "V":
            point.y = try number() + (relative ? point.y : 0); path.addLine(to: point)
        case "C":
            let first = try coordinate(relative: relative), second = try coordinate(relative: relative)
            let end = try coordinate(relative: relative)
            path.addCurve(to: end, control1: first, control2: second)
            point = end; lastCubicControl = second
        case "S":
            let first = reflected(previousCubic)
            let second = try coordinate(relative: relative), end = try coordinate(relative: relative)
            path.addCurve(to: end, control1: first, control2: second)
            point = end; lastCubicControl = second
        case "Q":
            let control = try coordinate(relative: relative), end = try coordinate(relative: relative)
            path.addQuadCurve(to: end, control: control)
            point = end; lastQuadraticControl = control
        case "T":
            let control = reflected(previousQuadratic), end = try coordinate(relative: relative)
            path.addQuadCurve(to: end, control: control)
            point = end; lastQuadraticControl = control
        case "Z":
            path.closeSubpath(); point = start; command = ""
        default:
            throw IconError(message: "Unsupported SVG path command '\(command)'. Use M/L/H/V/C/S/Q/T/Z outlines.")
        }
    }
    guard !path.isEmpty else { throw IconError(message: "The SVG logo path is empty.") }
    return path
}

func escapedXML(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
}

let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let resourcesURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
let rawArguments = Array(CommandLine.arguments.dropFirst())
let isTestVariant = rawArguments.last == "--test"
let arguments = isTestVariant ? Array(rawArguments.dropLast()) : rawArguments
guard arguments.count <= 4 else {
    throw IconError(message: "Usage: swift make-icon.swift [AppIcon.icns] [GrokMark.svg] [GrokSymbol.swift] [AppIcon-preview.png] [--test]")
}
let destination = arguments.first.map { URL(fileURLWithPath: $0) } ?? resourcesURL.appendingPathComponent("AppIcon.icns")
let source = arguments.dropFirst().first.map { URL(fileURLWithPath: $0) } ?? resourcesURL.appendingPathComponent("GrokMark.svg")
let symbolDestination = arguments.dropFirst(2).first.map { URL(fileURLWithPath: $0) }
    ?? resourcesURL.deletingLastPathComponent().appendingPathComponent("Sources/GrokDesktop/GrokSymbol.swift")
let previewDestination = arguments.dropFirst(3).first.map { URL(fileURLWithPath: $0) }
    ?? resourcesURL.deletingLastPathComponent().appendingPathComponent("dist/AppIcon-preview.png")
let reader = SVGReader()
guard let parser = XMLParser(contentsOf: source) else { throw IconError(message: "Could not open \(source.path).") }
parser.delegate = reader
parser.shouldResolveExternalEntities = false
guard parser.parse(), let viewBox = reader.viewBox, !reader.shapes.isEmpty else {
    throw reader.failure ?? parser.parserError ?? IconError(message: "No usable paths in \(source.path).")
}
try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("GrokDesktop-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

// Standard macOS icon footprint, with a restrained monochrome mark. The test variant uses a bright
// orange field and a dark banner so a workspace build remains recognizable beside the production app.
let backgroundInset: CGFloat = 0.065
let backgroundRadius: CGFloat = 0.21
let markFraction: CGFloat = isTestVariant ? 0.52 : 0.58

func render(pixels: Int) throws -> Data {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                  bytesPerRow: pixels * 4, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw IconError(message: "Could not allocate \(pixels) × \(pixels) icon pixels.")
    }
    let side = CGFloat(pixels)
    context.setAllowsAntialiasing(true); context.setShouldAntialias(true)
    context.translateBy(x: 0, y: side); context.scaleBy(x: 1, y: -1)
    let frame = CGRect(x: side * backgroundInset, y: side * backgroundInset,
                       width: side * (1 - 2 * backgroundInset), height: side * (1 - 2 * backgroundInset))
    context.setFillColor(isTestVariant
        ? CGColor(red: 1.0, green: 0.42, blue: 0.055, alpha: 1)
        : CGColor(gray: 17.0 / 255.0, alpha: 1))
    context.addPath(CGPath(roundedRect: frame, cornerWidth: side * backgroundRadius, cornerHeight: side * backgroundRadius, transform: nil))
    context.fillPath()

    context.saveGState()
    let scale = side * markFraction / max(viewBox.width, viewBox.height)
    let markCenterY = isTestVariant ? side * 0.39 : side / 2
    context.translateBy(x: (side - viewBox.width * scale) / 2, y: markCenterY - viewBox.height * scale / 2)
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -viewBox.minX, y: -viewBox.minY)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    for shape in reader.shapes {
        context.addPath(shape.path)
        context.drawPath(using: shape.evenOdd ? .eoFill : .fill)
    }
    context.restoreGState()

    if isTestVariant {
        let banner = CGRect(x: side * 0.09, y: side * 0.755, width: side * 0.82, height: side * 0.165)
        context.setFillColor(CGColor(red: 0.70, green: 0.20, blue: 0.025, alpha: 1))
        context.addPath(CGPath(roundedRect: banner, cornerWidth: side * 0.045, cornerHeight: side * 0.045, transform: nil))
        context.fillPath()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text = "TESTING" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: side * 0.09, weight: .heavy),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let textSize = text.size(withAttributes: attributes)
        let textFrame = CGRect(x: banner.minX, y: banner.midY - textSize.height / 2,
                               width: banner.width, height: textSize.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        text.draw(in: textFrame, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    guard let image = context.makeImage() else { throw IconError(message: "Could not render icon.") }
    let data = NSMutableData()
    guard let output = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
        throw IconError(message: "Could not encode icon PNG.")
    }
    CGImageDestinationAddImage(output, image, nil)
    guard CGImageDestinationFinalize(output) else { throw IconError(message: "Could not finish icon PNG.") }
    return data as Data
}

var preview: Data?
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let png = try render(pixels: pixels)
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try png.write(to: iconset.appendingPathComponent(name), options: .atomic)
        if pixels == 256 { preview = png }
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "-o", destination.path, iconset.path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { throw IconError(message: "iconutil failed (\(process.terminationStatus)).") }

let outputBase = destination.deletingPathExtension()
if let preview {
    try FileManager.default.createDirectory(at: previewDestination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try preview.write(to: previewDestination, options: .atomic)
}
let vectorSide: CGFloat = 1024
let vectorScale = vectorSide * markFraction / max(viewBox.width, viewBox.height)
let vectorX = (vectorSide - viewBox.width * vectorScale) / 2 - viewBox.minX * vectorScale
let vectorMarkCenterY = isTestVariant ? vectorSide * 0.39 : vectorSide / 2
let vectorY = vectorMarkCenterY - viewBox.height * vectorScale / 2 - viewBox.minY * vectorScale
let paths = reader.shapes.map { "    <path d=\"\(escapedXML($0.data))\" fill-rule=\"\($0.evenOdd ? "evenodd" : "nonzero")\"/>" }.joined(separator: "\n")
let title = isTestVariant ? "Grok Desktop test app icon" : "Grok Desktop app icon"
let backgroundFill = isTestVariant ? "#FF6B0E" : "#111"
let banner = isTestVariant ? """
  <rect x="92.16" y="773.12" width="839.68" height="168.96" rx="46.08" fill="#B33306"/>
  <text x="512" y="858" fill="#fff" font-family="-apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif" font-size="92" font-weight="800" text-anchor="middle" dominant-baseline="middle">TESTING</text>
""" : ""
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <title>\(title)</title>
  <rect x="\(vectorSide * backgroundInset)" y="\(vectorSide * backgroundInset)" width="\(vectorSide * (1 - 2 * backgroundInset))" height="\(vectorSide * (1 - 2 * backgroundInset))" rx="\(vectorSide * backgroundRadius)" fill="\(backgroundFill)"/>
  <g fill="#fff" transform="translate(\(vectorX) \(vectorY)) scale(\(vectorScale))">
\(paths)
  </g>
\(banner)</svg>
"""
try svg.write(to: outputBase.appendingPathExtension("svg"), atomically: true, encoding: .utf8)

func swiftPoint(_ point: CGPoint) -> String { "CGPoint(x: \(point.x), y: \(point.y))" }
var instructions: [String] = []
for shape in reader.shapes {
    shape.path.applyWithBlock { pointer in
        let element = pointer.pointee
        switch element.type {
        case .moveToPoint: instructions.append("path.move(to: \(swiftPoint(element.points[0])))")
        case .addLineToPoint: instructions.append("path.addLine(to: \(swiftPoint(element.points[0])))")
        case .addQuadCurveToPoint:
            instructions.append("path.addQuadCurve(to: \(swiftPoint(element.points[1])), control: \(swiftPoint(element.points[0])))")
        case .addCurveToPoint:
            instructions.append("path.addCurve(to: \(swiftPoint(element.points[2])), control1: \(swiftPoint(element.points[0])), control2: \(swiftPoint(element.points[1])))")
        case .closeSubpath: instructions.append("path.closeSubpath()")
        @unknown default: break
        }
    }
}
let symbol = """
// Generated from Resources/GrokMark.svg by scripts/make-icon.swift. Do not edit by hand.
import SwiftUI

struct GrokSymbol: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
\(instructions.map { "        " + $0 }.joined(separator: "\n"))
        let scale = min(rect.width / \(viewBox.width), rect.height / \(viewBox.height))
        return path.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                             tx: rect.midX - \(viewBox.midX) * scale,
                                             ty: rect.midY - \(viewBox.midY) * scale))
    }
}

"""
try FileManager.default.createDirectory(at: symbolDestination.deletingLastPathComponent(), withIntermediateDirectories: true)
// Keep SwiftPM's incremental build intact when the canonical geometry has not changed.
if (try? String(contentsOf: symbolDestination, encoding: .utf8)) != symbol {
    try symbol.write(to: symbolDestination, atomically: true, encoding: .utf8)
}
print("Generated \(destination.path) from \(source.lastPathComponent) (16–1024 px), SVG, SwiftUI shape, and \(previewDestination.path).")
