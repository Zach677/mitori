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
        #expect(context.secretBackend.readAllowsAuthenticationUI == [false, false])
        #expect(context.secretBackend.writeAllowsAuthenticationUI == [true, false])
        guard case .succeeded = context.model.refreshState(for: context.accountID) else {
            Issue.record("Expected succeeded state, got \(context.model.refreshState(for: context.accountID))")
            return
        }
    }

    private struct AutoRefreshContext {
        var model: MitoriModel
        var bridge: SessionBridgeStub
        var secretBackend: RecordingSecretBackend
        var accountID: String
        var defaultsSuiteName: String

        func cleanUp() {
            UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(forName: defaultsSuiteName)
        }
    }

    private func makeAutoRefreshContext(
        enabled: Bool,
        lastRefreshAt: Date,
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
            probeBundleID: "com.example.probe",
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
            screenIsLocked: { screenIsLocked }
        )
        return AutoRefreshContext(
            model: model,
            bridge: bridge,
            secretBackend: secretBackend,
            accountID: meta.id,
            defaultsSuiteName: suiteName
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
