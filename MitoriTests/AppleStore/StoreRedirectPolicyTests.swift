import Foundation
import Testing

@testable import Mitori

struct StoreRedirectPolicyTests {
    static let untrustedLocations = [
        "http://p25-buy.itunes.apple.com/next",
        "https://example.com/next",
        "https://itunes.apple.com.example.com/next",
        "https://evilp25-buy.itunes.apple.com/next",
        "https://p25-buy.itunes.apple.com.example.com/next",
        "https://pabc-buy.itunes.apple.com/next",
        "https://user@p25-buy.itunes.apple.com/next",
        "https://user:pass@auth.itunes.apple.com/next",
        "https://p25-buy.itunes.apple.com:8443/next",
    ]

    @Test(arguments: [
        ("/next", "https://p25-buy.itunes.apple.com/next"),
        ("https://p99-buy.itunes.apple.com/next", "https://p99-buy.itunes.apple.com/next"),
        ("https://auth.itunes.apple.com:443/next", "https://auth.itunes.apple.com:443/next"),
        ("https://P25-Buy.iTunes.Apple.com/next", "https://P25-Buy.iTunes.Apple.com/next"),
        ("https://downloaddispatch.itunes.apple.com/next", "https://downloaddispatch.itunes.apple.com/next"),
        ("https://init.itunes.apple.com/next", "https://init.itunes.apple.com/next"),
    ])
    func acceptsTrustedLocations(location: String, expected: String) throws {
        let baseURL = try #require(URL(string: "https://p25-buy.itunes.apple.com/start"))

        let url = try StoreRedirectPolicy.validatedURL(location: location, relativeTo: baseURL)

        #expect(url.absoluteString == expected)
    }

    @Test(arguments: untrustedLocations)
    func rejectsUntrustedLocations(location: String) throws {
        let baseURL = try #require(URL(string: "https://p25-buy.itunes.apple.com/start"))

        #expect(throws: StoreAuthError.self) {
            try StoreRedirectPolicy.validatedURL(location: location, relativeTo: baseURL)
        }
    }

    @Test(arguments: untrustedLocations)
    func authenticateRefusesUntrustedRedirectWithoutFollowUp(location: String) async throws {
        let transport = StoreTransportStub([.emptyBag, .redirect(to: location)])

        await #expect(throws: StoreAuthError.untrustedRedirect(host: URL(string: location)?.host ?? "")) {
            try await authenticate(over: transport)
        }
        #expect(transport.requests.count == 2)
    }

    @Test(arguments: [
        ("/auth/v1/native/fast/?attempt=2", "auth.itunes.apple.com"),
        ("https://auth.itunes.apple.com:443/auth/v1/native/fast/", "auth.itunes.apple.com"),
        ("https://P25-Buy.iTunes.Apple.com/WebObjects/MZFinance.woa/wa/authenticate", "p25-buy.itunes.apple.com"),
    ])
    func authenticateFollowsTrustedRedirect(location: String, host: String) async throws {
        let transport = StoreTransportStub([
            .emptyBag,
            .redirect(to: location),
            try .plist(authSuccessPlist(), headers: storeFrontHeader),
        ])

        _ = try await authenticate(over: transport)

        let requests = transport.requests
        #expect(requests.count == 3)
        #expect(requests[2].url?.host?.lowercased() == host)
        #expect(requests[2].httpMethod == "POST")
    }

    @Test
    func probeRefusesUntrustedRedirectWithoutFollowUp() async throws {
        let transport = StoreTransportStub([
            .lookup(adamID: 42, bundleID: "com.example.probe"),
            .redirect(to: "https://example.com/next"),
        ])
        let service = BalanceService(probeClient: BalanceProbeClient(transport: transport))

        await #expect(throws: StoreAuthError.untrustedRedirect(host: "example.com")) {
            try await service.refreshBalance(for: probeMeta(), secret: StoredAccountSecret(account: sampleAccount()))
        }
        #expect(transport.requests.count == 2)
    }
}
