import Foundation

/// Typed store protocol errors (spec §4, I-3).
enum StoreAuthError: Error, Equatable, Sendable {
    case untrustedRedirect(host: String)
}
