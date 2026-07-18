import Foundation

enum CatalogLoadState: Equatable, Sendable {
    case idle
    case remote
    case remoteWithOfflineError(String)
    case offline(remoteError: String)
    case failed(String)

    var notice: String? {
        switch self {
        case .idle, .remote:
            nil
        case .remoteWithOfflineError(let message):
            "The catalog is current, but downloaded novels could not be loaded. \(message)"
        case .offline(let remoteError):
            "Showing downloaded novels because the catalog is unavailable. \(remoteError)"
        case .failed(let message):
            message
        }
    }
}

enum ChapterListLoadState: Equatable, Sendable {
    case idle
    case remote
    case offline(remoteError: String)
    case failed(String)

    var notice: String? {
        switch self {
        case .idle, .remote:
            nil
        case .offline(let remoteError):
            "Showing the downloaded chapter list because the latest chapters could not be loaded. \(remoteError)"
        case .failed(let message):
            message
        }
    }
}

enum ChapterListLoadError: LocalizedError, Equatable {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        }
    }
}
