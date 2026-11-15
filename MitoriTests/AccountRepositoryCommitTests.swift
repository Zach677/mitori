import Foundation
import Security
import Testing

@testable import Mitori

struct AccountRepositoryCommitTests {
    @Test
    func commitReplacesUndecodableStoredSecret() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let backend = InMemorySecretBackend()
        let secretStore = SecretStore(backend: backend)
        let repository = AccountRepository(
            accountStore: AccountStore(baseDirectory: tempDirectory),
            secretStore: secretStore
        )
        let result = sampleResult()
        try backend.set(Data("not a secret".utf8), for: "account.\(result.meta.id)", allowsAuthenticationUI: false)

        let accounts = try await repository.commit(result)

        #expect(accounts.map(\.id) == [result.meta.id])
        #expect(try await secretStore.loadSecret(for: result.meta.id) == result.secret)
    }

    @Test
    func commitStopsWhenStoredSecretCannotBeRead() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let backend = ReadFailingSecretBackend()
        let repository = AccountRepository(
            accountStore: accountStore,
            secretStore: SecretStore(backend: backend)
        )
        let result = sampleResult()
        let storedData = Data("stored secret".utf8)
        backend.storage["account.\(result.meta.id)"] = storedData

        await #expect(throws: (any Error).self) {
            try await repository.commit(result)
        }

        #expect(backend.storage == ["account.\(result.meta.id)": storedData])
        #expect(try await accountStore.loadAccounts().isEmpty)
    }

    private func sampleResult() -> SessionRefreshResult {
        SessionRefreshResult(
            meta: StoredAccountMeta(
                account: sampleAccount(),
                deviceIdentifier: "ABCDEF123456",
                probeBundleID: "com.example.probe"
            ),
            secret: StoredAccountSecret(account: sampleAccount())
        )
    }
}

private final class ReadFailingSecretBackend: SecretKeyValueStore, @unchecked Sendable {
    var storage: [String: Data] = [:]

    func data(for _: String, allowsAuthenticationUI _: Bool) throws -> Data? {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecInteractionNotAllowed))
    }

    func set(_ data: Data, for key: String, allowsAuthenticationUI _: Bool) throws {
        storage[key] = data
    }

    func removeValue(for key: String, allowsAuthenticationUI _: Bool) throws {
        storage[key] = nil
    }
}
