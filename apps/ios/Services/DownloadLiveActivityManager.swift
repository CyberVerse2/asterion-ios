import Foundation
import UIKit

#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
import ActivityKit

@MainActor
final class DownloadLiveActivityManager {
    static let shared = DownloadLiveActivityManager()

    private var activity: Activity<ChapterDownloadActivityAttributes>?

    func start(novelTitle: String, novelImageURL: String?, total: Int) async {
        guard #available(iOS 16.1, *) else {
            debugLog("Live Activities unavailable on this iOS version.")
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            debugLog("Live Activities are disabled by system/user settings.")
            return
        }

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
            debugLog("Ended existing live activity before starting a new one.")
        }

        let normalizedURL = normalizedImageURLString(novelImageURL)
        let artwork = await LiveActivityImage.artwork(from: normalizedURL, maxBytes: 3200)
        let imageData = artwork.data
        let state = ChapterDownloadActivityAttributes.ContentState(
            completed: 0,
            total: max(total, 1),
            statusText: "Preparing"
        )

        do {
            let attrs = ChapterDownloadActivityAttributes(
                novelTitle: novelTitle,
                novelImageURL: normalizedURL,
                novelImageData: imageData,
                tint: artwork.tint
            )
            activity = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            debugLog("Started live activity. imageDataBytes=\(imageData?.count ?? 0)")
        } catch {
            debugLog("Live activity start failed with image payload: \(String(describing: error))")
            do {
                let fallbackAttrs = ChapterDownloadActivityAttributes(
                    novelTitle: novelTitle,
                    novelImageURL: normalizedURL,
                    novelImageData: nil,
                    tint: artwork.tint
                )
                activity = try Activity.request(
                    attributes: fallbackAttrs,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
                debugLog("Started live activity using URL-only fallback.")
            } catch {
                activity = nil
                debugLog("Live activity fallback start also failed: \(String(describing: error))")
            }
        }
    }

    private func normalizedImageURLString(_ raw: String?) -> String? {
        LiveActivityImage.normalizedURLString(raw)
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

    private func debugLog(_ message: String) {
        print("[LiveActivity] \(message)")
    }
}

@MainActor
final class ReadingLiveActivityManager {
    static let shared = ReadingLiveActivityManager()

    private var activity: Activity<ReadingSessionActivityAttributes>?

    func startOrUpdate(
        novelTitle: String,
        chapterTitle: String,
        currentLine: Int,
        totalLines: Int,
        minutesLeft: Int? = nil
    ) async {
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = ReadingSessionActivityAttributes.ContentState(
            chapterTitle: chapterTitle,
            currentLine: max(0, currentLine),
            totalLines: max(totalLines, 1),
            minutesLeft: minutesLeft
        )

        if let activity, activity.activityState == .active {
            await activity.update(ActivityContent(state: state, staleDate: nil))
            return
        }

        do {
            activity = try Activity.request(
                attributes: ReadingSessionActivityAttributes(novelTitle: novelTitle),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            #if DEBUG
            print("[ReadingLiveActivity] Failed to start: \(error.localizedDescription)")
            #endif
        }
    }

    func end() async {
        guard #available(iOS 16.1, *) else {
            activity = nil
            return
        }
        guard let activity else { return }
        let finalState = activity.content.state
        await activity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: .immediate
        )
        self.activity = nil
    }
}
/// Shared image helpers: Live Activities cannot load remote images, so a
/// tiny JPEG travels inside the attributes (the whole payload must stay
/// under ActivityKit's 4 KB limit).
private enum LiveActivityImage {
    static func normalizedURLString(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("//") {
            value = "https:\(value)"
        } else if !value.contains("://") {
            value = "https://\(value)"
        } else if value.hasPrefix("http://") {
            value = value.replacingOccurrences(of: "http://", with: "https://")
        }

        if let components = URLComponents(string: value), let url = components.url {
            return url.absoluteString
        }

        let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        return encoded
    }

    static func tinyThumbnail(from normalizedURL: String?, maxBytes: Int, maxSide: CGFloat = 64) async -> Data? {
        await artwork(from: normalizedURL, maxBytes: maxBytes, maxSide: maxSide).data
    }

    /// The cover thumbnail plus the colour it casts, sampled with the same
    /// artwork-glow logic the app's pages use.
    static func artwork(
        from normalizedURL: String?,
        maxBytes: Int,
        maxSide: CGFloat = 64
    ) async -> (data: Data?, tint: ActivityTint?) {
        guard let normalizedURL, let url = URL(string: normalizedURL) else { return (nil, nil) }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              !data.isEmpty else {
            return (nil, nil)
        }
        let tint = ArtworkTone.extract(from: data).map {
            ActivityTint(red: $0.red, green: $0.green, blue: $0.blue)
        }
        return (thumbnail(from: data, maxBytes: maxBytes, maxSide: maxSide), tint)
    }

    private static func thumbnail(from data: Data, maxBytes: Int, maxSide: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(maxSide / max(image.size.width, 1), maxSide / max(image.size.height, 1), 1)
        let targetSize = CGSize(
            width: max(1, floor(image.size.width * scale)),
            height: max(1, floor(image.size.height * scale))
        )
        let reduced = UIGraphicsImageRenderer(size: targetSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        for quality in [0.65, 0.45, 0.3, 0.2, 0.12] {
            if let candidate = reduced.jpegData(compressionQuality: quality), candidate.count <= maxBytes {
                return candidate
            }
        }
        return nil
    }

}

/// The film or episode playing in the native player, on the Lock Screen and
/// in the Dynamic Island. The player pushes every change; nothing ticks on
/// its own.
@MainActor
final class WatchingLiveActivityManager {
    static let shared = WatchingLiveActivityManager()

    private var activity: Activity<WatchingActivityAttributes>?
    private var lastState: WatchingActivityAttributes.ContentState?
    private var activityID: String?
    /// Bumped on every start/end so a slow start cannot resurrect an
    /// activity the player already ended.
    private var generation = 0

    /// If the app dies mid-film the activity dims instead of claiming to play.
    private static let staleAfter: TimeInterval = 5 * 60

    /// Starts the activity for `id` (the playback request id). Restarting
    /// the same item (a stream switch, a retry) only updates it; anything
    /// else, including activities left over from a crash, is ended first.
    func start(
        id: String,
        title: String,
        mediaType: String,
        imageURL: String?,
        unitLabel: String,
        positionSeconds: Double,
        durationSeconds: Double,
        isPlaying: Bool
    ) async {
        if let activity, activityID == id, activity.activityState == .active || activity.activityState == .stale {
            update(positionSeconds: positionSeconds, durationSeconds: durationSeconds, isPlaying: isPlaying)
            return
        }
        generation += 1
        let token = generation
        let leftovers = Activity<WatchingActivityAttributes>.activities
        activity = nil
        lastState = nil
        activityID = nil
        for leftover in leftovers {
            await leftover.end(nil, dismissalPolicy: .immediate)
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let normalizedURL = LiveActivityImage.normalizedURLString(imageURL)
        let artwork = await LiveActivityImage.artwork(from: normalizedURL, maxBytes: 2800)
        let imageData = artwork.data
        guard token == generation else { return }

        let state = WatchingActivityAttributes.ContentState(
            unitLabel: unitLabel,
            positionSeconds: max(0, positionSeconds),
            durationSeconds: max(0, durationSeconds),
            isPlaying: isPlaying
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(Self.staleAfter))
        var candidates = [
            WatchingActivityAttributes(title: title, mediaType: mediaType, imageURL: normalizedURL, imageData: nil, tint: artwork.tint),
        ]
        if imageData != nil {
            // Try with the thumbnail first; fall back if the payload is refused.
            candidates.insert(
                WatchingActivityAttributes(title: title, mediaType: mediaType, imageURL: normalizedURL, imageData: imageData, tint: artwork.tint),
                at: 0
            )
        }
        for attributes in candidates {
            do {
                activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
                lastState = state
                activityID = id
                return
            } catch {
                #if DEBUG
                print("[WatchingLiveActivity] Failed to start: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func update(positionSeconds: Double, durationSeconds: Double, isPlaying: Bool) {
        guard let activity, let lastState else { return }
        let state = WatchingActivityAttributes.ContentState(
            unitLabel: lastState.unitLabel,
            positionSeconds: max(0, positionSeconds),
            durationSeconds: durationSeconds > 0 ? durationSeconds : lastState.durationSeconds,
            isPlaying: isPlaying
        )
        guard state != lastState else { return }
        self.lastState = state
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(Self.staleAfter))
        Task { await activity.update(content) }
    }

    func end() {
        generation += 1
        let ending = Activity<WatchingActivityAttributes>.activities
        activity = nil
        lastState = nil
        activityID = nil
        guard !ending.isEmpty else { return }
        Task {
            for activity in ending {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}

/// A followed football match: a kickoff countdown that turns LIVE at kickoff
/// (via `staleDate`) and leaves about two and a half hours later.
@MainActor
final class MatchLiveActivityManager {
    static let shared = MatchLiveActivityManager()

    enum FollowResult {
        case following
        case activitiesDisabled
        /// Live Activities last at most eight hours, so following opens
        /// eight hours before kickoff.
        case tooEarly(opensAt: Date)
        case finished
        case failed
    }

    static let followWindow: TimeInterval = 8 * 60 * 60
    static let matchLength: TimeInterval = 2.5 * 60 * 60

    private var autoEndTasks: [String: Task<Void, Never>] = [:]

    func isFollowing(matchID: String) -> Bool {
        endExpired()
        return activities(for: matchID).contains { $0.activityState == .active || $0.activityState == .stale }
    }

    func follow(
        matchID: String,
        home: String,
        away: String,
        competition: String,
        kickoff: Date,
        isLive: Bool,
        homeBadgeURL: String?,
        awayBadgeURL: String?
    ) -> FollowResult {
        endExpired()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return .activitiesDisabled }
        let now = Date()
        let endsAt = kickoff.addingTimeInterval(Self.matchLength)
        if !isLive, now >= endsAt { return .finished }
        if !isLive, kickoff.timeIntervalSince(now) > Self.followWindow {
            return .tooEarly(opensAt: kickoff.addingTimeInterval(-Self.followWindow))
        }

        if !activities(for: matchID).isEmpty {
            update(matchID: matchID, isLive: isLive)
            return .following
        }

        let attributes = MatchActivityAttributes(
            matchID: matchID,
            home: home,
            away: away,
            competition: competition,
            kickoff: kickoff,
            homeBadgeURL: homeBadgeURL,
            awayBadgeURL: awayBadgeURL
        )
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content(isLive: isLive, kickoff: kickoff),
                pushType: nil
            )
            scheduleAutoEnd(for: activity, at: isLive ? max(endsAt, now.addingTimeInterval(Self.matchLength)) : endsAt)
            return .following
        } catch {
            #if DEBUG
            print("[MatchLiveActivity] Failed to start: \(error.localizedDescription)")
            #endif
            return .failed
        }
    }

    /// Mark the match as in play (e.g. the detail screen saw `isLive`).
    func update(matchID: String, isLive: Bool) {
        for activity in activities(for: matchID) where activity.content.state.isLive != isLive {
            let content = content(isLive: isLive, kickoff: activity.attributes.kickoff)
            Task { await activity.update(content) }
        }
    }

    func unfollow(matchID: String) {
        autoEndTasks[matchID]?.cancel()
        autoEndTasks[matchID] = nil
        let ending = activities(for: matchID)
        Task {
            for activity in ending {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Ends every followed match whose kickoff was more than ~2.5 hours ago.
    /// Cheap; safe to call whenever the app becomes active.
    func endExpired() {
        let now = Date()
        for activity in Activity<MatchActivityAttributes>.activities
        where now >= activity.attributes.kickoff.addingTimeInterval(Self.matchLength) {
            autoEndTasks[activity.attributes.matchID]?.cancel()
            autoEndTasks[activity.attributes.matchID] = nil
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func activities(for matchID: String) -> [Activity<MatchActivityAttributes>] {
        Activity<MatchActivityAttributes>.activities.filter {
            $0.attributes.matchID == matchID && $0.activityState != .ended && $0.activityState != .dismissed
        }
    }

    private func content(isLive: Bool, kickoff: Date) -> ActivityContent<MatchActivityAttributes.ContentState> {
        // Going stale at kickoff is what flips the countdown to LIVE while
        // the app is not running.
        ActivityContent(
            state: .init(isLive: isLive),
            staleDate: !isLive && kickoff > Date() ? kickoff : nil,
            relevanceScore: isLive ? 80 : 50
        )
    }

    /// Works while the app stays alive; `endExpired()` covers the rest, and
    /// the system ends any Live Activity after eight hours regardless.
    private func scheduleAutoEnd(for activity: Activity<MatchActivityAttributes>, at date: Date) {
        let matchID = activity.attributes.matchID
        autoEndTasks[matchID]?.cancel()
        autoEndTasks[matchID] = Task { [weak self] in
            let delay = max(0, date.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await activity.end(nil, dismissalPolicy: .immediate)
            self?.autoEndTasks[matchID] = nil
        }
    }
}
#else
@MainActor
final class DownloadLiveActivityManager {
    static let shared = DownloadLiveActivityManager()

    func start(novelTitle: String, novelImageURL: String?, total: Int) async {}
    func update(completed: Int, total: Int) {}
    func end(success: Bool, completed: Int, total: Int) {}
}

@MainActor
final class ReadingLiveActivityManager {
    static let shared = ReadingLiveActivityManager()

    func startOrUpdate(
        novelTitle: String,
        chapterTitle: String,
        currentLine: Int,
        totalLines: Int,
        minutesLeft: Int? = nil
    ) async {}

    func end() async {}
}

@MainActor
final class WatchingLiveActivityManager {
    static let shared = WatchingLiveActivityManager()

    func start(
        id: String,
        title: String,
        mediaType: String,
        imageURL: String?,
        unitLabel: String,
        positionSeconds: Double,
        durationSeconds: Double,
        isPlaying: Bool
    ) async {}
    func update(positionSeconds: Double, durationSeconds: Double, isPlaying: Bool) {}
    func end() {}
}

@MainActor
final class MatchLiveActivityManager {
    static let shared = MatchLiveActivityManager()

    enum FollowResult {
        case following
        case activitiesDisabled
        case tooEarly(opensAt: Date)
        case finished
        case failed
    }

    func isFollowing(matchID: String) -> Bool { false }
    func follow(
        matchID: String,
        home: String,
        away: String,
        competition: String,
        kickoff: Date,
        isLive: Bool,
        homeBadgeURL: String?,
        awayBadgeURL: String?
    ) -> FollowResult { .activitiesDisabled }
    func update(matchID: String, isLive: Bool) {}
    func unfollow(matchID: String) {}
    func endExpired() {}
}
#endif
