import Foundation

nonisolated struct AnimeTitle: Identifiable, Codable, Hashable, Sendable {
    let slug: String
    let title: String
    let japaneseTitle: String?
    let imageURL: URL?
    let type: String?
    let episodeLabel: String?

    var id: String { slug }

    private enum CodingKeys: String, CodingKey {
        case slug, title, type
        case japaneseTitle = "japanese_title"
        case imageURL = "image_url"
        case episodeLabel = "episode_label"
    }
}

nonisolated struct AnimeScheduleDay: Identifiable, Codable, Hashable, Sendable {
    let label: String
    let entries: [AnimeScheduleEntry]
    var id: String { label }
}

nonisolated struct AnimeScheduleEntry: Identifiable, Codable, Hashable, Sendable {
    let slug: String
    let title: String
    let japaneseTitle: String?
    let time: String
    let episodeNumber: Int?
    let passed: Bool

    var id: String { "\(slug):\(episodeNumber ?? 0):\(time)" }

    private enum CodingKeys: String, CodingKey {
        case slug, title, time, passed
        case japaneseTitle = "japanese_title"
        case episodeNumber = "episode_number"
    }
}

nonisolated struct AnimeShow: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let japaneseTitle: String?
    let imageURL: URL?
    let description: String?
    let type: String?
    let status: String?
    let genres: [String]
    let episodesCount: Int
    let subEpisodes: Int
    let dubEpisodes: Int
    let season: String?
    let studio: String?
    let dateAired: String?
    let malScore: String?
    let slug: String

    private enum CodingKeys: String, CodingKey {
        case id, title, description, type, status, genres, season, studio, slug
        case japaneseTitle = "japanese_title"
        case imageURL = "image_url"
        case episodesCount = "episodes_count"
        case subEpisodes = "sub_episodes"
        case dubEpisodes = "dub_episodes"
        case dateAired = "date_aired"
        case malScore = "mal_score"
    }
}

nonisolated struct AnimeEpisode: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let animeID: String
    let number: Int

    private enum CodingKeys: String, CodingKey {
        case id, number
        case animeID = "anime_id"
    }
}

nonisolated enum AnimePlaybackVariant: String, Hashable, Sendable {
    case subtitled = "sub"
    case hardSubtitled = "hsub"
    case dubbed = "dub"

    init?(streamURL: URL) {
        self.init(rawValue: streamURL.lastPathComponent.lowercased())
    }

    var title: String {
        switch self {
        case .subtitled: "Sub"
        case .hardSubtitled: "Hard Sub"
        case .dubbed: "Dub"
        }
    }
}

nonisolated struct AnimeStreamSource: Codable, Hashable, Sendable {
    let server: String
    let embedURL: URL
    let quality: String?
    let directURL: URL?
    let tracks: [AnimeSubtitleTrack]

    private enum CodingKeys: String, CodingKey {
        case server, quality, tracks
        case embedURL = "url"
        case directURL = "source"
    }
}

nonisolated struct AnimeSubtitleTrack: Codable, Hashable, Sendable {
    let fileURL: URL
    let label: String
    let kind: String
    let languageCode: String?
    let isDefault: Bool

    init(
        fileURL: URL,
        label: String,
        kind: String = "subtitles",
        languageCode: String? = nil,
        isDefault: Bool = false
    ) {
        self.fileURL = fileURL
        self.label = label
        self.kind = kind
        self.languageCode = languageCode
        self.isDefault = isDefault
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fileURL = try values.decode(URL.self, forKey: .fileURL)
        label = try values.decodeIfPresent(String.self, forKey: .label) ?? "Subtitles"
        kind = try values.decodeIfPresent(String.self, forKey: .kind) ?? "subtitles"
        languageCode = try values.decodeIfPresent(String.self, forKey: .languageCode)
        isDefault = try values.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case label, kind
        case fileURL = "file"
        case languageCode = "srclang"
        case isDefault = "default"
    }
}

nonisolated struct MovieTitle: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let slug: String
    let title: String
    let imageURL: URL?
    let imdbRating: String?
    let runtime: String?
    let year: String?
    let type: String?
    let quality: String?

    private enum CodingKeys: String, CodingKey {
        case id, slug, title, runtime, year, type, quality
        case imageURL = "image_url"
        case imdbRating = "imdb_rating"
    }
}

nonisolated struct MovieGenre: Identifiable, Codable, Hashable, Sendable {
    let slug: String
    let title: String
    var id: String { slug }
}

nonisolated struct MovieCatalogPage: Codable, Sendable {
    let page: Int
    let totalPages: Int
    let results: [MovieTitle]

    private enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
    }
}

nonisolated struct MovieShow: Identifiable, Codable, Hashable, Sendable {
    let slug: String
    let title: String
    let type: String
    let imageURL: URL?
    let description: String?
    let imdbRating: String?
    let genres: [String]
    let director: String?
    let actors: [String]
    let duration: String?
    let releaseYear: String?
    let seasons: [String]
    let streams: [MovieStreamSource]

    var id: String { slug }
    var isSeries: Bool { type == "tv" }

    private enum CodingKeys: String, CodingKey {
        case slug, title, type, description, genres, director, actors, duration, seasons, streams
        case imageURL = "image_url"
        case imdbRating = "imdb_rating"
        case releaseYear = "release_year"
    }
}

nonisolated struct MovieEpisode: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let season: Int
    let number: Int
    let title: String
    let url: URL
}

nonisolated struct MovieStreamSource: Codable, Hashable, Sendable {
    let serverID: Int
    let label: String
    let quality: String
    let embedURL: URL
    let isHLS: Bool
    let isVerified: Bool
    let automatic: Bool
    let proxyURL: URL?

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        serverID = try values.decode(Int.self, forKey: .serverID)
        label = try values.decode(String.self, forKey: .label)
        quality = try values.decode(String.self, forKey: .quality)
        embedURL = try values.decode(URL.self, forKey: .embedURL)
        isHLS = try values.decode(Bool.self, forKey: .isHLS)
        isVerified = try values.decodeIfPresent(Bool.self, forKey: .isVerified) ?? false
        automatic = try values.decodeIfPresent(Bool.self, forKey: .automatic) ?? false
        proxyURL = try values.decodeIfPresent(URL.self, forKey: .proxyURL)
    }

    private enum CodingKeys: String, CodingKey {
        case label, quality, automatic
        case serverID = "server_id"
        case embedURL = "embed_url"
        case isHLS = "is_hls"
        case isVerified = "is_verified"
        case proxyURL = "proxy_url"
    }
}

nonisolated struct MoviePlaybackSources: Codable, Sendable {
    let slug: String
    let sources: [MovieStreamSource]
}

nonisolated enum PlaybackSource: Hashable, Sendable {
    case anime(animeID: String, episodeNumber: Int, title: String, item: MediaItemDescriptor)
    case movie(
        slug: String,
        title: String,
        item: MediaItemDescriptor,
        unitTitle: String?,
        seasonNumber: Int?,
        episodeNumber: Int?
    )

    var requestID: String {
        switch self {
        case .anime(let animeID, let episodeNumber, _, _):
            "anime-\(animeID)-\(episodeNumber)"
        case .movie(let slug, _, _, _, _, _):
            "movie-\(slug)"
        }
    }
}

nonisolated struct PlaybackQueue: Hashable, Sendable {
    let sources: [PlaybackSource]

    func adjacent(of requestID: String, offset: Int) -> PlaybackSource? {
        guard let index = sources.firstIndex(where: { $0.requestID == requestID }) else {
            return nil
        }
        let adjacentIndex = index + offset
        guard sources.indices.contains(adjacentIndex) else { return nil }
        return sources[adjacentIndex]
    }
}

nonisolated struct PlaybackOption: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case direct
        case embed
    }

    let id: String
    let kind: Kind
    let title: String
    let url: URL
    let requestHeaders: [String: String]
    let subtitleTracks: [AnimeSubtitleTrack]
}

nonisolated struct PlaybackRequest: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let directURL: URL?
    let embedURL: URL?
    let requestHeaders: [String: String]
    let playback: MediaPlaybackDescriptor?
    let subtitleTracks: [AnimeSubtitleTrack]
    let queue: PlaybackQueue?
    let options: [PlaybackOption]
    let selectedOptionID: String?

    var selectedOption: PlaybackOption? {
        if let selectedOptionID {
            return options.first { $0.id == selectedOptionID } ?? options.first
        }
        return options.first
    }

    init(
        id: String,
        title: String,
        directURL: URL?,
        embedURL: URL?,
        requestHeaders: [String: String],
        playback: MediaPlaybackDescriptor?,
        subtitleTracks: [AnimeSubtitleTrack] = [],
        queue: PlaybackQueue? = nil,
        options: [PlaybackOption] = [],
        selectedOptionID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.directURL = directURL
        self.embedURL = embedURL
        self.requestHeaders = requestHeaders
        self.playback = playback
        self.subtitleTracks = subtitleTracks
        self.queue = queue
        self.options = options
        self.selectedOptionID = selectedOptionID ?? options.first?.id
    }

    func withQueue(_ queue: PlaybackQueue?) -> PlaybackRequest {
        PlaybackRequest(
            id: id,
            title: title,
            directURL: directURL,
            embedURL: embedURL,
            requestHeaders: requestHeaders,
            playback: playback,
            subtitleTracks: subtitleTracks,
            queue: queue,
            options: options,
            selectedOptionID: selectedOptionID
        )
    }

    func selecting(_ option: PlaybackOption) -> PlaybackRequest {
        PlaybackRequest(
            id: id,
            title: title,
            directURL: option.kind == .direct ? option.url : nil,
            embedURL: option.kind == .embed ? option.url : embedURL,
            requestHeaders: option.requestHeaders,
            playback: playback,
            subtitleTracks: option.subtitleTracks,
            queue: queue,
            options: options,
            selectedOptionID: option.id
        )
    }
}

nonisolated enum MediaAccountType: String, Codable, CaseIterable, Hashable, Sendable {
    case anime
    case movie
    case football

    var title: String {
        switch self {
        case .anime: "Anime"
        case .movie: "Movies & TV"
        case .football: "Football"
        }
    }

    var systemImage: String {
        switch self {
        case .anime: "play.rectangle.on.rectangle"
        case .movie: "film"
        case .football: "sportscourt"
        }
    }
}

nonisolated struct MediaAccountKey: Hashable, Sendable {
    let mediaType: MediaAccountType
    let contentID: String
}

nonisolated struct MediaItemDescriptor: Codable, Hashable, Sendable {
    let mediaType: MediaAccountType
    let contentID: String
    let title: String
    let subtitle: String?
    let imageURL: URL?

    var key: MediaAccountKey {
        MediaAccountKey(mediaType: mediaType, contentID: contentID)
    }
}

nonisolated struct MediaPlaybackDescriptor: Codable, Hashable, Sendable {
    let item: MediaItemDescriptor
    let unitID: String
    let unitTitle: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
}

nonisolated struct MediaBookmark: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let userId: String
    let mediaType: MediaAccountType
    let contentId: String
    let title: String
    let subtitle: String?
    let imageURL: URL?
    let createdAt: Date
    let updatedAt: Date

    var key: MediaAccountKey {
        MediaAccountKey(mediaType: mediaType, contentID: contentId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, userId, mediaType, contentId, title, subtitle, createdAt, updatedAt
        case imageURL = "imageUrl"
    }
}

nonisolated struct MediaBookmarkMutationResult: Codable, Sendable {
    let bookmark: MediaBookmark?
    let isSaved: Bool
    let clientUpdatedAt: Date
}

nonisolated struct MediaPlaybackProgress: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let userId: String
    let mediaType: MediaAccountType
    let contentId: String
    let title: String
    let imageURL: URL?
    let unitId: String
    let unitTitle: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let positionSeconds: Double
    let durationSeconds: Double
    let percentage: Double
    let completed: Bool
    let clientUpdatedAt: Date
    let createdAt: Date
    let updatedAt: Date

    var key: MediaAccountKey {
        MediaAccountKey(mediaType: mediaType, contentID: contentId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, userId, mediaType, contentId, title, unitId, unitTitle
        case seasonNumber, episodeNumber, positionSeconds, durationSeconds
        case percentage, completed, clientUpdatedAt, createdAt, updatedAt
        case imageURL = "imageUrl"
    }
}

nonisolated struct MediaHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let userId: String
    let mediaType: MediaAccountType
    let contentId: String
    let title: String
    let imageURL: URL?
    let unitId: String
    let unitTitle: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let positionSeconds: Double
    let durationSeconds: Double
    let percentage: Double
    let completed: Bool
    let visitCount: Int
    let clientUpdatedAt: Date
    let firstViewedAt: Date
    let lastViewedAt: Date
    let createdAt: Date
    let updatedAt: Date

    static func latestPerTitle(_ history: [MediaHistoryEntry]) -> [MediaHistoryEntry] {
        var latest: [String: MediaHistoryEntry] = [:]
        for entry in history {
            let key = "\(entry.mediaType.rawValue)-\(entry.contentId)"
            if let existing = latest[key] {
                if existing.lastViewedAt > entry.lastViewedAt { continue }
                if existing.lastViewedAt == entry.lastViewedAt, existing.id < entry.id { continue }
            }
            latest[key] = entry
        }
        return latest.values.sorted {
            if $0.lastViewedAt == $1.lastViewedAt { return $0.id < $1.id }
            return $0.lastViewedAt > $1.lastViewedAt
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, userId, mediaType, contentId, title, unitId, unitTitle
        case seasonNumber, episodeNumber, positionSeconds, durationSeconds
        case percentage, completed, visitCount, clientUpdatedAt, firstViewedAt, lastViewedAt
        case createdAt, updatedAt
        case imageURL = "imageUrl"
    }
}

nonisolated struct MediaAccountStats: Codable, Equatable, Sendable {
    var savedAnime: Int
    var savedMovies: Int
    var savedMatches: Int
    var animeEpisodesCompleted: Int
    var movieUnitsCompleted: Int
    var titlesInProgress: Int
    var historyEntries: Int
    var activityLast30Days: Int

    static let empty = MediaAccountStats(
        savedAnime: 0,
        savedMovies: 0,
        savedMatches: 0,
        animeEpisodesCompleted: 0,
        movieUnitsCompleted: 0,
        titlesInProgress: 0,
        historyEntries: 0,
        activityLast30Days: 0
    )
}

nonisolated struct MediaAccountSnapshot: Codable, Sendable {
    let bookmarks: [MediaBookmark]
    let progress: [MediaPlaybackProgress]
    let history: [MediaHistoryEntry]
    let stats: MediaAccountStats

    static let empty = MediaAccountSnapshot(
        bookmarks: [],
        progress: [],
        history: [],
        stats: .empty
    )
}

nonisolated struct MediaProgressSaveResult: Codable, Sendable {
    let progress: MediaPlaybackProgress?
    let history: MediaHistoryEntry?
}

nonisolated struct NormalizedMediaProgress: Equatable, Sendable {
    let positionSeconds: Double
    let durationSeconds: Double
    let percentage: Double
    let completed: Bool
}

nonisolated enum MediaContinuePolicy {
    /// The account keeps one progress record per title: the unit watched
    /// most recently. Resume it if unfinished, else go to the unit after it.
    /// After the final unit the title is finished, so offer the first again.
    static func resumeUnit<Unit>(
        from units: [Unit],
        progress: [MediaPlaybackProgress],
        matches: (Unit, MediaPlaybackProgress) -> Bool
    ) -> Unit? {
        guard let (latest, index) = latestActivity(in: units, progress: progress, matches: matches) else {
            return units.first
        }
        if !latest.completed { return units[index] }
        return units.indices.contains(index + 1) ? units[index + 1] : units.first
    }

    /// True once the most recent unit watched is the last one and it's done.
    static func isFinished<Unit>(
        _ units: [Unit],
        progress: [MediaPlaybackProgress],
        matches: (Unit, MediaPlaybackProgress) -> Bool
    ) -> Bool {
        guard let (latest, index) = latestActivity(in: units, progress: progress, matches: matches) else {
            return false
        }
        return latest.completed && index == units.count - 1
    }

    private static func latestActivity<Unit>(
        in units: [Unit],
        progress: [MediaPlaybackProgress],
        matches: (Unit, MediaPlaybackProgress) -> Bool
    ) -> (MediaPlaybackProgress, Int)? {
        progress
            .compactMap { item in units.firstIndex { matches($0, item) }.map { (item, $0) } }
            .max { lhs, rhs in
                lhs.0.updatedAt == rhs.0.updatedAt ? lhs.1 < rhs.1 : lhs.0.updatedAt < rhs.0.updatedAt
            }
    }

    static func isInProgress<Unit>(
        _ unit: Unit,
        progress: [MediaPlaybackProgress],
        matches: (Unit, MediaPlaybackProgress) -> Bool
    ) -> Bool {
        progress.contains {
            matches(unit, $0) && !$0.completed && ($0.positionSeconds > 0 || $0.percentage > 0)
        }
    }
}

nonisolated enum MediaProgressPolicy {
    static func normalize(positionSeconds: Double, durationSeconds: Double) -> NormalizedMediaProgress {
        let safeDuration = durationSeconds.isFinite ? max(0, durationSeconds) : 0
        let rawPosition = positionSeconds.isFinite ? max(0, positionSeconds) : 0
        let safePosition = safeDuration > 0 ? min(rawPosition, safeDuration) : rawPosition
        let percentage = safeDuration > 0 ? min(100, safePosition / safeDuration * 100) : 0
        return NormalizedMediaProgress(
            positionSeconds: safePosition,
            durationSeconds: safeDuration,
            percentage: percentage,
            completed: percentage >= 90
        )
    }
}

nonisolated enum FootballCatalogSection: String, CaseIterable, Hashable, Sendable {
    case live = "Live"
    case schedule = "Schedule"
    case popular = "Popular"
}

nonisolated struct FootballTeam: Codable, Hashable, Sendable {
    let name: String
    let badge: String?
    let badgeURL: URL?
}

nonisolated struct FootballTeams: Codable, Hashable, Sendable {
    let home: FootballTeam?
    let away: FootballTeam?
}

nonisolated struct FootballStreamSource: Codable, Hashable, Sendable {
    let source: String
    let id: String
}

nonisolated struct FootballMatch: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let category: String
    let kickoff: Date
    let posterURL: URL?
    let popular: Bool
    let isLive: Bool
    let teams: FootballTeams?
    let sources: [FootballStreamSource]

    var displayTitle: String {
        guard let home = teams?.home?.name, let away = teams?.away?.name else { return title }
        return "\(home) vs \(away)"
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, category, posterURL, popular, isLive, teams, sources
        case kickoff = "date"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        category = try values.decode(String.self, forKey: .category)
        posterURL = try values.decodeIfPresent(URL.self, forKey: .posterURL)
        popular = try values.decode(Bool.self, forKey: .popular)
        isLive = try values.decode(Bool.self, forKey: .isLive)
        teams = try values.decodeIfPresent(FootballTeams.self, forKey: .teams)
        sources = try values.decode([FootballStreamSource].self, forKey: .sources)
        let milliseconds = try values.decode(Int64.self, forKey: .kickoff)
        kickoff = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }
}

nonisolated struct FootballStream: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let streamNumber: Int
    let language: String
    let hd: Bool
    let embedURL: URL
    let source: String
    let viewers: Int?

    var optionID: String { "\(source)-\(id)-\(streamNumber)" }

    var displayName: String {
        var parts = [source.capitalized]
        if !language.isEmpty { parts.append(language.uppercased()) }
        if hd { parts.append("HD") }
        return parts.joined(separator: " · ")
    }

    private enum CodingKeys: String, CodingKey {
        case id, language, hd, source, viewers
        case streamNumber = "streamNo"
        case embedURL = "embedUrl"
    }
}

nonisolated struct FootballStreamCollection: Codable, Sendable {
    let streams: [FootballStream]
}

nonisolated struct FootballEnvelope<Value: Decodable & Sendable>: Decodable, Sendable {
    let success: Bool
    let data: Value
}
