//
//  MitoriModelAutoRefreshTests.swift
//  Mitori
//
//  Created by @Zach677 on 2026/07/18.
//

import Foundation
import Testing

@testable import Mitori

@MainActor
struct MitoriModelAutoRefreshTests {
    @Test
    func autoRefreshTickSkipsWhenDisabled() async throws {
        let context = try await makeAutoRefreshContext(
            enabled: false,
            lastRefreshAt: Date(timeIntervalSinceNow: -7200)
        )
        defer { context.cleanUp() }

        await context.model.autoRefreshTick()

        #expect(context.bridge.refreshCallCount == 0)
    }

    @Test
    func autoRefreshTickSkipsWhenScreenIsLocked() async throws {
        let context = try await makeAutoRefreshContext(
            enabled: true,
            lastRefreshAt: Date(timeIntervalSinceNow: -7200),
            screenIsLocked: true
        )
        defer { context.cleanUp() }

        await context.model.autoRefreshTick()

        #expect(context.bridge.refreshCallCount == 0)
    }

    @Test
    func screenLockDetectionTreatsAbsentKeyAsUnlocked() {
        #expect(MitoriModel.isScreenLocked(in: ["kCGSSessionOnConsoleKey": true]) == false)
        #expect(MitoriModel.isScreenLocked(in: ["kCGSSessionOnConsoleKey": true, "CGSSessionScreenIsLocked": false]) == false)
        #expect(MitoriModel.isScreenLocked(in: ["kCGSSessionOnConsoleKey": true, "CGSSessionScreenIsLocked": true]) == true)
        #expect(MitoriModel.isScreenLocked(in: ["kCGSSessionOnConsoleKey": false]) == true)
        #expect(MitoriModel.isScreenLocked(in: nil) == true)
    }

    @Test
    func schedulerSkipsOverlappingTicks() async {
        let gate = RefreshGate()
        var tickCount = 0
        let scheduler = AutoRefreshScheduler(
            nextFireDate: { Date.distantFuture },
            onTick: {
                tickCount += 1
                await gate.suspend()
            }
        )

        scheduler.triggerTick()
        await gate.waitUntilStarted()
        scheduler.triggerTick()
        await Task.yield()

        #expect(tickCount == 1)
        gate.release()
        scheduler.stop()
    }

    @Test
    func nextAutoRefreshDateTracksEarliestDueAndRespectsPauseAndBackoff() async throws {
        let clock = TestClock()
        clock.date = Date(timeIntervalSince1970: 1_800_000_000)
        let context = try await makeAutoRefreshContext(
            enabled: true,
            lastRefreshAt: clock.date.addingTimeInterval(-600),
            now: { clock.date }
        )
        defer { context.cleanUp() }

        // Before accounts load, scheduler asks to wake immediately once to load them.
        #expect(context.model.nextAutoRefreshDate() == clock.date)

        await context.model.loadAccountsIfNeeded()
        let expectedFirstDue = clock.date.addingTimeInterval(-600 + context.settings.autoRefreshInterval)
        #expect(context.model.nextAutoRefreshDate() == expectedFirstDue)

        // Disabled auto-refresh schedules nothing.
        context.settings.isAutoRefreshEnabled = false
        #expect(context.model.nextAutoRefreshDate() == nil)
        context.settings.isAutoRefreshEnabled = true

        // A network backoff pushes due date forward when later than interval.
        clock.date = expectedFirstDue
        context.bridge.refreshHandler = { _ in throw MitoriError.network("offline") }
        await context.model.autoRefreshTick()
        #expect(context.model.nextAutoRefreshDate() == clock.date.addingTimeInterval(60))

        // Session expiry pauses auto-refresh completely (nil next fire date).
        clock.date += 61
        context.bridge.refreshHandler = { _ in throw MitoriError.sessionExpired }
        await context.model.autoRefreshTick()
        #expect(context.model.nextAutoRefreshDate() == nil)
    }

    @Test
    func autoRefreshTickSkipsRecentlyRefreshedAccounts() async throws {
        let context = try await makeAutoRefreshContext(
            enabled: true,
            lastRefreshAt: Date()
        )
        defer { context.cleanUp() }

        await context.model.autoRefreshTick()

        #expect(context.bridge.refreshCallCount == 0)
        #expect(context.model.refreshState(for: context.accountID) == .idle)
    }

    @Test
    func autoRefreshTickRefreshesStaleAccounts() async throws {
        let context = try await makeAutoRefreshContext(
            enabled: true,
            lastRefreshAt: Date(timeIntervalSinceNow: -7200)
        )
        defer { context.cleanUp() }

        await context.model.autoRefreshTick()

        #expect(context.bridge.refreshCallCount == 1)
        #expect(context.bridge.refreshAllowsReauthentication == [false])
        #expect(context.secretBackend.readAllowsAuthenticationUI == [false, false])
        #expect(context.secretBackend.writeAllowsAuthenticationUI == [true, false])
        guard case .succeeded = context.model.refreshState(for: context.accountID) else {
            Issue.record("Expected succeeded state, got \(context.model.refreshState(for: context.accountID))")
            return
        }
    }

    @Test
    func autoRefreshNeverCallsTheBridgeForAccountsWithoutProbe() async throws {
        let clock = TestClock()
        let context = try await makeAutoRefreshContext(
            enabled: true,
            lastRefreshAt: nil,
            probeBundleID: "",
            now: { clock.date }
        )
        defer { context.cleanUp() }

        await context.model.autoRefreshTick()
        clock.date += context.settings.autoRefreshInterval
        await context.model.autoRefreshTick()

        #expect(context.bridge.refreshCallCount == 0)
    }

    @Test
    func automaticSessionExpiryPausesAutoRefreshAcrossReloads() async throws {
        let clock = TestClock()
        let context = try await makeAutoRefreshContext(
            enabled: true,
            lastRefreshAt: nil,
            now: { clock.date }
        )
        defer { context.cleanUp() }
        context.bridge.refreshHandler = { _ in throw MitoriError.sessionExpired }

        await context.model.autoRefreshTick()

        #expect(context.bridge.refreshAllowsReauthentication == [false])
        #expect(context.model.account(with: context.accountID)?.lastIssue?.kind == .sessionExpired)

        clock.date += context.settings.autoRefreshInterval
        await context.model.autoRefreshTick()
        clock.date += context.settings.autoRefreshInterval
        await context.model.autoRefreshTick()

        #expect(context.bridge.refreshCallCount == 1)

        let reloadedModel = MitoriModel(
            accountStore: context.accountStore,
            secretStore: context.secretStore,
            sessionBridge: context.bridge,
            settings: context.settings,
            now: { clock.date },
            screenIsLocked: { false }
        )
        await reloadedModel.autoRefreshTick()

        #expect(reloadedModel.account(with: context.accountID)?.lastIssue?.kind == .sessionExpired)
        #expect(context.bridge.refreshCallCount == 1)
    }

    @Test
    func automaticNetworkFailureRetriesAfterBackoff() async throws {
        let clock = TestClock()
        let context = try await makeAutoRefreshContext(
            enabled: true,
            lastRefreshAt: nil,
            now: { clock.date }
        )
        defer { context.cleanUp() }
        context.bridge.refreshHandler = { _ in throw MitoriError.network("offline") }

        await context.model.autoRefreshTick()
        await context.model.autoRefreshTick()

        #expect(context.bridge.refreshCallCount == 1)
        #expect(context.model.account(with: context.accountID)?.lastIssue?.kind == .network)

        clock.date += 61
        await context.model.autoRefreshTick()

        #expect(context.bridge.refreshCallCount == 2)
        #expect(context.bridge.refreshAllowsReauthentication == [false, false])
    }

    @Test
    func pausedAccountDoesNotBlockOtherAccounts() async throws {
        let clock = TestClock()
        let context = try await makeAutoRefreshContext(
            enabled: true,
            lastRefreshAt: nil,
            lastIssue: MitoriError.sessionExpired.refreshIssue(),
            now: { clock.date }
        )
        defer { context.cleanUp() }

        var otherAccount = sampleAccount()
        otherAccount.email = "other@example.com"
        let otherMeta = StoredAccountMeta(
            account: otherAccount,
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        _ = try await context.accountStore.upsert(otherMeta)
        try await context.secretStore.save(StoredAccountSecret(account: otherAccount), for: otherMeta.id)

        var refreshedIDs: [String] = []
        context.bridge.refreshHandler = { meta in
            refreshedIDs.append(meta.id)
            var updated = meta
            updated.lastRefreshAt = clock.date
            return SessionRefreshResult(meta: updated, secret: StoredAccountSecret(account: otherAccount))
        }

        await context.model.autoRefreshTick()
        clock.date += context.settings.autoRefreshInterval
        await context.model.autoRefreshTick()

        #expect(refreshedIDs == [otherMeta.id, otherMeta.id])
    }

    @Test
    func manualRefreshClearsPauseAndAutoRefreshResumes() async throws {
        let clock = TestClock()
        let context = try await makeAutoRefreshContext(
            enabled: true,
            lastRefreshAt: nil,
            now: { clock.date }
        )
        defer { context.cleanUp() }

        // The bridge reauthenticated, but the probe still reported an expired session.
        var nextIssue: RefreshIssue? = RefreshIssue(
            kind: .balanceUnavailable,
            message: "Probe unavailable",
            updatedAt: clock.date
        )
        context.bridge.refreshHandler = { meta in
            var updated = meta
            updated.lastIssue = nextIssue
            updated.lastRefreshAt = clock.date
            return SessionRefreshResult(meta: updated, secret: StoredAccountSecret(account: sampleAccount()))
        }

        await context.model.loadAccountsIfNeeded()
        await context.model.refreshAccount(id: context.accountID, isManualRefresh: true)

        #expect(context.model.refreshState(for: context.accountID) == .failed(.balanceUnavailable))
        clock.date += context.settings.autoRefreshInterval
        await context.model.autoRefreshTick()
        #expect(context.bridge.refreshCallCount == 1)

        nextIssue = nil
        await context.model.refreshAccount(id: context.accountID, isManualRefresh: true)

        #expect(context.model.account(with: context.accountID)?.lastIssue == nil)
        clock.date += context.settings.autoRefreshInterval
        await context.model.autoRefreshTick()
        #expect(context.bridge.refreshAllowsReauthentication == [true, true, false])
    }

    private final class TestClock {
        var date = Date()
    }

    private struct AutoRefreshContext {
        var model: MitoriModel
        var bridge: SessionBridgeStub
        var secretBackend: RecordingSecretBackend
        var accountStore: AccountStore
        var secretStore: SecretStore
        var settings: RefreshSettingsStore
        var accountID: String
        var defaultsSuiteName: String
        var tempDirectory: URL

        func cleanUp() {
            UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(forName: defaultsSuiteName)
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    private func makeAutoRefreshContext(
        enabled: Bool,
        lastRefreshAt: Date?,
        probeBundleID: String = "com.example.probe",
        lastIssue: RefreshIssue? = nil,
        now: @escaping () -> Date = Date.init,
        screenIsLocked: Bool = false
    ) async throws -> AutoRefreshContext {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = RefreshSettingsStore(defaults: defaults)
        settings.isAutoRefreshEnabled = enabled

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let secretBackend = RecordingSecretBackend()
        let secretStore = SecretStore(backend: secretBackend)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: probeBundleID,
            lastIssue: lastIssue,
            lastRefreshAt: lastRefreshAt
        )
        _ = try await accountStore.upsert(meta)
        try await secretStore.save(StoredAccountSecret(account: sampleAccount()), for: meta.id)

        let bridge = SessionBridgeStub(refreshResult: SessionRefreshResult(
            meta: StoredAccountMeta(
                account: sampleAccount(),
                deviceIdentifier: meta.deviceIdentifier,
                probeBundleID: meta.probeBundleID,
                lastRefreshAt: Date()
            ),
            secret: StoredAccountSecret(account: sampleAccount())
        ))
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: secretStore,
            sessionBridge: bridge,
            settings: settings,
            now: now,
            screenIsLocked: { screenIsLocked }
        )
        return AutoRefreshContext(
            model: model,
            bridge: bridge,
            secretBackend: secretBackend,
            accountStore: accountStore,
            secretStore: secretStore,
            settings: settings,
            accountID: meta.id,
            defaultsSuiteName: suiteName,
            tempDirectory: tempDirectory
        )
    }
}

private final class RecordingSecretBackend: SecretKeyValueStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private(set) var readAllowsAuthenticationUI: [Bool] = []
    private(set) var writeAllowsAuthenticationUI: [Bool] = []

    func data(for key: String, allowsAuthenticationUI: Bool) throws -> Data? {
        readAllowsAuthenticationUI.append(allowsAuthenticationUI)
        return storage[key]
    }

    func set(_ data: Data, for key: String, allowsAuthenticationUI: Bool) throws {
        writeAllowsAuthenticationUI.append(allowsAuthenticationUI)
        storage[key] = data
    }

    func removeValue(for key: String, allowsAuthenticationUI _: Bool) throws {
        storage[key] = nil
    }
}
