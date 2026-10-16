import AsterionKit
import Combine
import Foundation

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
