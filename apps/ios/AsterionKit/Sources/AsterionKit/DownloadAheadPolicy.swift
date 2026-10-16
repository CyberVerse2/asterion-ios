import Foundation

/// Which shows and episodes Download ahead fetches and prunes.
public enum DownloadAheadPolicy {
    /// At most this many shows are downloaded ahead at once.
    public static let maximumShows = 3
    /// Shows untouched for longer than this are left alone.
    public static let recentWatchWindow: TimeInterval = 21 * 24 * 60 * 60

    /// Anime and series watched recently, one entry per title. A finished
    /// episode counts too: the episodes after it are the ones to fetch.
    public static func showsToQueue(
        from progress: [MediaPlaybackProgress],
        now: Date = Date()
    ) -> [MediaPlaybackProgress] {
        var seen = Set<String>()
        return progress
            .filter { item in
                guard item.completed || item.positionSeconds > 0 else { return false }
                guard now.timeIntervalSince(item.updatedAt) < recentWatchWindow else { return false }
                switch item.mediaType {
                case .anime: return item.episodeNumber != nil
                case .movie: return item.episodeNumber != nil || item.seasonNumber != nil
                default: return false
                }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .filter { seen.insert("\($0.mediaType.rawValue):\($0.contentId)").inserted }
            .prefix(maximumShows)
            .map { $0 }
    }

    /// Whether a downloaded episode is behind the title's latest progress
    /// (or is that episode, finished), so it can be removed.
    public static func isWatchedPast(_ unit: MediaPlaybackDescriptor, latest: MediaPlaybackProgress) -> Bool {
        if let episode = unit.episodeNumber, let latestEpisode = latest.episodeNumber {
            let position = (unit.seasonNumber ?? 0, episode)
            let latestPosition = (latest.seasonNumber ?? 0, latestEpisode)
            return position < latestPosition || (position == latestPosition && latest.completed)
        }
        return latest.completed && unit.unitID == latest.unitId
    }
}

public enum OfflineVideoPaths {
    /// Where a package lives inside the app container. iOS 26 reports
    /// downloads under /.nofollow/private/var/…, NSHomeDirectory() is /var/…,
    /// and the container ID changes on reinstall, so keep only the part after
    /// the container. Also repairs absolute paths saved by earlier builds.
    public static func containerRelativePath(_ path: String) -> String {
        if let range = path.range(of: #"/Containers/Data/Application/[^/]+/"#, options: .regularExpression) {
            return String(path[range.upperBound...])
        }
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        if path.hasPrefix(home + "/") {
            return String(path.dropFirst(home.count + 1))
        }
        return path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

/// Runs one pass at a time. A request that arrives while a pass runs is kept
/// (only the newest, merged with any request already waiting) and handed back
/// when the pass finishes, so a later call with fresher inputs is never lost.
public struct FollowUpPassQueue<Input> {
    public private(set) var isRunning = false
    public private(set) var waiting: Input?

    public init() {}

    /// The input to start now, or nil when a pass is running and `input`
    /// waits for it. `merge(waiting, new)` combines with a request already waiting.
    public mutating func request(
        _ input: Input,
        merge: (Input, Input) -> Input = { _, newest in newest }
    ) -> Input? {
        guard isRunning else {
            isRunning = true
            return input
        }
        waiting = waiting.map { merge($0, input) } ?? input
        return nil
    }

    /// Call when a pass ends. Returns the waiting input to run next (the queue
    /// stays running), or nil once there is nothing left to do.
    public mutating func finish() -> Input? {
        guard let next = waiting else {
            isRunning = false
            return nil
        }
        waiting = nil
        return next
    }
}

extension FollowUpPassQueue: Sendable where Input: Sendable {}
