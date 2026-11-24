//
//  MitoriError.swift
//  Mitori
//
//  Created by @Zach677 on 2026/03/25.
//

import Foundation

enum MitoriError: LocalizedError, Equatable, Sendable {
    case twoFactorCodeRequired
    case invalidTwoFactorCode
    case invalidCredentials
    case sessionExpired
    case missingProbeBundleID
    case probeAppNotOwned
    case probeAppNotFound(String)
    case balanceNotFound
    case missingSecret
    case operationInProgress
    case operationSuperseded
    case unsupportedStorefront(String)
    case network(String)
    case storage(String)
    case unknown(String)

    static func map(_ error: Error) -> MitoriError {
        if let error = error as? MitoriError {
            return error
        }

        if let error = error as? StoreAuthError {
            return map(error)
        }

        if let error = error as? URLError {
            return .network(error.localizedDescription)
        }

        let message = error.localizedDescription
        let nsError = error as NSError
        if nsError.domain == NSOSStatusErrorDomain {
            return .storage(message)
        }
        if nsError.domain == NSCocoaErrorDomain,
           CocoaError(CocoaError.Code(rawValue: nsError.code)).isFileError
        {
            return .storage(message)
        }
        return .unknown(message)
    }

    private static func map(_ error: StoreAuthError) -> MitoriError {
        switch error {
        case .codeRequired:
            return .twoFactorCodeRequired
        case .invalid2FACode:
            return .invalidTwoFactorCode
        case .invalidCredentials:
            return .invalidCredentials
        case let .badLogin(message):
            return .unknown("Authentication failed: \(message)")
        case .sessionExpired:
            return .sessionExpired
        case .probeAppNotOwned:
            return .probeAppNotOwned
        case let .probeAppNotFound(bundleID):
            return .probeAppNotFound(bundleID)
        case let .unsupportedStorefront(storefront):
            return .unsupportedStorefront(storefront)
        case let .redirectExhausted(status):
            return .network("Apple returned too many redirects (HTTP \(status)).")
        case .untrustedRedirect:
            return .network("Apple returned an untrusted redirect URL.")
        case let .transport(error):
            return .network(error.localizedDescription)
        case let .malformedResponse(detail):
            return .unknown("Apple returned an unexpected response: \(detail)")
        }
    }

    var issueKind: RefreshIssueKind {
        switch self {
        case .twoFactorCodeRequired, .invalidTwoFactorCode, .invalidCredentials:
            return .requiresVerification
        case .sessionExpired:
            return .sessionExpired
        case .missingProbeBundleID, .probeAppNotOwned, .probeAppNotFound:
            return .probeConfigurationMissing
        case .balanceNotFound, .unsupportedStorefront:
            return .balanceUnavailable
        case .network:
            return .network
        case .missingSecret, .operationInProgress, .operationSuperseded, .storage, .unknown:
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
        case .invalidCredentials:
            return "Apple did not accept the sign-in. If your devices showed a verification code, enter it and sign in again. If not, check the password."
        case .sessionExpired:
            return "Apple ended the saved session. Sign in again to resume automatic refresh."
        case .missingProbeBundleID:
            return "Add an owned app bundle ID before refreshing balance."
        case .probeAppNotOwned:
            return "The probe app must already be owned by this Apple ID."
        case let .probeAppNotFound(bundleID):
            return "No App Store app was found for bundle ID \"\(bundleID)\" in this account's storefront."
        case .balanceNotFound:
            return "Apple responded, but no balance field could be parsed."
        case .missingSecret:
            return "Stored credentials are missing for this account."
        case .operationInProgress:
            return "Another operation is already running for this account."
        case .operationSuperseded:
            return "A newer account change replaced this operation."
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
