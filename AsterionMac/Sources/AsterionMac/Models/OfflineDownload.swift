import Foundation

struct OfflineDownload: Identifiable, Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case downloading
        case completed
        case failed
    }

    let novelID: String
    let novelTitle: String
    var completedChapters: Int
    var totalChapters: Int
    var phase: Phase
    var errorMessage: String?
    var updatedAt: Date

    var id: String { novelID }

    var progress: Double {
        guard totalChapters > 0 else { return 0 }
        return min(max(Double(completedChapters) / Double(totalChapters), 0), 1)
    }

    var isDownloading: Bool { phase == .downloading }
}

enum OfflineDownloadError: LocalizedError, Equatable {
    case alreadyInProgress(novelTitle: String)

    var errorDescription: String? {
        switch self {
        case .alreadyInProgress(let novelTitle):
            "\(novelTitle) is already downloading."
        }
    }
}
