import Foundation
import Testing
@testable import AsterionMac

@Suite(.serialized)
struct CatalogRequestTests {
    @Test func apiClientDeduplicatesACompletedNovelPage() async throws {
        let data = try Self.novelPage(ids: ["novel-1", "novel-1", "novel-2"], total: 2)
        CatalogURLProtocol.install { request in
            (Self.successResponse(for: request), data)
        }
        defer { CatalogURLProtocol.reset() }

        let client = APIClient(session: Self.stubbedSession())
        let novels = try await client.fetchAllNovels()

        #expect(novels.map(\.id) == ["novel-1", "novel-2"])
    }

    @Test func apiClientStopsWhenAFullNovelPageRepeats() async throws {
        let ids = (0..<100).map { "novel-\($0)" }
        let data = try Self.novelPage(ids: ids, total: 200)
        CatalogURLProtocol.install { request in
            (Self.successResponse(for: request), data)
        }
        defer { CatalogURLProtocol.reset() }

        let client = APIClient(session: Self.stubbedSession())
        do {
            _ = try await client.fetchAllNovels()
            Issue.record("Expected repeated pagination to stop with an error.")
        } catch let error as CatalogPaginationError {
            guard case .repeatedPage(let resource) = error else {
                Issue.record("Expected a repeated-page error.")
                return
            }
            #expect(resource == "novel")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func chapterPageFetchesOnlyTheRequestedRangeAndSearch() async throws {
        let data = try Self.chapterPage(numbers: [1201, 1202], total: 2_400, offset: 1_200)
        CatalogURLProtocol.install { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let query = Dictionary(
                uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value) }
            )
            #expect(request.url?.path == "/novels/42/chapters")
            #expect(query["limit"] == "100")
            #expect(query["offset"] == "1200")
            #expect(query["search"] == "dragon")
            return (Self.successResponse(for: request), data)
        }
        defer { CatalogURLProtocol.reset() }

        let client = APIClient(session: Self.stubbedSession())
        let page = try await client.fetchChapterPage(
            novelID: "42",
            offset: 1_200,
            search: "dragon"
        )

        #expect(page.chapters.map(\.chapterNumber) == [1201, 1202])
        #expect(page.total == 2_400)
        #expect(page.pageIndex == 12)
        #expect(page.pageCount == 24)
    }

    @Test func fetchChapterByIDLoadsThatChapterOnly() async throws {
        let data = try Self.chapterEnvelope(
            id: "12",
            number: 3,
            title: "The Gate",
            content: "<p>Opened.</p>"
        )
        CatalogURLProtocol.install { request in
            #expect(request.url?.path == "/chapters/12")
            #expect(request.url?.query == nil)
            return (Self.successResponse(for: request), data)
        }
        defer { CatalogURLProtocol.reset() }

        let client = APIClient(session: Self.stubbedSession())
        let chapter = try await client.fetchChapter(id: "12")

        #expect(chapter.id == "12")
        #expect(chapter.chapterNumber == 3)
        #expect(chapter.title == "The Gate")
        #expect(chapter.content == "<p>Opened.</p>")
    }

    @Test func fetchChapterByNumberLoadsThatChapterOnly() async throws {
        let data = try Self.chapterEnvelope(
            id: "12",
            number: 3,
            title: "The Gate",
            content: "<p>Opened.</p>"
        )
        CatalogURLProtocol.install { request in
            #expect(request.url?.path == "/novels/42/chapters/3")
            return (Self.successResponse(for: request), data)
        }
        defer { CatalogURLProtocol.reset() }

        let client = APIClient(session: Self.stubbedSession())
        let chapter = try await client.fetchChapter(novelID: "42", chapterNumber: 3)

        #expect(chapter.id == "12")
        #expect(chapter.chapterNumber == 3)
    }

    @Test @MainActor func animeCatalogDeduplicatesEveryPageAndSurfacesARepeat() async {
        let first = Self.animeTitle("anime-1")
        let second = Self.animeTitle("anime-2")
        let third = Self.animeTitle("anime-3")
        let service = AnimeCatalogStub(
            pages: [
                1: [first, first, second],
                2: [second, third, third],
                3: [third, third],
            ]
        )
        let store = AnimeStore(api: service)
        #expect(!store.hasLoadedCatalog(section: .discover, query: ""))

        await store.loadCatalog(section: .discover, query: "")
        #expect(store.hasLoadedCatalog(section: .discover, query: ""))
        #expect(store.titles.map(\.id) == [first.id, second.id])

        await store.loadNextPageIfNeeded(
            section: .discover,
            query: "",
            currentTitle: second
        )
        #expect(store.titles.map(\.id) == [first.id, second.id, third.id])

        await store.loadNextPageIfNeeded(
            section: .discover,
            query: "",
            currentTitle: third
        )
        #expect(store.paginationError?.contains("repeated the previous page") == true)

        await store.retryNextPage(section: .discover, query: "")
        let calls = await service.latestCallCount
        #expect(calls == 4)
    }

    @Test @MainActor func animeGenresPreloadWithoutReplacingTheCurrentShelf() async {
        let title = Self.animeTitle("anime-1")
        let genres = ["slice-of-life", "action", "action", "sci-fi"]
        let service = AnimeCatalogStub(pages: [1: [title]], genres: genres)
        let store = AnimeStore(api: service)

        await store.loadCatalog(section: .popular, query: "")
        await store.loadGenresIfNeeded()
        await store.loadGenresIfNeeded()

        #expect(store.titles.map(\.id) == [title.id])
        #expect(store.genres == ["action", "sci-fi", "slice-of-life"])
        #expect(store.selectedGenre == "action")
        #expect(!store.isLoadingGenres)
        #expect(store.genreError == nil)
        #expect(await service.genreCallCount == 1)
    }

    @Test @MainActor func animeDiscoverKeepsShelvesWhenRefreshFails() async {
        let title = Self.animeTitle("anime-1")
        let service = AnimeCatalogStub(pages: [1: [title]])
        let store = AnimeStore(api: service)

        await store.loadCurrentSeason()
        await store.loadDiscoverNewReleases()
        await service.failNextSeasonAndReleases()
        await store.loadCurrentSeason(force: true)
        await store.loadDiscoverNewReleases(force: true)

        #expect(store.seasonalTitles.map(\.id) == [title.id])
        #expect(store.newReleaseTitles.map(\.id) == [title.id])
        #expect(store.seasonError == nil)
        #expect(store.newReleasesError == nil)
    }

    @Test @MainActor func cancelledAnimeShelfLoadsAreNotSurfacedAsErrors() async {
        let service = AnimeCatalogStub(pages: [:])
        let store = AnimeStore(api: service)

        await service.cancelNextSeasonAndReleases()
        await store.loadCurrentSeason()
        await store.loadDiscoverNewReleases()

        #expect(store.seasonalTitles.isEmpty)
        #expect(store.newReleaseTitles.isEmpty)
        #expect(store.seasonError == nil)
        #expect(store.newReleasesError == nil)
    }

    @Test @MainActor func animeDetailFallsBackToDownloadedMetadataWhenOffline() async {
        let show = Self.animeShow("offline-anime")
        let episode = AnimeEpisode(id: "offline-anime-episode-3", animeID: show.id, number: 3)
        let service = AnimeCatalogStub(pages: [:], failsCatalog: true, failsDetail: true)
        let store = AnimeStore(api: service)
        store.updateOfflineDownloads([
            Self.mediaDownload(animeShow: show, episode: episode),
        ])

        await store.loadCatalog(section: .discover, query: "")

        #expect(store.titles.map(\.slug) == [show.slug])
        #expect(store.show == show)
        #expect(store.episodes == [episode])
        #expect(store.catalogError == nil)
        #expect(store.detailError == nil)
    }

    @Test @MainActor func movieCatalogDeduplicatesEveryPageAndSurfacesARepeat() async {
        let first = Self.movieTitle("movie-1")
        let second = Self.movieTitle("movie-2")
        let third = Self.movieTitle("movie-3")
        let service = MovieCatalogStub(
            pages: [
                1: MovieCatalogPage(
                    page: 1,
                    totalPages: 3,
                    results: [first, first, second]
                ),
                2: MovieCatalogPage(
                    page: 2,
                    totalPages: 3,
                    results: [second, third, third]
                ),
                3: MovieCatalogPage(
                    page: 3,
                    totalPages: 3,
                    results: [third, third]
                ),
            ]
        )
        let store = MovieStore(api: service)
        #expect(!store.hasLoadedCatalog(section: .movies, query: ""))

        await store.loadCatalog(section: .movies, query: "")
        #expect(store.hasLoadedCatalog(section: .movies, query: ""))
        #expect(store.titles.map(\.id) == [first.id, second.id])

        await store.loadNextPageIfNeeded(
            section: .movies,
            query: "",
            currentTitle: second
        )
        #expect(store.titles.map(\.id) == [first.id, second.id, third.id])

        await store.loadNextPageIfNeeded(
            section: .movies,
            query: "",
            currentTitle: third
        )
        #expect(store.paginationError?.contains("repeated the previous page") == true)
    }

    @Test @MainActor func movieGenresPreloadWithoutReplacingTheCurrentShelf() async {
        let title = Self.movieTitle("movie-1")
        let genres = [
            MovieGenre(slug: "action", title: "Action"),
            MovieGenre(slug: "drama", title: "Drama"),
        ]
        let service = MovieCatalogStub(
            pages: [
                1: MovieCatalogPage(page: 1, totalPages: 1, results: [title]),
            ],
            genres: genres
        )
        let store = MovieStore(api: service)

        await store.loadCatalog(section: .movies, query: "")
        await store.loadGenresIfNeeded()
        await store.loadGenresIfNeeded()

        #expect(store.titles.map(\.id) == [title.id])
        #expect(store.genres == genres)
        #expect(store.selectedGenre == genres.first)
        #expect(!store.isLoadingGenres)
        #expect(store.genreError == nil)
        #expect(await service.genreCallCount == 1)
    }

    @Test @MainActor func movieDetailFallsBackToDownloadedMetadataWhenOffline() async {
        let show = Self.movieShow("offline-series", type: "tv")
        let episode = MovieEpisode(
            id: "offline-series-s1e2",
            season: 1,
            number: 2,
            title: "Episode 2",
            url: URL(string: "https://movies.example/offline-series/s1e2")!
        )
        let service = MovieCatalogStub(
            pages: [:],
            failsCatalog: true,
            failsDetail: true
        )
        let store = MovieStore(api: service)
        store.updateOfflineDownloads([
            Self.mediaDownload(movieShow: show, episode: episode),
        ])

        await store.loadCatalog(section: .tvShows, query: "")

        #expect(store.titles.map(\.slug) == [show.slug])
        #expect(store.show == show)
        #expect(store.episodes == [episode])
        #expect(store.catalogError == nil)
        #expect(store.detailError == nil)
    }

    @Test func movieGenreFallbackIsCompleteAndPrefersFreshServiceSlugs() {
        let genres = MovieAPI.completeGenreList([
            MovieGenre(slug: "current-action", title: "Action"),
        ])

        #expect(genres.count == 22)
        #expect(genres.first(where: { $0.title == "Action" })?.slug == "current-action")
        #expect(genres.contains(where: { $0.title == "Western" }))
    }

    @Test func animeStreamResolutionRetriesATemporary502() async throws {
        let attempts = CatalogRequestCounter()
        CatalogURLProtocol.install { request in
            if attempts.increment() == 1 {
                return (
                    Self.response(for: request, statusCode: 502),
                    Data(#"{"error":"Temporary gateway failure"}"#.utf8)
                )
            }
            let payload = Data(
                #"[{"server":"primary","url":"https://embed.example/watch","quality":"1080p","source":"https://cdn.example/video.m3u8","tracks":[]}]"#.utf8
            )
            return (Self.successResponse(for: request), payload)
        }
        defer { CatalogURLProtocol.reset() }

        let api = AnimeAPI(
            baseURL: URL(string: "https://anime.example")!,
            session: Self.stubbedSession(),
            responseCache: HTTPResponseCache(),
            retryDelays: [.zero]
        )
        let sources = try await api.fetchStream(animeID: "anime-1", episodeNumber: 1)

        #expect(sources.first?.server == "primary")
        #expect(attempts.value == 2)
    }

    @Test func animeCatalogKeepsStaleShelvesAfterAGatewayFailure() async throws {
        let clock = CatalogDateBox()
        let cache = HTTPResponseCache(now: { clock.now })
        let attempts = CatalogRequestCounter()
        CatalogURLProtocol.install { request in
            if attempts.increment() == 1 {
                let payload = Data(
                    #"[{"slug":"cached-show","title":"Cached Show","japanese_title":null,"image_url":null,"type":"TV","episode_label":"12 episodes"}]"#.utf8
                )
                return (Self.successResponse(for: request), payload)
            }
            return (
                Self.response(for: request, statusCode: 502),
                Data("error code: 502\n".utf8)
            )
        }
        defer { CatalogURLProtocol.reset() }

        let api = AnimeAPI(
            baseURL: URL(string: "https://anime.example")!,
            session: Self.stubbedSession(),
            responseCache: cache,
            retryDelays: [.zero]
        )

        let first = try await api.fetchSeason(season: "summer", year: 2026, page: 1)
        clock.now = clock.now.addingTimeInterval(121)
        let second = try await api.fetchSeason(season: "summer", year: 2026, page: 1)

        #expect(first.map(\.slug) == ["cached-show"])
        #expect(second.map(\.slug) == ["cached-show"])
        #expect(attempts.value > 1)
    }

    @Test func animeGatewayFailureHasAReadableMessage() {
        let error = AnimeAPIError.http(statusCode: 502, message: "")
        #expect(error.errorDescription == "The anime service is temporarily unreachable.")
    }

    @Test @MainActor func cancelledAnimeCatalogCanRetryTheSameRequest() async throws {
        let service = AnimeCatalogStub(pages: [1: []], suspendFirstRequest: true)
        let store = AnimeStore(api: service)
        let firstLoad = Task {
            await store.loadCatalog(section: .discover, query: "")
        }

        try await Self.waitUntil { await service.latestCallCount == 1 }
        firstLoad.cancel()
        await firstLoad.value

        #expect(!store.isLoadingCatalog)
        await store.loadCatalog(section: .discover, query: "")
        let calls = await service.latestCallCount
        #expect(calls == 2)
    }

    @Test @MainActor func cancelledMovieCatalogCanRetryTheSameRequest() async throws {
        let emptyPage = MovieCatalogPage(page: 1, totalPages: 1, results: [])
        let service = MovieCatalogStub(pages: [1: emptyPage], suspendFirstRequest: true)
        let store = MovieStore(api: service)
        let firstLoad = Task {
            await store.loadCatalog(section: .movies, query: "")
        }

        try await Self.waitUntil { await service.movieCallCount == 1 }
        firstLoad.cancel()
        await firstLoad.value

        #expect(!store.isLoadingCatalog)
        await store.loadCatalog(section: .movies, query: "")
        let calls = await service.movieCallCount
        #expect(calls == 2)
    }

    @Test @MainActor func cancelledFootballCatalogCanRetryTheSameSection() async throws {
        let service = FootballCatalogStub(suspendFirstRequest: true)
        let store = FootballStore(api: service)
        let firstLoad = Task {
            await store.load(section: .live)
        }

        try await Self.waitUntil { await service.callCount == 1 }
        firstLoad.cancel()
        await firstLoad.value

        #expect(!store.isLoading)
        await store.load(section: .live)
        let calls = await service.callCount
        #expect(calls == 2)
    }

    @Test @MainActor func emptyFootballCatalogRefetchesOnReentry() async {
        let fixture = Self.footballMatch("fixture-after-empty")
        let service = FootballCatalogStub(responses: [[], [fixture]])
        let store = FootballStore(api: service)

        await store.load(section: .live)
        #expect(store.matches.isEmpty)

        await store.load(section: .live)
        let calls = await service.callCount
        #expect(calls == 2)
        #expect(store.matches.map(\.id) == [fixture.id])
    }

    @Test @MainActor func animeScheduleExcludesPassedEntriesAndEmptyDays() async {
        let passed = Self.animeScheduleEntry("passed", passed: true)
        let upcoming = Self.animeScheduleEntry("upcoming", passed: false)
        let service = AnimeCatalogStub(
            pages: [:],
            scheduleDays: [
                AnimeScheduleDay(label: "Today", entries: [passed, upcoming]),
                AnimeScheduleDay(label: "Yesterday", entries: [passed]),
            ]
        )
        let store = AnimeStore(api: service)

        await store.loadSchedule()

        #expect(store.scheduleDays.map(\.label) == ["Today"])
        #expect(store.scheduleDays.first?.entries.map(\.slug) == ["upcoming"])
    }

    @Test @MainActor func footballScheduleExcludesFixturesBeforeNow() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let past = Self.footballMatch("past", kickoff: now.addingTimeInterval(-1))
        let startingNow = Self.footballMatch("now", kickoff: now)
        let future = Self.footballMatch("future", kickoff: now.addingTimeInterval(1))
        let service = FootballCatalogStub(responses: [[past, future, startingNow]])
        let store = FootballStore(api: service, now: { now })

        await store.load(section: .schedule)

        #expect(store.matches.map(\.id) == [startingNow.id, future.id])
    }

    private static func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func successResponse(for request: URLRequest) -> HTTPURLResponse {
        response(for: request, statusCode: 200)
    }

    private static func response(for request: URLRequest, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    private static func novelPage(ids: [String], total: Int) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "data": ids.map { ["_id": $0, "title": "Title \($0)"] },
                "meta": ["total": total],
            ]
        )
    }

    private static func chapterEnvelope(
        id: String,
        number: Int,
        title: String,
        content: String
    ) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "data": [
                    "_id": id,
                    "chapterNumber": number,
                    "title": title,
                    "content": content,
                ]
            ]
        )
    }

    private static func chapterPage(numbers: [Int], total: Int, offset: Int) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "data": numbers.map {
                    [
                        "_id": "chapter-\($0)",
                        "chapterNumber": $0,
                        "title": "Chapter \($0)",
                    ] as [String: Any]
                },
                "meta": [
                    "total": total,
                    "count": numbers.count,
                    "limit": 100,
                    "offset": offset,
                ],
            ]
        )
    }

    private static func animeTitle(_ id: String) -> AnimeTitle {
        AnimeTitle(
            slug: id,
            title: "Title \(id)",
            japaneseTitle: nil,
            imageURL: nil,
            type: "TV",
            episodeLabel: nil
        )
    }

    private static func animeShow(_ id: String) -> AnimeShow {
        AnimeShow(
            id: id,
            title: "Downloaded \(id)",
            japaneseTitle: nil,
            imageURL: nil,
            description: "Saved synopsis",
            type: "TV",
            status: "Finished Airing",
            genres: ["action"],
            episodesCount: 3,
            subEpisodes: 3,
            dubEpisodes: 0,
            season: "Spring 2026",
            studio: "Asterion",
            dateAired: nil,
            malScore: nil,
            slug: id
        )
    }

    private static func animeScheduleEntry(_ id: String, passed: Bool) -> AnimeScheduleEntry {
        AnimeScheduleEntry(
            slug: id,
            title: "Title \(id)",
            japaneseTitle: nil,
            time: "12:00",
            episodeNumber: 1,
            passed: passed
        )
    }

    private static func movieTitle(_ id: String) -> MovieTitle {
        MovieTitle(
            id: id,
            slug: id,
            title: "Title \(id)",
            imageURL: nil,
            imdbRating: nil,
            runtime: nil,
            year: nil,
            type: "movie",
            quality: nil
        )
    }

    private static func movieShow(_ id: String, type: String) -> MovieShow {
        MovieShow(
            slug: id,
            title: "Downloaded \(id)",
            type: type,
            imageURL: nil,
            description: "Saved synopsis",
            imdbRating: "8.0",
            tmdbRating: nil,
            rottenTomatoes: nil,
            metacritic: nil,
            genres: ["Drama"],
            director: nil,
            actors: [],
            duration: "24m",
            releaseYear: "2026",
            releaseDate: nil,
            country: nil,
            seasons: type == "tv" ? ["1"] : [],
            streams: []
        )
    }

    private static func mediaDownload(
        animeShow: AnimeShow,
        episode: AnimeEpisode
    ) -> MediaDownloadRecord {
        MediaDownloadRecord(
            id: "anime:\(animeShow.slug):\(episode.id)",
            mediaType: .anime,
            contentID: animeShow.slug,
            contentTitle: animeShow.title,
            unitID: episode.id,
            unitTitle: "Episode \(episode.number)",
            imageURL: animeShow.imageURL,
            animeShow: animeShow,
            animeEpisode: episode,
            movieShow: nil,
            movieEpisode: nil,
            downloadQuality: .p720,
            phase: .completed,
            progress: 1,
            localAssetURL: URL(fileURLWithPath: "/tmp/\(episode.id).movpkg"),
            subtitleTracks: [],
            errorMessage: nil,
            updatedAt: .now
        )
    }

    private static func mediaDownload(
        movieShow: MovieShow,
        episode: MovieEpisode?
    ) -> MediaDownloadRecord {
        let unitID = episode?.id ?? movieShow.slug
        return MediaDownloadRecord(
            id: "movie:\(movieShow.slug):\(unitID)",
            mediaType: .movie,
            contentID: movieShow.slug,
            contentTitle: movieShow.title,
            unitID: unitID,
            unitTitle: episode?.title ?? movieShow.title,
            imageURL: movieShow.imageURL,
            animeShow: nil,
            animeEpisode: nil,
            movieShow: movieShow,
            movieEpisode: episode,
            downloadQuality: .p720,
            phase: .completed,
            progress: 1,
            localAssetURL: URL(fileURLWithPath: "/tmp/\(unitID).movpkg"),
            subtitleTracks: [],
            errorMessage: nil,
            updatedAt: .now
        )
    }

    private static func footballMatch(
        _ id: String,
        kickoff: Date = Date(timeIntervalSince1970: 1_784_330_000)
    ) -> FootballMatch {
        FootballMatch(
            id: id,
            title: "Home vs Away",
            category: "football",
            kickoff: kickoff,
            poster: nil,
            posterURL: nil,
            popular: false,
            isLive: true,
            teams: nil,
            sources: [FootballStreamSource(source: "echo", id: id)]
        )
    }

    private static func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool
    ) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw CatalogTestError.timedOut
    }
}

private enum CatalogTestError: Error {
    case timedOut
    case offline
}

private final class CatalogDateBox: @unchecked Sendable {
    var now = Date()
}

private final class CatalogRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}

private final class CatalogURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?

    static func install(_ handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private actor AnimeCatalogStub: AnimeCatalogServing {
    let pages: [Int: [AnimeTitle]]
    let scheduleDays: [AnimeScheduleDay]
    let genres: [String]
    let suspendFirstRequest: Bool
    let failsCatalog: Bool
    let failsDetail: Bool
    private(set) var latestCallCount = 0
    private(set) var genreCallCount = 0
    private var failSeasonAndReleases = false
    private var cancelSeasonAndReleases = false

    init(
        pages: [Int: [AnimeTitle]],
        scheduleDays: [AnimeScheduleDay] = [],
        genres: [String] = [],
        suspendFirstRequest: Bool = false,
        failsCatalog: Bool = false,
        failsDetail: Bool = false
    ) {
        self.pages = pages
        self.scheduleDays = scheduleDays
        self.genres = genres
        self.suspendFirstRequest = suspendFirstRequest
        self.failsCatalog = failsCatalog
        self.failsDetail = failsDetail
    }

    func failNextSeasonAndReleases() {
        failSeasonAndReleases = true
    }

    func cancelNextSeasonAndReleases() {
        cancelSeasonAndReleases = true
    }

    func fetchLatest(page: Int) async throws -> [AnimeTitle] {
        latestCallCount += 1
        if failsCatalog { throw CatalogTestError.offline }
        if suspendFirstRequest, latestCallCount == 1 {
            try await Task.sleep(for: .seconds(30))
        }
        return pages[page] ?? []
    }

    func fetchPopular(page: Int) async throws -> [AnimeTitle] { pages[page] ?? [] }
    func fetchNewReleases(page: Int) async throws -> [AnimeTitle] {
        if cancelSeasonAndReleases { throw CancellationError() }
        if failSeasonAndReleases { throw CatalogTestError.offline }
        return pages[page] ?? []
    }
    func fetchGenre(_ genre: String, page: Int) async throws -> [AnimeTitle] { pages[page] ?? [] }
    func fetchSeason(season: String, year: Int, page: Int) async throws -> [AnimeTitle] {
        if cancelSeasonAndReleases { throw CancellationError() }
        if failSeasonAndReleases { throw CatalogTestError.offline }
        return pages[page] ?? []
    }
    func fetchType(_ type: String, page: Int) async throws -> [AnimeTitle] { pages[page] ?? [] }
    func fetchStatus(_ status: String, page: Int) async throws -> [AnimeTitle] { pages[page] ?? [] }
    func fetchSchedule(timeZoneHours: Double) async throws -> [AnimeScheduleDay] { scheduleDays }
    func fetchGenres() async throws -> [String] {
        genreCallCount += 1
        return genres
    }
    func search(query: String, page: Int) async throws -> [AnimeTitle] { pages[page] ?? [] }

    func fetchShow(slug: String) async throws -> AnimeShow {
        if failsDetail { throw CatalogTestError.offline }
        return AnimeShow(
            id: slug,
            title: slug,
            japaneseTitle: nil,
            imageURL: nil,
            description: nil,
            type: "TV",
            status: nil,
            genres: [],
            episodesCount: 0,
            subEpisodes: 0,
            dubEpisodes: 0,
            season: nil,
            studio: nil,
            dateAired: nil,
            malScore: nil,
            slug: slug
        )
    }

    func fetchEpisodes(showID: String) async throws -> [AnimeEpisode] { [] }
    func fetchRelatedSeasons(showID: String) async throws -> [AnimeRelatedSeason] { [] }
}

private actor MovieCatalogStub: MovieCatalogServing {
    let pages: [Int: MovieCatalogPage]
    let genres: [MovieGenre]
    let suspendFirstRequest: Bool
    let failsCatalog: Bool
    let failsDetail: Bool
    private(set) var movieCallCount = 0
    private(set) var genreCallCount = 0

    init(
        pages: [Int: MovieCatalogPage],
        genres: [MovieGenre] = [],
        suspendFirstRequest: Bool = false,
        failsCatalog: Bool = false,
        failsDetail: Bool = false
    ) {
        self.pages = pages
        self.genres = genres
        self.suspendFirstRequest = suspendFirstRequest
        self.failsCatalog = failsCatalog
        self.failsDetail = failsDetail
    }

    func fetchMovies(page: Int) async throws -> MovieCatalogPage {
        movieCallCount += 1
        if failsCatalog { throw CatalogTestError.offline }
        if suspendFirstRequest, movieCallCount == 1 {
            try await Task.sleep(for: .seconds(30))
        }
        return pages[page] ?? MovieCatalogPage(page: page, totalPages: page, results: [])
    }

    func fetchTV(page: Int) async throws -> MovieCatalogPage {
        if failsCatalog { throw CatalogTestError.offline }
        return pages[page] ?? MovieCatalogPage(page: page, totalPages: page, results: [])
    }

    func fetchTrendingMovies() async throws -> [MovieTitle] { [] }
    func fetchPopularMovies() async throws -> [MovieTitle] { [] }
    func fetchGenre(_ slug: String, page: Int) async throws -> [MovieTitle] { [] }
    func fetchGenres() async throws -> [MovieGenre] {
        genreCallCount += 1
        return genres
    }
    func search(query: String) async throws -> [MovieTitle] { [] }

    func fetchShow(slug: String) async throws -> MovieShow {
        if failsDetail { throw CatalogTestError.offline }
        return MovieShow(
            slug: slug,
            title: slug,
            type: "movie",
            imageURL: nil,
            description: nil,
            imdbRating: nil,
            tmdbRating: nil,
            rottenTomatoes: nil,
            metacritic: nil,
            genres: [],
            director: nil,
            actors: [],
            duration: nil,
            releaseYear: nil,
            releaseDate: nil,
            country: nil,
            seasons: [],
            streams: []
        )
    }

    func fetchEpisodes(slug: String) async throws -> [MovieEpisode] { [] }
}

private actor FootballCatalogStub: FootballCatalogServing {
    let suspendFirstRequest: Bool
    let responses: [[FootballMatch]]
    private(set) var callCount = 0

    init(suspendFirstRequest: Bool = false, responses: [[FootballMatch]] = [[]]) {
        self.suspendFirstRequest = suspendFirstRequest
        self.responses = responses
    }

    func fetchMatches(section: FootballSection) async throws -> [FootballMatch] {
        callCount += 1
        if suspendFirstRequest, callCount == 1 {
            try await Task.sleep(for: .seconds(30))
        }
        return responses[min(callCount - 1, responses.count - 1)]
    }
}
