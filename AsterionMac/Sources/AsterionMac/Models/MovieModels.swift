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
    let proxyURL: URL?

    private enum CodingKeys: String, CodingKey {
        case label, quality
        case serverID = "server_id"
        case embedURL = "embed_url"
        case isHLS = "is_hls"
        case proxyURL = "proxy_url"
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

    static func options(from sources: [MovieStreamSource]) -> [MoviePlaybackOption] {
        sources.map { source in
            let kind: Kind = source.isHLS ? .direct : .web
            return MoviePlaybackOption(
                id: "\(kind.rawValue)-\(source.serverID)",
                kind: kind,
                url: source.isHLS ? source.proxyURL ?? source.embedURL : source.embedURL,
                title: [source.label, source.quality]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
            )
        }
    }

    static func preferred(from options: [MoviePlaybackOption]) -> MoviePlaybackOption? {
        options.first { $0.kind == .web && $0.url.host()?.localizedCaseInsensitiveContains("videasy.net") == true }
            ?? options.first { $0.kind == .web && $0.title.localizedCaseInsensitiveContains("VidNest") }
            ?? options.first { $0.kind == .web }
            ?? options.first
    }
}

struct MoviePlayerRoute: Codable, Hashable, Sendable {
    let slug: String
    let title: String
    let initialEpisodeID: String?
}
