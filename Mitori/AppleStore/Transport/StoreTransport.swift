import Foundation

/// All Apple store traffic goes through one transport (I-1). It never follows
/// redirects and never stores cookies; callers handle both.
protocol StoreTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class URLSessionStoreTransport: StoreTransport {
    static let shared = URLSessionStoreTransport()

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = Configuration.timeoutRead
        configuration.timeoutIntervalForResource = Configuration.timeoutResource
        session = URLSession(
            configuration: configuration,
            delegate: RedirectRefusingDelegate(),
            delegateQueue: nil
        )
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
    }
}

private final class RedirectRefusingDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

extension HTTPURLResponse {
    func setCookies() -> [HTTPCookie] {
        guard let url else { return [] }
        let fields = allHeaderFields.reduce(into: [String: String]()) { fields, field in
            if let name = field.key as? String, let value = field.value as? String {
                fields[name] = value
            }
        }
        return HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
    }
}
