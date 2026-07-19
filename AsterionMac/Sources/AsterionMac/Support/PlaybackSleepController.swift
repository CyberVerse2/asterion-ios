import Foundation

@MainActor
final class PlaybackSleepController {
    typealias BeginActivity = () -> any NSObjectProtocol
    typealias EndActivity = (any NSObjectProtocol) -> Void

    private let beginActivity: BeginActivity
    private let endActivity: EndActivity
    private var activeSources: Set<String> = []
    private var activity: (any NSObjectProtocol)?

    init(reason: String = "Asterion is playing video") {
        beginActivity = {
            ProcessInfo.processInfo.beginActivity(
                options: [
                    .userInitiated,
                    .idleDisplaySleepDisabled,
                    .idleSystemSleepDisabled,
                ],
                reason: reason
            )
        }
        endActivity = { activity in
            ProcessInfo.processInfo.endActivity(activity)
        }
    }

    init(
        beginActivity: @escaping BeginActivity,
        endActivity: @escaping EndActivity
    ) {
        self.beginActivity = beginActivity
        self.endActivity = endActivity
    }

    isolated deinit {
        if let activity {
            endActivity(activity)
        }
    }

    func setPlaying(_ isPlaying: Bool, sourceID: String) {
        if isPlaying {
            activeSources.insert(sourceID)
        } else {
            activeSources.remove(sourceID)
        }
        updateActivity()
    }

    func stopAll() {
        activeSources.removeAll()
        updateActivity()
    }

    private func updateActivity() {
        if activeSources.isEmpty {
            guard let activity else { return }
            self.activity = nil
            endActivity(activity)
        } else if activity == nil {
            activity = beginActivity()
        }
    }
}
