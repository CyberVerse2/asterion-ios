import ActivityKit
import Foundation

struct ChapterDownloadActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var completed: Int
        var total: Int
        var statusText: String
    }

    var novelTitle: String
}
