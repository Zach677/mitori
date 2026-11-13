import Testing

@testable import Mitori

// Ported from ApplePackage Tests/ApplePackageTests/ConfigurationTests.swift at 3b535f1.
struct AppleStoreConfigurationTests {
    @Test(arguments: [("42", "p42-buy.itunes.apple.com"), (nil, "p25-buy.itunes.apple.com"), ("", "p25-buy.itunes.apple.com")] as [(String?, String)])
    func storeAPIHost(pod: String?, host: String) {
        #expect(Configuration.storeAPIHost(pod: pod) == host)
    }

    @Test
    func countryCodeRoundTrip() {
        #expect(Configuration.storeFrontValues["US"] == "143441")
        #expect(Configuration.countryCode(for: "143441") == "US")
    }

    @Test
    func countryCodeForUnknownStore() {
        #expect(Configuration.countryCode(for: "999999") == nil)
    }
}
