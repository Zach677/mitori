import Foundation

/// The one redirect validator for every store request (I-2).
enum StoreRedirectPolicy {
    private static let trustedHosts: Set<String> = [
        "buy.itunes.apple.com",
        "downloaddispatch.itunes.apple.com",
        "auth.itunes.apple.com",
        "init.itunes.apple.com",
    ]

    static func validatedURL(location: String, relativeTo baseURL: URL) throws -> URL {
        guard let url = URL(string: location, relativeTo: baseURL)?.absoluteURL else {
            throw StoreAuthError.untrustedRedirect(host: "")
        }
        return try validated(url)
    }

    static func validated(_ url: URL) throws -> URL {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443,
              isTrustedHost(url.host)
        else {
            throw StoreAuthError.untrustedRedirect(host: url.host ?? "")
        }
        return url
    }

    static func isTrustedHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        if trustedHosts.contains(host) {
            return true
        }

        // Pod hosts: ^p[0-9]+-buy\.itunes\.apple\.com$
        let suffix = "-buy.itunes.apple.com"
        guard host.hasPrefix("p"), host.hasSuffix(suffix) else { return false }
        let pod = host.dropFirst().dropLast(suffix.count)
        return !pod.isEmpty && pod.allSatisfy { ("0" ... "9").contains($0) }
    }
}
