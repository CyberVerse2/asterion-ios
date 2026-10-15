import Combine
import Foundation

struct ReadingDayActivity: Codable, Equatable {
    let date: Date
    var seconds: Double
    var chapterIDs: Set<String>
}

struct ReadingStatistics: Equatable {
    let weeklyChapters: Int
    let todaySeconds: Double
    let weeklySeconds: Double
    let streak: Int
    let goal: Int
    var goalFraction: Double { min(1, Double(weeklyChapters) / Double(max(1, goal))) }

    static func calculate(days: [ReadingDayActivity], visits: [(Date, String)], goal: Int,
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

@MainActor
final class ReadingActivityService: ObservableObject {
    @Published private(set) var days: [ReadingDayActivity] = []
    private let defaults: UserDefaults
    private var storageKey = "asterion.reading.activity.guest"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
    }

    func setUser(_ userID: String?) {
        let key = "asterion.reading.activity.\(userID ?? "guest")"
        guard key != storageKey else { return }
        storageKey = key
        restore()
    }

    func record(novelID: String, chapterID: String, seconds: Double, endingAt date: Date = .now) {
        guard seconds > 0, seconds.isFinite else { return }
        // Divide intervals at local midnight so today's time and streak stay accurate.
        let calendar = Calendar.current
        var start = date.addingTimeInterval(-min(seconds, 60))
        while start < date {
            let day = calendar.startOfDay(for: start)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
            let end = min(date, nextDay)
            if let index = days.firstIndex(where: { $0.date == day }) {
                days[index].seconds += end.timeIntervalSince(start)
                days[index].chapterIDs.insert("\(novelID)/\(chapterID)")
            } else {
                days.append(ReadingDayActivity(date: day, seconds: end.timeIntervalSince(start),
                                               chapterIDs: ["\(novelID)/\(chapterID)"]))
            }
            start = end
        }
        if let data = try? JSONEncoder().encode(days) { defaults.set(data, forKey: storageKey) }
    }

    func summary(history: [AsterionReadingHistoryEntry], goal: Int, now: Date = .now) -> ReadingStatistics {
        let visits = history.compactMap { entry -> (Date, String)? in
            guard let date = entry.visitedAt ?? entry.createdAt else { return nil }
            return (date, "\(entry.novelId)/\(entry.chapterId)")
        }
        return ReadingStatistics.calculate(days: days, visits: visits, goal: goal, now: now)
    }

    private func restore() {
        days = defaults.data(forKey: storageKey).flatMap {
            try? JSONDecoder().decode([ReadingDayActivity].self, from: $0)
        } ?? []
    }
}
