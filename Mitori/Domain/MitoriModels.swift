//
//  MitoriModels.swift
//  Mitori
//
//  Created by @Zach677 on 2026/03/25.
//

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

    func localizedDisplayText(countryCode: String?) -> String {
        guard let numericValue,
              let regionCode = countryCode?
              .trimmingCharacters(in: .whitespacesAndNewlines)
              .uppercased(),
              regionCode.count == 2
        else {
            return displayText
        }

        let locale = Locale(identifier: "en_\(regionCode)")
        let responseCurrencyCode = currencyCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard let resolvedCurrencyCode = responseCurrencyCode?.count == 3
            ? responseCurrencyCode
            : locale.currency?.identifier
        else {
            return displayText
        }

        return numericValue.formatted(
            .currency(code: resolvedCurrencyCode).locale(locale)
        )
    }
}

enum RefreshIssueKind: String, Codable, Sendable {
    case requiresVerification
    case sessionExpired
    case probeConfigurationMissing
    case balanceUnavailable
    case network
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = RefreshIssueKind(rawValue: rawValue) ?? .unknown
    }
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
    var probeAdamID: Int64?
    var probeAppName: String?
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
    var balanceDisplayText: String? {
        balanceSnapshot?.localizedDisplayText(countryCode: countryCode)
    }
    var storeDisplayName: String {
        if let countryCode, !countryCode.isEmpty {
            if let localized = Locale.current.localizedString(forRegionCode: countryCode), !localized.isEmpty {
                return localized
            }
            return countryCode
        }
        return storefront.isEmpty ? "Unknown" : storefront
    }
    var needsProbeBundleID: Bool {
        probeBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var visibleIssue: RefreshIssue? {
        guard let lastIssue else { return nil }
        if lastIssue.kind == .probeConfigurationMissing, needsProbeBundleID {
            return nil
        }
        return lastIssue
    }
}

struct StoredAccountSecret: Codable, Equatable, Sendable {
    var password: String
    var cookies: [Cookie]
    var passwordToken: String
    var directoryServicesIdentifier: String
}

struct SessionRefreshResult: Sendable {
    var meta: StoredAccountMeta
    var secret: StoredAccountSecret
}
