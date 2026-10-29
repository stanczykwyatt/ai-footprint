import Foundation
import Testing
@testable import FootprintCore

@Suite("Versions")
struct VersionTests {
    @Test(arguments: [
        ("2.1.4", true), ("0.52.0-beta.1", true), ("v1.3", true), ("10.0", true), ("1.0+build5", true),
        ("2", false), ("latest", false), ("abc.def", false), ("", false), (".DS_Store", false), ("1.2/3", false),
    ])
    func whatLooksLikeAVersion(name: String, expected: Bool) {
        #expect(Versions.isVersion(name) == expected)
    }

    @Test func comparesNumberByNumber() {
        #expect(Versions.compare("2.10.0", "2.9.9") == .orderedDescending)
        #expect(Versions.compare("1.2", "1.2.0") == .orderedSame)
        #expect(Versions.compare("v1.3", "1.4") == .orderedAscending)
        #expect(Versions.compare("0.52.0-beta.1", "0.52.0") == .orderedAscending)
        #expect(Versions.compare("0.52.0-beta.10", "0.52.0-beta.9") == .orderedDescending)
        #expect(Versions.compare("1.0+build5", "1.0") == .orderedSame)
    }

    @Test func picksTheNewest() {
        #expect(Versions.newest(["2.1.9", "2.1.10", ".DS_Store", "2.0.99"]) == "2.1.10")
        #expect(Versions.newest(["notes", "tmp"]) == nil)
        #expect(Versions.newest([]) == nil)
    }

    @Test func readsVersionsFromInstallPaths() {
        #expect(Versions.fromPath("/opt/homebrew/Cellar/ollama/0.12.3/bin/ollama") == "0.12.3")
        #expect(Versions.fromPath("/Users/someone/.local/share/claude/versions/2.1.4") == "2.1.4")
        #expect(Versions.fromPath("/Users/someone/Library/Application Support/Claude/claude-code/2.1.4/abc/claude.app/Contents/MacOS/claude") == "2.1.4")
        #expect(Versions.fromPath("/usr/local/bin/codex") == nil)
        #expect(Versions.fromPath("/opt/homebrew/Cellar/ollama/HEAD/bin/ollama") == nil)
        #expect(Versions.fromPath("") == nil)
    }
}

@Suite("Footprint")
struct FootprintTests {
    @Test func sortsReadingsIntoTools() throws {
        let readings = Readings(
            appVersions: ["/Applications/Ollama.app": "0.12.3"],
            usage: [".ollama/models": Fixture.usage(8_000_000_000), ".claude/projects": Fixture.usage(400_000_000), ".ollama/logs": Fixture.usage(2_000_000)],
            launchItems: [Fixture.item("com.ollama.ollama"), Fixture.item("com.google.keystone.agent")]
        )
        let footprint = readings.footprint(tools: Tool.all, at: Fixture.start)
        let ollama = try #require(footprint.state("ollama"))
        #expect(ollama.version == "0.12.3")
        #expect(ollama.bytes == 8_002_000_000)
        #expect(ollama.launchItems.map(\.label) == ["com.ollama.ollama"])
        #expect(ollama.isInstalled)
        #expect(footprint.state("claude-code")?.bytes == 400_000_000)
        #expect(footprint.state("lm-studio")?.isInstalled == false)
        #expect(footprint.bytes == 8_402_000_000)
        // Login items that aren't an AI tool's are left out.
        #expect(!footprint.tools.flatMap(\.launchItems).contains { $0.label.contains("keystone") })
    }

    @Test func versionComesFromTheAppFirst() {
        let readings = Readings(
            appVersions: ["/Applications/Codex.app": "1.2.0"],
            processPaths: ["codex": ["/opt/homebrew/Cellar/codex/0.52.0/bin/codex"]]
        )
        #expect(readings.version(of: .codex) == "1.2.0")
    }

    @Test func thenFromVersionFolders() {
        let readings = Readings(
            folderEntries: [".local/share/claude/versions": ["2.1.3", "2.1.10", "2.1.9"]],
            processPaths: ["claude-code": ["/Users/someone/.local/share/claude/versions/2.1.3"]]
        )
        #expect(readings.version(of: .claudeCode) == "2.1.10")
    }

    @Test func thenFromRunningProcesses() {
        let readings = Readings(processPaths: ["codex": ["/opt/homebrew/Cellar/codex/0.51.0/bin/codex", "/opt/homebrew/Cellar/codex/0.52.0/bin/codex"]])
        #expect(readings.version(of: .codex) == "0.52.0")
        #expect(Readings().version(of: .codex) == nil)
    }

    @Test func marksVersionsThatOnlyCameFromProcesses() {
        let fromPath = Readings(processPaths: ["codex": ["/opt/homebrew/Cellar/codex/0.52.0/bin/codex"]])
        #expect(fromPath.footprint(tools: Tool.all, at: Fixture.start).state("codex")?.versionFromProcesses == true)
        let fromApp = Readings(appVersions: ["/Applications/Codex.app": "1.2.0"])
        #expect(fromApp.footprint(tools: Tool.all, at: Fixture.start).state("codex")?.versionFromProcesses == nil)
    }

    @Test func aToolWithOnlyALoginItemIsInstalled() {
        let state = ToolState(toolID: "codex", launchItems: [Fixture.item("com.openai.codex.updater")])
        #expect(state.isInstalled)
        #expect(!ToolState(toolID: "codex").isInstalled)
    }
}

@Suite("Login items")
struct LaunchItemTests {
    @Test func readsAPropertyList() throws {
        let data = Fixture.plist([
            "Label": "com.example.agent",
            "ProgramArguments": ["/usr/local/bin/agent", "--quiet"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StartInterval": 3600,
        ])
        let item = try #require(LaunchItem.parse(data, path: "/Users/someone/Library/LaunchAgents/com.example.agent.plist", scope: .user))
        #expect(item.label == "com.example.agent")
        #expect(item.program == "/usr/local/bin/agent")
        #expect(item.arguments == ["/usr/local/bin/agent", "--quiet"])
        #expect(item.runsAtLoad)
        #expect(item.keepsAlive)
        #expect(item.interval == 3600)
        #expect(item.id == "/Users/someone/Library/LaunchAgents/com.example.agent.plist")
    }

    @Test func programWinsOverArguments() throws {
        let data = Fixture.plist(["Label": "a", "Program": "/bin/real", "ProgramArguments": ["shown-name", "x"]])
        #expect(LaunchItem.parse(data, path: "/a.plist", scope: .user)?.program == "/bin/real")
    }

    @Test func keepAliveConditionsCount() throws {
        let crashes = Fixture.plist(["Label": "a", "KeepAlive": ["SuccessfulExit": false]])
        #expect(LaunchItem.parse(crashes, path: "/a.plist", scope: .user)?.keepsAlive == true)
        let off = Fixture.plist(["Label": "a", "KeepAlive": false])
        #expect(LaunchItem.parse(off, path: "/a.plist", scope: .user)?.keepsAlive == false)
        let none = Fixture.plist(["Label": "a"])
        #expect(LaunchItem.parse(none, path: "/a.plist", scope: .user)?.keepsAlive == false)
    }

    @Test func rejectsAnythingElse() {
        #expect(LaunchItem.parse(Data("not a plist".utf8), path: "/a.plist", scope: .user) == nil)
        #expect(LaunchItem.parse(Fixture.plist(["Program": "/bin/x"]), path: "/a.plist", scope: .user) == nil)
        #expect(LaunchItem.parse(Fixture.plist(["Label": ""]), path: "/a.plist", scope: .user) == nil)
        let array = try! PropertyListSerialization.data(fromPropertyList: ["a"], format: .xml, options: 0)
        #expect(LaunchItem.parse(array, path: "/a.plist", scope: .user) == nil)
    }

    @Test func binaryPropertyLists() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["Label": "b", "Program": "/bin/b"], format: .binary, options: 0)
        #expect(LaunchItem.parse(data, path: "/b.plist", scope: .allUsers)?.label == "b")
    }

    @Test func recognizesWhatItStarted() {
        let item = Fixture.item("x", program: "/opt/homebrew/opt/ollama/bin/ollama")
        #expect(item.runs(Fixture.process(1, name: "ollama", path: "/opt/homebrew/opt/ollama/bin/ollama")))
        // Through a symlink, the process runs from somewhere else with the same name and arguments.
        #expect(item.runs(Fixture.process(2, name: "ollama", path: "/opt/homebrew/Cellar/ollama/0.12.3/bin/ollama", arguments: ["/opt/homebrew/opt/ollama/bin/ollama"])))
        #expect(!item.runs(Fixture.process(3, name: "other", path: "/usr/bin/other")))
        #expect(!Fixture.item("y").runs(Fixture.process(4, name: "y", path: "/bin/y")))
    }

    @Test func argumentsArentSaved() throws {
        let item = LaunchItem(label: "a", plistPath: "/a.plist", scope: .user, program: "/bin/a", arguments: ["/bin/a", "--token", "secret"])
        let data = try JSONEncoder().encode(item)
        #expect(!String(decoding: data, as: UTF8.self).contains("secret"))
        let decoded = try JSONDecoder().decode(LaunchItem.self, from: data)
        #expect(decoded.arguments.isEmpty)
        #expect(decoded == item)
    }
}
