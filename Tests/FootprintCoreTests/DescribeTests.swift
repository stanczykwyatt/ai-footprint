import Foundation
import Testing
@testable import FootprintCore

@Suite("Wording")
struct DescribeTests {
    @Test(arguments: [
        (Int64(0), "Zero KB"), (-5, "Zero KB"), (1, "1 KB"), (499, "1 KB"), (1_500, "2 KB"), (512_000, "512 KB"),
        (999_400, "999 KB"), (999_600, "1 MB"), (1_000_000, "1 MB"), (4_240_000, "4.2 MB"), (9_960_000, "10 MB"),
        (452_000_000, "452 MB"), (11_735_000_000, "12 GB"), (4_200_000_000, "4.2 GB"), (118_000_000_000, "118 GB"),
        (2_500_000_000_000, "2.5 TB"),
    ])
    func sizes(bytes: Int64, expected: String) {
        #expect(Describe.bytes(bytes) == expected)
    }

    @Test func deltas() {
        #expect(Describe.delta(1_200_000_000) == "+1.2 GB")
        #expect(Describe.delta(-340_000_000) == "−340 MB")
        #expect(Describe.delta(0) == "no change")
    }

    @Test func counts() {
        #expect(Describe.count(1, "process", "processes") == "1 process")
        #expect(Describe.count(3, "process", "processes") == "3 processes")
        #expect(Describe.count(2, "login item") == "2 login items")
        #expect(Describe.count(0, "helper") == "0 helpers")
    }

    @Test func relativeTimes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US_POSIX")
        let now = Fixture.start // Friday, Jan 15 2027, 08:00 UTC
        func relative(_ offset: TimeInterval) -> String {
            // Date formatting puts a narrow no-break space before AM and PM.
            Describe.relative(now.addingTimeInterval(-offset), now: now, calendar: calendar, locale: locale)
                .replacingOccurrences(of: "\u{202F}", with: " ")
        }
        #expect(relative(3) == "just now")
        #expect(relative(42) == "42 s ago")
        #expect(relative(600) == "10 min ago")
        #expect(relative(3 * 3600) == "at 5:00 AM")
        #expect(relative(12 * 3600) == "yesterday at 8:00 PM")
        #expect(relative(3 * 86_400) == "Jan 12 at 8:00 AM")
        #expect(relative(400 * 86_400) == "Dec 11, 2025 at 8:00 AM")
        #expect(Describe.relativeCapitalized(now.addingTimeInterval(-12 * 3600), now: now, calendar: calendar, locale: locale)
            .replacingOccurrences(of: "\u{202F}", with: " ") == "Yesterday at 8:00 PM")
    }

    @Test func ages() {
        #expect(Describe.age(20) == "under a minute")
        #expect(Describe.age(-5) == "under a minute")
        #expect(Describe.age(60) == "1 min")
        #expect(Describe.age(59 * 60) == "59 min")
        #expect(Describe.age(3 * 3600 + 100) == "3 h")
        #expect(Describe.age(86_400) == "1 day")
        #expect(Describe.age(9 * 86_400) == "9 days")
    }

    @Test func homeFolderShowsAsTilde() {
        #expect(Describe.path("/Users/someone/.ollama/models", home: "/Users/someone") == "~/.ollama/models")
        #expect(Describe.path("/Users/someone", home: "/Users/someone/") == "~")
        #expect(Describe.path("/Users/someoneelse/x", home: "/Users/someone") == "/Users/someoneelse/x")
        #expect(Describe.path("/Applications/Ollama.app", home: "/Users/someone") == "/Applications/Ollama.app")
        #expect(Describe.path("/x", home: nil) == "/x")
    }

    @Test func toolSummaries() {
        #expect(Describe.summary(bytes: 11_900_000_000, processes: 3, launchItems: 1) == "12 GB · 3 processes · 1 login item")
        #expect(Describe.summary(bytes: 4_200_000, processes: 0, launchItems: 0) == "4.2 MB")
        #expect(Describe.name(.ollama, version: "0.12.3") == "Ollama 0.12.3")
        #expect(Describe.name(.huggingFace, version: nil) == "Hugging Face")
        #expect(Describe.location(Location(".ollama/models", "Models"), usage: Fixture.usage(8_400_000_000)) == "Models: 8.4 GB")
        #expect(Location(".ollama/models", "Models").displayPath == "~/.ollama/models")
    }

    private func process(_ role: ProcessRole, _ attachment: Attachment, pids: [ProcessID] = [42], bundleID: String? = nil) -> ToolProcess {
        ToolProcess(
            pid: pids[0], pids: pids, toolID: "codex", launchedBy: nil, name: "codex", role: role, attachment: attachment,
            residentBytes: 120_000_000, path: "/opt/homebrew/bin/codex", bundleID: bundleID, started: Fixture.start
        )
    }

    @Test func rolesAndWhatKeepsThemRunning() {
        #expect(Describe.role(process(.app, .app, pids: [1, 2, 3])) == "App, with 2 helpers")
        #expect(Describe.role(process(.app, .app)) == "App")
        #expect(Describe.role(process(.server, .none)) == "Server")
        #expect(Describe.role(process(.mcpServer, .none)) == "MCP server")
        #expect(Describe.role(process(.session, .terminal)) == "Session")
        #expect(Describe.role(process(.helper, .parent(name: "Codex"))) == "Helper")
        #expect(Describe.attachment(process(.session, .terminal)) == "In a terminal")
        #expect(Describe.attachment(process(.server, .launchItem(label: "com.x", scope: .user))) == "Started by the login item com.x")
        #expect(Describe.attachment(process(.mcpServer, .parent(name: "Claude Code"))) == "Started by Claude Code")
        #expect(Describe.attachment(process(.mcpServer, .none)) == "Orphaned: the app that started it has quit")
        #expect(Describe.attachment(process(.server, .none)) == "Left running on its own")
        #expect(Describe.attachment(process(.app, .app)) == "Open as an app")
    }

    @Test func processLines() {
        let line = Describe.processLine(process(.server, .none), now: Fixture.start.addingTimeInterval(7200))
        #expect(line == "Server · 120 MB memory · running 2 h")
        var unknown = process(.server, .none)
        unknown.started = nil
        #expect(Describe.processLine(unknown, now: Fixture.start) == "Server · 120 MB memory")
    }

    @Test func schedules() {
        #expect(Describe.schedule(Fixture.item("a", runsAtLoad: true, keepsAlive: true)) == "Starts at login, and again if it quits")
        #expect(Describe.schedule(Fixture.item("a", runsAtLoad: true)) == "Starts at login")
        #expect(Describe.schedule(Fixture.item("a", scope: .system, runsAtLoad: true)) == "Starts with your Mac")
        #expect(Describe.schedule(Fixture.item("a", runsAtLoad: false, keepsAlive: true)) == "Restarts whenever it quits")
        #expect(Describe.schedule(Fixture.item("a", runsAtLoad: false)) == "Starts when something asks for it")
        var timed = Fixture.item("a", runsAtLoad: false)
        timed.interval = 3600
        #expect(Describe.schedule(timed) == "Runs every hour")
        timed.interval = 7200
        timed.runsAtLoad = true
        #expect(Describe.schedule(timed) == "Starts at login, and every 2 hours")
        timed.interval = 86_400
        #expect(Describe.schedule(timed) == "Starts at login, and every day")
        timed.interval = 90
        #expect(Describe.schedule(timed) == "Starts at login, and every 90 seconds")
        timed.interval = 300
        #expect(Describe.schedule(timed) == "Starts at login, and every 5 minutes")
    }

    @Test func scopes() {
        #expect(Describe.scope(.user) == "For you")
        #expect(Describe.scope(.allUsers) == "For everyone who logs in")
        #expect(Describe.scope(.system) == "For the whole Mac, as the system")
    }

    @Test func stopCommands() {
        #expect(Describe.stopCommand(process(.server, .none, pids: [42]), uid: 501) == "kill 42")
        #expect(Describe.stopCommand(process(.mcpServer, .none, pids: [42, 43]), uid: 501) == "kill 42 43")
        #expect(Describe.stopCommand(process(.server, .launchItem(label: "com.openai.codex.server", scope: .user)), uid: 501) == "launchctl bootout gui/501/com.openai.codex.server")
        #expect(Describe.stopCommand(process(.app, .app, bundleID: "com.electron.ollama"), uid: 501) == #"osascript -e 'quit app id "com.electron.ollama"'"#)
        #expect(Describe.stopCommand(process(.app, .app), uid: 501) == "kill 42")
        #expect(Describe.stopCommand(Fixture.item("com.ollama.ollama"), uid: 502) == "launchctl bootout gui/502/com.ollama.ollama")
        #expect(Describe.stopCommand(Fixture.item("com.x.daemon", scope: .system), uid: 501) == "sudo launchctl bootout system/com.x.daemon")
        #expect(Describe.stopCommand(Fixture.item("com.x.shared", scope: .allUsers), uid: 501) == "launchctl bootout gui/501/com.x.shared")
    }

    @Test func stopCommandsQuoteLabelsSafely() {
        // A label comes from another app's file, so it mustn't be able to add a second command.
        let command = Describe.stopCommand(Fixture.item("x; rm -rf ~"), uid: 501)
        #expect(command == "launchctl bootout gui/501/'x; rm -rf ~'")
        let quote = Describe.stopCommand(Fixture.item("it's"), uid: 501)
        #expect(quote == #"launchctl bootout gui/501/'it'\''s'"#)
        // So must a bundle ID, inside the script that quits the app.
        #expect(Describe.stopCommand(process(.app, .app, bundleID: "a\"; do shell script \"x"), uid: 501) == "kill 42")
        #expect(Describe.stopCommand(process(.app, .app, bundleID: "com.exämple.app"), uid: 501) == "kill 42")
        #expect(Describe.stopCommand(process(.app, .app, bundleID: ""), uid: 501) == "kill 42")
    }

    @Test func shellQuoting() {
        #expect(Describe.shellQuote("com.example.agent") == "com.example.agent")
        #expect(Describe.shellQuote("") == "''")
        #expect(Describe.shellQuote("two words") == "'two words'")
        #expect(Describe.shellQuote("$(whoami)") == "'$(whoami)'")
        #expect(Describe.shellQuote("a`b`") == "'a`b`'")
    }

    @Test func stopNotes() {
        #expect(Describe.stopNote(process(.server, .launchItem(label: "x", scope: .user))).contains("login item"))
        #expect(Describe.stopNote(process(.app, .app, bundleID: "com.example.app")).contains("Quit"))
        #expect(Describe.stopNote(process(.mcpServer, .none, pids: [1, 2])) == "Asks it and its helpers to quit.")
        #expect(Describe.stopNote(process(.mcpServer, .none)) == "Asks it to quit.")
    }

    private func receipt(_ kind: Receipt.Kind, from: String? = "0.51.0", to: String? = "0.52.0", before: Int64 = 200_000_000, after: Int64 = 2_000_000_000, added: [LaunchItem] = [], removed: [LaunchItem] = []) -> Receipt {
        Receipt(
            kind: kind, toolID: "codex", toolName: "Codex", date: Fixture.start, since: Fixture.start, fromVersion: from, toVersion: to,
            bytesBefore: before, bytesAfter: after,
            changes: [Receipt.Change(path: ".codex/log", label: "Logs", before: 10_000_000, after: 1_810_000_000)],
            itemsAdded: added, itemsRemoved: removed
        )
    }

    @Test func receiptHeadlines() {
        let agent = Fixture.item("com.openai.codex.server", keepsAlive: true)
        #expect(Describe.headline(receipt(.updated)) == "Codex 0.51.0 → 0.52.0")
        #expect(Describe.headline(receipt(.installed, from: nil)) == "Codex 0.52.0 installed")
        #expect(Describe.headline(receipt(.installed, from: nil, to: nil)) == "Codex installed")
        #expect(Describe.headline(receipt(.removed)) == "Codex removed")
        #expect(Describe.headline(receipt(.changed, added: [agent])) == "Codex added a login item")
        #expect(Describe.headline(receipt(.changed, added: [agent, agent])) == "Codex added 2 login items")
        #expect(Describe.headline(receipt(.changed, removed: [agent])) == "Codex removed a login item")
        #expect(Describe.headline(receipt(.changed, added: [agent], removed: [agent])) == "Codex changed its login items")
    }

    @Test func receiptGists() {
        let agent = Fixture.item("com.openai.codex.server")
        #expect(Describe.gist(receipt(.updated, added: [agent])) == "+1.8 GB, added a login item")
        #expect(Describe.gist(receipt(.updated, before: 5, after: 5)) == "no change")
        #expect(Describe.gist(receipt(.changed, before: 5, after: 5, added: [agent])) == "")
        #expect(Describe.gist(receipt(.removed, before: 3_000_000, after: 0, removed: [agent, agent])) == "−3 MB, removed 2 login items")
    }

    @Test func receiptLines() {
        let agent = Fixture.item("com.openai.codex.server", runsAtLoad: true, keepsAlive: true)
        let lines = Describe.lines(receipt(.updated, added: [agent], removed: [Fixture.item("com.openai.codex.old")]))
        #expect(lines == [
            "Disk: 200 MB → 2 GB (+1.8 GB)",
            "  Logs (~/.codex/log): +1.8 GB",
            "Added login item com.openai.codex.server: Starts at login, and again if it quits",
            "Removed login item com.openai.codex.old",
        ])
    }

    @Test func receiptTextHidesYourUsername() {
        let agent = LaunchItem(label: "com.openai.codex.server", plistPath: "/Users/someone/Library/LaunchAgents/com.openai.codex.server.plist", scope: .user, program: "/Users/someone/.codex/bin/server")
        let text = Describe.receiptText(receipt(.updated, added: [agent]), date: "today at 9:00", since: "today at 8:45", home: "/Users/someone")
        #expect(text.hasPrefix("Codex 0.51.0 → 0.52.0\nNoticed today at 9:00, compared with the check today at 8:45."))
        #expect(text.contains("~/Library/LaunchAgents/com.openai.codex.server.plist runs ~/.codex/bin/server"))
        #expect(!text.contains("/Users/someone"))
    }

    @Test func aSystemLoginItemsProcessNeedsSudo() {
        let daemon = process(.server, .launchItem(label: "homebrew.mxcl.ollama", scope: .system))
        #expect(Describe.stopCommand(daemon, uid: 501) == "sudo launchctl bootout system/homebrew.mxcl.ollama")
        #expect(Describe.stopNote(daemon) == "Stops it and its login item until your Mac restarts.")
        let shared = process(.server, .launchItem(label: "com.x.shared", scope: .allUsers))
        #expect(Describe.stopCommand(shared, uid: 501) == "launchctl bootout gui/501/com.x.shared")
    }

    @Test func loginItemNotesSayHowLongItStaysStopped() {
        #expect(Describe.stopNote(Fixture.item("a")).hasPrefix("Stops it until you next log in."))
        #expect(Describe.stopNote(Fixture.item("a", scope: .system)).hasPrefix("Stops it until your Mac restarts."))
    }

    @Test func anAppWithoutAUsableBundleIDIsAskedToQuit() {
        #expect(Describe.stopNote(process(.app, .app, bundleID: "com.example.app")) == "Quits the app, as if you chose Quit from its menu.")
        #expect(Describe.stopNote(process(.app, .app)) == "Asks it to quit.")
    }

    @Test func controlCharactersAreSpelledOut() {
        // An escape sequence in a label could hide part of the command in Terminal.
        #expect(Describe.shellQuote("a\u{1B}[2Kb") == "$'a\\x1b[2Kb'")
        #expect(Describe.shellQuote("line\nbreak") == "$'line\\x0abreak'")
        #expect(Describe.shellQuote("it's\t") == "$'it\\'s\\x09'")
        #expect(Describe.stopCommand(Fixture.item("x\u{7}y"), uid: 501) == "launchctl bootout gui/501/$'x\\x07y'")
    }
}
