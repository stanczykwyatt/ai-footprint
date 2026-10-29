import AppKit
import FootprintCore
import SwiftUI
import Testing
@testable import AIFootprint

/// Renders the window into a bitmap from a window that's never shown, so nothing appears on screen
/// or takes focus. Set SCREENSHOT_DIR to also save the renders as the README screenshots:
///
///   SCREENSHOT_DIR=docs swift test --filter "Window"
@MainActor
@Suite("Window")
struct WindowTests {
    @Test func rendersTheTools() async throws {
        let (model, icons) = await Gallery.make()
        let image = render(FootprintView(model: model, icons: icons, uid: 501), name: "screenshot-light", dark: false)
        #expect(image.pixelsWide >= Int(Gallery.size.width))
        #expect(colors(in: image) > 40)
    }

    @Test func rendersInDarkMode() async throws {
        let (model, icons) = await Gallery.make()
        let image = render(FootprintView(model: model, icons: icons, uid: 501), name: "screenshot-dark", dark: true)
        #expect(colors(in: image) > 40)
    }

    @Test func rendersTheUpdates() async throws {
        let (model, icons) = await Gallery.make()
        let image = render(FootprintView(model: model, icons: icons, uid: 501, tab: .updates), name: "screenshot-updates", dark: false, size: NSSize(width: 980, height: 330))
        #expect(colors(in: image) > 20)
    }

    @Test func rendersTheEmptyStates() {
        let model = makeModel()
        #expect(colors(in: render(FootprintView(model: model, icons: ToolIcons()), name: nil, dark: false)) > 4)
        #expect(colors(in: render(FootprintView(model: model, icons: ToolIcons(), tab: .updates), name: nil, dark: true)) > 4)
    }

    @Test func toolTilesAndTheMenuBarIcon() {
        let tile = ToolIcons.tile("cube")
        #expect(tile.size == NSSize(width: 64, height: 64))
        for alert in [false, true] {
            let icon = ToolIcons.statusIcon(alert: alert)
            #expect(icon.isTemplate)
            #expect(icon.size.height <= 22)
        }
        #expect(ToolIcons.statusIcon(alert: true).accessibilityDescription == "AI Footprint, new update")
        #expect(NSImage(systemSymbolName: "shoeprints.fill", accessibilityDescription: nil) != nil)
    }

    @Test func everyToolSymbolExists() {
        for tool in Tool.all + [Gallery.driftwood] {
            #expect(NSImage(systemSymbolName: tool.symbol, accessibilityDescription: nil) != nil, "Missing symbol \(tool.symbol)")
        }
        for symbol in ProcessRole.allCases.map(ProcessRow.symbol) + ["folder", "power", "exclamationmark.triangle.fill", "point.3.connected.trianglepath.dotted", "doc.plaintext", "ellipsis.circle"] {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "Missing symbol \(symbol)")
        }
    }

    @Test func iconsAreCachedAndCustomOnesWin() {
        let icons = ToolIcons()
        icons.usesAppIcons = false
        let custom = ToolIcons.tile("wind")
        icons.custom["ollama"] = custom
        let first = icons.icon(for: .ollama, size: 20)
        #expect(first.size == NSSize(width: 20, height: 20))
        #expect(icons.icon(for: .ollama, size: 20) === first)
        #expect(icons.icon(for: .ollama, size: 34).size == NSSize(width: 34, height: 34))
        #expect(icons.icon(for: .codex, size: 20).size == NSSize(width: 20, height: 20))
    }

    // MARK: Rendering

    private func render(_ view: FootprintView, name: String?, dark: Bool, size: NSSize = Gallery.size) -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        // Never ordered front: it only gives the view a backing to draw into.
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: image)
        if let name, let folder = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
            try? image.representation(using: .png, properties: [:])?.write(to: url)
        }
        return image
    }

    /// Distinct colors in a coarse grid: a blank or broken render has only a few.
    private func colors(in image: NSBitmapImageRep) -> Int {
        var seen = Set<UInt32>()
        for x in stride(from: 0, to: image.pixelsWide, by: 7) {
            for y in stride(from: 0, to: image.pixelsHigh, by: 7) {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let r = UInt32(color.redComponent * 31), g = UInt32(color.greenComponent * 31), b = UInt32(color.blueComponent * 31)
                seen.insert(r << 10 | g << 5 | b)
            }
        }
        return seen.count
    }
}
