import ApplePackage
import Foundation

enum MitoriError: LocalizedError, Equatable, Sendable {
    case twoFactorCodeRequired
    case invalidTwoFactorCode
    case sessionExpired
    case missingProbeBundleID
    case probeAppNotOwned
    case balanceNotFound
    case missingSecret
    case unsupportedStorefront(String)
    case network(String)
    case storage(String)
    case unknown(String)

    static func map(_ error: Error) -> MitoriError {
        if let error = error as? MitoriError {
            return error
        }

        if let error = error as? ApplePackageError {
            switch error {
            case .licenseRequired:
                return .probeAppNotOwned
            }
        }

        if let error = error as? URLError {
            return .network(error.localizedDescription)
        }

        let message = error.localizedDescription
        let normalized = message.lowercased()

        if normalized.contains("verification code") {
            return .twoFactorCodeRequired
        }
        if normalized.contains("invalid or expired 2fa code") {
            return .invalidTwoFactorCode
        }
        if normalized.contains("password token is expired") || normalized.contains("password has changed") {
            return .sessionExpired
        }
        if normalized.contains("unsupported store identifier") {
            return .unsupportedStorefront(message)
        }
        if (error as NSError).domain == NSOSStatusErrorDomain {
            return .storage(message)
        }
        if normalized.contains("keychain") || normalized.contains("storage") {
            return .storage(message)
        }
        return .unknown(message)
    }

    static func from(refreshIssue: RefreshIssue) -> MitoriError {
        switch refreshIssue.kind {
        case .requiresVerification:
            if refreshIssue.message == MitoriError.invalidTwoFactorCode.localizedDescription {
                return .invalidTwoFactorCode
            }
            return .twoFactorCodeRequired
        case .sessionExpired:
            return .sessionExpired
        case .probeConfigurationMissing:
            return .missingProbeBundleID
        case .balanceUnavailable, .unknown:
            return .unknown(refreshIssue.message)
        case .network:
            let prefix = "Network error: "
            if refreshIssue.message.hasPrefix(prefix) {
                return .network(String(refreshIssue.message.dropFirst(prefix.count)))
            }
            return .network(refreshIssue.message)
        }
    }

    var issueKind: RefreshIssueKind {
        switch self {
        case .twoFactorCodeRequired, .invalidTwoFactorCode:
            return .requiresVerification
        case .sessionExpired:
            return .sessionExpired
        case .missingProbeBundleID:
            return .probeConfigurationMissing
        case .probeAppNotOwned, .balanceNotFound, .unsupportedStorefront:
            return .balanceUnavailable
        case .network:
            return .network
        case .missingSecret, .storage, .unknown:
            return .unknown
        }
    }

    func refreshIssue(at date: Date = Date()) -> RefreshIssue {
        RefreshIssue(kind: issueKind, message: errorDescription ?? "Unknown error", updatedAt: date)
    }

    var errorDescription: String? {
        switch self {
        case .twoFactorCodeRequired:
            return "Authentication needs a 2FA code."
        case .invalidTwoFactorCode:
            return "The 2FA code is invalid or expired."
        case .sessionExpired:
            return "Session expired. The app will try to re-authenticate."
        case .missingProbeBundleID:
            return "Add an owned app bundle ID before refreshing balance."
        case .probeAppNotOwned:
            return "The probe app must already be owned by this Apple ID."
        case .balanceNotFound:
            return "Apple responded, but no balance field could be parsed."
        case .missingSecret:
            return "Stored credentials are missing for this account."
        case let .unsupportedStorefront(message):
            return "Unsupported storefront: \(message)"
        case let .network(message):
            return "Network error: \(message)"
        case let .storage(message):
            return "Storage error: \(message)"
        case let .unknown(message):
            return message
        }
    }
}
