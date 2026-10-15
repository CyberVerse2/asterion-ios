import Foundation

#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
import ActivityKit

/// The colour a cover casts, sampled by the app (widgets cannot sample
/// images cheaply) so the Dynamic Island can be lit by the story.
nonisolated struct ActivityTint: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
}

nonisolated struct ChapterDownloadActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var completed: Int
        var total: Int
        var statusText: String
    }

    var novelTitle: String
    var novelImageURL: String?
    var novelImageData: Data?
    var tint: ActivityTint? = nil
}

nonisolated struct ReadingSessionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var chapterTitle: String
        var currentLine: Int
        var totalLines: Int
        /// Estimated minutes to the end of the chapter at reading pace.
        var minutesLeft: Int? = nil
    }

    var novelTitle: String
    /// Tiny 2:3 JPEG thumbnail of the cover (a few KB).
    var imageData: Data? = nil
    var tint: ActivityTint? = nil
}

/// A film or episode playing in the native player. The player drives every
/// update, so the widget renders static values (no system timers).
nonisolated struct WatchingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// "S1 E3", "Episode 7" or "Film".
        var unitLabel: String
        var positionSeconds: Double
        var durationSeconds: Double
        var isPlaying: Bool
    }

    var title: String
    /// "anime" or "movie".
    var mediaType: String
    var imageURL: String?
    /// Tiny 2:3 JPEG thumbnail (a few KB); Live Activities cannot load remote images.
    var imageData: Data?
    var tint: ActivityTint? = nil
}

/// A followed football match: a countdown to kickoff that flips to LIVE once
/// the activity goes stale at kickoff or the app reports the match in play.
nonisolated struct MatchActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var isLive: Bool
    }

    var matchID: String
    var home: String
    var away: String
    var competition: String
    var kickoff: Date
    var homeBadgeURL: String?
    var awayBadgeURL: String?
}
#endif
