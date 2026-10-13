import Foundation

/// Typed store protocol errors (spec §4, I-3). State decisions use these
/// cases, never Apple's message text.
enum StoreAuthError: Error, Equatable, Sendable {
    case codeRequired
    case invalid2FACode
    case badLogin(message: String)
    case sessionExpired
    case probeAppNotOwned
    case unsupportedStorefront(String)
    case redirectExhausted(status: Int)
    case untrustedRedirect(host: String)
    case transport(URLError)
    case malformedResponse(String)
}
