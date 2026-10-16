import Foundation

/// When listen mode should stop reading aloud.
public enum ListenSleepTimer: Hashable, Sendable {
    case minutes(Int)
    case endOfChapter

    /// The choices offered, in menu order.
    public static let choices: [ListenSleepTimer] = [
        .minutes(15), .minutes(30), .minutes(45), .minutes(60), .endOfChapter,
    ]

    public var title: String {
        switch self {
        case .minutes(60): "1 hour"
        case .minutes(let minutes): String(minutes) + " minutes"
        case .endOfChapter: "End of chapter"
        }
    }
}

/// A sleep timer that is set: the choice and, for a timed one, when it ends.
/// Times are wall-clock, so the countdown is right after the app was
/// suspended with the screen locked.
public struct ListenSleepSchedule: Hashable, Sendable {
    public let timer: ListenSleepTimer
    public let endsAt: Date?

    public init(_ timer: ListenSleepTimer, startingAt start: Date = Date()) {
        self.timer = timer
        switch timer {
        case .minutes(let minutes):
            endsAt = start.addingTimeInterval(TimeInterval(max(0, minutes)) * 60)
        case .endOfChapter:
            endsAt = nil
        }
    }

    /// Seconds left on a timed schedule (never negative); nil for end of chapter.
    public func remaining(at now: Date = Date()) -> TimeInterval? {
        endsAt.map { max(0, $0.timeIntervalSince(now)) }
    }

    /// Whether a timed schedule has run out.
    public func isDue(at now: Date = Date()) -> Bool {
        guard let endsAt else { return false }
        return now >= endsAt
    }

    /// Whether listening should stop when the current chapter ends.
    public var stopsAtChapterEnd: Bool { timer == .endOfChapter }

    /// Whole minutes left, rounded up, so a fresh 15 minute timer reads 15
    /// and the last seconds read 1. Nil for end of chapter.
    public func minutesLeft(at now: Date = Date()) -> Int? {
        remaining(at: now).map { Int(($0 / 60).rounded(.up)) }
    }

    /// The short countdown on the control ("12m"); nil for end of chapter.
    public func shortLabel(at now: Date = Date()) -> String? {
        minutesLeft(at: now).map { String($0) + "m" }
    }
}
