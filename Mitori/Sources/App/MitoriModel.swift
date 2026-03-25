import ApplePackage
import Foundation
import Observation

@MainActor
@Observable
final class MitoriModel {
    private let accountStore: AccountStore
    private let secretStore: SecretStore
    private let sessionBridge: AppleSessionBridge

    private(set) var accounts: [StoredAccountMeta] = []
    private(set) var refreshStates: [String: RefreshState] = [:]
    private(set) var secretSummaries: [String: String] = [:]

    var isPresentingAddAccount = false
    var selectedAccountID: String?
    var bannerMessage: String?
    var isRefreshingAll = false

    private var hasLoadedAccounts = false

    init(
        accountStore: AccountStore = AccountStore(),
        secretStore: SecretStore = SecretStore(),
        sessionBridge: AppleSessionBridge = AppleSessionBridge()
    ) {
        self.accountStore = accountStore
        self.secretStore = secretStore
        self.sessionBridge = sessionBridge
    }

    static func live() -> MitoriModel {
        MitoriModel()
    }

    var selectedAccount: StoredAccountMeta? {
        account(with: selectedAccountID)
    }

    func menuPresented() async {
        if !hasLoadedAccounts {
            await reloadAccounts()
            hasLoadedAccounts = true
        }
        await refreshStaleAccountsIfNeeded()
    }

    func account(with id: String?) -> StoredAccountMeta? {
        guard let id else { return nil }
        return accounts.first(where: { $0.id == id })
    }

    func refreshState(for accountID: String) -> RefreshState {
        refreshStates[accountID] ?? .idle
    }

    func secretSummary(for accountID: String) -> String {
        secretSummaries[accountID] ?? "Unavailable"
    }

    func openAddAccount() {
        bannerMessage = nil
        isPresentingAddAccount = true
    }

    func dismissDetails() {
        selectedAccountID = nil
    }

    func loadSecretSummary(for accountID: String) async {
        do {
            let summary = try await secretStore.loadSecret(for: accountID)?.dsidSummary ?? "Unavailable"
            secretSummaries[accountID] = summary
        } catch {
            secretSummaries[accountID] = "Unavailable"
        }
    }

    func addAccount(
        email: String,
        password: String,
        code: String,
        probeBundleID: String
    ) async throws {
        let deviceIdentifier = DeviceIdentifier.random()
        let result = try await sessionBridge.login(
            email: email,
            password: password,
            code: code,
            deviceIdentifier: deviceIdentifier,
            probeBundleID: probeBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        try await persist(normalized(result))
        bannerMessage = result.meta.lastIssue?.message
        isPresentingAddAccount = false
    }

    func refreshAll() async {
        guard !accounts.isEmpty, !isRefreshingAll else { return }
        isRefreshingAll = true
        defer { isRefreshingAll = false }

        let accountIDs = accounts.map(\.id)
        for accountID in accountIDs {
            await refreshAccount(id: accountID, isManualRefresh: true)
        }
    }

    func refreshAccount(id: String, isManualRefresh: Bool) async {
        guard let meta = account(with: id) else { return }
        if !isManualRefresh, !shouldAutoRefresh(meta) { return }
        if case .refreshing = refreshState(for: id) { return }

        refreshStates[id] = .refreshing

        do {
            guard let secret = try await secretStore.loadSecret(for: id) else {
                throw MitoriError.missingSecret
            }
            let result = try await sessionBridge.refreshBalance(meta: meta, secret: secret)
            try await persist(normalized(result))
            refreshStates[id] = .succeeded(result.meta.lastRefreshAt ?? Date())
            bannerMessage = nil
        } catch {
            let storedError = MitoriError.map(error)
            try? await persistFailure(for: meta, error: storedError)
            refreshStates[id] = .failed(storedError.issueKind)
            bannerMessage = storedError.localizedDescription
        }
    }

    func reauthenticateAccount(id: String, code: String) async throws {
        guard let meta = account(with: id) else { return }
        guard let secret = try await secretStore.loadSecret(for: id) else {
            throw MitoriError.missingSecret
        }

        refreshStates[id] = .refreshing
        let result = try await sessionBridge.reauthenticate(meta: meta, secret: secret, code: code)
        try await persist(normalized(result))
        refreshStates[id] = .succeeded(result.meta.lastRefreshAt ?? Date())
        bannerMessage = result.meta.lastIssue?.message
    }

    func saveProbeBundleID(_ probeBundleID: String, for accountID: String) async throws {
        guard var meta = account(with: accountID) else { return }
        meta.probeBundleID = probeBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts = try await accountStore.upsert(meta)
    }

    func deleteAccount(id: String) async {
        do {
            accounts = try await accountStore.deleteAccount(id: id)
            try await secretStore.deleteSecret(for: id)
            secretSummaries[id] = nil
            if selectedAccountID == id {
                selectedAccountID = nil
            }
            bannerMessage = nil
        } catch {
            bannerMessage = MitoriError.map(error).localizedDescription
        }
    }

    private func reloadAccounts() async {
        do {
            accounts = try await accountStore.loadAccounts()
        } catch {
            bannerMessage = MitoriError.map(error).localizedDescription
        }
    }

    private func persist(_ result: SessionRefreshResult) async throws {
        try await secretStore.save(result.secret, for: result.meta.id)
        accounts = try await accountStore.upsert(result.meta)
        secretSummaries[result.meta.id] = result.secret.dsidSummary
    }

    private func persistFailure(for meta: StoredAccountMeta, error: MitoriError) async throws {
        var failed = meta
        failed.lastIssue = error.refreshIssue()
        failed.consecutiveFailureCount += 1
        failed.nextEligibleRefreshAt = Date().addingTimeInterval(backoffInterval(for: failed.consecutiveFailureCount))
        accounts = try await accountStore.upsert(failed)
    }

    private func normalized(_ result: SessionRefreshResult) -> SessionRefreshResult {
        var normalized = result
        if normalized.meta.lastIssue == nil {
            normalized.meta.consecutiveFailureCount = 0
            normalized.meta.nextEligibleRefreshAt = nil
            return normalized
        }

        normalized.meta.consecutiveFailureCount = max(1, normalized.meta.consecutiveFailureCount)
        normalized.meta.nextEligibleRefreshAt = Date().addingTimeInterval(
            backoffInterval(for: normalized.meta.consecutiveFailureCount)
        )
        return normalized
    }

    private func refreshStaleAccountsIfNeeded() async {
        let staleAccountIDs = accounts
            .filter(shouldAutoRefresh(_:))
            .map(\.id)

        for accountID in staleAccountIDs {
            await refreshAccount(id: accountID, isManualRefresh: false)
        }
    }

    private func shouldAutoRefresh(_ meta: StoredAccountMeta) -> Bool {
        if case .refreshing = refreshState(for: meta.id) {
            return false
        }

        let now = Date()
        if let nextEligibleRefreshAt = meta.nextEligibleRefreshAt, nextEligibleRefreshAt > now {
            return false
        }

        guard let lastRefreshAt = meta.lastRefreshAt else {
            return meta.balanceSnapshot == nil
        }

        return now.timeIntervalSince(lastRefreshAt) >= 15 * 60
    }

    private func backoffInterval(for failureCount: Int) -> TimeInterval {
        switch failureCount {
        case ...1:
            return 60
        case 2:
            return 5 * 60
        default:
            return 15 * 60
        }
    }
}
