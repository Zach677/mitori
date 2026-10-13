//
//  Search.swift
//  ApplePackage
//
//  Created by qaq on 9/14/25.
//

import Foundation

public enum Searcher {
    private struct SearchResponse: Codable {
        var resultCount: Int
        var results: [Software]
    }

    static func search(
        term: String,
        countryCode: String,
        limit: Int = 5,
        entityType: EntityType = .iPhone,
        transport: any StoreTransport = URLSessionStoreTransport.shared
    ) async throws -> [Software] {
        let request = try makeRequest(
            term: term,
            countryCode: countryCode,
            limit: limit,
            entityType: entityType
        )
        let (data, response) = try await transport.data(for: request)

        guard response.statusCode == 200 else {
            throw StoreAuthError.transport(URLError(
                .badServerResponse,
                userInfo: [NSLocalizedDescriptionKey: "search request failed with status \(response.statusCode)"]
            ))
        }
        try ensure(!data.isEmpty, "response body is empty")

        let decoder = JSONDecoder()
        let searchResponse = try decoder.decode(SearchResponse.self, from: data)
        return searchResponse.results
    }

    private static func makeRequest(
        term: String,
        countryCode: String,
        limit: Int,
        entityType: EntityType
    ) throws -> URLRequest {
        let url = try createSearchURL(
            term: term,
            countryCode: countryCode,
            limit: limit,
            entityType: entityType
        )
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Configuration.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func createSearchURL(
        term: String,
        countryCode: String,
        limit: Int,
        entityType: EntityType
    ) throws -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "itunes.apple.com"
        comps.path = "/search"
        comps.queryItems = [
            URLQueryItem(name: "entity", value: entityType.searchEntityValue),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "media", value: "software"),
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: countryCode),
        ]
        return try comps.url.get()
    }
}
