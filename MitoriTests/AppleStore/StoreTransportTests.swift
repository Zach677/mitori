import Foundation
import Testing

@testable import Mitori

struct StoreTransportTests {
    @Test
    func authenticateParsesAccountFromStubTransport() async throws {
        let transport = StoreTransportStub([
            .emptyBag,
            try .plist(authSuccessPlist(), headers: [
                "x-set-apple-store-front": "143441-1,29",
                "pod": "25",
                "Set-Cookie": "mz_at0=session; Domain=.apple.com; Path=/",
            ]),
        ])

        let result = try await authenticate(over: transport)

        #expect(result.account.store == "143441")
        #expect(result.account.pod == "25")
        #expect(result.account.cookie.map(\.name) == ["mz_at0"])
        #expect(try BalanceParser.parse(plistData: result.responsePlist, source: .authentication).numericValue == Decimal(string: "24.90"))

        let requests = transport.requests
        #expect(requests.count == 2)
        #expect(requests[0].url?.host == "init.itunes.apple.com")
        #expect(requests[1].httpMethod == "POST")
        #expect(requests[1].url?.absoluteString == "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate/?guid=ABCDEF123456")
        #expect(requests[1].value(forHTTPHeaderField: "Cookie") == nil)
    }

    // The live bag (2026-10-15) advertises the bare MZFinance path.
    @Test
    func authenticatePostsToTheBagEndpointWithTrailingSlash() async throws {
        let transport = StoreTransportStub([
            try .plist(["authenticateAccount": "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate"]),
            try .plist(authSuccessPlist(), headers: storeFrontHeader),
        ])

        _ = try await authenticate(over: transport)

        #expect(transport.requests.last?.url?.absoluteString
            == "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate/?guid=ABCDEF123456")
    }

    @Test
    func authenticateSendsStoredCookies() async throws {
        let transport = StoreTransportStub([.emptyBag, try .plist(authSuccessPlist(), headers: storeFrontHeader)])
        let cookie = Cookie(name: "mz_at0", value: "stored", path: "/", domain: ".apple.com", httpOnly: true, secure: true)

        _ = try await authenticate(over: transport, cookies: [cookie])

        #expect(transport.requests.last?.value(forHTTPHeaderField: "Cookie") == "mz_at0=stored")
    }

    @Test
    func cancelledAuthenticationThrowsCancellationWithoutRequests() async throws {
        let transport = StoreTransportStub([.emptyBag])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await authenticate(over: transport)
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(transport.requests.isEmpty)
    }

    @Test
    func probeParsesBalanceFromStubTransport() async throws {
        let transport = StoreTransportStub([
            .lookup(adamID: 42, bundleID: "com.example.probe"),
            StoreTransportStub.Response(status: 200, body: try FixtureLoader.data(named: "probe_success_balance")),
        ])
        let service = BalanceService(probeClient: BalanceProbeClient(transport: transport))

        let result = try await service.refreshBalance(for: probeMeta(), secret: StoredAccountSecret(account: sampleAccount()))

        #expect(result.snapshot.source == .probe)
        #expect(result.snapshot.numericValue == Decimal(string: "88.00"))
        let probeRequest = try #require(transport.requests.last)
        #expect(probeRequest.url?.host == "p25-buy.itunes.apple.com")
        #expect(probeRequest.value(forHTTPHeaderField: "X-Dsid") == "1234567890")
    }

    @Test
    func cancelledProbeThrowsCancellationWithoutRequests() async throws {
        let transport = StoreTransportStub([.lookup(adamID: 42, bundleID: "com.example.probe")])
        let service = BalanceService(probeClient: BalanceProbeClient(transport: transport))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.refreshBalance(for: probeMeta(), secret: StoredAccountSecret(account: sampleAccount()))
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(transport.requests.isEmpty)
    }

    @Test(arguments: [true, false])
    func cancelledBridgeRefreshStaysCancellation(allowsReauthentication: Bool) async throws {
        let transport = StoreTransportStub([])
        let bridge = liveBridge(over: transport)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await bridge.refreshBalance(
                meta: probeMeta(),
                secret: StoredAccountSecret(account: sampleAccount()),
                allowsReauthentication: allowsReauthentication
            )
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(transport.requests.isEmpty)
    }

    // T3 policy through the real stack: automatic refresh never sends a password (I-6).
    @Test
    func automaticProbeExpiryMakesNoAuthenticationRequest() async throws {
        let transport = StoreTransportStub([
            .lookup(adamID: 42, bundleID: "com.example.probe"),
            try .plist(["failureType": "2034", "customerMessage": "ignored"]),
        ])
        let bridge = liveBridge(over: transport)

        await #expect(throws: MitoriError.sessionExpired) {
            try await bridge.refreshBalance(
                meta: probeMeta(),
                secret: StoredAccountSecret(account: sampleAccount()),
                allowsReauthentication: false
            )
        }
        #expect(transport.requests.count == 2)
        #expect(!transport.requests.contains { $0.url?.host == "auth.itunes.apple.com" })
    }

    @Test
    func automaticRefreshWithoutProbeMakesNoRequest() async throws {
        let transport = StoreTransportStub([])
        let bridge = liveBridge(over: transport)
        let meta = StoredAccountMeta(account: sampleAccount(), deviceIdentifier: "ABCDEF123456", probeBundleID: "")

        await #expect(throws: MitoriError.missingProbeBundleID) {
            try await bridge.refreshBalance(
                meta: meta,
                secret: StoredAccountSecret(account: sampleAccount()),
                allowsReauthentication: false
            )
        }
        #expect(transport.requests.isEmpty)
    }

    // T2 parsing through the real stack: the auth response is the balance for a no-probe account.
    @Test
    func manualRefreshWithoutProbeUsesAuthenticationBalance() async throws {
        let transport = StoreTransportStub([.emptyBag, try .plist(authSuccessPlist(), headers: storeFrontHeader)])
        let bridge = liveBridge(over: transport)
        let meta = StoredAccountMeta(account: sampleAccount(), deviceIdentifier: "ABCDEF123456", probeBundleID: "")

        let result = try await bridge.refreshBalance(
            meta: meta,
            secret: StoredAccountSecret(account: sampleAccount()),
            allowsReauthentication: true
        )

        #expect(result.meta.balanceSnapshot?.source == .authentication)
        #expect(result.meta.balanceSnapshot?.numericValue == Decimal(string: "24.90"))
        #expect(transport.requests.count == 2)
    }

    @Test
    func authenticationWithoutBalanceKeepsExistingSnapshot() async throws {
        var plist = authSuccessPlist()
        var accountInfo = plist["accountInfo"] as! [String: Any]
        accountInfo["balance"] = nil
        plist["accountInfo"] = accountInfo
        let transport = StoreTransportStub([.emptyBag, try .plist(plist, headers: storeFrontHeader)])
        let bridge = liveBridge(over: transport)
        let previous = BalanceSnapshot(
            displayText: "$1.00",
            numericValue: 1,
            currencyCode: "USD",
            fetchedAt: Date(timeIntervalSince1970: 0),
            source: .authentication,
            rawFieldPath: "accountInfo.balance"
        )
        var meta = StoredAccountMeta(account: sampleAccount(), deviceIdentifier: "ABCDEF123456", probeBundleID: "")
        meta.balanceSnapshot = previous

        let result = try await bridge.refreshBalance(
            meta: meta,
            secret: StoredAccountSecret(account: sampleAccount()),
            allowsReauthentication: true
        )

        #expect(result.meta.balanceSnapshot == previous)
    }
}

let storeFrontHeader = ["x-set-apple-store-front": "143441-1,29"]

func authSuccessPlist() -> [String: Any] {
    [
        "accountInfo": [
            "appleId": "demo@example.com",
            "address": ["firstName": "Demo", "lastName": "User"],
            "balance": ["display": "USD 24.90", "amount": 24.90, "currency": "USD"],
        ],
        "passwordToken": "token",
        "dsPersonId": "1234567890",
    ]
}

func authenticate(
    over transport: StoreTransportStub,
    code: String = "",
    cookies: [Cookie] = []
) async throws -> AuthenticationResult {
    try await Authenticator.authenticateWithResponse(
        email: "demo@example.com",
        password: "password",
        code: code,
        cookies: cookies,
        deviceIdentifier: "ABCDEF123456",
        transport: transport,
        signAction: { _ in "c2lnbmF0dXJl" }
    )
}

func liveBridge(over transport: StoreTransportStub) -> AppleSessionBridge {
    AppleSessionBridge(
        authenticator: LiveAppleAuthenticator(transport: transport, signAction: { _ in "c2lnbmF0dXJl" }),
        balanceService: BalanceService(probeClient: BalanceProbeClient(transport: transport))
    )
}

func probeMeta() -> StoredAccountMeta {
    StoredAccountMeta(account: sampleAccount(), deviceIdentifier: "ABCDEF123456", probeBundleID: "com.example.probe")
}
