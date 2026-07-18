import ApplePackage
import Foundation

protocol AppleSessionBridging: Sendable {
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
            cookies: secret.cookies.map(\.appleCookie),
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
            let mappedError = MitoriError.mapApplePackage(error)
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
        let authenticatedAccount: Account
        do {
            authenticatedAccount = try await Authenticator.authenticate(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                code: code.trimmingCharacters(in: .whitespacesAndNewlines),
                cookies: cookies,
                deviceIdentifier: deviceIdentifier
            )
        } catch {
            throw MitoriError.mapApplePackage(error)
        }

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
            meta = updatedMeta(from: meta, account: balanceResult.account, snapshot: balanceResult.snapshot)
            return SessionRefreshResult(meta: meta, secret: StoredAccountSecret(account: balanceResult.account))
        } catch {
            meta.lastIssue = MitoriError.mapApplePackage(error).refreshIssue()
            return SessionRefreshResult(meta: meta, secret: secret)
        }
    }

    private func refreshBalanceOnly(
        meta: StoredAccountMeta,
        secret: StoredAccountSecret
    ) async throws -> SessionRefreshResult {
        let balanceResult = try await balanceService.refreshBalance(for: meta, secret: secret)
        let updatedMeta = updatedMeta(from: meta, account: balanceResult.account, snapshot: balanceResult.snapshot)
        return SessionRefreshResult(
            meta: updatedMeta,
            secret: StoredAccountSecret(account: balanceResult.account)
        )
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

private extension MitoriError {
    static func mapApplePackage(_ error: Error) -> MitoriError {
        if let error = error as? ApplePackageError {
            switch error {
            case .licenseRequired:
                return .probeAppNotOwned
            }
        }
        return map(error)
    }
}

extension StoredAccountMeta {
    init(
        account: Account,
        deviceIdentifier: String,
        probeBundleID: String,
        balanceSnapshot: BalanceSnapshot? = nil,
        lastIssue: RefreshIssue? = nil,
        lastRefreshAt: Date? = nil,
        nextEligibleRefreshAt: Date? = nil,
        consecutiveFailureCount: Int = 0
    ) {
        email = account.email
        appleID = account.appleId
        firstName = account.firstName
        lastName = account.lastName
        storefront = account.store
        countryCode = Configuration.countryCode(for: account.store)
        pod = account.pod
        self.deviceIdentifier = deviceIdentifier
        self.probeBundleID = probeBundleID
        self.balanceSnapshot = balanceSnapshot
        self.lastIssue = lastIssue
        self.lastRefreshAt = lastRefreshAt
        self.nextEligibleRefreshAt = nextEligibleRefreshAt
        self.consecutiveFailureCount = consecutiveFailureCount
    }
}

extension StoredAccountSecret {
    init(account: Account) {
        password = account.password
        cookies = account.cookie.map(StoredCookie.init)
        passwordToken = account.passwordToken
        directoryServicesIdentifier = account.directoryServicesIdentifier
    }

    func restoredAccount(meta: StoredAccountMeta) -> Account {
        Account(
            email: meta.email,
            password: password,
            appleId: meta.appleID,
            store: meta.storefront,
            firstName: meta.firstName,
            lastName: meta.lastName,
            passwordToken: passwordToken,
            directoryServicesIdentifier: directoryServicesIdentifier,
            cookie: cookies.map(\.appleCookie),
            pod: meta.pod
        )
    }
}

private extension StoredCookie {
    init(_ cookie: Cookie) {
        name = cookie.name
        value = cookie.value
        path = cookie.path
        domain = cookie.domain
        expiresAt = cookie.expiresAt
        httpOnly = cookie.httpOnly
        secure = cookie.secure
    }

    var appleCookie: Cookie {
        Cookie(
            name: name,
            value: value,
            path: path,
            domain: domain,
            expiresAt: expiresAt,
            httpOnly: httpOnly,
            secure: secure
        )
    }
}
