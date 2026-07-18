import Foundation

struct AnimeTitle: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let japaneseTitle: String?
    let imageURL: URL?
    let type: String?
    let episodeLabel: String?
    let url: URL?

    var displayTitle: String { title.decodedHTMLEntities }
    var displayJapaneseTitle: String? { japaneseTitle?.decodedHTMLEntities }

    private enum CodingKeys: String, CodingKey {
        case id, title, type, url
        case japaneseTitle = "japanese_title"
        case imageURL = "image_url"
        case episodeLabel = "episode_label"
    }

    var slug: String {
        if let url {
            let components = url.pathComponents.filter { $0 != "/" }
            if let animeIndex = components.firstIndex(of: "anime"),
               components.indices.contains(animeIndex + 1) {
                return components[animeIndex + 1]
            }

            if let path = components.last, let episodeRange = path.range(of: "-episode-") {
                return String(path[..<episodeRange.lowerBound])
            }
        }

        return displayTitle
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
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
    let episodes: Int?
    let season: String?
    let studio: String?
    let dateAired: String?
    let slug: String

    var displayTitle: String { title.decodedHTMLEntities }
    var displayJapaneseTitle: String? { japaneseTitle?.decodedHTMLEntities }
    var displayDescription: String? { description?.decodedHTMLEntities }
    var displayStudio: String? { studio?.decodedHTMLEntities }

    private enum CodingKeys: String, CodingKey {
        case id, title, description, type, status, genres, episodes, season, studio, slug
        case japaneseTitle = "japanese_title"
        case imageURL = "image_url"
        case dateAired = "date_aired"
    }
}

private extension String {
    var decodedHTMLEntities: String {
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
    let number: Int
    let url: URL?
}

struct AnimeStreamSource: Codable, Hashable, Sendable {
    let serverID: String?
    let type: String?
    let quality: String?
    let directURL: URL?
    let embedURL: URL?

    private enum CodingKeys: String, CodingKey {
        case type, quality
        case serverID = "server_id"
        case directURL = "direct_url"
        case embedURL = "embed_url"
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
    let serverID: String?

    var title: String {
        let base = kind == .direct ? "Direct stream" : "Web player"
        guard let quality, !quality.isEmpty else { return base }
        return "\(base) · \(quality)"
    }

    static func options(from sources: [AnimeStreamSource]) -> [AnimePlaybackOption] {
        sources.enumerated().flatMap { index, source in
            var options: [AnimePlaybackOption] = []
            let sourceID = source.serverID ?? String(index)

            if let url = source.directURL {
                options.append(
                    AnimePlaybackOption(
                        id: "direct-\(sourceID)-\(index)",
                        kind: .direct,
                        url: url,
                        quality: source.quality,
                        serverID: source.serverID
                    )
                )
            }
            if let url = source.embedURL {
                options.append(
                    AnimePlaybackOption(
                        id: "embed-\(sourceID)-\(index)",
                        kind: .embed,
                        url: url,
                        quality: source.quality,
                        serverID: source.serverID
                    )
                )
            }
            return options
        }
    }
}
