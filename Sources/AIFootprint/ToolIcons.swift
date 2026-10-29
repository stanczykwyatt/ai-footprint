import AppKit
import FootprintCore

/// Icons for the menu and the window: the tool's app icon if it has an app, otherwise a symbol on
/// a tile. Looked up once per tool and size.
@MainActor
final class ToolIcons {
    private var cache: [String: NSImage] = [:]
    /// Icons to use instead of looking them up, by tool ID. Used for the README screenshots, whose
    /// made-up tool has no app of its own.
    var custom: [String: NSImage] = [:]
    /// Whether to use installed apps' icons. Off for the screenshots, so they look the same everywhere.
    var usesAppIcons = true

    func icon(for tool: Tool, size: CGFloat) -> NSImage {
        let key = "\(tool.id)@\(size)"
        if let cached = cache[key] { return cached }
        let icon = ((custom[tool.id] ?? source(for: tool)).copy() as? NSImage) ?? NSImage()
        icon.size = NSSize(width: size, height: size)
        cache[key] = icon
        return icon
    }

    private func source(for tool: Tool) -> NSImage {
        if usesAppIcons, let app = tool.apps.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return NSWorkspace.shared.icon(forFile: app)
        }
        return Self.tile(tool.symbol)
    }

    /// A slate tile with a symbol on it, in the app icon's colors.
    static func tile(_ symbol: String, top: NSColor = NSColor(srgbRed: 0.45, green: 0.57, blue: 0.75, alpha: 1),
                     bottom: NSColor = NSColor(srgbRed: 0.13, green: 0.17, blue: 0.27, alpha: 1)) -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            let body = NSBezierPath(roundedRect: rect.insetBy(dx: 5, dy: 5), xRadius: 13, yRadius: 13)
            NSGradient(starting: top, ending: bottom)!.draw(in: body, angle: -90)
            let config = NSImage.SymbolConfiguration(pointSize: 26, weight: .semibold).applying(.init(paletteColors: [.white]))
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let size = image.size
                image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
            }
            return true
        }
    }

    /// The menu bar icon: footprints, with a dot when there's an update you haven't looked at.
    static func statusIcon(alert: Bool) -> NSImage {
        let base = NSImage(systemSymbolName: "shoeprints.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) ?? NSImage()
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { rect in
            let size = base.size
            base.draw(in: NSRect(x: (rect.width - size.width) / 2 - (alert ? 1.5 : 0), y: (rect.height - size.height) / 2, width: size.width, height: size.height))
            if alert {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: rect.maxX - 6.5, y: rect.maxY - 7, width: 6, height: 6)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = alert ? "AI Footprint, new update" : "AI Footprint"
        return image
    }
}
