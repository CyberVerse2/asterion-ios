import Foundation
@testable import AsterionKit

func novel(id: String, genres: [String], rating: Double, rank: String? = nil) -> Novel {
    Novel(
        id: id,
        title: id,
        author: nil,
        rank: rank,
        totalChapters: nil,
        views: nil,
        bookmarks: nil,
        status: nil,
        genres: genres,
        summary: nil,
        imageUrl: nil,
        rating: rating
    )
}

func catalogNovel(
    _ id: String,
    genres: [String] = [],
    rating: Double? = nil,
    rank: String? = nil,
    views: String? = nil,
    status: String? = nil,
    chapters: String? = nil,
    author: String? = nil,
    summary: String? = nil,
    image: String? = "https://example.com/\(UUID().uuidString).jpg"
) -> Novel {
    Novel(
        id: id, title: id, author: author, rank: rank, totalChapters: chapters,
        views: views, bookmarks: nil, status: status, genres: genres,
        summary: summary, imageUrl: image, rating: rating
    )
}

func playbackProgress(
    unitId: String,
    episodeNumber: Int,
    completed: Bool,
    positionSeconds: Double,
    percentage: Double = 20,
    updatedAt: Date = Date()
) -> MediaPlaybackProgress {
    MediaPlaybackProgress(
        id: unitId,
        userId: "user",
        mediaType: .anime,
        contentId: "show",
        title: "Show",
        imageURL: nil,
        unitId: unitId,
        unitTitle: "Episode \(episodeNumber)",
        seasonNumber: 1,
        episodeNumber: episodeNumber,
        positionSeconds: positionSeconds,
        durationSeconds: 1_000,
        percentage: percentage,
        completed: completed,
        clientUpdatedAt: updatedAt,
        createdAt: updatedAt,
        updatedAt: updatedAt
    )
}

func isoDate(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
