import Foundation
import KeychainAccess

private let legacySecretStoreServiceName = ["dev", "zach", ["store", "peek"].joined(), "accounts"].joined(separator: ".")

protocol SecretKeyValueStore {
    func data(for key: String) throws -> Data?
    func set(_ data: Data, for key: String) throws
    func removeValue(for key: String) throws
}

final class KeychainSecretBackend: SecretKeyValueStore {
    private let keychain: Keychain

    init(service: String) {
        keychain = Keychain(service: service).synchronizable(false)
    }

    func data(for key: String) throws -> Data? {
        try keychain.getData(key)
    }

    func set(_ data: Data, for key: String) throws {
        try keychain.set(data, key: key)
    }

    func removeValue(for key: String) throws {
        try keychain.remove(key)
    }
}

final class InMemorySecretBackend: SecretKeyValueStore {
    private var storage: [String: Data] = [:]

    func data(for key: String) throws -> Data? {
        storage[key]
    }

    func set(_ data: Data, for key: String) throws {
        storage[key] = data
    }

    func removeValue(for key: String) throws {
        storage[key] = nil
    }
}

actor SecretStore {
    private let backend: any SecretKeyValueStore
    private let legacyBackend: (any SecretKeyValueStore)?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        service: String = "dev.zach.mitori.accounts",
        legacyService: String? = legacySecretStoreServiceName,
        backend: (any SecretKeyValueStore)? = nil,
        legacyBackend: (any SecretKeyValueStore)? = nil
    ) {
        self.backend = backend ?? KeychainSecretBackend(service: service)
        if let legacyBackend {
            self.legacyBackend = legacyBackend
        } else if backend == nil, let legacyService {
            self.legacyBackend = KeychainSecretBackend(service: legacyService)
        } else {
            self.legacyBackend = nil
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        decoder = JSONDecoder()
    }

    func loadSecret(for accountID: String) throws -> StoredAccountSecret? {
        let key = storageKey(for: accountID)

        if let data = try backend.data(for: key) {
            return try decodeSecret(from: data)
        }

        guard let legacyBackend,
              let legacyData = try legacyBackend.data(for: key)
        else {
            return nil
        }

        try backend.set(legacyData, for: key)
        return try decodeSecret(from: legacyData)
    }

    func save(_ secret: StoredAccountSecret, for accountID: String) throws {
        let data = try encoder.encode(secret)
        try backend.set(data, for: storageKey(for: accountID))
    }

    func deleteSecret(for accountID: String) throws {
        try backend.removeValue(for: storageKey(for: accountID))
    }

    private func storageKey(for accountID: String) -> String {
        "account.\(accountID)"
    }

    private func decodeSecret(from data: Data) throws -> StoredAccountSecret {
        try decoder.decode(StoredAccountSecret.self, from: data)
    }
}
