import ApplePackage
import Foundation

struct BalanceSnapshot: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case authentication
        case probe
    }

    var displayText: String
    var numericValue: Decimal?
    var currencyCode: String?
    var fetchedAt: Date
    var source: Source
    var rawFieldPath: String
}

enum RefreshIssueKind: String, Codable, Sendable {
    case requiresVerification
    case sessionExpired
    case probeConfigurationMissing
    case balanceUnavailable
    case network
    case unknown
}

struct RefreshIssue: Codable, Equatable, Sendable {
    var kind: RefreshIssueKind
    var message: String
    var updatedAt: Date
}

enum RefreshState: Equatable, Sendable {
    case idle
    case refreshing
    case succeeded(Date)
    case failed(RefreshIssueKind)
}

enum AccountStatus: Sendable {
    case normal
    case needsVerification
    case sessionExpired
    case attention
}

struct StoredAccountMeta: Codable, Equatable, Identifiable, Sendable {
    var email: String
    var appleID: String
    var firstName: String
    var lastName: String
    var storefront: String
    var countryCode: String?
    var pod: String?
    var deviceIdentifier: String
    var probeBundleID: String
    var lastRefreshAt: Date?
    var balanceSnapshot: BalanceSnapshot?
    var lastIssue: RefreshIssue?
    var nextEligibleRefreshAt: Date?
    var consecutiveFailureCount: Int

    var id: String { email.lowercased() }
    var displayName: String {
        let pieces = [firstName, lastName].filter { !$0.isEmpty }
        return pieces.isEmpty ? email : pieces.joined(separator: " ")
    }
    var regionLabel: String {
        [countryCode, storefront].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " • ")
    }
    var needsProbeBundleID: Bool {
        probeBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var requiresProbeConfiguration: Bool {
        needsProbeBundleID || lastIssue?.kind == .probeConfigurationMissing
    }
    var status: AccountStatus {
        guard let lastIssue else { return .normal }
        switch lastIssue.kind {
        case .requiresVerification:
            return .needsVerification
        case .sessionExpired:
            return .sessionExpired
        case .probeConfigurationMissing, .balanceUnavailable, .network, .unknown:
            return .attention
        }
    }
}

extension StoredAccountMeta {
    init(
        account: Account,
        deviceIdentifier: String,
        probeBundleID: String,
        balanceSnapshot: BalanceSnapshot? = nil,
        lastIssue: RefreshIssue? = nil,
        lastRefreshAt: Date? = nil,
        nextEligibleRefreshAt: Date? = nil,
        consecutiveFailureCount: Int = 0
    ) {
        email = account.email
        appleID = account.appleId
        firstName = account.firstName
        lastName = account.lastName
        storefront = account.store
        countryCode = Configuration.countryCode(for: account.store)
        pod = account.pod
        self.deviceIdentifier = deviceIdentifier
        self.probeBundleID = probeBundleID
        self.balanceSnapshot = balanceSnapshot
        self.lastIssue = lastIssue
        self.lastRefreshAt = lastRefreshAt
        self.nextEligibleRefreshAt = nextEligibleRefreshAt
        self.consecutiveFailureCount = consecutiveFailureCount
    }
}

struct StoredAccountSecret: Codable, Equatable, Sendable {
    var password: String
    var cookies: [Cookie]
    var passwordToken: String
    var directoryServicesIdentifier: String
    var account: Account

    init(account: Account) {
        password = account.password
        cookies = account.cookie
        passwordToken = account.passwordToken
        directoryServicesIdentifier = account.directoryServicesIdentifier
        self.account = account
    }

    func restoredAccount() -> Account {
        var restored = account
        restored.password = password
        restored.cookie = cookies
        restored.passwordToken = passwordToken
        restored.directoryServicesIdentifier = directoryServicesIdentifier
        return restored
    }
}

struct SessionRefreshResult: Sendable {
    var meta: StoredAccountMeta
    var secret: StoredAccountSecret
}

struct BalanceResult: Sendable {
    var snapshot: BalanceSnapshot
    var secret: StoredAccountSecret
}
