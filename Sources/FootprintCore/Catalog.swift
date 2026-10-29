import Foundation

/// A folder or file a tool keeps in your home folder.
public struct Location: Hashable, Sendable, Codable {
    /// Relative to your home folder, with no leading slash: `.ollama/models`.
    public let path: String
    /// What's in it, in a few words: "Models".
    public let label: String
    public let isFile: Bool

    public init(_ path: String, _ label: String, isFile: Bool = false) {
        self.path = path
        self.label = label
        self.isFile = isFile
    }

    /// How it's shown: `~/.ollama/models`.
    public var displayPath: String { "~/" + path }
}

/// How to recognize a tool's processes and login items.
public struct ProcessMatch: Hashable, Sendable {
    /// Exact command names, like `codex`, matched against the executable and, for scripts run by
    /// Node or Python, the script.
    public var commands: [String]
    /// Pieces of an executable's path, like `/Ollama.app/`.
    public var pathContains: [String]
    /// Pieces of an argument, like `@openai/codex`, for tools installed as packages.
    public var argumentContains: [String]
    /// Starts of a login item's label, like `com.ollama`.
    public var labelPrefixes: [String]

    public init(commands: [String] = [], pathContains: [String] = [], argumentContains: [String] = [], labelPrefixes: [String] = []) {
        self.commands = commands
        self.pathContains = pathContains
        self.argumentContains = argumentContains
        self.labelPrefixes = labelPrefixes
    }
}

/// An AI tool the app knows how to find.
public struct Tool: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let locations: [Location]
    /// App bundles whose version is the tool's version, like `/Applications/Ollama.app`.
    public let apps: [String]
    /// Home-relative folders that hold one subfolder per installed version, like `2.1.4`.
    public let versionFolders: [String]
    public let match: ProcessMatch
    /// An SF Symbol for when the tool has no app icon.
    public let symbol: String

    public init(
        id: String, name: String, locations: [Location], apps: [String] = [], versionFolders: [String] = [],
        match: ProcessMatch, symbol: String
    ) {
        self.id = id
        self.name = name
        self.locations = locations
        self.apps = apps
        self.versionFolders = versionFolders
        self.match = match
        self.symbol = symbol
    }
}

extension Tool {
    /// Every tool the app looks for. Each location here is listed in the app's entitlements as
    /// read-only, and nothing else in your home folder is: a tool's settings, sign-in tokens and
    /// keys are left out on purpose, so the app can't open them. A test checks the two lists match.
    public static let all: [Tool] = [claudeCode, claudeApp, codex, ollama, lmStudio, huggingFace]

    public static let claudeCode = Tool(
        id: "claude-code", name: "Claude Code",
        locations: [
            Location(".claude/projects", "Session transcripts"),
            Location(".claude/file-history", "File checkpoints"),
            Location(".claude/shell-snapshots", "Shell snapshots"),
            Location(".claude/todos", "To-do lists"),
            Location(".claude/debug", "Debug logs"),
            Location(".claude/plugins", "Plugins"),
            Location(".claude/telemetry", "Telemetry queue"),
            Location(".local/share/claude", "Installed versions"),
            Location(".local/state/claude", "State"),
            Location("Library/Caches/claude-cli-nodejs", "Cache and MCP logs"),
        ],
        versionFolders: [".local/share/claude/versions"],
        match: ProcessMatch(
            commands: ["claude"],
            pathContains: ["/.local/share/claude/", "/Application Support/Claude/claude-code/"],
            argumentContains: ["@anthropic-ai/claude-code"]
        ),
        symbol: "terminal"
    )

    public static let claudeApp = Tool(
        id: "claude-app", name: "Claude app",
        locations: [
            Location("Library/Application Support/Claude/vm_bundles", "Virtual machine"),
            Location("Library/Application Support/Claude/claude-code", "Built-in Claude Code"),
            Location("Library/Application Support/Claude/claude-code-vm", "Claude Code for the virtual machine"),
            Location("Library/Application Support/Claude/Cache", "Web cache"),
            Location("Library/Application Support/Claude/Code Cache", "Script cache"),
            Location("Library/Logs/Claude", "Logs and MCP logs"),
        ],
        apps: ["/Applications/Claude.app"],
        match: ProcessMatch(pathContains: ["/Applications/Claude.app/"], labelPrefixes: ["com.anthropic"]),
        symbol: "sparkle"
    )

    public static let codex = Tool(
        id: "codex", name: "Codex",
        locations: [
            Location(".codex/sessions", "Session transcripts"),
            Location(".codex/archived_sessions", "Archived sessions"),
            Location(".codex/log", "Logs"),
            Location(".codex/history.jsonl", "Prompt history", isFile: true),
        ],
        apps: ["/Applications/Codex.app"],
        match: ProcessMatch(
            commands: ["codex"],
            pathContains: ["/Codex.app/"],
            argumentContains: ["@openai/codex"],
            labelPrefixes: ["com.openai.codex"]
        ),
        symbol: "chevron.left.forwardslash.chevron.right"
    )

    public static let ollama = Tool(
        id: "ollama", name: "Ollama",
        locations: [
            Location(".ollama/models", "Models"),
            Location(".ollama/logs", "Logs"),
        ],
        apps: ["/Applications/Ollama.app"],
        match: ProcessMatch(
            commands: ["ollama"],
            pathContains: ["/Ollama.app/"],
            labelPrefixes: ["com.ollama", "homebrew.mxcl.ollama"]
        ),
        symbol: "cube"
    )

    public static let lmStudio = Tool(
        id: "lm-studio", name: "LM Studio",
        locations: [
            Location(".lmstudio/models", "Models"),
            Location(".lmstudio/extensions", "Runtimes"),
            Location(".lmstudio/server-logs", "Server logs"),
            Location(".cache/lm-studio", "Older models folder"),
        ],
        apps: ["/Applications/LM Studio.app"],
        match: ProcessMatch(
            commands: ["lms", "llmster"],
            pathContains: ["/LM Studio.app/", "/.lmstudio/"],
            labelPrefixes: ["ai.elementlabs"]
        ),
        symbol: "cpu"
    )

    public static let huggingFace = Tool(
        id: "hugging-face", name: "Hugging Face",
        locations: [
            Location(".cache/huggingface/hub", "Downloaded models"),
            Location(".cache/huggingface/datasets", "Datasets"),
            Location(".cache/huggingface/xet", "Download cache"),
            Location(".cache/huggingface/assets", "Assets"),
        ],
        match: ProcessMatch(commands: ["hf", "huggingface-cli"]),
        symbol: "shippingbox"
    )

    /// Where login items live. Read-only, like the tools' folders.
    public static let launchAgentFolders: [(path: String, scope: LaunchItem.Scope)] = [
        ("Library/LaunchAgents", .user),
    ]

    /// Login items installed for every user, readable by any app.
    public static let sharedLaunchFolders: [(path: String, scope: LaunchItem.Scope)] = [
        ("/Library/LaunchAgents", .allUsers),
        ("/Library/LaunchDaemons", .system),
    ]
}
