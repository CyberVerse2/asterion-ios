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

struct AnimeStreamSource: Codable, Hashable, Sendable {
    let server: String
    let embedURL: URL
    let quality: String?
    let directURL: URL?

    private enum CodingKeys: String, CodingKey {
        case server, quality
        case embedURL = "url"
        case directURL = "source"
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

    var title: String {
        let format = kind == .direct ? "Direct" : "Web"
        let qualityLabel = quality.map { " · \($0)" } ?? ""
        return "\(server) · \(format)\(qualityLabel)"
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
                        server: source.server
                    )
                )
            }
            options.append(
                AnimePlaybackOption(
                    id: "embed-\(sourceID)-\(index)",
                    kind: .embed,
                    url: source.embedURL,
                    quality: source.quality,
                    server: source.server
                )
            )
            return options
        }
    }
}
