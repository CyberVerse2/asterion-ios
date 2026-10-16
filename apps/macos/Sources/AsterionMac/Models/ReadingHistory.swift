import Foundation

/// One chapter someone has read: the novel's History row, like an episode's.
struct ReadingHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    let novelID: String
    let chapterID: String
    var chapterNumber: Int?
    var chapterTitle: String?
    /// The novel's title and cover when the chapter was read, so the row
    /// survives a catalog that hasn't loaded. Synced rows arrive without them.
    var novelTitle: String?
    var coverURL: String?
    /// How far into the chapter the reader got, 0–100; nil for synced rows.
    var percentage: Double?
    var firstReadAt: Date
    var lastReadAt: Date

    var id: String { novelID + "\u{0}" + chapterID }
}

/// A `reading_history` row from the account API. The API writes one on every
/// progress save, so a chapter appears many times.
struct RemoteReadingHistoryRow: Decodable, Hashable, Sendable {
    let id: String
    let novelId: String
    let chapterId: String
    let visitedAt: Date
}

/// Account-wide reading stats from `/me/stats`.
struct RemoteReadingStats: Decodable, Equatable, Sendable {
    let chaptersRead: Int
}

/// Reading figures shown beside the watch stats on the profile.
struct ReadingActivityStats: Equatable, Sendable {
    var chaptersRead: Int
    var novelsFinished: Int
    var chaptersLast30Days: Int

    static let empty = ReadingActivityStats(chaptersRead: 0, novelsFinished: 0, chaptersLast30Days: 0)
}

enum ReadingHistory {
    /// The most chapters kept, newest first.
    static let limit = 2_000

    struct Visit: Equatable, Sendable {
        let novelID: String
        let chapterID: String
        let chapterNumber: Int?
        let chapterTitle: String?
        let novelTitle: String?
        let coverURL: String?
        let percentage: Double
        let readAt: Date
    }

    /// Records a visit to a chapter. Reading the same chapter again moves it
    /// to the top rather than adding a row; how far into it the reader got
    /// only ever grows.
    static func recording(_ visit: Visit, into entries: [ReadingHistoryEntry]) -> [ReadingHistoryEntry] {
        var result = entries
        let percentage = visit.percentage.isFinite ? min(100, max(0, visit.percentage)) : 0
        if let index = result.firstIndex(where: {
            $0.novelID == visit.novelID && $0.chapterID == visit.chapterID
        }) {
            var entry = result[index]
            entry.chapterNumber = visit.chapterNumber ?? entry.chapterNumber
            entry.chapterTitle = visit.chapterTitle ?? entry.chapterTitle
            entry.novelTitle = visit.novelTitle ?? entry.novelTitle
            entry.coverURL = visit.coverURL ?? entry.coverURL
            entry.percentage = max(entry.percentage ?? 0, percentage)
            entry.firstReadAt = min(entry.firstReadAt, visit.readAt)
            entry.lastReadAt = max(entry.lastReadAt, visit.readAt)
            result[index] = entry
        } else {
            result.append(
                ReadingHistoryEntry(
                    novelID: visit.novelID,
                    chapterID: visit.chapterID,
                    chapterNumber: visit.chapterNumber,
                    chapterTitle: visit.chapterTitle,
                    novelTitle: visit.novelTitle,
                    coverURL: visit.coverURL,
                    percentage: percentage,
                    firstReadAt: visit.readAt,
                    lastReadAt: visit.readAt
                )
            )
        }
        return trimmed(result)
    }

    /// Folds the account's history into this Mac's. Repeated rows for one
    /// chapter collapse into its entry, keeping the earliest and latest
    /// visits; local details such as the chapter number are never lost.
    static func merging(
        remote rows: [RemoteReadingHistoryRow],
        into entries: [ReadingHistoryEntry]
    ) -> [ReadingHistoryEntry] {
        var byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { lhs, _ in lhs })
        var order = entries.map(\.id)
        for row in rows {
            let id = row.novelId + "\u{0}" + row.chapterId
            if var entry = byID[id] {
                entry.firstReadAt = min(entry.firstReadAt, row.visitedAt)
                entry.lastReadAt = max(entry.lastReadAt, row.visitedAt)
                byID[id] = entry
            } else {
                byID[id] = ReadingHistoryEntry(
                    novelID: row.novelId,
                    chapterID: row.chapterId,
                    chapterNumber: nil,
                    chapterTitle: nil,
                    novelTitle: nil,
                    coverURL: nil,
                    percentage: nil,
                    firstReadAt: row.visitedAt,
                    lastReadAt: row.visitedAt
                )
                order.append(id)
            }
        }
        return trimmed(order.compactMap { byID[$0] })
    }

    /// Newest first, at most `limit`.
    static func trimmed(_ entries: [ReadingHistoryEntry]) -> [ReadingHistoryEntry] {
        Array(entries.sorted { $0.lastReadAt > $1.lastReadAt }.prefix(limit))
    }

    /// Chapters read counts every distinct chapter opened, as the account
    /// API does; the account's own count wins when it knows more, since this
    /// Mac only holds recent history from other devices.
    static func stats(
        entries: [ReadingHistoryEntry],
        novelsFinished: Int,
        accountChaptersRead: Int?,
        now: Date
    ) -> ReadingActivityStats {
        let cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let distinct = Set(entries.map(\.id)).count
        return ReadingActivityStats(
            chaptersRead: max(distinct, accountChaptersRead ?? 0),
            novelsFinished: novelsFinished,
            chaptersLast30Days: entries.count(where: { $0.lastReadAt >= cutoff })
        )
    }
}
