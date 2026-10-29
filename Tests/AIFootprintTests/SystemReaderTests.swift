import Foundation
import FootprintCore
import Testing
@testable import AIFootprint

/// The real reader, pointed at a made-up home folder. Shared login item folders are left out, so
/// nothing outside the throwaway folder is read.
@Suite("Reading the Mac")
struct SystemReaderTests {
    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func plist(_ values: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0).write(to: url)
    }

    @Test func measuresLocationsInHome() throws {
        let home = scratchFolder()
        try write(String(repeating: "x", count: 50_000), to: home.appendingPathComponent(".ollama/models/blobs/sha256-1"))
        try write("log", to: home.appendingPathComponent(".ollama/logs/server.log"))
        // Ollama's key sits right next to its models, and isn't part of any location.
        try write("secret", to: home.appendingPathComponent(".ollama/id_ed25519"))
        let reader = SystemReader(home: home.path, sharedLaunchFolders: [])
        let readings = reader.readings(tools: Tool.all, processes: [], isCancelled: { false })
        #expect(readings.usage[".ollama/models"]?.files == 1)
        #expect(readings.usage[".ollama/models"]?.parts.first?.name == "blobs")
        #expect(readings.usage[".ollama/logs"] != nil)
        #expect(readings.usage[".codex/sessions"] == nil)
        #expect(Set(readings.usage.keys) == [".ollama/models", ".ollama/logs"])
    }

    @Test func readsVersionsFromFoldersAndApps() throws {
        let home = scratchFolder()
        for version in ["2.1.3", "2.1.10"] {
            try write("", to: home.appendingPathComponent(".local/share/claude/versions/\(version)"))
        }
        let app = home.appendingPathComponent("Applications/Sample.app")
        try plist(["CFBundleShortVersionString": "4.5.6", "CFBundleVersion": "456"], to: app.appendingPathComponent("Contents/Info.plist"))
        let tool = Tool(id: "sample", name: "Sample", locations: [], apps: [app.path], match: ProcessMatch(), symbol: "cube")
        let reader = SystemReader(home: home.path, sharedLaunchFolders: [])
        let readings = reader.readings(tools: [.claudeCode, tool], processes: [], isCancelled: { false })
        #expect(readings.folderEntries[".local/share/claude/versions"]?.sorted() == ["2.1.10", "2.1.3"])
        #expect(readings.appVersions[app.path] == "4.5.6")
        #expect(readings.footprint(tools: [.claudeCode, tool], at: Date()).state("claude-code")?.version == "2.1.10")
    }

    @Test func picksUpAnAppUpdateRightAway() throws {
        // Bundle would keep the first version it read for as long as the app runs.
        let home = scratchFolder()
        let app = home.appendingPathComponent("Applications/Sample.app")
        let info = app.appendingPathComponent("Contents/Info.plist")
        let tool = Tool(id: "sample", name: "Sample", locations: [], apps: [app.path], match: ProcessMatch(), symbol: "cube")
        let reader = SystemReader(home: home.path, sharedLaunchFolders: [])
        try plist(["CFBundleShortVersionString": "1.0"], to: info)
        #expect(reader.readings(tools: [tool], processes: [], isCancelled: { false }).appVersions[app.path] == "1.0")
        try plist(["CFBundleShortVersionString": "1.1"], to: info)
        #expect(reader.readings(tools: [tool], processes: [], isCancelled: { false }).appVersions[app.path] == "1.1")
    }

    @Test func readsLoginItems() throws {
        let home = scratchFolder()
        let agents = home.appendingPathComponent("Library/LaunchAgents")
        try plist(["Label": "com.ollama.ollama", "ProgramArguments": ["/Applications/Ollama.app/Contents/Resources/ollama", "serve"], "RunAtLoad": true], to: agents.appendingPathComponent("com.ollama.ollama.plist"))
        try write("not a plist", to: agents.appendingPathComponent("broken.plist"))
        try write("ignored", to: agents.appendingPathComponent("notes.txt"))
        let shared = scratchFolder()
        try plist(["Label": "com.example.shared"], to: shared.appendingPathComponent("com.example.shared.plist"))
        let reader = SystemReader(home: home.path, sharedLaunchFolders: [(shared.path, .allUsers)])
        let readings = reader.readings(tools: Tool.all, processes: [], isCancelled: { false })
        #expect(readings.launchItems.map(\.label).sorted() == ["com.example.shared", "com.ollama.ollama"])
        let ollama = try #require(readings.launchItems.first { $0.label == "com.ollama.ollama" })
        #expect(ollama.scope == .user)
        #expect(ollama.modified != nil)
        #expect(readings.launchItems.first { $0.label == "com.example.shared" }?.scope == .allUsers)
        #expect(readings.footprint(tools: Tool.all, at: Date()).state("ollama")?.launchItems.count == 1)
    }

    @Test func skipsHugeAndOddLoginItemFiles() throws {
        let home = scratchFolder()
        let agents = home.appendingPathComponent("Library/LaunchAgents")
        try write(String(repeating: "x", count: 1_200_000), to: agents.appendingPathComponent("huge.plist"))
        try FileManager.default.createDirectory(at: agents.appendingPathComponent("folder.plist"), withIntermediateDirectories: true)
        let reader = SystemReader(home: home.path, sharedLaunchFolders: [])
        #expect(reader.readings(tools: Tool.all, processes: [], isCancelled: { false }).launchItems.isEmpty)
    }

    @Test func stopsWhenCancelled() throws {
        let home = scratchFolder()
        try write("x", to: home.appendingPathComponent(".ollama/models/a"))
        let reader = SystemReader(home: home.path, sharedLaunchFolders: [])
        #expect(reader.readings(tools: Tool.all, processes: [], isCancelled: { true }).usage.isEmpty)
    }

    @Test func groupsProcessPathsByTool() {
        let reader = SystemReader(home: scratchFolder().path, sharedLaunchFolders: [])
        let running = [
            process(1, name: "codex", path: "/opt/homebrew/Cellar/codex/0.52.0/bin/codex"),
            process(2, name: "node", path: "/opt/homebrew/bin/node", arguments: ["node", "server.js"]),
        ]
        let readings = reader.readings(tools: Tool.all, processes: running, isCancelled: { false })
        #expect(readings.processPaths == ["codex": ["/opt/homebrew/Cellar/codex/0.52.0/bin/codex"]])
        #expect(readings.footprint(tools: Tool.all, at: Date()).state("codex")?.version == "0.52.0")
    }

    /// Starts a process of the test's own, and finds it the way the app finds tools. Nothing else
    /// on the Mac is looked at beyond the list `ps` would show.
    @MainActor
    @Test func findsAProcessWithItsArguments() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        child.environment = ["AI_FOOTPRINT_TEST_SECRET": "should-not-appear"]
        try child.run()
        defer { child.terminate() }
        try await Task.sleep(for: .milliseconds(200))
        let found = try #require(SystemReader(home: "/nonexistent").processes().first { $0.pid == child.processIdentifier })
        #expect(found.parent == ProcessInfo.processInfo.processIdentifier)
        #expect(found.path == "/bin/sleep")
        #expect(found.arguments == ["/bin/sleep", "30"])
        #expect(found.name == "sleep")
        #expect(found.residentBytes > 0)
        #expect(found.started != nil)
        #expect(found.app == nil)
        #expect(!found.arguments.joined().contains("should-not-appear"))
    }

    @MainActor
    @Test func leavesItselfOut() {
        let me = ProcessInfo.processInfo.processIdentifier
        #expect(!SystemReader(home: "/nonexistent").processes().contains { $0.pid == me })
    }
}
