//
//  MitoriModel.swift
//  Mitori
//
//  Created by @Zach677 on 2026/03/25.
//

import Combine
import CoreGraphics
import Foundation

enum ModelChange: Equatable, Sendable {
    case accounts
    case account(String)
    case banner
    case loadError
    case refreshingAll
}

@MainActor
final class MitoriModel {
    private struct ActiveOperation {
        enum Kind {
            case refresh
            case login
            case mutation
        }

        var kind: Kind
        var token: UUID
    }

    private let repository: AccountRepository
    private let sessionBridge: any AppleSessionBridging
    private let settings: RefreshSettingsStore
    private let now: () -> Date
    private let screenIsLocked: @MainActor () -> Bool

    private(set) var accounts: [StoredAccountMeta] = [] {
        didSet { changeSubject.send(.accounts) }
    }
    private(set) var refreshStates: [String: RefreshState] = [:]
    private(set) var loadError: String? {
        didSet { changeSubject.send(.loadError) }
    }

    var accountsDirectoryURL: URL {
        repository.accountsDirectoryURL
    }

    /// A message set from outside the model has no owner (I-10).
    var bannerMessage: String? {
        didSet {
            bannerAccountID = nil
            changeSubject.send(.banner)
        }
    }
    private(set) var isRefreshingAll = false {
        didSet { changeSubject.send(.refreshingAll) }
    }
    var changeEvents: AnyPublisher<ModelChange, Never> {
        changeSubject.eraseToAnyPublisher()
    }
    var changes: AnyPublisher<Void, Never> {
        changeSubject.map { _ in () }.eraseToAnyPublisher()
    }

    private let changeSubject = PassthroughSubject<ModelChange, Never>()
    private var hasLoadedAccounts = false
    private var activeOperations: [String: ActiveOperation] = [:]
    private var bannerAccountID: String?

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
        await loadAccountsIfNeeded()
    }

    func loadAccountsIfNeeded() async {
        await ensureAccountsLoaded()
    }

    func retryLoadAccounts() async {
        hasLoadedAccounts = false
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

    /// The earliest time any account is eligible for automatic refresh, or `nil` when none is scheduled.
    func nextAutoRefreshDate() -> Date? {
        guard settings.isAutoRefreshEnabled else { return nil }
        guard hasLoadedAccounts else { return now() }

        let currentDate = now()
        return accounts.compactMap { nextAutoRefreshDate(for: $0, at: currentDate) }.min()
    }

    /// The next scheduled automatic refresh date for a single account, or `nil` when automatic
    /// refresh is off or this account is not eligible.
    func nextAutoRefreshDate(for accountID: String) -> Date? {
        guard settings.isAutoRefreshEnabled,
              let meta = account(with: accountID)
        else {
            return nil
        }
        return nextAutoRefreshDate(for: meta, at: now())
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
        await ensureAccountsLoaded()
        let accountID = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let token = try beginLogin(for: accountID)
        defer { finishOperation(for: accountID, token: token) }

        // Re-adding an account keeps its history; an empty probe field keeps the stored probe.
        let existing = account(with: accountID)
        let trimmedProbeBundleID = probeBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = normalized(try await sessionBridge.login(
            email: email,
            password: password,
            code: code,
            deviceIdentifier: deviceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            probeBundleID: trimmedProbeBundleID.isEmpty ? existing?.probeBundleID ?? "" : trimmedProbeBundleID,
            existing: existing
        ))
        try Task.checkCancellation()
        guard result.meta.id == accountID else {
            throw MitoriError.unknown("Authenticated account does not match the requested email.")
        }
        try promoteLoginToMutation(for: accountID, token: token)

        let updatedAccounts = try await repository.commit(result, respectingCancellation: true)
        guard operationIsCurrent(for: accountID, token: token) else {
            throw MitoriError.operationSuperseded
        }
        // The write already succeeded on disk and Keychain, so keep memory in sync even if cancelled next.
        accounts = updatedAccounts
        if let issue = result.meta.lastIssue {
            showBanner(issue.message, ownedBy: accountID)
        } else {
            clearBanner(ownedBy: accountID)
        }
        try Task.checkCancellation()
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
        guard let token = beginRefresh(for: id) else { return }
        defer { finishOperation(for: id, token: token) }

        do {
            guard let secret = try await repository.loadSecret(
                for: id,
                allowsAuthenticationUI: isManualRefresh
            ) else {
                throw MitoriError.missingSecret
            }
            guard operationIsCurrent(for: id, token: token, requireAccount: true) else { return }
            let result = normalized(try await sessionBridge.refreshBalance(
                meta: meta,
                secret: secret,
                allowsReauthentication: isManualRefresh
            ))
            guard operationIsCurrent(for: id, token: token, requireAccount: true) else { return }
            let updatedAccounts = try await repository.commit(
                result,
                allowsAuthenticationUI: isManualRefresh
            )
            guard operationIsCurrent(for: id, token: token, requireAccount: true) else { return }
            accounts = updatedAccounts
            applyPostRefreshState(for: id, using: result)
        } catch {
            // A cancelled refresh is not a failure; it must not record an issue or start a backoff.
            if error is CancellationError || (!isManualRefresh && isKeychainInteractionNotAllowed(error)) {
                if operationIsCurrent(for: id, token: token, requireAccount: true) {
                    setRefreshState(.idle, for: id)
                }
                return
            }
            guard operationIsCurrent(for: id, token: token, requireAccount: true) else { return }

            let refreshError = MitoriError.map(error)
            let storageError = await recordFailure(for: meta, error: refreshError, token: token)
            guard operationIsCurrent(for: id, token: token, requireAccount: true) else { return }
            setRefreshState(.failed(refreshError.issueKind), for: id)
            showBanner(storageError?.localizedDescription ?? refreshError.localizedDescription, ownedBy: id)
        }
    }

    @discardableResult
    func reauthenticateAccount(
        id: String,
        password: String? = nil,
        code: String
    ) async throws -> RefreshIssue? {
        guard let meta = account(with: id) else { return nil }
        guard let token = beginRefresh(for: id) else {
            throw MitoriError.operationInProgress
        }
        defer { finishOperation(for: id, token: token) }

        let passwordOverride = (password?.isEmpty == false) ? password : nil
        do {
            let secret: StoredAccountSecret?
            if passwordOverride != nil {
                // With a new password, allow recovery even if the old Keychain item is missing or unreadable.
                secret = try? await repository.loadSecret(for: id)
            } else {
                guard let loaded = try await repository.loadSecret(for: id) else {
                    throw MitoriError.missingSecret
                }
                secret = loaded
            }
            guard operationIsCurrent(for: id, token: token, requireAccount: true) else {
                throw MitoriError.operationSuperseded
            }
            let result = normalized(try await sessionBridge.reauthenticate(
                meta: meta,
                secret: secret,
                passwordOverride: passwordOverride,
                code: code
            ))
            guard operationIsCurrent(for: id, token: token, requireAccount: true) else {
                throw MitoriError.operationSuperseded
            }
            let updatedAccounts = try await repository.commit(result)
            guard operationIsCurrent(for: id, token: token, requireAccount: true) else {
                throw MitoriError.operationSuperseded
            }
            accounts = updatedAccounts
            return applyPostRefreshState(for: id, using: result)
        } catch {
            if error is CancellationError {
                if operationIsCurrent(for: id, token: token, requireAccount: true) {
                    setRefreshState(.idle, for: id)
                }
                throw CancellationError()
            }
            let mappedError = MitoriError.map(error)
            if operationIsCurrent(for: id, token: token, requireAccount: true) {
                setRefreshState(.failed(mappedError.issueKind), for: id)
                showBanner(mappedError.localizedDescription, ownedBy: id)
            }
            throw mappedError
        }
    }

    func saveProbeBundleID(
        _ probeBundleID: String,
        adamID: Int64? = nil,
        appName: String? = nil,
        for accountID: String
    ) async throws {
        guard account(with: accountID) != nil else { return }
        let token = try beginMutation(for: accountID)
        defer { finishOperation(for: accountID, token: token) }
        let trimmedProbeBundleID = probeBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAppName = appName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAppName = (trimmedAppName?.isEmpty == false) ? trimmedAppName : nil
        let updatedAccounts = try await repository.updateMeta(id: accountID) { latest in
            // Saving the same probe changes nothing, so it must not resume a paused account.
            guard latest.probeBundleID != trimmedProbeBundleID
                || (normalizedAppName != nil && latest.probeAppName != normalizedAppName)
            else {
                return latest
            }
            var updated = latest
            let bundleChanged = latest.probeBundleID != trimmedProbeBundleID
            updated.probeBundleID = trimmedProbeBundleID
            updated.probeAdamID = trimmedProbeBundleID.isEmpty ? nil : (bundleChanged ? adamID : (adamID ?? latest.probeAdamID))
            updated.probeAppName = trimmedProbeBundleID.isEmpty ? nil : normalizedAppName

            if bundleChanged {
                switch updated.lastIssue?.kind {
                case .probeConfigurationMissing, .balanceUnavailable:
                    updated.lastIssue = nil
                    updated.nextEligibleRefreshAt = nil
                    updated.consecutiveFailureCount = 0
                default:
                    break
                }
            }
            return updated
        }
        guard operationIsCurrent(for: accountID, token: token) else { return }
        accounts = updatedAccounts

        if account(with: accountID)?.lastIssue == nil {
            clearBanner(ownedBy: accountID)
        }
    }

    func deleteAccount(id: String) async throws {
        guard account(with: id) != nil else { return }
        let token = try beginMutation(for: id)
        defer { finishOperation(for: id, token: token) }
        do {
            let remainingAccounts = try await repository.deleteAccount(id: id)
            guard operationIsCurrent(for: id, token: token) else { return }
            accounts = remainingAccounts
            refreshStates[id] = nil
            clearBanner(ownedBy: id)
        } catch {
            let mappedError = MitoriError.map(error)
            showBanner(mappedError.localizedDescription, ownedBy: id)
            throw mappedError
        }
    }

    private func ensureAccountsLoaded() async {
        guard !hasLoadedAccounts else { return }
        do {
            accounts = try await repository.loadAccounts()
            loadError = nil
            hasLoadedAccounts = true
        } catch {
            let message = MitoriError.map(error).localizedDescription
            loadError = message
            bannerMessage = message
        }
    }

    private func recordFailure(
        for meta: StoredAccountMeta,
        error: MitoriError,
        token: UUID
    ) async -> MitoriError? {
        let currentDate = now()
        let issue = error.refreshIssue(at: currentDate)
        let failureCount = meta.consecutiveFailureCount + 1
        let retryDate = currentDate.addingTimeInterval(backoffInterval(for: failureCount))
        // Merge into the latest metadata, so a probe edit made during the refresh survives.
        let applyFailure: @Sendable (StoredAccountMeta) -> StoredAccountMeta = { latest in
            var failed = latest
            failed.lastIssue = issue
            failed.consecutiveFailureCount = failureCount
            failed.nextEligibleRefreshAt = retryDate
            return failed
        }

        do {
            let updatedAccounts = try await repository.updateMeta(id: meta.id, transform: applyFailure)
            if operationIsCurrent(for: meta.id, token: token, requireAccount: true) {
                accounts = updatedAccounts
            }
            return nil
        } catch {
            // Keep the backoff in memory so a failed write cannot turn into a retry on every tick.
            if operationIsCurrent(for: meta.id, token: token, requireAccount: true),
               let index = accounts.firstIndex(where: { $0.id == meta.id })
            {
                accounts[index] = applyFailure(accounts[index])
            }
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
        isScreenLocked(in: CGSessionCopyCurrentDictionary() as? [String: Any])
    }

    /// macOS omits `CGSSessionScreenIsLocked` while unlocked, so an absent key means unlocked
    /// as long as the console session dictionary exists and is on console.
    static func isScreenLocked(in sessionDictionary: [String: Any]?) -> Bool {
        guard let sessionDictionary else {
            return true
        }
        if let onConsole = sessionDictionary["kCGSSessionOnConsoleKey"] as? Bool, !onConsole {
            return true
        }
        return (sessionDictionary["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    private func shouldAutoRefresh(_ meta: StoredAccountMeta) -> Bool {
        let currentDate = now()
        guard let dueDate = nextAutoRefreshDate(for: meta, at: currentDate) else {
            return false
        }
        return dueDate <= currentDate
    }

    private func nextAutoRefreshDate(for meta: StoredAccountMeta, at currentDate: Date) -> Date? {
        // Automatic refresh only probes the stored session (I-6). Accounts without
        // a probe, or paused by a non-network issue, wait for a user action.
        guard !meta.needsProbeBundleID else { return nil }
        if let issueKind = meta.lastIssue?.kind, issueKind != .network {
            return nil
        }
        if case .refreshing = refreshState(for: meta.id) {
            return nil
        }

        let baseDueDate: Date?
        if let lastRefreshAt = meta.lastRefreshAt {
            baseDueDate = lastRefreshAt.addingTimeInterval(settings.autoRefreshInterval)
        } else if meta.balanceSnapshot == nil {
            baseDueDate = currentDate
        } else {
            return nil
        }

        guard let baseDueDate else { return nil }
        if let nextEligibleRefreshAt = meta.nextEligibleRefreshAt {
            return max(baseDueDate, nextEligibleRefreshAt)
        }
        return baseDueDate
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

    private func beginRefresh(for accountID: String) -> UUID? {
        guard activeOperations[accountID] == nil else { return nil }
        let token = UUID()
        activeOperations[accountID] = ActiveOperation(kind: .refresh, token: token)
        setRefreshState(.refreshing, for: accountID)
        return token
    }

    private func beginLogin(for accountID: String) throws -> UUID {
        guard activeOperations[accountID] == nil else {
            throw MitoriError.operationInProgress
        }
        let token = UUID()
        activeOperations[accountID] = ActiveOperation(kind: .login, token: token)
        setRefreshState(.idle, for: accountID)
        return token
    }

    private func promoteLoginToMutation(for accountID: String, token: UUID) throws {
        guard activeOperations[accountID]?.token == token else {
            throw MitoriError.operationSuperseded
        }
        activeOperations[accountID]?.kind = .mutation
    }

    private func beginMutation(for accountID: String) throws -> UUID {
        guard activeOperations[accountID]?.kind != .mutation else {
            throw MitoriError.operationInProgress
        }
        let token = UUID()
        activeOperations[accountID] = ActiveOperation(kind: .mutation, token: token)
        setRefreshState(.idle, for: accountID)
        return token
    }

    private func finishOperation(for accountID: String, token: UUID) {
        if activeOperations[accountID]?.token == token {
            activeOperations[accountID] = nil
        }
    }

    private func operationIsCurrent(
        for accountID: String,
        token: UUID,
        requireAccount: Bool = false
    ) -> Bool {
        guard activeOperations[accountID]?.token == token else { return false }
        return !requireAccount || account(with: accountID) != nil
    }

    private func setRefreshState(_ state: RefreshState, for accountID: String) {
        refreshStates[accountID] = state
        changeSubject.send(.account(accountID))
    }

    @discardableResult
    private func applyPostRefreshState(
        for accountID: String,
        using result: SessionRefreshResult
    ) -> RefreshIssue? {
        if let issue = result.meta.lastIssue {
            setRefreshState(.failed(issue.kind), for: accountID)
            showBanner(issue.message, ownedBy: accountID)
            return issue
        }

        setRefreshState(.succeeded(result.meta.lastRefreshAt ?? now()), for: accountID)
        clearBanner(ownedBy: accountID)
        return nil
    }

    private func showBanner(_ message: String, ownedBy accountID: String) {
        bannerMessage = message
        bannerAccountID = accountID
    }

    /// One account's success must not clear another account's or an unowned error.
    private func clearBanner(ownedBy accountID: String) {
        guard bannerAccountID == accountID else { return }
        bannerMessage = nil
    }
}
