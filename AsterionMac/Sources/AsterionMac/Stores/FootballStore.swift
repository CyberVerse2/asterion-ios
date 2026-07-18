import Combine
import Foundation

@MainActor
final class FootballStore: ObservableObject {
    @Published private(set) var matches: [FootballMatch] = []
    @Published private(set) var selectedMatchID: FootballMatch.ID?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private let api: FootballAPI
    private var loadedSection: FootballSection?
    private var allMatches: [FootballMatch] = []
    private var query = ""
    private var requestID = UUID()

    init(api: FootballAPI = FootballAPI()) {
        self.api = api
    }

    var selectedMatch: FootballMatch? {
        matches.first { $0.id == selectedMatchID }
            ?? allMatches.first { $0.id == selectedMatchID }
    }

    func load(section: FootballSection, force: Bool = false) async {
        if !force, loadedSection == section, !allMatches.isEmpty {
            applySearch()
            return
        }

        let currentRequestID = UUID()
        requestID = currentRequestID
        isLoading = true
        error = nil

        do {
            let fetched = try await api.fetchMatches(section: section)
            guard !Task.isCancelled, requestID == currentRequestID else { return }
            loadedSection = section
            allMatches = fetched.sorted { $0.kickoff < $1.kickoff }
            applySearch()
            isLoading = false
        } catch {
            guard !Task.isCancelled, requestID == currentRequestID else { return }
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    func refresh(section: FootballSection) async {
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
        if query.isEmpty {
            matches = allMatches
        } else {
            matches = allMatches.filter {
                $0.displayTitle.localizedStandardContains(query)
                    || $0.category.localizedStandardContains(query)
            }
        }

        if !matches.contains(where: { $0.id == selectedMatchID }) {
            selectedMatchID = matches.first?.id
        }
    }
}
