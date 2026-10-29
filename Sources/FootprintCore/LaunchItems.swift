import Foundation

/// A login item or background service installed with launchd, from its property list.
public struct LaunchItem: Hashable, Codable, Sendable, Identifiable {
    public enum Scope: String, Codable, Sendable {
        /// `~/Library/LaunchAgents`: runs for you.
        case user
        /// `/Library/LaunchAgents`: runs for everyone who logs in.
        case allUsers
        /// `/Library/LaunchDaemons`: runs as the system, even before anyone logs in.
        case system
    }

    public var label: String
    public var plistPath: String
    public var scope: Scope
    /// The executable it runs.
    public var program: String?
    /// Only kept to recognize what it runs; never shown.
    public var arguments: [String]
    public var runsAtLoad: Bool
    /// Started again whenever it quits.
    public var keepsAlive: Bool
    /// Seconds between runs, for one that runs on a timer.
    public var interval: Int?
    /// When its property list was last written, which is usually when it was installed or updated.
    public var modified: Date?

    public var id: String { plistPath }

    public init(
        label: String, plistPath: String, scope: Scope, program: String? = nil, arguments: [String] = [],
        runsAtLoad: Bool = false, keepsAlive: Bool = false, interval: Int? = nil, modified: Date? = nil
    ) {
        self.label = label
        self.plistPath = plistPath
        self.scope = scope
        self.program = program
        self.arguments = arguments
        self.runsAtLoad = runsAtLoad
        self.keepsAlive = keepsAlive
        self.interval = interval
        self.modified = modified
    }

    /// Reads a launchd property list. Returns nil for anything that isn't one.
    public static func parse(_ data: Data, path: String, scope: Scope, modified: Date? = nil) -> LaunchItem? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = plist["Label"] as? String, !label.isEmpty
        else { return nil }
        let arguments = (plist["ProgramArguments"] as? [Any])?.compactMap { $0 as? String } ?? []
        let program = (plist["Program"] as? String) ?? arguments.first
        let keepAlive: Bool
        switch plist["KeepAlive"] {
        case let flag as Bool: keepAlive = flag
        // Conditions like "restart only after a crash" still bring it back.
        case let conditions as [String: Any]: keepAlive = !conditions.isEmpty
        default: keepAlive = false
        }
        return LaunchItem(
            label: label, plistPath: path, scope: scope, program: program, arguments: arguments,
            runsAtLoad: (plist["RunAtLoad"] as? Bool) ?? false, keepsAlive: keepAlive,
            interval: plist["StartInterval"] as? Int, modified: modified
        )
    }

    /// Whether this is the item that started a process.
    public func runs(_ process: RunningProcess) -> Bool {
        guard let program, let path = process.path else { return false }
        if program == path { return true }
        // A symlink like /opt/homebrew/bin/ollama runs the real file somewhere else.
        return RunningProcess.command(program) == RunningProcess.command(path)
            && arguments.dropFirst() == process.arguments.dropFirst()
    }

    // Arguments are left out of the saved file, like everywhere else.
    private enum CodingKeys: String, CodingKey {
        case label, plistPath, scope, program, runsAtLoad, keepsAlive, interval, modified
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        plistPath = try container.decode(String.self, forKey: .plistPath)
        scope = try container.decode(Scope.self, forKey: .scope)
        program = try container.decodeIfPresent(String.self, forKey: .program)
        arguments = []
        runsAtLoad = try container.decode(Bool.self, forKey: .runsAtLoad)
        keepsAlive = try container.decode(Bool.self, forKey: .keepsAlive)
        interval = try container.decodeIfPresent(Int.self, forKey: .interval)
        modified = try container.decodeIfPresent(Date.self, forKey: .modified)
    }

    public static func == (a: LaunchItem, b: LaunchItem) -> Bool {
        a.label == b.label && a.plistPath == b.plistPath && a.scope == b.scope && a.program == b.program
            && a.runsAtLoad == b.runsAtLoad && a.keepsAlive == b.keepsAlive && a.interval == b.interval
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(plistPath)
        hasher.combine(label)
    }
}
