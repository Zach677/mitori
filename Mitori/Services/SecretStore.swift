import Foundation
import Security

protocol SecretKeyValueStore {
    func data(for key: String) throws -> Data?
    func set(_ data: Data, for key: String) throws
    func removeValue(for key: String) throws
}

// Items are standard kSecClassGenericPassword entries keyed by
// service + account, so secrets written by the previous KeychainAccess
// backend stay readable without migration.
final class KeychainSecretBackend: SecretKeyValueStore {
    private let service: String

    init(service: String) {
        self.service = service
    }

    func data(for key: String) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw keychainError(status)
        }
    }

    func set(_ data: Data, for key: String) throws {
        var attributes = baseQuery(for: key)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery(for: key) as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw keychainError(updateStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            throw keychainError(status)
        }
    }

    func removeValue(for key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    private func keychainError(_ status: OSStatus) -> Error {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        return NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: message]
        )
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
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        service: String = "dev.zach.mitori.accounts",
        backend: (any SecretKeyValueStore)? = nil
    ) {
        self.backend = backend ?? KeychainSecretBackend(service: service)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        decoder = JSONDecoder()
    }

    func loadSecret(for accountID: String) throws -> StoredAccountSecret? {
        guard let data = try backend.data(for: storageKey(for: accountID)) else {
            return nil
        }
        return try decodeSecret(from: data)
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
