import Foundation

struct AnimeTitle: Identifiable, Codable, Hashable, Sendable {
    let slug: String
    let title: String
    let japaneseTitle: String?
    let imageURL: URL?
    let type: String?
    let episodeLabel: String?

    var id: String { slug }
    var displayTitle: String { title.decodedHTMLEntities.trimmingCharacters(in: .whitespacesAndNewlines) }
    var displayJapaneseTitle: String? {
        japaneseTitle?.decodedHTMLEntities.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private enum CodingKeys: String, CodingKey {
        case slug, title, type
        case japaneseTitle = "japanese_title"
        case imageURL = "image_url"
        case episodeLabel = "episode_label"
    }
}

struct AnimeScheduleDay: Identifiable, Codable, Hashable, Sendable {
    let label: String
    let entries: [AnimeScheduleEntry]

    var id: String { label }
}

struct AnimeScheduleEntry: Identifiable, Codable, Hashable, Sendable {
    let slug: String
    let title: String
    let japaneseTitle: String?
    let time: String
    let episodeNumber: Int?
    let passed: Bool

    var id: String { "\(slug):\(episodeNumber ?? 0):\(time)" }
    var displayTitle: String {
        title.decodedHTMLEntities.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case slug, title, time, passed
        case japaneseTitle = "japanese_title"
        case episodeNumber = "episode_number"
    }
}

struct AnimeShow: Identifiable, Codable, Hashable, Sendable {
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

    var displayTitle: String { title.decodedHTMLEntities.trimmingCharacters(in: .whitespacesAndNewlines) }
    var displayJapaneseTitle: String? {
        japaneseTitle?.decodedHTMLEntities.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var displayDescription: String? {
        description?.decodedHTMLEntities.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var displayStudio: String? {
        studio?.decodedHTMLEntities.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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

private extension String {
    var decodedHTMLEntities: String {
        var decoded = self
        for _ in 0..<3 {
            let next = decoded.decodingHTMLEntitiesOnce
            guard next != decoded else { break }
            decoded = next
        }
        return decoded
    }

    var decodingHTMLEntitiesOnce: String {
        let namedEntities: [Substring: Character] = [
            "amp": "&",
            "apos": "'",
            "gt": ">",
            "hellip": "…",
            "ldquo": "“",
            "lsquo": "‘",
            "lt": "<",
            "mdash": "—",
            "nbsp": " ",
            "ndash": "–",
            "quot": "\"",
            "rdquo": "”",
            "rsquo": "’",
        ]

        var result = ""
        var index = startIndex

        while index < endIndex {
            guard self[index] == "&",
                  let semicolon = self[index...].firstIndex(of: ";"),
                  distance(from: index, to: semicolon) <= 12 else {
                result.append(self[index])
                formIndex(after: &index)
                continue
            }

            let entityStart = self.index(after: index)
            let entity = self[entityStart..<semicolon]
            let decoded: Character?

            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                decoded = UInt32(entity.dropFirst(2), radix: 16)
                    .flatMap(UnicodeScalar.init)
                    .map(Character.init)
            } else if entity.hasPrefix("#") {
                decoded = UInt32(entity.dropFirst())
                    .flatMap(UnicodeScalar.init)
                    .map(Character.init)
            } else {
                decoded = namedEntities[entity]
            }

            guard let decoded else {
                result.append(self[index])
                formIndex(after: &index)
                continue
            }

            result.append(decoded)
            index = self.index(after: semicolon)
        }

        return result
    }
}

struct AnimeEpisode: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let animeID: String
    let number: Int

    private enum CodingKeys: String, CodingKey {
        case id, number
        case animeID = "anime_id"
    }
}

struct AnimeRelatedSeason: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let slug: String
    let type: String
    let imageURL: URL?
    let episodesCount: Int

    var isTVSeason: Bool { type.localizedCaseInsensitiveCompare("TV") == .orderedSame }

    private enum CodingKeys: String, CodingKey {
        case id, title, slug, type
        case imageURL = "image_url"
        case episodesCount = "episodes_count"
    }
}

struct AnimeDownloadGroup: Identifiable, Hashable, Sendable {
    let show: AnimeShow
    let episodes: [AnimeEpisode]

    var id: String { show.slug }
}

struct AnimeEpisodeRange: Identifiable, Equatable, Sendable {
    static let pageSize = 100

    let episodes: [AnimeEpisode]

    var id: String {
        guard let first = episodes.first, let last = episodes.last else { return "empty" }
        return "\(first.id)-\(last.id)"
    }

    var label: String {
        guard let first = episodes.first, let last = episodes.last else { return "Episodes" }
        return String(format: "%03d–%03d", first.number, last.number)
    }

    func contains(episodeID: AnimeEpisode.ID?) -> Bool {
        guard let episodeID else { return false }
        return episodes.contains { $0.id == episodeID }
    }

    static func pages(for episodes: [AnimeEpisode], pageSize: Int = pageSize) -> [AnimeEpisodeRange] {
        precondition(pageSize > 0)

        return stride(from: 0, to: episodes.count, by: pageSize).map { startIndex in
            let endIndex = min(startIndex + pageSize, episodes.count)
            return AnimeEpisodeRange(episodes: Array(episodes[startIndex..<endIndex]))
        }
    }
}

struct AnimeStreamSource: Codable, Hashable, Sendable {
    let server: String
    let embedURL: URL
    let quality: String?
    let directURL: URL?
    let tracks: [AnimeSubtitleTrack]

    var directRequestHeaders: [String: String] {
        guard let origin = embedURL.webOrigin else {
            return ["User-Agent": "Mozilla/5.0"]
        }
        let headers = [
            "Referer": "\(origin)/",
            "Origin": origin,
            "User-Agent": "Mozilla/5.0",
        ]
        return headers
    }

    private enum CodingKeys: String, CodingKey {
        case server, quality, tracks
        case embedURL = "url"
        case directURL = "source"
    }
}

struct AnimeSubtitleTrack: Codable, Hashable, Sendable {
    let fileURL: URL
    let label: String
    let kind: String
    let languageCode: String?
    let isDefault: Bool

    init(
        fileURL: URL,
        label: String,
        kind: String,
        languageCode: String?,
        isDefault: Bool
    ) {
        self.fileURL = fileURL
        self.label = label
        self.kind = kind
        self.languageCode = languageCode
        self.isDefault = isDefault
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileURL = try container.decode(URL.self, forKey: .fileURL)
        let decodedLabel = try container.decodeIfPresent(String.self, forKey: .label)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        label = decodedLabel.flatMap { $0.isEmpty ? nil : $0 } ?? "Subtitles"
        let decodedKind = try container.decodeIfPresent(String.self, forKey: .kind)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        kind = decodedKind.flatMap { $0.isEmpty ? nil : $0 } ?? "subtitles"
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fileURL, forKey: .fileURL)
        try container.encode(label, forKey: .label)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(languageCode, forKey: .languageCode)
        try container.encode(isDefault, forKey: .isDefault)
    }

    private enum CodingKeys: String, CodingKey {
        case label, kind
        case fileURL = "file"
        case languageCode = "srclang"
        case isDefault = "default"
    }
}

struct AnimePlaybackOption: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case direct
        case embed
    }

    let id: String
    let kind: Kind
    let url: URL
    let quality: String?
    let server: String
    let variant: AnimePlaybackVariant?
    let subtitleTracks: [AnimeSubtitleTrack]
    let requestHeaders: [String: String]

    var title: String {
        let format = kind == .direct ? "Direct" : "Web"
        return ([server, variant?.title, format, quality]
            .compactMap { $0 }
            .filter { !$0.isEmpty })
            .joined(separator: " · ")
    }

    static func options(from sources: [AnimeStreamSource]) -> [AnimePlaybackOption] {
        sources.enumerated().flatMap { index, source in
            var options: [AnimePlaybackOption] = []
            let sourceID = source.server.isEmpty ? String(index) : source.server

            if let url = source.directURL {
                options.append(
                    AnimePlaybackOption(
                        id: "direct-\(sourceID)-\(index)",
                        kind: .direct,
                        url: url,
                        quality: source.quality,
                        server: source.server,
                        variant: AnimePlaybackVariant(streamURL: source.embedURL),
                        subtitleTracks: source.tracks,
                        requestHeaders: source.directRequestHeaders
                    )
                )
            }
            options.append(
                AnimePlaybackOption(
                    id: "embed-\(sourceID)-\(index)",
                    kind: .embed,
                    url: source.embedURL,
                    quality: source.quality,
                    server: source.server,
                    variant: AnimePlaybackVariant(streamURL: source.embedURL),
                    subtitleTracks: [],
                    requestHeaders: [:]
                )
            )
            return options
        }
    }
}

private extension URL {
    var webOrigin: String? {
        guard let scheme, let host else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        return components.url?.absoluteString
    }
}

enum AnimePlaybackVariant: String, Hashable, Sendable {
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
