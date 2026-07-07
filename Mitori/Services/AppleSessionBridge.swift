import ApplePackage
import Foundation

protocol AppleSessionBridging {
    func login(
        email: String,
        password: String,
        code: String,
        deviceIdentifier: String,
        probeBundleID: String
    ) async throws -> SessionRefreshResult

    func reauthenticate(
        meta: StoredAccountMeta,
        secret: StoredAccountSecret,
        code: String
    ) async throws -> SessionRefreshResult

    func refreshBalance(
        meta: StoredAccountMeta,
        secret: StoredAccountSecret
    ) async throws -> SessionRefreshResult
}

actor AppleSessionBridge: AppleSessionBridging {
    private let balanceService: BalanceService

    init(balanceService: BalanceService = BalanceService()) {
        self.balanceService = balanceService
    }

    func login(
        email: String,
        password: String,
        code: String,
        deviceIdentifier: String,
        probeBundleID: String
    ) async throws -> SessionRefreshResult {
        try await authenticate(
            email: email,
            password: password,
            code: code,
            cookies: [],
            deviceIdentifier: deviceIdentifier,
            probeBundleID: probeBundleID,
            existing: nil
        )
    }

    func reauthenticate(
        meta: StoredAccountMeta,
        secret: StoredAccountSecret,
        code: String = ""
    ) async throws -> SessionRefreshResult {
        try await authenticate(
            email: meta.email,
            password: secret.password,
            code: code,
            cookies: secret.cookies,
            deviceIdentifier: meta.deviceIdentifier,
            probeBundleID: meta.probeBundleID,
            existing: meta
        )
    }

    func refreshBalance(
        meta: StoredAccountMeta,
        secret: StoredAccountSecret
    ) async throws -> SessionRefreshResult {
        do {
            return try await refreshBalanceOnly(meta: meta, secret: secret)
        } catch {
            let mappedError = MitoriError.map(error)
            if case .sessionExpired = mappedError {
                return try await reauthenticate(meta: meta, secret: secret)
            }
            throw mappedError
        }
    }

    private func authenticate(
        email: String,
        password: String,
        code: String,
        cookies: [Cookie],
        deviceIdentifier: String,
        probeBundleID: String,
        existing: StoredAccountMeta?
    ) async throws -> SessionRefreshResult {
        let authenticatedAccount = try await Authenticator.authenticate(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            code: code.trimmingCharacters(in: .whitespacesAndNewlines),
            cookies: cookies,
            deviceIdentifier: deviceIdentifier
        )

        var meta = StoredAccountMeta(
            account: authenticatedAccount,
            deviceIdentifier: deviceIdentifier,
            probeBundleID: probeBundleID,
            balanceSnapshot: existing?.balanceSnapshot,
            lastIssue: nil,
            lastRefreshAt: existing?.lastRefreshAt,
            nextEligibleRefreshAt: nil,
            consecutiveFailureCount: 0
        )
        let secret = StoredAccountSecret(account: authenticatedAccount)

        do {
            let balanceResult = try await balanceService.refreshBalance(for: meta, secret: secret)
            meta = updatedMeta(from: meta, account: balanceResult.secret.account, snapshot: balanceResult.snapshot)
            return SessionRefreshResult(meta: meta, secret: balanceResult.secret)
        } catch {
            meta.lastIssue = MitoriError.map(error).refreshIssue()
            return SessionRefreshResult(meta: meta, secret: secret)
        }
    }

    private func refreshBalanceOnly(
        meta: StoredAccountMeta,
        secret: StoredAccountSecret
    ) async throws -> SessionRefreshResult {
        let balanceResult = try await balanceService.refreshBalance(for: meta, secret: secret)
        let updatedMeta = updatedMeta(from: meta, account: balanceResult.secret.account, snapshot: balanceResult.snapshot)
        return SessionRefreshResult(meta: updatedMeta, secret: balanceResult.secret)
    }

    private func updatedMeta(
        from meta: StoredAccountMeta,
        account: Account,
        snapshot: BalanceSnapshot
    ) -> StoredAccountMeta {
        var updated = meta
        updated.appleID = account.appleId
        updated.firstName = account.firstName
        updated.lastName = account.lastName
        updated.storefront = account.store
        updated.countryCode = Configuration.countryCode(for: account.store)
        updated.pod = account.pod
        updated.balanceSnapshot = snapshot
        updated.lastRefreshAt = snapshot.fetchedAt
        updated.lastIssue = nil
        updated.nextEligibleRefreshAt = nil
        updated.consecutiveFailureCount = 0
        return updated
    }
}
