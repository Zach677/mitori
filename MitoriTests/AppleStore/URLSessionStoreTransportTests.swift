import Foundation
import Testing

@testable import Mitori

struct URLSessionStoreTransportTests {
    @Test
    func redirectIsReturnedUnfollowed() async throws {
        let transport = URLSessionStoreTransport(protocolClasses: [RedirectingURLProtocol.self])
        let request = URLRequest(url: URL(string: "https://buy.itunes.apple.com/start")!)

        let (_, response) = try await transport.data(for: request)

        #expect(response.statusCode == 302)
        #expect(RedirectingURLProtocol.startedURLs == [request.url])
    }
}

/// Answers the first URL with a 302 and every other URL with a 200, and records each request it starts.
private final class RedirectingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var started: [URL] = []

    static var startedURLs: [URL] {
        lock.withLock { started }
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let url = request.url!
        let isFirst = Self.lock.withLock {
            Self.started.append(url)
            return Self.started.count == 1
        }
        if isFirst {
            let target = URL(string: "https://example.com/next")!
            let redirect = HTTPURLResponse(
                url: url,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": target.absoluteString]
            )!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: redirect)
            client?.urlProtocol(self, didReceive: redirect, cacheStoragePolicy: .notAllowed)
        } else {
            let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
            client?.urlProtocol(self, didReceive: ok, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
