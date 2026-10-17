import Foundation

/// A big-league match's score from the football service (football-data.org behind it).
public struct FootballScore: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        case scheduled, live, halftime, finished, suspended, postponed, cancelled

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .scheduled
        }
    }

    public let home: Int?
    public let away: Int?
    public let status: Status
    public let minute: Int?
    public let injuryTime: Int?
    public let competition: String?
    /// The free plan's scores run a few minutes behind the match.
    public let delayed: Bool

    public init(home: Int?, away: Int?, status: Status, minute: Int? = nil, injuryTime: Int? = nil,
                competition: String? = nil, delayed: Bool = true) {
        self.home = home
        self.away = away
        self.status = status
        self.minute = minute
        self.injuryTime = injuryTime
        self.competition = competition
        self.delayed = delayed
    }

    public var isInPlay: Bool { status == .live || status == .halftime }

    /// "2 – 1", or nil before kickoff.
    public var scoreline: String? {
        guard let home, let away else { return nil }
        return "\(home) – \(away)"
    }

    /// "67'", "90+3'", "HT", "FT"; nil when there is nothing to say.
    public var clockLabel: String? {
        switch status {
        case .live:
            guard let minute else { return nil }
            if let injuryTime, injuryTime > 0 { return "\(minute)+\(injuryTime)'" }
            return "\(minute)'"
        case .halftime: return "HT"
        case .finished: return "FT"
        case .suspended: return "Suspended"
        case .postponed: return "Postponed"
        case .cancelled: return "Cancelled"
        case .scheduled: return nil
        }
    }

    /// Spoken form for VoiceOver: "Arsenal 2, Chelsea 1, 67th minute".
    public func accessibilityText(home homeName: String, away awayName: String) -> String? {
        guard let home, let away else { return nil }
        var parts = ["\(homeName) \(home), \(awayName) \(away)"]
        switch status {
        case .live: if let minute { parts.append("minute \(minute)") }
        case .halftime: parts.append("half time")
        case .finished: parts.append("full time")
        default: break
        }
        return parts.joined(separator: ", ")
    }
}
