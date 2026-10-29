import Foundation
import Testing
@testable import FootprintCore

@Suite("Recognizing tools")
struct ToolMatchTests {
    let classifier = ProcessClassifier()

    private func tool(_ process: RunningProcess) -> String? {
        classifier.tool(for: process)?.id
    }

    @Test func nativeClaudeCode() {
        #expect(tool(Fixture.process(10, name: "claude", path: "/Users/someone/.local/share/claude/versions/2.1.4")) == "claude-code")
        #expect(tool(Fixture.process(10, name: "2.1.4", path: "/Users/someone/.local/share/claude/versions/2.1.4", arguments: ["claude"])) == "claude-code")
    }

    @Test func claudeCodeFromNpm() {
        let process = Fixture.process(10, name: "node", path: "/opt/homebrew/bin/node", arguments: ["node", "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"])
        #expect(tool(process) == "claude-code")
    }

    @Test func claudeCodeInsideTheClaudeApp() {
        let path = "/Users/someone/Library/Application Support/Claude/claude-code/2.1.4/abc/claude.app/Contents/MacOS/claude"
        #expect(tool(Fixture.process(10, name: "claude", path: path)) == "claude-code")
    }

    @Test func theClaudeAppAndItsHelpers() {
        #expect(tool(Fixture.process(10, name: "Claude", path: "/Applications/Claude.app/Contents/MacOS/Claude")) == "claude-app")
        #expect(tool(Fixture.process(11, name: "Claude Helper", path: "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper")) == "claude-app")
    }

    @Test func codexNativeAndFromNpm() {
        #expect(tool(Fixture.process(10, name: "codex", path: "/opt/homebrew/Cellar/codex/0.52.0/bin/codex")) == "codex")
        let script = Fixture.process(11, name: "node", path: "/usr/local/bin/node", arguments: ["node", "/usr/local/bin/codex"])
        #expect(tool(script) == "codex")
        let vendored = Fixture.process(12, name: "codex", path: "/usr/local/lib/node_modules/@openai/codex/vendor/aarch64-apple-darwin/codex/codex")
        #expect(tool(vendored) == "codex")
        #expect(tool(Fixture.process(13, name: "Codex", path: "/Applications/Codex.app/Contents/MacOS/Codex")) == "codex")
    }

    @Test func ollamaAndLMStudio() {
        #expect(tool(Fixture.process(10, name: "ollama", path: "/Applications/Ollama.app/Contents/Resources/ollama", arguments: ["ollama", "serve"])) == "ollama")
        #expect(tool(Fixture.process(11, name: "LM Studio", path: "/Applications/LM Studio.app/Contents/MacOS/LM Studio")) == "lm-studio")
        #expect(tool(Fixture.process(12, name: "lms", path: "/Users/someone/.lmstudio/bin/lms")) == "lm-studio")
        #expect(tool(Fixture.process(13, name: "huggingface-cli", path: "/opt/homebrew/bin/huggingface-cli")) == "hugging-face")
    }

    @Test func otherProcessesAreLeftAlone() {
        #expect(tool(Fixture.process(10, name: "node", path: "/opt/homebrew/bin/node", arguments: ["node", "server.js"])) == nil)
        #expect(tool(Fixture.process(11, name: "Safari", path: "/Applications/Safari.app/Contents/MacOS/Safari")) == nil)
        // Names that only contain a tool's name aren't it.
        #expect(tool(Fixture.process(12, name: "claudette", path: "/usr/local/bin/claudette")) == nil)
        #expect(tool(Fixture.process(13, name: "codexer", path: "/usr/local/bin/codexer")) == nil)
    }

    @Test func aScriptIsOnlyTheFirstNonFlagArgument() {
        let process = Fixture.process(10, name: "node", path: "/usr/local/bin/node", arguments: ["node", "--max-old-space-size=4096", "/srv/app.js", "codex"])
        #expect(tool(process) == nil)
    }

    @Test func loginItemsByLabelOrProgram() {
        #expect(classifier.tool(for: Fixture.item("com.ollama.ollama"))?.id == "ollama")
        #expect(classifier.tool(for: Fixture.item("homebrew.mxcl.ollama", program: "/opt/homebrew/opt/ollama/bin/ollama"))?.id == "ollama")
        #expect(classifier.tool(for: Fixture.item("com.example.agent", program: "/usr/local/bin/codex"))?.id == "codex")
        #expect(classifier.tool(for: Fixture.item("com.anthropic.claude.updater"))?.id == "claude-app")
        #expect(classifier.tool(for: Fixture.item("ai.elementlabs.lmstudio.daemon"))?.id == "lm-studio")
        #expect(classifier.tool(for: Fixture.item("com.google.keystone.agent", program: "/Library/Google/keystone"))?.id == nil)
        #expect(classifier.tool(for: Fixture.item("com.valvesoftware.steamclean"))?.id == nil)
    }

    @Test func labelsMatchWhateverTheirCase() {
        #expect(classifier.tool(for: Fixture.item("COM.Ollama.Agent"))?.id == "ollama")
    }
}

@Suite("MCP servers")
struct MCPTests {
    private func name(_ arguments: [String], path: String? = nil) -> String? {
        MCP.serverName(Fixture.process(10, name: "x", path: path, arguments: arguments))
    }

    @Test func officialPackages() {
        #expect(name(["npm", "exec", "@modelcontextprotocol/server-filesystem", "/Users/someone/code"]) == "server-filesystem")
        #expect(name(["node", "/Users/someone/.npm/_npx/abc/node_modules/.bin/mcp-server-filesystem"]) == "mcp-server-filesystem")
        #expect(name(["npx", "-y", "@modelcontextprotocol/server-github@2025.4.8"]) == "server-github")
    }

    @Test func pythonAndUvx() {
        #expect(name(["uvx", "mcp-server-fetch"]) == "mcp-server-fetch")
        #expect(name(["python3", "-m", "mcp_server_time", "--local-timezone=America/Chicago"]) == "mcp_server_time")
        #expect(name(["uv", "run", "fastmcp", "run", "server.py"]) == "fastmcp")
    }

    @Test func containersAndBinaries() {
        #expect(name(["docker", "run", "-i", "--rm", "ghcr.io/github/github-mcp-server:latest"]) == "github-mcp-server")
        #expect(name(["/usr/local/bin/xcode-mcp"], path: "/usr/local/bin/xcode-mcp") == "xcode-mcp")
        #expect(name(["mcp-remote", "https://example.com/sse"]) == "mcp-remote")
    }

    @Test func flagsAndTheirValuesDontCount() {
        // Claude Code's own flags mention MCP, but it isn't an MCP server.
        #expect(name(["claude", "--mcp-config", "servers.json"]) == nil)
        #expect(name(["node", "app.js", "--config=mcp.json"]) == nil)
        #expect(name(["node", "app.js", "--name", "-mcp"]) == nil)
    }

    @Test func mcpMustBeAWordOfItsOwn() {
        #expect(MCP.looksLikeMCP("mcp"))
        #expect(MCP.looksLikeMCP("mcp-server-git"))
        #expect(MCP.looksLikeMCP("github-mcp-server"))
        #expect(MCP.looksLikeMCP("mcp_server_time"))
        #expect(MCP.looksLikeMCP("fastmcp"))
        #expect(!MCP.looksLikeMCP("imcp"))
        #expect(!MCP.looksLikeMCP("mcpherson"))
        #expect(!MCP.looksLikeMCP("server"))
    }

    @Test func toolNamesAndListsInArgumentsDontCount() {
        #expect(name(["node", "app.js", "mcp__github__search"]) == nil)
        #expect(name(["node", "app.js", "Bash,mcp__notes__read"]) == nil)
        #expect(name(["node", "app.js", #"{"mcpServers":{}}"#]) == nil)
    }

    @Test func aToolIsOnlyAServerWhenItSaysSo() {
        func isServer(_ arguments: [String]) -> Bool { MCP.isToolServer(Fixture.process(1, name: "x", arguments: arguments)) }
        #expect(isServer(["claude", "mcp", "serve"]))
        #expect(isServer(["codex", "mcp-server"]))
        #expect(isServer(["codex", "--verbose", "mcp", "serve"]))
        #expect(!isServer(["claude", "mcp", "list"]))
        #expect(!isServer(["claude", "mcp"]))
        #expect(!isServer(["claude", "--mcp-config", "mcp.json"]))
    }

    @Test func plainServersAreNotMCP() {
        #expect(name(["node", "/srv/server.js"]) == nil)
        #expect(name(["python3", "-m", "http.server"]) == nil)
    }
}

@Suite("MCP servers, carefully")
struct MCPCarefulTests {
    private func name(_ arguments: [String]) -> String? {
        MCP.serverName(Fixture.process(10, name: "x", arguments: arguments))
    }

    @Test func secretsAfterFlagsArentNames() {
        #expect(name(["node", "app.js", "--key", "sk-mcp-abc"]) == nil)
        #expect(name(["node", "app.js", "--api-key", "my-mcp-token"]) == nil)
        #expect(name(["node", "app.js", "-H", "x"]) == nil)
        #expect(name(["node", "/srv/notes-mcp/index.js", "--header", "Authorization: Bearer mcp-123"]) == "notes-mcp")
        // A flag that takes no secret doesn't hide what follows.
        #expect(name(["npx", "-y", "@modelcontextprotocol/server-memory"]) == "server-memory")
        #expect(MCP.looksPrivate("--api-key"))
        #expect(MCP.looksPrivate("--Authorization-Header"))
        #expect(!MCP.looksPrivate("-y"))
    }

    @Test func dockerHubsMCPImages() {
        #expect(name(["docker", "run", "-i", "--rm", "mcp/github"]) == "github")
        #expect(name(["docker", "run", "-i", "--rm", "docker.io/mcp/fetch:latest"]) == "fetch")
        #expect(name(["docker", "run", "-i", "--rm", "library/postgres"]) == nil)
    }
}

@Suite("Process arguments")
struct ProcessArgumentsTests {
    @Test func readsThePathAndArguments() throws {
        let buffer = Fixture.procargs(path: "/usr/local/bin/node", arguments: ["node", "server.js", "--port", "3000"])
        let parsed = try #require(ProcessArguments.parse(buffer))
        #expect(parsed.path == "/usr/local/bin/node")
        #expect(parsed.arguments == ["node", "server.js", "--port", "3000"])
    }

    @Test func neverReadsTheEnvironment() throws {
        let buffer = Fixture.procargs(path: "/bin/tool", arguments: ["tool"], environment: ["API_KEY=secret", "HOME=/Users/someone"])
        let parsed = try #require(ProcessArguments.parse(buffer))
        #expect(parsed.arguments == ["tool"])
        #expect(!parsed.arguments.joined().contains("secret"))
    }

    @Test func handlesAnyAmountOfPadding() throws {
        for padding in [0, 1, 7, 40] {
            let parsed = try #require(ProcessArguments.parse(Fixture.procargs(path: "/bin/a", arguments: ["a", "b"], padding: padding)))
            #expect(parsed.arguments == ["a", "b"])
        }
    }

    @Test func emptyAndDamagedBuffers() {
        #expect(ProcessArguments.parse([]) == nil)
        #expect(ProcessArguments.parse([1, 0]) == nil)
        // A count with no path after it.
        #expect(ProcessArguments.parse([1, 0, 0, 0, 65, 66]) == nil)
        // A count far too big is a damaged buffer.
        #expect(ProcessArguments.parse([255, 255, 255, 127, 47, 0]) == nil)
    }

    @Test func stopsAtTheEndOfAShortBuffer() throws {
        var buffer = Fixture.procargs(path: "/bin/a", arguments: ["a", "b", "c"])
        buffer.removeLast(2) // "c" and its terminator
        let parsed = try #require(ProcessArguments.parse(buffer))
        #expect(parsed.arguments == ["a", "b"])
    }

    @Test func zeroArguments() throws {
        let parsed = try #require(ProcessArguments.parse(Fixture.procargs(path: "/bin/a", arguments: [])))
        #expect(parsed.path == "/bin/a")
        #expect(parsed.arguments.isEmpty)
    }
}

@Suite("Sorting processes")
struct ClassifierTests {
    let classifier = ProcessClassifier()

    @Test func anAppAndItsHelpersAreOneEntry() throws {
        let processes = [
            Fixture.process(100, name: "Claude", path: "/Applications/Claude.app/Contents/MacOS/Claude", memory: 400_000_000, app: ("Claude", "com.anthropic.claudefordesktop")),
            Fixture.process(101, parent: 100, name: "Claude Helper", path: "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper", memory: 100_000_000),
            Fixture.process(102, parent: 100, name: "Claude Helper (Renderer)", path: "/Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)", memory: 200_000_000),
        ]
        let found = classifier.classify(processes)
        let app = try #require(found.first)
        #expect(found.count == 1)
        #expect(app.role == .app)
        #expect(app.name == "Claude")
        #expect(app.pids == [100, 101, 102])
        #expect(app.helpers == 2)
        #expect(app.residentBytes == 700_000_000)
        #expect(app.attachment == .app)
        #expect(app.bundleID == "com.anthropic.claudefordesktop")
        #expect(!app.isBackground)
    }

    @Test func aSessionInATerminal() throws {
        let processes = [Fixture.terminalApp, Fixture.login, Fixture.shell,
                         Fixture.process(500, parent: 402, name: "claude", path: "/Users/someone/.local/share/claude/versions/2.1.4", terminal: true)]
        let session = try #require(classifier.classify(processes).first)
        #expect(session.toolID == "claude-code")
        #expect(session.role == .session)
        #expect(session.attachment == .terminal)
        #expect(!session.isBackground)
    }

    @Test func anMCPServerBelongsToWhatStartedIt() throws {
        let processes = [Fixture.terminalApp, Fixture.login, Fixture.shell,
                         Fixture.process(500, parent: 402, name: "claude", path: "/Users/someone/.local/share/claude/versions/2.1.4", terminal: true),
                         Fixture.process(510, parent: 500, name: "node", path: "/opt/homebrew/bin/node", arguments: ["npm", "exec", "@modelcontextprotocol/server-filesystem"], memory: 40_000_000, terminal: true),
                         Fixture.process(511, parent: 510, name: "node", path: "/opt/homebrew/bin/node", arguments: ["node", "/Users/someone/.npm/_npx/1/node_modules/.bin/mcp-server-filesystem"], memory: 60_000_000, terminal: true)]
        let found = classifier.classify(processes)
        #expect(found.count == 2)
        let server = try #require(found.first { $0.role == .mcpServer })
        #expect(server.toolID == nil)
        #expect(server.launchedBy == "claude-code")
        #expect(server.attachment == .parent(name: "Claude Code"))
        #expect(server.name == "server-filesystem")
        // The npx wrapper and the server it started are one server.
        #expect(server.pids == [510, 511])
        #expect(server.residentBytes == 100_000_000)
        #expect(!server.isOrphaned)
    }

    @Test func anMCPServerLeftBehindIsOrphaned() throws {
        let processes = [Fixture.process(600, parent: 1, name: "node", path: "/opt/homebrew/bin/node", arguments: ["node", "/Users/someone/mcp/notes-mcp/index.js"])]
        let server = try #require(classifier.classify(processes).first)
        #expect(server.isOrphaned)
        #expect(server.isLeftRunning)
        #expect(server.isBackground)
        #expect(server.name == "notes-mcp")
    }

    @Test func anOrphanThatOnceHadATerminalIsStillOrphaned() throws {
        // When a terminal closes, a process that survives is handed to launchd but can keep its old terminal.
        let processes = [Fixture.process(600, parent: 1, name: "node", path: "/opt/homebrew/bin/node", arguments: ["node", "/srv/notes-mcp/index.js"], terminal: true)]
        let server = try #require(classifier.classify(processes).first)
        #expect(server.attachment == .none)
        #expect(server.isOrphaned)
    }

    @Test func anMCPServerStartedByAnotherApp() throws {
        let editor = Fixture.process(700, name: "Editor", path: "/Applications/Editor.app/Contents/MacOS/Editor", app: ("Editor", "com.example.editor"))
        let helper = Fixture.process(701, parent: 700, name: "Editor Helper", path: "/Applications/Editor.app/Contents/Frameworks/Editor Helper.app/Contents/MacOS/Editor Helper")
        let server = Fixture.process(702, parent: 701, name: "node", path: "/usr/local/bin/node", arguments: ["node", "/x/mcp-server-git/dist/index.js"])
        let found = try #require(classifier.classify([editor, helper, server]).first)
        #expect(found.attachment == .parent(name: "Editor"))
        #expect(found.launchedBy == nil)
        #expect(!found.isOrphaned)
    }

    @Test func aServerStartedByItsApp() throws {
        let app = Fixture.process(800, name: "Ollama", path: "/Applications/Ollama.app/Contents/MacOS/Ollama", app: ("Ollama", "com.electron.ollama"))
        let server = Fixture.process(801, parent: 800, name: "ollama", path: "/Applications/Ollama.app/Contents/Resources/ollama", arguments: ["ollama", "serve"], memory: 50_000_000)
        let found = classifier.classify([app, server])
        // A server isn't a helper, so it gets its own entry.
        #expect(found.count == 2)
        let serve = try #require(found.first { $0.role == .server })
        #expect(serve.name == "ollama serve")
        #expect(serve.attachment == .parent(name: "Ollama"))
        #expect(serve.isBackground)
        #expect(!serve.isLeftRunning)
    }

    @Test func aServerLeftRunningAfterItsAppQuit() throws {
        let server = Fixture.process(900, parent: 1, name: "codex", path: "/Applications/Codex.app/Contents/Resources/codex", arguments: ["codex", "app-server"])
        let found = try #require(classifier.classify([server]).first)
        #expect(found.role == .server)
        #expect(found.name == "codex app-server")
        #expect(found.isLeftRunning)
        #expect(!found.isOrphaned)
        #expect(found.isBackground)
    }

    @Test func aServerALoginItemStarts() throws {
        let path = "/opt/homebrew/opt/ollama/bin/ollama"
        let server = Fixture.process(950, parent: 1, name: "ollama", path: path, arguments: [path, "serve"])
        var item = Fixture.item("homebrew.mxcl.ollama", program: path, keepsAlive: true)
        item.arguments = [path, "serve"]
        let found = try #require(classifier.classify([server], launchItems: [item]).first)
        #expect(found.attachment == .launchItem(label: "homebrew.mxcl.ollama", scope: .user))
        #expect(!found.isLeftRunning)
        #expect(found.isBackground)
    }

    @Test func aParentOutOfSightIsntMistakenForAnOrphan() throws {
        // Its parent belongs to another user, so it isn't in the list.
        let server = Fixture.process(960, parent: 77, name: "node", path: "/usr/local/bin/node", arguments: ["node", "/srv/mcp-server-git/index.js"])
        let found = try #require(classifier.classify([server]).first)
        #expect(found.attachment == .parent(name: "another process"))
        #expect(!found.isOrphaned)
    }

    @Test func claudeCodeStartedByTheClaudeApp() throws {
        let app = Fixture.process(100, name: "Claude", path: "/Applications/Claude.app/Contents/MacOS/Claude", app: ("Claude", "com.anthropic.claudefordesktop"))
        let wrapper = Fixture.process(110, parent: 100, name: "disclaimer", path: "/Applications/Claude.app/Contents/Helpers/disclaimer", memory: 16_000)
        let code = Fixture.process(111, parent: 110, name: "claude", path: "/Users/someone/Library/Application Support/Claude/claude-code/2.1.4/abc/claude.app/Contents/MacOS/claude", memory: 200_000_000)
        let found = classifier.classify([app, wrapper, code])
        #expect(found.count == 2)
        let session = try #require(found.first { $0.toolID == "claude-code" })
        #expect(session.attachment == .parent(name: "Claude app"))
        #expect(session.role == .session)
        let claude = try #require(found.first { $0.toolID == "claude-app" })
        #expect(claude.pids == [100, 110])
    }

    @Test func aSessionWhoseArgumentsMentionMCPTools() throws {
        // The Claude app starts Claude Code with MCP tool names in its arguments.
        let app = Fixture.process(100, name: "Claude", path: "/Applications/Claude.app/Contents/MacOS/Claude", app: ("Claude", "com.anthropic.claudefordesktop"))
        let wrapper = Fixture.process(110, parent: 100, name: "disclaimer", path: "/Applications/Claude.app/Contents/Helpers/disclaimer",
                                      arguments: ["disclaimer", "/x/claude", "--permission-prompt-tool", "mcp__app__approve", "--allowedTools", "Read,mcp__notes__search"])
        let code = Fixture.process(111, parent: 110, name: "claude", path: "/Users/someone/Library/Application Support/Claude/claude-code/2.1.4/abc/claude.app/Contents/MacOS/claude",
                                   arguments: ["/x/claude", "--permission-prompt-tool", "mcp__app__approve", "--mcp-config", "{\"mcpServers\":{}}"])
        let found = classifier.classify([app, wrapper, code])
        #expect(found.count == 2)
        #expect(!found.contains { $0.role == .mcpServer })
        let session = try #require(found.first { $0.toolID == "claude-code" })
        #expect(session.role == .session)
        #expect(session.name == "claude")
    }

    @Test func aDetachedHelperBelongsToItsOpenApp() throws {
        // Electron's crash reporter is started on its own, so its parent is launchd.
        let app = Fixture.process(100, name: "Claude", path: "/Applications/Claude.app/Contents/MacOS/Claude", app: ("Claude", "com.anthropic.claudefordesktop"))
        let crashpad = Fixture.process(101, parent: 1, name: "chrome_crashpad", path: "/Applications/Claude.app/Contents/Frameworks/Electron Framework.framework/Helpers/chrome_crashpad_handler", memory: 700_000)
        let found = classifier.classify([app, crashpad])
        #expect(found.count == 1)
        #expect(found.first?.pids == [100, 101])
        #expect(found.allSatisfy { !$0.isLeftRunning })
        // With the app closed, it really is left running.
        let alone = try #require(classifier.classify([crashpad]).first)
        #expect(alone.isLeftRunning)
        #expect(alone.role == .helper)
    }

    @Test func aToolRunningAsAnMCPServer() throws {
        let processes = [Fixture.process(500, parent: 1, name: "claude", path: "/Users/someone/.local/share/claude/versions/2.1.4", arguments: ["claude", "mcp", "serve"])]
        let found = try #require(classifier.classify(processes).first)
        #expect(found.role == .mcpServer)
        #expect(found.toolID == "claude-code")
        #expect(found.name == "Claude Code")
        // Listing its servers isn't being one.
        let listing = [Fixture.process(501, parent: 1, name: "claude", path: "/Users/someone/.local/share/claude/versions/2.1.4", arguments: ["claude", "mcp", "list"])]
        #expect(classifier.classify(listing).first?.role == .session)
    }

    @Test func sortsByMemory() {
        let processes = [
            Fixture.process(1001, parent: 1, name: "node", arguments: ["node", "a-mcp"], memory: 10),
            Fixture.process(1002, parent: 1, name: "node", arguments: ["node", "b-mcp"], memory: 30),
            Fixture.process(1003, parent: 1, name: "node", arguments: ["node", "c-mcp"], memory: 20),
        ]
        #expect(classifier.classify(processes).map(\.pid) == [1002, 1003, 1001])
    }

    @Test func survivesALoopInParents() {
        // The system never reports this, but a damaged list mustn't hang the app.
        let processes = [
            Fixture.process(1, parent: 2, name: "a-mcp", arguments: ["a-mcp"]),
            Fixture.process(2, parent: 3, name: "b", arguments: ["b"]),
            Fixture.process(3, parent: 2, name: "c", arguments: ["c"]),
            Fixture.process(4, parent: 3, name: "node", arguments: ["node", "d-mcp"]),
        ]
        #expect(classifier.classify(processes).count == 2)
    }

    @Test func ignoresEverythingElse() {
        let processes = [Fixture.terminalApp, Fixture.login, Fixture.shell,
                         Fixture.process(1100, parent: 402, name: "node", path: "/usr/local/bin/node", arguments: ["node", "server.js"], terminal: true)]
        #expect(classifier.classify(processes).isEmpty)
    }

    @Test func aSessionsMCPServerInsideAGrandchild() throws {
        // Codex starts servers through a shell.
        let processes = [
            Fixture.process(1200, parent: 1, name: "codex", path: "/opt/homebrew/bin/codex", arguments: ["codex", "app-server"]),
            Fixture.process(1201, parent: 1200, name: "sh", path: "/bin/sh", arguments: ["sh", "-c", "uvx mcp-server-fetch"]),
            Fixture.process(1202, parent: 1201, name: "python3", path: "/usr/bin/python3", arguments: ["python3", "mcp-server-fetch"]),
        ]
        let server = try #require(classifier.classify(processes).first { $0.role == .mcpServer })
        #expect(server.launchedBy == "codex")
        #expect(server.attachment == .parent(name: "Codex"))
    }

    @Test func aServerUnderAProcessManagerIsntOrphaned() throws {
        // pm2 itself runs under launchd, but it's still there looking after the server.
        let manager = Fixture.process(1300, parent: 1, name: "node", path: "/opt/homebrew/bin/node", arguments: ["PM2 v5.3.0: God Daemon"])
        let server = Fixture.process(1301, parent: 1300, name: "node", path: "/opt/homebrew/bin/node", arguments: ["node", "/srv/notes-mcp/index.js"])
        let found = try #require(classifier.classify([manager, server]).first)
        #expect(found.attachment == .parent(name: "node"))
        #expect(!found.isOrphaned)
        #expect(!found.isLeftRunning)
    }

    @Test func aServersNameNeverIncludesOtherArguments() throws {
        let secret = #"model_providers.x.http_headers.Authorization="Bearer sk-123""#
        let process = Fixture.process(1400, parent: 1, name: "codex", path: "/opt/homebrew/bin/codex", arguments: ["codex", "-c", secret, "app-server"])
        let found = try #require(classifier.classify([process]).first)
        #expect(found.name == "codex app-server")
        #expect(!found.name.contains("sk-"))
    }

    @Test func modelRunnersFoldIntoTheirServer() throws {
        let server = Fixture.process(1500, parent: 1, name: "ollama", path: "/opt/homebrew/bin/ollama", arguments: ["ollama", "serve"], memory: 100)
        let runner = Fixture.process(1501, parent: 1500, name: "ollama", path: "/opt/homebrew/bin/ollama", arguments: ["ollama", "runner", "--model", "/x/blobs/sha256-1"], memory: 4000)
        let found = classifier.classify([server, runner])
        #expect(found.count == 1)
        #expect(found.first?.pids == [1500, 1501])
        #expect(found.first?.residentBytes == 4100)
        #expect(found.first?.name == "ollama serve")
    }

    @Test func anyPythonRunsAScript() {
        let process = Fixture.process(1600, name: "Python", path: "/opt/homebrew/Cellar/python@3.12/3.12.4/Frameworks/Python.framework/Versions/3.12/Resources/Python.app/Contents/MacOS/Python", arguments: ["/opt/homebrew/opt/python@3.12/bin/python3.12", "/Users/someone/.local/bin/hf", "download"])
        #expect(classifier.tool(for: process)?.id == "hugging-face")
    }
}
