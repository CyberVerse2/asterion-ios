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
            if !message.isEmpty {
                message
            } else if [502, 503, 504].contains(statusCode) {
                "The anime service is temporarily unreachable."
            } else {
                "The anime service returned HTTP \(statusCode)."
            }
        case .invalidPayload:
            "The anime service returned data Asterion could not read."
        case .noPlaybackSource:
            "No playable source is available for this episode."
        }
    }
}

actor AnimeAPI {
    static let shared = AnimeAPI()

    private struct ErrorEnvelope: Decodable {
        let error: String?
        let message: String?
    }

    private let baseURL: URL
    private let session: URLSession
    private let responseCache: HTTPResponseCache
    private let retryDelays: [Duration]

    private static let catalogCacheNamespace = "anime.catalog"
    private static let detailCacheNamespace = "anime.detail"

    init(
        baseURL: URL = URL(string: "https://asterion-scraper.cyberverse.cloud")!,
        session: URLSession = .shared,
        responseCache: HTTPResponseCache = HTTPResponseCache(),
        retryDelays: [Duration] = [
            .seconds(1),
            .seconds(3),
            .seconds(8),
        ]
    ) {
        self.baseURL = baseURL
        self.session = session
        self.responseCache = responseCache
        self.retryDelays = retryDelays
    }

    func invalidateCatalogCache() async {
        await responseCache.invalidate(namespace: Self.catalogCacheNamespace)
    }

    func fetchLatest(page: Int) async throws -> [AnimeTitle] {
        try await request(
            path: "/api/amp/latest",
            query: [URLQueryItem(name: "page", value: String(page))],
            namespace: Self.catalogCacheNamespace,
            cacheLifetime: 120
        )
    }

    func fetchPopular(page: Int) async throws -> [AnimeTitle] {
        try await request(
            path: "/api/amp/popular",
            query: [URLQueryItem(name: "page", value: String(page))],
            namespace: Self.catalogCacheNamespace,
            cacheLifetime: 120
        )
    }

    func fetchNewReleases(page: Int) async throws -> [AnimeTitle] {
        try await request(
            path: "/api/amp/releases",
            query: [URLQueryItem(name: "page", value: String(page))],
            namespace: Self.catalogCacheNamespace,
            cacheLifetime: 120
        )
    }

    func fetchGenre(_ genre: String, page: Int) async throws -> [AnimeTitle] {
        try await request(
            path: "/api/amp/genre/\(genre)",
            query: [URLQueryItem(name: "page", value: String(page))],
            namespace: Self.catalogCacheNamespace,
            cacheLifetime: 120
        )
    }

    func fetchSeason(season: String, year: Int, page: Int) async throws -> [AnimeTitle] {
        try await request(
            path: "/api/amp/season",
            query: [
                URLQueryItem(name: "season", value: season),
                URLQueryItem(name: "year", value: String(year)),
                URLQueryItem(name: "page", value: String(page)),
            ],
            namespace: Self.catalogCacheNamespace,
            cacheLifetime: 120
        )
    }

    func fetchType(_ type: String, page: Int) async throws -> [AnimeTitle] {
        try await request(
            path: "/api/amp/type/\(type)",
            query: [URLQueryItem(name: "page", value: String(page))],
            namespace: Self.catalogCacheNamespace,
            cacheLifetime: 120
        )
    }

    func fetchStatus(_ status: String, page: Int) async throws -> [AnimeTitle] {
        try await request(
            path: "/api/amp/status/\(status)",
            query: [URLQueryItem(name: "page", value: String(page))],
            namespace: Self.catalogCacheNamespace,
            cacheLifetime: 120
        )
    }

    func fetchSchedule(timeZoneHours: Double) async throws -> [AnimeScheduleDay] {
        try await request(
            path: "/api/amp/schedule",
            query: [URLQueryItem(name: "tz", value: String(timeZoneHours))],
            namespace: Self.catalogCacheNamespace,
            cacheLifetime: 60
        )
    }

    func fetchGenres() async throws -> [String] {
        try await request(
            path: "/api/amp/genres",
            namespace: Self.catalogCacheNamespace,
            cacheLifetime: 3_600
        )
    }

    func search(query: String, page: Int) async throws -> [AnimeTitle] {
        try await request(
            path: "/api/amp/search",
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "page", value: String(page)),
            ],
            namespace: Self.catalogCacheNamespace,
            cacheLifetime: 120
        )
    }

    func fetchShow(slug: String) async throws -> AnimeShow {
        try await request(
            path: "/api/amp/show/\(slug)",
            namespace: Self.detailCacheNamespace,
            cacheLifetime: 900
        )
    }

    func fetchEpisodes(showID: String) async throws -> [AnimeEpisode] {
        try await request(
            path: "/api/amp/episodes/\(showID)",
            namespace: Self.detailCacheNamespace
        )
    }

    func fetchRelatedSeasons(showID: String) async throws -> [AnimeRelatedSeason] {
        try await request(
            path: "/api/amp/seasons/\(showID)",
            namespace: Self.detailCacheNamespace,
            cacheLifetime: 900
        )
    }

    func fetchStream(animeID: String, episodeNumber: Int) async throws -> [AnimeStreamSource] {
        let sources: [AnimeStreamSource] = try await request(
            path: "/api/amp/stream/\(animeID)/\(episodeNumber)",
            namespace: "anime.stream"
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
        query: [URLQueryItem] = [],
        namespace: String,
        cacheLifetime: TimeInterval = 0
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
        for attempt in 0...retryDelays.count {
            do {
                let candidate: CachedHTTPResponse
                if cacheLifetime > 0 {
                    candidate = try await responseCache.response(
                        for: request,
                        session: session,
                        namespace: namespace,
                        lifetime: cacheLifetime
                    )
                } else {
                    let (data, urlResponse) = try await session.data(for: request)
                    guard let httpResponse = urlResponse as? HTTPURLResponse else {
                        throw AnimeAPIError.invalidResponse
                    }
                    candidate = CachedHTTPResponse(
                        data: data,
                        statusCode: httpResponse.statusCode
                    )
                }

                if Self.retryableStatusCodes.contains(candidate.statusCode),
                   attempt < retryDelays.count {
                    try await Task.sleep(for: retryDelays[attempt])
                    continue
                }
                response = candidate
                break
            } catch let error as URLError
            where attempt < retryDelays.count && Self.isRetryable(error) {
                try await Task.sleep(for: retryDelays[attempt])
            }
        }
        guard let response else { throw AnimeAPIError.invalidResponse }
        if !(200..<300 ~= response.statusCode), cacheLifetime > 0,
           let stale = await responseCache.staleResponse(
            for: request,
            namespace: namespace
           ),
           200..<300 ~= stale.statusCode {
            do {
                return try Self.decoder.decode(Response.self, from: stale.data)
            } catch {
                throw AnimeAPIError.invalidPayload
            }
        }
        guard 200..<300 ~= response.statusCode else {
            let envelope = try? Self.decoder.decode(ErrorEnvelope.self, from: response.data)
            let rawMessage = envelope?.error ?? envelope?.message
            throw AnimeAPIError.http(
                statusCode: response.statusCode,
                message: rawMessage ?? ""
            )
        }

        do {
            return try Self.decoder.decode(Response.self, from: response.data)
        } catch {
            throw AnimeAPIError.invalidPayload
        }
    }

    private static let retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504]

    private static func isRetryable(_ error: URLError) -> Bool {
        ![.badURL, .unsupportedURL, .cancelled].contains(error.code)
    }

    private static let decoder = JSONDecoder()
}
