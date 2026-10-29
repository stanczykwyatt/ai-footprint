import Foundation
import FootprintCore
import Testing
@testable import AIFootprint

/// What a notification would say. Nothing is posted.
@Suite("Notifications")
struct NotifierTests {
    private func receipt(_ kind: Receipt.Kind, before: Int64, after: Int64, added: [LaunchItem] = []) -> Receipt {
        Receipt(
            kind: kind, toolID: "codex", toolName: "Codex", date: Date(), since: Date(), fromVersion: "0.51.0", toVersion: "0.52.0",
            bytesBefore: before, bytesAfter: after, itemsAdded: added
        )
    }

    @MainActor
    @Test func anUpdate() {
        let item = LaunchItem(label: "com.openai.codex.server", plistPath: "/a.plist", scope: .user)
        let content = Notifier.content(for: receipt(.updated, before: 100_000_000, after: 1_300_000_000, added: [item]))
        #expect(content.title == "Codex 0.51.0 → 0.52.0")
        #expect(content.body == "+1.2 GB, added a login item.")
        #expect(content.threadIdentifier == "codex")
    }

    @MainActor
    @Test func aChangeWithNothingToSay() {
        let item = LaunchItem(label: "com.openai.codex.server", plistPath: "/a.plist", scope: .user)
        let content = Notifier.content(for: receipt(.changed, before: 5, after: 5, added: [item]))
        #expect(content.title == "Codex added a login item")
        #expect(content.body == "Open AI Footprint to see what changed.")
    }
}
