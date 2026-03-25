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

@MainActor
struct LaunchHaloPresenterTests {
    @Test
    func presentsOnlyOncePerProcess() {
        let display = LaunchHaloDisplaySpy()
        let presenter = LaunchHaloPresenter(displaying: display)

        presenter.presentIfNeeded()
        presenter.presentIfNeeded()

        #expect(display.presentCount == 1)
    }
}

private final class FixtureBundleToken: NSObject {}

@MainActor
private final class LaunchHaloDisplaySpy: LaunchHaloDisplaying {
    private(set) var presentCount = 0

    func showLaunchHalo() {
        presentCount += 1
    }
}

private enum FixtureLoader {
    static func data(named resourceName: String) throws -> Data {
        let bundle = Bundle(for: FixtureBundleToken.self)
        let urls = [
            bundle.url(forResource: resourceName, withExtension: "plist"),
            bundle.url(forResource: resourceName, withExtension: "plist", subdirectory: "Fixtures"),
        ]

        guard let url = urls.compactMap({ $0 }).first else {
            throw NSError(domain: "FixtureLoader", code: 404)
        }

        return try Data(contentsOf: url)
    }
}

private func sampleAccount() -> Account {
    Account(
        email: "demo@example.com",
        password: "password",
        appleId: "demo@example.com",
        store: "143441",
        firstName: "Demo",
        lastName: "User",
        passwordToken: "token",
        directoryServicesIdentifier: "1234567890",
        cookie: [],
        pod: "25"
    )
}
