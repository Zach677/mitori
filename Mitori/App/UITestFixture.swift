#if DEBUG
import Foundation

/// Offline launch fixture for UI tests, enabled by `MITORI_UI_FIXTURE=1`.
/// It never reads or writes the real account file, Keychain, user defaults, or network.
@MainActor
final class UITestFixture {
    nonisolated static let readyEmail = "ready@example.com"
    nonisolated static let expiredEmail = "expired@example.com"

    let settings: RefreshSettingsStore
    let model: MitoriModel
    private let accountStore: AccountStore
    private let secretStore: SecretStore

    static func fromEnvironment() -> UITestFixture? {
        ProcessInfo.processInfo.environment["MITORI_UI_FIXTURE"] == "1" ? UITestFixture() : nil
    }

    private init() {
        let suiteName = "dev.zach.mitori.uitest"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        settings = RefreshSettingsStore(defaults: defaults)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mitori-uitest-\(UUID().uuidString)", isDirectory: true)
        accountStore = AccountStore(baseDirectory: directory)
        secretStore = SecretStore(backend: InMemorySecretBackend())
        model = MitoriModel(
            accountStore: accountStore,
            secretStore: secretStore,
            sessionBridge: FixtureSessionBridge(),
            settings: settings
        )
    }

    func seed() async throws {
        let fetchedAt = Date(timeIntervalSinceNow: -3600)
        var ready = Self.meta(email: Self.readyEmail, firstName: "Ready")
        ready.balanceSnapshot = Self.snapshot("$12.34", amount: "12.34", fetchedAt: fetchedAt)
        ready.lastRefreshAt = fetchedAt
        var expired = Self.meta(email: Self.expiredEmail, firstName: "Expired")
        expired.balanceSnapshot = Self.snapshot("$5.00", amount: "5.00", fetchedAt: fetchedAt)
        expired.lastRefreshAt = fetchedAt

        for meta in [ready, expired] {
            try await accountStore.upsert(meta)
            try await secretStore.save(StoredAccountSecret(password: "fixture", cookies: [], passwordToken: "fixture", directoryServicesIdentifier: "0"), for: meta.id)
        }
    }

    static func meta(email: String, firstName: String) -> StoredAccountMeta {
        StoredAccountMeta(
            email: email,
            appleID: email,
            firstName: firstName,
            lastName: "Account",
            storefront: "143441",
            countryCode: "US",
            pod: "25",
            deviceIdentifier: "000000000000",
            probeBundleID: "com.example.probe",
            lastRefreshAt: nil,
            balanceSnapshot: nil,
            lastIssue: nil,
            nextEligibleRefreshAt: nil,
            consecutiveFailureCount: 0
        )
    }

    nonisolated static func snapshot(_ display: String, amount: String, fetchedAt: Date) -> BalanceSnapshot {
        BalanceSnapshot(
            displayText: display,
            numericValue: Decimal(string: amount),
            currencyCode: "USD",
            fetchedAt: fetchedAt,
            source: .probe,
            rawFieldPath: "creditDisplay"
        )
    }
}

/// Deterministic bridge: the ready account refreshes to $42.00, the expired one fails.
private struct FixtureSessionBridge: AppleSessionBridging {
    func login(
        email _: String,
        password _: String,
        code _: String,
        deviceIdentifier _: String,
        probeBundleID _: String,
        existing _: StoredAccountMeta?
    ) async throws -> SessionRefreshResult {
        throw MitoriError.twoFactorCodeRequired
    }

    func reauthenticate(
        meta _: StoredAccountMeta,
        secret _: StoredAccountSecret,
        code _: String
    ) async throws -> SessionRefreshResult {
        throw MitoriError.invalidTwoFactorCode
    }

    func refreshBalance(
        meta: StoredAccountMeta,
        secret: StoredAccountSecret,
        allowsReauthentication _: Bool
    ) async throws -> SessionRefreshResult {
        try await Task.sleep(nanoseconds: 300_000_000)
        guard meta.email == UITestFixture.readyEmail else {
            throw MitoriError.sessionExpired
        }
        var updated = meta
        updated.balanceSnapshot = UITestFixture.snapshot("$42.00", amount: "42.00", fetchedAt: Date())
        updated.lastRefreshAt = Date()
        updated.lastIssue = nil
        return SessionRefreshResult(meta: updated, secret: secret)
    }
}
#endif
