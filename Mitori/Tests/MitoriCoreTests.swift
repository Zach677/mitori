import ApplePackage
import Foundation
import Testing

@testable import Mitori

struct AccountStoreTests {
    private static let legacyDirectoryName = ["Store", "Peek"].joined()

    @Test
    func persistsAndDeletesAccounts() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = AccountStore(baseDirectory: tempDirectory)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )

        let savedAccounts = try await store.upsert(meta)
        #expect(savedAccounts.count == 1)

        let loadedAccounts = try await store.loadAccounts()
        #expect(loadedAccounts == [meta])

        let remainingAccounts = try await store.deleteAccount(id: meta.id)
        #expect(remainingAccounts.isEmpty)
    }

    @Test
    func migratesLegacyAccountsIntoMitoriDirectory() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacyDirectory = tempDirectory.appendingPathComponent(Self.legacyDirectoryName, isDirectory: true)
        let currentDirectory = tempDirectory.appendingPathComponent("Mitori", isDirectory: true)
        let legacyStore = AccountStore(baseDirectory: legacyDirectory)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )

        _ = try await legacyStore.upsert(meta)

        let store = AccountStore(baseDirectory: currentDirectory, legacyBaseDirectory: legacyDirectory)
        let loadedAccounts = try await store.loadAccounts()

        #expect(loadedAccounts == [meta])
        #expect(FileManager.default.fileExists(atPath: currentDirectory.appendingPathComponent("accounts.json").path))
    }
}

struct SecretStoreTests {
    @Test
    func roundTripsSecretsThroughInjectedBackend() async throws {
        let backend = InMemorySecretBackend()
        let store = SecretStore(backend: backend)
        let secret = StoredAccountSecret(account: sampleAccount())

        try await store.save(secret, for: secret.account.email.lowercased())
        let restored = try await store.loadSecret(for: secret.account.email.lowercased())

        #expect(restored == secret)
    }

    @Test
    func migratesLegacySecretsIntoMitoriService() async throws {
        let currentBackend = InMemorySecretBackend()
        let legacyBackend = InMemorySecretBackend()
        let legacyStore = SecretStore(backend: legacyBackend)
        let accountID = sampleAccount().email.lowercased()
        let secret = StoredAccountSecret(account: sampleAccount())

        try await legacyStore.save(secret, for: accountID)

        let store = SecretStore(backend: currentBackend, legacyBackend: legacyBackend)
        let restored = try await store.loadSecret(for: accountID)

        #expect(restored == secret)
        #expect(try currentBackend.data(for: "account.\(accountID)") != nil)
    }
}

@MainActor
struct MitoriModelTests {
    @Test
    func savingProbeBundleIDClearsProbeConfigurationIssue() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "",
            lastIssue: MitoriError.missingProbeBundleID.refreshIssue(
                at: Date(timeIntervalSince1970: 1_743_166_800)
            ),
            lastRefreshAt: Date(),
            nextEligibleRefreshAt: Date().addingTimeInterval(300),
            consecutiveFailureCount: 2
        )
        _ = try await accountStore.upsert(meta)

        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: SecretStore(backend: InMemorySecretBackend()),
            sessionBridge: AppleSessionBridge()
        )
        model.bannerMessage = MitoriError.missingProbeBundleID.localizedDescription

        await model.menuPresented()
        try await model.saveProbeBundleID(" com.example.probe ", for: meta.id)

        let updated = try #require(model.account(with: meta.id))
        #expect(updated.probeBundleID == "com.example.probe")
        #expect(updated.lastIssue == nil)
        #expect(updated.nextEligibleRefreshAt == nil)
        #expect(updated.consecutiveFailureCount == 0)
        #expect(model.bannerMessage == nil)
    }

    @Test
    func menuPresentationDoesNotStartKeychainBackedRefresh() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        _ = try await accountStore.upsert(meta)

        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: SecretStore(backend: InMemorySecretBackend()),
            sessionBridge: SessionBridgeStub()
        )

        await model.menuPresented()

        #expect(model.account(with: meta.id) != nil)
        #expect(model.refreshState(for: meta.id) == .idle)
        #expect(model.bannerMessage == nil)
    }

    @Test
    func refreshAccountMarksReturnedIssueAsFailure() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let secretBackend = InMemorySecretBackend()
        let secretStore = SecretStore(backend: secretBackend)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        let secret = StoredAccountSecret(account: sampleAccount())
        _ = try await accountStore.upsert(meta)
        try await secretStore.save(secret, for: meta.id)

        let result = SessionRefreshResult(
            meta: StoredAccountMeta(
                account: sampleAccount(),
                deviceIdentifier: meta.deviceIdentifier,
                probeBundleID: meta.probeBundleID,
                lastIssue: MitoriError.sessionExpired.refreshIssue()
            ),
            secret: secret
        )
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: secretStore,
            sessionBridge: SessionBridgeStub(refreshResult: result)
        )

        await model.menuPresented()
        await model.refreshAccount(id: meta.id, isManualRefresh: true)

        #expect(model.refreshState(for: meta.id) == .failed(.sessionExpired))
        #expect(model.bannerMessage == MitoriError.sessionExpired.localizedDescription)
    }

    @Test
    func reauthenticateThrowsWhenReturnedIssuePersists() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let secretBackend = InMemorySecretBackend()
        let secretStore = SecretStore(backend: secretBackend)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        let secret = StoredAccountSecret(account: sampleAccount())
        _ = try await accountStore.upsert(meta)
        try await secretStore.save(secret, for: meta.id)

        let result = SessionRefreshResult(
            meta: StoredAccountMeta(
                account: sampleAccount(),
                deviceIdentifier: meta.deviceIdentifier,
                probeBundleID: meta.probeBundleID,
                lastIssue: MitoriError.sessionExpired.refreshIssue()
            ),
            secret: secret
        )
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: secretStore,
            sessionBridge: SessionBridgeStub(reauthenticateResult: result)
        )

        await model.menuPresented()

        await #expect(throws: MitoriError.sessionExpired) {
            try await model.reauthenticateAccount(id: meta.id, code: "")
        }

        #expect(model.refreshState(for: meta.id) == .failed(.sessionExpired))
        #expect(model.bannerMessage == MitoriError.sessionExpired.localizedDescription)
    }

    @Test
    func addAccountUsesFlowDeviceIdentifier() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bridge = SessionBridgeStub(loginResult: SessionRefreshResult(
            meta: StoredAccountMeta(
                account: sampleAccount(),
                deviceIdentifier: "ABCDEF123456",
                probeBundleID: "com.example.probe"
            ),
            secret: StoredAccountSecret(account: sampleAccount())
        ))
        let model = MitoriModel(
            accountStore: AccountStore(baseDirectory: tempDirectory),
            secretStore: SecretStore(backend: InMemorySecretBackend()),
            sessionBridge: bridge
        )

        try await model.addAccount(
            email: "demo@example.com",
            password: "password",
            code: "123456",
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )

        let request = try #require(bridge.loginRequests.first)
        #expect(request.deviceIdentifier == "ABCDEF123456")
        #expect(request.code == "123456")
    }
}

struct MitoriErrorTests {
    @Test
    func mapsVerificationAndSessionErrors() {
        let verificationError = NSError(
            domain: "Test",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Authentication requires verification code"]
        )
        let expiredError = NSError(
            domain: "Test",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "password token is expired"]
        )

        #expect(MitoriError.map(verificationError) == .twoFactorCodeRequired)
        #expect(MitoriError.map(expiredError) == .sessionExpired)
    }
}

struct BalanceParserTests {
    @Test
    func parsesAuthenticationFixture() throws {
        let data = try FixtureLoader.data(named: "auth_success_balance")
        let snapshot = try BalanceParser.parse(plistData: data, source: .authentication)

        #expect(snapshot.displayText == "USD 24.90")
        #expect(snapshot.currencyCode == "USD")
        #expect(snapshot.numericValue == Decimal(string: "24.90"))
        #expect(snapshot.rawFieldPath == "accountInfo.balance")
    }

    @Test
    func parsesProbeFixture() throws {
        let data = try FixtureLoader.data(named: "probe_success_balance")
        let snapshot = try BalanceParser.parse(plistData: data, source: .probe)

        #expect(snapshot.displayText == "CNY 88.00")
        #expect(snapshot.currencyCode == "CNY")
        #expect(snapshot.numericValue == Decimal(string: "88.00"))
        #expect(snapshot.rawFieldPath == "songList[0].creditBalance")
    }
}

private final class FixtureBundleToken: NSObject {}

private enum FixtureLoader {
    static func data(named resourceName: String) throws -> Data {
        let urls = [
            Bundle.module.url(forResource: resourceName, withExtension: "plist"),
            Bundle.module.url(forResource: resourceName, withExtension: "plist", subdirectory: "Fixtures"),
            Bundle(for: FixtureBundleToken.self).url(forResource: resourceName, withExtension: "plist"),
            Bundle(for: FixtureBundleToken.self).url(forResource: resourceName, withExtension: "plist", subdirectory: "Fixtures"),
        ]

        guard let url = urls.compactMap({ $0 }).first else {
            throw NSError(domain: "FixtureLoader", code: 404)
        }

        return try Data(contentsOf: url)
    }
}

private func sampleAccount(cookies: [Cookie] = []) -> Account {
    Account(
        email: "demo@example.com",
        password: "password",
        appleId: "demo@example.com",
        store: "143441",
        firstName: "Demo",
        lastName: "User",
        passwordToken: "token",
        directoryServicesIdentifier: "1234567890",
        cookie: cookies,
        pod: "25"
    )
}

private final class SessionBridgeStub: AppleSessionBridging {
    struct LoginRequest {
        var email: String
        var password: String
        var code: String
        var deviceIdentifier: String
        var probeBundleID: String
    }

    var loginResult: SessionRefreshResult?
    var refreshResult: SessionRefreshResult?
    var reauthenticateResult: SessionRefreshResult?
    var loginRequests: [LoginRequest] = []

    init(
        loginResult: SessionRefreshResult? = nil,
        refreshResult: SessionRefreshResult? = nil,
        reauthenticateResult: SessionRefreshResult? = nil
    ) {
        self.loginResult = loginResult
        self.refreshResult = refreshResult
        self.reauthenticateResult = reauthenticateResult
    }

    func login(
        email: String,
        password: String,
        code: String,
        deviceIdentifier: String,
        probeBundleID: String
    ) async throws -> SessionRefreshResult {
        loginRequests.append(LoginRequest(
            email: email,
            password: password,
            code: code,
            deviceIdentifier: deviceIdentifier,
            probeBundleID: probeBundleID
        ))
        return try requiredResult(loginResult, fallback: .unknown("Missing login result"))
    }

    func reauthenticate(
        meta: StoredAccountMeta,
        secret: StoredAccountSecret,
        code: String
    ) async throws -> SessionRefreshResult {
        try requiredResult(reauthenticateResult, fallback: .unknown("Missing reauthenticate result"))
    }

    func refreshBalance(
        meta: StoredAccountMeta,
        secret: StoredAccountSecret
    ) async throws -> SessionRefreshResult {
        try requiredResult(refreshResult, fallback: .unknown("Missing refresh result"))
    }

    private func requiredResult(
        _ result: SessionRefreshResult?,
        fallback: MitoriError
    ) throws -> SessionRefreshResult {
        guard let result else { throw fallback }
        return result
    }
}
