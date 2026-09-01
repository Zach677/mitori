import Foundation
import LocalAuthentication
import Security

protocol SecretKeyValueStore {
    func data(for key: String, allowsAuthenticationUI: Bool) throws -> Data?
    func set(_ data: Data, for key: String, allowsAuthenticationUI: Bool) throws
    func removeValue(for key: String, allowsAuthenticationUI: Bool) throws
}

final class KeychainSecretBackend: SecretKeyValueStore {
    private let service: String
    private let usesDataProtectionKeychain: Bool

    init(service: String, usesDataProtectionKeychain: Bool? = nil) {
        self.service = service
        self.usesDataProtectionKeychain = usesDataProtectionKeychain ?? Self.defaultUsesDataProtectionKeychain
    }

    func data(for key: String, allowsAuthenticationUI: Bool = true) throws -> Data? {
        guard usesDataProtectionKeychain else {
            return try copyData(matching: legacyQuery(for: key), allowsAuthenticationUI: allowsAuthenticationUI)
        }

        if let data = try copyData(
            matching: protectedQuery(for: key),
            allowsAuthenticationUI: allowsAuthenticationUI
        ) {
            try delete(
                matching: legacyQuery(for: key),
                allowsAuthenticationUI: allowsAuthenticationUI
            )
            return data
        }
        guard let legacyData = try copyData(
            matching: legacyQuery(for: key),
            allowsAuthenticationUI: allowsAuthenticationUI
        ) else {
            return nil
        }

        try set(legacyData, for: key, allowsAuthenticationUI: allowsAuthenticationUI)
        return legacyData
    }

    func set(
        _ data: Data,
        for key: String,
        allowsAuthenticationUI: Bool = true
    ) throws {
        let baseQuery = usesDataProtectionKeychain ? protectedQuery(for: key) : legacyQuery(for: key)
        let query = authenticationQuery(baseQuery, allowsAuthenticationUI: allowsAuthenticationUI)
        var attributes = query
        attributes[kSecValueData as String] = data
        if usesDataProtectionKeychain {
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            var update: [String: Any] = [kSecValueData as String: data]
            if usesDataProtectionKeychain {
                update[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            }
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw keychainError(updateStatus)
            }
        } else if status != errSecSuccess {
            throw keychainError(status)
        }

        guard try copyData(
            matching: baseQuery,
            allowsAuthenticationUI: allowsAuthenticationUI
        ) == data else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(errSecDecode),
                userInfo: [NSLocalizedDescriptionKey: "Keychain write verification failed."]
            )
        }
        if usesDataProtectionKeychain {
            try delete(
                matching: legacyQuery(for: key),
                allowsAuthenticationUI: allowsAuthenticationUI
            )
        }
    }

    func removeValue(for key: String, allowsAuthenticationUI: Bool = true) throws {
        if usesDataProtectionKeychain {
            try delete(
                matching: protectedQuery(for: key),
                allowsAuthenticationUI: allowsAuthenticationUI
            )
        }
        try delete(
            matching: legacyQuery(for: key),
            allowsAuthenticationUI: allowsAuthenticationUI
        )
    }

    private static var defaultUsesDataProtectionKeychain: Bool {
#if MITORI_COMMUNITY_BUILD
        false
#else
        true
#endif
    }

    private func copyData(
        matching baseQuery: [String: Any],
        allowsAuthenticationUI: Bool = true
    ) throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query = authenticationQuery(query, allowsAuthenticationUI: allowsAuthenticationUI)

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

    private func delete(
        matching baseQuery: [String: Any],
        allowsAuthenticationUI: Bool = true
    ) throws {
        let query = authenticationQuery(baseQuery, allowsAuthenticationUI: allowsAuthenticationUI)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(status)
        }
    }

    private func authenticationQuery(
        _ baseQuery: [String: Any],
        allowsAuthenticationUI: Bool
    ) -> [String: Any] {
        guard !allowsAuthenticationUI else { return baseQuery }
        var query = baseQuery
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        return query
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
            kSecAttrSynchronizable as String: false,
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

    func data(for key: String, allowsAuthenticationUI _: Bool = true) throws -> Data? {
        storage[key]
    }

    func set(_ data: Data, for key: String, allowsAuthenticationUI _: Bool = true) throws {
        storage[key] = data
    }

    func removeValue(for key: String, allowsAuthenticationUI _: Bool = true) throws {
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

    func loadSecret(
        for accountID: String,
        allowsAuthenticationUI: Bool = true
    ) throws -> StoredAccountSecret? {
        guard let data = try backend.data(
            for: storageKey(for: accountID),
            allowsAuthenticationUI: allowsAuthenticationUI
        ) else {
            return nil
        }
        return try decodeSecret(from: data)
    }

    func save(
        _ secret: StoredAccountSecret,
        for accountID: String,
        allowsAuthenticationUI: Bool = true
    ) throws {
        let data = try encoder.encode(secret)
        try backend.set(
            data,
            for: storageKey(for: accountID),
            allowsAuthenticationUI: allowsAuthenticationUI
        )
    }

    func deleteSecret(
        for accountID: String,
        allowsAuthenticationUI: Bool = true
    ) throws {
        try backend.removeValue(
            for: storageKey(for: accountID),
            allowsAuthenticationUI: allowsAuthenticationUI
        )
    }

    private func storageKey(for accountID: String) -> String {
        "account.\(accountID)"
    }

    private func decodeSecret(from data: Data) throws -> StoredAccountSecret {
        try decoder.decode(StoredAccountSecret.self, from: data)
    }
}
