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

    func fetchLatest(page: Int) async throws -> [AnimeTitle] {
        try await request(
            path: "/api/amp/latest",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
    }

    func fetchPopular(page: Int) async throws -> [AnimeTitle] {
        try await request(
            path: "/api/amp/popular",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
    }

    func fetchNewReleases(page: Int) async throws -> [AnimeTitle] {
        try await request(
            path: "/api/amp/releases",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
    }

    func fetchGenre(_ genre: String, page: Int) async throws -> [AnimeTitle] {
        try await request(
            path: "/api/amp/genre/\(genre)",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
    }

    func fetchSeason(season: String, year: Int, page: Int) async throws -> [AnimeTitle] {
        try await request(
            path: "/api/amp/season",
            query: [
                URLQueryItem(name: "season", value: season),
                URLQueryItem(name: "year", value: String(year)),
                URLQueryItem(name: "page", value: String(page)),
            ]
        )
    }

    func fetchType(_ type: String, page: Int) async throws -> [AnimeTitle] {
        try await request(
            path: "/api/amp/type/\(type)",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
    }

    func fetchStatus(_ status: String, page: Int) async throws -> [AnimeTitle] {
        try await request(
            path: "/api/amp/status/\(status)",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
    }

    func fetchSchedule(timeZoneHours: Double) async throws -> [AnimeScheduleDay] {
        try await request(
            path: "/api/amp/schedule",
            query: [URLQueryItem(name: "tz", value: String(timeZoneHours))]
        )
    }

    func fetchGenres() async throws -> [String] {
        try await request(path: "/api/amp/genres")
    }

    func search(query: String, page: Int) async throws -> [AnimeTitle] {
        try await request(
            path: "/api/amp/search",
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "page", value: String(page)),
            ]
        )
    }

    func fetchShow(slug: String) async throws -> AnimeShow {
        try await request(path: "/api/amp/show/\(slug)")
    }

    func fetchEpisodes(showID: String) async throws -> [AnimeEpisode] {
        try await request(path: "/api/amp/episodes/\(showID)")
    }

    func fetchStream(animeID: String, episodeNumber: Int) async throws -> [AnimeStreamSource] {
        let sources: [AnimeStreamSource] = try await request(
            path: "/api/amp/stream/\(animeID)/\(episodeNumber)"
        )
        return sources.map { source in
            let hasDefaultTrack = source.tracks.contains(where: \.isDefault)
            return AnimeStreamSource(
                server: source.server,
                embedURL: Self.serviceURL(source.embedURL, relativeTo: baseURL),
                quality: source.quality,
                directURL: source.directURL.map {
                    Self.playableDirectURL($0, relativeTo: baseURL)
                },
                tracks: source.tracks.enumerated().map { index, track in
                    AnimeSubtitleTrack(
                        fileURL: Self.serviceURL(track.fileURL, relativeTo: baseURL),
                        label: track.label,
                        kind: track.kind,
                        languageCode: track.languageCode,
                        isDefault: track.isDefault || (!hasDefaultTrack && index == 0)
                    )
                }
            )
        }
    }

    static func serviceURL(_ url: URL, relativeTo baseURL: URL) -> URL {
        guard !url.relativeString.isEmpty else { return url }
        guard url.scheme == nil else { return url }
        return URL(string: url.relativeString, relativeTo: baseURL)?.absoluteURL ?? url
    }

    static func playableDirectURL(_ url: URL, relativeTo baseURL: URL) -> URL {
        let resolvedURL = serviceURL(url, relativeTo: baseURL)
        guard resolvedURL.host?.lowercased() != baseURL.host?.lowercased()
                || resolvedURL.path != "/proxy/m3u8" else {
            return resolvedURL
        }

        var components = URLComponents(
            url: baseURL.appending(path: "/proxy/m3u8"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "url", value: resolvedURL.absoluteString),
        ]
        return components?.url ?? resolvedURL
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
