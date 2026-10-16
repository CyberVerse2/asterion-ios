import Foundation

// MARK: - Playback queue

public enum PlaybackSource: Hashable, Sendable {
    case anime(animeID: String, episodeNumber: Int, title: String, item: MediaItemDescriptor)
    case movie(
        slug: String,
        title: String,
        item: MediaItemDescriptor,
        unitTitle: String?,
        seasonNumber: Int?,
        episodeNumber: Int?
    )

    public var requestID: String {
        switch self {
        case .anime(let animeID, let episodeNumber, _, _):
            "anime-\(animeID)-\(episodeNumber)"
        case .movie(let slug, _, _, _, _, _):
            "movie-\(slug)"
        }
    }
}

public struct PlaybackQueue: Hashable, Sendable {
    public let sources: [PlaybackSource]

    public init(sources: [PlaybackSource]) {
        self.sources = sources
    }

    public func adjacent(of requestID: String, offset: Int) -> PlaybackSource? {
        guard let index = sources.firstIndex(where: { $0.requestID == requestID }) else {
            return nil
        }
        let adjacentIndex = index + offset
        guard sources.indices.contains(adjacentIndex) else { return nil }
        return sources[adjacentIndex]
    }
}

// MARK: - Account records

public enum MediaAccountType: String, Codable, CaseIterable, Hashable, Sendable {
    case anime
    case movie
    case football

    public var title: String {
        switch self {
        case .anime: "Anime"
        case .movie: "Movies & TV"
        case .football: "Football"
        }
    }

    public var systemImage: String {
        switch self {
        case .anime: "play.rectangle.on.rectangle"
        case .movie: "film"
        case .football: "sportscourt"
        }
    }
}

public struct MediaAccountKey: Hashable, Sendable {
    public let mediaType: MediaAccountType
    public let contentID: String

    public init(mediaType: MediaAccountType, contentID: String) {
        self.mediaType = mediaType
        self.contentID = contentID
    }
}

public struct MediaItemDescriptor: Codable, Hashable, Sendable {
    public let mediaType: MediaAccountType
    public let contentID: String
    public let title: String
    public let subtitle: String?
    public let imageURL: URL?

    public init(mediaType: MediaAccountType, contentID: String, title: String, subtitle: String?, imageURL: URL?) {
        self.mediaType = mediaType
        self.contentID = contentID
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
    }

    public var key: MediaAccountKey {
        MediaAccountKey(mediaType: mediaType, contentID: contentID)
    }
}

public struct MediaPlaybackDescriptor: Codable, Hashable, Sendable {
    public let item: MediaItemDescriptor
    public let unitID: String
    public let unitTitle: String?
    public let seasonNumber: Int?
    public let episodeNumber: Int?

    public init(item: MediaItemDescriptor, unitID: String, unitTitle: String?, seasonNumber: Int?, episodeNumber: Int?) {
        self.item = item
        self.unitID = unitID
        self.unitTitle = unitTitle
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
    }
}

public struct MediaBookmark: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let userId: String
    public let mediaType: MediaAccountType
    public let contentId: String
    public let title: String
    public let subtitle: String?
    public let imageURL: URL?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        userId: String,
        mediaType: MediaAccountType,
        contentId: String,
        title: String,
        subtitle: String?,
        imageURL: URL?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.userId = userId
        self.mediaType = mediaType
        self.contentId = contentId
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var key: MediaAccountKey {
        MediaAccountKey(mediaType: mediaType, contentID: contentId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, userId, mediaType, contentId, title, subtitle, createdAt, updatedAt
        case imageURL = "imageUrl"
    }
}

public struct MediaBookmarkMutationResult: Codable, Sendable {
    public let bookmark: MediaBookmark?
    public let isSaved: Bool
    public let clientUpdatedAt: Date

    public init(bookmark: MediaBookmark?, isSaved: Bool, clientUpdatedAt: Date) {
        self.bookmark = bookmark
        self.isSaved = isSaved
        self.clientUpdatedAt = clientUpdatedAt
    }
}

public struct MediaPlaybackProgress: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let userId: String
    public let mediaType: MediaAccountType
    public let contentId: String
    public let title: String
    public let imageURL: URL?
    public let unitId: String
    public let unitTitle: String?
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    public let positionSeconds: Double
    public let durationSeconds: Double
    public let percentage: Double
    public let completed: Bool
    public let clientUpdatedAt: Date
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        userId: String,
        mediaType: MediaAccountType,
        contentId: String,
        title: String,
        imageURL: URL?,
        unitId: String,
        unitTitle: String?,
        seasonNumber: Int?,
        episodeNumber: Int?,
        positionSeconds: Double,
        durationSeconds: Double,
        percentage: Double,
        completed: Bool,
        clientUpdatedAt: Date,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.userId = userId
        self.mediaType = mediaType
        self.contentId = contentId
        self.title = title
        self.imageURL = imageURL
        self.unitId = unitId
        self.unitTitle = unitTitle
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.percentage = percentage
        self.completed = completed
        self.clientUpdatedAt = clientUpdatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var key: MediaAccountKey {
        MediaAccountKey(mediaType: mediaType, contentID: contentId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, userId, mediaType, contentId, title, unitId, unitTitle
        case seasonNumber, episodeNumber, positionSeconds, durationSeconds
        case percentage, completed, clientUpdatedAt, createdAt, updatedAt
        case imageURL = "imageUrl"
    }
}

public struct MediaHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let userId: String
    public let mediaType: MediaAccountType
    public let contentId: String
    public let title: String
    public let imageURL: URL?
    public let unitId: String
    public let unitTitle: String?
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    public let positionSeconds: Double
    public let durationSeconds: Double
    public let percentage: Double
    public let completed: Bool
    public let visitCount: Int
    public let clientUpdatedAt: Date
    public let firstViewedAt: Date
    public let lastViewedAt: Date
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        userId: String,
        mediaType: MediaAccountType,
        contentId: String,
        title: String,
        imageURL: URL?,
        unitId: String,
        unitTitle: String?,
        seasonNumber: Int?,
        episodeNumber: Int?,
        positionSeconds: Double,
        durationSeconds: Double,
        percentage: Double,
        completed: Bool,
        visitCount: Int,
        clientUpdatedAt: Date,
        firstViewedAt: Date,
        lastViewedAt: Date,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.userId = userId
        self.mediaType = mediaType
        self.contentId = contentId
        self.title = title
        self.imageURL = imageURL
        self.unitId = unitId
        self.unitTitle = unitTitle
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.percentage = percentage
        self.completed = completed
        self.visitCount = visitCount
        self.clientUpdatedAt = clientUpdatedAt
        self.firstViewedAt = firstViewedAt
        self.lastViewedAt = lastViewedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func latestPerTitle(_ history: [MediaHistoryEntry]) -> [MediaHistoryEntry] {
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

public struct MediaAccountStats: Codable, Equatable, Sendable {
    public var savedAnime: Int
    public var savedMovies: Int
    public var savedMatches: Int
    public var animeEpisodesCompleted: Int
    public var movieUnitsCompleted: Int
    public var titlesInProgress: Int
    public var historyEntries: Int
    public var activityLast30Days: Int

    public init(
        savedAnime: Int,
        savedMovies: Int,
        savedMatches: Int,
        animeEpisodesCompleted: Int,
        movieUnitsCompleted: Int,
        titlesInProgress: Int,
        historyEntries: Int,
        activityLast30Days: Int
    ) {
        self.savedAnime = savedAnime
        self.savedMovies = savedMovies
        self.savedMatches = savedMatches
        self.animeEpisodesCompleted = animeEpisodesCompleted
        self.movieUnitsCompleted = movieUnitsCompleted
        self.titlesInProgress = titlesInProgress
        self.historyEntries = historyEntries
        self.activityLast30Days = activityLast30Days
    }

    public static let empty = MediaAccountStats(
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

public struct MediaAccountSnapshot: Codable, Sendable {
    public let bookmarks: [MediaBookmark]
    public let progress: [MediaPlaybackProgress]
    public let history: [MediaHistoryEntry]
    public let stats: MediaAccountStats

    public init(
        bookmarks: [MediaBookmark],
        progress: [MediaPlaybackProgress],
        history: [MediaHistoryEntry],
        stats: MediaAccountStats
    ) {
        self.bookmarks = bookmarks
        self.progress = progress
        self.history = history
        self.stats = stats
    }

    public static let empty = MediaAccountSnapshot(
        bookmarks: [],
        progress: [],
        history: [],
        stats: .empty
    )
}

public struct MediaProgressSaveResult: Codable, Sendable {
    public let progress: MediaPlaybackProgress?
    public let history: MediaHistoryEntry?

    public init(progress: MediaPlaybackProgress?, history: MediaHistoryEntry?) {
        self.progress = progress
        self.history = history
    }
}

// MARK: - Progress policies

public struct NormalizedMediaProgress: Equatable, Sendable {
    public let positionSeconds: Double
    public let durationSeconds: Double
    public let percentage: Double
    public let completed: Bool

    public init(positionSeconds: Double, durationSeconds: Double, percentage: Double, completed: Bool) {
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.percentage = percentage
        self.completed = completed
    }
}

public enum MediaContinuePolicy {
    /// The account keeps one progress record per title: the unit watched
    /// most recently. Resume it if unfinished, else go to the unit after it.
    /// After the final unit the title is finished, so offer the first again.
    public static func resumeUnit<Unit>(
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
    public static func isFinished<Unit>(
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

    public static func isInProgress<Unit>(
        _ unit: Unit,
        progress: [MediaPlaybackProgress],
        matches: (Unit, MediaPlaybackProgress) -> Bool
    ) -> Bool {
        progress.contains {
            matches(unit, $0) && !$0.completed && ($0.positionSeconds > 0 || $0.percentage > 0)
        }
    }
}

public enum MediaProgressPolicy {
    public static func normalize(positionSeconds: Double, durationSeconds: Double) -> NormalizedMediaProgress {
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
