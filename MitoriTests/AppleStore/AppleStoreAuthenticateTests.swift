import Foundation
import Testing

@testable import Mitori

// Ported from ApplePackage Tests/ApplePackageTests/AuthenticateTests.swift at 3b535f1.
// Live login tests are not ported; T5 covers live behavior.
struct AppleStoreAuthenticateTests {
    @Test
    func loginRequestSignsExactPayload() throws {
        let endpoint = try #require(URL(string: "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate"))
        var signedPayload: Data?

        let request = try Authenticator.makeRequest(
            endpoint: endpoint,
            email: "test@example.com",
            password: "password",
            code: "123456",
            cookies: [],
            deviceIdentifier: "ABCDEF123456",
            signAction: { payload in
                signedPayload = payload
                return "dGVzdC1zaWduYXR1cmU="
            }
        )

        let payload = try #require(signedPayload)
        let propertyList = try #require(
            PropertyListSerialization.propertyList(from: payload, format: nil) as? [String: String]
        )
        #expect(propertyList["appleId"] == "test@example.com")
        #expect(propertyList["password"] == "password123456")
        #expect(propertyList["guid"] == "ABCDEF123456")
        #expect(request.value(forHTTPHeaderField: "X-Apple-ActionSignature") == "dGVzdC1zaWduYXR1cmU=")
    }

    @Test
    func retriesTransientAuthenticationResponses() async throws {
        var statuses: [UInt] = [204, 404, 200]
        var sleepDurations: [UInt64] = []

        let response = try await Authenticator.sendAuthenticationRequest(
            execute: {
                let status = statuses.removeFirst()
                return (status, status, nil)
            },
            sleep: { sleepDurations.append($0) }
        )

        #expect(response == 200)
        #expect(statuses.isEmpty)
        // Each retry resends the password, so wait like ipatool does (B14).
        #expect(sleepDurations == [10_000_000_000, 20_000_000_000])
    }

    @Test
    func rateLimitHonorsRetryAfter() async throws {
        var statuses: [UInt] = [429, 200]
        var sleepDurations: [UInt64] = []

        let response = try await Authenticator.sendAuthenticationRequest(
            execute: {
                let status = statuses.removeFirst()
                return (status, status, status == 429 ? " 3 " : nil)
            },
            sleep: { sleepDurations.append($0) }
        )

        #expect(response == 200)
        #expect(sleepDurations == [3_000_000_000])
    }

    @Test(arguments: ["0", "1"])
    func retryAfterWaitsAtLeastOneSecond(retryAfter: String) async throws {
        var statuses: [UInt] = [204, 200]
        var sleepDurations: [UInt64] = []

        _ = try await Authenticator.sendAuthenticationRequest(
            execute: {
                let status = statuses.removeFirst()
                return (status, status, retryAfter)
            },
            sleep: { sleepDurations.append($0) }
        )

        #expect(sleepDurations == [1_000_000_000])
    }

    @Test
    func retryAfterBeyondBudgetStopsWithoutAnotherPassword() async throws {
        var callCount = 0

        let response = try await Authenticator.sendAuthenticationRequest(
            execute: {
                callCount += 1
                return (429, 429, "120")
            },
            sleep: { _ in Issue.record("a wait beyond 30 s must end the sign-in") }
        )

        #expect(response == 429)
        #expect(callCount == 1)
    }

    @Test
    func doesNotRetryNonTransientAuthenticationResponse() async throws {
        var callCount = 0

        let response = try await Authenticator.sendAuthenticationRequest(
            execute: {
                callCount += 1
                return (403, 403, nil)
            },
            sleep: { _ in Issue.record("non-transient response must not sleep") }
        )

        #expect(response == 403)
        #expect(callCount == 1)
    }

    // The bare MZFinance path 301s without Location; the trailing slash fixes it (D-20).
    @Test(arguments: [
        ("https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate",
         "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate/"),
        ("https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate?guid=ABCDEF123456",
         "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate/?guid=ABCDEF123456"),
        ("https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate/",
         "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate/"),
    ])
    func legacyAuthenticateEndpointKeepsHostAndAddsTrailingSlash(raw: String, expected: String) {
        #expect(Bag.normalizedAuthEndpoint(from: raw)?.absoluteString == expected)
    }

    @Test
    func redirectWithoutLocationAddsAuthenticateTrailingSlash() {
        #expect(
            Authenticator.resolvedRedirectURL(
                locationHeader: nil,
                currentURL: URL(string: "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate?guid=ABCDEF123456")!
            )?.absoluteString
                == "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate/?guid=ABCDEF123456"
        )
    }

    @Test
    func redirectWithoutLocationAddsNativeFastTrailingSlash() {
        let current = URL(string: "https://auth.itunes.apple.com/auth/v1/native/fast?guid=ABCDEF123456")!
        let url = Authenticator.resolvedRedirectURL(locationHeader: nil, currentURL: current)
        #expect(url?.absoluteString == "https://auth.itunes.apple.com/auth/v1/native/fast/?guid=ABCDEF123456")
    }

    @Test
    func redirectWithoutLocationDoesNotLoopWhenTrailingSlashPresent() {
        let current = URL(string: "https://auth.itunes.apple.com/auth/v1/native/fast/?guid=ABCDEF123456")!
        #expect(Authenticator.resolvedRedirectURL(locationHeader: nil, currentURL: current) == nil)
    }

    @Test
    func cookieReauthRedirectWithoutLocationRetriesWithoutCookies() {
        let current = URL(string: "https://auth.itunes.apple.com/auth/v1/native/fast/?guid=ABCDEF123456")!
        #expect(
            Authenticator.redirectHandling(
                status: 302,
                locationHeader: nil,
                currentURL: current,
                bodyLength: 0
            ) == .retryWithoutCookies
        )
        #expect(
            Authenticator.redirectHandling(
                status: 302,
                locationHeader: nil,
                currentURL: current,
                bodyLength: 162
            ) == .parseBody
        )
    }

    @Test
    func redirectTrimsLocationAndResolvesRelativePath() {
        let current = URL(string: "https://auth.itunes.apple.com/auth/v1/native/fast/?guid=ABCDEF123456")!
        let url = Authenticator.resolvedRedirectURL(
            locationHeader: " /auth/v1/native/fast/",
            currentURL: current
        )
        #expect(url?.absoluteString == "https://auth.itunes.apple.com/auth/v1/native/fast/")
    }

    @Test
    func redirectTrimsAbsoluteLocation() {
        let current = URL(string: "https://auth.itunes.apple.com/auth/v1/native/fast/?guid=ABCDEF123456")!
        let url = Authenticator.resolvedRedirectURL(
            locationHeader: " https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate?guid=ABCDEF123456",
            currentURL: current
        )
        // A bare MZFinance Location also gets the trailing slash (D-20).
        #expect(url?.absoluteString == "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate/?guid=ABCDEF123456")
    }

    @Test
    func stopsAfterThreeTransientAuthenticationResponses() async throws {
        var callCount = 0

        let response = try await Authenticator.sendAuthenticationRequest(
            execute: {
                callCount += 1
                return (204, 204, nil)
            },
            sleep: { _ in }
        )

        #expect(response == 204)
        #expect(callCount == 3)
    }

    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["APPLEPACKAGE_TEST_SAP"] == "1",
        "Set APPLEPACKAGE_TEST_SAP=1 to run the CommerceKit integration test"
    ))
    func commerceKitSignerProducesSignature() throws {
        let signature = try AppleActionSigner.sign(Data("ApplePackage SAP integration test".utf8))

        #expect(!signature.isEmpty)
        #expect(Data(base64Encoded: signature) != nil)
    }
}
