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

    func loadSecret(for accountID: String) async throws -> StoredAccountSecret? {
        await acquireLock(for: accountID)
        defer { releaseLock(for: accountID) }
        return try await secretStore.loadSecret(for: accountID)
    }

    func upsert(_ meta: StoredAccountMeta) async throws -> [StoredAccountMeta] {
        await acquireLock(for: meta.id)
        defer { releaseLock(for: meta.id) }
        return try await accountStore.upsert(meta)
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
        respectingCancellation: Bool = false
    ) async throws -> [StoredAccountMeta] {
        let accountID = result.meta.id
        await acquireLock(for: accountID)
        defer { releaseLock(for: accountID) }

        if respectingCancellation {
            try Task.checkCancellation()
        }
        let previousSecret = try await secretStore.loadSecret(for: accountID)
        guard respectingCancellation else {
            try await secretStore.save(result.secret, for: accountID)
            do {
                return try await accountStore.upsert(result.meta)
            } catch {
                try await restoreSecret(previousSecret, for: accountID, after: error)
                throw error
            }
        }

        let previousMeta = try await accountStore.loadAccounts().first(where: { $0.id == accountID })
        try Task.checkCancellation()
        do {
            try await secretStore.save(result.secret, for: accountID)
            try Task.checkCancellation()
            let accounts = try await accountStore.upsert(result.meta)
            try Task.checkCancellation()
            return accounts
        } catch {
            try await restoreCommit(
                previousMeta: previousMeta,
                previousSecret: previousSecret,
                for: accountID,
                after: error
            )
            throw error
        }
    }

    func deleteAccount(id: String) async throws -> [StoredAccountMeta] {
        await acquireLock(for: id)
        defer { releaseLock(for: id) }

        let previousSecret = try await secretStore.loadSecret(for: id)
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
        after originalError: Error
    ) async throws {
        do {
            if let previousSecret {
                try await secretStore.save(previousSecret, for: accountID)
            } else {
                try await secretStore.deleteSecret(for: accountID)
            }
        } catch {
            throw MitoriError.storage(
                "\(originalError.localizedDescription) Secret recovery also failed: \(error.localizedDescription)"
            )
        }
    }

    private func restoreCommit(
        previousMeta: StoredAccountMeta?,
        previousSecret: StoredAccountSecret?,
        for accountID: String,
        after originalError: Error
    ) async throws {
        var recoveryErrors: [String] = []

        do {
            if let previousMeta {
                try await accountStore.upsert(previousMeta)
            } else {
                try await accountStore.deleteAccount(id: accountID)
            }
        } catch {
            recoveryErrors.append(error.localizedDescription)
        }

        do {
            if let previousSecret {
                try await secretStore.save(previousSecret, for: accountID)
            } else {
                try await secretStore.deleteSecret(for: accountID)
            }
        } catch {
            recoveryErrors.append(error.localizedDescription)
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
