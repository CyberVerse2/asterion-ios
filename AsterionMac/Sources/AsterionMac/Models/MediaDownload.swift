import Foundation

enum MediaDownloadPhase: String, Codable, Hashable, Sendable {
    case preparing
    case downloading
    case completed
    case failed
}

struct MediaDownloadRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let mediaType: MediaAccountType
    let contentID: String
    let contentTitle: String
    let unitID: String
    let unitTitle: String
    let imageURL: URL?
    let animeShow: AnimeShow?
    let animeEpisode: AnimeEpisode?
    let movieShow: MovieShow?
    let movieEpisode: MovieEpisode?
    var phase: MediaDownloadPhase
    var progress: Double
    var localAssetURL: URL?
    var subtitleTracks: [AnimeSubtitleTrack]
    var errorMessage: String?
    var updatedAt: Date

    var isActive: Bool { phase == .preparing || phase == .downloading }
    var isAvailableOffline: Bool {
        phase == .completed && localAssetURL != nil
    }

    var detailLabel: String {
        switch mediaType {
        case .anime:
            unitTitle
        case .movie:
            movieEpisode == nil ? "Movie" : unitTitle
        case .football:
            unitTitle
        }
    }

    static func identifier(
        mediaType: MediaAccountType,
        contentID: String,
        unitID: String
    ) -> String {
        "\(mediaType.rawValue):\(contentID):\(unitID)"
    }
}

enum MediaDownloadError: LocalizedError, Equatable {
    case alreadyDownloading(title: String)
    case noDownloadableSource(title: String)
    case missingDownload
    case invalidStoredDownload

    var errorDescription: String? {
        switch self {
        case .alreadyDownloading(let title):
            "\(title) is already downloading."
        case .noDownloadableSource(let title):
            "\(title) does not currently have a direct HLS source that can be downloaded."
        case .missingDownload:
            "This download no longer exists."
        case .invalidStoredDownload:
            "The saved download record is incomplete."
        }
    }
}
