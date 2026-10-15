import Foundation

nonisolated enum EntertainmentAPIError: LocalizedError {
    case invalidResponse
    case http(Int)
    case noPlaybackSource

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Asterion received an invalid response."
        case .http(let status):
            "The content service returned HTTP \(status)."
        case .noPlaybackSource:
            "No playable source is available right now."
        }
    }
}

actor EntertainmentAPI {
    static let shared = EntertainmentAPI()

    private let animeBaseURL = URL(string: "https://asterion-scraper.cyberverse.cloud")!
    private let movieBaseURL = URL(string: "https://asterion-movies.cyberverse.cloud")!
    private let footballBaseURL = URL(string: "https://asterion-football.cyberverse.cloud")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchAnime(query: String = "") async throws -> [AnimeTitle] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return try await request(
                baseURL: animeBaseURL,
                path: "/api/amp/latest",
                query: [URLQueryItem(name: "page", value: "1")]
            )
        }
        return try await request(
            baseURL: animeBaseURL,
            path: "/api/amp/search",
            query: [
                URLQueryItem(name: "q", value: normalized),
                URLQueryItem(name: "page", value: "1"),
            ]
        )
    }

    func fetchPopularAnime() async throws -> [AnimeTitle] {
        try await fetchAnimePath("/api/amp/popular")
    }

    func fetchAnimeReleases() async throws -> [AnimeTitle] {
        try await fetchAnimePath("/api/amp/releases")
    }

    func fetchAnimeStatus(_ status: String) async throws -> [AnimeTitle] {
        try await fetchAnimePath("/api/amp/status/\(status)")
    }

    func fetchAnimeType(_ type: String) async throws -> [AnimeTitle] {
        try await fetchAnimePath("/api/amp/type/\(type)")
    }

    func fetchAnimeGenre(_ genre: String) async throws -> [AnimeTitle] {
        try await fetchAnimePath("/api/amp/genre/\(genre)")
    }

    func fetchAnimeGenres() async throws -> [String] {
        try await request(baseURL: animeBaseURL, path: "/api/amp/genres")
    }

    func fetchAnimeSchedule() async throws -> [AnimeTitle] {
        let offset = Double(TimeZone.current.secondsFromGMT()) / 3600
        let days: [AnimeScheduleDay] = try await request(
            baseURL: animeBaseURL,
            path: "/api/amp/schedule",
            query: [URLQueryItem(name: "tz", value: String(offset))]
        )
        return days.flatMap { day in
            day.entries.map { entry in
                AnimeTitle(
                    slug: entry.slug,
                    title: entry.title,
                    japaneseTitle: entry.japaneseTitle,
                    imageURL: nil,
                    type: day.label,
                    episodeLabel: entry.time
                )
            }
        }
    }

    private func fetchAnimePath(_ path: String) async throws -> [AnimeTitle] {
        try await request(
            baseURL: animeBaseURL,
            path: path,
            query: [URLQueryItem(name: "page", value: "1")]
        )
    }

    func fetchAnimeShow(slug: String) async throws -> AnimeShow {
        try await request(baseURL: animeBaseURL, path: "/api/amp/show/\(slug)")
    }

    func fetchAnimeEpisodes(showID: String) async throws -> [AnimeEpisode] {
        try await request(baseURL: animeBaseURL, path: "/api/amp/episodes/\(showID)")
    }

    func fetchAnimePlayback(
        animeID: String,
        episodeNumber: Int,
        title: String,
        item: MediaItemDescriptor? = nil
    ) async throws -> PlaybackRequest {
        let sources: [AnimeStreamSource] = try await request(
            baseURL: animeBaseURL,
            path: "/api/amp/stream/\(animeID)/\(episodeNumber)",
            timeout: 25,
            retries: 2,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        let options = animePlaybackOptions(from: sources)
        guard let preferred = preferredAnimeOption(from: options) else {
            throw EntertainmentAPIError.noPlaybackSource
        }
        return PlaybackRequest(
            id: "anime-\(animeID)-\(episodeNumber)",
            title: title,
            directURL: preferred.kind == .direct ? preferred.url : nil,
            embedURL: preferred.kind == .embed ? preferred.url : options.first { $0.kind == .embed }?.url,
            requestHeaders: preferred.requestHeaders,
            playback: item.map {
                MediaPlaybackDescriptor(
                    item: $0,
                    unitID: "\(animeID)-\(episodeNumber)",
                    unitTitle: "Episode \(episodeNumber)",
                    seasonNumber: nil,
                    episodeNumber: episodeNumber
                )
            },
            subtitleTracks: preferred.subtitleTracks,
            options: options,
            selectedOptionID: preferred.id
        )
    }

    func fetchMovies(kind: MovieCatalogKind, query: String = "") async throws -> [MovieTitle] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.isEmpty {
            return try await request(
                baseURL: movieBaseURL,
                path: "/api/search",
                query: [URLQueryItem(name: "q", value: normalized)]
            )
        }
        let page: MovieCatalogPage = try await request(
            baseURL: movieBaseURL,
            path: kind == .movies ? "/api/movies" : "/api/tv",
            query: [URLQueryItem(name: "page", value: "1")]
        )
        return page.results
    }

    func fetchTrendingMovies() async throws -> [MovieTitle] {
        try await request(baseURL: movieBaseURL, path: "/api/trending/movies")
    }

    func fetchPopularMovies() async throws -> [MovieTitle] {
        try await request(baseURL: movieBaseURL, path: "/api/popular/movies")
    }

    func fetchMovieGenres() async throws -> [MovieGenre] {
        try await request(baseURL: movieBaseURL, path: "/api/genres")
    }

    func fetchMovies(genreSlug: String) async throws -> [MovieTitle] {
        try await request(
            baseURL: movieBaseURL,
            path: "/api/genre/\(genreSlug)",
            query: [URLQueryItem(name: "page", value: "1")]
        )
    }

    func fetchMovieShow(slug: String) async throws -> MovieShow {
        try await request(baseURL: movieBaseURL, path: "/api/show/\(slug)")
    }

    func fetchMovieEpisodes(slug: String) async throws -> [MovieEpisode] {
        try await request(baseURL: movieBaseURL, path: "/api/show/\(slug)/episodes")
    }

    func fetchMoviePlayback(
        slug: String,
        title: String,
        item: MediaItemDescriptor? = nil,
        unitTitle: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil
    ) async throws -> PlaybackRequest {
        let response: MoviePlaybackSources = try await request(
            baseURL: movieBaseURL,
            path: "/api/playback/\(slug)",
            timeout: 25,
            retries: 2,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        let options = moviePlaybackOptions(from: response.sources)
        let prefersSeriesServer = seasonNumber != nil || episodeNumber != nil
        guard let preferred = preferredMovieOption(
            from: options,
            sources: response.sources,
            prefersSeriesServer: prefersSeriesServer
        ) else {
            throw EntertainmentAPIError.noPlaybackSource
        }
        return PlaybackRequest(
            id: "movie-\(slug)",
            title: title,
            directURL: preferred.kind == .direct ? preferred.url : nil,
            embedURL: preferred.kind == .embed ? preferred.url : options.first { $0.kind == .embed }?.url,
            requestHeaders: preferred.requestHeaders,
            playback: item.map {
                MediaPlaybackDescriptor(
                    item: $0,
                    unitID: slug,
                    unitTitle: unitTitle,
                    seasonNumber: seasonNumber,
                    episodeNumber: episodeNumber
                )
            },
            subtitleTracks: preferred.subtitleTracks,
            options: options,
            selectedOptionID: preferred.id
        )
    }

    func fetchFootball(section: FootballCatalogSection) async throws -> [FootballMatch] {
        let path = switch section {
        case .live: "/api/matches/live"
        case .schedule: "/api/matches"
        case .popular: "/api/matches/popular"
        }
        let response: FootballEnvelope<[FootballMatch]> = try await request(
            baseURL: footballBaseURL,
            path: path
        )
        let now = Date()
        return response.data
            .filter { section != .schedule || $0.kickoff >= now }
            .sorted { $0.kickoff < $1.kickoff }
    }

    func fetchPlayback(for source: PlaybackSource) async throws -> PlaybackRequest {
        switch source {
        case .anime(let animeID, let episodeNumber, let title, let item):
            try await fetchAnimePlayback(
                animeID: animeID,
                episodeNumber: episodeNumber,
                title: title,
                item: item
            )
        case .movie(let slug, let title, let item, let unitTitle, let seasonNumber, let episodeNumber):
            try await fetchMoviePlayback(
                slug: slug,
                title: title,
                item: item,
                unitTitle: unitTitle,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber
            )
        }
    }

    func fetchFootballPlayback(match: FootballMatch) async throws -> PlaybackRequest {
        struct StreamRequest: Encodable {
            let matchId: String
            let sources: [FootballStreamSource]
            let homeTeam: String?
            let awayTeam: String?
        }

        let body = StreamRequest(
            matchId: match.id,
            sources: match.sources,
            homeTeam: match.teams?.home?.name,
            awayTeam: match.teams?.away?.name
        )
        let encodedBody = try JSONEncoder().encode(body)
        let response: FootballEnvelope<FootballStreamCollection> = try await request(
            baseURL: footballBaseURL,
            path: "/api/streams",
            method: "POST",
            body: encodedBody,
            timeout: 25,
            retries: 2,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        let streams = response.data.streams.sorted(by: Self.preferredFootballOrder)
        let options = footballPlaybackOptions(from: streams)
        guard let preferred = options.first else {
            throw EntertainmentAPIError.noPlaybackSource
        }
        return PlaybackRequest(
            id: "football-\(match.id)",
            title: match.displayTitle,
            directURL: nil,
            embedURL: preferred.url,
            requestHeaders: [:],
            playback: nil,
            options: options,
            selectedOptionID: preferred.id
        )
    }

    private func animePlaybackOptions(from sources: [AnimeStreamSource]) -> [PlaybackOption] {
        sources.enumerated().flatMap { index, source in
            let embedURL = resolved(source.embedURL, relativeTo: animeBaseURL)
            let sourceID = source.server.isEmpty ? String(index) : source.server
            let variant = AnimePlaybackVariant(streamURL: source.embedURL)?.title
            let tracks = source.tracks.map { track in
                AnimeSubtitleTrack(
                    fileURL: resolved(track.fileURL, relativeTo: animeBaseURL),
                    label: track.label,
                    kind: track.kind,
                    languageCode: track.languageCode,
                    isDefault: track.isDefault
                )
            }
            var options: [PlaybackOption] = []
            if let directURL = source.directURL {
                options.append(
                    PlaybackOption(
                        id: "direct-\(sourceID)-\(index)",
                        kind: .direct,
                        title: animeOptionTitle(
                            server: source.server,
                            variant: variant,
                            format: "Direct",
                            quality: source.quality
                        ),
                        url: proxiedAnimeURL(resolved(directURL, relativeTo: animeBaseURL)),
                        requestHeaders: playbackHeaders(for: embedURL),
                        subtitleTracks: tracks
                    )
                )
            }
            options.append(
                PlaybackOption(
                    id: "embed-\(sourceID)-\(index)",
                    kind: .embed,
                    title: animeOptionTitle(
                        server: source.server,
                        variant: variant,
                        format: "Web",
                        quality: source.quality
                    ),
                    url: embedURL,
                    requestHeaders: [:],
                    subtitleTracks: []
                )
            )
            return options
        }
    }

    private func animeOptionTitle(
        server: String,
        variant: String?,
        format: String,
        quality: String?
    ) -> String {
        ([server, variant, format, quality]
            .compactMap { $0 }
            .filter { !$0.isEmpty })
            .joined(separator: " · ")
    }

    private func preferredAnimeOption(from options: [PlaybackOption]) -> PlaybackOption? {
        options.first { $0.kind == .direct && !$0.subtitleTracks.isEmpty }
            ?? options.first { $0.kind == .direct }
            ?? options.first
    }

    private func moviePlaybackOptions(from sources: [MovieStreamSource]) -> [PlaybackOption] {
        sources.map { source in
            let kind: PlaybackOption.Kind = source.isHLS ? .direct : .embed
            let quality = kind == .embed && source.quality == "Direct Player"
                ? "Web Player"
                : source.quality
            let embedURL = resolved(source.embedURL, relativeTo: movieBaseURL)
            return PlaybackOption(
                id: [
                    kind.rawValue,
                    source.label.lowercased(),
                    source.embedURL.host?.lowercased() ?? String(source.serverID),
                ].joined(separator: "-"),
                kind: kind,
                title: [source.label, quality]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "),
                url: source.isHLS
                    ? resolved(source.proxyURL ?? source.embedURL, relativeTo: movieBaseURL)
                    : embedURL,
                requestHeaders: playbackHeaders(for: embedURL),
                subtitleTracks: []
            )
        }
    }

    private func preferredMovieOption(
        from options: [PlaybackOption],
        sources: [MovieStreamSource],
        prefersSeriesServer: Bool
    ) -> PlaybackOption? {
        guard !options.isEmpty else { return nil }
        if prefersSeriesServer,
           let index = sources.firstIndex(where: Self.isPreferredSeriesServer),
           options.indices.contains(index) {
            return options[index]
        }
        if let index = sources.firstIndex(where: { $0.isHLS && $0.isVerified }),
           options.indices.contains(index) {
            return options[index]
        }
        if let index = sources.firstIndex(where: \.isHLS),
           options.indices.contains(index) {
            return options[index]
        }
        return options.first
    }

    private func footballPlaybackOptions(from streams: [FootballStream]) -> [PlaybackOption] {
        streams.map { stream in
            PlaybackOption(
                id: stream.optionID,
                kind: .embed,
                title: stream.displayName,
                url: resolved(stream.embedURL, relativeTo: footballBaseURL),
                requestHeaders: [:],
                subtitleTracks: []
            )
        }
    }

    private static func preferredFootballOrder(_ left: FootballStream, _ right: FootballStream) -> Bool {
        if left.hd != right.hd { return left.hd }
        let leftIsEnglish = left.language.localizedCaseInsensitiveCompare("English") == .orderedSame
        let rightIsEnglish = right.language.localizedCaseInsensitiveCompare("English") == .orderedSame
        if leftIsEnglish != rightIsEnglish { return leftIsEnglish }
        return (left.viewers ?? 0) > (right.viewers ?? 0)
    }

    private static func isPreferredSeriesServer(_ source: MovieStreamSource) -> Bool {
        source.label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare("Server 4") == .orderedSame
    }

    private func request<Response: Decodable & Sendable>(
        baseURL: URL,
        path: String,
        query: [URLQueryItem] = [],
        method: String = "GET",
        body: Data? = nil,
        timeout: TimeInterval = 60,
        retries: Int = 3,
        cachePolicy: URLRequest.CachePolicy = .returnCacheDataElseLoad
    ) async throws -> Response {
        var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.timeoutInterval = timeout
        request.cachePolicy = cachePolicy

        var lastError: Error?
        let attempts = max(1, retries)
        for attempt in 0..<attempts {
            do {
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else {
                    throw EntertainmentAPIError.invalidResponse
                }
                guard 200..<300 ~= response.statusCode else {
                    throw EntertainmentAPIError.http(response.statusCode)
                }
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                lastError = error
                guard attempt < attempts - 1 else { break }
                try await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
            }
        }
        throw lastError ?? EntertainmentAPIError.invalidResponse
    }

    private func resolved(_ url: URL, relativeTo baseURL: URL) -> URL {
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return url
        }
        let raw = url.relativeString.isEmpty ? url.path : url.relativeString
        return URL(string: raw, relativeTo: baseURL)?.absoluteURL ?? url
    }

    private func proxiedAnimeURL(_ url: URL) -> URL {
        guard url.host?.lowercased() != animeBaseURL.host?.lowercased()
                || url.path != "/proxy/m3u8" else {
            return url
        }
        var components = URLComponents(
            url: animeBaseURL.appending(path: "/proxy/m3u8"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        return components?.url ?? url
    }

    private func playbackHeaders(for embedURL: URL) -> [String: String] {
        guard let scheme = embedURL.scheme, let host = embedURL.host else {
            return ["User-Agent": "Mozilla/5.0"]
        }
        var origin = "\(scheme)://\(host)"
        if let port = embedURL.port { origin += ":\(port)" }
        return [
            "Referer": "\(origin)/",
            "Origin": origin,
            "User-Agent": "Mozilla/5.0",
        ]
    }
}

nonisolated enum MovieCatalogKind: String, CaseIterable, Hashable, Sendable {
    case movies = "Movies"
    case tv = "TV Shows"
}

nonisolated enum MovieBrowseSection: String, CaseIterable, Hashable, Sendable {
    case discover = "Discover"
    case movies = "Movies"
    case tvShows = "TV Shows"
    case popular = "Popular"
    case genres = "Genres"
}

nonisolated enum AnimeBrowseSection: String, CaseIterable, Hashable, Sendable {
    case discover = "Discover"
    case updated = "Updated"
    case added = "Added"
    case popular = "Popular"
    case airing = "Airing"
    case upcoming = "Upcoming"
    case completed = "Completed"
    case schedule = "Schedule"
    case genres = "Genres"
    case types = "Types"
}
