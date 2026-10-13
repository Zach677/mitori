import Foundation

@testable import Mitori

/// Answers each request with the next queued response and records every request.
final class StoreTransportStub: StoreTransport, @unchecked Sendable {
    struct Response {
        var status: Int
        var headers: [String: String] = [:]
        var body = Data()
    }

    private let lock = NSLock()
    private var responses: [Response]
    private var recorded: [URLRequest] = []

    init(_ responses: [Response]) {
        self.responses = responses
    }

    var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let next: Response = try lock.withLock {
            recorded.append(request)
            guard !responses.isEmpty else { throw URLError(.resourceUnavailable) }
            return responses.removeFirst()
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: next.status,
            httpVersion: "HTTP/1.1",
            headerFields: next.headers
        )!
        return (next.body, response)
    }
}

extension StoreTransportStub.Response {
    /// The bag falls back to the default auth endpoint on an empty body.
    static let emptyBag = Self(status: 200)

    static func plist(_ object: Any, status: Int = 200, headers: [String: String] = [:]) throws -> Self {
        Self(
            status: status,
            headers: headers,
            body: try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
        )
    }

    static func redirect(to location: String, status: Int = 302) -> Self {
        Self(status: status, headers: ["Location": location])
    }

    static func lookup(adamID: Int64, bundleID: String) -> Self {
        let json = """
        {"resultCount":1,"results":[{"trackId":\(adamID),"bundleId":"\(bundleID)","trackName":"Probe",\
        "version":"1.0","artistName":"Example","sellerName":"Example","description":"",\
        "averageUserRating":0,"userRatingCount":0,"artworkUrl512":"","screenshotUrls":[],\
        "minimumOsVersion":"14.0","currentVersionReleaseDate":"","primaryGenreName":"Utilities"}]}
        """
        return Self(status: 200, body: Data(json.utf8))
    }
}
