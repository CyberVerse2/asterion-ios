import Combine
import Foundation

protocol AnimeCatalogServing: Sendable {
    func invalidateCatalogCache() async
    func fetchLatest(page: Int) async throws -> [AnimeTitle]
    func fetchPopular(page: Int) async throws -> [AnimeTitle]
    func fetchNewReleases(page: Int) async throws -> [AnimeTitle]
    func fetchGenre(_ genre: String, page: Int) async throws -> [AnimeTitle]
    func fetchSeason(season: String, year: Int, page: Int) async throws -> [AnimeTitle]
    func fetchType(_ type: String, page: Int) async throws -> [AnimeTitle]
    func fetchStatus(_ status: String, page: Int) async throws -> [AnimeTitle]
    func fetchSchedule(timeZoneHours: Double) async throws -> [AnimeScheduleDay]
    func fetchGenres() async throws -> [String]
    func search(query: String, page: Int) async throws -> [AnimeTitle]
    func fetchShow(slug: String) async throws -> AnimeShow
    func fetchEpisodes(showID: String) async throws -> [AnimeEpisode]
    func fetchRelatedSeasons(showID: String) async throws -> [AnimeRelatedSeason]
}

extension AnimeCatalogServing {
    func invalidateCatalogCache() async {}
}

extension AnimeAPI: AnimeCatalogServing {}

struct AnimeSeason: Equatable, Sendable {
    enum Name: String, Sendable {
        case winter
        case spring
        case summer
        case fall

        var title: String { rawValue.capitalized }
    }

    let name: Name
    let year: Int

    var title: String { "\(name.title) \(year)" }

    static func current(date: Date = .now, calendar: Calendar = .current) -> AnimeSeason {
        let month = calendar.component(.month, from: date)
        let name: Name = switch month {
        case 1...3: .winter
        case 4...6: .spring
        case 7...9: .summer
        default: .fall
        }
        return AnimeSeason(name: name, year: calendar.component(.year, from: date))
    }
}

@MainActor
final class AnimeStore: ObservableObject {
    static let types = ["tv", "movie", "ova", "ona", "special", "music", "tv-short", "tv-special"]

    @Published private(set) var titles: [AnimeTitle] = []
    @Published private(set) var seasonalTitles: [AnimeTitle] = []
    @Published private(set) var newReleaseTitles: [AnimeTitle] = []
    @Published private(set) var season = AnimeSeason.current()
    @Published private(set) var genres: [String] = []
    @Published private(set) var scheduleDays: [AnimeScheduleDay] = []
    @Published private(set) var selectedGenre: String?
    @Published private(set) var selectedType = AnimeStore.types[0]
    @Published private(set) var selectedTitleID: AnimeTitle.ID?
    @Published private(set) var show: AnimeShow?
    @Published private(set) var episodes: [AnimeEpisode] = []
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var isLoadingSeason = false
    @Published private(set) var isLoadingNewReleases = false
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var isLoadingSchedule = false
    @Published private(set) var catalogError: String?
    @Published private(set) var seasonError: String?
    @Published private(set) var newReleasesError: String?
    @Published private(set) var paginationError: String?
    @Published private(set) var detailError: String?
    @Published private(set) var scheduleError: String?

    private let api: any AnimeCatalogServing
    private var loadedRequestKey: String?
    private var loadedSeasonKey: String?
    private var hasLoadedNewReleases = false
    private var catalogRequestID = UUID()
    private var catalogPage = 0
    private var canLoadNextPage = false
    private var selectedScheduleTitle: AnimeTitle?
    private var dashboardSelectionID: AnimeTitle.ID?

    init(api: any AnimeCatalogServing = AnimeAPI.shared) {
        self.api = api
    }

    func hasLoadedCatalog(section: AnimeSection, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty || query.count >= 2 else { return true }
        let requestKey = query.isEmpty ? catalogRequestKey(section) : "search:\(query)"
        return loadedRequestKey == requestKey
    }

    func loadCatalog(
        section: AnimeSection,
        query: String,
        force: Bool = false,
        selectsInitialTitle: Bool = true
    ) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if section == .schedule, query.isEmpty {
            await loadSchedule(force: force)
            return
        }
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
            ? catalogRequestKey(section)
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

            if selectsInitialTitle, dashboardSelectionID == nil {
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
            }
        } catch {
            guard !Task.isCancelled, catalogRequestID == requestID else { return }
            titles = []
            catalogError = error.localizedDescription
            clearSelection()
        }
    }

    func refresh(section: AnimeSection, query: String) async {
        await api.invalidateCatalogCache()
        if section == .schedule,
           query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await loadSchedule(force: true)
            return
        }
        if section == .discover,
           query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            async let catalog: Void = loadCatalog(section: section, query: query, force: true)
            async let currentSeason: Void = loadCurrentSeason(force: true)
            async let newReleases: Void = loadDiscoverNewReleases(force: true)
            _ = await (catalog, currentSeason, newReleases)
        } else {
            await loadCatalog(section: section, query: query, force: true)
        }
    }

    func refreshHome() async {
        await api.invalidateCatalogCache()
        async let catalog: Void = loadCatalog(
            section: .discover,
            query: "",
            force: true,
            selectsInitialTitle: false
        )
        async let currentSeason: Void = loadCurrentSeason(force: true)
        async let newReleases: Void = loadDiscoverNewReleases(force: true)
        _ = await (catalog, currentSeason, newReleases)
    }

    func loadCurrentSeason(force: Bool = false) async {
        let requestedSeason = AnimeSeason.current()
        let requestKey = "\(requestedSeason.name.rawValue):\(requestedSeason.year)"
        guard force || loadedSeasonKey != requestKey else { return }

        season = requestedSeason
        loadedSeasonKey = requestKey
        isLoadingSeason = true
        seasonError = nil
        defer { isLoadingSeason = false }

        do {
            seasonalTitles = try await api.fetchSeason(
                season: requestedSeason.name.rawValue,
                year: requestedSeason.year,
                page: 1
            ).deduplicatedByID()
        } catch {
            seasonalTitles = []
            seasonError = error.localizedDescription
            loadedSeasonKey = nil
        }
    }

    func retryCurrentSeason() async {
        await loadCurrentSeason(force: true)
    }

    func loadDiscoverNewReleases(force: Bool = false) async {
        guard force || !hasLoadedNewReleases else { return }

        hasLoadedNewReleases = true
        isLoadingNewReleases = true
        newReleasesError = nil
        defer { isLoadingNewReleases = false }

        do {
            newReleaseTitles = try await api.fetchNewReleases(page: 1).deduplicatedByID()
        } catch {
            newReleaseTitles = []
            newReleasesError = error.localizedDescription
            hasLoadedNewReleases = false
        }
    }

    func retryDiscoverNewReleases() async {
        await loadDiscoverNewReleases(force: true)
    }

    func loadSchedule(force: Bool = false) async {
        guard force || scheduleDays.isEmpty else { return }

        catalogRequestID = UUID()
        resetPagination()
        clearSelection()
        isLoadingSchedule = true
        scheduleError = nil
        defer { isLoadingSchedule = false }

        do {
            let seconds = TimeZone.current.secondsFromGMT()
            let fetchedDays = try await api.fetchSchedule(
                timeZoneHours: Double(seconds) / 3_600
            )
            scheduleDays = fetchedDays.compactMap { day in
                let upcomingEntries = day.entries.filter { !$0.passed }
                guard !upcomingEntries.isEmpty else { return nil }
                return AnimeScheduleDay(label: day.label, entries: upcomingEntries)
            }
        } catch {
            scheduleDays = []
            scheduleError = error.localizedDescription
        }
    }

    func retrySchedule() async {
        await loadSchedule(force: true)
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

    func selectType(_ type: String, query: String) async {
        guard AnimeStore.types.contains(type), selectedType != type else { return }
        selectedType = type
        await loadCatalog(section: .types, query: query, force: true)
    }

    func select(_ entry: AnimeScheduleEntry) async {
        let title = AnimeTitle(
            slug: entry.slug,
            title: entry.title,
            japaneseTitle: entry.japaneseTitle,
            imageURL: nil,
            type: nil,
            episodeLabel: entry.episodeNumber.map { "Ep \($0)" }
        )
        selectedScheduleTitle = title
        await select(title)
    }

    func selectFromDashboard(_ title: AnimeTitle) {
        dashboardSelectionID = title.id
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.select(title, force: true)
            if self.dashboardSelectionID == title.id {
                self.dashboardSelectionID = nil
            }
        }
    }

    func select(_ title: AnimeTitle, force: Bool = false) async {
        guard force || selectedTitleID != title.id || show == nil else { return }

        if selectedScheduleTitle?.id != title.id {
            selectedScheduleTitle = nil
        }

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
              let title = (titles + seasonalTitles + newReleaseTitles + [selectedScheduleTitle].compactMap { $0 })
                .first(where: { $0.id == selectedTitleID }) else {
            return
        }
        await select(title, force: true)
    }

    func downloadGroups(for currentShow: AnimeShow) async throws -> [AnimeDownloadGroup] {
        let related = try await api.fetchRelatedSeasons(showID: currentShow.id)
        let currentEpisodes = episodes
        var orderedSeasons = related.filter(\.isTVSeason)

        if !orderedSeasons.contains(where: { $0.slug == currentShow.slug }) {
            orderedSeasons.append(
                AnimeRelatedSeason(
                    id: currentShow.id,
                    title: currentShow.displayTitle,
                    slug: currentShow.slug,
                    type: currentShow.type ?? "TV",
                    imageURL: currentShow.imageURL,
                    episodesCount: currentShow.episodesCount
                )
            )
        }

        return try await withThrowingTaskGroup(
            of: (Int, AnimeDownloadGroup).self,
            returning: [AnimeDownloadGroup].self
        ) { group in
            for (index, season) in orderedSeasons.enumerated() {
                group.addTask { [api] in
                    if season.slug == currentShow.slug {
                        return (
                            index,
                            AnimeDownloadGroup(show: currentShow, episodes: currentEpisodes)
                        )
                    }

                    let show = try await api.fetchShow(slug: season.slug)
                    let episodes = try await api.fetchEpisodes(showID: show.id)
                        .sorted { $0.number < $1.number }
                    return (index, AnimeDownloadGroup(show: show, episodes: episodes))
                }
            }

            var results: [(Int, AnimeDownloadGroup)] = []
            for try await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
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
        case .updated:
            return try await api.fetchLatest(page: page)
        case .added:
            return try await api.fetchNewReleases(page: page)
        case .popular:
            return try await api.fetchPopular(page: page)
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
        case .types:
            loadedRequestKey = "\(section.rawValue):\(selectedType)"
            return try await api.fetchType(selectedType, page: page)
        case .upcoming:
            return try await api.fetchStatus("not-yet-aired", page: page)
        case .ongoing:
            return try await api.fetchStatus("currently-airing", page: page)
        case .completed:
            return try await api.fetchStatus("finished-airing", page: page)
        case .schedule:
            return []
        }
    }

    private func loadNextPage(section: AnimeSection, query: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canLoadNextPage,
              !isLoadingCatalog,
              !isLoadingNextPage else { return }

        let requestKey = query.isEmpty
            ? catalogRequestKey(section)
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
        selectedScheduleTitle = nil
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

    private func catalogRequestKey(_ section: AnimeSection) -> String {
        switch section {
        case .genres:
            "\(section.rawValue):\(selectedGenre ?? "")"
        case .types:
            "\(section.rawValue):\(selectedType)"
        default:
            section.rawValue
        }
    }

}
