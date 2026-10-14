import Foundation
import os

/// Sanitized store request trace for live diagnosis (T5), off by default.
/// Enable: `defaults write dev.zach.mitori debug.storeTrace -bool YES`
/// Read:   `log stream --predicate 'subsystem == "dev.zach.mitori" && category == "StoreTrace"'`
/// A line never holds a URL, query, header value, body, or identifier (I-8).
enum StoreTrace {
    /// The user-level operation that owns the requests in this task.
    @TaskLocal static var operation: Operation?

    final class Operation: @unchecked Sendable {
        let name: String
        private let lock = NSLock()
        private var attempts: [String: Int] = [:]

        init(_ name: String) {
            self.name = name
        }

        func nextAttempt(for endpoint: String) -> Int {
            lock.withLock {
                attempts[endpoint, default: 0] += 1
                return attempts[endpoint]!
            }
        }
    }

    private static let logger = Logger(subsystem: "dev.zach.mitori", category: "StoreTrace")

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "debug.storeTrace")
    }

    /// Runs `body` as `name` unless an outer operation already owns this task.
    static func run<T>(
        _ name: String,
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async rethrows -> T {
        if operation != nil { return try await body() }
        return try await $operation.withValue(Operation(name), operation: body, isolation: isolation)
    }

    static func record(request: URLRequest, response: HTTPURLResponse?, data: Data?, error: Error?) {
        guard isEnabled else { return }
        let endpoint = endpointLabel(for: request.url)
        let line = describe(
            request: request,
            response: response,
            data: data,
            error: error,
            operation: operation?.name ?? "-",
            attempt: operation?.nextAttempt(for: endpoint) ?? 0
        )
        logger.notice("\(line, privacy: .public)")
    }

    static func describe(
        request: URLRequest,
        response: HTTPURLResponse?,
        data: Data?,
        error: Error?,
        operation: String,
        attempt: Int
    ) -> String {
        var fields = [
            "op=\(operation)",
            "endpoint=\(endpointLabel(for: request.url))",
            "attempt=\(attempt)",
            "method=\(request.httpMethod ?? "GET")",
            "cookiesSent=\(cookieCount(request.value(forHTTPHeaderField: "Cookie")))",
        ]
        if let response {
            let names = response.allHeaderFields.keys.compactMap { ($0 as? String)?.lowercased() }.sorted()
            fields += [
                "status=\(response.statusCode)",
                "cookiesSet=\(response.setCookies().count)",
                "headers=[\(names.joined(separator: ","))]",
                "body=\(data?.count ?? 0)B",
                "type=\(bodyType(data))",
            ]
        }
        if let error {
            fields.append("error=\(errorLabel(error))")
        }
        return fields.joined(separator: " ")
    }

    static func endpointLabel(for url: URL?) -> String {
        guard let host = url?.host?.lowercased() else { return "unknown" }
        let path = url?.path ?? ""
        switch host {
        case "init.itunes.apple.com":
            return "bag"
        case "auth.itunes.apple.com":
            return "auth.native"
        case "itunes.apple.com":
            return path.hasPrefix("/lookup") ? "lookup" : path.hasPrefix("/search") ? "search" : "itunes.other"
        default:
            break
        }
        guard host.hasSuffix(".itunes.apple.com") else { return "other" }
        if path.contains("authenticate") { return "auth.legacy" }
        if path.contains("volumeStoreDownloadProduct") { return "probe" }
        return "store.other"
    }

    private static func cookieCount(_ header: String?) -> Int {
        guard let header, !header.isEmpty else { return 0 }
        return header.split(separator: ";").count
    }

    private static func bodyType(_ data: Data?) -> String {
        guard let data, !data.isEmpty else { return "empty" }
        let prefix = String(decoding: data.prefix(256), as: UTF8.self).lowercased()
        if prefix.contains("<plist") || prefix.hasPrefix("bplist") { return "plist" }
        if prefix.contains("<html") || prefix.contains("<!doctype html") { return "html" }
        if prefix.hasPrefix("{") || prefix.hasPrefix("[") { return "json" }
        if prefix.hasPrefix("<?xml") { return "xml" }
        return "other"
    }

    private static func errorLabel(_ error: Error) -> String {
        if let error = error as? URLError { return "URLError(\(error.code.rawValue))" }
        if error is CancellationError { return "cancelled" }
        return String(describing: type(of: error))
    }
}
