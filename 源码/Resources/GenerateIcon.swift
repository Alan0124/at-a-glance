import AppKit
import Foundation

// Reproducible, code-drawn macOS icon. No remote assets or image-generation tools.
let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let iconset = destination.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func makeIcon(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "Icon", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    let outer = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
    NSColor(calibratedRed: 0.88, green: 0.89, blue: 0.84, alpha: 1).setFill()
    outer.fill()
    let panel = NSBezierPath(roundedRect: NSRect(x: 174, y: 170, width: 676, height: 686), xRadius: 78, yRadius: 78)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.14)
    shadow.shadowBlurRadius = 32
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    NSColor(calibratedRed: 0.98, green: 0.97, blue: 0.94, alpha: 1).setFill()
    panel.fill()
    NSShadow().set()

    NSColor(calibratedRed: 0.31, green: 0.36, blue: 0.29, alpha: 1).setStroke()
    let check = NSBezierPath()
    check.move(to: NSPoint(x: 257, y: 652))
    check.line(to: NSPoint(x: 294, y: 614))
    check.line(to: NSPoint(x: 360, y: 691))
    check.lineWidth = 29
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    check.stroke()

    NSColor(calibratedRed: 0.35, green: 0.36, blue: 0.33, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 407, y: 634, width: 290, height: 25), xRadius: 12.5, yRadius: 12.5).fill()
    for y: CGFloat in [477, 326] {
        let box = NSBezierPath(roundedRect: NSRect(x: 272, y: y - 22, width: 51, height: 51), xRadius: 12, yRadius: 12)
        NSColor(calibratedRed: 0.66, green: 0.68, blue: 0.62, alpha: 1).setStroke()
        box.lineWidth = 12
        box.stroke()
        NSColor(calibratedRed: 0.63, green: 0.65, blue: 0.59, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 407, y: y - 8, width: y > 400 ? 290 : 213, height: 22), xRadius: 11, yRadius: 11).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let result = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Icon", code: 2)
    }
    return result
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let filename = "icon_\(base)x\(base)\(suffix).png"
        try makeIcon(size: base * scale).write(to: iconset.appendingPathComponent(filename))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", destination.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Generated \(destination.appendingPathComponent("AppIcon.icns").path)")
