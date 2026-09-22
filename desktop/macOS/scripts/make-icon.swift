import AppKit

// Reproducible, vector-drawn application icon. No external assets or tooling.
let destination = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns"
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("GrokDesktop-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        let inset = p * 0.065
        let frame = NSRect(x: inset, y: inset, width: p - inset * 2, height: p - inset * 2)
        NSColor(srgbRed: 0.10, green: 0.12, blue: 0.11, alpha: 1).setFill()
        NSBezierPath(roundedRect: frame, xRadius: p * 0.21, yRadius: p * 0.21).fill()
        NSColor(srgbRed: 0.94, green: 0.95, blue: 0.90, alpha: 1).setStroke()
        let center = CGPoint(x: p * 0.5, y: p * 0.5)
        for degrees in [14.0, 74.0, 134.0] {
            let angle = degrees * .pi / 180
            let radius = p * 0.24
            let path = NSBezierPath()
            path.move(to: CGPoint(x: center.x - cos(angle) * radius, y: center.y - sin(angle) * radius))
            path.line(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
            path.lineWidth = p * 0.068; path.lineCapStyle = .round; path.stroke()
        }
        image.unlockFocus()
        guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not render icon") }
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try png.write(to: iconset.appendingPathComponent(name))
    }
}
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "-o", destination, iconset.path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
