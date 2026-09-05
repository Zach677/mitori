import Combine
import CoreGraphics
import Foundation

@MainActor
final class MitoriModel {
    private let repository: AccountRepository
    private let sessionBridge: any AppleSessionBridging
    private let settings: RefreshSettingsStore
    private let now: () -> Date
    private let screenIsLocked: @MainActor () -> Bool

    private(set) var accounts: [StoredAccountMeta] = [] {
        didSet { changeSubject.send() }
    }
    private(set) var refreshStates: [String: RefreshState] = [:] {
        didSet { changeSubject.send() }
    }

    var bannerMessage: String? {
        didSet { changeSubject.send() }
    }
    var isRefreshingAll = false {
        didSet { changeSubject.send() }
    }
    var changes: AnyPublisher<Void, Never> {
        changeSubject.eraseToAnyPublisher()
    }

    private let changeSubject = PassthroughSubject<Void, Never>()
    private var hasLoadedAccounts = false
    private var accountGenerations: [String: Int] = [:]
    private var mutatingAccountIDs: Set<String> = []
    private var pendingLoginGenerations: [String: Int] = [:]

    init(
        accountStore: AccountStore = AccountStore(),
        secretStore: SecretStore = SecretStore(),
        sessionBridge: any AppleSessionBridging = AppleSessionBridge(),
        settings: RefreshSettingsStore = RefreshSettingsStore(),
        now: @escaping () -> Date = Date.init,
        screenIsLocked: @escaping @MainActor () -> Bool = MitoriModel.currentScreenIsLocked
    ) {
        repository = AccountRepository(accountStore: accountStore, secretStore: secretStore)
        self.sessionBridge = sessionBridge
        self.settings = settings
        self.now = now
        self.screenIsLocked = screenIsLocked
    }

    func menuPresented() async {
        await ensureAccountsLoaded()
    }

    func autoRefreshTick() async {
        guard settings.isAutoRefreshEnabled else { return }
        guard !screenIsLocked() else { return }
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
        try Task.checkCancellation()
        let accountID = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !mutatingAccountIDs.contains(accountID), pendingLoginGenerations[accountID] == nil else {
            throw MitoriError.operationInProgress
        }
        let generation = nextGeneration(for: accountID)
        pendingLoginGenerations[accountID] = generation
        refreshStates[accountID] = .idle
        defer {
            if pendingLoginGenerations[accountID] == generation {
                pendingLoginGenerations[accountID] = nil
            }
        }

        let result = normalized(try await sessionBridge.login(
            email: email,
            password: password,
            code: code,
            deviceIdentifier: deviceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            probeBundleID: probeBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        try Task.checkCancellation()
        guard result.meta.id == accountID else {
            throw MitoriError.unknown("Authenticated account does not match the requested email.")
        }
        guard operationIsCurrent(for: accountID, generation: generation) else {
            throw MitoriError.operationSuperseded
        }
        pendingLoginGenerations[accountID] = nil
        mutatingAccountIDs.insert(accountID)
        defer { finishMutation(for: accountID) }

        let updatedAccounts = try await repository.commit(result, respectingCancellation: true)
        try Task.checkCancellation()
        guard operationIsCurrent(for: accountID, generation: generation) else {
            throw MitoriError.operationSuperseded
        }
        accounts = updatedAccounts
        bannerMessage = result.meta.lastIssue?.message
        return accountID
    }

    func refreshAll() async {
        guard !accounts.isEmpty, !isRefreshingAll else { return }
        isRefreshingAll = true
        defer { isRefreshingAll = false }

        for accountID in accounts.map(\.id) {
            await refreshAccount(id: accountID, isManualRefresh: true)
        }
    }

    func refreshAccount(id: String, isManualRefresh: Bool) async {
        guard let meta = account(with: id) else { return }
        if !isManualRefresh, !shouldAutoRefresh(meta) { return }
        guard let generation = beginOperation(for: id) else { return }

        do {
            guard let secret = try await repository.loadSecret(
                for: id,
                allowsAuthenticationUI: isManualRefresh
            ) else {
                throw MitoriError.missingSecret
            }
            guard operationIsCurrent(for: id, generation: generation, requireAccount: true) else { return }
            let result = normalized(try await sessionBridge.refreshBalance(meta: meta, secret: secret))
            guard operationIsCurrent(for: id, generation: generation, requireAccount: true) else { return }
            let updatedAccounts = try await repository.commit(
                result,
                allowsAuthenticationUI: isManualRefresh
            )
            guard operationIsCurrent(for: id, generation: generation, requireAccount: true) else { return }
            accounts = updatedAccounts
            applyPostRefreshState(for: id, using: result)
        } catch {
            if !isManualRefresh, isKeychainInteractionNotAllowed(error) {
                if operationIsCurrent(for: id, generation: generation, requireAccount: true) {
                    refreshStates[id] = .idle
                }
                return
            }
            guard operationIsCurrent(for: id, generation: generation, requireAccount: true) else { return }

            let refreshError = MitoriError.map(error)
            let storageError = await recordFailure(for: meta, error: refreshError, generation: generation)
            guard operationIsCurrent(for: id, generation: generation, requireAccount: true) else { return }
            refreshStates[id] = .failed(refreshError.issueKind)
            bannerMessage = storageError?.localizedDescription ?? refreshError.localizedDescription
        }
    }

    func reauthenticateAccount(id: String, code: String) async throws {
        guard let meta = account(with: id) else { return }
        guard let generation = beginOperation(for: id) else {
            throw MitoriError.operationInProgress
        }

        do {
            guard let secret = try await repository.loadSecret(for: id) else {
                throw MitoriError.missingSecret
            }
            guard operationIsCurrent(for: id, generation: generation, requireAccount: true) else {
                throw MitoriError.operationSuperseded
            }
            let result = normalized(try await sessionBridge.reauthenticate(meta: meta, secret: secret, code: code))
            guard operationIsCurrent(for: id, generation: generation, requireAccount: true) else {
                throw MitoriError.operationSuperseded
            }
            let updatedAccounts = try await repository.commit(result)
            guard operationIsCurrent(for: id, generation: generation, requireAccount: true) else {
                throw MitoriError.operationSuperseded
            }
            accounts = updatedAccounts
            if let error = applyPostRefreshState(for: id, using: result) {
                throw error
            }
        } catch {
            let mappedError = MitoriError.map(error)
            if operationIsCurrent(for: id, generation: generation, requireAccount: true) {
                refreshStates[id] = .failed(mappedError.issueKind)
                bannerMessage = mappedError.localizedDescription
            }
            throw mappedError
        }
    }

    func saveProbeBundleID(_ probeBundleID: String, for accountID: String) async throws {
        guard account(with: accountID) != nil else { return }
        let generation = try beginMutation(for: accountID)
        defer { finishMutation(for: accountID) }
        let trimmedProbeBundleID = probeBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedAccounts = try await repository.updateMeta(id: accountID) { latest in
            var updated = latest
            updated.probeBundleID = trimmedProbeBundleID

            if updated.lastIssue?.kind == .probeConfigurationMissing {
                updated.lastIssue = nil
                updated.nextEligibleRefreshAt = nil
                updated.consecutiveFailureCount = 0
            }
            return updated
        }
        guard operationIsCurrent(for: accountID, generation: generation) else { return }
        accounts = updatedAccounts

        if bannerMessage == MitoriError.missingProbeBundleID.localizedDescription {
            bannerMessage = nil
        }
    }

    func deleteAccount(id: String) async throws {
        guard account(with: id) != nil else { return }
        let generation = try beginMutation(for: id)
        defer { finishMutation(for: id) }
        do {
            let remainingAccounts = try await repository.deleteAccount(id: id)
            guard operationIsCurrent(for: id, generation: generation) else { return }
            accounts = remainingAccounts
            refreshStates[id] = nil
            bannerMessage = nil
        } catch {
            let mappedError = MitoriError.map(error)
            bannerMessage = mappedError.localizedDescription
            throw mappedError
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
            accounts = try await repository.loadAccounts()
        } catch {
            bannerMessage = MitoriError.map(error).localizedDescription
        }
    }

    private func recordFailure(
        for meta: StoredAccountMeta,
        error: MitoriError,
        generation: Int
    ) async -> MitoriError? {
        var failed = meta
        let currentDate = now()
        failed.lastIssue = error.refreshIssue(at: currentDate)
        failed.consecutiveFailureCount += 1
        failed.nextEligibleRefreshAt = currentDate.addingTimeInterval(
            backoffInterval(for: failed.consecutiveFailureCount)
        )

        if let index = accounts.firstIndex(where: { $0.id == meta.id }) {
            accounts[index] = failed
        }

        do {
            let updatedAccounts = try await repository.upsert(failed)
            if operationIsCurrent(for: meta.id, generation: generation, requireAccount: true) {
                accounts = updatedAccounts
            }
            return nil
        } catch {
            return MitoriError.map(error)
        }
    }

    private func normalized(_ result: SessionRefreshResult) -> SessionRefreshResult {
        var normalized = result
        if normalized.meta.lastIssue == nil {
            normalized.meta.consecutiveFailureCount = 0
            normalized.meta.nextEligibleRefreshAt = nil
            return normalized
        }

        normalized.meta.consecutiveFailureCount = max(1, normalized.meta.consecutiveFailureCount)
        normalized.meta.nextEligibleRefreshAt = now().addingTimeInterval(
            backoffInterval(for: normalized.meta.consecutiveFailureCount)
        )
        return normalized
    }

    private static func currentScreenIsLocked() -> Bool {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any],
              let isLocked = dictionary["CGSSessionScreenIsLocked"] as? Bool
        else {
            return true
        }
        return isLocked
    }

    private func shouldAutoRefresh(_ meta: StoredAccountMeta) -> Bool {
        if case .refreshing = refreshState(for: meta.id) {
            return false
        }

        let currentDate = now()
        if let nextEligibleRefreshAt = meta.nextEligibleRefreshAt, nextEligibleRefreshAt > currentDate {
            return false
        }

        guard let lastRefreshAt = meta.lastRefreshAt else {
            return meta.balanceSnapshot == nil
        }

        return currentDate.timeIntervalSince(lastRefreshAt) >= settings.autoRefreshInterval
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

    private func beginOperation(for accountID: String) -> Int? {
        guard !mutatingAccountIDs.contains(accountID) else { return nil }
        guard pendingLoginGenerations[accountID] == nil else { return nil }
        if case .refreshing = refreshState(for: accountID) {
            return nil
        }
        let generation = nextGeneration(for: accountID)
        refreshStates[accountID] = .refreshing
        return generation
    }

    private func beginMutation(for accountID: String) throws -> Int {
        guard !mutatingAccountIDs.contains(accountID) else {
            throw MitoriError.operationInProgress
        }
        pendingLoginGenerations[accountID] = nil
        mutatingAccountIDs.insert(accountID)
        let generation = nextGeneration(for: accountID)
        refreshStates[accountID] = .idle
        return generation
    }

    private func finishMutation(for accountID: String) {
        mutatingAccountIDs.remove(accountID)
    }

    private func nextGeneration(for accountID: String) -> Int {
        let generation = accountGenerations[accountID, default: 0] + 1
        accountGenerations[accountID] = generation
        return generation
    }

    private func operationIsCurrent(
        for accountID: String,
        generation: Int,
        requireAccount: Bool = false
    ) -> Bool {
        guard accountGenerations[accountID, default: 0] == generation else { return false }
        return !requireAccount || account(with: accountID) != nil
    }

    @discardableResult
    private func applyPostRefreshState(
        for accountID: String,
        using result: SessionRefreshResult
    ) -> MitoriError? {
        if let issue = result.meta.lastIssue {
            refreshStates[accountID] = .failed(issue.kind)
            bannerMessage = issue.message
            return MitoriError.from(refreshIssue: issue)
        }

        refreshStates[accountID] = .succeeded(result.meta.lastRefreshAt ?? now())
        bannerMessage = nil
        return nil
    }
}
