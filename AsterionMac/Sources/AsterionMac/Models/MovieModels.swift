import Foundation

struct MovieTitle: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let slug: String
    let title: String
    let imageURL: URL?
    let imdbRating: String?
    let runtime: String?
    let year: String?
    let type: String?
    let quality: String?

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSeries: Bool { type == "tv" }

    private enum CodingKeys: String, CodingKey {
        case id, slug, title, runtime, year, type, quality
        case imageURL = "image_url"
        case imdbRating = "imdb_rating"
    }
}

struct MovieCatalogPage: Codable, Sendable {
    let page: Int
    let totalPages: Int
    let results: [MovieTitle]

    private enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
    }
}

struct MovieGenre: Identifiable, Codable, Hashable, Sendable {
    let slug: String
    let title: String

    var id: String { slug }
}

struct MovieShow: Identifiable, Codable, Hashable, Sendable {
    let slug: String
    let title: String
    let type: String
    let imageURL: URL?
    let description: String?
    let imdbRating: String?
    let tmdbRating: String?
    let rottenTomatoes: String?
    let metacritic: String?
    let genres: [String]
    let director: String?
    let actors: [String]
    let duration: String?
    let releaseYear: String?
    let releaseDate: String?
    let country: String?
    let seasons: [String]
    let streams: [MovieStreamSource]

    var id: String { slug }
    var isSeries: Bool { type == "tv" }
    var displayTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private enum CodingKeys: String, CodingKey {
        case slug, title, type, description, genres, director, actors, duration
        case country, seasons, streams
        case imageURL = "image_url"
        case imdbRating = "imdb_rating"
        case tmdbRating = "tmdb_rating"
        case rottenTomatoes = "rotten_tomatoes"
        case metacritic
        case releaseYear = "release_year"
        case releaseDate = "release_date"
    }
}

struct MovieEpisode: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let season: Int
    let number: Int
    let title: String
    let url: URL
}

struct MovieStreamSource: Codable, Hashable, Sendable {
    let serverID: Int
    let label: String
    let quality: String
    let embedURL: URL
    let isHLS: Bool
    let isVerified: Bool
    let automatic: Bool
    let proxyURL: URL?

    init(
        serverID: Int,
        label: String,
        quality: String,
        embedURL: URL,
        isHLS: Bool,
        isVerified: Bool = false,
        automatic: Bool = false,
        proxyURL: URL?
    ) {
        self.serverID = serverID
        self.label = label
        self.quality = quality
        self.embedURL = embedURL
        self.isHLS = isHLS
        self.isVerified = isVerified
        self.automatic = automatic
        self.proxyURL = proxyURL
    }

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
        case label, quality
        case serverID = "server_id"
        case embedURL = "embed_url"
        case isHLS = "is_hls"
        case isVerified = "is_verified"
        case automatic
        case proxyURL = "proxy_url"
    }
}

struct MoviePlaybackSources: Codable, Sendable {
    let slug: String
    let sources: [MovieStreamSource]
    let verifiedDirectCount: Int

    private enum CodingKeys: String, CodingKey {
        case slug, sources
        case verifiedDirectCount = "verified_direct_count"
    }
}

struct MoviePlaybackOption: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case direct
        case web
    }

    let id: String
    let kind: Kind
    let url: URL
    let title: String
    let isAutomatic: Bool

    init(
        id: String,
        kind: Kind,
        url: URL,
        title: String,
        isAutomatic: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.title = title
        self.isAutomatic = isAutomatic
    }

    static func options(from sources: [MovieStreamSource]) -> [MoviePlaybackOption] {
        sources.map { source in
            let kind: Kind = source.isHLS ? .direct : .web
            let quality = kind == .web && source.quality == "Direct Player"
                ? "Web Player"
                : source.quality
            return MoviePlaybackOption(
                id: [
                    kind.rawValue,
                    source.label.lowercased(),
                    source.embedURL.host?.lowercased() ?? String(source.serverID),
                ].joined(separator: "-"),
                kind: kind,
                url: source.isHLS ? source.proxyURL ?? source.embedURL : source.embedURL,
                title: [source.label, quality]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "),
                isAutomatic: kind == .direct && source.isVerified && source.automatic
            )
        }
    }

    static func preferred(from options: [MoviePlaybackOption]) -> MoviePlaybackOption? {
        options.first
    }
}

enum MediaPlaybackLifecycleEvent: Sendable {
    case loading
    case ready
    case playRequested
    case playing
    case paused
    case failed(String)
}

struct MoviePlayerRoute: Codable, Hashable, Sendable {
    let slug: String
    let title: String
    let initialEpisodeID: String?
}
