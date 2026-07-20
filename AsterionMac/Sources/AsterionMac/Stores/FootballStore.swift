import Combine
import Foundation

protocol FootballCatalogServing: Sendable {
    func invalidateCatalogCache() async
    func fetchMatches(section: FootballSection) async throws -> [FootballMatch]
}

extension FootballCatalogServing {
    func invalidateCatalogCache() async {}
}

extension FootballAPI: FootballCatalogServing {}

@MainActor
final class FootballStore: ObservableObject {
    @Published private(set) var matches: [FootballMatch] = []
    @Published private(set) var selectedMatchID: FootballMatch.ID?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private let api: any FootballCatalogServing
    private let now: @Sendable () -> Date
    private var loadedSection: FootballSection?
    private var allMatches: [FootballMatch] = []
    private var query = ""
    private var requestID = UUID()

    init(
        api: any FootballCatalogServing = FootballAPI.shared,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.api = api
        self.now = now
    }

    var selectedMatch: FootballMatch? {
        matches.first { $0.id == selectedMatchID }
            ?? allMatches.first { $0.id == selectedMatchID }
    }

    func load(section: FootballSection, force: Bool = false) async {
        if !force, isLoading, loadedSection == section {
            return
        }

        if loadedSection != section {
            loadedSection = section
            allMatches = []
            matches = []
            selectedMatchID = nil
        }

        let currentRequestID = UUID()
        requestID = currentRequestID
        isLoading = true
        error = nil
        var completedRequest = false
        defer {
            if requestID == currentRequestID {
                isLoading = false
                if !completedRequest {
                    loadedSection = nil
                }
            }
        }

        do {
            let fetched = try await api.fetchMatches(section: section)
            guard !Task.isCancelled, requestID == currentRequestID else { return }
            allMatches = fetched.sorted { $0.kickoff < $1.kickoff }
            applySearch()
            completedRequest = true
        } catch {
            guard !Task.isCancelled, requestID == currentRequestID else { return }
            self.error = error.localizedDescription
        }
    }

    func refresh(section: FootballSection) async {
        await api.invalidateCatalogCache()
        await load(section: section, force: true)
    }

    func updateSearch(_ value: String) {
        query = value.trimmingCharacters(in: .whitespacesAndNewlines)
        applySearch()
    }

    func select(_ match: FootballMatch) {
        selectedMatchID = match.id
    }

    private func applySearch() {
        let availableMatches = loadedSection == .schedule
            ? allMatches.filter { $0.kickoff >= now() }
            : allMatches

        if query.isEmpty {
            matches = availableMatches
        } else {
            matches = availableMatches.filter {
                $0.displayTitle.localizedStandardContains(query)
                    || $0.category.localizedStandardContains(query)
            }
        }

        if !matches.contains(where: { $0.id == selectedMatchID }) {
            selectedMatchID = matches.first?.id
        }
    }
}
