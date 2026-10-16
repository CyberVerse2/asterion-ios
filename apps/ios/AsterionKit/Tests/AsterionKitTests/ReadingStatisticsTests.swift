import Foundation
import Testing
@testable import AsterionKit

struct ReadingStatisticsTests {
    @Test
    func contentAlertsStartQuietlyAndOnlyReportIncreases() {
        #expect(ContentUpdatePolicy.newCount(current: 100, previous: nil) == nil)
        #expect(ContentUpdatePolicy.newCount(current: 103, previous: 100) == 3)
        #expect(ContentUpdatePolicy.newCount(current: 103, previous: 103) == nil)
        #expect(ContentUpdatePolicy.newCount(current: 90, previous: 103) == nil)
        #expect(ContentUpdatePolicy.nextBaseline(current: 90, previous: 103) == 103)
        #expect(ContentUpdatePolicy.newCount(current: 103,
            previous: ContentUpdatePolicy.nextBaseline(current: 90, previous: 103)) == nil)
    }

    @Test
    func weeklyGoalDeduplicatesCloudAndLocalChaptersAndStartsOnMonday() {
        let monday = isoDate("2026-10-05T10:00:00Z")
        let sunday = isoDate("2026-10-04T10:00:00Z")
        let stats = ReadingStatistics.calculate(
            days: [ReadingDayActivity(date: monday, seconds: 120, chapterIDs: ["novel/chapter"])],
            visits: [(monday, "novel/chapter"), (monday, "novel/other"), (sunday, "novel/old")],
            goal: 30, now: monday, timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(stats.weeklyChapters == 2)
        #expect(stats.todaySeconds == 120)
        #expect(stats.streak == 2)
    }

    @Test
    func streakRemainsActiveUntilTheNextDayEnds() {
        let now = isoDate("2026-10-05T10:00:00Z")
        let visits = [(isoDate("2026-10-04T10:00:00Z"), "one"), (isoDate("2026-10-03T10:00:00Z"), "two")]
        let stats = ReadingStatistics.calculate(days: [], visits: visits, goal: 1, now: now,
                                                 timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(stats.streak == 2)
        let broken = ReadingStatistics.calculate(days: [], visits: visits, goal: 1,
            now: isoDate("2026-10-06T10:00:00Z"), timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(broken.streak == 0)
    }

    @Test
    func streakHandlesDaylightSavingAndGoalsNeverOverfill() {
        let visits = ["2026-10-31T18:00:00Z", "2026-11-01T18:00:00Z", "2026-11-02T18:00:00Z"]
            .enumerated().map { (isoDate($0.element), "chapter-\($0.offset)") }
        let stats = ReadingStatistics.calculate(days: [], visits: visits, goal: 1,
            now: isoDate("2026-11-02T20:00:00Z"), timeZone: TimeZone(identifier: "America/New_York")!)
        #expect(stats.streak == 3)
        #expect(stats.goalFraction == 1)
    }
}
