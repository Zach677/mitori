import ApplePackage
import CoreGraphics
import Foundation

@MainActor
final class MitoriModel {
    private let accountStore: AccountStore
    private let secretStore: SecretStore
    private let sessionBridge: any AppleSessionBridging
    private let settings: RefreshSettingsStore

    private(set) var accounts: [StoredAccountMeta] = []
    private(set) var refreshStates: [String: RefreshState] = [:]

    var bannerMessage: String?
    var isRefreshingAll = false

    private var hasLoadedAccounts = false

    init(
        accountStore: AccountStore = AccountStore(),
        secretStore: SecretStore = SecretStore(),
        sessionBridge: any AppleSessionBridging = AppleSessionBridge(),
        settings: RefreshSettingsStore = RefreshSettingsStore()
    ) {
        self.accountStore = accountStore
        self.secretStore = secretStore
        self.sessionBridge = sessionBridge
        self.settings = settings
    }

    func menuPresented() async {
        await ensureAccountsLoaded()
    }

    func autoRefreshTick() async {
        guard settings.isAutoRefreshEnabled else { return }
        guard !isScreenLocked() else { return }
        await ensureAccountsLoaded()
        guard !accounts.isEmpty, !isRefreshingAll else { return }

        for accountID in accounts.map(\.id) {
            await refreshAccount(id: accountID, isManualRefresh: false)
        }
    }

    func account(with id: String?) -> StoredAccountMeta? {
        guard let id else { return nil }
        return accounts.first(where: { $0.id == id })
    }

    func refreshState(for accountID: String) -> RefreshState {
        refreshStates[accountID] ?? .idle
    }

    func addAccount(
        email: String,
        password: String,
        code: String,
        deviceIdentifier: String,
        probeBundleID: String
    ) async throws -> String {
        let result = try await sessionBridge.login(
            email: email,
            password: password,
            code: code,
            deviceIdentifier: deviceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            probeBundleID: probeBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        try await persist(normalized(result))
        bannerMessage = result.meta.lastIssue?.message
        return result.meta.id
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

    func startRefresh(accountID: String) {
        guard account(with: accountID) != nil else { return }
        refreshStates[accountID] = .refreshing
    }

    func refreshAccount(id: String, isManualRefresh: Bool) async {
        guard let meta = account(with: id) else { return }
        if !isManualRefresh, !shouldAutoRefresh(meta) { return }
        if !isManualRefresh, case .refreshing = refreshState(for: id) { return }

        refreshStates[id] = .refreshing

        do {
            guard let secret = try await secretStore.loadSecret(for: id) else {
                throw MitoriError.missingSecret
            }
            let result = try await sessionBridge.refreshBalance(meta: meta, secret: secret)
            try await persist(normalized(result))
            applyPostRefreshState(for: id, using: result)
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
        if let error = applyPostRefreshState(for: id, using: result) {
            throw error
        }
    }

    func saveProbeBundleID(_ probeBundleID: String, for accountID: String) async throws {
        guard var meta = account(with: accountID) else { return }
        let trimmedProbeBundleID = probeBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.probeBundleID = trimmedProbeBundleID

        if trimmedProbeBundleID.isEmpty {
            meta.lastIssue = MitoriError.missingProbeBundleID.refreshIssue()
        } else if meta.lastIssue?.kind == .probeConfigurationMissing {
            meta.lastIssue = nil
            meta.nextEligibleRefreshAt = nil
            meta.consecutiveFailureCount = 0
        }

        accounts = try await accountStore.upsert(meta)

        if trimmedProbeBundleID.isEmpty {
            bannerMessage = MitoriError.missingProbeBundleID.localizedDescription
        } else if bannerMessage == MitoriError.missingProbeBundleID.localizedDescription {
            bannerMessage = nil
        }
    }

    func deleteAccount(id: String) async {
        do {
            accounts = try await accountStore.deleteAccount(id: id)
            try await secretStore.deleteSecret(for: id)
            bannerMessage = nil
        } catch {
            bannerMessage = MitoriError.map(error).localizedDescription
        }
    }

    private func ensureAccountsLoaded() async {
        if !hasLoadedAccounts {
            await reloadAccounts()
            hasLoadedAccounts = true
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

    private func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        // kCGSSessionOnConsoleKey is not Swift-exported; use its stable string value.
        return !(dict["kCGSSessionOnConsoleKey"] as? Bool ?? true)
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

        return now.timeIntervalSince(lastRefreshAt) >= settings.autoRefreshInterval
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

    @discardableResult
    private func applyPostRefreshState(for accountID: String, using result: SessionRefreshResult) -> MitoriError? {
        if let issue = result.meta.lastIssue {
            refreshStates[accountID] = .failed(issue.kind)
            bannerMessage = issue.message
            return MitoriError.from(refreshIssue: issue)
        }

        refreshStates[accountID] = .succeeded(result.meta.lastRefreshAt ?? Date())
        bannerMessage = nil
        return nil
    }
}
