import Combine
import Foundation
import Testing

@testable import Mitori

@MainActor
struct AccountRepositoryConcurrencyTests {
    @Test
    func queuedProbeEditPreservesRefreshFieldsFromLatestMetadata() async throws {
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

        let refreshDate = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = BalanceSnapshot(
            displayText: "USD 42.00",
            numericValue: 42,
            currencyCode: "USD",
            fetchedAt: refreshDate,
            source: .probe,
            rawFieldPath: "creditDisplay"
        )
        var refreshedMeta = meta
        refreshedMeta.balanceSnapshot = snapshot
        refreshedMeta.lastRefreshAt = refreshDate
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

        let probeEdit = Task {
            try await model.saveProbeBundleID("com.example.new-probe", for: meta.id)
        }
        if model.refreshState(for: meta.id) == .refreshing {
            for await _ in model.changes.values {
                if model.refreshState(for: meta.id) != .refreshing {
                    break
                }
            }
        }

        writeGate.release()
        await refresh.value
        try await probeEdit.value

        let stored = try #require(model.account(with: meta.id))
        #expect(stored.probeBundleID == "com.example.new-probe")
        #expect(stored.balanceSnapshot == snapshot)
        #expect(stored.lastRefreshAt == refreshDate)
    }
}
