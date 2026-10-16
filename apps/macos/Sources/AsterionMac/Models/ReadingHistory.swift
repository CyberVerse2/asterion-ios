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
    /// The latest read and furthest progress the account is known to hold
    /// for this chapter: what this Mac uploaded, or what the account sent.
    /// The entry needs uploading while it is ahead of these; nil (rows
    /// recorded before history synced) uploads once.
    var syncedReadAt: Date?
    var syncedPercentage: Double?

    var id: String { novelID + "\u{0}" + chapterID }
}

/// A `reading_history` row from the account API: one per chapter, holding
/// its latest read on any device. Older API builds wrote a row per progress
/// save and had no chapter details, so a chapter may still repeat.
struct RemoteReadingHistoryRow: Decodable, Hashable, Sendable {
    let id: String
    let novelId: String
    let chapterId: String
    let visitedAt: Date
    /// When the account first saw the chapter read.
    var createdAt: Date? = nil
    var chapterNumber: Int? = nil
    var chapterTitle: String? = nil
    /// 0–100.
    var progress: Double? = nil
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
    /// The most entries one `POST /me/history` call carries.
    static let uploadBatchLimit = 200

    /// One chapter read, as `POST /me/history` takes it.
    struct Upload: Encodable, Equatable, Sendable {
        let novelId: String
        let chapterId: String
        let chapterNumber: Int?
        let chapterTitle: String?
        let readAt: Date
        /// 0–100.
        let progress: Double

        private enum CodingKeys: String, CodingKey {
            case novelId, chapterId, chapterNumber, chapterTitle, readAt, progress
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(novelId, forKey: .novelId)
            try container.encode(chapterId, forKey: .chapterId)
            try container.encodeIfPresent(chapterNumber, forKey: .chapterNumber)
            try container.encodeIfPresent(chapterTitle, forKey: .chapterTitle)
            try container.encode(readAt.formatted(Self.timestampStyle), forKey: .readAt)
            try container.encode(progress, forKey: .progress)
        }

        private static let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    }

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
        let percentage = clampedPercentage(visit.percentage)
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
    /// visits and the furthest progress; local details such as the chapter
    /// number are never lost. Whatever the account sent counts as synced, so
    /// it is not uploaded back.
    static func merging(
        remote rows: [RemoteReadingHistoryRow],
        into entries: [ReadingHistoryEntry]
    ) -> [ReadingHistoryEntry] {
        var byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { lhs, _ in lhs })
        var order = entries.map(\.id)
        for row in rows {
            let id = row.novelId + "\u{0}" + row.chapterId
            let progress = row.progress.map(clampedPercentage)
            let firstReadAt = min(row.createdAt ?? row.visitedAt, row.visitedAt)
            if var entry = byID[id] {
                entry.firstReadAt = min(entry.firstReadAt, firstReadAt)
                entry.lastReadAt = max(entry.lastReadAt, row.visitedAt)
                entry.chapterNumber = entry.chapterNumber ?? row.chapterNumber
                entry.chapterTitle = entry.chapterTitle ?? row.chapterTitle
                if let progress {
                    entry.percentage = max(entry.percentage ?? 0, progress)
                    entry.syncedPercentage = max(entry.syncedPercentage ?? 0, progress)
                }
                entry.syncedReadAt = max(entry.syncedReadAt ?? .distantPast, row.visitedAt)
                byID[id] = entry
            } else {
                byID[id] = ReadingHistoryEntry(
                    novelID: row.novelId,
                    chapterID: row.chapterId,
                    chapterNumber: row.chapterNumber,
                    chapterTitle: row.chapterTitle,
                    novelTitle: nil,
                    coverURL: nil,
                    percentage: progress,
                    firstReadAt: firstReadAt,
                    lastReadAt: row.visitedAt,
                    syncedReadAt: row.visitedAt,
                    syncedPercentage: progress
                )
                order.append(id)
            }
        }
        return trimmed(order.compactMap { byID[$0] })
    }

    // MARK: Upload

    /// How long to wait before retrying an upload that failed `failures`
    /// times in a row: 5 s, doubling, at most 5 minutes.
    static func uploadRetryDelay(afterFailures failures: Int) -> Duration {
        let seconds = 5 * pow(2, Double(min(max(0, failures), 6)))
        return .seconds(min(300, seconds))
    }

    /// Whether the entry holds a read or progress the account hasn't seen.
    /// Rows the API would reject (blank or oversized ids, impossible dates)
    /// never upload, so they can't hold up the rest of a batch.
    static func needsUpload(_ entry: ReadingHistoryEntry) -> Bool {
        guard isUploadable(entry) else { return false }
        guard let syncedReadAt = entry.syncedReadAt else { return true }
        return entry.lastReadAt > syncedReadAt
            || (entry.percentage ?? 0) > (entry.syncedPercentage ?? 0)
    }

    /// The next batch to send, newest first so recent reading reaches other
    /// devices soonest.
    static func pendingUploads(
        in entries: [ReadingHistoryEntry],
        limit: Int = uploadBatchLimit
    ) -> [Upload] {
        Array(
            entries
                .filter(needsUpload)
                .sorted { $0.lastReadAt > $1.lastReadAt }
                .prefix(max(0, limit))
                .map(upload(for:))
        )
    }

    /// Records that the account now holds `uploads`. A read made while the
    /// batch was in flight is newer than what was sent, so it stays pending.
    static func markingUploaded(
        _ uploads: [Upload],
        in entries: [ReadingHistoryEntry]
    ) -> [ReadingHistoryEntry] {
        let sent = Dictionary(
            uploads.map { ($0.novelId + "\u{0}" + $0.chapterId, $0) },
            uniquingKeysWith: { lhs, rhs in lhs.readAt >= rhs.readAt ? lhs : rhs }
        )
        return entries.map { entry in
            guard let upload = sent[entry.id] else { return entry }
            var marked = entry
            marked.syncedReadAt = max(entry.syncedReadAt ?? .distantPast, upload.readAt)
            marked.syncedPercentage = max(entry.syncedPercentage ?? 0, upload.progress)
            return marked
        }
    }

    private static let earliestUploadDate = Date(timeIntervalSince1970: 946_684_800) // 2000-01-01

    private static func isUploadable(_ entry: ReadingHistoryEntry) -> Bool {
        func valid(_ id: String) -> Bool {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed == id && id.count <= 500
        }
        return valid(entry.novelID) && valid(entry.chapterID) && entry.lastReadAt >= earliestUploadDate
    }

    private static func upload(for entry: ReadingHistoryEntry) -> Upload {
        let title = entry.chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Upload(
            novelId: entry.novelID,
            chapterId: entry.chapterID,
            chapterNumber: entry.chapterNumber.flatMap { $0 >= 0 ? $0 : nil },
            chapterTitle: title.flatMap { $0.isEmpty ? nil : String($0.prefix(500)) },
            readAt: entry.lastReadAt,
            progress: clampedPercentage(entry.percentage ?? 0)
        )
    }

    private static func clampedPercentage(_ value: Double) -> Double {
        value.isFinite ? min(100, max(0, value)) : 0
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
