import AppKit
import FootprintCore
import Testing
@testable import AIFootprint

@MainActor
final class RecordedActions: StatusMenuActions {
    var calls: [String] = []
    func openWindow() { calls.append("openWindow") }
    func checkNow() { calls.append("checkNow") }
    func clearReceipts() { calls.append("clearReceipts") }
    func toggleNotifications() { calls.append("notifications") }
    func toggleOpenAtLogin() { calls.append("login") }
    func showAbout() { calls.append("about") }
}

/// The menu, built into an NSMenu that's never shown.
@MainActor
@Suite("Menu")
struct StatusMenuTests {
    let actions = RecordedActions()

    private func build(_ model: FootprintModel, icons: ToolIcons = ToolIcons(), now: Date = Date(), notificationsAllowed: Bool = true) -> NSMenu {
        let statusMenu = StatusMenu(model: model, icons: icons, actions: actions)
        statusMenu.now = { now }
        statusMenu.opensAtLogin = { true }
        statusMenu.uid = 501
        statusMenu.notificationsAllowed = notificationsAllowed
        let menu = NSMenu()
        statusMenu.build(into: menu)
        // Keeps the builder alive for the menu's targets, as the app delegate does.
        objc_setAssociatedObject(menu, "builder", statusMenu, .OBJC_ASSOCIATION_RETAIN)
        return menu
    }

    /// Matches the first line, since two-line items carry both lines in their title.
    private func item(_ menu: NSMenu?, _ title: String) throws -> NSMenuItem {
        try #require(menu?.items.first { firstLine($0) == title }, "No item titled \(title)")
    }

    private func firstLine(_ item: NSMenuItem) -> String {
        item.title.components(separatedBy: "\n")[0]
    }

    private func titles(_ menu: NSMenu?) -> [String] {
        menu?.items.map { $0.isSeparatorItem ? "—" : ($0.attributedTitle?.string ?? $0.title) } ?? []
    }

    private func click(_ item: NSMenuItem) {
        _ = (item.target as? NSObject)?.perform(item.action, with: item)
    }

    @Test func beforeTheFirstCheck() throws {
        let menu = build(makeModel())
        #expect(menu.items.first?.title == "Not checked yet")
        #expect(try !item(menu, "MCP Servers").isEnabled)
        #expect(try !item(menu, "Clear Update History…").isEnabled)
        #expect(try item(menu, "Open at Login").state == .on)
        #expect(try item(menu, "Notify Me About Updates").state == .off)
        #expect(!titles(menu).contains { $0.hasPrefix("Sizes checked") })
        let updates = try item(menu, "Recent Updates")
        #expect(updates.submenu?.items.first?.title.hasPrefix("None yet.") == true)
    }

    @Test func nothingFound() async throws {
        let model = makeModel()
        await model.check()
        let menu = build(model)
        #expect(menu.items.first?.title == "AI tools use Zero KB on this Mac")
        #expect(titles(menu).contains("No AI tools found. They show up here once installed."))
        #expect(titles(menu).contains("Nothing running in the background"))
    }

    @Test func theSummaryAtTheTop() async throws {
        let (model, icons) = await Gallery.make()
        let menu = build(model, icons: icons)
        #expect(menu.items[0].title == "AI tools use 14 GB on this Mac")
        #expect(titles(menu)[1] == "3 background processes · 1 login item")
        #expect(titles(menu).contains { $0.hasPrefix("Sizes checked") })
    }

    @Test func toolsBiggestFirst() async throws {
        let (model, icons) = await Gallery.make()
        let menu = build(model, icons: icons)
        let tools = menu.items.filter { $0.submenu != nil && $0.image != nil && $0.title.contains("\n") }.map(firstLine)
        #expect(tools.prefix(4) == ["Ollama 0.12.3", "Driftwood Code 3.2.0", "Hugging Face", "Claude Code 2.1.4"])
        let ollama = try item(menu, "Ollama 0.12.3")
        #expect(ollama.title.components(separatedBy: "\n")[1] == "8.4 GB · 2 processes")
        let driftwood = try item(menu, "Driftwood Code 3.2.0")
        #expect(driftwood.title.components(separatedBy: "\n")[1] == "2.6 GB · 1 process · 1 login item")
    }

    @Test func aToolsDiskProcessesAndLoginItems() async throws {
        let (model, icons) = await Gallery.make()
        let menu = build(model, icons: icons)
        let submenu = try item(menu, "Driftwood Code 3.2.0").submenu
        let all = titles(submenu)
        #expect(all.contains("On Disk"))
        #expect(all.contains("Logs\n2.4 GB · ~/.driftwood/logs"))
        #expect(all.contains("Running"))
        #expect(all.contains { $0.hasPrefix("driftwood daemon\nServer · 412 MB memory · running 4 min") })
        #expect(all.contains("Login Items"))
        #expect(all.contains("com.example.driftwood.daemon\nStarts at login, and again if it quits"))
        #expect(all.contains { $0.hasPrefix("Last change: Driftwood Code 3.1.4 → 3.2.0") })
        // Biggest folder first.
        let logs = try #require(all.firstIndex { $0.hasPrefix("Logs") })
        let sessions = try #require(all.firstIndex { $0.hasPrefix("Session transcripts") })
        #expect(logs < sessions)
    }

    @Test func aFoldersBiggestPartsAndFinder() async throws {
        let (model, icons) = await Gallery.make()
        let menu = build(model, icons: icons)
        let logs = try item(try item(menu, "Driftwood Code 3.2.0").submenu, "Logs")
        let all = titles(logs.submenu)
        #expect(all.prefix(2) == ["daemon.log: 2.4 GB", "ui.log: 30 MB"])
        let reveal = try item(logs.submenu, "Show in Finder")
        #expect((reveal.representedObject as? String)?.hasSuffix("/.driftwood/logs") == true)
        #expect(all.contains { $0.hasPrefix("AI Footprint never deletes anything") })
    }

    @Test func copyStopCommandShowsTheCommandFirst() async throws {
        let (model, icons) = await Gallery.make()
        let menu = build(model, icons: icons)
        let driftwood = try item(menu, "Driftwood Code 3.2.0").submenu
        let daemon = try item(driftwood, "driftwood daemon")
        let copy = try item(daemon.submenu, "Copy Stop Command")
        #expect(copy.representedObject as? String == "launchctl bootout gui/501/com.example.driftwood.daemon")
        #expect(titles(daemon.submenu).contains("launchctl bootout gui/501/com.example.driftwood.daemon"))
        #expect(titles(daemon.submenu).contains("Started by the login item com.example.driftwood.daemon"))
        let loginItem = try item(driftwood, "com.example.driftwood.daemon")
        #expect(try item(loginItem.submenu, "Copy Stop Command").representedObject as? String == "launchctl bootout gui/501/com.example.driftwood.daemon")
        #expect(titles(loginItem.submenu).contains("For you"))
    }

    @Test func copyingPutsTheCommandOnTheClipboard() async throws {
        let (model, icons) = await Gallery.make()
        let menu = build(model, icons: icons)
        let leftovers = try item(menu, "Left Running (1)").submenu
        let orphan = try item(leftovers, "notes-mcp (orphaned)")
        // A private pasteboard, so your clipboard is left alone.
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("AIFootprintTests-\(UUID().uuidString)"))
        Clipboard.pasteboard = pasteboard
        defer {
            Clipboard.pasteboard = .general
            pasteboard.releaseGlobally()
        }
        click(try item(orphan.submenu, "Copy Stop Command"))
        #expect(pasteboard.string(forType: .string) == "kill 600")
    }

    @Test func mcpServersAndOrphans() async throws {
        let (model, icons) = await Gallery.make()
        let menu = build(model, icons: icons)
        let mcp = try item(menu, "MCP Servers (2), 1 orphaned")
        #expect(mcp.isEnabled)
        let names = mcp.submenu?.items.map(firstLine) ?? []
        #expect(Set(names) == ["notes-mcp (orphaned)", "server-filesystem"])
        let filesystem = try item(mcp.submenu, "server-filesystem")
        #expect(titles(filesystem.submenu).contains("Started by Claude Code"))
        #expect(titles(filesystem.submenu).contains("Processes 311, 312"))
        let orphan = try item(mcp.submenu, "notes-mcp (orphaned)")
        #expect(orphan.image != nil)
        #expect(titles(orphan.submenu).contains("Orphaned: the app that started it has quit"))
    }

    @Test func leftRunningOnlyWhenThereIsSomething() async throws {
        let model = makeModel()
        await model.check()
        #expect(!build(model).items.contains { $0.title.hasPrefix("Left Running") })
    }

    @Test func recentUpdates() async throws {
        let (model, icons) = await Gallery.make()
        let updates = try item(build(model, icons: icons), "Recent Updates")
        let entries = updates.submenu?.items ?? []
        #expect(entries.map(firstLine) == ["Driftwood Code 3.1.4 → 3.2.0", "Ollama 0.12.2 → 0.12.3"])
        #expect(entries[0].title.components(separatedBy: "\n")[1].hasSuffix("· +1.9 GB, added a login item"))
        let lines = titles(entries[0].submenu)
        #expect(lines.contains("Disk: 711 MB → 2.6 GB (+1.9 GB)"))
        #expect(lines.contains("Logs (~/.driftwood/logs): +1.9 GB"))
        #expect(lines.contains("Added login item com.example.driftwood.daemon: Starts at login, and again if it quits"))
        let copy = try item(entries[0].submenu, "Copy Receipt")
        #expect((copy.representedObject as? String)?.hasPrefix("Driftwood Code 3.1.4 → 3.2.0\nNoticed") == true)
    }

    @Test func newUpdatesAreCounted() async throws {
        let reader = FakeReader(readings: Readings(appVersions: ["/Applications/Ollama.app": "1"], usage: [".ollama/models": usage(1_000_000)]))
        let model = makeModel(reader: reader)
        await model.check()
        reader.result.appVersions["/Applications/Ollama.app"] = "2"
        await model.check()
        #expect(try item(build(model), "Recent Updates (1 new)").submenu?.items.count == 1)
    }

    @Test func manyUpdatesLinkToTheWindow() async throws {
        let reader = FakeReader(readings: Readings(appVersions: ["/Applications/Ollama.app": "0"], usage: [".ollama/models": usage(1_000_000)]))
        let model = makeModel(reader: reader)
        await model.check()
        for version in 1...10 {
            reader.result.appVersions["/Applications/Ollama.app"] = "\(version)"
            await model.check()
        }
        let menu = build(model)
        let updates = try item(menu, "Recent Updates (10 new)").submenu
        #expect(updates?.items.filter { $0.submenu != nil }.count == StatusMenu.receiptLimit)
        let all = try item(updates, "See All 10 in AI Footprint…")
        click(all)
        #expect(actions.calls == ["openWindow"])
    }

    @Test func itemsCallTheirActions() async throws {
        let model = makeModel()
        await model.check()
        let menu = build(model)
        for title in ["Open AI Footprint…", "Check Now", "Notify Me About Updates", "Open at Login", "About AI Footprint"] {
            click(try item(menu, title))
        }
        #expect(actions.calls == ["openWindow", "checkNow", "notifications", "login", "about"])
        #expect(try item(menu, "Open AI Footprint…").keyEquivalent == "o")
        #expect(try item(menu, "Check Now").keyEquivalent == "r")
        #expect(menu.items.last?.title == "Quit AI Footprint")
    }

    @Test func clearAsksTheDelegate() async throws {
        let (model, icons) = await Gallery.make()
        let menu = build(model, icons: icons)
        click(try item(menu, "Clear Update History…"))
        #expect(actions.calls == ["clearReceipts"])
    }

    @Test func blockedNotificationsAreExplained() throws {
        let model = makeModel()
        model.notifies = true
        let menu = build(model, notificationsAllowed: false)
        #expect(try item(menu, "Notify Me About Updates").state == .on)
        #expect(titles(menu).contains("Allow notifications in System Settings → Notifications"))
        #expect(!titles(build(model, notificationsAllowed: true)).contains("Allow notifications in System Settings → Notifications"))
    }

    @Test func pathsShowYourHomeAsTilde() async throws {
        let home = try #require(Home.path)
        let reader = FakeReader(running: [process(10, parent: 1, name: "codex", path: "\(home)/.codex/bin/codex", arguments: ["codex", "app-server"])])
        let model = makeModel(reader: reader)
        await model.check()
        let menu = build(model)
        let codex = try item(menu, "Codex")
        let server = try #require(codex.submenu?.items.first { firstLine($0) == "codex app-server" })
        #expect(titles(server.submenu).contains("~/.codex/bin/codex"))
        #expect(!titles(server.submenu).contains { $0.contains(home) })
    }
}
