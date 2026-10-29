import Foundation

public typealias ProcessID = Int32

/// A process as the system reports it. Arguments are only used to recognize the process, and are
/// never saved or shown, since they can hold things like API keys.
public struct RunningProcess: Hashable, Sendable {
    public var pid: ProcessID
    public var parent: ProcessID
    /// The short name the system keeps, cut to 16 characters.
    public var name: String
    public var path: String?
    public var arguments: [String]
    public var residentBytes: Int64
    public var started: Date?
    /// Whether it runs in a Terminal window or other terminal.
    public var hasTerminal: Bool
    /// Set for apps with a Dock icon or a menu bar icon, with the app's name and bundle ID.
    public var app: (name: String, bundleID: String?)?

    public init(
        pid: ProcessID, parent: ProcessID, name: String, path: String? = nil, arguments: [String] = [],
        residentBytes: Int64 = 0, started: Date? = nil, hasTerminal: Bool = false, app: (name: String, bundleID: String?)? = nil
    ) {
        self.pid = pid
        self.parent = parent
        self.name = name
        self.path = path
        self.arguments = arguments
        self.residentBytes = residentBytes
        self.started = started
        self.hasTerminal = hasTerminal
        self.app = app
    }

    public static func == (a: RunningProcess, b: RunningProcess) -> Bool {
        a.pid == b.pid && a.parent == b.parent && a.name == b.name && a.path == b.path && a.arguments == b.arguments
            && a.residentBytes == b.residentBytes && a.started == b.started && a.hasTerminal == b.hasTerminal
            && a.app?.name == b.app?.name && a.app?.bundleID == b.app?.bundleID
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
        hasher.combine(started)
    }

    /// Runtimes that run a script named in the next argument.
    static let interpreters: Set<String> = ["node", "bun", "deno", "ruby", "perl"]

    /// Whether a command runs a script: a runtime above, or any Python, like `python3.12`.
    static func isInterpreter(_ name: String) -> Bool {
        interpreters.contains(name) || name.lowercased().hasPrefix("python")
    }

    /// The names it goes by: the executable, the first argument, and the script an interpreter runs.
    var commandNames: [String] {
        // Case matters: `claude` is Claude Code, while `Claude` is the Claude app.
        var names = [name]
        if let path { names.append(Self.command(path)) }
        if let first = arguments.first { names.append(Self.command(first)) }
        if names.contains(where: Self.isInterpreter), let script = arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) {
            names.append(Self.command(script))
        }
        return names
    }

    /// `/usr/local/bin/codex.js` → `codex`.
    static func command(_ path: String) -> String {
        var name = (path as NSString).lastPathComponent
        for suffix in [".js", ".mjs", ".cjs", ".ts", ".py", ".exe"] where name.lowercased().hasSuffix(suffix) {
            name.removeLast(suffix.count)
        }
        return name
    }
}

/// Reads the buffer `sysctl(KERN_PROCARGS2)` fills in: the argument count, the executable path,
/// padding, the arguments, then the environment. The environment is never read.
public enum ProcessArguments {
    public static func parse(_ buffer: [UInt8]) -> (path: String, arguments: [String])? {
        let countSize = MemoryLayout<Int32>.size
        guard buffer.count > countSize else { return nil }
        let count = buffer.prefix(countSize).withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        guard count >= 0, count < 4096 else { return nil }
        var index = countSize
        func string() -> String? {
            guard index < buffer.count, let end = buffer[index...].firstIndex(of: 0) else { return nil }
            let text = String(decoding: buffer[index..<end], as: UTF8.self)
            index = end + 1
            return text
        }
        guard let path = string() else { return nil }
        while index < buffer.count, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        for _ in 0..<count {
            guard let argument = string() else { break }
            arguments.append(argument)
        }
        return (path, arguments)
    }
}

/// Recognizes MCP servers from their command line.
public enum MCP {
    /// The server's name, like `server-filesystem` or `github-mcp-server`, or nil if this doesn't
    /// look like an MCP server. Only package and script names count, never flags or their values.
    public static func serverName(_ process: RunningProcess) -> String? {
        // A command run through `sh -c` arrives as one argument, so it's split into words.
        // Tool names like `mcp__github__search` and lists of them are settings, not a server's name,
        // and the value after a flag like `--api-key` is never looked at, so it can't become one.
        var tokens: [String] = []
        var skipNext = false
        for word in process.arguments.flatMap({ $0.split(whereSeparator: \.isWhitespace).map(String.init) }) {
            if skipNext { skipNext = false; continue }
            if word.hasPrefix("-") {
                skipNext = !word.contains("=") && looksPrivate(word)
                continue
            }
            if word.contains("=") || word.contains("__") || word.contains(",") || word.contains("{") || word.contains("\"") { continue }
            tokens.append(word)
        }
        if let path = process.path { tokens.insert(path, at: 0) }
        for token in tokens {
            if let name = name(from: token) { return name }
        }
        return nil
    }

    static func name(from token: String) -> String? {
        // `@modelcontextprotocol/server-filesystem@1.2.0` and `ghcr.io/org/github-mcp-server:latest`.
        var text = token
        if let at = text.dropFirst().lastIndex(of: "@"), !text[at...].contains("/") {
            text = String(text[..<at])
        }
        if let colon = text.lastIndex(of: ":"), !text[colon...].contains("/") {
            text = String(text[..<colon])
        }
        let lowered = text.lowercased()
        let last = meaningfulName(lowered)
        // Docker Hub's MCP catalog: `mcp/github`, `docker.io/mcp/github`.
        if lowered.hasPrefix("mcp/") || lowered.contains("/mcp/") { return last }
        if lowered.contains("modelcontextprotocol") {
            return last == "modelcontextprotocol" ? "mcp" : last
        }
        return looksLikeMCP(last) ? last : nil
    }

    /// Flags whose value may be a secret or a setting, like `--api-key` or `--header`.
    static func looksPrivate(_ flag: String) -> Bool {
        let name = flag.lowercased()
        return ["key", "token", "secret", "auth", "pass", "header", "cookie", "env", "config", "cred"].contains { name.contains($0) }
    }

    /// Folders and files that say nothing about what a script is.
    static let genericNames: Set<String> = ["index", "main", "server", "cli", "dist", "build", "src", "lib", "bin", "out", "app", ".bin"]

    /// The last part of a path that names something: `notes-mcp` for `/srv/notes-mcp/dist/index.js`.
    static func meaningfulName(_ path: String) -> String {
        let parts = path.split(separator: "/").map { RunningProcess.command(String($0)) }
        return parts.last(where: { !genericNames.contains($0) && !$0.isEmpty }) ?? RunningProcess.command(path)
    }

    /// Whether a known tool is running as an MCP server itself, like `claude mcp serve` or
    /// `codex mcp-server`. Its other arguments often mention MCP without it being a server.
    static func isToolServer(_ process: RunningProcess) -> Bool {
        let words = process.arguments.dropFirst().filter { !$0.hasPrefix("-") }.map { $0.lowercased() }
        if words.contains("mcp-server") { return true }
        guard let index = words.firstIndex(of: "mcp") else { return false }
        return words.dropFirst(index + 1).first == "serve"
    }

    /// `mcp` as a word of its own: `mcp-server-git`, `github-mcp-server`, `mcp_server_time`,
    /// `fastmcp`, but not `imcp` or `mcpherson`.
    static func looksLikeMCP(_ name: String) -> Bool {
        if name.hasPrefix("fastmcp") { return true }
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return words.contains("mcp")
    }
}

/// What a process does for its tool.
public enum ProcessRole: String, Codable, Sendable, CaseIterable {
    /// The app itself, with a Dock or menu bar icon.
    case app
    /// A helper inside the app's bundle.
    case helper
    /// A server or daemon, like `ollama serve`.
    case server
    /// A command-line session, like `claude` or `codex` in a terminal.
    case session
    case mcpServer
}

/// What keeps a process running.
public enum Attachment: Hashable, Sendable {
    /// It's an app you can see and quit.
    case app
    /// It runs in a terminal.
    case terminal
    /// A login item starts it. A system one runs as root and needs `sudo` to stop.
    case launchItem(label: String, scope: LaunchItem.Scope)
    /// Another app or tool started it.
    case parent(name: String)
    /// Nothing: whatever started it has gone, and it was left running.
    case none
}

/// A process that belongs to an AI tool, with its helpers folded in.
public struct ToolProcess: Identifiable, Hashable, Sendable {
    public var pid: ProcessID
    /// This process and the helpers folded into it.
    public var pids: [ProcessID]
    /// The tool it belongs to. Nil for an MCP server, which belongs to whatever started it.
    public var toolID: String?
    /// For an MCP server, the tool that started it.
    public var launchedBy: String?
    public var name: String
    public var role: ProcessRole
    public var attachment: Attachment
    public var residentBytes: Int64
    public var path: String?
    public var bundleID: String?
    public var started: Date?
    public var helpers: Int { pids.count - 1 }

    public var id: ProcessID { pid }

    /// An MCP server whose app has quit. It talks to its app over a pipe that's now closed, so it
    /// does nothing but use memory.
    public var isOrphaned: Bool { role == .mcpServer && attachment == .none }

    /// Running without an app, terminal or login item to show for it.
    public var isLeftRunning: Bool { attachment == .none }

    /// Running on its own, out of sight: started by a login item, left running, or a server. An MCP
    /// server or helper that goes away with the app or session it belongs to doesn't count.
    public var isBackground: Bool {
        switch attachment {
        case .app, .terminal: false
        case .launchItem, .none: true
        case .parent: role == .server
        }
    }
}

/// Sorts the system's processes into the tools they belong to.
public struct ProcessClassifier: Sendable {
    public let tools: [Tool]

    public init(tools: [Tool] = Tool.all) {
        self.tools = tools
    }

    /// The tool a process belongs to, by its command, path or arguments.
    public func tool(for process: RunningProcess) -> Tool? {
        let names = process.commandNames
        return tools.first { tool in
            let match = tool.match
            if names.contains(where: match.commands.contains) { return true }
            if let path = process.path, match.pathContains.contains(where: path.contains) { return true }
            return process.arguments.contains { argument in match.argumentContains.contains(where: argument.contains) }
        }
    }

    /// The tool a login item belongs to, by its label or what it runs.
    public func tool(for item: LaunchItem) -> Tool? {
        let label = item.label.lowercased()
        if let tool = tools.first(where: { $0.match.labelPrefixes.contains { label.hasPrefix($0.lowercased()) } }) {
            return tool
        }
        guard let program = item.program else { return nil }
        return tool(for: RunningProcess(pid: 0, parent: 0, name: RunningProcess.command(program), path: program, arguments: item.arguments))
    }

    public func classify(_ processes: [RunningProcess], launchItems: [LaunchItem] = []) -> [ToolProcess] {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var found: [ProcessID: ToolProcess] = [:]
        for process in processes {
            let tool = tool(for: process)
            let server = tool == nil ? MCP.serverName(process) : MCP.isToolServer(process) ? tool?.name : nil
            guard tool != nil || server != nil else { continue }
            let role = role(of: process, tool: tool, isMCP: server != nil)
            found[process.pid] = ToolProcess(
                pid: process.pid, pids: [process.pid], toolID: role == .mcpServer && tool == nil ? nil : tool?.id,
                launchedBy: nil, name: displayName(process, tool: tool, role: role, server: server), role: role, attachment: .none,
                residentBytes: process.residentBytes, path: process.path, bundleID: process.app?.bundleID, started: process.started
            )
        }

        // Work out what keeps each one running, and fold helpers into what they help.
        var folded: [ProcessID: ProcessID] = [:]
        for pid in found.keys.sorted() {
            guard var entry = found[pid], let process = byPID[pid] else { continue }
            let (attachment, parentOwner) = attachment(of: process, byPID: byPID, found: found, launchItems: launchItems)
            entry.attachment = attachment
            var owner = parentOwner
            // Some helpers, like Electron's crash reporter, are started on their own on purpose.
            // While their app is open, they belong to it rather than being left running.
            if attachment == .none, entry.role == .helper, let app = found.values.filter({ $0.toolID == entry.toolID && $0.role == .app }).min(by: { $0.pid < $1.pid }) {
                entry.attachment = .parent(name: app.name)
                owner = app.pid
            }
            if entry.role == .mcpServer, let owner {
                entry.launchedBy = found[owner]?.toolID ?? found[owner]?.launchedBy
            }
            found[pid] = entry
            if let owner, let parent = found[owner], belongsInside(entry, parent) {
                folded[pid] = owner
            }
        }
        for (child, owner) in folded {
            var root = owner
            while let next = folded[root] { root = next }
            guard let entry = found[child] else { continue }
            found[root]?.pids.append(contentsOf: [child])
            found[root]?.residentBytes += entry.residentBytes
        }
        return found.values
            .filter { folded[$0.pid] == nil }
            .map { entry in var entry = entry; entry.pids.sort(); return entry }
            .sorted { $0.residentBytes != $1.residentBytes ? $0.residentBytes > $1.residentBytes : $0.pid < $1.pid }
    }

    private func role(of process: RunningProcess, tool: Tool?, isMCP: Bool) -> ProcessRole {
        if process.app != nil, tool != nil { return .app }
        if isMCP { return .mcpServer }
        if Self.serverWord(process) != nil { return .server }
        if let tool, let path = process.path, tool.apps.contains(where: { path.hasPrefix($0 + "/") }) { return .helper }
        return .session
    }

    /// Words that make a process a server: `ollama serve`, `codex app-server`, and the model
    /// runners a server starts, which fold into it.
    static let serverWords: Set<String> = ["serve", "server", "app-server", "daemon", "runner"]

    static func serverWord(_ process: RunningProcess) -> String? {
        process.arguments.dropFirst().map { $0.lowercased() }.first(where: serverWords.contains)
    }

    private func displayName(_ process: RunningProcess, tool: Tool?, role: ProcessRole, server: String?) -> String {
        if let app = process.app { return app.name }
        if role == .mcpServer, let server { return server }
        // The tool's own command, since a native install's file can be named after its version.
        let command = tool.flatMap { tool in process.commandNames.first(where: tool.match.commands.contains) }
            ?? (process.arguments.first ?? process.path).map { ($0 as NSString).lastPathComponent } ?? process.name
        // Only the word that made it a server, never another argument, which could be a flag's value.
        if role == .server, let word = Self.serverWord(process) {
            return "\(command) \(word)"
        }
        return command
    }

    /// What keeps a process running, and the nearest tool process above it, if any.
    private func attachment(
        of process: RunningProcess, byPID: [ProcessID: RunningProcess], found: [ProcessID: ToolProcess], launchItems: [LaunchItem]
    ) -> (Attachment, owner: ProcessID?) {
        if process.app != nil { return (.app, nil) }
        var seen: Set<ProcessID> = [process.pid]
        var current = process
        while current.parent > 1, let parent = byPID[current.parent], seen.insert(parent.pid).inserted {
            if let owner = found[parent.pid] {
                return (.parent(name: ownerName(owner)), parent.pid)
            }
            if parent.hasTerminal { return (.terminal, nil) }
            if let app = parent.app { return (.parent(name: app.name), nil) }
            current = parent
        }
        // Something launchd started directly is never in a terminal, even if it once was.
        if process.hasTerminal, process.parent > 1 { return (.terminal, nil) }
        if current.parent <= 1, let item = launchItems.first(where: { $0.runs(current) }) {
            return (.launchItem(label: item.label, scope: item.scope), nil)
        }
        // Only a process launchd took in has lost what started it. One whose parent is still
        // running belongs to that parent, like a server run by a process manager.
        if process.parent > 1 {
            guard let parent = byPID[process.parent] else { return (.parent(name: "another process"), nil) }
            return (.parent(name: parent.app?.name ?? parent.path.map { ($0 as NSString).lastPathComponent } ?? parent.name), nil)
        }
        return (.none, nil)
    }

    private func ownerName(_ entry: ToolProcess) -> String {
        if let id = entry.toolID, let tool = tools.first(where: { $0.id == id }) { return tool.name }
        return entry.name
    }

    /// Helpers go inside their app, and a wrapper like `npx` and the server it starts are one server.
    private func belongsInside(_ child: ToolProcess, _ parent: ToolProcess) -> Bool {
        if child.role == .mcpServer { return parent.role == .mcpServer }
        guard child.toolID == parent.toolID else { return false }
        return child.role == .helper || child.role == parent.role
    }
}
