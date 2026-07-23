import Foundation

#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
import ActivityKit

struct ChapterDownloadActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var completed: Int
        var total: Int
        var statusText: String
    }

    var novelTitle: String
    var novelImageURL: String?
    var novelImageData: Data?
}

struct ReadingSessionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var chapterTitle: String
        var currentLine: Int
        var totalLines: Int
    }

    var novelTitle: String
}
#endif
