import Foundation

enum AnimeAPIError: LocalizedError {
    case invalidResponse
    case http(statusCode: Int, message: String)
    case invalidPayload
    case noPlaybackSource

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The anime service returned an invalid response."
        case .http(let statusCode, let message):
            message.isEmpty
                ? "The anime service returned HTTP \(statusCode)."
                : message
        case .invalidPayload:
            "The anime service returned data Asterion could not read."
        case .noPlaybackSource:
            "No playable source is available for this episode."
        }
    }
}

actor AnimeAPI {
    private struct ErrorEnvelope: Decodable {
        let error: String?
        let message: String?
    }

    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = URL(string: "https://asterion-scraper.cyberverse.cloud")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchCatalog(sort: String? = nil, genre: String? = nil, page: Int) async throws -> [AnimeTitle] {
        var query = [URLQueryItem(name: "page", value: String(page))]
        if let sort, !sort.isEmpty {
            query.append(URLQueryItem(name: "sort", value: sort))
        }
        if let genre, !genre.isEmpty {
            query.append(URLQueryItem(name: "genre", value: genre))
        }
        return try await request(path: "/api/filter", query: query)
    }

    func fetchGenres() async throws -> [String] {
        try await request(path: "/api/genres")
    }

    func search(query: String) async throws -> [AnimeTitle] {
        try await request(
            path: "/api/search",
            query: [URLQueryItem(name: "q", value: query)]
        )
    }

    func fetchShow(slug: String) async throws -> AnimeShow {
        try await request(path: "/api/show/\(slug)")
    }

    func fetchEpisodes(showID: String) async throws -> [AnimeEpisode] {
        try await request(path: "/api/episodes/\(showID)")
    }

    func fetchStream(episodeID: String) async throws -> [AnimeStreamSource] {
        let sources: [AnimeStreamSource] = try await request(path: "/api/stream/\(episodeID)")
        return sources.map { source in
            AnimeStreamSource(
                serverID: source.serverID,
                type: source.type,
                quality: source.quality,
                directURL: Self.serviceURL(source.directURL, relativeTo: baseURL),
                embedURL: Self.serviceURL(source.embedURL, relativeTo: baseURL)
            )
        }
    }

    static func serviceURL(_ url: URL?, relativeTo baseURL: URL) -> URL? {
        guard let url, !url.relativeString.isEmpty else { return nil }
        guard url.scheme == nil else { return url }
        return URL(string: url.relativeString, relativeTo: baseURL)?.absoluteURL
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
            throw AnimeAPIError.invalidResponse
        }
        guard 200..<300 ~= response.statusCode else {
            let envelope = try? Self.decoder.decode(ErrorEnvelope.self, from: data)
            let rawMessage = envelope?.error ?? envelope?.message
            throw AnimeAPIError.http(
                statusCode: response.statusCode,
                message: rawMessage ?? ""
            )
        }

        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw AnimeAPIError.invalidPayload
        }
    }

    private static let decoder = JSONDecoder()
}
