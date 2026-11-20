//
//  StoreAuthError.swift
//  Mitori
//
//  Created by @Zach677 on 2026/10/13.
//

import Foundation

/// Typed store protocol errors (spec §4, I-3). State decisions use these
/// cases, never Apple's message text.
enum StoreAuthError: Error, Equatable, Sendable {
    case codeRequired
    case invalid2FACode
    /// `failureType` -5000. Apple gives it for a wrong password, and also for a
    /// 2FA account that signs in without a code or with a wrong code (#2).
    case invalidCredentials
    case badLogin(message: String)
    case sessionExpired
    case probeAppNotOwned
    case unsupportedStorefront(String)
    case redirectExhausted(status: Int)
    case untrustedRedirect(host: String)
    case transport(URLError)
    case malformedResponse(String)
}
