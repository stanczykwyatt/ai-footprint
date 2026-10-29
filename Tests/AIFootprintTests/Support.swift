import AppKit
import FootprintCore
@testable import AIFootprint

/// A made-up Mac: the processes and readings a test sets by hand.
final class FakeReader: SystemReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _running: [RunningProcess]
    private var _readings: Readings
    private var _checks = 0
    /// Runs during a check, to change the made-up Mac while it's being measured.
    var duringCheck: (@Sendable () -> Void)?

    init(running: [RunningProcess] = [], readings: Readings = Readings()) {
        _running = running
        _readings = readings
    }

    var running: [RunningProcess] {
        get { lock.withLock { _running } }
        set { lock.withLock { _running = newValue } }
    }

    var result: Readings {
        get { lock.withLock { _readings } }
        set { lock.withLock { _readings = newValue } }
    }

    var checks: Int { lock.withLock { _checks } }

    func processes() -> [RunningProcess] { running }

    func readings(tools: [Tool], processes: [RunningProcess], isCancelled: @Sendable () -> Bool) -> Readings {
        duringCheck?()
        return lock.withLock {
            _checks += 1
            return _readings
        }
    }
}

/// Settings in a throwaway defaults domain, so tests never touch the real app's settings.
func scratchPreferences() -> Preferences {
    let name = "AIFootprintTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return Preferences(defaults: defaults)
}

/// A folder that's deleted when the test process ends.
func scratchFolder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("AIFootprintTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func usage(_ bytes: Int64, parts: [(String, Int64)] = []) -> Usage {
    Usage(bytes: bytes, files: 10, parts: parts.map { Usage.Part(name: $0.0, bytes: $0.1) })
}

func process(
    _ pid: ProcessID, parent: ProcessID = 1, name: String, path: String? = nil, arguments: [String]? = nil,
    memory: Int64 = 50_000_000, terminal: Bool = false, app: (String, String?)? = nil, started: Date? = nil
) -> RunningProcess {
    RunningProcess(
        pid: pid, parent: parent, name: name, path: path, arguments: arguments ?? [path ?? name], residentBytes: memory,
        started: started, hasTerminal: terminal, app: app.map { (name: $0.0, bundleID: $0.1) }
    )
}

/// A model on a made-up Mac, with a store in a throwaway folder.
@MainActor
func makeModel(
    reader: FakeReader = FakeReader(), tools: [Tool] = Tool.all, store: HistoryStore? = HistoryStore(url: scratchFolder().appendingPathComponent("history.json")),
    preferences: Preferences = scratchPreferences()
) -> FootprintModel {
    let model = FootprintModel(tools: tools, reader: reader, store: store, preferences: preferences)
    // Whole seconds, as they come back from the saved file.
    model.now = { Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded()) }
    return model
}

/// A made-up Mac for the screenshots and demo. Driftwood, its login item and the orphaned
/// `notes-mcp` server are invented, so no real tool is shown misbehaving. The real tools only show
/// ordinary, typical sizes.
@MainActor
enum Gallery {
    static let size = NSSize(width: 980, height: 900)
    static let home = "/Users/you"

    static let driftwood = Tool(
        id: "driftwood", name: "Driftwood Code",
        locations: [Location(".driftwood/logs", "Logs"), Location(".driftwood/sessions", "Session transcripts")],
        versionFolders: [".driftwood/versions"],
        match: ProcessMatch(commands: ["driftwood"], labelPrefixes: ["com.example.driftwood"]),
        symbol: "wind"
    )
    static let tools = Tool.all + [driftwood]

    static let daemonPath = "\(home)/.driftwood/bin/driftwood"
    static let daemonItem = LaunchItem(
        label: "com.example.driftwood.daemon", plistPath: "\(home)/Library/LaunchAgents/com.example.driftwood.daemon.plist",
        scope: .user, program: daemonPath, arguments: [daemonPath, "daemon"], runsAtLoad: true, keepsAlive: true
    )

    static func processes(now: Date) -> [RunningProcess] {
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        return [
            process(300, name: "Terminal", path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", app: ("Terminal", "com.apple.Terminal")),
            process(301, parent: 300, name: "zsh", path: "/bin/zsh", terminal: true),
            process(310, parent: 301, name: "claude", path: "\(home)/.local/share/claude/versions/2.1.4", memory: 286_000_000, terminal: true, started: ago(1.6)),
            process(311, parent: 310, name: "node", path: "/opt/homebrew/bin/node", arguments: ["npm", "exec", "@modelcontextprotocol/server-filesystem", "\(home)/code"], memory: 46_000_000, terminal: true, started: ago(1.6)),
            process(312, parent: 311, name: "node", path: "/opt/homebrew/bin/node", arguments: ["node", "\(home)/.npm/_npx/4f1/node_modules/.bin/mcp-server-filesystem"], memory: 52_000_000, terminal: true, started: ago(1.6)),
            process(400, name: "Ollama", path: "/Applications/Ollama.app/Contents/MacOS/Ollama", memory: 98_000_000, app: ("Ollama", "com.electron.ollama"), started: ago(30)),
            process(401, parent: 400, name: "ollama", path: "/Applications/Ollama.app/Contents/Resources/ollama", arguments: ["ollama", "serve"], memory: 1_240_000_000, started: ago(30)),
            process(500, name: "driftwood", path: daemonPath, arguments: [daemonPath, "daemon"], memory: 412_000_000, started: ago(0.07)),
            process(600, name: "node", path: "/opt/homebrew/bin/node", arguments: ["node", "\(home)/mcp/notes-mcp/dist/index.js"], memory: 84_000_000, started: ago(74)),
        ]
    }

    static func readings() -> Readings {
        Readings(
            appVersions: ["/Applications/Ollama.app": "0.12.3"],
            folderEntries: [".local/share/claude/versions": ["2.1.3", "2.1.4"], ".driftwood/versions": ["3.1.4", "3.2.0"]],
            usage: [
                ".ollama/models": usage(8_400_000_000, parts: [("blobs", 8_390_000_000), ("manifests", 10_000_000)]),
                ".ollama/logs": usage(3_100_000),
                ".claude/projects": usage(412_000_000),
                ".claude/file-history": usage(38_000_000),
                ".local/share/claude": usage(214_000_000),
                "Library/Caches/claude-cli-nodejs": usage(6_200_000),
                ".cache/huggingface/hub": usage(1_900_000_000, parts: [("models--example--small-coder", 1_900_000_000)]),
                ".driftwood/logs": usage(2_430_000_000, parts: [("daemon.log", 2_400_000_000), ("ui.log", 30_000_000)]),
                ".driftwood/sessions": usage(181_000_000),
            ],
            launchItems: [daemonItem],
            processPaths: ["driftwood": [daemonPath]]
        )
    }

    /// Before Driftwood's update: smaller logs, no login item.
    static func earlierReadings() -> Readings {
        var readings = readings()
        readings.usage[".driftwood/logs"] = usage(530_000_000)
        readings.launchItems = []
        readings.processPaths = [:]
        readings.folderEntries[".driftwood/versions"] = ["3.1.4"]
        readings.appVersions["/Applications/Ollama.app"] = "0.12.2"
        readings.usage[".ollama/models"] = usage(8_396_000_000)
        return readings
    }

    /// A model with a history: Ollama updated yesterday and Driftwood a few minutes ago.
    static func make(now: Date = Date()) async -> (FootprintModel, ToolIcons) {
        let reader = FakeReader(running: processes(now: now), readings: earlierReadings())
        let model = makeModel(reader: reader, tools: tools)
        var clock = now.addingTimeInterval(-30 * 3600)
        model.now = { clock }
        await model.check()
        clock = now.addingTimeInterval(-26 * 3600)
        var update = earlierReadings()
        update.appVersions["/Applications/Ollama.app"] = "0.12.3"
        update.usage[".ollama/models"] = usage(8_400_000_000)
        reader.result = update
        await model.check()
        clock = now.addingTimeInterval(-4 * 60)
        reader.result = readings()
        await model.check()
        clock = now
        model.refreshProcesses()
        model.markSeen()
        let icons = ToolIcons()
        icons.usesAppIcons = false
        icons.custom = [
            // Plain colored tiles, not the tools' own icons.
            "ollama": ToolIcons.tile("cube.fill", top: NSColor(srgbRed: 0.62, green: 0.65, blue: 0.71, alpha: 1), bottom: NSColor(srgbRed: 0.33, green: 0.36, blue: 0.43, alpha: 1)),
            "claude-code": ToolIcons.tile("terminal.fill", top: NSColor(srgbRed: 0.55, green: 0.52, blue: 0.95, alpha: 1), bottom: NSColor(srgbRed: 0.33, green: 0.28, blue: 0.78, alpha: 1)),
            "hugging-face": ToolIcons.tile("shippingbox.fill", top: NSColor(srgbRed: 0.45, green: 0.82, blue: 0.52, alpha: 1), bottom: NSColor(srgbRed: 0.18, green: 0.58, blue: 0.33, alpha: 1)),
            "driftwood": ToolIcons.tile("wind", top: NSColor(srgbRed: 0.30, green: 0.78, blue: 0.74, alpha: 1), bottom: NSColor(srgbRed: 0.10, green: 0.50, blue: 0.52, alpha: 1)),
        ]
        return (model, icons)
    }
}

extension Date {
    func rounded() -> Date { Date(timeIntervalSince1970: timeIntervalSince1970.rounded()) }
}
