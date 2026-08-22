import Combine
import Foundation

protocol MovieCatalogServing: Sendable {
    func invalidateCatalogCache() async
    func fetchMovies(page: Int) async throws -> MovieCatalogPage
    func fetchTV(page: Int) async throws -> MovieCatalogPage
    func fetchTrendingMovies() async throws -> [MovieTitle]
    func fetchPopularMovies() async throws -> [MovieTitle]
    func fetchGenre(_ slug: String, page: Int) async throws -> [MovieTitle]
    func fetchGenres() async throws -> [MovieGenre]
    func search(query: String) async throws -> [MovieTitle]
    func fetchShow(slug: String) async throws -> MovieShow
    func fetchEpisodes(slug: String) async throws -> [MovieEpisode]
}

extension MovieCatalogServing {
    func invalidateCatalogCache() async {}
}

extension MovieAPI: MovieCatalogServing {}

@MainActor
final class MovieStore: ObservableObject {
    private struct DetailSnapshot {
        let show: MovieShow
        let episodes: [MovieEpisode]
        let expiresAt: Date
    }

    @Published private(set) var titles: [MovieTitle] = []
    @Published private(set) var genres: [MovieGenre] = []
    @Published private(set) var selectedGenre: MovieGenre?
    @Published private(set) var isLoadingGenres = false
    @Published private(set) var genreError: String?
    @Published private(set) var selectedTitleID: MovieTitle.ID?
    @Published private(set) var show: MovieShow?
    @Published private(set) var episodes: [MovieEpisode] = []
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var catalogError: String?
    @Published private(set) var paginationError: String?
    @Published private(set) var detailError: String?

    private let api: any MovieCatalogServing
    private var loadedRequestKey: String?
    private var catalogRequestID = UUID()
    private var catalogPage = 0
    private var canLoadNextPage = false
    private var detailCache: [String: DetailSnapshot] = [:]
    private var dashboardSelectionID: MovieTitle.ID?
    private var genreLoadTask: Task<[MovieGenre], Error>?
    private var offlineDownloads: [MediaDownloadRecord] = []

    init(api: any MovieCatalogServing = MovieAPI.shared) {
        self.api = api
    }

    func updateOfflineDownloads(_ records: [MediaDownloadRecord]) {
        offlineDownloads = records.filter {
            $0.mediaType == .movie && $0.isAvailableOffline
        }
    }

    func hasLoadedCatalog(section: MovieSection, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty || query.count >= 2 else { return true }
        let requestKey = query.isEmpty
            ? "\(section.rawValue):\(section == .genres ? selectedGenre?.slug ?? "" : "")"
            : "search:\(query)"
        return loadedRequestKey == requestKey
    }

    func loadCatalog(
        section: MovieSection,
        query: String,
        force: Bool = false,
        selectsInitialTitle: Bool = true
    ) async {
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
            ? "\(section.rawValue):\(section == .genres ? selectedGenre?.slug ?? "" : "")"
            : "search:\(query)"
        guard force || loadedRequestKey != requestKey else {
            if selectsInitialTitle, dashboardSelectionID == nil, show == nil,
               let selected = titles.first(where: { $0.id == selectedTitleID }) ?? titles.first {
                await select(selected)
            }
            return
        }

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
            let result = try await fetchTitles(
                section: section,
                query: query,
                page: 1,
                requestID: requestID
            )
            guard !Task.isCancelled, catalogRequestID == requestID else { return }

            let uniqueTitles = result.titles.deduplicatedByID()
            titles = uniqueTitles
            catalogPage = 1
            canLoadNextPage = result.hasNextPage
            isLoadingCatalog = false
            completedCatalogRequest = true

            if selectsInitialTitle, dashboardSelectionID == nil {
                if let selectedTitleID,
                   let selected = uniqueTitles.first(where: { $0.id == selectedTitleID }) {
                    if show == nil { await select(selected) }
                } else if let first = uniqueTitles.first {
                    await select(first)
                } else {
                    clearSelection()
                }
            }
        } catch {
            guard !Task.isCancelled, catalogRequestID == requestID else { return }
            let downloadedTitles = offlineTitles(section: section, query: query)
            titles = downloadedTitles
            catalogError = downloadedTitles.isEmpty ? error.localizedDescription : nil
            if selectsInitialTitle, dashboardSelectionID == nil,
               let selected = downloadedTitles.first {
                await select(selected)
            } else if downloadedTitles.isEmpty {
                clearSelection()
            }
        }
    }

    func refresh(section: MovieSection, query: String) async {
        await api.invalidateCatalogCache()
        await loadCatalog(section: section, query: query, force: true)
    }

    func refreshHome() async {
        await api.invalidateCatalogCache()
        await loadCatalog(
            section: .discover,
            query: "",
            force: true,
            selectsInitialTitle: false
        )
    }

    func loadGenresIfNeeded() async {
        do {
            try await ensureGenresLoaded()
        } catch is CancellationError {
            return
        } catch {
            genreError = error.localizedDescription
        }
    }

    func selectGenre(_ genre: MovieGenre, query: String) async {
        guard selectedGenre != genre else { return }
        selectedGenre = genre
        await loadCatalog(section: .genres, query: query, force: true)
    }

    func selectFromDashboard(_ title: MovieTitle) {
        dashboardSelectionID = title.id
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.select(title, force: true)
            if self.dashboardSelectionID == title.id {
                self.dashboardSelectionID = nil
            }
        }
    }

    func select(_ title: MovieTitle, force: Bool = false) async {
        guard force || selectedTitleID != title.id || show == nil else { return }

        selectedTitleID = title.id
        show = nil
        episodes = []
        detailError = nil
        isLoadingDetail = true

        if !force,
           let cached = detailCache[title.slug],
           cached.expiresAt > Date() {
            show = cached.show
            episodes = cached.episodes
            isLoadingDetail = false
            return
        }
        detailCache.removeValue(forKey: title.slug)

        do {
            let loadedShow = try await api.fetchShow(slug: title.slug)
            guard selectedTitleID == title.id else { return }

            let loadedEpisodes = loadedShow.isSeries
                ? try await api.fetchEpisodes(slug: title.slug)
                : []
            guard selectedTitleID == title.id else { return }

            let sortedEpisodes = loadedEpisodes.sorted {
                ($0.season, $0.number) < ($1.season, $1.number)
            }
            let metadata = catalogMetadata(from: loadedShow)
            show = metadata
            episodes = sortedEpisodes
            detailCache[title.slug] = DetailSnapshot(
                show: metadata,
                episodes: sortedEpisodes,
                expiresAt: Date().addingTimeInterval(900)
            )
            trimDetailCache()
            isLoadingDetail = false
        } catch {
            guard selectedTitleID == title.id else { return }
            if !loadOfflineDetail(slug: title.slug) {
                detailError = error.localizedDescription
            }
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

    private func loadOfflineDetail(slug: String) -> Bool {
        let records = offlineDownloads.filter { $0.contentID == slug }
        guard let loadedShow = records.compactMap(\.movieShow).first else { return false }

        show = loadedShow
        episodes = records.compactMap(\.movieEpisode)
            .deduplicatedByID()
            .sorted { ($0.season, $0.number) < ($1.season, $1.number) }
        detailError = nil
        return true
    }

    private func offlineTitles(section: MovieSection, query: String) -> [MovieTitle] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let shows = offlineDownloads.compactMap(\.movieShow).deduplicatedByID()
        return shows.filter { show in
            guard normalizedQuery.isEmpty
                    || show.displayTitle.localizedCaseInsensitiveContains(normalizedQuery)
            else { return false }

            return switch section {
            case .movies:
                !show.isSeries
            case .tvShows:
                show.isSeries
            case .genres:
                selectedGenre == nil || show.genres.contains {
                    $0.localizedCaseInsensitiveCompare(selectedGenre?.title ?? "") == .orderedSame
                }
            default:
                true
            }
        }.map { show in
            MovieTitle(
                id: show.slug,
                slug: show.slug,
                title: show.title,
                imageURL: show.imageURL,
                imdbRating: show.imdbRating,
                runtime: show.duration,
                year: show.releaseYear,
                type: show.type,
                quality: nil
            )
        }
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
            try await ensureGenresLoaded()
            guard !Task.isCancelled, catalogRequestID == requestID else {
                throw CancellationError()
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
            let pageTitles = result.titles.deduplicatedByID()
            let newTitles = pageTitles.filter { !existingIDs.contains($0.id) }
            guard pageTitles.isEmpty || !newTitles.isEmpty else {
                paginationError = CatalogPaginationError
                    .repeatedPage(resource: "movie")
                    .localizedDescription
                return
            }
            titles.append(contentsOf: newTitles)
            catalogPage += 1
            canLoadNextPage = result.hasNextPage
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

    private func ensureGenresLoaded() async throws {
        guard genres.isEmpty else { return }

        let task: Task<[MovieGenre], Error>
        if let genreLoadTask {
            task = genreLoadTask
        } else {
            let api = self.api
            let newTask = Task { try await api.fetchGenres() }
            genreLoadTask = newTask
            isLoadingGenres = true
            genreError = nil
            task = newTask
        }

        do {
            let loadedGenres = try await task.value
            genres = loadedGenres
            selectedGenre = selectedGenre ?? loadedGenres.first
            genreError = nil
            isLoadingGenres = false
            genreLoadTask = nil
        } catch {
            isLoadingGenres = false
            genreLoadTask = nil
            genreError = error.localizedDescription
            throw error
        }
    }

    private func resetPagination() {
        catalogPage = 0
        canLoadNextPage = false
        isLoadingNextPage = false
        paginationError = nil
    }

    private func catalogMetadata(from show: MovieShow) -> MovieShow {
        MovieShow(
            slug: show.slug,
            title: show.title,
            type: show.type,
            imageURL: show.imageURL,
            description: show.description,
            imdbRating: show.imdbRating,
            tmdbRating: show.tmdbRating,
            rottenTomatoes: show.rottenTomatoes,
            metacritic: show.metacritic,
            genres: show.genres,
            director: show.director,
            actors: show.actors,
            duration: show.duration,
            releaseYear: show.releaseYear,
            releaseDate: show.releaseDate,
            country: show.country,
            seasons: show.seasons,
            streams: []
        )
    }

    private func trimDetailCache() {
        let now = Date()
        detailCache = detailCache.filter { $0.value.expiresAt > now }
        guard detailCache.count > 32 else { return }
        let overflow = detailCache.count - 32
        detailCache
            .sorted { $0.value.expiresAt < $1.value.expiresAt }
            .prefix(overflow)
            .forEach { detailCache.removeValue(forKey: $0.key) }
    }
}
