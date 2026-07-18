import Foundation
import Testing

@testable import Mitori

struct BalanceProbeClientTests {
    @Test
    func acceptsTrustedAppleStoreRedirects() throws {
        let baseURL = try #require(URL(string: "https://p25-buy.itunes.apple.com/start"))

        let relative = try BalanceProbeClient.validatedRedirectURL(
            location: "/next",
            relativeTo: baseURL
        )
        let otherPod = try BalanceProbeClient.validatedRedirectURL(
            location: "https://p99-buy.itunes.apple.com/next",
            relativeTo: baseURL
        )

        #expect(relative.absoluteString == "https://p25-buy.itunes.apple.com/next")
        #expect(otherPod.host == "p99-buy.itunes.apple.com")
    }

    @Test(arguments: [
        "http://p25-buy.itunes.apple.com/next",
        "https://example.com/next",
        "https://itunes.apple.com.example.com/next",
        "https://user@p25-buy.itunes.apple.com/next",
        "https://pabc-buy.itunes.apple.com/next",
        "https://p25-buy.itunes.apple.com:8443/next",
    ])
    func rejectsUntrustedRedirects(location: String) throws {
        let baseURL = try #require(URL(string: "https://p25-buy.itunes.apple.com/start"))

        #expect(throws: MitoriError.self) {
            try BalanceProbeClient.validatedRedirectURL(location: location, relativeTo: baseURL)
        }
    }
}
