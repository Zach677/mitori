//
//  MitoriModelTests.swift
//  Mitori
//
//  Created by @Zach677 on 2026/07/18.
//

import Foundation
import Testing

@testable import Mitori

@MainActor
struct MitoriModelTests {
    @Test
    func loadAccountsRetriesAfterFailedLoad() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("accounts.json")
        try Data("not json".utf8).write(to: fileURL)
        let model = MitoriModel(
            accountStore: AccountStore(baseDirectory: tempDirectory),
            secretStore: SecretStore(backend: InMemorySecretBackend()),
            sessionBridge: SessionBridgeStub()
        )

        await model.loadAccountsIfNeeded()
        #expect(model.accounts.isEmpty)
        #expect(model.loadError != nil)

        try FileManager.default.removeItem(at: fileURL)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        _ = try await AccountStore(baseDirectory: tempDirectory).upsert(meta)

        await model.loadAccountsIfNeeded()
        #expect(model.accounts.map(\.id) == [meta.id])
        #expect(model.loadError == nil)
    }

    @Test
    func concurrentLoadAccountsIfNeededSharesOneLoad() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        _ = try await accountStore.upsert(meta)
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: SecretStore(backend: InMemorySecretBackend()),
            sessionBridge: SessionBridgeStub()
        )

        var accountsEventCount = 0
        let cancellable = model.changeEvents.sink { change in
            if case .accounts = change {
                accountsEventCount += 1
            }
        }
        defer { cancellable.cancel() }

        async let first: Void = model.loadAccountsIfNeeded()
        async let second: Void = model.loadAccountsIfNeeded()
        _ = await (first, second)

        #expect(model.accounts.map(\.id) == [meta.id])
        #expect(accountsEventCount == 1)
    }

    @Test
    func accountSuccessDoesNotClearAnotherAccountsIssue() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let secretStore = SecretStore(backend: InMemorySecretBackend())

        var secondAccount = sampleAccount()
        secondAccount.email = "other@example.com"
        let firstMeta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        let secondMeta = StoredAccountMeta(
            account: secondAccount,
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        for (meta, account) in [(firstMeta, sampleAccount()), (secondMeta, secondAccount)] {
            _ = try await accountStore.upsert(meta)
            try await secretStore.save(StoredAccountSecret(account: account), for: meta.id)
        }

        let bridge = SessionBridgeStub()
        bridge.refreshHandler = { meta in
            if meta.id == secondMeta.id {
                throw MitoriError.network("offline")
            }
            var updated = meta
            updated.lastIssue = nil
            updated.lastRefreshAt = Date()
            return SessionRefreshResult(meta: updated, secret: StoredAccountSecret(account: sampleAccount()))
        }
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: secretStore,
            sessionBridge: bridge
        )
        await model.loadAccountsIfNeeded()

        await model.refreshAccount(id: secondMeta.id, isManualRefresh: true)
        #expect(model.account(with: secondMeta.id)?.visibleIssue?.kind == .network)

        await model.refreshAccount(id: firstMeta.id, isManualRefresh: true)
        #expect(model.account(with: firstMeta.id)?.visibleIssue == nil)
        #expect(model.account(with: secondMeta.id)?.visibleIssue?.kind == .network)
    }

    @Test
    func savingProbeBundleIDClearsProbeConfigurationIssue() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "",
            lastIssue: MitoriError.missingProbeBundleID.refreshIssue(
                at: Date(timeIntervalSince1970: 1_743_166_800)
            ),
            lastRefreshAt: Date(),
            nextEligibleRefreshAt: Date().addingTimeInterval(300),
            consecutiveFailureCount: 2
        )
        _ = try await accountStore.upsert(meta)

        let secretStore = SecretStore(backend: InMemorySecretBackend())
        try await secretStore.save(StoredAccountSecret(account: sampleAccount()), for: meta.id)
        let bridge = SessionBridgeStub()
        bridge.refreshHandler = { _ in throw MitoriError.missingProbeBundleID }
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: secretStore,
            sessionBridge: bridge
        )

        await model.loadAccountsIfNeeded()
        await model.refreshAccount(id: meta.id, isManualRefresh: true)
        #expect(model.account(with: meta.id)?.lastIssue?.kind == .probeConfigurationMissing)

        try await model.saveProbeBundleID(" com.example.probe ", for: meta.id)

        let updated = try #require(model.account(with: meta.id))
        #expect(updated.probeBundleID == "com.example.probe")
        #expect(updated.lastIssue == nil)
        #expect(updated.nextEligibleRefreshAt == nil)
        #expect(updated.consecutiveFailureCount == 0)
    }

    @Test
    func clearingProbeBundleIDDoesNotCreateConfigurationIssue() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe",
            lastRefreshAt: Date()
        )
        _ = try await accountStore.upsert(meta)

        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: SecretStore(backend: InMemorySecretBackend()),
            sessionBridge: SessionBridgeStub()
        )

        await model.loadAccountsIfNeeded()
        try await model.saveProbeBundleID(" ", for: meta.id)

        let updated = try #require(model.account(with: meta.id))
        #expect(updated.probeBundleID.isEmpty)
        #expect(updated.lastIssue == nil)
    }

    @Test(arguments: ["com.example.new-probe", ""])
    func changingProbeClearsOnlyProbeRelatedIssues(newProbeBundleID: String) async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let probeMeta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe",
            lastIssue: MitoriError.probeAppNotOwned.refreshIssue(),
            consecutiveFailureCount: 1
        )
        _ = try await accountStore.upsert(probeMeta)
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: SecretStore(backend: InMemorySecretBackend()),
            sessionBridge: SessionBridgeStub()
        )
        await model.loadAccountsIfNeeded()

        try await model.saveProbeBundleID(newProbeBundleID, for: probeMeta.id)
        #expect(model.account(with: probeMeta.id)?.lastIssue == nil)

        var sessionMeta = probeMeta
        sessionMeta.lastIssue = MitoriError.sessionExpired.refreshIssue()
        _ = try await accountStore.upsert(sessionMeta)
        let reloadedModel = MitoriModel(
            accountStore: accountStore,
            secretStore: SecretStore(backend: InMemorySecretBackend()),
            sessionBridge: SessionBridgeStub()
        )
        await reloadedModel.loadAccountsIfNeeded()

        try await reloadedModel.saveProbeBundleID(newProbeBundleID, for: sessionMeta.id)
        #expect(reloadedModel.account(with: sessionMeta.id)?.lastIssue?.kind == .sessionExpired)

        var notFoundMeta = probeMeta
        notFoundMeta.lastIssue = MitoriError.probeAppNotFound("com.example.probe").refreshIssue()
        _ = try await accountStore.upsert(notFoundMeta)
        let notFoundModel = MitoriModel(
            accountStore: accountStore,
            secretStore: SecretStore(backend: InMemorySecretBackend()),
            sessionBridge: SessionBridgeStub()
        )
        await notFoundModel.loadAccountsIfNeeded()

        try await notFoundModel.saveProbeBundleID(newProbeBundleID, for: notFoundMeta.id)
        #expect(notFoundModel.account(with: notFoundMeta.id)?.lastIssue == nil)
    }

    @Test
    func savingUnchangedProbeKeepsProbeIssue() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe",
            lastIssue: MitoriError.probeAppNotOwned.refreshIssue(),
            consecutiveFailureCount: 1
        )
        _ = try await accountStore.upsert(meta)
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: SecretStore(backend: InMemorySecretBackend()),
            sessionBridge: SessionBridgeStub()
        )
        await model.loadAccountsIfNeeded()

        try await model.saveProbeBundleID(" com.example.probe ", for: meta.id)

        #expect(model.account(with: meta.id)?.lastIssue?.kind == .probeConfigurationMissing)
    }

    @Test
    func menuPresentationDoesNotStartKeychainBackedRefresh() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        _ = try await accountStore.upsert(meta)

        let sessionBridge = SessionBridgeStub()
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: SecretStore(backend: InMemorySecretBackend()),
            sessionBridge: sessionBridge
        )

        await model.loadAccountsIfNeeded()

        #expect(model.account(with: meta.id) != nil)
        #expect(model.refreshState(for: meta.id) == .idle)
        #expect(sessionBridge.refreshCallCount == 0)
        #expect(sessionBridge.loginRequests.isEmpty)
    }

    @Test
    func refreshAccountMarksReturnedIssueAsFailure() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let secretBackend = InMemorySecretBackend()
        let secretStore = SecretStore(backend: secretBackend)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        let secret = StoredAccountSecret(account: sampleAccount())
        _ = try await accountStore.upsert(meta)
        try await secretStore.save(secret, for: meta.id)

        let result = SessionRefreshResult(
            meta: StoredAccountMeta(
                account: sampleAccount(),
                deviceIdentifier: meta.deviceIdentifier,
                probeBundleID: meta.probeBundleID,
                lastIssue: MitoriError.sessionExpired.refreshIssue()
            ),
            secret: secret
        )
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: secretStore,
            sessionBridge: SessionBridgeStub(refreshResult: result)
        )

        await model.loadAccountsIfNeeded()
        await model.refreshAccount(id: meta.id, isManualRefresh: true)

        #expect(model.refreshState(for: meta.id) == .failed(.sessionExpired))
        #expect(model.account(with: meta.id)?.visibleIssue?.kind == .sessionExpired)
    }

    @Test(arguments: [true, false])
    func cancelledRefreshReturnsToIdleWithoutIssue(isManualRefresh: Bool) async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let secretStore = SecretStore(backend: InMemorySecretBackend())
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        _ = try await accountStore.upsert(meta)
        try await secretStore.save(StoredAccountSecret(account: sampleAccount()), for: meta.id)
        let bridge = SessionBridgeStub()
        bridge.refreshHandler = { _ in throw CancellationError() }
        let model = MitoriModel(accountStore: accountStore, secretStore: secretStore, sessionBridge: bridge)

        await model.loadAccountsIfNeeded()
        await model.refreshAccount(id: meta.id, isManualRefresh: isManualRefresh)

        #expect(bridge.refreshCallCount == 1)
        #expect(model.refreshState(for: meta.id) == .idle)
        #expect(model.account(with: meta.id)?.lastIssue == nil)
        #expect(model.account(with: meta.id)?.nextEligibleRefreshAt == nil)
    }

    @Test
    func completedRefreshDoesNotRestoreDeletedAccount() async throws {
        let context = try await makeSuspendedRefreshContext()
        defer { try? FileManager.default.removeItem(at: context.tempDirectory) }

        let refreshTask = Task {
            await context.model.refreshAccount(id: context.meta.id, isManualRefresh: true)
        }
        await context.gate.waitUntilStarted()

        try await context.model.deleteAccount(id: context.meta.id)
        context.gate.release()
        await refreshTask.value

        #expect(context.model.account(with: context.meta.id) == nil)
        #expect(try await context.secretStore.loadSecret(for: context.meta.id) == nil)
    }

    @Test
    func deleteWaitsForStartedCommitAndStillWins() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let seedStore = AccountStore(baseDirectory: tempDirectory)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        _ = try await seedStore.upsert(meta)

        let writeGate = BlockingWriteGate()
        let accountStore = AccountStore(baseDirectory: tempDirectory) { data, url in
            writeGate.suspend()
            try data.write(to: url, options: .atomic)
        }
        let secretStore = SecretStore(backend: InMemorySecretBackend())
        let secret = StoredAccountSecret(account: sampleAccount())
        try await secretStore.save(secret, for: meta.id)
        let refreshedMeta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: meta.deviceIdentifier,
            probeBundleID: meta.probeBundleID,
            lastRefreshAt: Date()
        )
        let bridge = SessionBridgeStub(refreshResult: SessionRefreshResult(
            meta: refreshedMeta,
            secret: secret
        ))
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: secretStore,
            sessionBridge: bridge
        )
        await model.loadAccountsIfNeeded()

        let refresh = Task {
            await model.refreshAccount(id: meta.id, isManualRefresh: true)
        }
        await Task.detached {
            writeGate.waitUntilStarted()
        }.value
        defer { writeGate.release() }

        let deletion = Task {
            try await model.deleteAccount(id: meta.id)
        }
        await Task.yield()
        writeGate.release()
        await refresh.value
        try await deletion.value

        #expect(model.account(with: meta.id) == nil)
        #expect(try await secretStore.loadSecret(for: meta.id) == nil)
    }

    @Test
    func pendingFailureRecordDoesNotChangeVisibleStateAndDeletionWins() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let seedStore = AccountStore(baseDirectory: tempDirectory)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        _ = try await seedStore.upsert(meta)

        let writeGate = BlockingWriteGate()
        let accountStore = AccountStore(baseDirectory: tempDirectory) { data, url in
            writeGate.suspend()
            try data.write(to: url, options: .atomic)
        }
        let secretStore = SecretStore(backend: InMemorySecretBackend())
        try await secretStore.save(StoredAccountSecret(account: sampleAccount()), for: meta.id)
        let bridge = SessionBridgeStub()
        bridge.refreshHandler = { _ in throw MitoriError.network("offline") }
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: secretStore,
            sessionBridge: bridge
        )
        await model.loadAccountsIfNeeded()

        let refresh = Task {
            await model.refreshAccount(id: meta.id, isManualRefresh: true)
        }
        await Task.detached {
            writeGate.waitUntilStarted()
        }.value
        defer { writeGate.release() }

        #expect(model.account(with: meta.id)?.lastIssue == nil)
        #expect(model.account(with: meta.id)?.consecutiveFailureCount == 0)

        let deletion = Task {
            try await model.deleteAccount(id: meta.id)
        }
        await Task.yield()
        writeGate.release()
        await refresh.value
        try await deletion.value

        #expect(model.account(with: meta.id) == nil)
        #expect(try await AccountStore(baseDirectory: tempDirectory).loadAccounts().isEmpty)
    }

    @Test
    func failedSecretDeletionKeepsAccountVisible() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let backend = FailingDeleteSecretBackend()
        let secretStore = SecretStore(backend: backend)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        _ = try await accountStore.upsert(meta)
        try await secretStore.save(StoredAccountSecret(account: sampleAccount()), for: meta.id)
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: secretStore,
            sessionBridge: SessionBridgeStub()
        )
        await model.loadAccountsIfNeeded()

        await #expect(throws: MitoriError.self) {
            try await model.deleteAccount(id: meta.id)
        }

        #expect(model.account(with: meta.id) != nil)
        #expect(try await secretStore.loadSecret(for: meta.id) != nil)
    }

    @Test
    func deleteAccountSucceedsWhenStoredSecretCannotBeDecoded() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let backend = InMemorySecretBackend()
        let secretStore = SecretStore(backend: backend)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        _ = try await accountStore.upsert(meta)
        try backend.set(Data("not json".utf8), for: "account.\(meta.id)")
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: secretStore,
            sessionBridge: SessionBridgeStub()
        )
        await model.loadAccountsIfNeeded()

        try await model.deleteAccount(id: meta.id)

        #expect(model.account(with: meta.id) == nil)
        #expect(try await accountStore.loadAccounts().isEmpty)
        #expect(try backend.data(for: "account.\(meta.id)") == nil)
    }

    @Test
    func failedMetadataDeletionRestoresSecret() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let seedStore = AccountStore(baseDirectory: tempDirectory)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        _ = try await seedStore.upsert(meta)
        let failingStore = AccountStore(baseDirectory: tempDirectory, writeData: failingWrite)
        let secretStore = SecretStore(backend: InMemorySecretBackend())
        let secret = StoredAccountSecret(account: sampleAccount())
        try await secretStore.save(secret, for: meta.id)
        let model = MitoriModel(
            accountStore: failingStore,
            secretStore: secretStore,
            sessionBridge: SessionBridgeStub()
        )
        await model.loadAccountsIfNeeded()

        await #expect(throws: MitoriError.self) {
            try await model.deleteAccount(id: meta.id)
        }

        #expect(model.account(with: meta.id) != nil)
        #expect(try await secretStore.loadSecret(for: meta.id) == secret)
    }

    @Test
    func failedMetadataWriteRestoresPreviousSecretAndKeepsBackoffInMemory() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let seedStore = AccountStore(baseDirectory: tempDirectory)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        _ = try await seedStore.upsert(meta)
        let failingStore = AccountStore(baseDirectory: tempDirectory, writeData: failingWrite)
        let secretStore = SecretStore(backend: InMemorySecretBackend())
        let previousSecret = StoredAccountSecret(account: sampleAccount())
        try await secretStore.save(previousSecret, for: meta.id)

        var refreshedAccount = sampleAccount()
        refreshedAccount.passwordToken = "new-token"
        let bridge = SessionBridgeStub(refreshResult: SessionRefreshResult(
            meta: meta,
            secret: StoredAccountSecret(account: refreshedAccount)
        ))
        let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
        let model = MitoriModel(
            accountStore: failingStore,
            secretStore: secretStore,
            sessionBridge: bridge,
            now: { fixedDate }
        )
        await model.loadAccountsIfNeeded()

        await model.refreshAccount(id: meta.id, isManualRefresh: true)

        #expect(try await secretStore.loadSecret(for: meta.id) == previousSecret)
        let failed = try #require(model.account(with: meta.id))
        #expect(failed.consecutiveFailureCount == 1)
        #expect(failed.nextEligibleRefreshAt == fixedDate.addingTimeInterval(60))
        #expect(failed.lastIssue?.kind == .unknown)
        #expect(failed.lastIssue?.message.hasPrefix("Storage error:") == true)
    }

    @Test
    func concurrentManualRefreshIsSingleFlight() async throws {
        let context = try await makeSuspendedRefreshContext()
        defer { try? FileManager.default.removeItem(at: context.tempDirectory) }
        let first = Task {
            await context.model.refreshAccount(id: context.meta.id, isManualRefresh: true)
        }
        await context.gate.waitUntilStarted()

        let second = Task {
            await context.model.refreshAccount(id: context.meta.id, isManualRefresh: true)
        }
        await second.value

        #expect(context.bridge.refreshCallCount == 1)
        context.gate.release()
        await first.value
    }

    @Test
    func accountMutationBlocksNewRefreshAndMutation() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let seedStore = AccountStore(baseDirectory: tempDirectory)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        _ = try await seedStore.upsert(meta)

        let writeGate = BlockingWriteGate()
        let accountStore = AccountStore(baseDirectory: tempDirectory) { data, url in
            writeGate.suspend()
            try data.write(to: url, options: .atomic)
        }
        let secretStore = SecretStore(backend: InMemorySecretBackend())
        try await secretStore.save(StoredAccountSecret(account: sampleAccount()), for: meta.id)
        let bridge = SessionBridgeStub()
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: secretStore,
            sessionBridge: bridge
        )
        await model.loadAccountsIfNeeded()

        let firstMutation = Task {
            try await model.saveProbeBundleID("com.example.first", for: meta.id)
        }
        await Task.detached {
            writeGate.waitUntilStarted()
        }.value
        defer { writeGate.release() }

        await model.refreshAccount(id: meta.id, isManualRefresh: true)
        await #expect(throws: MitoriError.operationInProgress) {
            try await model.saveProbeBundleID("com.example.second", for: meta.id)
        }
        #expect(bridge.refreshCallCount == 0)

        writeGate.release()
        try await firstMutation.value
        #expect(model.account(with: meta.id)?.probeBundleID == "com.example.first")
    }

    @Test
    func probeEditWinsOverInFlightRefresh() async throws {
        let context = try await makeSuspendedRefreshContext()
        defer { try? FileManager.default.removeItem(at: context.tempDirectory) }
        let refresh = Task {
            await context.model.refreshAccount(id: context.meta.id, isManualRefresh: true)
        }
        await context.gate.waitUntilStarted()

        try await context.model.saveProbeBundleID("com.example.new-probe", for: context.meta.id)
        context.gate.release()
        await refresh.value

        #expect(context.model.account(with: context.meta.id)?.probeBundleID == "com.example.new-probe")
    }

    @Test
    func reauthenticateReturnsPersistedIssueAfterAuthSucceeds() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let secretBackend = InMemorySecretBackend()
        let secretStore = SecretStore(backend: secretBackend)
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        let secret = StoredAccountSecret(account: sampleAccount())
        _ = try await accountStore.upsert(meta)
        try await secretStore.save(secret, for: meta.id)

        let result = SessionRefreshResult(
            meta: StoredAccountMeta(
                account: sampleAccount(),
                deviceIdentifier: meta.deviceIdentifier,
                probeBundleID: meta.probeBundleID,
                lastIssue: MitoriError.sessionExpired.refreshIssue()
            ),
            secret: secret
        )
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: secretStore,
            sessionBridge: SessionBridgeStub(reauthenticateResult: result)
        )

        await model.loadAccountsIfNeeded()

        let returnedIssue = try await model.reauthenticateAccount(id: meta.id, code: "")
        #expect(returnedIssue?.kind == .sessionExpired)
        #expect(model.refreshState(for: meta.id) == .failed(.sessionExpired))
        #expect(model.account(with: meta.id)?.visibleIssue?.kind == .sessionExpired)
    }

    @Test
    func reauthenticateKeepsReturnedIssueKindAndMessage() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let secretStore = SecretStore(backend: InMemorySecretBackend())
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        let secret = StoredAccountSecret(account: sampleAccount())
        _ = try await accountStore.upsert(meta)
        try await secretStore.save(secret, for: meta.id)

        let issue = MitoriError.probeAppNotOwned.refreshIssue()
        var issueMeta = meta
        issueMeta.lastIssue = issue
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: secretStore,
            sessionBridge: SessionBridgeStub(reauthenticateResult: SessionRefreshResult(
                meta: issueMeta,
                secret: secret
            ))
        )
        await model.loadAccountsIfNeeded()

        let returnedIssue = try await model.reauthenticateAccount(id: meta.id, code: "")

        #expect(returnedIssue?.message == issue.message)
        #expect(model.refreshState(for: meta.id) == .failed(.probeConfigurationMissing))
        #expect(model.account(with: meta.id)?.visibleIssue?.message == issue.message)
    }

    @Test
    func reauthenticateWithNewPasswordRecoversMissingSecret() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let secretStore = SecretStore(backend: InMemorySecretBackend())
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        _ = try await accountStore.upsert(meta)
        // Intentionally leave Keychain secret missing.

        var updatedAccount = sampleAccount()
        updatedAccount.password = "new-password"
        let bridge = SessionBridgeStub(reauthenticateResult: SessionRefreshResult(
            meta: meta,
            secret: StoredAccountSecret(account: updatedAccount)
        ))
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: secretStore,
            sessionBridge: bridge
        )
        await model.loadAccountsIfNeeded()

        let issue = try await model.reauthenticateAccount(id: meta.id, password: "new-password", code: "123456")

        #expect(issue == nil)
        #expect(bridge.reauthenticateRequests.count == 1)
        #expect(bridge.reauthenticateRequests.first?.passwordOverride == "new-password")
        #expect(bridge.reauthenticateRequests.first?.secret == nil)
        #expect(try await secretStore.loadSecret(for: meta.id)?.password == "new-password")
    }

    @Test
    func cancelledReauthenticateReturnsToIdle() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let secretStore = SecretStore(backend: InMemorySecretBackend())
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        _ = try await accountStore.upsert(meta)
        try await secretStore.save(StoredAccountSecret(account: sampleAccount()), for: meta.id)
        let bridge = SessionBridgeStub()
        bridge.reauthenticateHandler = { _, _ in throw CancellationError() }
        let model = MitoriModel(accountStore: accountStore, secretStore: secretStore, sessionBridge: bridge)
        await model.loadAccountsIfNeeded()

        await #expect(throws: CancellationError.self) {
            try await model.reauthenticateAccount(id: meta.id, code: "123456")
        }

        #expect(model.refreshState(for: meta.id) == .idle)
    }

    @Test
    func addAccountUsesFlowDeviceIdentifier() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let bridge = SessionBridgeStub(loginResult: SessionRefreshResult(
            meta: StoredAccountMeta(
                account: sampleAccount(),
                deviceIdentifier: "ABCDEF123456",
                probeBundleID: "com.example.probe"
            ),
            secret: StoredAccountSecret(account: sampleAccount())
        ))
        let model = MitoriModel(
            accountStore: AccountStore(baseDirectory: tempDirectory),
            secretStore: SecretStore(backend: InMemorySecretBackend()),
            sessionBridge: bridge
        )

        _ = try await model.addAccount(
            email: "demo@example.com",
            password: "password",
            code: "123456",
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )

        let request = try #require(bridge.loginRequests.first)
        #expect(request.deviceIdentifier == "ABCDEF123456")
        #expect(request.code == "123456")
    }

    @Test
    func cancelledInFlightLoginDoesNotPersistAccount() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let secretStore = SecretStore(backend: InMemorySecretBackend())
        let account = sampleAccount()
        let result = SessionRefreshResult(
            meta: StoredAccountMeta(
                account: account,
                deviceIdentifier: "ABCDEF123456",
                probeBundleID: "com.example.probe"
            ),
            secret: StoredAccountSecret(account: account)
        )
        let gate = RefreshGate()
        let bridge = SessionBridgeStub(loginResult: result)
        bridge.beforeLogin = { await gate.suspend() }
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: secretStore,
            sessionBridge: bridge
        )

        let login = Task {
            try await model.addAccount(
                email: account.email,
                password: account.password,
                code: "",
                deviceIdentifier: "ABCDEF123456",
                probeBundleID: "com.example.probe"
            )
        }
        await gate.waitUntilStarted()

        login.cancel()
        gate.release()

        await #expect(throws: CancellationError.self) {
            try await login.value
        }
        #expect(model.account(with: account.email) == nil)
        #expect(try await accountStore.loadAccounts().isEmpty)
        #expect(try await secretStore.loadSecret(for: account.email) == nil)
    }

    @Test
    func loginCancelledDuringCommitRollsBackAccount() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let writeGate = BlockingWriteGate()
        let accountStore = AccountStore(baseDirectory: tempDirectory) { data, url in
            writeGate.suspend()
            try data.write(to: url, options: .atomic)
        }
        let secretStore = SecretStore(backend: InMemorySecretBackend())
        let account = sampleAccount()
        let bridge = SessionBridgeStub(loginResult: SessionRefreshResult(
            meta: StoredAccountMeta(
                account: account,
                deviceIdentifier: "ABCDEF123456",
                probeBundleID: "com.example.probe"
            ),
            secret: StoredAccountSecret(account: account)
        ))
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: secretStore,
            sessionBridge: bridge
        )

        let login = Task {
            try await model.addAccount(
                email: account.email,
                password: account.password,
                code: "",
                deviceIdentifier: "ABCDEF123456",
                probeBundleID: "com.example.probe"
            )
        }
        await Task.detached {
            writeGate.waitUntilStarted()
        }.value

        login.cancel()
        writeGate.release()

        await #expect(throws: CancellationError.self) {
            try await login.value
        }
        #expect(model.account(with: account.email) == nil)
        #expect(try await accountStore.loadAccounts().isEmpty)
        #expect(try await secretStore.loadSecret(for: account.email) == nil)
    }

    @Test
    func inFlightLoginDoesNotRestoreDeletedAccount() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let secretStore = SecretStore(backend: InMemorySecretBackend())
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        let secret = StoredAccountSecret(account: sampleAccount())
        _ = try await accountStore.upsert(meta)
        try await secretStore.save(secret, for: meta.id)

        let gate = RefreshGate()
        let bridge = SessionBridgeStub(loginResult: SessionRefreshResult(meta: meta, secret: secret))
        bridge.beforeLogin = { await gate.suspend() }
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: secretStore,
            sessionBridge: bridge
        )
        await model.loadAccountsIfNeeded()

        let login = Task {
            try await model.addAccount(
                email: meta.email,
                password: secret.password,
                code: "",
                deviceIdentifier: meta.deviceIdentifier,
                probeBundleID: meta.probeBundleID
            )
        }
        await gate.waitUntilStarted()

        try await model.deleteAccount(id: meta.id)
        gate.release()

        await #expect(throws: MitoriError.operationSuperseded) {
            try await login.value
        }
        #expect(model.account(with: meta.id) == nil)
        #expect(try await secretStore.loadSecret(for: meta.id) == nil)
    }

    @Test
    func inFlightLoginIsNotSupersededByAutoRefresh() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let secretStore = SecretStore(backend: InMemorySecretBackend())
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        let oldSecret = StoredAccountSecret(account: sampleAccount())
        var refreshedAccount = sampleAccount()
        refreshedAccount.passwordToken = "new-token"
        let newSecret = StoredAccountSecret(account: refreshedAccount)
        _ = try await accountStore.upsert(meta)
        try await secretStore.save(oldSecret, for: meta.id)

        let gate = RefreshGate()
        let bridge = SessionBridgeStub(
            loginResult: SessionRefreshResult(meta: meta, secret: newSecret),
            refreshResult: SessionRefreshResult(meta: meta, secret: oldSecret)
        )
        bridge.beforeLogin = { await gate.suspend() }
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: secretStore,
            sessionBridge: bridge
        )
        await model.loadAccountsIfNeeded()

        let login = Task {
            try await model.addAccount(
                email: meta.email,
                password: newSecret.password,
                code: "",
                deviceIdentifier: meta.deviceIdentifier,
                probeBundleID: meta.probeBundleID
            )
        }
        await gate.waitUntilStarted()

        await model.refreshAccount(id: meta.id, isManualRefresh: false)
        #expect(bridge.refreshCallCount == 0)
        gate.release()

        #expect(try await login.value == meta.id)
        #expect(try await secretStore.loadSecret(for: meta.id) == newSecret)
    }

    private struct SuspendedRefreshContext {
        var model: MitoriModel
        var secretStore: SecretStore
        var meta: StoredAccountMeta
        var gate: RefreshGate
        var bridge: SessionBridgeStub
        var tempDirectory: URL
    }

    private func makeSuspendedRefreshContext() async throws -> SuspendedRefreshContext {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let secretStore = SecretStore(backend: InMemorySecretBackend())
        let meta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.example.probe"
        )
        let secret = StoredAccountSecret(account: sampleAccount())
        _ = try await accountStore.upsert(meta)
        try await secretStore.save(secret, for: meta.id)

        let gate = RefreshGate()
        let refreshedMeta = StoredAccountMeta(
            account: sampleAccount(),
            deviceIdentifier: meta.deviceIdentifier,
            probeBundleID: meta.probeBundleID,
            lastRefreshAt: Date()
        )
        let bridge = SessionBridgeStub(refreshResult: SessionRefreshResult(meta: refreshedMeta, secret: secret))
        bridge.beforeRefresh = {
            await gate.suspend()
        }
        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: secretStore,
            sessionBridge: bridge
        )
        await model.loadAccountsIfNeeded()

        return SuspendedRefreshContext(
            model: model,
            secretStore: secretStore,
            meta: meta,
            gate: gate,
            bridge: bridge,
            tempDirectory: tempDirectory
        )
    }
}
