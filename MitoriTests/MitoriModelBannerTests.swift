import Foundation
import Testing

@testable import Mitori

@MainActor
struct MitoriModelBannerTests {
    @Test
    func successClearsOnlyItsOwnBanner() async throws {
        let context = try await makeTwoAccountContext()
        context.failingIDs.value = [context.second]

        await context.model.refreshAccount(id: context.second, isManualRefresh: true)
        let secondBanner = try #require(context.model.bannerMessage)

        await context.model.refreshAccount(id: context.first, isManualRefresh: true)
        #expect(context.model.bannerMessage == secondBanner)

        context.failingIDs.value = []
        await context.model.refreshAccount(id: context.second, isManualRefresh: true)
        #expect(context.model.bannerMessage == nil)
    }

    @Test
    func deletingAnAccountClearsOnlyItsOwnBanner() async throws {
        let context = try await makeTwoAccountContext()
        context.failingIDs.value = [context.second]
        await context.model.refreshAccount(id: context.second, isManualRefresh: true)
        let secondBanner = try #require(context.model.bannerMessage)

        try await context.model.deleteAccount(id: context.first)
        #expect(context.model.bannerMessage == secondBanner)

        try await context.model.deleteAccount(id: context.second)
        #expect(context.model.bannerMessage == nil)
    }

    @Test
    func unownedErrorSurvivesAnAccountSuccess() async throws {
        let context = try await makeTwoAccountContext()
        context.model.bannerMessage = MitoriError.storage("disk full").localizedDescription

        await context.model.refreshAccount(id: context.first, isManualRefresh: true)
        try await context.model.deleteAccount(id: context.second)

        #expect(context.model.bannerMessage == MitoriError.storage("disk full").localizedDescription)
    }

    private final class FailingIDs {
        var value: Set<String> = []
    }

    private struct TwoAccountContext {
        var model: MitoriModel
        var failingIDs: FailingIDs
        var first: String
        var second: String
    }

    private func makeTwoAccountContext() async throws -> TwoAccountContext {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let accountStore = AccountStore(baseDirectory: tempDirectory)
        let secretStore = SecretStore(backend: InMemorySecretBackend())

        var secondAccount = sampleAccount()
        secondAccount.email = "other@example.com"
        var ids: [String] = []
        for account in [sampleAccount(), secondAccount] {
            let meta = StoredAccountMeta(
                account: account,
                deviceIdentifier: "ABCDEF123456",
                probeBundleID: "com.example.probe"
            )
            _ = try await accountStore.upsert(meta)
            try await secretStore.save(StoredAccountSecret(account: account), for: meta.id)
            ids.append(meta.id)
        }

        let failingIDs = FailingIDs()
        let bridge = SessionBridgeStub()
        bridge.refreshHandler = { meta in
            if failingIDs.value.contains(meta.id) {
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
        await model.menuPresented()
        return TwoAccountContext(model: model, failingIDs: failingIDs, first: ids[0], second: ids[1])
    }
}
