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
    private struct ErrorEnvelope: Decodable {
        let error: String?
    }

    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = URL(string: "https://asterion-movies.cyberverse.cloud")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchMovies(page: Int) async throws -> MovieCatalogPage {
        try await request(path: "/api/movies", query: pageQuery(page))
    }

    func fetchTV(page: Int) async throws -> MovieCatalogPage {
        try await request(path: "/api/tv", query: pageQuery(page))
    }

    func fetchTrendingMovies() async throws -> [MovieTitle] {
        try await request(path: "/api/trending/movies")
    }

    func fetchPopularMovies() async throws -> [MovieTitle] {
        try await request(path: "/api/popular/movies")
    }

    func fetchGenre(_ slug: String, page: Int) async throws -> [MovieTitle] {
        try await request(path: "/api/genre/\(slug)", query: pageQuery(page))
    }

    func fetchGenres() async throws -> [MovieGenre] {
        try await request(path: "/api/genres")
    }

    func search(query: String) async throws -> [MovieTitle] {
        try await request(
            path: "/api/search",
            query: [URLQueryItem(name: "q", value: query)]
        )
    }

    func fetchShow(slug: String) async throws -> MovieShow {
        let show: MovieShow = try await request(path: "/api/show/\(slug)")
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
        try await request(path: "/api/show/\(slug)/episodes")
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
            proxyURL: source.proxyURL.map { Self.serviceURL($0, relativeTo: baseURL) }
        )
    }

    private func pageQuery(_ page: Int) -> [URLQueryItem] {
        [URLQueryItem(name: "page", value: String(page))]
    }

    private func request<Response: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem] = []
    ) async throws -> Response {
        var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw MovieAPIError.invalidResponse
        }
        guard 200..<300 ~= response.statusCode else {
            let envelope = try? Self.decoder.decode(ErrorEnvelope.self, from: data)
            throw MovieAPIError.http(
                statusCode: response.statusCode,
                message: envelope?.error ?? ""
            )
        }

        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw MovieAPIError.invalidPayload
        }
    }

    private static let decoder = JSONDecoder()
}
