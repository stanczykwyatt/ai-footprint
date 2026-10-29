import AppKit
import FootprintCore
import SwiftUI

/// The main window: every AI tool's disk, processes and login items, and what each update changed.
struct FootprintView: View {
    let model: FootprintModel
    let icons: ToolIcons
    var uid: UInt32 = getuid()
    var checkNow: () -> Void = {}

    enum Tab: String, CaseIterable, Identifiable {
        case tools = "Tools"
        case updates = "Updates"
        var id: Self { self }
    }

    @State var tab: Tab = .tools

    var body: some View {
        // Redraws every half minute so "2 min ago" doesn't go stale while the window is open.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 0) {
                header(now: context.date)
                Divider()
                switch tab {
                case .tools: toolsList(now: context.date)
                case .updates: updatesList(now: context.date)
                }
                Divider()
                footer(now: context.date)
            }
        }
        .frame(minWidth: 680, minHeight: 420)
        // The window draws this anyway; drawing it here too keeps off-screen renders right in dark mode.
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Parts

    private func header(now: Date) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                if model.footprint == nil {
                    Text(model.isChecking ? "Measuring AI tools…" : "Not checked yet")
                        .font(.title2.weight(.semibold))
                } else {
                    Text("AI tools use \(Describe.bytes(model.totalBytes))")
                        .font(.title2.weight(.semibold))
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Picker("Show", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab == .updates && model.unseenReceipts > 0 ? "Updates (\(model.unseenReceipts))" : tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var summary: String {
        var parts = [Describe.count(model.installedTools.count, "tool")]
        let background = model.backgroundProcesses.count
        parts.append(background == 0 ? "nothing in the background" : Describe.count(background, "background process", "background processes"))
        if model.totalMemory > 0 { parts.append("\(Describe.bytes(model.totalMemory)) memory") }
        if !model.launchItems.isEmpty { parts.append(Describe.count(model.launchItems.count, "login item")) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func toolsList(now: Date) -> some View {
        let tools = model.installedTools
        if tools.isEmpty && model.mcpServers.isEmpty {
            ContentUnavailableView {
                Label(model.footprint == nil ? "Measuring…" : "No AI tools found", systemImage: "shoeprints.fill")
            } description: {
                Text("AI Footprint looks for Claude Code, the Claude app, Codex, Ollama, LM Studio, Hugging Face downloads and MCP servers. Anything it finds shows up here.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    let unattached = model.mcpServers.filter { $0.launchedBy == nil }
                    if !unattached.isEmpty {
                        MCPCard(servers: unattached, model: model, uid: uid, now: now)
                    }
                    ForEach(tools) { tool in
                        ToolCard(tool: tool, model: model, icon: icons.icon(for: tool, size: 34), uid: uid, now: now)
                    }
                    if !model.missingTools.isEmpty {
                        Text("Not found on this Mac: " + model.missingTools.map(\.name).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(16)
            }
        }
    }

    @ViewBuilder
    private func updatesList(now: Date) -> some View {
        if model.receipts.isEmpty {
            ContentUnavailableView {
                Label("No updates yet", systemImage: "doc.plaintext")
            } description: {
                Text("When a tool updates, installs itself, or adds or removes a login item, a receipt shows up here with what it changed on disk.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.receipts) { receipt in
                        ReceiptCard(receipt: receipt, icon: model.tool(receipt.toolID).map { icons.icon(for: $0, size: 28) }, now: now)
                    }
                }
                .padding(16)
            }
        }
    }

    private func footer(now: Date) -> some View {
        HStack(spacing: 10) {
            Text("Read-only. AI Footprint can't delete or stop anything: Show in Finder and Copy Stop Command leave that to you.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            if let checked = model.lastChecked {
                Text("Checked \(Describe.relative(checked, now: now))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(model.isChecking ? "Checking…" : "Check Now", action: checkNow)
                .disabled(model.isChecking)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// One tool: what it keeps on disk, what it runs and what starts it.
private struct ToolCard: View {
    let tool: Tool
    let model: FootprintModel
    let icon: NSImage
    let uid: UInt32
    let now: Date

    var body: some View {
        let state = model.state(tool)
        let processes = model.processes(for: tool)
        let locations = tool.locations.compactMap { location in state?.usage[location.path].map { (location, $0) } }
            .sorted { $0.1.bytes > $1.1.bytes }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: icon)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tool.name)
                        .font(.headline)
                    Text(state?.version.map { "Version \($0)" } ?? "Version unknown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Describe.bytes(state?.bytes ?? 0))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            if let total = state?.bytes, total > 0 {
                UsageBar(parts: locations.map { $0.1.bytes }, total: total)
            }
            ForEach(locations, id: \.0.path) { location, usage in
                Row(symbol: "folder", title: location.label, detail: location.displayPath, value: Describe.bytes(usage.bytes)) {
                    Button("Show in Finder") { Finder.reveal(Home.url(location.path).path) }
                }
                .help(usage.parts.map { "\($0.name): \(Describe.bytes($0.bytes))" }.joined(separator: "\n"))
            }
            ForEach(processes) { process in
                ProcessRow(process: process, uid: uid, now: now)
            }
            ForEach(state?.launchItems ?? []) { item in
                Row(symbol: "power", title: item.label, detail: Describe.schedule(item), value: nil) {
                    Button("Show in Finder") { Finder.reveal(item.plistPath) }
                    Button("Copy Stop Command") { Clipboard.copy(Describe.stopCommand(item, uid: uid)) }
                        .help(Describe.stopCommand(item, uid: uid) + "\n" + Describe.stopNote(item))
                }
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.6)))
    }
}

/// MCP servers that no AI tool in the list started: orphans, and ones another app started.
private struct MCPCard: View {
    let servers: [ToolProcess]
    let model: FootprintModel
    let uid: UInt32
    let now: Date

    var body: some View {
        let orphans = servers.filter(\.isOrphaned).count
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: orphans > 0 ? "exclamationmark.triangle.fill" : "point.3.connected.trianglepath.dotted")
                    .font(.title2)
                    .foregroundStyle(orphans > 0 ? .orange : .secondary)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MCP Servers")
                        .font(.headline)
                    Text(orphans > 0 ? "\(Describe.count(orphans, "orphan")): the app that started \(orphans == 1 ? "it" : "them") has quit" : "Started by other apps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Describe.bytes(servers.reduce(0) { $0 + $1.residentBytes })) memory")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            ForEach(servers) { server in
                ProcessRow(process: server, uid: uid, now: now)
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(orphans > 0 ? AnyShapeStyle(.orange.opacity(0.5)) : AnyShapeStyle(.separator.opacity(0.6))))
    }
}

struct ProcessRow: View {
    let process: ToolProcess
    let uid: UInt32
    let now: Date

    static func symbol(_ role: ProcessRole) -> String {
        switch role {
        case .app: "macwindow"
        case .helper: "gearshape"
        case .server: "server.rack"
        case .session: "terminal"
        case .mcpServer: "point.3.connected.trianglepath.dotted"
        }
    }

    var body: some View {
        let command = Describe.stopCommand(process, uid: uid)
        Row(
            symbol: process.isLeftRunning ? "exclamationmark.triangle.fill" : Self.symbol(process.role),
            title: process.name,
            detail: Describe.attachment(process) + " · " + Describe.processLine(process, now: now),
            value: nil,
            warning: process.isLeftRunning
        ) {
            if let path = process.path {
                Button("Show in Finder") { Finder.reveal(path) }
            }
            Button("Copy Stop Command") { Clipboard.copy(command) }
                .help(command + "\n" + Describe.stopNote(process))
        }
    }
}

/// A line in a card with its actions in a menu.
private struct Row<Actions: View>: View {
    let symbol: String
    let title: String
    let detail: String
    let value: String?
    var warning = false
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(warning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Menu {
                actions()
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .contextMenu { actions() }
    }
}

/// How a tool's disk use splits between its folders.
private struct UsageBar: View {
    let parts: [Int64]
    let total: Int64
    static let shades: [Double] = [1, 0.7, 0.5, 0.36, 0.26, 0.18]
    /// The icon's icy blue, the same in every accent color, so screenshots match.
    static let color = Color(.sRGB, red: 0.38, green: 0.55, blue: 0.80)

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1.5) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, bytes in
                    Rectangle()
                        .fill(Self.color.opacity(Self.shades[min(index, Self.shades.count - 1)]))
                        .frame(width: max(2, geometry.size.width * CGFloat(bytes) / CGFloat(max(total, 1)) - 1.5))
                }
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

private struct ReceiptCard: View {
    let receipt: Receipt
    let icon: NSImage?
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let icon {
                Image(nsImage: icon)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(Describe.headline(receipt))
                        .font(.headline)
                    Spacer()
                    Text(Describe.relativeCapitalized(receipt.date, now: now))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(Describe.lines(receipt).enumerated()), id: \.offset) { _, line in
                    Text(line.trimmingCharacters(in: .whitespaces))
                        .font(line.hasPrefix(" ") ? .callout : .callout.weight(.medium))
                        .foregroundStyle(line.hasPrefix(" ") ? .secondary : .primary)
                        .padding(.leading, line.hasPrefix(" ") ? 12 : 0)
                }
                Text("Compared with the check \(Describe.relative(receipt.since, now: now))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.6)))
        .contextMenu {
            Button("Copy Receipt") {
                Clipboard.copy(Describe.receiptText(receipt, date: StatusMenu.longDate(receipt.date), since: StatusMenu.longDate(receipt.since), home: Home.path))
            }
        }
    }
}

/// Opens the window and remembers where you put it.
@MainActor
final class FootprintWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let makeView: () -> FootprintView
    /// Called when you close the window.
    var onClose: (() -> Void)?
    /// Called when the window comes to the front.
    var onActivate: (() -> Void)?

    init(makeView: @escaping () -> FootprintView) {
        self.makeView = makeView
    }

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onActivate?()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: makeView()))
        window.title = "AI Footprint"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 820, height: 640))
        if !window.setFrameUsingName("FootprintWindow") {
            window.center()
        }
        window.setFrameAutosaveName("FootprintWindow")
        return window
    }
}
