import Foundation

@MainActor
final class ProbeAppLookupModel {
    private let searchService: any ProbeAppSearching

    var query = ""
    var results: [ProbeAppCandidate] = []
    var errorMessage: String?
    var isSearching = false

    init(searchService: any ProbeAppSearching = ProbeAppSearchService()) {
        self.searchService = searchService
    }

    var canSearch: Bool {
        !isSearching && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func search(countryCode: String?) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            results = try await searchService.searchApps(
                matching: trimmedQuery,
                countryCode: normalizedCountryCode(countryCode),
                limit: 5
            )

            if results.isEmpty {
                errorMessage = "No matching apps found. Try a more specific name."
            }
        } catch {
            results = []
            errorMessage = MitoriError.map(error).localizedDescription
        }
    }

    func select(_ candidate: ProbeAppCandidate) -> String {
        query = candidate.name
        results = []
        errorMessage = nil
        return candidate.bundleID
    }

    private func normalizedCountryCode(_ countryCode: String?) -> String {
        guard let countryCode, !countryCode.isEmpty else { return "US" }
        return countryCode.uppercased()
    }
}
