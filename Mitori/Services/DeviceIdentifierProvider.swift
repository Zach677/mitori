import Foundation

enum DeviceIdentifierProvider {
    private static let fallbackKey = "deviceIdentifier.fallback"

    /// The hardware identifier, or one random identifier kept for this Mac, so
    /// every account added here presents the same device to Apple.
    static func make(
        system: () throws -> String = DeviceIdentifier.system,
        defaults: UserDefaults = .standard
    ) -> String {
        if let identifier = try? system() {
            return identifier
        }
        if let stored = defaults.string(forKey: fallbackKey), stored.count == 12 {
            return stored
        }
        let identifier = DeviceIdentifier.random()
        defaults.set(identifier, forKey: fallbackKey)
        return identifier
    }
}
