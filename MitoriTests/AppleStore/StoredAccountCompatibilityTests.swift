import Foundation
import Testing

@testable import Mitori

/// Data written before the ApplePackage port must decode the same with the local AppleStore types.
struct StoredAccountCompatibilityTests {
    @Test
    func storedAccountsAndSecretDecodeWithLocalTypes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FixtureLoader.data(named: "stored_accounts", withExtension: "json")
            .write(to: directory.appendingPathComponent("accounts.json"))

        let meta = try #require(try await AccountStore(baseDirectory: directory).loadAccounts().first)
        let secret = try JSONDecoder().decode(
            StoredAccountSecret.self,
            from: FixtureLoader.data(named: "stored_secret", withExtension: "json")
        )

        #expect(meta.id == "demo@example.com")
        #expect(meta.storefront == "143441")
        #expect(meta.pod == "25")
        #expect(meta.balanceSnapshot?.numericValue == Decimal(string: "12.34"))
        #expect(meta.balanceSnapshot?.source == .probe)
        #expect(meta.lastIssue?.kind == .network)

        let account = secret.restoredAccount(meta: meta)
        #expect(account.email == "Demo@example.com")
        #expect(account.store == "143441")
        #expect(account.pod == "25")
        let cookie = try #require(account.cookie.first)
        #expect(cookie.name == "session")
        #expect(cookie.domain == ".apple.com")
        #expect(cookie.expiresAt == 1_800_000_000)
        #expect(cookie.httpOnly && cookie.secure)

        #expect(StoredAccountSecret(account: account) == secret)
        #expect(Configuration.countryCode(for: account.store) == meta.countryCode)
    }
}
