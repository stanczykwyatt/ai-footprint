import Foundation

/// Every piece of wording shown in the menu and window, in one place so it reads the same everywhere.
public enum Describe {
    // MARK: Sizes

    /// Disk and memory sizes in the units Finder uses: "512 KB", "4.2 GB", "118 GB".
    public static func bytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "Zero KB" }
        let units = ["KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes) / 1000
        var unit = 0
        while value >= 999.5, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        if unit == 0 { return "\(max(1, Int(value.rounded()))) KB" }
        let rounded = (value * 10).rounded() / 10
        if rounded < 10 {
            return rounded == rounded.rounded() ? "\(Int(rounded)) \(units[unit])" : String(format: "%.1f %@", rounded, units[unit])
        }
        return "\(Int(value.rounded())) \(units[unit])"
    }

    /// A change in size: "+1.2 GB", "−340 MB", "no change".
    public static func delta(_ bytes: Int64) -> String {
        if bytes == 0 { return "no change" }
        return (bytes > 0 ? "+" : "−") + self.bytes(abs(bytes))
    }

    public static func count(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(count) \(count == 1 ? singular : (plural ?? singular + "s"))"
    }

    // MARK: Times

    /// When something happened, relative to now: "just now", "5 min ago", "yesterday at 3:41 PM".
    public static func relative(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if let recent = recent(date, now: now) { return recent }
        let parts = DateParts(date, now: now, calendar: calendar, locale: locale)
        if parts.isToday { return "at \(parts.time)" }
        if parts.isYesterday { return "yesterday at \(parts.time)" }
        return "\(parts.day) at \(parts.time)"
    }

    /// The same, with a capital letter for the start of a line: "Yesterday at 3:41 PM".
    public static func relativeCapitalized(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let text = relative(date, now: now, calendar: calendar, locale: locale)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private static func recent(_ date: Date, now: Date) -> String? {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 10 { return "just now" }
        if elapsed < 60 { return "\(Int(elapsed)) s ago" }
        if elapsed < 3600 { return "\(Int(elapsed / 60)) min ago" }
        return nil
    }

    /// How long something has been running: "4 min", "3 h", "2 days".
    public static func age(_ seconds: TimeInterval) -> String {
        let seconds = max(0, seconds)
        if seconds < 60 { return "under a minute" }
        if seconds < 3600 { return count(Int(seconds / 60), "min", "min") }
        if seconds < 86_400 { return count(Int(seconds / 3600), "h", "h") }
        return count(Int(seconds / 86_400), "day")
    }

    private struct DateParts {
        var time: String
        var day: String
        var isToday: Bool
        var isYesterday: Bool

        init(_ date: Date, now: Date, calendar: Calendar, locale: Locale) {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            time = formatter.string(from: date)
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "MMMdyyyy")
            day = formatter.string(from: date)
            isToday = calendar.isDate(date, inSameDayAs: now)
            isYesterday = calendar.date(byAdding: .day, value: -1, to: now).map { calendar.isDate(date, inSameDayAs: $0) } ?? false
        }
    }

    // MARK: Paths

    /// A path with your home folder shown as `~`, so your username isn't in what you copy.
    public static func path(_ path: String, home: String?) -> String {
        guard let home, !home.isEmpty else { return path }
        let base = home.hasSuffix("/") ? String(home.dropLast()) : home
        if path == base { return "~" }
        if path.hasPrefix(base + "/") { return "~" + path.dropFirst(base.count) }
        return path
    }

    // MARK: Tools

    /// One line about a tool: "11.9 GB · 3 processes · 1 login item".
    public static func summary(bytes: Int64, processes: Int, launchItems: Int) -> String {
        var parts = [self.bytes(bytes)]
        if processes > 0 { parts.append(count(processes, "process", "processes")) }
        if launchItems > 0 { parts.append(count(launchItems, "login item")) }
        return parts.joined(separator: " · ")
    }

    public static func name(_ tool: Tool, version: String?) -> String {
        version.map { "\(tool.name) \($0)" } ?? tool.name
    }

    /// What a location holds, for a folder whose biggest part is worth naming: "Models: 8.4 GB".
    public static func location(_ location: Location, usage: Usage) -> String {
        "\(location.label): \(bytes(usage.bytes))"
    }

    // MARK: Processes

    /// What a process is: "App", "Background server", "MCP server".
    public static func role(_ process: ToolProcess) -> String {
        switch process.role {
        case .app: process.helpers > 0 ? "App, with \(count(process.helpers, "helper"))" : "App"
        case .helper: "Helper"
        case .server: "Server"
        case .session: "Session"
        case .mcpServer: "MCP server"
        }
    }

    /// What keeps it running: "In a terminal", "Started by Claude Code", "Left running: its app has quit".
    public static func attachment(_ process: ToolProcess) -> String {
        switch process.attachment {
        case .app: "Open as an app"
        case .terminal: "In a terminal"
        case .launchItem(let label, _): "Started by the login item \(label)"
        case .parent(let name): "Started by \(name)"
        case .none: process.role == .mcpServer ? "Orphaned: the app that started it has quit" : "Left running on its own"
        }
    }

    /// Two short lines for a menu: what it is, then how much memory and how long it's run.
    public static func processLine(_ process: ToolProcess, now: Date) -> String {
        var parts = [role(process), "\(bytes(process.residentBytes)) memory"]
        if let started = process.started { parts.append("running \(age(now.timeIntervalSince(started)))") }
        return parts.joined(separator: " · ")
    }

    // MARK: Login items

    /// When a login item runs: "Starts at login, and again if it quits".
    public static func schedule(_ item: LaunchItem) -> String {
        var parts: [String] = []
        if item.runsAtLoad { parts.append(item.scope == .system ? "Starts with your Mac" : "Starts at login") }
        if item.keepsAlive { parts.append(parts.isEmpty ? "Restarts whenever it quits" : "and again if it quits") }
        if let interval = item.interval, interval > 0 {
            parts.append((parts.isEmpty ? "Runs every " : "and every ") + every(interval))
        }
        if parts.isEmpty { return "Starts when something asks for it" }
        return parts.joined(separator: ", ")
    }

    private static func every(_ seconds: Int) -> String {
        if seconds % 86_400 == 0 { return seconds == 86_400 ? "day" : "\(seconds / 86_400) days" }
        if seconds % 3600 == 0 { return seconds == 3600 ? "hour" : "\(seconds / 3600) hours" }
        if seconds % 60 == 0 { return seconds == 60 ? "minute" : "\(seconds / 60) minutes" }
        return "\(seconds) seconds"
    }

    public static func scope(_ scope: LaunchItem.Scope) -> String {
        switch scope {
        case .user: "For you"
        case .allUsers: "For everyone who logs in"
        case .system: "For the whole Mac, as the system"
        }
    }

    // MARK: Stopping

    /// The Terminal command that stops a process, for you to read and paste. The app can't stop
    /// anything itself: the sandbox doesn't let it.
    public static func stopCommand(_ process: ToolProcess, uid: UInt32) -> String {
        switch process.attachment {
        case .launchItem(let label, let scope):
            return stopCommand(LaunchItem(label: label, plistPath: "", scope: scope), uid: uid)
        case .app:
            // A bundle ID only ever has letters, digits, dots and hyphens, so one with anything
            // else can't be trusted inside the script.
            if let bundleID = process.bundleID, !bundleID.isEmpty,
               bundleID.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "." || $0 == "-" }) {
                return "osascript -e \(shellQuote("quit app id \"\(bundleID)\""))"
            }
        case .terminal, .parent, .none:
            break
        }
        return "kill " + process.pids.map(String.init).joined(separator: " ")
    }

    /// The Terminal command that stops a login item until you next log in.
    public static func stopCommand(_ item: LaunchItem, uid: UInt32) -> String {
        switch item.scope {
        case .user, .allUsers: "launchctl bootout gui/\(uid)/\(shellQuote(item.label))"
        case .system: "sudo launchctl bootout system/\(shellQuote(item.label))"
        }
    }

    /// What the stop command does, in words.
    public static func stopNote(_ process: ToolProcess) -> String {
        switch process.attachment {
        case .launchItem(_, .system): "Stops it and its login item until your Mac restarts."
        case .launchItem: "Stops it and its login item until you next log in."
        case .app where stopCommand(process, uid: 0).hasPrefix("osascript"): "Quits the app, as if you chose Quit from its menu."
        case .app: process.helpers > 0 ? "Asks it and its helpers to quit." : "Asks it to quit."
        case .terminal, .parent, .none:
            process.helpers > 0 ? "Asks it and its helpers to quit." : "Asks it to quit."
        }
    }

    /// What stopping a login item does, and how to keep it from starting again.
    public static func stopNote(_ item: LaunchItem) -> String {
        let until = item.scope == .system ? "until your Mac restarts" : "until you next log in"
        return "Stops it \(until). To keep it from starting, turn it off in System Settings → General → Login Items & Extensions, or remove its file."
    }

    /// Quotes text for the shell when it needs it. Control characters are written out as `\xHH`,
    /// so a label can't hide part of the command when it's shown or pasted.
    public static func shellQuote(_ text: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/@:+=,")
        if !text.isEmpty, text.unicodeScalars.allSatisfy(safe.contains) { return text }
        if text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            var escaped = ""
            for scalar in text.unicodeScalars {
                switch scalar {
                case "\\": escaped += "\\\\"
                case "'": escaped += "\\'"
                case _ where CharacterSet.controlCharacters.contains(scalar) && scalar.value < 0x100:
                    escaped += String(format: "\\x%02x", scalar.value)
                case _ where CharacterSet.controlCharacters.contains(scalar):
                    escaped += String(format: "\\u%04x", scalar.value)
                default: escaped.unicodeScalars.append(scalar)
                }
            }
            return "$'" + escaped + "'"
        }
        return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: Receipts

    /// "Codex 0.51.0 → 0.52.0", "Ollama installed", "Codex added a login item".
    public static func headline(_ receipt: Receipt) -> String {
        switch receipt.kind {
        case .updated:
            return "\(receipt.toolName) \(receipt.fromVersion ?? "?") → \(receipt.toVersion ?? "?")"
        case .installed:
            return receipt.toVersion.map { "\(receipt.toolName) \($0) installed" } ?? "\(receipt.toolName) installed"
        case .removed:
            return "\(receipt.toolName) removed"
        case .changed:
            let added = receipt.itemsAdded.count, removed = receipt.itemsRemoved.count
            if added > 0 && removed == 0 { return "\(receipt.toolName) added \(added == 1 ? "a login item" : count(added, "login item"))" }
            if removed > 0 && added == 0 { return "\(receipt.toolName) removed \(removed == 1 ? "a login item" : count(removed, "login item"))" }
            return "\(receipt.toolName) changed its login items"
        }
    }

    /// The short version for a menu: "+1.8 GB, added a login item".
    public static func gist(_ receipt: Receipt) -> String {
        var parts: [String] = []
        if receipt.delta != 0 || receipt.kind == .updated { parts.append(delta(receipt.delta)) }
        if receipt.kind != .changed {
            if !receipt.itemsAdded.isEmpty { parts.append(receipt.itemsAdded.count == 1 ? "added a login item" : "added \(count(receipt.itemsAdded.count, "login item"))") }
            if !receipt.itemsRemoved.isEmpty { parts.append(receipt.itemsRemoved.count == 1 ? "removed a login item" : "removed \(count(receipt.itemsRemoved.count, "login item"))") }
        }
        return parts.joined(separator: ", ")
    }

    /// Each line of a receipt, for the window and Copy Receipt.
    public static func lines(_ receipt: Receipt) -> [String] {
        var lines: [String] = []
        if receipt.kind == .updated || receipt.kind == .installed || receipt.delta != 0 {
            lines.append("Disk: \(bytes(receipt.bytesBefore)) → \(bytes(receipt.bytesAfter)) (\(delta(receipt.delta)))")
        }
        for change in receipt.changes {
            lines.append("  \(change.label) (~/\(change.path)): \(delta(change.delta))")
        }
        for item in receipt.itemsAdded {
            lines.append("Added login item \(item.label): \(schedule(item))")
        }
        for item in receipt.itemsRemoved {
            lines.append("Removed login item \(item.label)")
        }
        return lines
    }

    /// The whole receipt as text, for a bug report or your notes. Paths show your home folder as `~`.
    public static func receiptText(_ receipt: Receipt, date: String, since: String, home: String?) -> String {
        var text = [headline(receipt), "Noticed \(date), compared with the check \(since)."]
        text += lines(receipt)
        for item in receipt.itemsAdded {
            text.append("  \(path(item.plistPath, home: home))" + (item.program.map { " runs \(path($0, home: home))" } ?? ""))
        }
        return text.joined(separator: "\n")
    }
}
