import Foundation

enum MediaAccountType: String, Codable, CaseIterable, Hashable, Sendable {
    case anime
    case movie
    case football

    var title: String {
        switch self {
        case .anime: "Anime"
        case .movie: "Movies"
        case .football: "Football"
        }
    }

    var systemImage: String {
        switch self {
        case .anime: "play.rectangle.on.rectangle"
        case .movie: "film"
        case .football: "sportscourt"
        }
    }
}

struct MediaAccountKey: Hashable, Sendable {
    let mediaType: MediaAccountType
    let contentID: String
}

struct MediaItemDescriptor: Codable, Hashable, Sendable {
    let mediaType: MediaAccountType
    let contentID: String
    let title: String
    let subtitle: String?
    let imageURL: URL?

    var key: MediaAccountKey {
        MediaAccountKey(mediaType: mediaType, contentID: contentID)
    }
}

struct MediaPlaybackDescriptor: Codable, Hashable, Sendable {
    let item: MediaItemDescriptor
    let unitID: String
    let unitTitle: String?
    let seasonNumber: Int?
    let episodeNumber: Int?

    var historyUnitID: String { unitID }
}

struct MediaPlaybackSample: Equatable, Sendable {
    let positionSeconds: Double
    let durationSeconds: Double
    let completed: Bool
    let observedAt: Date
}

struct MediaBookmark: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let userId: String
    let mediaType: MediaAccountType
    let contentId: String
    let title: String
    let subtitle: String?
    let imageURL: URL?
    let createdAt: Date
    let updatedAt: Date

    var key: MediaAccountKey {
        MediaAccountKey(mediaType: mediaType, contentID: contentId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, userId, mediaType, contentId, title, subtitle, createdAt, updatedAt
        case imageURL = "imageUrl"
    }
}

struct MediaBookmarkMutationResult: Codable, Sendable {
    let bookmark: MediaBookmark?
    let isSaved: Bool
    let clientUpdatedAt: Date
}

struct MediaPlaybackProgress: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let userId: String
    let mediaType: MediaAccountType
    let contentId: String
    let title: String
    let imageURL: URL?
    let unitId: String
    let unitTitle: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let positionSeconds: Double
    let durationSeconds: Double
    let percentage: Double
    let completed: Bool
    let clientUpdatedAt: Date
    let createdAt: Date
    let updatedAt: Date

    var key: MediaAccountKey {
        MediaAccountKey(mediaType: mediaType, contentID: contentId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, userId, mediaType, contentId, title, unitId, unitTitle
        case seasonNumber, episodeNumber, positionSeconds, durationSeconds
        case percentage, completed, clientUpdatedAt, createdAt, updatedAt
        case imageURL = "imageUrl"
    }
}

struct MediaHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let userId: String
    let mediaType: MediaAccountType
    let contentId: String
    let title: String
    let imageURL: URL?
    let unitId: String
    let unitTitle: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let positionSeconds: Double
    let durationSeconds: Double
    let percentage: Double
    let completed: Bool
    let visitCount: Int
    let clientUpdatedAt: Date
    let firstViewedAt: Date
    let lastViewedAt: Date
    let createdAt: Date
    let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, userId, mediaType, contentId, title, unitId, unitTitle
        case seasonNumber, episodeNumber, positionSeconds, durationSeconds
        case percentage, completed, visitCount, clientUpdatedAt, firstViewedAt, lastViewedAt
        case createdAt, updatedAt
        case imageURL = "imageUrl"
    }
}

struct MediaAccountStats: Codable, Equatable, Sendable {
    var savedAnime: Int
    var savedMovies: Int
    var savedMatches: Int
    var animeEpisodesCompleted: Int
    var movieUnitsCompleted: Int
    var titlesInProgress: Int
    var historyEntries: Int
    var activityLast30Days: Int

    static let empty = MediaAccountStats(
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

struct MediaAccountSnapshot: Codable, Sendable {
    let bookmarks: [MediaBookmark]
    let progress: [MediaPlaybackProgress]
    let history: [MediaHistoryEntry]
    let stats: MediaAccountStats
}

struct MediaProgressSaveResult: Codable, Sendable {
    let progress: MediaPlaybackProgress?
    let history: MediaHistoryEntry?
}
