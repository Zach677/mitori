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

    @Test
    func olderSearchCannotOverwriteNewerResults() async {
        let gate = SearchGate()
        let service = OutOfOrderProbeAppSearchService(gate: gate)
        let model = ProbeAppLookupModel(searchService: service)
        model.query = "first"
        let firstSearch = Task {
            await model.search(countryCode: "US")
        }
        await gate.waitUntilStarted()

        model.query = "second"
        await model.search(countryCode: "US")
        gate.release()
        await firstSearch.value

        #expect(model.results.map(\.name) == ["Second"])
        #expect(model.errorMessage == nil)
        #expect(model.isSearching == false)
    }
}

@MainActor
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

@MainActor
private final class OutOfOrderProbeAppSearchService: ProbeAppSearching {
    private let gate: SearchGate

    init(gate: SearchGate) {
        self.gate = gate
    }

    func searchApps(matching term: String, countryCode _: String, limit _: Int) async throws -> [ProbeAppCandidate] {
        if term == "first" {
            await gate.suspend()
            return [ProbeAppCandidate(id: 1, bundleID: "com.example.first", name: "First", sellerName: "Example")]
        }
        return [ProbeAppCandidate(id: 2, bundleID: "com.example.second", name: "Second", sellerName: "Example")]
    }
}

@MainActor
private final class SearchGate {
    private var hasStarted = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        hasStarted = true
        startContinuation?.resume()
        startContinuation = nil
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
