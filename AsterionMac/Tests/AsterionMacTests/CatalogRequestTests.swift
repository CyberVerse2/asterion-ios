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

        await store.loadCatalog(section: .discover, query: "")
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

        await store.loadCatalog(section: .movies, query: "")
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

    private static func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func successResponse(for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
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

    private static func footballMatch(_ id: String) -> FootballMatch {
        FootballMatch(
            id: id,
            title: "Home vs Away",
            category: "football",
            kickoff: Date(timeIntervalSince1970: 1_784_330_000),
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
    let suspendFirstRequest: Bool
    private(set) var latestCallCount = 0

    init(pages: [Int: [AnimeTitle]], suspendFirstRequest: Bool = false) {
        self.pages = pages
        self.suspendFirstRequest = suspendFirstRequest
    }

    func fetchLatest(page: Int) async throws -> [AnimeTitle] {
        latestCallCount += 1
        if suspendFirstRequest, latestCallCount == 1 {
            try await Task.sleep(for: .seconds(30))
        }
        return pages[page] ?? []
    }

    func fetchPopular(page: Int) async throws -> [AnimeTitle] { pages[page] ?? [] }
    func fetchNewReleases(page: Int) async throws -> [AnimeTitle] { pages[page] ?? [] }
    func fetchGenre(_ genre: String, page: Int) async throws -> [AnimeTitle] { pages[page] ?? [] }
    func fetchSeason(season: String, year: Int, page: Int) async throws -> [AnimeTitle] { pages[page] ?? [] }
    func fetchType(_ type: String, page: Int) async throws -> [AnimeTitle] { pages[page] ?? [] }
    func fetchStatus(_ status: String, page: Int) async throws -> [AnimeTitle] { pages[page] ?? [] }
    func fetchSchedule(timeZoneHours: Double) async throws -> [AnimeScheduleDay] { [] }
    func fetchGenres() async throws -> [String] { [] }
    func search(query: String, page: Int) async throws -> [AnimeTitle] { pages[page] ?? [] }

    func fetchShow(slug: String) async throws -> AnimeShow {
        AnimeShow(
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
}

private actor MovieCatalogStub: MovieCatalogServing {
    let pages: [Int: MovieCatalogPage]
    let suspendFirstRequest: Bool
    private(set) var movieCallCount = 0

    init(pages: [Int: MovieCatalogPage], suspendFirstRequest: Bool = false) {
        self.pages = pages
        self.suspendFirstRequest = suspendFirstRequest
    }

    func fetchMovies(page: Int) async throws -> MovieCatalogPage {
        movieCallCount += 1
        if suspendFirstRequest, movieCallCount == 1 {
            try await Task.sleep(for: .seconds(30))
        }
        return pages[page] ?? MovieCatalogPage(page: page, totalPages: page, results: [])
    }

    func fetchTV(page: Int) async throws -> MovieCatalogPage {
        pages[page] ?? MovieCatalogPage(page: page, totalPages: page, results: [])
    }

    func fetchTrendingMovies() async throws -> [MovieTitle] { [] }
    func fetchPopularMovies() async throws -> [MovieTitle] { [] }
    func fetchGenre(_ slug: String, page: Int) async throws -> [MovieTitle] { [] }
    func fetchGenres() async throws -> [MovieGenre] { [] }
    func search(query: String) async throws -> [MovieTitle] { [] }

    func fetchShow(slug: String) async throws -> MovieShow {
        MovieShow(
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
