import AsterionKit
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
    /// Big-league matches only; nil when the score service doesn't know the fixture.
    let score: FootballScore?

    var displayTitle: String {
        guard let home = teams?.home?.name, let away = teams?.away?.name else { return title }
        return "\(home) vs \(away)"
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, category, posterURL, popular, isLive, teams, sources, score
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
        score = try? values.decodeIfPresent(FootballScore.self, forKey: .score)
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
