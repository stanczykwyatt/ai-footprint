import AppKit
import FootprintCore
import ServiceManagement

/// What the menu's items do. The app delegate does them; tests record them.
@MainActor
protocol StatusMenuActions: AnyObject {
    func openWindow()
    func checkNow()
    func clearReceipts()
    func toggleNotifications()
    func toggleOpenAtLogin()
    func showAbout()
}

/// Builds the menu bar menu fresh each time it opens, so sizes and processes are never stale.
@MainActor
final class StatusMenu: NSObject {
    private let model: FootprintModel
    private let icons: ToolIcons
    private weak var actions: StatusMenuActions?
    var now: () -> Date = Date.init
    var opensAtLogin: () -> Bool = { SMAppService.mainApp.status == .enabled }
    var uid: UInt32 = getuid()
    /// Whether macOS lets the app post notifications, as last checked.
    var notificationsAllowed = true

    static let receiptLimit = 8

    init(model: FootprintModel, icons: ToolIcons, actions: StatusMenuActions) {
        self.model = model
        self.icons = icons
        self.actions = actions
    }

    func build(into menu: NSMenu) {
        menu.removeAllItems()
        let now = now()

        if model.footprint == nil {
            menu.addItem(disabled(model.isChecking ? "Measuring AI tools…" : "Not checked yet"))
        } else {
            menu.addItem(disabled("AI tools use \(Describe.bytes(model.totalBytes)) on this Mac"))
            var details: [String] = []
            let background = model.backgroundProcesses.count
            details.append(background == 0 ? "Nothing running in the background" : "\(Describe.count(background, "background process", "background processes"))")
            if !model.launchItems.isEmpty { details.append(Describe.count(model.launchItems.count, "login item")) }
            menu.addItem(disabled(details.joined(separator: " · "), small: true))
        }
        menu.addItem(.separator())

        let installed = model.installedTools
        if !installed.isEmpty {
            menu.addItem(.sectionHeader(title: "Tools"))
            for tool in installed {
                menu.addItem(toolItem(tool, now: now))
            }
        } else if model.footprint != nil {
            menu.addItem(disabled("No AI tools found. They show up here once installed."))
        }

        menu.addItem(.separator())
        menu.addItem(mcpItem(now: now))
        let leftovers = model.leftRunning
        if !leftovers.isEmpty {
            let item = NSMenuItem(title: "Left Running (\(leftovers.count))", action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            let submenu = NSMenu()
            submenu.addItem(disabled("Nothing is keeping these open. Each one says how to stop it."))
            for process in leftovers {
                submenu.addItem(processItem(process, now: now))
            }
            item.submenu = submenu
            menu.addItem(item)
        }
        menu.addItem(receiptsItem(now: now))

        menu.addItem(.separator())
        menu.addItem(item("Open AI Footprint…", #selector(openWindow), key: "o"))
        let check = item(model.isChecking ? "Checking…" : "Check Now", #selector(checkNow), key: "r")
        check.isEnabled = !model.isChecking
        menu.addItem(check)
        if let checked = model.lastChecked {
            menu.addItem(disabled("Sizes checked \(Describe.relative(checked, now: now))", small: true))
        }

        menu.addItem(.separator())
        let notify = item("Notify Me About Updates", #selector(toggleNotifications))
        notify.state = model.notifies ? .on : .off
        menu.addItem(notify)
        if model.notifies && !notificationsAllowed {
            menu.addItem(disabled("Allow notifications in System Settings → Notifications"))
        }
        let login = item("Open at Login", #selector(toggleOpenAtLogin))
        login.state = opensAtLogin() ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let clear = item("Clear Update History…", #selector(clearReceipts))
        clear.isEnabled = !model.receipts.isEmpty
        menu.addItem(clear)
        menu.addItem(item("About AI Footprint", #selector(showAbout)))
        menu.addItem(NSMenuItem(title: "Quit AI Footprint", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    // MARK: Tools

    private func toolItem(_ tool: Tool, now: Date) -> NSMenuItem {
        let state = model.state(tool)
        let processes = model.processes(for: tool)
        let title = Describe.name(tool, version: state?.version)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = twoLines(title, Describe.summary(bytes: state?.bytes ?? 0, processes: processes.count, launchItems: state?.launchItems.count ?? 0))
        item.image = icons.icon(for: tool, size: 20)

        let submenu = NSMenu()
        let usage = tool.locations.compactMap { location in state?.usage[location.path].map { (location, $0) } }
            .sorted { $0.1.bytes > $1.1.bytes }
        if !usage.isEmpty {
            submenu.addItem(.sectionHeader(title: "On Disk"))
            for (location, usage) in usage {
                submenu.addItem(locationItem(location, usage: usage))
            }
        }
        if !processes.isEmpty {
            submenu.addItem(.sectionHeader(title: "Running"))
            for process in processes {
                submenu.addItem(processItem(process, now: now))
            }
        }
        if let launchItems = state?.launchItems, !launchItems.isEmpty {
            submenu.addItem(.sectionHeader(title: "Login Items"))
            for launchItem in launchItems {
                submenu.addItem(launchItemItem(launchItem))
            }
        }
        if let receipt = model.lastReceipt(for: tool) {
            submenu.addItem(.separator())
            submenu.addItem(disabled("Last change: \(Describe.headline(receipt)), \(Describe.relative(receipt.date, now: now))", small: true))
        }
        if submenu.items.isEmpty {
            submenu.addItem(disabled("Nothing measured yet"))
        }
        item.submenu = submenu
        return item
    }

    private func locationItem(_ location: Location, usage: Usage) -> NSMenuItem {
        let item = NSMenuItem(title: location.label, action: nil, keyEquivalent: "")
        item.attributedTitle = twoLines(location.label, "\(Describe.bytes(usage.bytes)) · \(location.displayPath)")
        let details = NSMenu()
        for part in usage.parts {
            details.addItem(disabled("\(part.name): \(Describe.bytes(part.bytes))"))
        }
        if !usage.parts.isEmpty { details.addItem(.separator()) }
        let reveal = self.item("Show in Finder", #selector(showInFinder(_:)))
        reveal.representedObject = Home.url(location.path).path
        details.addItem(reveal)
        details.addItem(disabled("AI Footprint never deletes anything. Remove files yourself, or with the tool's own settings.", small: true))
        item.submenu = details
        return item
    }

    private func processItem(_ process: ToolProcess, now: Date) -> NSMenuItem {
        let title = process.isOrphaned ? "\(process.name) (orphaned)" : process.name
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = twoLines(title, Describe.processLine(process, now: now))
        if process.isLeftRunning {
            item.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Left running")
        }
        let details = NSMenu()
        details.addItem(disabled(Describe.attachment(process)))
        if let launchedBy = process.launchedBy.flatMap(model.tool), process.toolID == nil {
            details.addItem(disabled("For \(launchedBy.name)"))
        }
        details.addItem(disabled(process.pids.count == 1 ? "Process \(process.pid)" : "Processes \(process.pids.map(String.init).joined(separator: ", "))", small: true))
        if let path = process.path {
            details.addItem(disabled(Describe.path(path, home: Home.path), small: true))
        }
        details.addItem(.separator())
        if let path = process.path {
            let reveal = self.item("Show in Finder", #selector(showInFinder(_:)))
            reveal.representedObject = path
            details.addItem(reveal)
        }
        addStop(Describe.stopCommand(process, uid: uid), note: Describe.stopNote(process), to: details)
        item.submenu = details
        return item
    }

    private func launchItemItem(_ launchItem: LaunchItem) -> NSMenuItem {
        let item = NSMenuItem(title: launchItem.label, action: nil, keyEquivalent: "")
        item.attributedTitle = twoLines(launchItem.label, Describe.schedule(launchItem))
        let details = NSMenu()
        details.addItem(disabled(Describe.scope(launchItem.scope)))
        if let program = launchItem.program {
            details.addItem(disabled("Runs \(Describe.path(program, home: Home.path))", small: true))
        }
        details.addItem(.separator())
        let reveal = self.item("Show in Finder", #selector(showInFinder(_:)))
        reveal.representedObject = launchItem.plistPath
        details.addItem(reveal)
        addStop(Describe.stopCommand(launchItem, uid: uid), note: Describe.stopNote(launchItem), to: details)
        item.submenu = details
        return item
    }

    /// The app can't stop anything itself, so it offers the command to paste into Terminal, and shows it first.
    private func addStop(_ command: String, note: String, to menu: NSMenu) {
        let copy = item("Copy Stop Command", #selector(copyText(_:)))
        copy.representedObject = command
        copy.toolTip = note
        menu.addItem(copy)
        let shown = disabled(command)
        shown.attributedTitle = NSAttributedString(string: command, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        menu.addItem(shown)
        menu.addItem(disabled(note, small: true))
    }

    // MARK: MCP servers and receipts

    private func mcpItem(now: Date) -> NSMenuItem {
        let servers = model.mcpServers
        let orphans = servers.filter(\.isOrphaned).count
        var title = servers.isEmpty ? "MCP Servers" : "MCP Servers (\(servers.count))"
        if orphans > 0 { title += ", \(orphans) orphaned" }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if servers.isEmpty {
            item.isEnabled = false
            return item
        }
        let submenu = NSMenu()
        for server in servers {
            submenu.addItem(processItem(server, now: now))
        }
        item.submenu = submenu
        return item
    }

    private func receiptsItem(now: Date) -> NSMenuItem {
        let receipts = model.receipts
        let item = NSMenuItem(title: model.unseenReceipts > 0 ? "Recent Updates (\(model.unseenReceipts) new)" : "Recent Updates", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        if receipts.isEmpty {
            submenu.addItem(disabled("None yet. When a tool updates, what it changed shows up here."))
        }
        for receipt in receipts.prefix(Self.receiptLimit) {
            let headline = Describe.headline(receipt)
            let gist = Describe.gist(receipt)
            let entry = NSMenuItem(title: headline, action: nil, keyEquivalent: "")
            entry.attributedTitle = twoLines(headline, ([Describe.relativeCapitalized(receipt.date, now: now)] + (gist.isEmpty ? [] : [gist])).joined(separator: " · "))
            entry.image = model.tool(receipt.toolID).map { icons.icon(for: $0, size: 20) }
            let details = NSMenu()
            for line in Describe.lines(receipt) {
                details.addItem(disabled(line.trimmingCharacters(in: .whitespaces)))
            }
            details.addItem(disabled("Compared with the check \(Describe.relative(receipt.since, now: now))", small: true))
            details.addItem(.separator())
            let copy = self.item("Copy Receipt", #selector(copyText(_:)))
            copy.representedObject = Describe.receiptText(
                receipt, date: Self.longDate(receipt.date), since: Self.longDate(receipt.since), home: Home.path
            )
            details.addItem(copy)
            entry.submenu = details
            submenu.addItem(entry)
        }
        if receipts.count > Self.receiptLimit {
            submenu.addItem(.separator())
            submenu.addItem(self.item("See All \(receipts.count) in AI Footprint…", #selector(openWindow)))
        }
        item.submenu = submenu
        return item
    }

    // MARK: Building blocks

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabled(_ title: String, small: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if small {
            item.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        }
        return item
    }

    private func twoLines(_ first: String, _ second: String) -> NSAttributedString {
        let text = NSMutableAttributedString(string: first, attributes: [.font: NSFont.menuFont(ofSize: 0)])
        text.append(NSAttributedString(string: "\n" + second, attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return text
    }

    static func longDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: Actions

    @objc private func openWindow() { actions?.openWindow() }
    @objc private func checkNow() { actions?.checkNow() }
    @objc private func clearReceipts() { actions?.clearReceipts() }
    @objc private func toggleNotifications() { actions?.toggleNotifications() }
    @objc private func toggleOpenAtLogin() { actions?.toggleOpenAtLogin() }
    @objc private func showAbout() { actions?.showAbout() }

    @objc private func showInFinder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        Finder.reveal(path)
    }

    @objc private func copyText(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        Clipboard.copy(text)
    }
}

/// Your real home folder. Inside the sandbox, `NSHomeDirectory()` is the app's container instead.
enum Home {
    static let path: String? = {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else { return nil }
        return String(cString: directory)
    }()

    static func url(_ relative: String) -> URL {
        URL(fileURLWithPath: path ?? NSHomeDirectory(), isDirectory: true).appendingPathComponent(relative)
    }
}

@MainActor
enum Clipboard {
    /// The general pasteboard. Tests use one of their own, so they never touch yours.
    static var pasteboard = NSPasteboard.general

    static func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

enum Finder {
    /// Shows a file in Finder. Finder opens it, not this app, so it works for files the sandbox
    /// keeps the app from reading.
    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
