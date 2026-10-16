import Foundation

public struct ReadingDayActivity: Codable, Equatable, Sendable {
    public let date: Date
    public var seconds: Double
    public var chapterIDs: Set<String>

    public init(date: Date, seconds: Double, chapterIDs: Set<String>) {
        self.date = date
        self.seconds = seconds
        self.chapterIDs = chapterIDs
    }
}

public struct ReadingStatistics: Equatable, Sendable {
    public let weeklyChapters: Int
    public let todaySeconds: Double
    public let weeklySeconds: Double
    public let streak: Int
    public let goal: Int
    public var goalFraction: Double { min(1, Double(weeklyChapters) / Double(max(1, goal))) }

    public init(weeklyChapters: Int, todaySeconds: Double, weeklySeconds: Double, streak: Int, goal: Int) {
        self.weeklyChapters = weeklyChapters
        self.todaySeconds = todaySeconds
        self.weeklySeconds = weeklySeconds
        self.streak = streak
        self.goal = goal
    }

    public static func calculate(days: [ReadingDayActivity], visits: [(Date, String)], goal: Int,
                                 now: Date = .now, timeZone: TimeZone = .current) -> ReadingStatistics {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)!
        var activeDays = Set<Date>()
        var weeklyChapters = Set<String>()
        var todaySeconds = 0.0
        var weeklySeconds = 0.0
        for day in days where day.date <= now {
            let date = calendar.startOfDay(for: day.date)
            if day.seconds > 0 || !day.chapterIDs.isEmpty { activeDays.insert(date) }
            if date == today { todaySeconds += day.seconds }
            if date >= week.start && date < week.end {
                weeklySeconds += day.seconds
                weeklyChapters.formUnion(day.chapterIDs)
            }
        }
        for (date, id) in visits where date <= now {
            activeDays.insert(calendar.startOfDay(for: date))
            if date >= week.start && date < week.end { weeklyChapters.insert(id) }
        }
        var cursor = today
        if !activeDays.contains(cursor) { cursor = calendar.date(byAdding: .day, value: -1, to: cursor)! }
        var streak = 0
        while activeDays.contains(cursor) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return ReadingStatistics(weeklyChapters: weeklyChapters.count, todaySeconds: todaySeconds,
                                 weeklySeconds: weeklySeconds, streak: streak, goal: max(1, goal))
    }
}
