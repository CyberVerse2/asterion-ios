import Foundation

enum FootballSection: String, CaseIterable, Codable, Hashable, Sendable {
    case live
    case schedule
    case popular

    var title: String {
        switch self {
        case .live: "Live"
        case .schedule: "Schedule"
        case .popular: "Popular"
        }
    }

    var systemImage: String {
        switch self {
        case .live: "dot.radiowaves.left.and.right"
        case .schedule: "calendar"
        case .popular: "flame"
        }
    }

    var catalogTitle: String {
        switch self {
        case .live: "Live now"
        case .schedule: "Match schedule"
        case .popular: "Popular matches"
        }
    }

    var catalogDescription: String {
        switch self {
        case .live: "Matches currently in play."
        case .schedule: "Upcoming and recently started fixtures."
        case .popular: "The matches drawing the most attention."
        }
    }
}

struct FootballTeam: Codable, Hashable, Sendable {
    let name: String
    let badge: String?
    let badgeURL: URL?
}

struct FootballTeams: Codable, Hashable, Sendable {
    let home: FootballTeam?
    let away: FootballTeam?
}

struct FootballStreamSource: Codable, Hashable, Sendable {
    let source: String
    let id: String
}

struct FootballMatch: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let category: String
    let kickoff: Date
    let poster: String?
    let posterURL: URL?
    let popular: Bool
    let isLive: Bool
    let teams: FootballTeams?
    let sources: [FootballStreamSource]

    var homeTeam: FootballTeam? { teams?.home }
    var awayTeam: FootballTeam? { teams?.away }
    var displayTitle: String {
        let home = homeTeam?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let away = awayTeam?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let home, !home.isEmpty, let away, !away.isEmpty {
            return "\(home) vs \(away)"
        }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, category, poster, posterURL, popular, isLive, teams, sources
        case kickoff = "date"
    }

    init(
        id: String,
        title: String,
        category: String,
        kickoff: Date,
        poster: String?,
        posterURL: URL?,
        popular: Bool,
        isLive: Bool,
        teams: FootballTeams?,
        sources: [FootballStreamSource]
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.kickoff = kickoff
        self.poster = poster
        self.posterURL = posterURL
        self.popular = popular
        self.isLive = isLive
        self.teams = teams
        self.sources = sources
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(String.self, forKey: .category)
        poster = try container.decodeIfPresent(String.self, forKey: .poster)
        posterURL = try container.decodeIfPresent(URL.self, forKey: .posterURL)
        popular = try container.decode(Bool.self, forKey: .popular)
        isLive = try container.decode(Bool.self, forKey: .isLive)
        teams = try container.decodeIfPresent(FootballTeams.self, forKey: .teams)
        sources = try container.decode([FootballStreamSource].self, forKey: .sources)
        let milliseconds = try container.decode(Int64.self, forKey: .kickoff)
        kickoff = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(poster, forKey: .poster)
        try container.encodeIfPresent(posterURL, forKey: .posterURL)
        try container.encode(popular, forKey: .popular)
        try container.encode(isLive, forKey: .isLive)
        try container.encodeIfPresent(teams, forKey: .teams)
        try container.encode(sources, forKey: .sources)
        try container.encode(Int64(kickoff.timeIntervalSince1970 * 1_000), forKey: .kickoff)
    }
}

struct FootballStream: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let streamNumber: Int
    let language: String
    let hd: Bool
    let embedURL: URL
    let source: String
    let viewers: Int?

    var optionID: String { "\(source)-\(id)-\(streamNumber)" }
    var displayName: String {
        var parts = [source.capitalized, language.uppercased()]
        if hd { parts.append("HD") }
        return parts.joined(separator: " · ")
    }

    private enum CodingKeys: String, CodingKey {
        case id, language, hd, source, viewers
        case streamNumber = "streamNo"
        case embedURL = "embedUrl"
    }
}

struct FootballStreamCollection: Codable, Sendable {
    let streams: [FootballStream]
    let matchID: String
    let homeTeam: String?
    let awayTeam: String?

    private enum CodingKeys: String, CodingKey {
        case streams, homeTeam, awayTeam
        case matchID = "matchId"
    }
}

struct FootballPlayerRoute: Codable, Hashable, Sendable {
    let match: FootballMatch
}
