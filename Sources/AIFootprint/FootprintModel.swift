import FootprintCore
import Foundation
import Observation

/// Everything the menu and the window show, and the one place checks happen.
@MainActor
@Observable
final class FootprintModel {
    let tools: [Tool]
    private(set) var history: History
    /// The tools' processes as of the last look, which happens whenever the menu or window opens.
    private(set) var processes: [ToolProcess] = []
    private(set) var processesChecked: Date?
    private(set) var isChecking = false
    /// Receipts you haven't seen in the menu or window yet, for the menu bar icon.
    private(set) var unseenReceipts = 0

    var notifies: Bool {
        didSet { preferences.notifies = notifies }
    }

    /// Called with the receipts a check made, newest first.
    @ObservationIgnored var onReceipts: (([Receipt]) -> Void)?
    @ObservationIgnored var now: () -> Date = Date.init

    @ObservationIgnored private let reader: SystemReading
    @ObservationIgnored private let store: HistoryStore?
    @ObservationIgnored private let preferences: Preferences
    /// Every login item on the Mac, not only the tools', to tell what started a process.
    @ObservationIgnored private var allLaunchItems: [LaunchItem] = []
    @ObservationIgnored private var scan: Task<Readings, Never>?

    init(tools: [Tool] = Tool.all, reader: SystemReading, store: HistoryStore?, preferences: Preferences) {
        self.tools = tools
        self.reader = reader
        self.store = store
        self.preferences = preferences
        history = store?.load() ?? History()
        notifies = preferences.notifies
        allLaunchItems = history.last?.tools.flatMap(\.launchItems) ?? []
        countUnseen()
    }

    var footprint: Footprint? { history.last }
    var receipts: [Receipt] { history.receipts }
    var lastChecked: Date? { history.last?.date }

    func tool(_ id: String) -> Tool? {
        tools.first { $0.id == id }
    }

    func state(_ tool: Tool) -> ToolState? {
        footprint?.state(tool.id)
    }

    /// The tool's own processes, then the MCP servers it started.
    func processes(for tool: Tool) -> [ToolProcess] {
        processes.filter { $0.toolID == tool.id } + processes.filter { $0.toolID == nil && $0.launchedBy == tool.id }
    }

    /// Tools with anything on this Mac, biggest first.
    var installedTools: [Tool] {
        tools.filter { tool in state(tool)?.isInstalled == true || processes.contains { $0.toolID == tool.id } }
            .sorted { (state($0)?.bytes ?? 0) > (state($1)?.bytes ?? 0) }
    }

    var missingTools: [Tool] {
        let installed = Set(installedTools.map(\.id))
        return tools.filter { !installed.contains($0.id) }
    }

    var mcpServers: [ToolProcess] { processes.filter { $0.role == .mcpServer } }
    /// Processes nothing is keeping alive, like MCP servers whose app has quit.
    var leftRunning: [ToolProcess] { processes.filter(\.isLeftRunning) }
    var backgroundProcesses: [ToolProcess] { processes.filter(\.isBackground) }
    var launchItems: [LaunchItem] { footprint?.tools.flatMap(\.launchItems) ?? [] }
    var totalBytes: Int64 { footprint?.bytes ?? 0 }
    var totalMemory: Int64 { processes.reduce(0) { $0 + $1.residentBytes } }

    /// The last receipt for a tool.
    func lastReceipt(for tool: Tool) -> Receipt? {
        receipts.first { $0.toolID == tool.id }
    }

    // MARK: Checking

    /// Looks at the running processes again. Quick, so it happens each time the menu opens.
    func refreshProcesses() {
        processes = ProcessClassifier(tools: tools).classify(reader.processes(), launchItems: allLaunchItems)
        processesChecked = now()
    }

    /// Measures every tool's folders, reads versions and login items, and compares with the last
    /// check. Returns the receipts it made.
    @discardableResult
    func check() async -> [Receipt] {
        guard !isChecking else { return [] }
        isChecking = true
        defer { isChecking = false }
        let running = reader.processes()
        let reader = self.reader, tools = self.tools
        let scan = Task.detached(priority: .utility) {
            reader.readings(tools: tools, processes: running, isCancelled: { Task.isCancelled })
        }
        self.scan = scan
        let readings = await scan.value
        self.scan = nil
        // A check that stopped early would make missing folders look like tools going away.
        guard readings.isComplete else { return [] }
        allLaunchItems = readings.launchItems
        // Processes come and go during a long scan, so they're looked at again now.
        refreshProcesses()
        let made = history.record(readings.footprint(tools: tools, at: now()), tools: tools)
        save()
        countUnseen()
        if !made.isEmpty { onReceipts?(made) }
        return made
    }

    /// Stops a check in progress, which then records nothing.
    func cancelCheck() {
        scan?.cancel()
    }

    func markSeen() {
        guard unseenReceipts > 0 else { return }
        preferences.seenThrough = receipts.first?.date ?? now()
        countUnseen()
    }

    func clearReceipts() {
        history = History(receipts: [], last: history.last)
        save()
        countUnseen()
    }

    private func countUnseen() {
        let seen = preferences.seenThrough ?? .distantPast
        unseenReceipts = receipts.prefix { $0.date > seen }.count
    }

    private func save() {
        try? store?.save(history)
    }
}
