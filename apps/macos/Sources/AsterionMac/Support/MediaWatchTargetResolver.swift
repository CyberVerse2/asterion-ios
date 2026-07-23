import Foundation

enum MediaWatchTargetAction: Equatable, Sendable {
    case start
    case resume(percentage: Double)
    case next
    case rewatch
}

struct MediaWatchTarget: Equatable, Sendable {
    let unitID: String
    let action: MediaWatchTargetAction
}

enum MediaWatchTargetResolver {
    private struct Activity {
        let unitID: String
        let percentage: Double
        let completed: Bool
        let updatedAt: Date
        let isCurrentProgress: Bool
    }

    static func resolve(
        orderedUnitIDs: [String],
        progress: MediaPlaybackProgress?,
        history: [MediaHistoryEntry]
    ) -> MediaWatchTarget? {
        var seenUnitIDs = Set<String>()
        let unitIDs = orderedUnitIDs.filter { seenUnitIDs.insert($0).inserted }
        guard let firstUnitID = unitIDs.first else { return nil }

        let availableUnitIDs = Set(unitIDs)
        let historyActivities = history.compactMap { entry -> Activity? in
            guard availableUnitIDs.contains(entry.unitId) else { return nil }
            return Activity(
                unitID: entry.unitId,
                percentage: entry.percentage,
                completed: entry.completed,
                updatedAt: entry.clientUpdatedAt,
                isCurrentProgress: false
            )
        }
        let progressActivity = progress.flatMap { progress -> Activity? in
            guard availableUnitIDs.contains(progress.unitId) else { return nil }
            return Activity(
                unitID: progress.unitId,
                percentage: progress.percentage,
                completed: progress.completed,
                updatedAt: progress.clientUpdatedAt,
                isCurrentProgress: true
            )
        }
        let activities = historyActivities + [progressActivity].compactMap { $0 }
        guard let latest = activities.max(by: isEarlier) else {
            return MediaWatchTarget(unitID: firstUnitID, action: .start)
        }

        if !latest.completed {
            return MediaWatchTarget(
                unitID: latest.unitID,
                action: .resume(percentage: min(100, max(0, latest.percentage)))
            )
        }

        var completedUnitIDs = Set(historyActivities.filter(\.completed).map(\.unitID))
        if let progressActivity, progressActivity.completed {
            completedUnitIDs.insert(progressActivity.unitID)
        }

        if let currentIndex = unitIDs.firstIndex(of: latest.unitID),
           let nextUnitID = unitIDs.dropFirst(currentIndex + 1).first(where: {
               !completedUnitIDs.contains($0)
           }) {
            return MediaWatchTarget(unitID: nextUnitID, action: .next)
        }

        if let unfinishedUnitID = unitIDs.first(where: { !completedUnitIDs.contains($0) }) {
            return MediaWatchTarget(unitID: unfinishedUnitID, action: .next)
        }

        return MediaWatchTarget(unitID: firstUnitID, action: .rewatch)
    }

    private static func isEarlier(_ lhs: Activity, _ rhs: Activity) -> Bool {
        if lhs.updatedAt == rhs.updatedAt {
            return !lhs.isCurrentProgress && rhs.isCurrentProgress
        }
        return lhs.updatedAt < rhs.updatedAt
    }
}
