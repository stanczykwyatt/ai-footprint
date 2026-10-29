import Foundation
import Testing
@testable import FootprintCore

@Suite("Receipts")
struct ReceiptTests {
    let tool = Tool.codex
    let earlier = Fixture.start
    let later = Fixture.start.addingTimeInterval(900)

    private func state(_ version: String?, sessions: Int64 = 0, logs: Int64 = 0, items: [LaunchItem] = []) -> ToolState {
        var usage: [String: Usage] = [:]
        if sessions > 0 { usage[".codex/sessions"] = Fixture.usage(sessions) }
        if logs > 0 { usage[".codex/log"] = Fixture.usage(logs) }
        return ToolState(toolID: "codex", version: version, usage: usage, launchItems: items)
    }

    private func compare(_ before: ToolState?, _ after: ToolState) -> Receipt? {
        Receipt.compare(before, after, tool: tool, since: earlier, now: later)
    }

    @Test func anUpdate() throws {
        let agent = Fixture.item("com.openai.codex.server", program: "/Applications/Codex.app/Contents/Resources/codex", keepsAlive: true)
        let receipt = try #require(compare(
            state("0.51.0", sessions: 200_000_000, logs: 10_000_000),
            state("0.52.0", sessions: 210_000_000, logs: 1_800_000_000, items: [agent])
        ))
        #expect(receipt.kind == .updated)
        #expect(receipt.fromVersion == "0.51.0")
        #expect(receipt.toVersion == "0.52.0")
        #expect(receipt.bytesBefore == 210_000_000)
        #expect(receipt.bytesAfter == 2_010_000_000)
        #expect(receipt.delta == 1_800_000_000)
        #expect(receipt.changes.map(\.path) == [".codex/log", ".codex/sessions"])
        #expect(receipt.changes.first?.delta == 1_790_000_000)
        #expect(receipt.itemsAdded == [agent])
        #expect(receipt.itemsRemoved.isEmpty)
        #expect(receipt.since == earlier)
        #expect(receipt.date == later)
        #expect(receipt.toolName == "Codex")
    }

    @Test func theFirstCheckIsJustWhereItStarts() {
        #expect(compare(nil, state("0.52.0", sessions: 5_000_000)) == nil)
    }

    @Test func diskChangesOnTheirOwnArentNews() {
        #expect(compare(state("0.52.0", sessions: 100_000_000), state("0.52.0", sessions: 900_000_000)) == nil)
    }

    @Test func learningTheVersionIsntAnUpdate() {
        #expect(compare(state(nil, sessions: 100_000_000), state("0.52.0", sessions: 100_000_000)) == nil)
    }

    @Test func anInstall() throws {
        let receipt = try #require(compare(state(nil), state("0.52.0", sessions: 3_000_000)))
        #expect(receipt.kind == .installed)
        #expect(receipt.bytesBefore == 0)
        #expect(receipt.toVersion == "0.52.0")
    }

    @Test func aRemoval() throws {
        let receipt = try #require(compare(state("0.52.0", sessions: 3_000_000), state(nil)))
        #expect(receipt.kind == .removed)
        #expect(receipt.delta == -3_000_000)
    }

    @Test func aLoginItemAddedWithoutAnUpdate() throws {
        let agent = Fixture.item("com.openai.codex.helper")
        let receipt = try #require(compare(state("0.52.0", sessions: 1_000_000), state("0.52.0", sessions: 1_000_000, items: [agent])))
        #expect(receipt.kind == .changed)
        #expect(receipt.itemsAdded == [agent])
    }

    @Test func aLoginItemRemoved() throws {
        let agent = Fixture.item("com.openai.codex.helper")
        let receipt = try #require(compare(state("0.52.0", sessions: 1_000_000, items: [agent]), state("0.52.0", sessions: 1_000_000)))
        #expect(receipt.kind == .changed)
        #expect(receipt.itemsRemoved == [agent])
    }

    @Test func smallChangesArentListed() throws {
        let receipt = try #require(compare(state("1", sessions: 5_000_000, logs: 1_000_000), state("2", sessions: 5_400_000, logs: 1_000_000)))
        #expect(receipt.changes.isEmpty)
        #expect(receipt.delta == 400_000)
    }

    @Test func comparesEveryTool() {
        let before = Footprint(date: earlier, tools: [
            ToolState(toolID: "codex", version: "0.51.0", usage: [".codex/log": Fixture.usage(1_000_000)]),
            ToolState(toolID: "ollama", version: "0.12.3", usage: [".ollama/models": Fixture.usage(9_000_000_000)]),
        ])
        let after = Footprint(date: later, tools: [
            ToolState(toolID: "codex", version: "0.52.0", usage: [".codex/log": Fixture.usage(1_000_000)]),
            ToolState(toolID: "ollama", version: "0.12.3", usage: [".ollama/models": Fixture.usage(9_000_000_000)]),
            // A tool the app learned about since the last check.
            ToolState(toolID: "lm-studio", version: "0.3.30", usage: [".lmstudio/models": Fixture.usage(4_000_000_000)]),
        ])
        let receipts = Receipt.compare(before, after, tools: Tool.all)
        #expect(receipts.map(\.toolID) == ["codex"])
        #expect(Receipt.compare(nil, after, tools: Tool.all).isEmpty)
    }
}

@Suite("History")
struct HistoryTests {
    private func footprint(_ version: String, at minutes: Double) -> Footprint {
        Footprint(date: Fixture.start.addingTimeInterval(minutes * 60), tools: [
            ToolState(toolID: "ollama", version: version, usage: [".ollama/models": Fixture.usage(1_000_000_000)]),
        ])
    }

    @Test func recordsReceiptsNewestFirst() {
        var history = History()
        #expect(history.record(footprint("1.0", at: 0), tools: Tool.all).isEmpty)
        #expect(history.record(footprint("1.1", at: 10), tools: Tool.all).count == 1)
        #expect(history.record(footprint("1.1", at: 20), tools: Tool.all).isEmpty)
        #expect(history.record(footprint("1.2", at: 30), tools: Tool.all).count == 1)
        #expect(history.receipts.map(\.toVersion) == ["1.2", "1.1"])
        #expect(history.receipts.first?.since == Fixture.start.addingTimeInterval(1200))
        #expect(history.last?.date == Fixture.start.addingTimeInterval(1800))
    }

    @Test func dropsTheOldestOnceFull() {
        var history = History(limit: 2)
        for (index, version) in ["1", "2", "3", "4"].enumerated() {
            history.record(footprint(version, at: Double(index)), tools: Tool.all)
        }
        #expect(history.receipts.map(\.toVersion) == ["4", "3"])
        #expect(History(limit: 0).limit == 1)
    }

    @Test func savesAndLoads() throws {
        var history = History()
        history.record(footprint("1.0", at: 0), tools: Tool.all)
        history.record(footprint("1.1", at: 10), tools: Tool.all)
        let loaded = try HistoryFile.decode(HistoryFile.encode(history))
        #expect(loaded == history)
    }

    @Test func refusesANewerFile() {
        let data = Data(#"{"version": 99, "history": {"receipts": []}}"#.utf8)
        #expect(throws: HistoryFile.ReadError.newerVersion(99)) { try HistoryFile.decode(data) }
    }

    @Test func rejectsDamagedFiles() {
        #expect(throws: (any Error).self) { try HistoryFile.decode(Data("{".utf8)) }
        #expect(throws: (any Error).self) { try HistoryFile.decode(Data(#"{"version": 1}"#.utf8)) }
    }

    @Test func aLoadedHistoryIsSortedAndCapped() throws {
        let receipts = (0..<(History.defaultLimit + 5)).map { index in
            Receipt(kind: .updated, toolID: "x", toolName: "X", date: Fixture.start.addingTimeInterval(Double(index)), since: Fixture.start, bytesBefore: 0, bytesAfter: 0)
        }
        let history = History(receipts: receipts.shuffled())
        #expect(history.receipts.count == History.defaultLimit)
        #expect(history.receipts.first?.date == receipts.last?.date)
    }

    private func brew(_ version: String?, fromProcesses: Bool = true) -> Footprint {
        var state = ToolState(toolID: "ollama", version: version, usage: [".ollama/models": Fixture.usage(5_000_000_000)])
        state.versionFromProcesses = version == nil ? nil : fromProcesses
        return Footprint(date: Fixture.start, tools: [state])
    }

    @Test func anUpdateWhileStoppedIsStillCaught() {
        // Homebrew's Ollama has no app, so its version only shows while it runs.
        var history = History()
        history.record(brew("0.12.3"), tools: Tool.all)
        #expect(history.record(brew(nil), tools: Tool.all).isEmpty)
        #expect(history.last?.state("ollama")?.version == "0.12.3")
        let made = history.record(brew("0.12.4"), tools: Tool.all)
        #expect(made.map(Describe.headline) == ["Ollama 0.12.3 → 0.12.4"])
    }

    @Test func aVersionFromRunningProcessesNeverGoesBackward() {
        // Two copies installed: which one is running decides what the path says.
        var history = History()
        history.record(brew("2.1.5"), tools: Tool.all)
        #expect(history.record(brew("2.1.4"), tools: Tool.all).isEmpty)
        #expect(history.record(brew("2.1.5"), tools: Tool.all).isEmpty)
        #expect(history.last?.state("ollama")?.version == "2.1.5")
    }

    @Test func anInstalledVersionCanGoBackward() {
        // A real downgrade of the app is news.
        var history = History()
        history.record(brew("2.0", fromProcesses: false), tools: Tool.all)
        #expect(history.record(brew("1.9", fromProcesses: false), tools: Tool.all).first?.kind == .updated)
    }

    @Test func aRemovedToolIsntKeptAlive() {
        var history = History()
        history.record(brew("0.12.3"), tools: Tool.all)
        let gone = Footprint(date: Fixture.start, tools: [ToolState(toolID: "ollama")])
        #expect(history.record(gone, tools: Tool.all).first?.kind == .removed)
    }

    @Test func refusesAVersionNoAppWrote() {
        let data = Data(#"{"version": 0, "history": {"receipts": []}}"#.utf8)
        #expect(throws: HistoryFile.ReadError.unknownVersion(0)) { try HistoryFile.decode(data) }
    }
}
