import Foundation
@testable import FootprintCore

enum Fixture {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    static func process(
        _ pid: ProcessID, parent: ProcessID = 1, name: String, path: String? = nil, arguments: [String]? = nil,
        memory: Int64 = 10_000_000, terminal: Bool = false, app: (String, String?)? = nil, started: Date? = nil
    ) -> RunningProcess {
        RunningProcess(
            pid: pid, parent: parent, name: name, path: path, arguments: arguments ?? [path ?? name],
            residentBytes: memory, started: started, hasTerminal: terminal, app: app.map { (name: $0.0, bundleID: $0.1) }
        )
    }

    /// The Terminal app and a shell in it, which processes started from a terminal sit under.
    static let terminalApp = process(400, name: "Terminal", path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", app: ("Terminal", "com.apple.Terminal"))
    static let login = process(401, parent: 400, name: "login", path: "/usr/bin/login", terminal: true)
    static let shell = process(402, parent: 401, name: "zsh", path: "/bin/zsh", terminal: true)

    static func item(_ label: String, program: String? = nil, scope: LaunchItem.Scope = .user, runsAtLoad: Bool = true, keepsAlive: Bool = false) -> LaunchItem {
        let folder = scope == .user ? "/Users/someone/Library/LaunchAgents" : scope == .allUsers ? "/Library/LaunchAgents" : "/Library/LaunchDaemons"
        return LaunchItem(
            label: label, plistPath: "\(folder)/\(label).plist", scope: scope, program: program,
            arguments: program.map { [$0] } ?? [], runsAtLoad: runsAtLoad, keepsAlive: keepsAlive
        )
    }

    static func usage(_ bytes: Int64) -> Usage {
        Usage(bytes: bytes, files: 1)
    }

    /// A launchd property list, as the system would write it.
    static func plist(_ values: [String: Any]) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
    }

    /// The buffer `KERN_PROCARGS2` fills in, environment and all.
    static func procargs(path: String, arguments: [String], environment: [String] = [], padding: Int = 3) -> [UInt8] {
        var count = Int32(arguments.count)
        var bytes = withUnsafeBytes(of: &count) { Array($0) }
        bytes += Array(path.utf8) + [0]
        bytes += [UInt8](repeating: 0, count: padding)
        for argument in arguments + environment {
            bytes += Array(argument.utf8) + [0]
        }
        return bytes
    }
}

/// A folder that's deleted when the test process ends.
func scratchFolder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("FootprintCoreTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func write(_ bytes: Int, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    // Random bytes, so the file system can't compress them away.
    var generator = SystemRandomNumberGenerator()
    let data = Data((0..<bytes).map { _ in UInt8.random(in: 0...255, using: &generator) })
    try data.write(to: url)
}
