import Foundation
import Testing
@testable import AsterionKit

struct ReadingHistoryLedgerTests {
    private let t0 = isoDate("2026-10-12T10:00:00Z") // a Monday

    @Test
    func readingAChapterAgainMovesItToTheTopAndProgressOnlyGrows() {
        var ledger = ReadingHistoryLedger()
        ledger.record(novelId: "n", chapterId: "c1", chapterNumber: 1, chapterTitle: "One", progress: 80, at: t0)
        ledger.record(novelId: "n", chapterId: "c2", chapterNumber: 2, progress: 10, at: t0 + 120)
        ledger.record(novelId: "n", chapterId: "c1", progress: 30, at: t0 + 240)

        #expect(ledger.entries.map(\.chapterId) == ["c1", "c2"])
        let first = ledger.entries[0]
        #expect(first.lastReadAt == t0 + 240)
        #expect(first.firstReadAt == t0)
        #expect(first.progress == 80)
        #expect(first.chapterNumber == 1)
        #expect(first.chapterTitle == "One")
    }

    @Test
    func scrollingWithinAMinuteOnlyChangesHistoryWhenProgressMoves() {
        var ledger = ReadingHistoryLedger()
        func record(_ progress: Double, after seconds: TimeInterval) -> Bool {
            ledger.record(novelId: "n", chapterId: "c1", progress: progress, at: t0 + seconds)
        }
        #expect(record(10, after: 0))
        #expect(!record(10, after: 20))
        #expect(!record(5, after: 30))
        #expect(record(20, after: 40))
        #expect(ledger.entries[0].lastReadAt == t0 + 40)
        #expect(record(20, after: 200))
        #expect(ledger.entries[0].lastReadAt == t0 + 200)
    }

    @Test
    func chaptersReadHereUploadNewestFirstAndClearOnceSent() {
        var ledger = ReadingHistoryLedger()
        ledger.record(novelId: "n", chapterId: "c1", chapterNumber: 1, chapterTitle: "  One  ", progress: 40, at: t0)
        ledger.record(novelId: "n", chapterId: "c2", progress: 10, at: t0 + 60)

        let batch = ledger.pendingUploads()
        #expect(batch.map(\.chapterId) == ["c2", "c1"])
        #expect(batch[1] == ReadingHistoryUpload(novelId: "n", chapterId: "c1", chapterNumber: 1,
                                                 chapterTitle: "One", readAt: t0, progress: 40))
        #expect(ledger.pendingUploads(limit: 1).map(\.chapterId) == ["c2"])

        // Read further while the batch was in flight: that read stays pending.
        ledger.record(novelId: "n", chapterId: "c1", progress: 90, at: t0 + 30)
        ledger.markUploaded(batch)
        #expect(ledger.pendingUploads().map { "\($0.chapterId):\($0.progress)" } == ["c1:90.0"])
        ledger.markUploaded(ledger.pendingUploads())
        #expect(ledger.pendingUploads().isEmpty)
        #expect(ledger.pendingCount == 0)
    }

    @Test
    func accountRowsMergeAsSyncedAndKeepWhatOnlyThisDeviceKnew() {
        var ledger = ReadingHistoryLedger()
        ledger.record(novelId: "n", chapterId: "c1", chapterTitle: "Mine", progress: 80, at: t0)
        ledger.merge(remote: [
            RemoteReadingHistoryRecord(novelId: "n", chapterId: "c1", visitedAt: t0 + 300,
                                       firstReadAt: t0 - 300, chapterNumber: 12, chapterTitle: "Theirs", progress: 30),
            // An older API repeats a chapter per progress save, without details.
            RemoteReadingHistoryRecord(novelId: "n", chapterId: "c9", visitedAt: t0 + 100),
            RemoteReadingHistoryRecord(novelId: "n", chapterId: "c9", visitedAt: t0 + 200),
        ])

        #expect(ledger.entries.map(\.chapterId) == ["c1", "c9"])
        let first = ledger.entries[0]
        #expect(first.firstReadAt == t0 - 300)
        #expect(first.lastReadAt == t0 + 300)
        #expect(first.chapterNumber == 12)
        #expect(first.chapterTitle == "Mine")
        #expect(first.progress == 80)
        let other = ledger.entries[1]
        #expect(other.firstReadAt == t0 + 100)
        #expect(other.lastReadAt == t0 + 200)

        // Only this device's 80% (ahead of the account's 30%) goes back up.
        #expect(ledger.pendingUploads().map { "\($0.chapterId):\($0.progress)" } == ["c1:80.0"])
    }

    @Test
    func rowsTheAccountWouldRejectAndLocalImportsNeverUpload() {
        var ledger = ReadingHistoryLedger()
        ledger.record(novelId: "offline-abc", chapterId: "offline-1", progress: 10, at: t0)
        ledger.record(novelId: "n", chapterId: String(repeating: "x", count: 501), progress: 10, at: t0)
        ledger.record(novelId: "n", chapterId: "ancient", progress: 10, at: Date(timeIntervalSince1970: 0))
        ledger.record(novelId: "n", chapterId: "ok", progress: 10, at: t0)
        #expect(ledger.pendingUploads().map(\.chapterId) == ["ok"])
    }

    @Test
    func guestReadingJoinsTheAccountQueuedForUpload() {
        var guest = ReadingHistoryLedger()
        guest.record(novelId: "n", chapterId: "c1", progress: 100, at: t0)
        guest.record(novelId: "n", chapterId: "c2", progress: 50, at: t0 + 60)
        var account = ReadingHistoryLedger()
        account.merge(remote: [RemoteReadingHistoryRecord(novelId: "n", chapterId: "c2", visitedAt: t0 + 600, progress: 20)])

        account.adopt(guest: guest)

        #expect(account.entries.map(\.chapterId) == ["c2", "c1"])
        #expect(account.entries[0].progress == 50)
        #expect(Set(account.pendingUploads().map(\.chapterId)) == ["c1", "c2"])
    }

    @Test
    func uploadsEncodeTheContractTheAPIValidates() throws {
        let upload = ReadingHistoryUpload(novelId: "n", chapterId: "c", chapterNumber: nil, chapterTitle: nil,
                                          readAt: t0.addingTimeInterval(0.25), progress: 42.5)
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(upload)) as? [String: Any])
        #expect(object["readAt"] as? String == "2026-10-12T10:00:00.250Z")
        #expect(object["progress"] as? Double == 42.5)
        #expect(Set(object.keys) == ["novelId", "chapterId", "readAt", "progress"])
    }

    @Test
    func historyFeedsTheWeeklyGoalStreakAndChapterCountsWithoutDoubleCounting() {
        var ledger = ReadingHistoryLedger()
        let utc = TimeZone(secondsFromGMT: 0)!
        // Started on Sunday on one device, finished on Monday on another.
        ledger.merge(remote: [RemoteReadingHistoryRecord(novelId: "n", chapterId: "c1", visitedAt: t0,
                                                         firstReadAt: t0 - 86_400, progress: 100)])
        ledger.record(novelId: "n", chapterId: "c1", progress: 100, at: t0 + 3_600)
        ledger.record(novelId: "n", chapterId: "c2", progress: 40, at: t0 + 7_200)
        ledger.record(novelId: "m", chapterId: "c1", progress: 40, at: t0 + 7_200)

        let days = [ReadingDayActivity(date: t0, seconds: 600, chapterIDs: ["n/c1"])]
        let stats = ReadingStatistics.calculate(days: days, visits: ledger.visits, goal: 5, now: t0 + 8_000, timeZone: utc)
        #expect(stats.weeklyChapters == 3)
        #expect(stats.streak == 2)
        #expect(ledger.chaptersRead(accountCount: nil) == 3)
        #expect(ledger.chaptersRead(accountCount: 120) == 120)
        #expect(ledger.chapterIdsByNovel == ["n": ["c1", "c2"], "m": ["c1"]])
    }

    @Test
    func trimmingDropsOldSyncedChaptersBeforeAnyStillWaitingToUpload() {
        var ledger = ReadingHistoryLedger()
        let synced = (0..<ReadingHistoryLedger.limit).map {
            RemoteReadingHistoryRecord(novelId: "n", chapterId: "s\($0)", visitedAt: t0 + Double($0))
        }
        ledger.merge(remote: synced)
        // An old chapter read offline long ago, still waiting to upload.
        ledger.record(novelId: "n", chapterId: "read-long-ago", progress: 10, at: t0 - 86_400)

        #expect(ledger.entries.count == ReadingHistoryLedger.limit)
        #expect(ledger.entry(novelId: "n", chapterId: "read-long-ago") != nil)
        #expect(ledger.entry(novelId: "n", chapterId: "s0") == nil)
    }

    @Test
    func retriesBackOffToFiveMinutes() {
        #expect(ReadingHistoryLedger.uploadRetryDelay(afterFailures: 0) == 5)
        #expect(ReadingHistoryLedger.uploadRetryDelay(afterFailures: 2) == 20)
        #expect(ReadingHistoryLedger.uploadRetryDelay(afterFailures: 40) == 300)
        #expect(ReadingHistoryUploadError(httpStatus: 400) == .rejected)
        #expect(ReadingHistoryUploadError(httpStatus: 401) == .unauthorized)
        #expect(ReadingHistoryUploadError(httpStatus: 404) == .retryLater)
        #expect(ReadingHistoryUploadError(httpStatus: 503) == .retryLater)
    }

    @Test
    func ledgersPersistPerOwner() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReadingHistoryFileStore(directory: directory)
        var ledger = ReadingHistoryLedger()
        ledger.record(novelId: "n", chapterId: "c1", chapterNumber: 3, progress: 50, at: t0)
        store.save(ledger, ownerID: "user_1")

        #expect(store.load(ownerID: "user_1") == ledger)
        #expect(store.load(ownerID: "guest").isEmpty)
        #expect(store.load(ownerID: "../escape").isEmpty)
        store.remove(ownerID: "user_1")
        #expect(store.load(ownerID: "user_1").isEmpty)
    }
}

@MainActor
struct ReadingHistorySyncTests {
    private let t0 = isoDate("2026-10-12T10:00:00Z")

    private func sync(chapters count: Int) -> ReadingHistorySync {
        var ledger = ReadingHistoryLedger()
        for index in 0..<count {
            ledger.record(novelId: "n", chapterId: "c\(index)", progress: 10, at: t0 + Double(index))
        }
        return ReadingHistorySync(ledger: ledger)
    }

    @Test
    func flushSendsEverythingInBatchesAndPersistsTheMarks() async {
        let sync = sync(chapters: 450)
        var saves = 0
        sync.onChange = { _ in saves += 1 }
        var batches: [[ReadingHistoryUpload]] = []

        let outcome = await sync.flush { batches.append($0) }

        #expect(outcome == .finished(uploaded: 450))
        #expect(batches.map(\.count) == [200, 200, 50])
        #expect(Set(batches.flatMap { $0.map(\.chapterId) }).count == 450)
        #expect(sync.ledger.pendingCount == 0)
        #expect(saves == 3)
        #expect(await sync.flush { batches.append($0) } == .finished(uploaded: 0))
        #expect(batches.count == 3)
    }

    @Test
    func failuresKeepRowsAndRejectedBatchesAreDropped() async {
        let sync = sync(chapters: 1)
        #expect(await sync.flush { _ in throw URLError(.notConnectedToInternet) } == .retryLater)
        #expect(await sync.flush { _ in throw ReadingHistoryUploadError(httpStatus: 404) } == .retryLater)
        #expect(await sync.flush { _ in throw ReadingHistoryUploadError.unauthorized } == .unauthorized)
        #expect(sync.ledger.pendingCount == 1)

        var attempts = 0
        #expect(await sync.flush { _ in attempts += 1; throw ReadingHistoryUploadError.rejected } == .finished(uploaded: 1))
        #expect(await sync.flush { _ in attempts += 1 } == .finished(uploaded: 0))
        #expect(attempts == 1)
        // The chapter stays in History.
        #expect(sync.ledger.entries.count == 1)
    }

    @Test
    func overlappingFlushesNeverSendARowTwiceAndPickUpNewReading() async {
        let sync = sync(chapters: 1)
        var sent: [[String]] = []
        var release: CheckedContinuation<Void, Never>?
        let upload: ReadingHistorySync.Upload = { batch in
            sent.append(batch.map(\.chapterId))
            if sent.count == 1 { await withCheckedContinuation { release = $0 } }
        }

        let first = Task { await sync.flush(using: upload) }
        while release == nil { await Task.yield() }
        sync.update { $0.record(novelId: "n", chapterId: "new", progress: 10, at: t0 + 100) }
        let second = Task { await sync.flush(using: upload) }
        await Task.yield()
        release?.resume()

        #expect(await first.value == .finished(uploaded: 2))
        #expect(await second.value == .finished(uploaded: 2))
        #expect(sent == [["c0"], ["new"]])
        #expect(sync.ledger.pendingCount == 0)
    }

    @Test
    func switchingAccountsMidFlushNeverMarksTheNewOwnersRows() async {
        let sync = sync(chapters: 1)
        var release: CheckedContinuation<Void, Never>?
        let first = Task {
            await sync.flush { _ in await withCheckedContinuation { release = $0 } }
        }
        while release == nil { await Task.yield() }

        var other = ReadingHistoryLedger()
        other.record(novelId: "n", chapterId: "c0", progress: 10, at: t0)
        sync.load(other)
        release?.resume()

        #expect(await first.value == .cancelled)
        #expect(sync.ledger.pendingCount == 1)
        var sent = 0
        #expect(await sync.flush { sent += $0.count } == .finished(uploaded: 1))
        #expect(sent == 1)
    }
}
