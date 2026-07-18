import Combine
import Foundation

protocol AnimeCatalogServing: Sendable {
    func fetchLatest(page: Int) async throws -> [AnimeTitle]
    func fetchPopular(page: Int) async throws -> [AnimeTitle]
    func fetchNewReleases(page: Int) async throws -> [AnimeTitle]
    func fetchGenre(_ genre: String, page: Int) async throws -> [AnimeTitle]
    func fetchGenres() async throws -> [String]
    func search(query: String, page: Int) async throws -> [AnimeTitle]
    func fetchShow(slug: String) async throws -> AnimeShow
    func fetchEpisodes(showID: String) async throws -> [AnimeEpisode]
}

extension AnimeAPI: AnimeCatalogServing {}

@MainActor
final class AnimeStore: ObservableObject {
    @Published private(set) var titles: [AnimeTitle] = []
    @Published private(set) var genres: [String] = []
    @Published private(set) var selectedGenre: String?
    @Published private(set) var selectedTitleID: AnimeTitle.ID?
    @Published private(set) var show: AnimeShow?
    @Published private(set) var episodes: [AnimeEpisode] = []
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var catalogError: String?
    @Published private(set) var paginationError: String?
    @Published private(set) var detailError: String?

    private let api: any AnimeCatalogServing
    private var loadedRequestKey: String?
    private var catalogRequestID = UUID()
    private var catalogPage = 0
    private var canLoadNextPage = false

    init(api: any AnimeCatalogServing = AnimeAPI()) {
        self.api = api
    }

    func loadCatalog(section: AnimeSection, query: String, force: Bool = false) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty || query.count >= 2 else {
            catalogRequestID = UUID()
            titles = []
            loadedRequestKey = "short-search:\(query)"
            catalogError = nil
            isLoadingCatalog = false
            resetPagination()
            clearSelection()
            return
        }

        let requestKey = query.isEmpty
            ? "\(section.rawValue):\(section == .genres ? selectedGenre ?? "" : "")"
            : "search:\(query)"
        guard force || loadedRequestKey != requestKey else { return }

        loadedRequestKey = requestKey
        let requestID = UUID()
        catalogRequestID = requestID
        isLoadingCatalog = true
        catalogError = nil
        resetPagination()
        var completedCatalogRequest = false
        defer {
            if catalogRequestID == requestID {
                isLoadingCatalog = false
                if !completedCatalogRequest {
                    loadedRequestKey = nil
                }
            }
        }

        do {
            let loadedTitles = try await fetchTitles(
                section: section,
                query: query,
                page: 1,
                requestID: requestID
            ).deduplicatedByID()
            guard !Task.isCancelled, catalogRequestID == requestID else { return }

            titles = loadedTitles
            isLoadingCatalog = false
            catalogPage = 1
            canLoadNextPage = !loadedTitles.isEmpty
            completedCatalogRequest = true

            if let selectedTitleID,
               let selected = loadedTitles.first(where: { $0.id == selectedTitleID }) {
                if show == nil {
                    await select(selected)
                }
            } else if let first = loadedTitles.first {
                await select(first)
            } else {
                clearSelection()
            }
        } catch {
            guard !Task.isCancelled, catalogRequestID == requestID else { return }
            titles = []
            catalogError = error.localizedDescription
            clearSelection()
        }
    }

    func refresh(section: AnimeSection, query: String) async {
        await loadCatalog(section: section, query: query, force: true)
    }

    func loadNextPageIfNeeded(
        section: AnimeSection,
        query: String,
        currentTitle: AnimeTitle
    ) async {
        guard currentTitle.id == titles.last?.id else { return }
        await loadNextPage(section: section, query: query)
    }

    func retryNextPage(section: AnimeSection, query: String) async {
        await loadNextPage(section: section, query: query)
    }

    func selectGenre(_ genre: String, query: String) async {
        guard selectedGenre != genre else { return }
        selectedGenre = genre
        await loadCatalog(section: .genres, query: query, force: true)
    }

    func select(_ title: AnimeTitle, force: Bool = false) async {
        guard force || selectedTitleID != title.id || show == nil else { return }

        selectedTitleID = title.id
        show = nil
        episodes = []
        detailError = nil
        isLoadingDetail = true

        do {
            let loadedShow = try await api.fetchShow(slug: title.slug)
            guard selectedTitleID == title.id else { return }

            let loadedEpisodes = try await api.fetchEpisodes(showID: loadedShow.id)
            guard selectedTitleID == title.id else { return }

            show = loadedShow
            episodes = loadedEpisodes.sorted { $0.number < $1.number }
            isLoadingDetail = false
        } catch {
            guard selectedTitleID == title.id else { return }
            detailError = error.localizedDescription
            isLoadingDetail = false
        }
    }

    func retryDetail() async {
        guard let selectedTitleID,
              let title = titles.first(where: { $0.id == selectedTitleID }) else { return }
        await select(title, force: true)
    }

    private func fetchTitles(
        section: AnimeSection,
        query: String,
        page: Int,
        requestID: UUID
    ) async throws -> [AnimeTitle] {
        guard query.isEmpty else { return try await api.search(query: query, page: page) }

        switch section {
        case .discover:
            return try await api.fetchLatest(page: page)
        case .popular:
            return try await api.fetchPopular(page: page)
        case .newReleases:
            return try await api.fetchNewReleases(page: page)
        case .genres:
            if genres.isEmpty {
                let loadedGenres = try await api.fetchGenres()
                guard !Task.isCancelled, catalogRequestID == requestID else {
                    throw CancellationError()
                }
                genres = loadedGenres
                selectedGenre = selectedGenre ?? loadedGenres.first
            }
            guard let selectedGenre else { return [] }
            loadedRequestKey = "\(section.rawValue):\(selectedGenre)"
            return try await api.fetchGenre(selectedGenre, page: page)
        case .bookmarks:
            return []
        }
    }

    private func loadNextPage(section: AnimeSection, query: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canLoadNextPage,
              !isLoadingCatalog,
              !isLoadingNextPage else { return }

        let requestKey = query.isEmpty
            ? "\(section.rawValue):\(section == .genres ? selectedGenre ?? "" : "")"
            : "search:\(query)"
        guard loadedRequestKey == requestKey else { return }

        let requestID = catalogRequestID
        let nextPage = catalogPage + 1
        isLoadingNextPage = true
        paginationError = nil
        defer {
            if catalogRequestID == requestID {
                isLoadingNextPage = false
            }
        }

        do {
            let pageTitles = try await fetchTitles(
                section: section,
                query: query,
                page: nextPage,
                requestID: requestID
            ).deduplicatedByID()
            guard !Task.isCancelled,
                  catalogRequestID == requestID,
                  loadedRequestKey == requestKey else { return }

            let existingIDs = Set(titles.map(\.id))
            let newTitles = pageTitles.filter { !existingIDs.contains($0.id) }
            guard pageTitles.isEmpty || !newTitles.isEmpty else {
                paginationError = CatalogPaginationError
                    .repeatedPage(resource: "anime")
                    .localizedDescription
                return
            }
            titles.append(contentsOf: newTitles)
            catalogPage = nextPage
            canLoadNextPage = !pageTitles.isEmpty
        } catch {
            guard !Task.isCancelled,
                  catalogRequestID == requestID,
                  loadedRequestKey == requestKey else { return }
            paginationError = error.localizedDescription
        }
    }

    private func clearSelection() {
        selectedTitleID = nil
        show = nil
        episodes = []
        detailError = nil
        isLoadingDetail = false
    }

    private func resetPagination() {
        catalogPage = 0
        canLoadNextPage = false
        isLoadingNextPage = false
        paginationError = nil
    }

}
