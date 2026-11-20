//
//  AccountRepository.swift
//  Mitori
//
//  Created by @Zach677 on 2026/07/18.
//

import Foundation

actor AccountRepository {
    private let accountStore: AccountStore
    private let secretStore: SecretStore
    private var lockedAccountIDs: Set<String> = []
    private var lockWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    init(accountStore: AccountStore, secretStore: SecretStore) {
        self.accountStore = accountStore
        self.secretStore = secretStore
    }

    func loadAccounts() async throws -> [StoredAccountMeta] {
        try await accountStore.loadAccounts()
    }

    func loadSecret(
        for accountID: String,
        allowsAuthenticationUI: Bool = true
    ) async throws -> StoredAccountSecret? {
        await acquireLock(for: accountID)
        defer { releaseLock(for: accountID) }
        return try await secretStore.loadSecret(
            for: accountID,
            allowsAuthenticationUI: allowsAuthenticationUI
        )
    }

    func updateMeta(
        id: String,
        transform: @Sendable (StoredAccountMeta) throws -> StoredAccountMeta
    ) async throws -> [StoredAccountMeta] {
        await acquireLock(for: id)
        defer { releaseLock(for: id) }

        let accounts = try await accountStore.loadAccounts()
        guard let current = accounts.first(where: { $0.id == id }) else {
            throw MitoriError.operationSuperseded
        }
        let updated = try transform(current)
        guard updated.id == id else {
            throw MitoriError.storage("Account metadata updates cannot change account identity.")
        }
        return try await accountStore.upsert(updated)
    }

    func commit(
        _ result: SessionRefreshResult,
        respectingCancellation: Bool = false,
        allowsAuthenticationUI: Bool = true
    ) async throws -> [StoredAccountMeta] {
        let accountID = result.meta.id
        await acquireLock(for: accountID)
        defer { releaseLock(for: accountID) }

        if respectingCancellation {
            try Task.checkCancellation()
        }
        let previousSecret: StoredAccountSecret?
        do {
            previousSecret = try await secretStore.loadSecret(
                for: accountID,
                allowsAuthenticationUI: allowsAuthenticationUI
            )
        } catch is DecodingError {
            // Undecodable data has nothing to restore. A Keychain read error still stops
            // the commit, because the stored secret can be good and a rollback would delete it.
            previousSecret = nil
        }
        guard respectingCancellation else {
            try await secretStore.save(
                result.secret,
                for: accountID,
                allowsAuthenticationUI: allowsAuthenticationUI
            )
            do {
                return try await accountStore.upsert(result.meta)
            } catch {
                try await restoreSecret(
                    previousSecret,
                    for: accountID,
                    after: error,
                    allowsAuthenticationUI: allowsAuthenticationUI
                )
                throw error
            }
        }

        let previousMeta = try await accountStore.loadAccounts().first(where: { $0.id == accountID })
        try Task.checkCancellation()
        var didSaveSecret = false
        var didUpsertMeta = false
        do {
            try await secretStore.save(
                result.secret,
                for: accountID,
                allowsAuthenticationUI: allowsAuthenticationUI
            )
            didSaveSecret = true
            try Task.checkCancellation()
            let accounts = try await accountStore.upsert(result.meta)
            didUpsertMeta = true
            try Task.checkCancellation()
            return accounts
        } catch {
            try await restoreCommit(
                previousMeta: didUpsertMeta ? previousMeta : nil,
                restoreMeta: didUpsertMeta,
                previousSecret: previousSecret,
                restoreSecret: didSaveSecret,
                for: accountID,
                after: error,
                allowsAuthenticationUI: allowsAuthenticationUI
            )
            throw error
        }
    }

    func deleteAccount(id: String) async throws -> [StoredAccountMeta] {
        await acquireLock(for: id)
        defer { releaseLock(for: id) }

        // An unreadable secret has nothing to restore and must not block deletion.
        let previousSecret = try? await secretStore.loadSecret(for: id)
        try await secretStore.deleteSecret(for: id)
        do {
            return try await accountStore.deleteAccount(id: id)
        } catch {
            try await restoreSecret(previousSecret, for: id, after: error)
            throw error
        }
    }

    private func restoreSecret(
        _ previousSecret: StoredAccountSecret?,
        for accountID: String,
        after originalError: Error,
        allowsAuthenticationUI: Bool = true
    ) async throws {
        do {
            if let previousSecret {
                try await secretStore.save(
                    previousSecret,
                    for: accountID,
                    allowsAuthenticationUI: allowsAuthenticationUI
                )
            } else {
                try await secretStore.deleteSecret(
                    for: accountID,
                    allowsAuthenticationUI: allowsAuthenticationUI
                )
            }
        } catch {
            throw MitoriError.storage(
                "\(originalError.localizedDescription) Secret recovery also failed: \(error.localizedDescription)"
            )
        }
    }

    private func restoreCommit(
        previousMeta: StoredAccountMeta?,
        restoreMeta: Bool,
        previousSecret: StoredAccountSecret?,
        restoreSecret: Bool,
        for accountID: String,
        after originalError: Error,
        allowsAuthenticationUI: Bool
    ) async throws {
        var recoveryErrors: [String] = []

        if restoreMeta {
            do {
                if let previousMeta {
                    try await accountStore.upsert(previousMeta)
                } else {
                    try await accountStore.deleteAccount(id: accountID)
                }
            } catch {
                recoveryErrors.append(error.localizedDescription)
            }
        }

        if restoreSecret {
            do {
                if let previousSecret {
                    try await secretStore.save(
                        previousSecret,
                        for: accountID,
                        allowsAuthenticationUI: allowsAuthenticationUI
                    )
                } else {
                    try await secretStore.deleteSecret(
                        for: accountID,
                        allowsAuthenticationUI: allowsAuthenticationUI
                    )
                }
            } catch {
                recoveryErrors.append(error.localizedDescription)
            }
        }

        guard recoveryErrors.isEmpty else {
            throw MitoriError.storage(
                "\(originalError.localizedDescription) Recovery also failed: \(recoveryErrors.joined(separator: " "))"
            )
        }
    }

    private func acquireLock(for accountID: String) async {
        if lockedAccountIDs.insert(accountID).inserted {
            return
        }

        await withCheckedContinuation { continuation in
            lockWaiters[accountID, default: []].append(continuation)
        }
    }

    private func releaseLock(for accountID: String) {
        guard var waiters = lockWaiters[accountID], !waiters.isEmpty else {
            lockedAccountIDs.remove(accountID)
            lockWaiters[accountID] = nil
            return
        }

        let next = waiters.removeFirst()
        lockWaiters[accountID] = waiters.isEmpty ? nil : waiters
        next.resume()
    }
}
