//
//  Bag.swift
//  ApplePackage
//
//  Created on 2026/2/20.
//

import Foundation

public enum Bag {
    public struct BagOutput {
        public var authEndpoint: URL
    }

    private static let defaultAuthEndpoint = "https://auth.itunes.apple.com/auth/v1/native/fast/"

    static func fetchBag(
        deviceIdentifier: String = Configuration.deviceIdentifier,
        transport: any StoreTransport = URLSessionStoreTransport.shared
    ) async throws -> BagOutput {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "init.itunes.apple.com"
        comps.path = "/bag.xml"
        comps.queryItems = [URLQueryItem(name: "guid", value: deviceIdentifier)]
        guard let url = comps.url else {
            APLogger.debug("bag: failed to construct URL, using default auth endpoint")
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!)
        }

        let headers: [(String, String)] = [
            ("User-Agent", Configuration.userAgent),
            ("Accept", "application/xml"),
        ]

        APLogger.logRequest(method: "GET", url: url.absoluteString, headers: headers)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await transport.data(for: request)

        APLogger.logResponse(
            status: UInt(response.statusCode),
            headers: response.allHeaderFields.map { ("\($0.key)", "\($0.value)") },
            bodySize: data.count
        )

        guard !data.isEmpty else {
            APLogger.debug("bag: empty response body, using default auth endpoint")
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!)
        }

        let plistData = extractPlistData(from: data)

        guard let plist = try? PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ) as? [String: Any] else {
            APLogger.debug("bag: failed to parse plist, using default auth endpoint")
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!)
        }

        // authenticateAccount used to live inside the nested urlBag dict,
        // newer bag responses move it to the plist root
        let urlBag = plist["urlBag"] as? [String: Any] ?? [:]
        let authURLString = (plist["authenticateAccount"] as? String) ?? (urlBag["authenticateAccount"] as? String)

        guard let authURLString,
              let authURL = normalizedAuthEndpoint(from: authURLString)
        else {
            APLogger.debug("bag: no authenticateAccount in plist, using default auth endpoint")
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!)
        }

        APLogger.info("bag: auth endpoint resolved to \(authURL)")
        return BagOutput(authEndpoint: authURL)
    }

    /// The bag still advertises MZFinance `authenticate`, but that host now 301s
    /// without a Location header. Signed login has to hit native `/fast/`.
    /// `auth.itunes.apple.com` URLs without the `/fast/` trailing slash have the
    /// same 301-without-Location failure mode.
    static func normalizedAuthEndpoint(from urlString: String) -> URL? {
        guard var comps = URLComponents(string: urlString) else { return nil }
        let host = comps.host?.lowercased() ?? ""
        if host == "buy.itunes.apple.com",
           comps.path.contains("authenticate")
        {
            var native = URLComponents(string: defaultAuthEndpoint)
            native?.query = comps.query
            return native?.url
        }
        if host == "auth.itunes.apple.com" {
            var path = comps.path
            while path.hasSuffix("/") {
                path.removeLast()
            }
            if !path.hasSuffix("/fast") {
                path += "/fast"
            }
            comps.path = path + "/"
        }
        return comps.url
    }

    /// The bag XML response wraps the plist inside `<Document><Protocol><plist>...</plist>`.
    /// Extract the `<plist>...</plist>` portion so PropertyListSerialization can parse it.
    /// If the data is already a bare plist, return it as-is.
    private static func extractPlistData(from data: Data) -> Data {
        guard let xmlString = String(data: data, encoding: .utf8),
              let startRange = xmlString.range(of: "<plist"),
              let endRange = xmlString.range(of: "</plist>")
        else {
            return data
        }
        return Data(xmlString[startRange.lowerBound ..< endRange.upperBound].utf8)
    }
}
