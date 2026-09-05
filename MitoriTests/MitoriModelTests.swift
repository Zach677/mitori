import Foundation
import Testing

@testable import Mitori

@MainActor
struct MitoriModelTests {
    @Test
    func savingProbeBundleIDClearsProbeConfigurationIssue() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
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

        let model = MitoriModel(
            accountStore: accountStore,
            secretStore: SecretStore(backend: InMemorySecretBackend()),
            sessionBridge: AppleSessionBridge()
        )
        model.bannerMessage = MitoriError.missingProbeBundleID.localizedDescription

        await model.menuPresented()
        try await model.saveProbeBundleID(" com.example.probe ", for: meta.id)

        let updated = try #require(model.account(with: meta.id))
        #expect(updated.probeBundleID == "com.example.probe")
        #expect(updated.lastIssue == nil)
        #expect(updated.nextEligibleRefreshAt == nil)
        #expect(updated.consecutiveFailureCount == 0)
        #expect(model.bannerMessage == nil)
    }

    @Test
    func clearingProbeBundleIDDoesNotCreateConfigurationIssue() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
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

        await model.menuPresented()
        try await model.saveProbeBundleID(" ", for: meta.id)

        let updated = try #require(model.account(with: meta.id))
        #expect(updated.probeBundleID.isEmpty)
        #expect(updated.lastIssue == nil)
        #expect(model.bannerMessage == nil)
    }

    @Test
    func menuPresentationDoesNotStartKeychainBackedRefresh() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
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

        await model.menuPresented()

        #expect(model.account(with: meta.id) != nil)
        #expect(model.refreshState(for: meta.id) == .idle)
        #expect(model.bannerMessage == nil)
    }

    @Test
    func refreshAccountMarksReturnedIssueAsFailure() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
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

        await model.menuPresented()
        await model.refreshAccount(id: meta.id, isManualRefresh: true)

        #expect(model.refreshState(for: meta.id) == .failed(.sessionExpired))
        #expect(model.bannerMessage == MitoriError.sessionExpired.localizedDescription)
    }

    @Test
    func completedRefreshDoesNotRestoreDeletedAccount() async throws {
        let context = try await makeSuspendedRefreshContext()

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
        await model.menuPresented()

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
    func failedSecretDeletionKeepsAccountVisible() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
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
        await model.menuPresented()

        await #expect(throws: MitoriError.self) {
            try await model.deleteAccount(id: meta.id)
        }

        #expect(model.account(with: meta.id) != nil)
        #expect(try await secretStore.loadSecret(for: meta.id) != nil)
    }

    @Test
    func failedMetadataDeletionRestoresSecret() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
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
        await model.menuPresented()

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
        await model.menuPresented()

        await model.refreshAccount(id: meta.id, isManualRefresh: true)

        #expect(try await secretStore.loadSecret(for: meta.id) == previousSecret)
        let failed = try #require(model.account(with: meta.id))
        #expect(failed.consecutiveFailureCount == 1)
        #expect(failed.nextEligibleRefreshAt == fixedDate.addingTimeInterval(60))
        #expect(failed.lastIssue?.kind == .unknown)
        #expect(model.bannerMessage?.hasPrefix("Storage error:") == true)
    }

    @Test
    func concurrentManualRefreshIsSingleFlight() async throws {
        let context = try await makeSuspendedRefreshContext()
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
        await model.menuPresented()

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
    func reauthenticateThrowsWhenReturnedIssuePersists() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
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

        await model.menuPresented()

        await #expect(throws: MitoriError.sessionExpired) {
            try await model.reauthenticateAccount(id: meta.id, code: "")
        }

        #expect(model.refreshState(for: meta.id) == .failed(.sessionExpired))
        #expect(model.bannerMessage == MitoriError.sessionExpired.localizedDescription)
    }

    @Test
    func addAccountUsesFlowDeviceIdentifier() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
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
        await model.menuPresented()

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
        await model.menuPresented()

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
        await model.menuPresented()

        return SuspendedRefreshContext(
            model: model,
            secretStore: secretStore,
            meta: meta,
            gate: gate,
            bridge: bridge
        )
    }
}
