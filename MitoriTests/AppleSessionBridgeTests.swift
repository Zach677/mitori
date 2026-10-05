import ApplePackage
import Foundation
import Testing

@testable import Mitori

struct AppleSessionBridgeTests {
    @Test
    func loginWithoutProbeKeepsAuthBalanceAndSkipsProbe() async throws {
        let authenticator = AppleAuthenticatorStub(
            result: try authenticationResult(fixture: "auth_success_balance")
        )
        let balanceService = BalanceRefreshingStub()
        let bridge = AppleSessionBridge(
            authenticator: authenticator,
            balanceService: balanceService
        )

        let result = try await bridge.login(
            email: "demo@example.com",
            password: "password",
            code: "",
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: ""
        )

        #expect(result.meta.lastIssue == nil)
        #expect(result.meta.needsProbeBundleID)
        #expect(result.meta.balanceSnapshot?.source == .authentication)
        #expect(result.meta.balanceSnapshot?.numericValue == Decimal(string: "24.90"))
        #expect(authenticator.callCount == 1)
        #expect(await balanceService.callCount == 0)
    }

    @Test
    func loginWithoutProbeDoesNotRecordMissingProbeIssue() async throws {
        let authenticator = AppleAuthenticatorStub(
            result: AuthenticationResult(
                account: sampleAccount(),
                responsePlist: Data()
            )
        )
        let balanceService = BalanceRefreshingStub()
        let bridge = AppleSessionBridge(
            authenticator: authenticator,
            balanceService: balanceService
        )

        let result = try await bridge.login(
            email: "demo@example.com",
            password: "password",
            code: "",
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: ""
        )

        #expect(result.meta.lastIssue == nil)
        #expect(result.meta.balanceSnapshot == nil)
        #expect(await balanceService.callCount == 0)
    }

    @Test
    func loginWithEmptyAuthCreditHasNoBalanceAndNoIssue() async throws {
        let authenticator = AppleAuthenticatorStub(
            result: AuthenticationResult(
                account: sampleAccount(),
                responsePlist: try PropertyListSerialization.data(
                    fromPropertyList: ["creditDisplay": "", "accountInfo": ["creditDisplay": " "]],
                    format: .xml,
                    options: 0
                )
            )
        )
        let bridge = AppleSessionBridge(
            authenticator: authenticator,
            balanceService: BalanceRefreshingStub()
        )

        let result = try await bridge.login(
            email: "demo@example.com",
            password: "password",
            code: "",
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: ""
        )

        #expect(result.meta.balanceSnapshot == nil)
        #expect(result.meta.lastRefreshAt == nil)
        #expect(result.meta.lastIssue == nil)
    }

    @Test
    func reauthenticationWithoutAuthBalanceKeepsExistingSnapshot() async throws {
        let authenticator = AppleAuthenticatorStub(
            result: AuthenticationResult(
                account: sampleAccount(),
                responsePlist: try PropertyListSerialization.data(
                    fromPropertyList: ["creditDisplay": ""],
                    format: .xml,
                    options: 0
                )
            )
        )
        let bridge = AppleSessionBridge(
            authenticator: authenticator,
            balanceService: BalanceRefreshingStub()
        )
        let fetchedAt = Date(timeIntervalSince1970: 1_743_166_800)
        let snapshot = BalanceSnapshot(
            displayText: "$12.34",
            numericValue: Decimal(string: "12.34"),
            currencyCode: nil,
            fetchedAt: fetchedAt,
            source: .probe,
            rawFieldPath: "creditDisplay"
        )
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "",
            balanceSnapshot: snapshot,
            lastRefreshAt: fetchedAt
        )

        let result = try await bridge.reauthenticate(
            meta: meta,
            secret: StoredAccountSecret(account: sampleAccount()),
            code: ""
        )

        #expect(result.meta.balanceSnapshot == snapshot)
        #expect(result.meta.lastRefreshAt == fetchedAt)
        #expect(result.meta.lastIssue == nil)
    }

    @Test
    func loginWithProbePrefersProbeBalance() async throws {
        let authenticator = AppleAuthenticatorStub(
            result: try authenticationResult(fixture: "auth_success_balance")
        )
        let probeSnapshot = try BalanceParser.parse(
            plistData: FixtureLoader.data(named: "probe_success_balance"),
            source: .probe
        )
        let balanceService = BalanceRefreshingStub(
            result: BalanceResult(snapshot: probeSnapshot, account: sampleAccount())
        )
        let bridge = AppleSessionBridge(
            authenticator: authenticator,
            balanceService: balanceService
        )

        let result = try await bridge.login(
            email: "demo@example.com",
            password: "password",
            code: "",
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )

        #expect(result.meta.lastIssue == nil)
        #expect(result.meta.balanceSnapshot?.source == .probe)
        #expect(result.meta.balanceSnapshot?.numericValue == Decimal(string: "88.00"))
        #expect(await balanceService.callCount == 1)
    }

    @Test
    func loginKeepsAuthBalanceWhenConfiguredProbeIsNotOwned() async throws {
        let authenticator = AppleAuthenticatorStub(
            result: try authenticationResult(fixture: "auth_success_balance")
        )
        let balanceService = BalanceRefreshingStub(error: MitoriError.probeAppNotOwned)
        let bridge = AppleSessionBridge(
            authenticator: authenticator,
            balanceService: balanceService
        )

        let result = try await bridge.login(
            email: "demo@example.com",
            password: "password",
            code: "",
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )

        #expect(result.meta.balanceSnapshot?.source == .authentication)
        #expect(result.meta.lastIssue?.kind == .balanceUnavailable)
        #expect(await balanceService.callCount == 1)
    }

    @Test
    func refreshWithoutProbeReauthenticatesInsteadOfProbing() async throws {
        let authenticator = AppleAuthenticatorStub(
            result: try authenticationResult(fixture: "auth_success_balance")
        )
        let balanceService = BalanceRefreshingStub()
        let bridge = AppleSessionBridge(
            authenticator: authenticator,
            balanceService: balanceService
        )
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: ""
        )

        let result = try await bridge.refreshBalance(
            meta: meta,
            secret: StoredAccountSecret(account: sampleAccount())
        )

        #expect(result.meta.lastIssue == nil)
        #expect(result.meta.balanceSnapshot?.source == .authentication)
        #expect(authenticator.callCount == 1)
        #expect(await balanceService.callCount == 0)
    }

    @Test
    func refreshFallsBackToReauthenticationWhenProbeSessionExpired() async throws {
        let authenticator = AppleAuthenticatorStub(
            result: try authenticationResult(fixture: "auth_success_balance")
        )
        let balanceService = BalanceRefreshingStub(error: MitoriError.sessionExpired)
        let bridge = AppleSessionBridge(
            authenticator: authenticator,
            balanceService: balanceService
        )
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )

        let result = try await bridge.refreshBalance(
            meta: meta,
            secret: StoredAccountSecret(account: sampleAccount())
        )

        #expect(result.meta.lastIssue == nil)
        #expect(result.meta.balanceSnapshot?.source == .authentication)
        #expect(authenticator.callCount == 1)
        #expect(await balanceService.callCount == 2)
    }
}

private final class AppleAuthenticatorStub: AppleAuthenticating, @unchecked Sendable {
    var result: AuthenticationResult
    var error: Error?
    private(set) var callCount = 0

    init(result: AuthenticationResult, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func authenticate(
        email _: String,
        password _: String,
        code _: String,
        cookies _: [Cookie],
        deviceIdentifier _: String
    ) async throws -> AuthenticationResult {
        callCount += 1
        if let error {
            throw error
        }
        return result
    }
}

private actor BalanceRefreshingStub: BalanceRefreshing {
    var result: BalanceResult?
    var error: Error?
    private(set) var callCount = 0

    init(result: BalanceResult? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func refreshBalance(
        for _: StoredAccountMeta,
        secret _: StoredAccountSecret
    ) async throws -> BalanceResult {
        callCount += 1
        if let error {
            throw error
        }
        if let result {
            return result
        }
        throw MitoriError.missingProbeBundleID
    }
}

private func authenticationResult(fixture: String) throws -> AuthenticationResult {
    AuthenticationResult(
        account: sampleAccount(),
        responsePlist: try FixtureLoader.data(named: fixture)
    )
}
