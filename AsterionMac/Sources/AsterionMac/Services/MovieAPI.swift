import Foundation

enum MovieAPIError: LocalizedError {
    case invalidResponse
    case http(statusCode: Int, message: String)
    case invalidPayload
    case noPlaybackSource

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The movie service returned an invalid response."
        case .http(let statusCode, let message):
            message.isEmpty ? "The movie service returned HTTP \(statusCode)." : message
        case .invalidPayload:
            "The movie service returned data Asterion could not read."
        case .noPlaybackSource:
            "No playable source is available for this title."
        }
    }
}

actor MovieAPI {
    static let shared = MovieAPI()

    private struct ErrorEnvelope: Decodable {
        let error: String?
    }

    private let baseURL: URL
    private let session: URLSession
    private let responseCache: HTTPResponseCache

    private static let catalogCacheNamespace = "movie.catalog"
    private static let detailCacheNamespace = "movie.detail"

    init(
        baseURL: URL = URL(string: "https://asterion-movies.cyberverse.cloud")!,
        session: URLSession = .shared,
        responseCache: HTTPResponseCache = HTTPResponseCache()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.responseCache = responseCache
    }

    func invalidateCatalogCache() async {
        await responseCache.invalidate(namespace: Self.catalogCacheNamespace)
    }

    func fetchMovies(page: Int) async throws -> MovieCatalogPage {
        try await request(
            path: "/api/movies",
            query: pageQuery(page),
            namespace: Self.catalogCacheNamespace,
            cacheLifetime: 120
        )
    }

    func fetchTV(page: Int) async throws -> MovieCatalogPage {
        try await request(
            path: "/api/tv",
            query: pageQuery(page),
            namespace: Self.catalogCacheNamespace,
            cacheLifetime: 120
        )
    }

    func fetchTrendingMovies() async throws -> [MovieTitle] {
        try await request(
            path: "/api/trending/movies",
            namespace: Self.catalogCacheNamespace,
            cacheLifetime: 120
        )
    }

    func fetchPopularMovies() async throws -> [MovieTitle] {
        try await request(
            path: "/api/popular/movies",
            namespace: Self.catalogCacheNamespace,
            cacheLifetime: 120
        )
    }

    func fetchGenre(_ slug: String, page: Int) async throws -> [MovieTitle] {
        try await request(
            path: "/api/genre/\(slug)",
            query: pageQuery(page),
            namespace: Self.catalogCacheNamespace,
            cacheLifetime: 120
        )
    }

    func fetchGenres() async throws -> [MovieGenre] {
        try await request(
            path: "/api/genres",
            namespace: Self.catalogCacheNamespace,
            cacheLifetime: 3_600
        )
    }

    func search(query: String) async throws -> [MovieTitle] {
        try await request(
            path: "/api/search",
            query: [URLQueryItem(name: "q", value: query)],
            namespace: Self.catalogCacheNamespace,
            cacheLifetime: 120
        )
    }

    func fetchShow(slug: String) async throws -> MovieShow {
        let show: MovieShow = try await request(
            path: "/api/show/\(slug)",
            namespace: "movie.playback",
            cacheLifetime: 0
        )
        return MovieShow(
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
            streams: show.streams.map(normalize)
        )
    }

    func fetchEpisodes(slug: String) async throws -> [MovieEpisode] {
        try await request(
            path: "/api/show/\(slug)/episodes",
            namespace: Self.detailCacheNamespace,
            cacheLifetime: 900
        )
    }

    func fetchPlaybackSources(slug: String) async throws -> [MovieStreamSource] {
        let response: MoviePlaybackSources = try await request(
            path: "/api/playback/\(slug)",
            namespace: "movie.playback",
            cacheLifetime: 0
        )
        return response.sources.map(normalize)
    }

    static func serviceURL(_ url: URL, relativeTo baseURL: URL) -> URL {
        guard url.scheme == nil else { return url }
        return URL(string: url.relativeString, relativeTo: baseURL)?.absoluteURL ?? url
    }

    private func normalize(_ source: MovieStreamSource) -> MovieStreamSource {
        MovieStreamSource(
            serverID: source.serverID,
            label: source.label,
            quality: source.quality,
            embedURL: Self.serviceURL(source.embedURL, relativeTo: baseURL),
            isHLS: source.isHLS,
            isVerified: source.isVerified,
            automatic: source.automatic,
            proxyURL: source.proxyURL.map { Self.serviceURL($0, relativeTo: baseURL) }
        )
    }

    private func pageQuery(_ page: Int) -> [URLQueryItem] {
        [URLQueryItem(name: "page", value: String(page))]
    }

    private func request<Response: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem] = [],
        namespace: String,
        cacheLifetime: TimeInterval
    ) async throws -> Response {
        var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var response: CachedHTTPResponse?
        for attempt in 0..<3 {
            do {
                let candidate = try await loadResponse(
                    for: request,
                    namespace: namespace,
                    cacheLifetime: cacheLifetime
                )
                if Self.retryableStatusCodes.contains(candidate.statusCode), attempt < 2 {
                    try await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
                    continue
                }
                response = candidate
                break
            } catch let error as URLError where attempt < 2 && Self.isRetryable(error) {
                try await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
            }
        }
        guard let response else { throw MovieAPIError.invalidResponse }
        guard 200..<300 ~= response.statusCode else {
            let envelope = try? Self.decoder.decode(ErrorEnvelope.self, from: response.data)
            throw MovieAPIError.http(
                statusCode: response.statusCode,
                message: envelope?.error ?? ""
            )
        }

        do {
            return try Self.decoder.decode(Response.self, from: response.data)
        } catch {
            throw MovieAPIError.invalidPayload
        }
    }

    private func loadResponse(
        for request: URLRequest,
        namespace: String,
        cacheLifetime: TimeInterval
    ) async throws -> CachedHTTPResponse {
        if cacheLifetime > 0 {
            return try await responseCache.response(
                for: request,
                session: session,
                namespace: namespace,
                lifetime: cacheLifetime
            )
        }

        let (data, urlResponse) = try await session.data(for: request)
        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw MovieAPIError.invalidResponse
        }
        return CachedHTTPResponse(data: data, statusCode: httpResponse.statusCode)
    }

    private static let retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504]

    private static func isRetryable(_ error: URLError) -> Bool {
        ![.badURL, .unsupportedURL, .cancelled].contains(error.code)
    }

    private static let decoder = JSONDecoder()
}
