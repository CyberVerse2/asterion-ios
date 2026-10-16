import Foundation

/// One chapter someone has read, on this device or (once synced) any other.
public struct ReadingHistoryEntry: Codable, Hashable, Identifiable, Sendable {
    public let novelId: String
    public let chapterId: String
    public var chapterNumber: Int?
    public var chapterTitle: String?
    /// How far into the chapter the reader got, 0–100. Only ever grows.
    public var progress: Double
    public var firstReadAt: Date
    public var lastReadAt: Date
    /// The latest read and furthest progress the account is known to hold:
    /// what this device uploaded, or what the account sent. The entry needs
    /// uploading while it is ahead of these.
    public var syncedReadAt: Date?
    public var syncedProgress: Double?

    public init(
        novelId: String,
        chapterId: String,
        chapterNumber: Int? = nil,
        chapterTitle: String? = nil,
        progress: Double = 0,
        firstReadAt: Date,
        lastReadAt: Date,
        syncedReadAt: Date? = nil,
        syncedProgress: Double? = nil
    ) {
        self.novelId = novelId
        self.chapterId = chapterId
        self.chapterNumber = chapterNumber
        self.chapterTitle = chapterTitle
        self.progress = progress
        self.firstReadAt = firstReadAt
        self.lastReadAt = lastReadAt
        self.syncedReadAt = syncedReadAt
        self.syncedProgress = syncedProgress
    }

    /// "novel/chapter", the key reading activity uses for chapters.
    public var id: String { ReadingHistoryLedger.key(novelId: novelId, chapterId: chapterId) }

    /// Whether the entry holds a read or progress the account hasn't seen.
    /// Rows the API would reject never upload, so they can't hold up a batch.
    public var needsUpload: Bool {
        guard ReadingHistoryLedger.isUploadable(self) else { return false }
        guard let syncedReadAt else { return true }
        return lastReadAt > syncedReadAt || progress > (syncedProgress ?? 0)
    }
}

/// A `reading_history` row from the account (`GET /me/history`): one per
/// chapter with its latest read on any device. Older API builds wrote a row
/// per progress save without chapter details, so a chapter may repeat.
public struct RemoteReadingHistoryRecord: Equatable, Sendable {
    public let novelId: String
    public let chapterId: String
    public let visitedAt: Date
    /// When the account first saw the chapter read.
    public let firstReadAt: Date?
    public let chapterNumber: Int?
    public let chapterTitle: String?
    public let progress: Double?

    public init(
        novelId: String,
        chapterId: String,
        visitedAt: Date,
        firstReadAt: Date? = nil,
        chapterNumber: Int? = nil,
        chapterTitle: String? = nil,
        progress: Double? = nil
    ) {
        self.novelId = novelId
        self.chapterId = chapterId
        self.visitedAt = visitedAt
        self.firstReadAt = firstReadAt
        self.chapterNumber = chapterNumber
        self.chapterTitle = chapterTitle
        self.progress = progress
    }
}

/// One chapter read, as `POST /me/history` takes it.
public struct ReadingHistoryUpload: Encodable, Equatable, Sendable {
    public let novelId: String
    public let chapterId: String
    public let chapterNumber: Int?
    public let chapterTitle: String?
    public let readAt: Date
    /// 0–100.
    public let progress: Double

    public init(novelId: String, chapterId: String, chapterNumber: Int?, chapterTitle: String?,
                readAt: Date, progress: Double) {
        self.novelId = novelId
        self.chapterId = chapterId
        self.chapterNumber = chapterNumber
        self.chapterTitle = chapterTitle
        self.readAt = readAt
        self.progress = progress
    }

    private enum CodingKeys: String, CodingKey {
        case novelId, chapterId, chapterNumber, chapterTitle, readAt, progress
    }

    public func encode(to encoder: any Encoder) throws {
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

/// The chapters read by one owner (an account, or the guest), newest first,
/// and which of them the account hasn't seen yet. The ledger is the upload
/// queue: an entry stays pending until an upload covering its latest read
/// and progress succeeds, so reading offline loses nothing.
public struct ReadingHistoryLedger: Codable, Hashable, Sendable {
    /// The most chapters kept. Older chapters the account already holds are
    /// dropped first; chapters still waiting to upload are kept up to
    /// `pendingLimit`.
    public static let limit = 5_000
    public static let pendingLimit = 10_000
    /// The most entries one `POST /me/history` call carries.
    public static let uploadBatchLimit = 200
    /// Saves within this long of the chapter's last read only refresh it
    /// when they move its progress, so scrolling doesn't rewrite History.
    public static let revisitInterval: TimeInterval = 60

    /// Newest first.
    public private(set) var entries: [ReadingHistoryEntry]

    public init(entries: [ReadingHistoryEntry] = []) {
        self.entries = entries
        normalize()
    }

    public var isEmpty: Bool { entries.isEmpty }

    public var pendingCount: Int { entries.count(where: \.needsUpload) }

    public func entry(novelId: String, chapterId: String) -> ReadingHistoryEntry? {
        let key = Self.key(novelId: novelId, chapterId: chapterId)
        return entries.first { $0.id == key }
    }

    // MARK: Reading here

    /// Records reading a chapter. Reading it again moves it to the top
    /// rather than adding a row, and its progress only ever grows. Returns
    /// whether anything changed.
    @discardableResult
    public mutating func record(
        novelId: String,
        chapterId: String,
        chapterNumber: Int? = nil,
        chapterTitle: String? = nil,
        progress: Double,
        at date: Date = Date()
    ) -> Bool {
        let progress = Self.clamped(progress)
        let number = chapterNumber.flatMap { $0 > 0 ? $0 : nil }
        let title = chapterTitle.flatMap { $0.isEmpty ? nil : $0 }
        let key = Self.key(novelId: novelId, chapterId: chapterId)
        guard let index = entries.firstIndex(where: { $0.id == key }) else {
            entries.append(ReadingHistoryEntry(
                novelId: novelId, chapterId: chapterId, chapterNumber: number, chapterTitle: title,
                progress: progress, firstReadAt: date, lastReadAt: date
            ))
            normalize()
            return true
        }
        var entry = entries[index]
        let before = entry
        entry.chapterNumber = number ?? entry.chapterNumber
        entry.chapterTitle = title ?? entry.chapterTitle
        entry.progress = max(entry.progress, progress)
        entry.firstReadAt = min(entry.firstReadAt, date)
        let isRevisit = date.timeIntervalSince(entry.lastReadAt) >= Self.revisitInterval
        if date > entry.lastReadAt, isRevisit || entry.progress > before.progress {
            entry.lastReadAt = date
        }
        guard entry != before else { return false }
        entries[index] = entry
        normalize()
        return true
    }

    // MARK: Account sync

    /// Folds the account's history in. Repeated rows for a chapter collapse
    /// into its entry, keeping the earliest and latest reads and the
    /// furthest progress; details only this device knew are kept. Whatever
    /// the account sent counts as synced, so it isn't uploaded back.
    public mutating func merge(remote rows: [RemoteReadingHistoryRecord]) {
        guard !rows.isEmpty else { return }
        var indexByKey = Dictionary(entries.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        for row in rows {
            let key = Self.key(novelId: row.novelId, chapterId: row.chapterId)
            let progress = row.progress.map(Self.clamped)
            let firstReadAt = min(row.firstReadAt ?? row.visitedAt, row.visitedAt)
            if let index = indexByKey[key] {
                var entry = entries[index]
                entry.firstReadAt = min(entry.firstReadAt, firstReadAt)
                entry.lastReadAt = max(entry.lastReadAt, row.visitedAt)
                entry.chapterNumber = entry.chapterNumber ?? row.chapterNumber.flatMap { $0 > 0 ? $0 : nil }
                entry.chapterTitle = entry.chapterTitle ?? row.chapterTitle
                if let progress {
                    entry.progress = max(entry.progress, progress)
                    entry.syncedProgress = max(entry.syncedProgress ?? 0, progress)
                }
                entry.syncedReadAt = max(entry.syncedReadAt ?? .distantPast, row.visitedAt)
                entries[index] = entry
            } else {
                indexByKey[key] = entries.count
                entries.append(ReadingHistoryEntry(
                    novelId: row.novelId,
                    chapterId: row.chapterId,
                    chapterNumber: row.chapterNumber.flatMap { $0 > 0 ? $0 : nil },
                    chapterTitle: row.chapterTitle,
                    progress: progress ?? 0,
                    firstReadAt: firstReadAt,
                    lastReadAt: row.visitedAt,
                    syncedReadAt: row.visitedAt,
                    syncedProgress: progress
                ))
            }
        }
        normalize()
    }

    /// The next batch to send, newest first so recent reading reaches other
    /// devices soonest.
    public func pendingUploads(limit: Int = uploadBatchLimit) -> [ReadingHistoryUpload] {
        Array(entries.lazy.filter(\.needsUpload).prefix(max(0, limit))).map { entry in
            let title = entry.chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ReadingHistoryUpload(
                novelId: entry.novelId,
                chapterId: entry.chapterId,
                chapterNumber: entry.chapterNumber,
                chapterTitle: title.flatMap { $0.isEmpty ? nil : String($0.prefix(500)) },
                readAt: entry.lastReadAt,
                progress: entry.progress
            )
        }
    }

    /// Records that the account now holds `uploads`. A read made while the
    /// batch was in flight is newer than what was sent, so it stays pending.
    public mutating func markUploaded(_ uploads: [ReadingHistoryUpload]) {
        guard !uploads.isEmpty else { return }
        let sent = Dictionary(
            uploads.map { (Self.key(novelId: $0.novelId, chapterId: $0.chapterId), $0) },
            uniquingKeysWith: { lhs, rhs in lhs.readAt >= rhs.readAt ? lhs : rhs }
        )
        for index in entries.indices {
            guard let upload = sent[entries[index].id] else { continue }
            entries[index].syncedReadAt = max(entries[index].syncedReadAt ?? .distantPast, upload.readAt)
            entries[index].syncedProgress = max(entries[index].syncedProgress ?? 0, upload.progress)
        }
        normalize()
    }

    /// Moves a guest's reading into this (account) ledger, queued for upload,
    /// so nothing read before sign-in is lost.
    public mutating func adopt(guest: ReadingHistoryLedger) {
        for entry in guest.entries {
            let key = entry.id
            if let index = entries.firstIndex(where: { $0.id == key }) {
                var merged = entries[index]
                merged.firstReadAt = min(merged.firstReadAt, entry.firstReadAt)
                merged.lastReadAt = max(merged.lastReadAt, entry.lastReadAt)
                merged.progress = max(merged.progress, entry.progress)
                merged.chapterNumber = merged.chapterNumber ?? entry.chapterNumber
                merged.chapterTitle = merged.chapterTitle ?? entry.chapterTitle
                entries[index] = merged
            } else {
                var adopted = entry
                adopted.syncedReadAt = nil
                adopted.syncedProgress = nil
                entries.append(adopted)
            }
        }
        normalize()
    }

    // MARK: Statistics

    /// One (date, "novel/chapter") per first and latest read, for
    /// `ReadingStatistics`: both days count toward the streak, and the
    /// chapter key dedupes the weekly goal.
    public var visits: [(Date, String)] {
        entries.flatMap { entry -> [(Date, String)] in
            entry.firstReadAt == entry.lastReadAt
                ? [(entry.lastReadAt, entry.id)]
                : [(entry.firstReadAt, entry.id), (entry.lastReadAt, entry.id)]
        }
    }

    /// Distinct chapters read: the account's count when it knows more, since
    /// this device may only hold part of the account's history.
    public func chaptersRead(accountCount: Int?) -> Int {
        max(entries.count, accountCount ?? 0)
    }

    /// Distinct chapters read per novel.
    public var chapterIdsByNovel: [String: Set<String>] {
        entries.reduce(into: [:]) { $0[$1.novelId, default: []].insert($1.chapterId) }
    }

    // MARK: Retry

    /// How long to wait before retrying an upload that failed `failures`
    /// times in a row: 5 s, doubling, at most 5 minutes.
    public static func uploadRetryDelay(afterFailures failures: Int) -> TimeInterval {
        min(300, 5 * pow(2, Double(min(max(0, failures), 6))))
    }

    // MARK: Helpers

    public static func key(novelId: String, chapterId: String) -> String {
        "\(novelId)/\(chapterId)"
    }

    private static let earliestUploadDate = Date(timeIntervalSince1970: 946_684_800) // 2000-01-01

    static func isUploadable(_ entry: ReadingHistoryEntry) -> Bool {
        func valid(_ id: String) -> Bool {
            !id.isEmpty && id.count <= 500
                && id.trimmingCharacters(in: .whitespacesAndNewlines) == id
                // Local imports ("offline-…") aren't catalog chapters.
                && !id.hasPrefix("offline-")
        }
        return valid(entry.novelId) && valid(entry.chapterId) && entry.lastReadAt >= earliestUploadDate
    }

    private static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(100, max(0, value)) : 0
    }

    /// Newest first, one entry per chapter, trimmed to the limits.
    private mutating func normalize() {
        entries.sort {
            if $0.lastReadAt == $1.lastReadAt { return $0.id < $1.id }
            return $0.lastReadAt > $1.lastReadAt
        }
        guard entries.count > Self.limit else { return }
        var kept: [ReadingHistoryEntry] = []
        var synced = 0
        for entry in entries {
            if entry.needsUpload {
                if kept.count < Self.pendingLimit { kept.append(entry) }
            } else if synced < Self.limit, kept.count < Self.pendingLimit {
                synced += 1
                kept.append(entry)
            }
        }
        // Drop the oldest synced rows until the total fits.
        while kept.count > Self.limit, let index = kept.lastIndex(where: { !$0.needsUpload }) {
            kept.remove(at: index)
        }
        entries = kept
    }
}
