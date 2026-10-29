import AppKit
import FootprintCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, StatusMenuActions {
    private let preferences = Preferences()
    private let icons = ToolIcons()
    private let notifier = Notifier()
    private let menu = NSMenu()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private lazy var model = FootprintModel(
        reader: SystemReader(home: Home.path ?? NSHomeDirectory()), store: HistoryStore(), preferences: preferences
    )
    private lazy var statusMenu = StatusMenu(model: model, icons: icons, actions: self)
    private lazy var window = FootprintWindowController { [unowned self] in
        FootprintView(model: model, icons: icons, checkNow: { [unowned self] in checkNow() })
    }

    /// How often sizes, versions and login items are checked. A check takes about a second.
    static let checkInterval: TimeInterval = 15 * 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self
        statusItem.menu = menu
        updateStatusItem()

        model.onReceipts = { [weak self] receipts in self?.made(receipts) }
        notifier.onOpen = { [weak self] in self?.openWindow() }
        notifier.activate()
        refreshNotificationPermission()
        // Gives the keyboard back to the app you were using.
        window.onClose = { NSApp.hide(nil) }
        // So Copy Stop Command never copies a process that has since quit.
        window.onActivate = { [weak self] in self?.model.refreshProcesses() }

        checkNow()
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkNow() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // The first time, open at login like most menu bar utilities, and show the window so it's
        // clear what the app does. After that it starts quietly. Turn off login in the menu.
        if !preferences.launchedBefore {
            preferences.launchedBefore = true
            try? SMAppService.mainApp.register()
            openWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.cancelCheck()
    }

    private func made(_ receipts: [Receipt]) {
        updateStatusItem()
        if model.notifies {
            receipts.forEach(notifier.post)
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        button.image = ToolIcons.statusIcon(alert: model.unseenReceipts > 0)
        var tip = "AI Footprint"
        if model.footprint != nil {
            tip += "\nAI tools use \(Describe.bytes(model.totalBytes))."
        }
        if let latest = model.receipts.first {
            tip += "\nLast update: \(Describe.headline(latest)), \(Describe.relative(latest.date, now: Date()))."
        }
        button.toolTip = tip
    }

    private func refreshNotificationPermission() {
        notifier.checkPermission { [weak self] allowed in
            self?.statusMenu.notificationsAllowed = allowed
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        model.refreshProcesses()
        statusMenu.build(into: menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshNotificationPermission()
    }

    func menuDidClose(_ menu: NSMenu) {
        // Seen once you've looked, so the dot goes away after the menu closes.
        model.markSeen()
        updateStatusItem()
    }

    // MARK: StatusMenuActions

    func openWindow() {
        model.refreshProcesses()
        model.markSeen()
        updateStatusItem()
        window.show()
    }

    func checkNow() {
        Task {
            await model.check()
            updateStatusItem()
        }
    }

    func clearReceipts() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clear the update history?"
        alert.informativeText = "This deletes every receipt AI Footprint has recorded. It doesn't touch any tool or file. It can't be undone."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            model.clearReceipts()
            updateStatusItem()
        }
        if !window.isVisible {
            NSApp.hide(nil)
        }
    }

    func toggleNotifications() {
        if model.notifies {
            model.notifies = false
            return
        }
        notifier.requestPermission { [weak self] granted in
            guard let self else { return }
            statusMenu.notificationsAllowed = granted
            model.notifies = true
        }
    }

    func toggleOpenAtLogin() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }

    func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: "Free and open source. No internet access.\ngithub.com/stanczykwyatt/ai-footprint",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
    }
}
