import Foundation

/// How much disk a folder or file takes.
public struct Usage: Hashable, Codable, Sendable {
    public struct Part: Hashable, Codable, Sendable {
        public var name: String
        public var bytes: Int64

        public init(name: String, bytes: Int64) {
            self.name = name
            self.bytes = bytes
        }
    }

    /// Space it takes on disk, which can be less than the files' sizes for sparse files like disk images.
    public var bytes: Int64
    public var files: Int
    /// The biggest things directly inside it, biggest first.
    public var parts: [Part]
    /// When anything inside it last changed.
    public var modified: Date?

    public init(bytes: Int64, files: Int, parts: [Part] = [], modified: Date? = nil) {
        self.bytes = bytes
        self.files = files
        self.parts = parts
        self.modified = modified
    }

    public static let partLimit = 4
}

/// Measures folders without following symbolic links, and counts a file with several hard links
/// once. Only sizes and dates are read, never what's in the files.
public struct DiskScanner: Sendable {
    public init() {}

    /// The usage of a file or folder, or nil if it isn't there or can't be read.
    /// `isCancelled` is checked as it goes, so a long scan can stop early.
    public func usage(of url: URL, isCancelled: () -> Bool = { false }) -> Usage? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        if info.st_mode & S_IFMT != S_IFDIR {
            return Usage(bytes: Self.allocated(info), files: 1, modified: Self.date(info.st_mtimespec))
        }

        var total: Int64 = 0
        var files = 0
        var newest = Self.date(info.st_mtimespec)
        var parts: [String: Int64] = [:]
        var seenLinks: Set<[UInt64]> = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        else { return nil }
        let rootDepth = url.standardizedFileURL.pathComponents.count
        for case let item as URL in walker {
            if isCancelled() { return nil }
            var entry = stat()
            guard lstat(item.path, &entry) == 0 else { continue }
            if entry.st_mode & S_IFMT != S_IFDIR, entry.st_nlink > 1 {
                guard seenLinks.insert([UInt64(entry.st_dev), entry.st_ino]).inserted else { continue }
            }
            let bytes = Self.allocated(entry)
            total += bytes
            if entry.st_mode & S_IFMT == S_IFREG { files += 1 }
            if let date = Self.date(entry.st_mtimespec), date > (newest ?? .distantPast) { newest = date }
            let components = item.standardizedFileURL.pathComponents
            if components.count > rootDepth {
                parts[components[rootDepth], default: 0] += bytes
            }
        }
        let biggest = parts.map { Usage.Part(name: $0.key, bytes: $0.value) }
            .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.name < $1.name }
            .prefix(Usage.partLimit)
        return Usage(bytes: total, files: files, parts: Array(biggest), modified: newest)
    }

    private static func allocated(_ info: stat) -> Int64 {
        Int64(info.st_blocks) * 512
    }

    private static func date(_ time: timespec) -> Date? {
        guard time.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1e9)
    }
}
