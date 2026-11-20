import Foundation
import Testing

@testable import Mitori

/// Replays store exchanges through the real `URLSessionStoreTransport`, with no live request (#14).
/// A scenario is `Fixtures/replay_<name>.json`. Its `source` field says which parts are recordings
/// and which parts have the shape of a sanitized trace. No fixture holds a secret (I-8).
@Suite(.serialized)
struct StoreReplayTests {
    @Test
    func signInWithZeroCreditAndNoProbe() async throws {
        let replay = try Replay("replay_sign_in_zero_credit")

        let result = try await replay.bridge.login(
            email: "demo@example.com",
            password: "password",
            code: "",
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "",
            existing: nil
        )

        #expect(replay.servedEndpoints == ["bag", "auth"])
        #expect(result.meta.storefront == "143465")
        #expect(result.meta.pod == "25")
        #expect(result.meta.balanceSnapshot?.numericValue == 0)
        #expect(result.meta.lastIssue == nil)
        #expect(Set(result.secret.cookies.map(\.name)) == ["mz_at0-1234567890", "itspod", "hsaccnt"])
    }

    @Test
    func signInWithProbeSendsTheSessionCookiesToThePod() async throws {
        let replay = try Replay("replay_sign_in_with_probe")

        let result = try await replay.bridge.login(
            email: "demo@example.com",
            password: "password",
            code: "",
            deviceIdentifier: "ABCDEF123456",
            probeBundleID: "com.apple.Pages",
            existing: nil
        )

        #expect(replay.servedEndpoints == ["bag", "auth", "lookup", "probe"])
        #expect(result.meta.balanceSnapshot?.numericValue == 88)
        #expect(result.meta.lastIssue == nil)

        let probe = try #require(replay.requests.last)
        #expect(probe.url?.host == "p25-buy.itunes.apple.com")
        let sent = Set((probe.value(forHTTPHeaderField: "Cookie") ?? "").components(separatedBy: "; "))
        // `hsaccnt` is host-only for buy.itunes.apple.com, so the pod host does not get it (#4).
        #expect(sent == ["mz_at0-1234567890=placeholder-session", "itspod=25"])
    }

    @Test
    func signInOfTwoFactorAccountWithNoCodeIsInvalidCredentials() async throws {
        let replay = try Replay("replay_sign_in_needs_code")

        await #expect(throws: MitoriError.invalidCredentials) {
            try await replay.bridge.login(
                email: "demo@example.com",
                password: "password",
                code: "",
                deviceIdentifier: "ABCDEF123456",
                probeBundleID: "",
                existing: nil
            )
        }
        // One sign-in request: the password is not sent again.
        #expect(replay.servedEndpoints == ["bag", "auth"])
    }

    @Test
    func signInRejectedByTheFrontProxyIsANetworkIssue() async throws {
        let replay = try Replay("replay_sign_in_rejected_by_proxy")

        await #expect {
            try await replay.bridge.login(
                email: "demo@example.com",
                password: "password",
                code: "",
                deviceIdentifier: "ABCDEF123456",
                probeBundleID: "",
                existing: nil
            )
        } throws: { error in
            MitoriError.map(error).issueKind == .network
        }
        #expect(replay.servedEndpoints == ["bag", "auth", "auth"])
    }
}

/// One loaded scenario and a session bridge that sends every request to it.
private struct Replay {
    private struct Scenario: Decodable {
        var source: String
        var exchanges: [Exchange]
    }

    private struct Exchange: Decodable {
        var endpoint: String
        var status: Int
        var headers: [String: String]
        var body: String
    }

    let bridge: AppleSessionBridge

    init(_ name: String) throws {
        let scenario = try JSONDecoder().decode(
            Scenario.self,
            from: FixtureLoader.data(named: name, withExtension: "json")
        )
        try ReplayURLProtocol.load(scenario.exchanges.map { exchange in
            let file = exchange.body as NSString
            return ReplayURLProtocol.Answer(
                endpoint: exchange.endpoint,
                status: exchange.status,
                headers: exchange.headers,
                body: try FixtureLoader.data(named: file.deletingPathExtension, withExtension: file.pathExtension)
            )
        })
        let transport = URLSessionStoreTransport(protocolClasses: [ReplayURLProtocol.self])
        bridge = AppleSessionBridge(
            authenticator: LiveAppleAuthenticator(transport: transport, signAction: { _ in "c2lnbmF0dXJl" }),
            balanceService: BalanceService(probeClient: BalanceProbeClient(transport: transport))
        )
    }

    var requests: [URLRequest] { ReplayURLProtocol.requests }
    var servedEndpoints: [String] { requests.map { StoreTrace.endpointLabel(for: $0.url) } }
}

/// Answers each request with the next answer of the scenario. A request for a different
/// endpoint than the next answer fails, so a scenario also fixes the request order.
/// The state is static because URLSession makes the instances; the suite is serialized.
private final class ReplayURLProtocol: URLProtocol {
    struct Answer {
        var endpoint: String
        var status: Int
        var headers: [String: String]
        var body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var answers: [Answer] = []
    nonisolated(unsafe) private static var started: [URLRequest] = []

    static func load(_ answers: [Answer]) {
        lock.withLock {
            self.answers = answers
            started = []
        }
    }

    static var requests: [URLRequest] {
        lock.withLock { started }
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let endpoint = StoreTrace.endpointLabel(for: request.url)
        let answer: Answer? = Self.lock.withLock {
            Self.started.append(request)
            guard Self.answers.first?.endpoint == endpoint else { return nil }
            return Self.answers.removeFirst()
        }
        guard let answer,
              let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: answer.status,
                  httpVersion: "HTTP/1.1",
                  headerFields: answer.headers
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
