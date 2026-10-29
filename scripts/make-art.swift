// Draws the README demo (docs/demo.gif) and the link preview image (docs/social.png).
// Everything is drawn here rather than recorded, so the art never shows anyone's real desktop.
// Driftwood Code, the tool that grows its logs and adds a login item, is made up, so no real
// tool is shown misbehaving.
//
//   swift scripts/make-art.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

let ink = NSColor(srgbRed: 0.05, green: 0.06, blue: 0.07, alpha: 1)
let ice = NSColor(srgbRed: 0.62, green: 0.82, blue: 1.0, alpha: 1)
let warn = NSColor(srgbRed: 1.0, green: 0.68, blue: 0.26, alpha: 1)

func bitmap(_ width: Int, _ height: Int, draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Cool silver light on a dark wallpaper, like Show Desktop's art.
func wallpaper(_ rect: NSRect) {
    NSGradient(starting: NSColor(srgbRed: 0.08, green: 0.09, blue: 0.13, alpha: 1), ending: ink)!.draw(in: rect, angle: -90)
    let glows: [(CGFloat, CGFloat, CGFloat, NSColor)] = [
        (0.18, 0.75, 0.42, NSColor(srgbRed: 0.84, green: 0.89, blue: 0.95, alpha: 0.45)),
        (0.85, 0.72, 0.38, NSColor(srgbRed: 0.59, green: 0.68, blue: 0.81, alpha: 0.40)),
        (0.70, 0.12, 0.46, NSColor(srgbRed: 0.75, green: 0.81, blue: 0.89, alpha: 0.32)),
        (0.22, 0.15, 0.30, NSColor(srgbRed: 0.44, green: 0.53, blue: 0.65, alpha: 0.32)),
    ]
    for (x, y, r, color) in glows {
        let center = NSPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        NSGradient(starting: color, ending: color.withAlphaComponent(0))!
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: rect.width * r, options: [])
    }
}

func symbol(_ name: String, size: CGFloat, colors: [NSColor], weight: NSFont.Weight = .regular) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight).applying(.init(paletteColors: colors))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
}

@discardableResult
func text(
    _ string: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white,
    centered: Bool = false, mono: Bool = false
) -> CGFloat {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let width = (string as NSString).size(withAttributes: attributes).width
    (string as NSString).draw(at: NSPoint(x: centered ? point.x - width / 2 : point.x, y: point.y), withAttributes: attributes)
    return width
}

/// A tool's icon in the menu: a gradient tile with a symbol on it. Plain colors, not any tool's own icon.
func appTile(_ rect: NSRect, symbolName: String, top: NSColor, bottom: NSColor) {
    let body = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.23, yRadius: rect.width * 0.23)
    NSGradient(starting: top, ending: bottom)!.draw(in: body, angle: -90)
    let image = symbol(symbolName, size: rect.width * 0.5, colors: [.white], weight: .semibold)
    image.draw(at: NSPoint(x: rect.midX - image.size.width / 2, y: rect.midY - image.size.height / 2), from: .zero, operation: .sourceOver, fraction: 1)
}

/// A dark app window with a title bar. Returns the content area.
@discardableResult
func window(_ frame: NSRect, title: String, alpha: CGFloat = 1, scale: CGFloat = 1, key: Bool) -> NSRect {
    let rect = NSRect(
        x: frame.midX - frame.width * scale / 2, y: frame.midY - frame.height * scale / 2,
        width: frame.width * scale, height: frame.height * scale
    )
    let body = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent((key ? 0.55 : 0.35) * alpha)
    shadow.shadowBlurRadius = key ? 30 : 18
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor(srgbRed: 0.15, green: 0.16, blue: 0.19, alpha: alpha).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.12 * alpha).setStroke()
    body.lineWidth = 1
    body.stroke()
    let colors: [NSColor] = key ? [.systemRed, .systemYellow, .systemGreen] : [.gray, .gray, .gray]
    for (index, color) in colors.enumerated() {
        color.withAlphaComponent(alpha * (key ? 1 : 0.5)).setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.minX + 14 + CGFloat(index) * 18, y: rect.maxY - 22, width: 11, height: 11)).fill()
    }
    text(title, at: NSPoint(x: rect.midX, y: rect.maxY - 24), size: 12, weight: .semibold, color: .white.withAlphaComponent((key ? 0.85 : 0.45) * alpha), centered: true)
    return NSRect(x: rect.minX + 18, y: rect.minY + 14, width: rect.width - 36, height: rect.height - 50)
}

func cursor(at point: NSPoint, pressed: Bool) {
    let arrow = NSBezierPath()
    let s: CGFloat = pressed ? 0.9 : 1
    arrow.move(to: point)
    arrow.line(to: NSPoint(x: point.x, y: point.y - 22 * s))
    arrow.line(to: NSPoint(x: point.x + 5.5 * s, y: point.y - 17 * s))
    arrow.line(to: NSPoint(x: point.x + 9.5 * s, y: point.y - 25.5 * s))
    arrow.line(to: NSPoint(x: point.x + 13 * s, y: point.y - 24 * s))
    arrow.line(to: NSPoint(x: point.x + 9 * s, y: point.y - 15.5 * s))
    arrow.line(to: NSPoint(x: point.x + 16 * s, y: point.y - 15.5 * s))
    arrow.close()
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.4)
    shadow.shadowBlurRadius = 3
    shadow.shadowOffset = NSSize(width: 0, height: -1)
    shadow.set()
    NSColor.black.setFill()
    arrow.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.setStroke()
    arrow.lineWidth = 1.5
    arrow.stroke()
}

// MARK: Scene

let width: CGFloat = 720
let height: CGFloat = 450
let menuBarHeight: CGFloat = 26
let iconCenter = NSPoint(x: width - 168, y: height - menuBarHeight / 2)
let terminalFrame = NSRect(x: 40, y: 150, width: 400, height: 210)

let command = "driftwood update"
let output = ["Downloading Driftwood Code 3.2.0…", "Installing background service…", "Updated 3.1.4 → 3.2.0"]

let teal = (NSColor(srgbRed: 0.30, green: 0.78, blue: 0.74, alpha: 1), NSColor(srgbRed: 0.10, green: 0.50, blue: 0.52, alpha: 1))
let gray = (NSColor(srgbRed: 0.62, green: 0.65, blue: 0.71, alpha: 1), NSColor(srgbRed: 0.33, green: 0.36, blue: 0.43, alpha: 1))
let indigo = (NSColor(srgbRed: 0.55, green: 0.52, blue: 0.95, alpha: 1), NSColor(srgbRed: 0.33, green: 0.28, blue: 0.78, alpha: 1))
let green = (NSColor(srgbRed: 0.45, green: 0.82, blue: 0.52, alpha: 1), NSColor(srgbRed: 0.18, green: 0.58, blue: 0.33, alpha: 1))

struct Moment {
    var typed = 0
    var lines = 0
    var caretOn = true
    var updated = false
    var cursorAt = NSPoint(x: 600, y: 120)
    var pressed = false
    var menuOpen = false
    var hovering = false
}

func scene(_ m: Moment) {
    wallpaper(NSRect(x: 0, y: 0, width: width, height: height))

    // A terminal where a made-up tool updates itself.
    let page = window(terminalFrame, title: "Terminal — zsh", key: !m.menuOpen)
    let prompt = "~ % "
    var y = page.maxY - 22
    let w = text(prompt + String(command.prefix(m.typed)), at: NSPoint(x: page.minX, y: y), size: 13, color: .white.withAlphaComponent(0.92), mono: true)
    if m.lines == 0 && m.caretOn {
        NSColor.white.withAlphaComponent(0.8).setFill()
        NSRect(x: page.minX + w + 1, y: y - 2, width: 8, height: 17).fill()
    }
    for (index, line) in output.prefix(m.lines).enumerated() {
        y -= 22
        let done = index == output.count - 1
        text(line, at: NSPoint(x: page.minX, y: y), size: 13, color: done ? NSColor(srgbRed: 0.55, green: 0.88, blue: 0.6, alpha: 1) : .white.withAlphaComponent(0.6), mono: true)
    }
    if m.lines == output.count {
        y -= 22
        let pw = text(prompt, at: NSPoint(x: page.minX, y: y), size: 13, color: .white.withAlphaComponent(0.92), mono: true)
        if m.caretOn {
            NSColor.white.withAlphaComponent(0.8).setFill()
            NSRect(x: page.minX + pw + 1, y: y - 2, width: 8, height: 17).fill()
        }
    }

    // The menu bar.
    NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 0.72).setFill()
    NSRect(x: 0, y: height - menuBarHeight, width: width, height: menuBarHeight).fill()
    text("Terminal", at: NSPoint(x: 18, y: height - 19), size: 12.5, weight: .bold)
    for (index, word) in ["Shell", "Edit", "View", "Window"].enumerated() {
        text(word, at: NSPoint(x: 92 + CGFloat(index) * 46, y: height - 19), size: 12.5)
    }
    if m.pressed || m.menuOpen {
        NSColor.white.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: NSRect(x: iconCenter.x - 15, y: height - menuBarHeight + 3, width: 30, height: menuBarHeight - 6), xRadius: 5, yRadius: 5).fill()
    }
    let menuIcon = symbol("shoeprints.fill", size: 13, colors: [.white])
    let iconX = iconCenter.x - menuIcon.size.width / 2 - (m.updated && !m.menuOpen ? 2 : 0)
    menuIcon.draw(at: NSPoint(x: iconX, y: iconCenter.y - menuIcon.size.height / 2), from: .zero, operation: .sourceOver, fraction: 1)
    if m.updated && !m.menuOpen {
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: iconCenter.x + 6, y: iconCenter.y + 2, width: 6, height: 6)).fill()
    }
    for (index, name) in ["wifi", "magnifyingglass", "switch.2"].enumerated() {
        let image = symbol(name, size: 13, colors: [.white])
        image.draw(at: NSPoint(x: width - 128 + CGFloat(index) * 30, y: height - 20), from: .zero, operation: .sourceOver, fraction: 1)
    }
    text("9:41", at: NSPoint(x: width - 40, y: height - 19), size: 12.5, weight: .medium)

    if m.menuOpen { menu(hovering: m.hovering) }
    cursor(at: m.cursorAt, pressed: m.pressed)
}

func panel(_ rect: NSRect) {
    let body = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.5)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    NSColor(srgbRed: 0.17, green: 0.18, blue: 0.21, alpha: 1).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.14).setStroke()
    body.lineWidth = 1
    body.stroke()
}

func separator(_ rect: NSRect, y: CGFloat) {
    NSColor.white.withAlphaComponent(0.12).setFill()
    NSRect(x: rect.minX + 10, y: y, width: rect.width - 20, height: 1).fill()
}

let menuWidth: CGFloat = 300
let menuRect = NSRect(x: width - 8 - menuWidth, y: height - menuBarHeight - 4 - 330, width: menuWidth, height: 330)
let updatesRowY = menuRect.minY + 44

/// The app's menu, drawn as it looks open, with the new receipt's submenu when hovered.
func menu(hovering: Bool) {
    panel(menuRect)
    let left = menuRect.minX + 14
    var y = menuRect.maxY - 26
    text("AI tools use 14 GB on this Mac", at: NSPoint(x: left, y: y), size: 13, color: .white.withAlphaComponent(0.5))
    y -= 17
    text("3 background processes · 1 login item", at: NSPoint(x: left, y: y), size: 11, color: .white.withAlphaComponent(0.4))
    y -= 12
    separator(menuRect, y: y)
    y -= 20
    text("Tools", at: NSPoint(x: left, y: y), size: 11, weight: .bold, color: .white.withAlphaComponent(0.45))
    let tools: [(String, String, String, (NSColor, NSColor))] = [
        ("Ollama 0.12.3", "8.4 GB · 2 processes", "cube.fill", gray),
        ("Driftwood Code 3.2.0", "2.6 GB · 1 process · 1 login item", "wind", teal),
        ("Hugging Face", "1.9 GB", "shippingbox.fill", green),
        ("Claude Code 2.1.4", "670 MB · 2 processes", "terminal.fill", indigo),
    ]
    for (name, detail, icon, colors) in tools {
        y -= 38
        appTile(NSRect(x: left, y: y + 3, width: 24, height: 24), symbolName: icon, top: colors.0, bottom: colors.1)
        text(name, at: NSPoint(x: left + 34, y: y + 16), size: 13)
        text(detail, at: NSPoint(x: left + 34, y: y + 1), size: 11, color: .white.withAlphaComponent(0.5))
        text("›", at: NSPoint(x: menuRect.maxX - 22, y: y + 9), size: 13, color: .white.withAlphaComponent(0.5))
    }
    y -= 12
    separator(menuRect, y: y)
    y -= 24
    text("MCP Servers (2), 1 orphaned", at: NSPoint(x: left, y: y), size: 13)
    text("›", at: NSPoint(x: menuRect.maxX - 22, y: y), size: 13, color: .white.withAlphaComponent(0.5))

    // Recent Updates, with one new.
    let row = NSRect(x: menuRect.minX + 6, y: updatesRowY - 5, width: menuRect.width - 12, height: 24)
    if hovering {
        NSColor.systemBlue.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: row, xRadius: 6, yRadius: 6).fill()
    }
    text("Recent Updates (1 new)", at: NSPoint(x: left, y: updatesRowY), size: 13, weight: hovering ? .medium : .regular)
    text("›", at: NSPoint(x: menuRect.maxX - 22, y: updatesRowY), size: 13, color: .white.withAlphaComponent(hovering ? 0.9 : 0.5))
    y = updatesRowY - 14
    separator(menuRect, y: y)
    text("Open AI Footprint…", at: NSPoint(x: left, y: y - 22), size: 13)
    text("⌘O", at: NSPoint(x: menuRect.maxX - 38, y: y - 22), size: 13, color: .white.withAlphaComponent(0.5))

    if hovering { receipt() }
}

/// The receipt for the update, opening to the left as macOS does near the screen's edge.
func receipt() {
    let lines: [(String, CGFloat, NSColor)] = [
        ("Disk: 711 MB → 2.6 GB (+1.9 GB)", 13, .white),
        ("Logs (~/.driftwood/logs): +1.9 GB", 12, .white.withAlphaComponent(0.6)),
        ("Added login item com.example.driftwood.daemon:", 13, .white),
        ("Starts at login, and again if it quits", 12, .white.withAlphaComponent(0.6)),
    ]
    // Moved up to fit on screen, as macOS does with submenus near the bottom.
    let rect = NSRect(x: menuRect.minX - 368, y: 10, width: 372, height: 182)
    panel(rect)
    let left = rect.minX + 14
    var y = rect.maxY - 46
    NSColor.systemBlue.withAlphaComponent(0.25).setFill()
    NSBezierPath(roundedRect: NSRect(x: rect.minX + 6, y: y - 5, width: rect.width - 12, height: 40), xRadius: 6, yRadius: 6).fill()
    appTile(NSRect(x: left, y: y + 2, width: 24, height: 24), symbolName: "wind", top: teal.0, bottom: teal.1)
    text("Driftwood Code 3.1.4 → 3.2.0", at: NSPoint(x: left + 34, y: y + 15), size: 13, weight: .semibold)
    text("Just now · +1.9 GB, added a login item", at: NSPoint(x: left + 34, y: y), size: 11, color: .white.withAlphaComponent(0.6))
    y -= 14
    for (line, size, color) in lines {
        y -= 22
        text(line, at: NSPoint(x: left + (size < 13 ? 12 : 0), y: y), size: size, color: color)
    }
    y -= 12
    separator(rect, y: y)
    text("Copy Receipt", at: NSPoint(x: left, y: y - 22), size: 13)
}

// MARK: Demo

func lerp(_ a: NSPoint, _ b: NSPoint, _ t: CGFloat) -> NSPoint {
    let e = t * t * (3 - 2 * t)
    return NSPoint(x: a.x + (b.x - a.x) * e, y: a.y + (b.y - a.y) * e)
}

var frames: [(NSBitmapImageRep, Double)] = []
func frame(_ m: Moment, hold: Double = 0.07) {
    // Drawn at 2x so the GIF looks sharp on Retina screens when shown at 720 points.
    let rep = bitmap(Int(width * 2), Int(height * 2)) {
        let transform = NSAffineTransform()
        transform.scale(by: 2)
        transform.concat()
        scene(m)
    }
    frames.append((rep, hold))
}

var m = Moment()
frame(m, hold: 0.7)
// A tool updates itself.
for count in 1...command.count {
    m.typed = count
    frame(m, hold: 0.06)
}
frame(m, hold: 0.3)
for line in 1...output.count {
    m.lines = line
    frame(m, hold: line == output.count ? 0.4 : 0.55)
}
// AI Footprint notices, and puts a dot on its icon.
m.updated = true
frame(m, hold: 0.9)
// What did that change? Check the menu bar.
let start = m.cursorAt
let onIcon = NSPoint(x: iconCenter.x - 2, y: iconCenter.y + 6)
for step in 1...12 {
    m.cursorAt = lerp(start, onIcon, CGFloat(step) / 12)
    frame(m, hold: 0.04)
}
m.pressed = true
frame(m, hold: 0.12)
m.pressed = false
m.menuOpen = true
frame(m, hold: 1.3)
let onUpdates = NSPoint(x: menuRect.minX + 90, y: updatesRowY + 8)
let fromIcon = m.cursorAt
for step in 1...10 {
    m.cursorAt = lerp(fromIcon, onUpdates, CGFloat(step) / 10)
    frame(m, hold: 0.04)
}
m.hovering = true
frame(m, hold: 3.6)

let gifURL = URL(fileURLWithPath: "docs/demo.gif")
let destination = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for (rep, hold) in frames {
    CGImageDestinationAddImage(destination, rep.cgImage!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: hold]] as CFDictionary)
}
guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't write the GIF") }

// The last frame on its own, for checking the art without playing the GIF.
if let preview = ProcessInfo.processInfo.environment["PREVIEW"] {
    try frames.last!.0.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: preview))
}

// MARK: Link preview

let social = bitmap(1280, 640) {
    let rect = NSRect(x: 0, y: 0, width: 1280, height: 640)
    wallpaper(rect)
    if let icon = NSImage(contentsOfFile: "docs/icon.png") {
        icon.draw(in: NSRect(x: 640 - 80, y: 380, width: 160, height: 160))
    }
    text("AI Footprint", at: NSPoint(x: 640, y: 270), size: 84, weight: .semibold, centered: true)
    text("See what AI coding tools leave on your Mac.", at: NSPoint(x: 640, y: 205), size: 30, color: .white.withAlphaComponent(0.75), centered: true)
    text("free · open source · read-only · no internet access", at: NSPoint(x: 640, y: 120), size: 22, weight: .medium, color: .white.withAlphaComponent(0.5), centered: true)
}
try social.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/social.png"))
print("Wrote docs/demo.gif and docs/social.png")
