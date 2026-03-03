import ActivityKit
import Foundation

@MainActor
final class DownloadLiveActivityManager {
    static let shared = DownloadLiveActivityManager()

    private var activity: Activity<ChapterDownloadActivityAttributes>?

    func start(novelTitle: String, total: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard #available(iOS 16.1, *) else { return }

        if let existing = activity {
            Task {
                await existing.end(
                    ActivityContent(
                        state: .init(completed: 0, total: max(total, 1), statusText: "Restarting"),
                        staleDate: nil
                    ),
                    dismissalPolicy: .immediate
                )
            }
        }

        do {
            let attrs = ChapterDownloadActivityAttributes(novelTitle: novelTitle)
            let state = ChapterDownloadActivityAttributes.ContentState(
                completed: 0,
                total: max(total, 1),
                statusText: "Preparing"
            )
            activity = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            activity = nil
        }
    }

    func update(completed: Int, total: Int) {
        guard #available(iOS 16.1, *) else { return }
        guard let activity else { return }
        let clampedCompleted = max(0, min(completed, max(total, 1)))
        let state = ChapterDownloadActivityAttributes.ContentState(
            completed: clampedCompleted,
            total: max(total, 1),
            statusText: "Downloading"
        )
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end(success: Bool, completed: Int, total: Int) {
        guard #available(iOS 16.1, *) else {
            activity = nil
            return
        }
        guard let activity else { return }
        let clampedCompleted = max(0, min(completed, max(total, 1)))
        let finalState = ChapterDownloadActivityAttributes.ContentState(
            completed: clampedCompleted,
            total: max(total, 1),
            statusText: success ? "Complete" : "Failed"
        )
        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .default
            )
        }
        self.activity = nil
    }
}
