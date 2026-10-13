import Foundation
import Testing

@testable import Mitori

/// Protocol responses map to typed errors; Apple's message text never selects a state (I-3).
struct StoreAuthErrorTests {
    @Test
    func authenticateThrowsCodeRequired() async throws {
        let transport = StoreTransportStub([
            .emptyBag,
            try .plist(["failureType": "", "customerMessage": "MZFinance.BadLogin.Configurator_message"]),
        ])

        await #expect(throws: StoreAuthError.codeRequired) {
            try await authenticate(over: transport)
        }
    }

    @Test
    func authenticateThrowsInvalidCode() async throws {
        let transport = StoreTransportStub([
            .emptyBag,
            try .plist(["failureType": "5005", "customerMessage": "Something else"]),
        ])

        await #expect(throws: StoreAuthError.invalid2FACode) {
            try await authenticate(over: transport, code: "123456")
        }
    }

    @Test
    func authenticateThrowsUnsupportedStorefront() async throws {
        let transport = StoreTransportStub([
            .emptyBag,
            try .plist(authSuccessPlist(), headers: ["x-set-apple-store-front": "999999-1,29"]),
        ])

        await #expect(throws: StoreAuthError.unsupportedStorefront("999999")) {
            try await authenticate(over: transport)
        }
    }

    @Test(arguments: [
        StoreTransportStub.Response(status: 200),
        StoreTransportStub.Response(status: 200, body: Data("not a plist".utf8)),
    ])
    func authenticateThrowsMalformedResponse(response: StoreTransportStub.Response) async throws {
        let transport = StoreTransportStub([.emptyBag, response])

        await #expect {
            try await authenticate(over: transport)
        } throws: { error in
            guard case .malformedResponse = error as? StoreAuthError else { return false }
            return true
        }
    }

    @Test
    func authenticateThrowsRedirectExhausted() async throws {
        let redirect = StoreTransportStub.Response.redirect(to: "/auth/v1/native/fast/")
        let transport = StoreTransportStub([.emptyBag, redirect, redirect, redirect, redirect])

        await #expect(throws: StoreAuthError.redirectExhausted(status: 302)) {
            try await authenticate(over: transport)
        }
        #expect(transport.requests.count == 5)
    }

    // An English message that looks like a 2FA prompt must not select the 2FA state.
    @Test
    func misleadingAuthenticationMessageIsABadLogin() async throws {
        let message = "Authentication requires verification code"
        let transport = StoreTransportStub([
            .emptyBag,
            try .plist(["failureType": "-5000", "customerMessage": message]),
        ])

        await #expect(throws: StoreAuthError.badLogin(message: message)) {
            try await authenticate(over: transport)
        }
        #expect(MitoriError.map(StoreAuthError.badLogin(message: message)) != .twoFactorCodeRequired)
    }

    @Test(arguments: [
        ("2034", StoreAuthError.sessionExpired),
        ("2042", .sessionExpired),
        ("9610", .probeAppNotOwned),
    ])
    func probeThrowsTypedFailure(failureType: String, expected: StoreAuthError) async throws {
        let transport = StoreTransportStub([
            .lookup(adamID: 42, bundleID: "com.example.probe"),
            try .plist(["failureType": failureType, "customerMessage": "Ignored text"]),
        ])

        await #expect(throws: expected) {
            try await refreshProbe(over: transport)
        }
    }

    // "Your password has changed." used to select sessionExpired by text match.
    @Test
    func misleadingProbeMessageStaysUnknown() async throws {
        let transport = StoreTransportStub([
            .lookup(adamID: 42, bundleID: "com.example.probe"),
            try .plist(["customerMessage": "Your password has changed."]),
        ])

        await #expect(throws: MitoriError.unknown("Your password has changed.")) {
            try await refreshProbe(over: transport)
        }
    }

    @Test
    func probeThrowsUnsupportedStorefrontWithoutRequests() async throws {
        let transport = StoreTransportStub([])
        var meta = probeMeta()
        meta.storefront = "999999"

        await #expect(throws: StoreAuthError.unsupportedStorefront("999999")) {
            try await BalanceService(probeClient: BalanceProbeClient(transport: transport))
                .refreshBalance(for: meta, secret: StoredAccountSecret(account: sampleAccount()))
        }
        #expect(transport.requests.isEmpty)
    }

    @Test
    func liveTransportWrapsConnectionFailures() async throws {
        // Nothing listens on port 1, so this fails fast without leaving the machine.
        let request = URLRequest(url: try #require(URL(string: "https://127.0.0.1:1/")))

        await #expect {
            _ = try await URLSessionStoreTransport().data(for: request)
        } throws: { error in
            guard case .transport = error as? StoreAuthError else { return false }
            return true
        }
    }

    private func refreshProbe(over transport: StoreTransportStub) async throws -> BalanceResult {
        try await BalanceService(probeClient: BalanceProbeClient(transport: transport))
            .refreshBalance(for: probeMeta(), secret: StoredAccountSecret(account: sampleAccount()))
    }
}
