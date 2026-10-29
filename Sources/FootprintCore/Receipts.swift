import Foundation

/// What changed on your Mac when a tool updated, installed itself, added a login item or went away.
public struct Receipt: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case updated, installed, changed, removed
    }

    public struct Change: Hashable, Codable, Sendable {
        public var path: String
        public var label: String
        public var before: Int64
        public var after: Int64

        public init(path: String, label: String, before: Int64, after: Int64) {
            self.path = path
            self.label = label
            self.before = before
            self.after = after
        }

        public var delta: Int64 { after - before }
    }

    public var id: UUID
    public var kind: Kind
    public var toolID: String
    public var toolName: String
    public var date: Date
    /// The check it's compared with.
    public var since: Date
    public var fromVersion: String?
    public var toVersion: String?
    public var bytesBefore: Int64
    public var bytesAfter: Int64
    /// Locations that grew or shrank by at least `Receipt.noticeable`, biggest change first.
    public var changes: [Change]
    public var itemsAdded: [LaunchItem]
    public var itemsRemoved: [LaunchItem]

    public init(
        id: UUID = UUID(), kind: Kind, toolID: String, toolName: String, date: Date, since: Date,
        fromVersion: String? = nil, toVersion: String? = nil, bytesBefore: Int64, bytesAfter: Int64,
        changes: [Change] = [], itemsAdded: [LaunchItem] = [], itemsRemoved: [LaunchItem] = []
    ) {
        self.id = id
        self.kind = kind
        self.toolID = toolID
        self.toolName = toolName
        self.date = date
        self.since = since
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.bytesBefore = bytesBefore
        self.bytesAfter = bytesAfter
        self.changes = changes
        self.itemsAdded = itemsAdded
        self.itemsRemoved = itemsRemoved
    }

    public var delta: Int64 { bytesAfter - bytesBefore }

    /// Smaller changes than this aren't listed, so a log growing by a few lines isn't news.
    public static let noticeable: Int64 = 1_000_000

    /// A receipt for what changed between two checks, or nil if nothing worth one did. Disk use
    /// changing on its own isn't worth one: tools write logs and caches all the time.
    public static func compare(_ before: ToolState?, _ after: ToolState, tool: Tool, since: Date, now: Date) -> Receipt? {
        // The first check is where everything starts from, not news.
        guard let before else { return nil }
        let kind: Kind
        if !before.isInstalled && after.isInstalled {
            kind = .installed
        } else if before.isInstalled && !after.isInstalled {
            kind = .removed
        } else if let old = before.version, let new = after.version, old != new {
            kind = .updated
        } else if Set(before.launchItems.map(\.id)) != Set(after.launchItems.map(\.id)) {
            kind = .changed
        } else {
            return nil
        }
        let changes = tool.locations.compactMap { location -> Change? in
            let old = before.usage[location.path]?.bytes ?? 0
            let new = after.usage[location.path]?.bytes ?? 0
            guard abs(new - old) >= noticeable else { return nil }
            return Change(path: location.path, label: location.label, before: old, after: new)
        }.sorted { abs($0.delta) > abs($1.delta) }
        let oldItems = Set(before.launchItems.map(\.id))
        let newItems = Set(after.launchItems.map(\.id))
        return Receipt(
            kind: kind, toolID: tool.id, toolName: tool.name, date: now, since: since,
            fromVersion: before.version, toVersion: after.version, bytesBefore: before.bytes, bytesAfter: after.bytes,
            changes: changes,
            itemsAdded: after.launchItems.filter { !oldItems.contains($0.id) },
            itemsRemoved: before.launchItems.filter { !newItems.contains($0.id) }
        )
    }

    /// Receipts for every tool between two checks.
    public static func compare(_ before: Footprint?, _ after: Footprint, tools: [Tool]) -> [Receipt] {
        guard let before else { return [] }
        return tools.compactMap { tool in
            guard let new = after.state(tool.id) else { return nil }
            // A tool added to the app since the last check has no state yet, which isn't an install.
            guard let old = before.state(tool.id) else { return nil }
            return compare(old, new, tool: tool, since: before.date, now: after.date)
        }
    }
}

/// The receipts so far and the last check, as saved between launches.
public struct History: Hashable, Codable, Sendable {
    public var receipts: [Receipt]
    public var last: Footprint?
    public var limit: Int

    public static let defaultLimit = 200

    public init(receipts: [Receipt] = [], last: Footprint? = nil, limit: Int = History.defaultLimit) {
        self.limit = max(1, limit)
        self.receipts = Array(receipts.sorted { $0.date > $1.date }.prefix(self.limit))
        self.last = last
    }

    /// Takes a new check, and returns the receipts it made, newest first.
    @discardableResult
    public mutating func record(_ footprint: Footprint, tools: [Tool]) -> [Receipt] {
        let footprint = Self.carryVersions(footprint, from: last)
        let new = Receipt.compare(last, footprint, tools: tools)
        last = footprint
        receipts.insert(contentsOf: new, at: 0)
        if receipts.count > limit { receipts.removeLast(receipts.count - limit) }
        return new
    }

    /// Fills in versions a check couldn't read from the one before. A tool whose version only
    /// shows while it runs keeps its last version while it's stopped, so an update made in between
    /// is still caught, and such a version never goes backward because an older copy is running.
    static func carryVersions(_ footprint: Footprint, from last: Footprint?) -> Footprint {
        guard let last else { return footprint }
        var footprint = footprint
        for index in footprint.tools.indices {
            let new = footprint.tools[index]
            guard let old = last.state(new.toolID), let known = old.version else { continue }
            // A tool with nothing left on disk is gone, whatever version it had.
            guard !new.usage.isEmpty || !new.launchItems.isEmpty || new.version != nil else { continue }
            if new.version == nil {
                footprint.tools[index].version = known
                footprint.tools[index].versionFromProcesses = old.versionFromProcesses
            } else if new.versionFromProcesses == true, let version = new.version, Versions.compare(version, known) == .orderedAscending {
                footprint.tools[index].version = known
            }
        }
        return footprint
    }

    private enum CodingKeys: String, CodingKey { case receipts, last }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            receipts: try container.decode([Receipt].self, forKey: .receipts),
            last: try container.decodeIfPresent(Footprint.self, forKey: .last)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(receipts, forKey: .receipts)
        try container.encodeIfPresent(last, forKey: .last)
    }
}

/// The history as it's saved to disk: versioned JSON, so a newer app's file is never misread.
public enum HistoryFile {
    public static let version = 1

    public enum ReadError: Error, Equatable {
        /// Written by a newer version of the app.
        case newerVersion(Int)
        /// A version number no app ever wrote.
        case unknownVersion(Int)
    }

    private struct Envelope: Codable {
        var version: Int
        var history: History
    }

    public static func encode(_ history: History) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Envelope(version: version, history: history))
    }

    public static func decode(_ data: Data) throws -> History {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        struct VersionOnly: Decodable { var version: Int }
        let found = try decoder.decode(VersionOnly.self, from: data).version
        guard found <= version else { throw ReadError.newerVersion(found) }
        guard found >= 1 else { throw ReadError.unknownVersion(found) }
        return try decoder.decode(Envelope.self, from: data).history
    }
}
