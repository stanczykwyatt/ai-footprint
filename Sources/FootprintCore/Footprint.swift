import Foundation

/// Version numbers, from app bundles, version folders and install paths.
public enum Versions {
    /// Whether a name looks like a version: `2.1.4`, `0.52.0-beta.1`, `v1.3`.
    public static func isVersion(_ name: String) -> Bool {
        let trimmed = name.hasPrefix("v") ? String(name.dropFirst()) : name
        guard let first = trimmed.first, first.isNumber, trimmed.contains(".") else { return false }
        return trimmed.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "+" }
    }

    /// Compares versions number by number, so `2.10` comes after `2.9`. A prerelease comes before its release.
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        func split(_ version: String) -> (numbers: [Int], prerelease: String?) {
            let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
            let main = trimmed.split(separator: "+", maxSplits: 1).first.map(String.init) ?? trimmed
            let pieces = main.split(separator: "-", maxSplits: 1).map(String.init)
            let numbers = (pieces.first ?? "").split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
            return (numbers, pieces.count > 1 ? pieces[1] : nil)
        }
        let (left, right) = (split(a), split(b))
        for index in 0..<max(left.numbers.count, right.numbers.count) {
            let x = index < left.numbers.count ? left.numbers[index] : 0
            let y = index < right.numbers.count ? right.numbers[index] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        switch (left.prerelease, right.prerelease) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        case let (x?, y?): return x.compare(y, options: .numeric)
        }
    }

    /// The newest of the names that look like versions.
    public static func newest(_ names: [String]) -> String? {
        names.filter(isVersion).max { compare($0, $1) == .orderedAscending }
    }

    /// A version named in an install path, like Homebrew's `/Cellar/ollama/0.12.3/bin/ollama`,
    /// `/versions/2.1.4` or the Claude app's `/claude-code/2.1.4/`.
    public static func fromPath(_ path: String) -> String? {
        let components = path.split(separator: "/").map(String.init)
        for (index, component) in components.enumerated() where index > 0 {
            let before = components[index - 1]
            if ["versions", "Versions", "claude-code"].contains(before) || (index > 1 && components[index - 2] == "Cellar") {
                if isVersion(component) { return component }
            }
        }
        return nil
    }
}

/// What a tool had on this Mac at one check. Processes come and go, so they're not part of it.
public struct ToolState: Hashable, Codable, Sendable {
    public var toolID: String
    public var version: String?
    /// Set when the version was only read from a running process's path, which depends on what's
    /// running, so it's not trusted to go backward.
    public var versionFromProcesses: Bool?
    /// By location path. Locations that aren't there are left out.
    public var usage: [String: Usage]
    public var launchItems: [LaunchItem]

    public init(toolID: String, version: String? = nil, usage: [String: Usage] = [:], launchItems: [LaunchItem] = []) {
        self.toolID = toolID
        self.version = version
        self.usage = usage
        self.launchItems = launchItems
    }

    public var bytes: Int64 { usage.values.reduce(0) { $0 + $1.bytes } }

    public var isInstalled: Bool { version != nil || !usage.isEmpty || !launchItems.isEmpty }
}

/// Everything found at one check.
public struct Footprint: Hashable, Codable, Sendable {
    public var date: Date
    public var tools: [ToolState]

    public init(date: Date, tools: [ToolState]) {
        self.date = date
        self.tools = tools
    }

    public func state(_ toolID: String) -> ToolState? {
        tools.first { $0.toolID == toolID }
    }

    public var bytes: Int64 { tools.reduce(0) { $0 + $1.bytes } }
}

/// What the app read from the system, before it's sorted into tools.
public struct Readings: Sendable {
    /// Version from each app bundle's Info.plist, by bundle path.
    public var appVersions: [String: String]
    /// Names inside each version folder, by home-relative path.
    public var folderEntries: [String: [String]]
    /// Usage of each location that's there, by home-relative path.
    public var usage: [String: Usage]
    public var launchItems: [LaunchItem]
    /// Executable paths of the tools' running processes, which can name a version.
    public var processPaths: [String: [String]]
    /// False when the reading stopped early. A partial reading is never recorded, since missing
    /// folders would look like a tool being removed.
    public var isComplete = true

    public init(
        appVersions: [String: String] = [:], folderEntries: [String: [String]] = [:], usage: [String: Usage] = [:],
        launchItems: [LaunchItem] = [], processPaths: [String: [String]] = [:]
    ) {
        self.appVersions = appVersions
        self.folderEntries = folderEntries
        self.usage = usage
        self.launchItems = launchItems
        self.processPaths = processPaths
    }

    /// Sorts the readings into one state per tool.
    public func footprint(tools: [Tool], at date: Date) -> Footprint {
        let classifier = ProcessClassifier(tools: tools)
        var items: [String: [LaunchItem]] = [:]
        for item in launchItems {
            if let tool = classifier.tool(for: item) { items[tool.id, default: []].append(item) }
        }
        return Footprint(date: date, tools: tools.map { tool in
            var state = ToolState(
                toolID: tool.id, version: version(of: tool),
                usage: usage.filter { path, _ in tool.locations.contains { $0.path == path } },
                launchItems: (items[tool.id] ?? []).sorted { $0.label < $1.label }
            )
            if state.version != nil, installedVersion(of: tool) == nil { state.versionFromProcesses = true }
            return state
        })
    }

    /// From the app bundle first, then the newest version folder, then a running process's path.
    func version(of tool: Tool) -> String? {
        installedVersion(of: tool) ?? Versions.newest((processPaths[tool.id] ?? []).compactMap(Versions.fromPath))
    }

    /// The version from what's installed, which doesn't depend on what's running.
    func installedVersion(of tool: Tool) -> String? {
        for app in tool.apps {
            if let version = appVersions[app] { return version }
        }
        return Versions.newest(tool.versionFolders.flatMap { folderEntries[$0] ?? [] })
    }
}
