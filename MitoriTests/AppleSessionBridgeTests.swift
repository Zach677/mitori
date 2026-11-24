//
//  AppleSessionBridgeTests.swift
//  Mitori
//
//  Created by @Zach677 on 2026/09/05.
//

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
            probeBundleID: "",
            existing: nil
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
            probeBundleID: "",
            existing: nil
        )

        #expect(result.meta.lastIssue == nil)
        #expect(result.meta.balanceSnapshot == nil)
        #expect(await balanceService.callCount == 0)
    }

    @Test
    func loginWithEmptyAuthCreditShowsZeroBalance() async throws {
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
            probeBundleID: "",
            existing: nil
        )

        #expect(result.meta.balanceSnapshot?.numericValue == 0)
        #expect(result.meta.balanceSnapshot?.source == .authentication)
        #expect(result.meta.lastRefreshAt == result.meta.balanceSnapshot?.fetchedAt)
        #expect(result.meta.lastIssue == nil)
    }

    @Test
    func reauthenticationWithoutAuthBalanceKeepsExistingSnapshot() async throws {
        let authenticator = AppleAuthenticatorStub(
            result: AuthenticationResult(
                account: sampleAccount(),
                responsePlist: try PropertyListSerialization.data(
                    fromPropertyList: ["accountInfo": ["creditDisplay": ""]],
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
    func loginForExistingAccountWithoutAuthBalanceKeepsHistory() async throws {
        let authenticator = AppleAuthenticatorStub(
            result: AuthenticationResult(account: sampleAccount(), responsePlist: Data())
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
            source: .authentication,
            rawFieldPath: "accountInfo.creditDisplay"
        )
        let existing = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "",
            balanceSnapshot: snapshot,
            lastRefreshAt: fetchedAt
        )

        let result = try await bridge.login(
            email: "demo@example.com",
            password: "new-password",
            code: "",
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "",
            existing: existing
        )

        #expect(result.meta.balanceSnapshot == snapshot)
        #expect(result.meta.lastRefreshAt == fetchedAt)
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
            probeBundleID: "com.example.probe",
            existing: nil
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
            probeBundleID: "com.example.probe",
            existing: nil
        )

        #expect(result.meta.balanceSnapshot?.source == .authentication)
        #expect(result.meta.lastIssue?.kind == .probeConfigurationMissing)
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
            secret: StoredAccountSecret(account: sampleAccount()),
            allowsReauthentication: true
        )

        #expect(result.meta.lastIssue == nil)
        #expect(result.meta.balanceSnapshot?.source == .authentication)
        #expect(authenticator.callCount == 1)
        #expect(await balanceService.callCount == 0)
    }

    @Test
    func manualRefreshRecordsProbeExpiryAfterReauthentication() async throws {
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
            secret: StoredAccountSecret(account: sampleAccount()),
            allowsReauthentication: true
        )

        #expect(result.meta.lastIssue?.kind == .balanceUnavailable)
        #expect(result.meta.balanceSnapshot?.source == .authentication)
        #expect(result.meta.balanceSnapshot?.numericValue == Decimal(string: "24.90"))
        #expect(authenticator.callCount == 1)
        #expect(await balanceService.callCount == 2)
    }

    @Test
    func manualProbeNetworkFailureDoesNotReauthenticate() async throws {
        let authenticator = AppleAuthenticatorStub(
            result: try authenticationResult(fixture: "auth_success_balance")
        )
        let balanceService = BalanceRefreshingStub(error: MitoriError.network("offline"))
        let bridge = AppleSessionBridge(
            authenticator: authenticator,
            balanceService: balanceService
        )
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )

        await #expect(throws: MitoriError.network("offline")) {
            try await bridge.refreshBalance(
                meta: meta,
                secret: StoredAccountSecret(account: sampleAccount()),
                allowsReauthentication: true
            )
        }
        #expect(authenticator.callCount == 0)
    }

    @Test
    func reauthenticationSendsStoredCookiesAndLoginSendsNone() async throws {
        let authenticator = AppleAuthenticatorStub(
            result: try authenticationResult(fixture: "auth_success_balance")
        )
        let bridge = AppleSessionBridge(
            authenticator: authenticator,
            balanceService: BalanceRefreshingStub()
        )
        let cookie = Cookie(name: "mz_at0", value: "session", path: "/", httpOnly: true, secure: true)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: ""
        )

        _ = try await bridge.reauthenticate(
            meta: meta,
            secret: StoredAccountSecret(account: sampleAccount(cookies: [cookie])),
            code: ""
        )
        _ = try await bridge.login(
            email: "demo@example.com",
            password: "password",
            code: "",
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "",
            existing: nil
        )

        #expect(authenticator.cookies.map { $0.map(\.name) } == [["mz_at0"], []])
    }

    @Test
    func reauthenticationWithNewPasswordClearsCookiesAndKeepsDeviceIdentifier() async throws {
        let authenticator = AppleAuthenticatorStub(
            result: try authenticationResult(fixture: "auth_success_balance")
        )
        let bridge = AppleSessionBridge(
            authenticator: authenticator,
            balanceService: BalanceRefreshingStub()
        )
        let cookie = Cookie(name: "mz_at0", value: "stale", path: "/", httpOnly: true, secure: true)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "KEEPDEVICE01",
            probeBundleID: ""
        )

        let result = try await bridge.reauthenticate(
            meta: meta,
            secret: StoredAccountSecret(account: sampleAccount(cookies: [cookie])),
            passwordOverride: "updated-password",
            code: "123456"
        )

        #expect(authenticator.cookies == [[]])
        #expect(result.meta.deviceIdentifier == "KEEPDEVICE01")
    }

    @Test
    func loginRecordsProbeNetworkFailureAndKeepsAuthBalance() async throws {
        let authenticator = AppleAuthenticatorStub(
            result: try authenticationResult(fixture: "auth_success_balance")
        )
        let balanceService = BalanceRefreshingStub(error: MitoriError.network("offline"))
        let bridge = AppleSessionBridge(
            authenticator: authenticator,
            balanceService: balanceService
        )

        let result = try await bridge.login(
            email: "demo@example.com",
            password: "password",
            code: "",
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe",
            existing: nil
        )

        #expect(result.meta.lastIssue?.kind == .network)
        #expect(result.meta.balanceSnapshot?.source == .authentication)
    }
}

private final class AppleAuthenticatorStub: AppleAuthenticating, @unchecked Sendable {
    var result: AuthenticationResult
    var error: Error?
    private(set) var callCount = 0
    private(set) var cookies: [[Cookie]] = []

    init(result: AuthenticationResult, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func authenticate(
        email _: String,
        password _: String,
        code _: String,
        cookies: [Cookie],
        deviceIdentifier _: String
    ) async throws -> AuthenticationResult {
        callCount += 1
        self.cookies.append(cookies)
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
