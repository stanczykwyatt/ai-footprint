// Draws the app icon and writes it to Resources/AppIcon.icns, plus docs/icon.png for the website.
//
//   swift scripts/make-icon.swift
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns"

/// Draws the icon on a 1024-point canvas, scaled to `pixels`.
func icon(pixels: Int) -> NSBitmapImageRep {
    let image = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(pixels) / 1024)
    scale.concat()

    let slate = NSColor(srgbRed: 0.13, green: 0.17, blue: 0.27, alpha: 1)
    let ice = NSColor(srgbRed: 0.62, green: 0.82, blue: 1.0, alpha: 1)

    // The rounded tile, with the soft shadow macOS icons sit on. Same tile and light as Show Desktop.
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let tileShadow = NSShadow()
    tileShadow.shadowColor = .black.withAlphaComponent(0.3)
    tileShadow.shadowBlurRadius = 24
    tileShadow.shadowOffset = NSSize(width: 0, height: -12)
    tileShadow.set()
    slate.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [
        NSColor(srgbRed: 0.80, green: 0.87, blue: 0.96, alpha: 1),
        NSColor(srgbRed: 0.45, green: 0.57, blue: 0.75, alpha: 1),
        slate,
    ])!.draw(in: tile, angle: -90)

    /// One shoeprint: a rounded sole and a separate heel, tilted along the path it walks.
    func print(at center: NSPoint, angle: CGFloat, size: CGFloat, color: NSColor, glow: Bool) {
        NSGraphicsContext.saveGraphicsState()
        let move = NSAffineTransform()
        move.translateX(by: center.x, yBy: center.y)
        move.rotate(byDegrees: angle)
        move.concat()
        let sole = NSBezierPath(roundedRect: NSRect(x: -size * 0.25, y: -size * 0.06, width: size * 0.5, height: size * 0.62), xRadius: size * 0.25, yRadius: size * 0.29)
        let heel = NSBezierPath(roundedRect: NSRect(x: -size * 0.2, y: -size * 0.56, width: size * 0.4, height: size * 0.4), xRadius: size * 0.2, yRadius: size * 0.2)
        if glow {
            let shine = NSShadow()
            shine.shadowColor = color.withAlphaComponent(0.7)
            shine.shadowBlurRadius = size * 0.22
            shine.set()
        } else {
            let drop = NSShadow()
            drop.shadowColor = NSColor.black.withAlphaComponent(0.18)
            drop.shadowBlurRadius = 10
            drop.shadowOffset = NSSize(width: 0, height: -6)
            drop.set()
        }
        color.setFill()
        sole.fill()
        heel.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    // A trail of prints walking down the tile, faded where they started and freshest at the bottom,
    // where the newest one glows in ice blue against the slate.
    let steps: [(x: CGFloat, y: CGFloat, alpha: CGFloat)] = [
        (610, 770, 0.30), (420, 625, 0.48), (612, 470, 0.7), (418, 310, 1),
    ]
    for (index, step) in steps.enumerated() {
        let last = index == steps.count - 1
        print(
            at: NSPoint(x: step.x, y: step.y), angle: index.isMultiple(of: 2) ? 192 : 168, size: 215,
            color: last ? ice : NSColor.white.withAlphaComponent(step.alpha), glow: last
        )
    }

    NSGraphicsContext.restoreGraphicsState()
    return image
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let png = icon(pixels: points * scale).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}
try icon(pixels: 256).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/icon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", iconset.path, "--output", output]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
Swift.print("Wrote \(output) and docs/icon.png")
