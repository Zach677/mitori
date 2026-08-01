import ApplePackage
import Foundation
import Security
import Testing

@testable import Mitori

struct AccountStoreTests {
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
}

struct BundledDocumentTests {
    @Test
    func loadsOpenSourceLicenses() {
        #expect(BundledDocument.openSourceLicenses.text().contains("## ApplePackage"))
    }
}

struct KeychainSecretBackendTests {
    @Test
    func roundTripsDataThroughRealKeychain() throws {
        let backend = KeychainSecretBackend(service: "dev.zach.mitori.tests.\(UUID().uuidString)")
        let key = "account.demo@example.com"
        defer { try? backend.removeValue(for: key) }

        #expect(try backend.data(for: key) == nil)

        try backend.set(Data("first".utf8), for: key)
        #expect(try backend.data(for: key) == Data("first".utf8))

        try backend.set(Data("second".utf8), for: key)
        #expect(try backend.data(for: key) == Data("second".utf8))

        try backend.removeValue(for: key)
        #expect(try backend.data(for: key) == nil)

        // Deleting a missing item must stay silent, not throw.
        try backend.removeValue(for: key)
    }

    @Test
    func roundTripsDataThroughFileBasedKeychain() throws {
        let backend = KeychainSecretBackend(
            service: "dev.zach.mitori.tests.\(UUID().uuidString)",
            usesDataProtectionKeychain: false
        )
        let key = "account.community@example.com"
        defer { try? backend.removeValue(for: key) }

        try backend.set(Data("community".utf8), for: key)
        #expect(try backend.data(for: key) == Data("community".utf8))

        try backend.removeValue(for: key)
        #expect(try backend.data(for: key) == nil)
    }

#if !MITORI_COMMUNITY_BUILD
    @Test
    func migratesLegacyItemToDataProtectionKeychain() throws {
        let service = "dev.zach.mitori.tests.\(UUID().uuidString)"
        let key = "account.legacy@example.com"
        let data = Data("legacy".utf8)
        let backend = KeychainSecretBackend(service: service)
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: false,
        ]
        let protectedQuery: [String: Any] = legacyQuery.merging([
            kSecUseDataProtectionKeychain as String: true,
        ]) { _, new in new }

        var legacyAttributes = legacyQuery
        legacyAttributes[kSecValueData as String] = data
        #expect(SecItemAdd(legacyAttributes as CFDictionary, nil) == errSecSuccess)
        defer {
            SecItemDelete(legacyQuery as CFDictionary)
            SecItemDelete(protectedQuery as CFDictionary)
        }

        #expect(try backend.data(for: key) == data)

        var protectedDataQuery = protectedQuery
        protectedDataQuery[kSecReturnData as String] = true
        protectedDataQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        #expect(SecItemCopyMatching(protectedDataQuery as CFDictionary, &result) == errSecSuccess)
        #expect(result as? Data == data)

        var legacyResult: AnyObject?
        #expect(SecItemCopyMatching(legacyQuery as CFDictionary, &legacyResult) == errSecItemNotFound)
    }

    @Test
    func protectedItemReadRemovesLegacyDuplicate() throws {
        let service = "dev.zach.mitori.tests.\(UUID().uuidString)"
        let key = "account.duplicate@example.com"
        let protectedData = Data("protected".utf8)
        let backend = KeychainSecretBackend(service: service)
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: false,
        ]
        let protectedQuery: [String: Any] = legacyQuery.merging([
            kSecUseDataProtectionKeychain as String: true,
        ]) { _, new in new }

        var legacyAttributes = legacyQuery
        legacyAttributes[kSecValueData as String] = Data("legacy".utf8)
        #expect(SecItemAdd(legacyAttributes as CFDictionary, nil) == errSecSuccess)

        var protectedAttributes = protectedQuery
        protectedAttributes[kSecValueData as String] = protectedData
        protectedAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #expect(SecItemAdd(protectedAttributes as CFDictionary, nil) == errSecSuccess)
        defer {
            SecItemDelete(legacyQuery as CFDictionary)
            SecItemDelete(protectedQuery as CFDictionary)
        }

        #expect(try backend.data(for: key) == protectedData)

        var legacyResult: AnyObject?
        #expect(SecItemCopyMatching(legacyQuery as CFDictionary, &legacyResult) == errSecItemNotFound)
    }
#endif
}

struct SecretStoreTests {
    @Test
    func roundTripsSecretsThroughInjectedBackend() async throws {
        let backend = InMemorySecretBackend()
        let store = SecretStore(backend: backend)
        let secret = StoredAccountSecret(account: sampleAccount())
        let accountID = "demo@example.com"

        try await store.save(secret, for: accountID)
        let restored = try await store.loadSecret(for: accountID)

        #expect(restored == secret)
    }

    @Test
    func decodesSecretWrittenByPreviousApplePackageBackedSchema() async throws {
        let account = sampleAccount(cookies: [Cookie(
            name: "session",
            value: "value",
            path: "/",
            domain: ".itunes.apple.com",
            httpOnly: true,
            secure: true
        )])
        let legacy = LegacyStoredAccountSecret(
            password: account.password,
            cookies: account.cookie,
            passwordToken: account.passwordToken,
            directoryServicesIdentifier: account.directoryServicesIdentifier,
            account: account
        )
        let backend = InMemorySecretBackend()
        try backend.set(
            JSONEncoder().encode(legacy),
            for: "account.\(account.email.lowercased())"
        )
        let store = SecretStore(backend: backend)

        let restored = try await store.loadSecret(for: account.email.lowercased())

        #expect(restored == StoredAccountSecret(account: account))
    }
}

@MainActor
struct RefreshSettingsStoreTests {
    @Test
    func defaultsToDisabledHourlyRefresh() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = RefreshSettingsStore(defaults: defaults)

        #expect(store.isAutoRefreshEnabled == false)
        #expect(store.autoRefreshInterval == RefreshSettingsStore.defaultInterval)
        #expect(store.isPersonalInformationHidden == false)
    }

    @Test
    func clampsIntervalToMinimum() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = RefreshSettingsStore(defaults: defaults)

        store.autoRefreshInterval = 60
        #expect(store.autoRefreshInterval == RefreshSettingsStore.minimumInterval)

        store.autoRefreshInterval = 2 * 60 * 60
        #expect(store.autoRefreshInterval == 2 * 60 * 60)

        // A too-short value written directly to defaults must also be clamped on read.
        defaults.set(120, forKey: "autoRefresh.interval")
        #expect(store.autoRefreshInterval == RefreshSettingsStore.minimumInterval)
    }

    @Test
    func persistsPersonalInformationVisibility() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = RefreshSettingsStore(defaults: defaults)
        store.isPersonalInformationHidden = true

        #expect(RefreshSettingsStore(defaults: defaults).isPersonalInformationHidden)
    }
}

struct AccountPresentationTests {
    @Test
    func hidesPersonalAccountIdentifiers() {
        let account = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF1234567890",
            probeBundleID: "com.example.probe"
        )
        let visible = AccountPresentation(
            account: account,
            accountIndex: 1,
            hidesPersonalInformation: false
        )

        let hidden = AccountPresentation(
            account: account,
            accountIndex: 1,
            hidesPersonalInformation: true
        )

        #expect(visible.name == account.displayName)
        #expect(visible.email == account.email)
        #expect(visible.windowTitle == account.displayName)
        #expect(visible.appleID == account.appleID)
        #expect(visible.deviceIdentifier == "ABCDEF123456…")
        #expect(hidden.name == "Account 2")
        #expect(hidden.email == nil)
        #expect(hidden.windowTitle == "Account Details")
        #expect(hidden.appleID == "Hidden")
        #expect(hidden.deviceIdentifier == "Hidden")
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

    @Test
    func onlyMapsFileBackedCocoaErrorsToStorage() {
        let fileError = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.fileWriteNoPermission.rawValue
        )
        let propertyListError = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.propertyListReadCorrupt.rawValue
        )

        guard case .storage = MitoriError.map(fileError) else {
            Issue.record("Expected a storage error for a file write failure.")
            return
        }
        guard case .unknown = MitoriError.map(propertyListError) else {
            Issue.record("Expected malformed external data to remain an unknown error.")
            return
        }
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
        #expect(snapshot.rawFieldPath == "songList[0].balance")
    }

    @Test
    func treatsEmptyCreditDisplayAsZeroAndIgnoresSentinelBalances() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: [
                "creditDisplay": "",
                "creditBalance": "1311811",
                "freeSongBalance": "1311811",
            ],
            format: .xml,
            options: 0
        )

        let snapshot = try BalanceParser.parse(plistData: data, source: .probe)

        #expect(snapshot.displayText == "0")
        #expect(snapshot.numericValue == 0)
        #expect(snapshot.rawFieldPath == "creditDisplay")
    }

    @Test
    func prefersStructuredBalanceOverEmptyCreditDisplay() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: [
                "creditDisplay": "",
                "balance": [
                    "display": "USD 4.20",
                    "amount": 4.20,
                    "currency": "USD",
                ],
            ],
            format: .xml,
            options: 0
        )

        let snapshot = try BalanceParser.parse(plistData: data, source: .probe)

        #expect(snapshot.displayText == "USD 4.20")
        #expect(snapshot.numericValue == Decimal(string: "4.2"))
        #expect(snapshot.rawFieldPath == "balance")
    }

    @Test
    func formatsBalanceForAccountRegion() {
        let snapshot = BalanceSnapshot(
            displayText: "12.34",
            numericValue: Decimal(string: "12.34"),
            currencyCode: nil,
            fetchedAt: Date(),
            source: .probe,
            rawFieldPath: "creditDisplay"
        )

        #expect(snapshot.localizedDisplayText(countryCode: "TR") == "₺12,34")
        #expect(snapshot.localizedDisplayText(countryCode: "US") == "$12.34")
    }

    @Test
    func preservesAppleCurrencyAndRawFallback() {
        var snapshot = BalanceSnapshot(
            displayText: "USD 12.34",
            numericValue: Decimal(string: "12.34"),
            currencyCode: "USD",
            fetchedAt: Date(),
            source: .probe,
            rawFieldPath: "creditDisplay"
        )

        #expect(snapshot.localizedDisplayText(countryCode: "TR") == "$12,34")

        snapshot.numericValue = nil
        #expect(snapshot.localizedDisplayText(countryCode: "TR") == "USD 12.34")
    }
}

private final class FixtureBundleToken {}

private enum FixtureLoader {
    static func data(named resourceName: String) throws -> Data {
        guard let url = Bundle(for: FixtureBundleToken.self).url(forResource: resourceName, withExtension: "plist") else {
            throw NSError(domain: "FixtureLoader", code: 404)
        }
        return try Data(contentsOf: url)
    }
}

func sampleAccount(cookies: [Cookie] = []) -> Account {
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

private struct LegacyStoredAccountSecret: Codable {
    var password: String
    var cookies: [Cookie]
    var passwordToken: String
    var directoryServicesIdentifier: String
    var account: Account
}
