import Foundation
import FootprintCore
import Testing
@testable import AIFootprint

@MainActor
@Suite("Model")
struct ModelTests {
    private func readings(ollama version: String, models: Int64 = 9_000_000_000, items: [LaunchItem] = []) -> Readings {
        Readings(appVersions: ["/Applications/Ollama.app": version], usage: [".ollama/models": usage(models)], launchItems: items)
    }

    @Test func theFirstCheckMakesNoReceipts() async {
        let reader = FakeReader(readings: readings(ollama: "0.12.2"))
        let model = makeModel(reader: reader)
        var told: [Receipt] = []
        model.onReceipts = { told += $0 }
        #expect(model.footprint == nil)
        let made = await model.check()
        #expect(made.isEmpty)
        #expect(told.isEmpty)
        #expect(model.footprint != nil)
        #expect(model.totalBytes == 9_000_000_000)
        #expect(reader.checks == 1)
    }

    @Test func anUpdateMakesAReceipt() async throws {
        let reader = FakeReader(readings: readings(ollama: "0.12.2"))
        let model = makeModel(reader: reader)
        var told: [Receipt] = []
        model.onReceipts = { told += $0 }
        await model.check()
        reader.result = readings(ollama: "0.12.3", models: 9_500_000_000)
        let made = await model.check()
        let receipt = try #require(made.first)
        #expect(receipt.kind == .updated)
        #expect(receipt.delta == 500_000_000)
        #expect(told == made)
        #expect(model.receipts == made)
        #expect(model.unseenReceipts == 1)
        #expect(model.lastReceipt(for: .ollama) == receipt)
        #expect(model.lastReceipt(for: .codex) == nil)
    }

    @Test func seeingReceiptsIsRemembered() async {
        let preferences = scratchPreferences()
        let store = HistoryStore(url: scratchFolder().appendingPathComponent("history.json"))
        let reader = FakeReader(readings: readings(ollama: "1"))
        let model = makeModel(reader: reader, store: store, preferences: preferences)
        await model.check()
        reader.result = readings(ollama: "2")
        await model.check()
        #expect(model.unseenReceipts == 1)
        model.markSeen()
        #expect(model.unseenReceipts == 0)
        // Still seen after a relaunch.
        #expect(makeModel(reader: reader, store: store, preferences: preferences).unseenReceipts == 0)
        reader.result = readings(ollama: "3")
        model.now = { Date().addingTimeInterval(5).rounded() }
        await model.check()
        #expect(model.unseenReceipts == 1)
    }

    @Test func historySurvivesARelaunch() async {
        let store = HistoryStore(url: scratchFolder().appendingPathComponent("history.json"))
        let reader = FakeReader(readings: readings(ollama: "1"))
        let model = makeModel(reader: reader, store: store)
        await model.check()
        reader.result = readings(ollama: "2")
        await model.check()
        let relaunched = makeModel(reader: reader, store: store)
        #expect(relaunched.receipts == model.receipts)
        #expect(relaunched.footprint == model.footprint)
        // The next check compares with the one saved before the relaunch.
        reader.result = readings(ollama: "3")
        let made = await relaunched.check()
        #expect(made.first?.fromVersion == "2")
    }

    @Test func clearingKeepsTheLastCheck() async {
        let reader = FakeReader(readings: readings(ollama: "1"))
        let model = makeModel(reader: reader)
        await model.check()
        reader.result = readings(ollama: "2")
        await model.check()
        model.clearReceipts()
        #expect(model.receipts.isEmpty)
        #expect(model.unseenReceipts == 0)
        #expect(model.footprint != nil)
        // So the next check doesn't treat everything as new.
        #expect(await model.check().isEmpty)
    }

    @Test func oneCheckAtATime() async {
        let reader = FakeReader(readings: readings(ollama: "1"))
        let model = makeModel(reader: reader)
        async let first = model.check()
        async let second = model.check()
        _ = await (first, second)
        #expect(reader.checks == 1)
        #expect(!model.isChecking)
    }

    @Test func toolsAreSortedBySizeAndMissingOnesListed() async {
        let reader = FakeReader(readings: Readings(usage: [
            ".ollama/models": usage(9_000_000_000), ".claude/projects": usage(400_000_000), ".cache/huggingface/hub": usage(12_000_000_000),
        ]))
        let model = makeModel(reader: reader)
        await model.check()
        #expect(model.installedTools.map(\.id) == ["hugging-face", "ollama", "claude-code"])
        #expect(model.missingTools.map(\.id) == ["claude-app", "codex", "lm-studio"])
    }

    @Test func aRunningToolCountsAsInstalled() {
        let reader = FakeReader(running: [process(10, name: "codex", path: "/opt/homebrew/bin/codex", terminal: true)])
        let model = makeModel(reader: reader)
        model.refreshProcesses()
        #expect(model.installedTools.map(\.id) == ["codex"])
        #expect(model.processesChecked != nil)
    }

    @Test func processesGoWithTheirTools() async throws {
        let (model, _) = await Gallery.make()
        let claude = try #require(model.tool("claude-code"))
        let processes = model.processes(for: claude)
        #expect(processes.map(\.name) == ["claude", "server-filesystem"])
        #expect(processes.last?.launchedBy == "claude-code")
        let ollama = try #require(model.tool("ollama"))
        #expect(Set(model.processes(for: ollama).map(\.name)) == ["Ollama", "ollama serve"])
    }

    @Test func orphansAndBackgroundProcesses() async {
        let (model, _) = await Gallery.make()
        #expect(model.leftRunning.map(\.name) == ["notes-mcp"])
        #expect(model.mcpServers.map(\.name).sorted() == ["notes-mcp", "server-filesystem"])
        #expect(model.backgroundProcesses.map(\.name).sorted() == ["driftwood daemon", "notes-mcp", "ollama serve"])
        #expect(model.launchItems.map(\.label) == ["com.example.driftwood.daemon"])
        #expect(model.totalMemory > 2_000_000_000)
    }

    @Test func aLoginItemIsKnownBeforeTheFirstCheckOfThisLaunch() async throws {
        let store = HistoryStore(url: scratchFolder().appendingPathComponent("history.json"))
        let item = Gallery.daemonItem
        let reader = FakeReader(running: [process(500, name: "driftwood", path: Gallery.daemonPath, arguments: [Gallery.daemonPath, "daemon"])], readings: Readings(launchItems: [item]))
        await makeModel(reader: reader, tools: Gallery.tools, store: store).check()
        // A relaunch remembers the tools' login items, so the menu can say what started a process right away.
        let relaunched = makeModel(reader: reader, tools: Gallery.tools, store: store)
        relaunched.refreshProcesses()
        let daemon = try #require(relaunched.processes.first)
        #expect(daemon.attachment == .launchItem(label: item.label, scope: .user))
    }

    @Test func theGalleryHasItsReceipts() async {
        let (model, _) = await Gallery.make()
        #expect(model.receipts.map(Describe.headline) == ["Driftwood Code 3.1.4 → 3.2.0", "Ollama 0.12.2 → 0.12.3"])
        #expect(model.receipts.first.map(Describe.gist) == "+1.9 GB, added a login item")
    }

    @Test func processesAreLookedAtAgainAfterAScan() async {
        let reader = FakeReader(running: [process(10, name: "codex", path: "/opt/homebrew/bin/codex", terminal: true)])
        // Codex quits while the folders are being measured.
        reader.duringCheck = { [reader] in reader.running = [] }
        let model = makeModel(reader: reader)
        await model.check()
        #expect(model.processes.isEmpty)
    }

    @Test func aPartialCheckIsNeverRecorded() async {
        let reader = FakeReader(readings: readings(ollama: "1"))
        let model = makeModel(reader: reader)
        await model.check()
        // Stopped early, nothing was measured, which mustn't look like Ollama being removed.
        var partial = Readings()
        partial.isComplete = false
        reader.result = partial
        #expect(await model.check().isEmpty)
        #expect(model.footprint?.state("ollama")?.version == "1")
        #expect(model.receipts.isEmpty)
    }

    @Test func notificationSettingIsSaved() {
        let preferences = scratchPreferences()
        let model = makeModel(preferences: preferences)
        #expect(!model.notifies)
        model.notifies = true
        #expect(preferences.notifies)
        #expect(makeModel(preferences: preferences).notifies)
    }
}

@Suite("Saving")
struct HistoryStoreTests {
    @Test func aMissingFileIsAnEmptyHistory() {
        let store = HistoryStore(url: scratchFolder().appendingPathComponent("nope/history.json"))
        #expect(store.load() == History())
    }

    @Test func savesIntoANewFolder() throws {
        let store = HistoryStore(url: scratchFolder().appendingPathComponent("AI Footprint/history.json"))
        let history = History(last: Footprint(date: Date(timeIntervalSince1970: 1_800_000_000), tools: [ToolState(toolID: "ollama", version: "1")]))
        try store.save(history)
        #expect(store.load() == history)
    }

    @Test func aDamagedFileIsSetAsideNotLost() throws {
        let folder = scratchFolder()
        let url = folder.appendingPathComponent("history.json")
        try Data("not json".utf8).write(to: url)
        #expect(HistoryStore(url: url).load() == History())
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.contains { $0.hasPrefix("history-unreadable-") })
        #expect(!names.contains("history.json"))
    }

    @Test func aNewerVersionsFileIsSetAside() throws {
        let folder = scratchFolder()
        let url = folder.appendingPathComponent("history.json")
        try Data(#"{"version": 7, "history": {"receipts": []}}"#.utf8).write(to: url)
        #expect(HistoryStore(url: url).load() == History())
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasPrefix("history-unreadable-") })
    }

    @Test func anUnreadableFileIsSetAsideNotOverwritten() throws {
        let folder = scratchFolder()
        let url = folder.appendingPathComponent("history.json")
        try Data("{}".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        let store = HistoryStore(url: url)
        #expect(store.load() == History())
        let aside = try #require(try FileManager.default.contentsOfDirectory(atPath: folder.path).first { $0.hasPrefix("history-unreadable-") })
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: folder.appendingPathComponent(aside).path)
        try store.save(History())
        #expect(try Data(contentsOf: folder.appendingPathComponent(aside)) == Data("{}".utf8))
    }

    @Test func theDefaultLivesInApplicationSupport() {
        #expect(HistoryStore.defaultURL.path.hasSuffix("Application Support/AI Footprint/history.json"))
    }
}

@Suite("Settings")
struct PreferencesTests {
    @Test func defaults() {
        let preferences = scratchPreferences()
        #expect(!preferences.notifies)
        #expect(!preferences.launchedBefore)
        #expect(preferences.seenThrough == nil)
    }

    @Test func remembersChanges() {
        let preferences = scratchPreferences()
        preferences.notifies = true
        preferences.launchedBefore = true
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        preferences.seenThrough = date
        let again = Preferences(defaults: preferences.defaults)
        #expect(again.notifies)
        #expect(again.launchedBefore)
        #expect(again.seenThrough == date)
    }
}
