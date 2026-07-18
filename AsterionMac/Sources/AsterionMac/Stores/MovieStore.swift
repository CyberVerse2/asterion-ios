import Combine
import Foundation

@MainActor
final class MovieStore: ObservableObject {
    @Published private(set) var titles: [MovieTitle] = []
    @Published private(set) var genres: [MovieGenre] = []
    @Published private(set) var selectedGenre: MovieGenre?
    @Published private(set) var selectedTitleID: MovieTitle.ID?
    @Published private(set) var show: MovieShow?
    @Published private(set) var episodes: [MovieEpisode] = []
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var catalogError: String?
    @Published private(set) var paginationError: String?
    @Published private(set) var detailError: String?

    private let api: MovieAPI
    private var loadedRequestKey: String?
    private var catalogRequestID = UUID()
    private var catalogPage = 0
    private var canLoadNextPage = false

    init(api: MovieAPI = MovieAPI()) {
        self.api = api
    }

    func loadCatalog(section: MovieSection, query: String, force: Bool = false) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty || query.count >= 2 else {
            titles = []
            loadedRequestKey = "short-search:\(query)"
            catalogError = nil
            isLoadingCatalog = false
            clearSelection()
            return
        }

        let requestKey = query.isEmpty
            ? "\(section.rawValue):\(section == .genres ? selectedGenre?.slug ?? "" : "")"
            : "search:\(query)"
        guard force || loadedRequestKey != requestKey else { return }

        loadedRequestKey = requestKey
        let requestID = UUID()
        catalogRequestID = requestID
        isLoadingCatalog = true
        catalogError = nil
        resetPagination()

        do {
            let result = try await fetchTitles(
                section: section,
                query: query,
                page: 1,
                requestID: requestID
            )
            guard !Task.isCancelled, catalogRequestID == requestID else { return }

            titles = result.titles
            catalogPage = 1
            canLoadNextPage = result.hasNextPage
            isLoadingCatalog = false

            if let selectedTitleID,
               let selected = result.titles.first(where: { $0.id == selectedTitleID }) {
                if show == nil { await select(selected) }
            } else if let first = result.titles.first {
                await select(first)
            } else {
                clearSelection()
            }
        } catch {
            guard !Task.isCancelled, catalogRequestID == requestID else { return }
            titles = []
            catalogError = error.localizedDescription
            isLoadingCatalog = false
            clearSelection()
        }
    }

    func refresh(section: MovieSection, query: String) async {
        await loadCatalog(section: section, query: query, force: true)
    }

    func selectGenre(_ genre: MovieGenre, query: String) async {
        guard selectedGenre != genre else { return }
        selectedGenre = genre
        await loadCatalog(section: .genres, query: query, force: true)
    }

    func select(_ title: MovieTitle, force: Bool = false) async {
        guard force || selectedTitleID != title.id || show == nil else { return }

        selectedTitleID = title.id
        show = nil
        episodes = []
        detailError = nil
        isLoadingDetail = true

        do {
            let loadedShow = try await api.fetchShow(slug: title.slug)
            guard selectedTitleID == title.id else { return }

            let loadedEpisodes = loadedShow.isSeries
                ? try await api.fetchEpisodes(slug: title.slug)
                : []
            guard selectedTitleID == title.id else { return }

            show = loadedShow
            episodes = loadedEpisodes.sorted {
                ($0.season, $0.number) < ($1.season, $1.number)
            }
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

    func loadNextPageIfNeeded(section: MovieSection, query: String, currentTitle: MovieTitle) async {
        guard currentTitle.id == titles.last?.id else { return }
        await loadNextPage(section: section, query: query)
    }

    func retryNextPage(section: MovieSection, query: String) async {
        await loadNextPage(section: section, query: query)
    }

    private func fetchTitles(
        section: MovieSection,
        query: String,
        page: Int,
        requestID: UUID
    ) async throws -> (titles: [MovieTitle], hasNextPage: Bool) {
        if !query.isEmpty {
            return (try await api.search(query: query), false)
        }

        switch section {
        case .discover:
            return (try await api.fetchTrendingMovies(), false)
        case .movies:
            let result = try await api.fetchMovies(page: page)
            return (result.results, result.page < result.totalPages)
        case .tvShows:
            let result = try await api.fetchTV(page: page)
            return (result.results, result.page < result.totalPages)
        case .popular:
            return (try await api.fetchPopularMovies(), false)
        case .genres:
            if genres.isEmpty {
                let loadedGenres = try await api.fetchGenres()
                guard !Task.isCancelled, catalogRequestID == requestID else {
                    throw CancellationError()
                }
                genres = loadedGenres
                selectedGenre = selectedGenre ?? loadedGenres.first
            }
            guard let selectedGenre else { return ([], false) }
            loadedRequestKey = "\(section.rawValue):\(selectedGenre.slug)"
            let pageTitles = try await api.fetchGenre(selectedGenre.slug, page: page)
            return (pageTitles, !pageTitles.isEmpty)
        }
    }

    private func loadNextPage(section: MovieSection, query: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canLoadNextPage, !isLoadingCatalog, !isLoadingNextPage else { return }

        let requestKey = query.isEmpty
            ? "\(section.rawValue):\(section == .genres ? selectedGenre?.slug ?? "" : "")"
            : "search:\(query)"
        guard loadedRequestKey == requestKey else { return }

        let requestID = catalogRequestID
        isLoadingNextPage = true
        paginationError = nil
        defer {
            if catalogRequestID == requestID { isLoadingNextPage = false }
        }

        do {
            let result = try await fetchTitles(
                section: section,
                query: query,
                page: catalogPage + 1,
                requestID: requestID
            )
            guard !Task.isCancelled, catalogRequestID == requestID else { return }

            let existingIDs = Set(titles.map(\.id))
            let newTitles = result.titles.filter { !existingIDs.contains($0.id) }
            titles.append(contentsOf: newTitles)
            catalogPage += 1
            canLoadNextPage = result.hasNextPage && !newTitles.isEmpty
        } catch {
            guard !Task.isCancelled, catalogRequestID == requestID else { return }
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
