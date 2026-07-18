import Foundation

@MainActor
final class ProbeAppLookupModel {
    private let searchService: any ProbeAppSearching

    var query = ""
    var results: [ProbeAppCandidate] = []
    var errorMessage: String?
    var isSearching = false
    private var searchGeneration = 0

    init(searchService: any ProbeAppSearching = ProbeAppSearchService()) {
        self.searchService = searchService
    }

    func search(countryCode: String?) async {
        searchGeneration += 1
        let generation = searchGeneration
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            results = []
            errorMessage = nil
            isSearching = false
            return
        }

        isSearching = true
        errorMessage = nil
        defer {
            if generation == searchGeneration {
                isSearching = false
            }
        }

        do {
            let newResults = try await searchService.searchApps(
                matching: trimmedQuery,
                countryCode: normalizedCountryCode(countryCode),
                limit: 5
            )
            guard generation == searchGeneration else { return }
            results = newResults

            if results.isEmpty {
                errorMessage = "No matching apps found. Try a more specific name."
            }
        } catch {
            guard generation == searchGeneration else { return }
            results = []
            errorMessage = MitoriError.map(error).localizedDescription
        }
    }

    func select(_ candidate: ProbeAppCandidate) -> String {
        searchGeneration += 1
        query = candidate.name
        results = []
        errorMessage = nil
        isSearching = false
        return candidate.bundleID
    }

    private func normalizedCountryCode(_ countryCode: String?) -> String {
        guard let countryCode, !countryCode.isEmpty else { return "US" }
        return countryCode.uppercased()
    }
}
