import Foundation

/// A local "match starts soon" notification, scheduled on the device from the fixture time.
public enum KickoffReminder {
    /// How long before kickoff the reminder fires.
    public static let leadTime: TimeInterval = 15 * 60
    /// Matches closer to kickoff than this are not worth a reminder.
    public static let minimumNotice: TimeInterval = 60

    public static let matchIDKey = "asterionMatchID"
    public static let kickoffKey = "asterionMatchKickoff"

    public static func identifier(matchID: String) -> String { "asterion.match.\(matchID)" }

    /// When to remind for a match kicking off at `kickoff`, or nil once it is too late. Inside
    /// the lead time the reminder fires almost at once instead of being skipped.
    public static func fireDate(kickoff: Date, now: Date = .now) -> Date? {
        guard kickoff.timeIntervalSince(now) > minimumNotice else { return nil }
        return max(kickoff.addingTimeInterval(-leadTime), now.addingTimeInterval(5))
    }

    /// "Kicks off in 15 minutes" for a reminder firing at `fireDate`.
    public static func body(kickoff: Date, fireDate: Date) -> String {
        let minutes = max(1, Int((kickoff.timeIntervalSince(fireDate) / 60).rounded()))
        return "Kicks off in \(minutes) minute\(minutes == 1 ? "" : "s")"
    }

    /// Whether a pending reminder scheduled for `scheduledKickoff` should be moved because the
    /// fixture now says `kickoff`.
    public static func needsReschedule(scheduledKickoff: Date?, kickoff: Date) -> Bool {
        guard let scheduledKickoff else { return true }
        return abs(scheduledKickoff.timeIntervalSince(kickoff)) >= 60
    }
}
