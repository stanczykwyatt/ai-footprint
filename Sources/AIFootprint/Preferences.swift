import Foundation

/// Settings, kept in the app's sandbox container.
struct Preferences {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let notifies = "notifies"
        static let launchedBefore = "launchedBefore"
        static let seenThrough = "receiptsSeenThrough"
    }

    var notifies: Bool {
        get { defaults.bool(forKey: Key.notifies) }
        nonmutating set { defaults.set(newValue, forKey: Key.notifies) }
    }

    var launchedBefore: Bool {
        get { defaults.bool(forKey: Key.launchedBefore) }
        nonmutating set { defaults.set(newValue, forKey: Key.launchedBefore) }
    }

    /// Receipts from before this date have been seen in the menu or window.
    var seenThrough: Date? {
        get { defaults.object(forKey: Key.seenThrough) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.seenThrough) }
    }
}
