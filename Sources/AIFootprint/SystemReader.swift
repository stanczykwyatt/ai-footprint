import AppKit
import Darwin
import FootprintCore

/// Where the app's information comes from. The app reads the real Mac; tests use a made-up one.
protocol SystemReading: Sendable {
    /// Your processes, right now.
    @MainActor func processes() -> [RunningProcess]
    /// Sizes, versions and login items. Slow for big folders, so it runs off the main thread.
    func readings(tools: [Tool], processes: [RunningProcess], isCancelled: @Sendable () -> Bool) -> Readings
}

/// Reads the real Mac, within what the sandbox allows: sizes and dates in the tools' folders, app
/// versions, login item files, and your own processes. Apart from asking macOS for app icons, this
/// is the only file in the app that opens a file it didn't write, and it only opens property lists.
/// A process's environment arrives with its command line and is dropped unread.
struct SystemReader: SystemReading {
    let home: String
    /// Login item folders outside your home folder. Tests leave them out.
    var sharedLaunchFolders = Tool.sharedLaunchFolders

    // MARK: Processes

    @MainActor
    func processes() -> [RunningProcess] {
        let apps = Dictionary(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy != .prohibited }
                .map { ($0.processIdentifier, (name: $0.localizedName ?? "", bundleID: $0.bundleIdentifier)) },
            uniquingKeysWith: { first, _ in first }
        )
        let me = getpid()
        let uid = getuid()
        return Self.allProcesses().compactMap { info -> RunningProcess? in
            let pid = info.kp_proc.p_pid
            guard pid > 0, pid != me, info.kp_eproc.e_ucred.cr_uid == uid else { return nil }
            let name = withUnsafeBytes(of: info.kp_proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let parsed = Self.arguments(pid)
            let start = info.kp_proc.p_un.__p_starttime
            return RunningProcess(
                pid: pid, parent: info.kp_eproc.e_ppid, name: name, path: Self.path(pid) ?? parsed?.path,
                arguments: parsed?.arguments ?? [], residentBytes: Self.residentBytes(pid),
                started: start.tv_sec > 0 ? Date(timeIntervalSince1970: TimeInterval(start.tv_sec)) : nil,
                hasTerminal: info.kp_eproc.e_tdev != -1, app: apps[pid]
            )
        }
    }

    /// Every process, from `sysctl`. The sandbox allows this; `proc_listpids` it doesn't.
    private static func allProcesses() -> [kinfo_proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
            // Room for processes that start in between.
            var list = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 32)
            size = list.count * MemoryLayout<kinfo_proc>.stride
            if sysctl(&mib, 3, &list, &size, nil, 0) == 0 {
                return Array(list.prefix(size / MemoryLayout<kinfo_proc>.stride))
            }
            guard errno == ENOMEM else { return [] }
        }
        return []
    }

    private static func path(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The command line, without the environment that follows it.
    private static func arguments(_ pid: pid_t) -> (path: String, arguments: [String])? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return ProcessArguments.parse(Array(buffer.prefix(size)))
    }

    private static func residentBytes(_ pid: pid_t) -> Int64 {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return 0 }
        return Int64(info.pti_resident_size)
    }

    // MARK: Folders, versions and login items

    func readings(tools: [Tool], processes: [RunningProcess], isCancelled: @Sendable () -> Bool) -> Readings {
        let scanner = DiskScanner()
        let homeURL = URL(fileURLWithPath: home, isDirectory: true)
        var readings = Readings()
        for tool in tools {
            for app in tool.apps {
                if let version = Self.appVersion(app) { readings.appVersions[app] = version }
            }
            for folder in tool.versionFolders {
                if let names = try? FileManager.default.contentsOfDirectory(atPath: homeURL.appendingPathComponent(folder).path) {
                    readings.folderEntries[folder] = names
                }
            }
            for location in tool.locations {
                let usage = scanner.usage(of: homeURL.appendingPathComponent(location.path), isCancelled: isCancelled)
                if isCancelled() {
                    readings.isComplete = false
                    return readings
                }
                if let usage { readings.usage[location.path] = usage }
            }
        }
        let classifier = ProcessClassifier(tools: tools)
        for process in processes {
            if let tool = classifier.tool(for: process), let path = process.path {
                readings.processPaths[tool.id, default: []].append(path)
            }
        }
        let folders = Tool.launchAgentFolders.map { (homeURL.appendingPathComponent($0.path).path, $0.scope) } + sharedLaunchFolders
        readings.launchItems = folders.flatMap { Self.launchItems(in: $0.0, scope: $0.1) }
        return readings
    }

    /// Read straight from Info.plist each time: `Bundle` would keep the version from before an update.
    private static func appVersion(_ path: String) -> String? {
        let url = URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count < 4_000_000,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String)
    }

    private static func launchItems(in folder: String, scope: LaunchItem.Scope) -> [LaunchItem] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return [] }
        return names.filter { $0.hasSuffix(".plist") }.sorted().compactMap { name in
            let path = (folder as NSString).appendingPathComponent(name)
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            // A launchd property list is a few kilobytes; anything huge isn't one.
            guard (attributes?[.size] as? Int ?? 0) < 1_000_000, attributes?[.type] as? FileAttributeType == .typeRegular,
                  let data = FileManager.default.contents(atPath: path)
            else { return nil }
            return LaunchItem.parse(data, path: path, scope: scope, modified: attributes?[.modificationDate] as? Date)
        }
    }
}
