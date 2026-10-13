//
//  Lookup.swift
//
//
//  Created by qaq on 2025/9/14.
//

import Foundation

public enum Lookup {
    private struct LookupResponse: Codable {
        var resultCount: Int
        var results: [Software]
    }

    static func lookup(
        bundleID: String,
        countryCode: String,
        entityType: EntityType? = nil,
        transport: any StoreTransport = URLSessionStoreTransport.shared
    ) async throws -> Software {
        let request = try makeRequest(bundleID: bundleID, countryCode: countryCode, entityType: entityType)
        let (data, response) = try await transport.data(for: request)

        guard response.statusCode == 200 else {
            throw StoreAuthError.transport(URLError(
                .badServerResponse,
                userInfo: [NSLocalizedDescriptionKey: "lookup request failed with status \(response.statusCode)"]
            ))
        }

        try ensure(!data.isEmpty, "response body is empty")

        let decoder = JSONDecoder()
        let lookupResponse = try decoder.decode(LookupResponse.self, from: data)
        try ensure(lookupResponse.resultCount > 0, "no results found for bundle ID \(bundleID)")
        try ensure(lookupResponse.results.count == 1, "unexpected number of results: \(lookupResponse.resultCount)")

        return lookupResponse.results.first!
    }

    private static func makeRequest(
        bundleID: String,
        countryCode: String,
        entityType: EntityType?
    ) throws -> URLRequest {
        let url = try createLookupURL(bundleID: bundleID, countryCode: countryCode, entityType: entityType)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Configuration.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func createLookupURL(
        bundleID: String,
        countryCode: String,
        entityType: EntityType?
    ) throws -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "itunes.apple.com"
        comps.path = "/lookup"
        comps.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "country", value: countryCode),
            URLQueryItem(name: "entity", value: entityType?.entityValue ?? "software,iPadSoftware"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "media", value: "software"),
        ]
        return try comps.url.get()
    }
}
