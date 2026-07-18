import Foundation
import Security

protocol SecretKeyValueStore {
    func data(for key: String) throws -> Data?
    func set(_ data: Data, for key: String) throws
    func removeValue(for key: String) throws
}

final class KeychainSecretBackend: SecretKeyValueStore {
    private let service: String

    init(service: String) {
        self.service = service
    }

    func data(for key: String) throws -> Data? {
        if let data = try copyData(matching: protectedQuery(for: key)) {
            try delete(matching: legacyQuery(for: key))
            return data
        }
        guard let legacyData = try copyData(matching: legacyQuery(for: key)) else {
            return nil
        }

        try set(legacyData, for: key)
        return legacyData
    }

    func set(_ data: Data, for key: String) throws {
        let query = protectedQuery(for: key)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw keychainError(updateStatus)
            }
        } else if status != errSecSuccess {
            throw keychainError(status)
        }

        guard try copyData(matching: query) == data else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(errSecDecode),
                userInfo: [NSLocalizedDescriptionKey: "Keychain write verification failed."]
            )
        }
        try delete(matching: legacyQuery(for: key))
    }

    func removeValue(for key: String) throws {
        try delete(matching: protectedQuery(for: key))
        try delete(matching: legacyQuery(for: key))
    }

    private func copyData(matching baseQuery: [String: Any]) throws -> Data? {
        var query = baseQuery
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

    private func delete(matching query: [String: Any]) throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(status)
        }
    }

    private func protectedQuery(for key: String) -> [String: Any] {
        var query = legacyQuery(for: key)
        query[kSecUseDataProtectionKeychain as String] = true
        return query
    }

    private func legacyQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: false,
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

func isKeychainInteractionNotAllowed(_ error: Error) -> Bool {
    let error = error as NSError
    return error.domain == NSOSStatusErrorDomain && error.code == Int(errSecInteractionNotAllowed)
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
