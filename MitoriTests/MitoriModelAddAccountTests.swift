import Foundation
import Testing

@testable import Mitori

@MainActor
struct MitoriModelAddAccountTests {
    @Test
    func reAddingAnAccountPassesItsHistoryAndKeepsTheStoredProbe() async throws {
        let context = try await makeExistingAccountContext()

        _ = try await context.addAccount(probeBundleID: " ")

        let request = try #require(context.bridge.loginRequests.first)
        #expect(request.existing == context.existing)
        #expect(request.probeBundleID == "com.example.probe")
        let stored = try await context.accountStore.loadAccounts()
        #expect(stored.count == 1)
        #expect(try await context.secretStore.loadSecret(for: context.existing.id)?.password == "new-password")
    }

    @Test
    func reAddingAnAccountWithANewProbeReplacesIt() async throws {
        let context = try await makeExistingAccountContext()

        _ = try await context.addAccount(probeBundleID: "com.example.new-probe")

        #expect(context.bridge.loginRequests.first?.probeBundleID == "com.example.new-probe")
    }

    @Test
    func failedTwoFactorReAddLeavesTheAccountUnchanged() async throws {
        let context = try await makeExistingAccountContext()
        context.bridge.loginError = MitoriError.twoFactorCodeRequired

        await #expect(throws: MitoriError.twoFactorCodeRequired) {
            _ = try await context.addAccount(probeBundleID: "")
        }

        #expect(try await context.accountStore.loadAccounts() == [context.existing])
        #expect(try await context.secretStore.loadSecret(for: context.existing.id) == context.existingSecret)
    }

    @Test
    func failedSecretSaveLeavesTheAccountUnchanged() async throws {
        let context = try await makeExistingAccountContext()
        context.secretBackend.failsWrites = true

        await #expect(throws: (any Error).self) {
            _ = try await context.addAccount(probeBundleID: "")
        }

        #expect(try await context.accountStore.loadAccounts() == [context.existing])
        #expect(try await context.secretStore.loadSecret(for: context.existing.id) == context.existingSecret)
    }

    private struct ExistingAccountContext {
        var model: MitoriModel
        var bridge: SessionBridgeStub
        var accountStore: AccountStore
        var secretStore: SecretStore
        var secretBackend: WriteFailingSecretBackend
        var existing: StoredAccountMeta
        var existingSecret: StoredAccountSecret

        func addAccount(probeBundleID: String) async throws -> String {
            try await model.addAccount(
                email: "Demo@example.com",
                password: "new-password",
                code: "",
                deviceIdentifier: "ABCDEF123456",
                probeBundleID: probeBundleID
            )
        }
    }

    private func makeExistingAccountContext() async throws -> ExistingAccountContext {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let secretBackend = WriteFailingSecretBackend()
        let secretStore = SecretStore(backend: secretBackend)
        let fetchedAt = Date(timeIntervalSince1970: 1_743_166_800)
        let existing = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe",
            balanceSnapshot: BalanceSnapshot(
                displayText: "$12.34",
                numericValue: Decimal(string: "12.34"),
                currencyCode: nil,
                fetchedAt: fetchedAt,
                source: .probe,
                rawFieldPath: "creditDisplay"
            ),
            lastRefreshAt: fetchedAt
        )
        let existingSecret = StoredAccountSecret(account: sampleAccount())
        _ = try await accountStore.upsert(existing)
        try await secretStore.save(existingSecret, for: existing.id)

        var newAccount = sampleAccount()
        newAccount.password = "new-password"
        let bridge = SessionBridgeStub(loginResult: SessionRefreshResult(
            meta: existing,
            secret: StoredAccountSecret(account: newAccount)
        ))
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: secretStore,
            sessionBridge: bridge
        )
        return ExistingAccountContext(
            model: model,
            bridge: bridge,
            accountStore: accountStore,
            secretStore: secretStore,
            secretBackend: secretBackend,
            existing: existing,
            existingSecret: existingSecret
        )
    }
}

private final class WriteFailingSecretBackend: SecretKeyValueStore {
    private var storage: [String: Data] = [:]
    var failsWrites = false

    func data(for key: String, allowsAuthenticationUI _: Bool) throws -> Data? {
        storage[key]
    }

    func set(_ data: Data, for key: String, allowsAuthenticationUI _: Bool) throws {
        if failsWrites {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecNotAvailable))
        }
        storage[key] = data
    }

    func removeValue(for key: String, allowsAuthenticationUI _: Bool) throws {
        storage[key] = nil
    }
}
