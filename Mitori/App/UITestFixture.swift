#if DEBUG
import Foundation

/// Offline launch fixture for UI tests. `MITORI_UI_FIXTURE=1` seeds two
/// accounts; `MITORI_UI_FIXTURE=empty` starts with none. It never reads or
/// writes the real account file, Keychain, refresh settings, or network.
@MainActor
final class UITestFixture {
    nonisolated static let readyEmail = "ready@example.com"
    nonisolated static let expiredEmail = "expired@example.com"
    /// The only 2FA code the fixture accepts.
    nonisolated static let validCode = "123456"

    let settings: RefreshSettingsStore
    let model: MitoriModel
    let probeAppSearch: any ProbeAppSearching = FixtureProbeAppSearch()
    private let seedsAccounts: Bool
    private let accountStore: AccountStore
    private let secretStore: SecretStore

    static func fromEnvironment() -> UITestFixture? {
        switch ProcessInfo.processInfo.environment["MITORI_UI_FIXTURE"] {
        case "1": UITestFixture(seedsAccounts: true)
        case "empty": UITestFixture(seedsAccounts: false)
        default: nil
        }
    }

    private init(seedsAccounts: Bool) {
        self.seedsAccounts = seedsAccounts
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
        guard seedsAccounts else { return }
        let fetchedAt = Date(timeIntervalSinceNow: -3600)
        var ready = Self.meta(email: Self.readyEmail, firstName: "Ready")
        ready.balanceSnapshot = Self.snapshot("$12.34", amount: "12.34", fetchedAt: fetchedAt)
        ready.lastRefreshAt = fetchedAt
        var expired = Self.meta(email: Self.expiredEmail, firstName: "Expired")
        expired.balanceSnapshot = Self.snapshot("$5.00", amount: "5.00", fetchedAt: fetchedAt)
        expired.lastRefreshAt = fetchedAt

        for meta in [ready, expired] {
            try await accountStore.upsert(meta)
            try await secretStore.save(Self.secret, for: meta.id)
        }
    }

    nonisolated static let secret = StoredAccountSecret(
        password: "fixture",
        cookies: [],
        passwordToken: "fixture",
        directoryServicesIdentifier: "0"
    )

    nonisolated static func meta(email: String, firstName: String) -> StoredAccountMeta {
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

/// Deterministic bridge. Login and reauthentication accept only `validCode`;
/// the ready account refreshes to $42.00 and the expired one always fails.
private struct FixtureSessionBridge: AppleSessionBridging {
    func login(
        email: String,
        password _: String,
        code: String,
        deviceIdentifier _: String,
        probeBundleID _: String,
        existing _: StoredAccountMeta?
    ) async throws -> SessionRefreshResult {
        try await Task.sleep(nanoseconds: 300_000_000)
        try Self.check(code: code)
        var meta = UITestFixture.meta(email: email.lowercased(), firstName: "New")
        meta.probeBundleID = ""
        meta.balanceSnapshot = UITestFixture.snapshot("$7.50", amount: "7.50", fetchedAt: Date())
        meta.lastRefreshAt = Date()
        return SessionRefreshResult(meta: meta, secret: UITestFixture.secret)
    }

    func reauthenticate(
        meta: StoredAccountMeta,
        secret: StoredAccountSecret,
        code: String
    ) async throws -> SessionRefreshResult {
        try await Task.sleep(nanoseconds: 300_000_000)
        try Self.check(code: code)
        var updated = meta
        updated.balanceSnapshot = UITestFixture.snapshot("$5.00", amount: "5.00", fetchedAt: Date())
        updated.lastRefreshAt = Date()
        updated.lastIssue = nil
        return SessionRefreshResult(meta: updated, secret: secret)
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

    private static func check(code: String) throws {
        if code.isEmpty { throw MitoriError.twoFactorCodeRequired }
        if code != UITestFixture.validCode { throw MitoriError.invalidTwoFactorCode }
    }
}

/// Any term returns two fixed apps; the term "none" returns no result.
private struct FixtureProbeAppSearch: ProbeAppSearching {
    func searchApps(matching term: String, countryCode _: String, limit _: Int) async throws -> [ProbeAppCandidate] {
        guard term != "none" else { return [] }
        return [
            ProbeAppCandidate(id: 1, bundleID: "com.example.notes", name: "Fixture Notes", sellerName: "Example"),
            ProbeAppCandidate(id: 2, bundleID: "com.example.reader", name: "Fixture Reader", sellerName: "Example"),
        ]
    }
}
#endif
