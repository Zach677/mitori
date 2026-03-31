import Foundation
import Testing

@testable import Mitori

@MainActor
struct ProbeAppLookupModelTests {
    @Test
    func searchPublishesResultsFromService() async throws {
        let service = ProbeAppSearchServiceStub(
            results: [
                ProbeAppCandidate(
                    id: 1,
                    bundleID: "com.example.app",
                    name: "Example App",
                    sellerName: "Example Studio"
                )
            ]
        )
        let model = ProbeAppLookupModel(searchService: service)
        model.query = "  example app  "

        await model.search(countryCode: "us")

        #expect(service.recordedQueries.count == 1)
        #expect(service.recordedQueries.first?.term == "example app")
        #expect(service.recordedQueries.first?.countryCode == "US")
        #expect(service.recordedQueries.first?.limit == 5)
        #expect(model.results.count == 1)
        #expect(model.results.first?.bundleID == "com.example.app")
        #expect(model.errorMessage == nil)
        #expect(model.isSearching == false)
    }

    @Test
    func selectingCandidateReturnsBundleIDAndClearsTransientState() {
        let model = ProbeAppLookupModel(searchService: ProbeAppSearchServiceStub())
        let candidate = ProbeAppCandidate(
            id: 2,
            bundleID: "com.example.pickme",
            name: "Pick Me",
            sellerName: "Example Studio"
        )
        model.query = "pick"
        model.results = [candidate]
        model.errorMessage = "Old error"

        let bundleID = model.select(candidate)

        #expect(bundleID == "com.example.pickme")
        #expect(model.query == "Pick Me")
        #expect(model.results.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test
    func emptyResultsShowHelpfulMessage() async {
        let model = ProbeAppLookupModel(searchService: ProbeAppSearchServiceStub())
        model.query = "missing"

        await model.search(countryCode: nil)

        #expect(model.results.isEmpty)
        #expect(model.errorMessage == "No matching apps found. Try a more specific name.")
    }
}

private final class ProbeAppSearchServiceStub: ProbeAppSearching {
    let results: [ProbeAppCandidate]
    private(set) var recordedQueries: [(term: String, countryCode: String, limit: Int)] = []

    init(results: [ProbeAppCandidate] = []) {
        self.results = results
    }

    func searchApps(matching term: String, countryCode: String, limit: Int) async throws -> [ProbeAppCandidate] {
        recordedQueries.append((term, countryCode, limit))
        return results
    }
}
