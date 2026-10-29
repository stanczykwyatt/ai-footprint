import FootprintCore
import Foundation

/// Saves the receipts and the last check as JSON in the app's sandbox container. Nothing is ever
/// sent anywhere.
struct HistoryStore {
    let url: URL

    init(url: URL = HistoryStore.defaultURL) {
        self.url = url
    }

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AI Footprint", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    /// The saved history, or an empty one. A file that can't be read, whether damaged or written by
    /// a newer version, is moved aside rather than overwritten, so nothing is lost.
    func load() -> History {
        guard FileManager.default.fileExists(atPath: url.path) else { return History() }
        guard let data = try? Data(contentsOf: url) else {
            // There but unreadable: keep it rather than writing over it.
            setAside()
            return History()
        }
        do {
            return try HistoryFile.decode(data)
        } catch {
            setAside()
            return History()
        }
    }

    func save(_ history: History) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try HistoryFile.encode(history).write(to: url, options: .atomic)
    }

    private func setAside() {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let unique = UUID().uuidString.prefix(8)
        let aside = url.deletingLastPathComponent().appendingPathComponent("history-unreadable-\(stamp)-\(unique).json")
        try? FileManager.default.moveItem(at: url, to: aside)
    }
}
