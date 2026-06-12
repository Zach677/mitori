import Foundation

// Stateless wrapper over UserDefaults, which is itself thread-safe.
final class RefreshSettingsStore: @unchecked Sendable {
    // Apple may rate-limit or flag accounts that are probed too often,
    // so intervals below this floor are never honored.
    static let minimumInterval: TimeInterval = 15 * 60
    static let defaultInterval: TimeInterval = 60 * 60

    private enum Keys {
        static let isAutoRefreshEnabled = "autoRefresh.enabled"
        static let autoRefreshInterval = "autoRefresh.interval"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isAutoRefreshEnabled: Bool {
        get { defaults.bool(forKey: Keys.isAutoRefreshEnabled) }
        set { defaults.set(newValue, forKey: Keys.isAutoRefreshEnabled) }
    }

    var autoRefreshInterval: TimeInterval {
        get {
            let stored = defaults.double(forKey: Keys.autoRefreshInterval)
            guard stored > 0 else { return Self.defaultInterval }
            return max(stored, Self.minimumInterval)
        }
        set { defaults.set(max(newValue, Self.minimumInterval), forKey: Keys.autoRefreshInterval) }
    }
}
