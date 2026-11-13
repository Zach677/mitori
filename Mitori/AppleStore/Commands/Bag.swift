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

    private static let defaultAuthEndpoint = "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate/"

    static func fetchBag(
        deviceIdentifier: String,
        transport: any StoreTransport = URLSessionStoreTransport.shared
    ) async throws -> BagOutput {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "init.itunes.apple.com"
        comps.path = "/bag.xml"
        comps.queryItems = [URLQueryItem(name: "guid", value: deviceIdentifier)]
        guard let url = comps.url else {
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!)
        }

        let headers: [(String, String)] = [
            ("User-Agent", Configuration.userAgent),
            ("Accept", "application/xml"),
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let (data, _) = try await transport.data(for: request)

        guard !data.isEmpty else {
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!)
        }

        let plistData = extractPlistData(from: data)

        guard let plist = try? PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ) as? [String: Any] else {
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!)
        }

        // authenticateAccount used to live inside the nested urlBag dict,
        // newer bag responses move it to the plist root
        let urlBag = plist["urlBag"] as? [String: Any] ?? [:]
        let authURLString = (plist["authenticateAccount"] as? String) ?? (urlBag["authenticateAccount"] as? String)

        guard let authURLString,
              let authURL = normalizedAuthEndpoint(from: authURLString)
        else {
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!)
        }

        // The login POST carries credentials, so the advertised URL must pass the
        // redirect policy before the legacy rewrite can turn it into a trusted one (I-2).
        if let advertisedURL = URL(string: authURLString) {
            _ = try StoreRedirectPolicy.validated(advertisedURL)
        }

        APLogger.info("bag: auth endpoint resolved to \(authURL)")
        return BagOutput(authEndpoint: authURL)
    }

    /// The bag advertises MZFinance `authenticate` without a trailing slash, and
    /// that bare path 301s without a Location header. Keep the bag host and add
    /// the slash, as ipatool does (D-20). The native `/fast` path has the same
    /// failure mode without its trailing slash.
    static func normalizedAuthEndpoint(from urlString: String) -> URL? {
        guard var comps = URLComponents(string: urlString) else { return nil }
        let host = comps.host?.lowercased() ?? ""
        if comps.path.hasSuffix("/MZFinance.woa/wa/authenticate") {
            comps.path += "/"
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
