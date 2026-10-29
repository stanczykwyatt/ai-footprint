import FootprintCore
import Foundation
import UserNotifications

/// Optional notifications when a tool updates or adds a login item. Off until you turn them on.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Called when you click a notification.
    var onOpen: (() -> Void)?

    private var center: UNUserNotificationCenter { .current() }

    func activate() {
        center.delegate = self
    }

    /// Asks macOS for permission. Calls back with whether notifications can be shown.
    func requestPermission(_ done: @escaping @MainActor (Bool) -> Void) {
        Task { done(await Self.requestAuthorization()) }
    }

    /// Checks whether notifications are allowed in System Settings.
    func checkPermission(_ done: @escaping @MainActor (Bool) -> Void) {
        Task {
            let status = await Self.authorizationStatus()
            done(status == .authorized || status == .provisional)
        }
    }

    // macOS runs these callbacks on a background queue. They're written in nonisolated functions,
    // because a closure written in this main-actor class would trap when called there.

    private nonisolated static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private nonisolated static func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    static func content(for receipt: Receipt) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = Describe.headline(receipt)
        let gist = Describe.gist(receipt)
        content.body = gist.isEmpty ? "Open AI Footprint to see what changed." : gist.prefix(1).uppercased() + gist.dropFirst() + "."
        content.threadIdentifier = receipt.toolID
        return content
    }

    func post(_ receipt: Receipt) {
        center.add(UNNotificationRequest(identifier: receipt.id.uuidString, content: Self.content(for: receipt), trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { onOpen?() }
    }
}
