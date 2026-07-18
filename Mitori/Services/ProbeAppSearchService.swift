import ApplePackage
import Foundation

struct ProbeAppCandidate: Equatable, Identifiable, Sendable {
    var id: Int64
    var bundleID: String
    var name: String
    var sellerName: String

    init(id: Int64, bundleID: String, name: String, sellerName: String) {
        self.id = id
        self.bundleID = bundleID
        self.name = name
        self.sellerName = sellerName
    }

    init(software: Software) {
        self.init(
            id: software.id,
            bundleID: software.bundleID,
            name: software.name,
            sellerName: software.sellerName
        )
    }
}

protocol ProbeAppSearching: Sendable {
    func searchApps(matching term: String, countryCode: String, limit: Int) async throws -> [ProbeAppCandidate]
}

struct ProbeAppSearchService: ProbeAppSearching {
    func searchApps(matching term: String, countryCode: String, limit: Int = 5) async throws -> [ProbeAppCandidate] {
        let results = try await Searcher.search(
            term: term,
            countryCode: countryCode,
            limit: limit
        )
        return results.map(ProbeAppCandidate.init(software:))
    }
}
