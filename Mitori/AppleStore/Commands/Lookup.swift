//
//  Lookup.swift
//
//
//  Created by qaq on 2025/9/14.
//

import Foundation

enum Lookup {
    private struct LookupResponse: Codable {
        var resultCount: Int
        var results: [Software]
    }

    static func lookup(
        bundleID: String,
        countryCode: String,
        transport: any StoreTransport = URLSessionStoreTransport.shared
    ) async throws -> Software {
        let request = try makeRequest(bundleID: bundleID, countryCode: countryCode)
        let (data, response) = try await transport.data(for: request)

        guard response.statusCode == 200 else {
            throw StoreAuthError.transport(URLError(
                .badServerResponse,
                userInfo: [NSLocalizedDescriptionKey: "lookup request failed with status \(response.statusCode)"]
            ))
        }

        guard !data.isEmpty else {
            throw StoreAuthError.malformedResponse("lookup response body is empty")
        }

        let lookupResponse: LookupResponse
        do {
            lookupResponse = try JSONDecoder().decode(LookupResponse.self, from: data)
        } catch {
            throw StoreAuthError.malformedResponse("lookup response could not be decoded")
        }
        guard lookupResponse.resultCount > 0, let first = lookupResponse.results.first else {
            throw StoreAuthError.probeAppNotFound(bundleID)
        }
        guard lookupResponse.results.count == 1 else {
            throw StoreAuthError.malformedResponse("unexpected number of lookup results: \(lookupResponse.resultCount)")
        }

        return first
    }

    private static func makeRequest(
        bundleID: String,
        countryCode: String
    ) throws -> URLRequest {
        let url = try createLookupURL(bundleID: bundleID, countryCode: countryCode)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Configuration.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func createLookupURL(
        bundleID: String,
        countryCode: String
    ) throws -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "itunes.apple.com"
        comps.path = "/lookup"
        comps.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "country", value: countryCode),
            URLQueryItem(name: "entity", value: "software,iPadSoftware"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "media", value: "software"),
        ]
        return try comps.url.get()
    }
}
