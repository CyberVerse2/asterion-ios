import Foundation
import Testing
@testable import AsterionMac

@Suite(.serialized)
struct NovelOfflineAndHistoryTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let day: TimeInterval = 24 * 60 * 60

    // MARK: Snapshots

    @Test func savedNovelsKeepTheirLastSnapshotWhenTheCatalogLacksThem() {
        let saved = NovelSnapshot(Self.novel("saved", title: "Old Title"), neededAt: Self.now - Self.day)
        let updated = NovelSnapshots.updated(
            ["saved": saved],
            neededIDs: ["saved", "reading"],
            catalog: { _ in nil },
            now: Self.now
        )

        #expect(updated["saved"]?.novel.title == "Old Title")
        #expect(updated["saved"]?.lastNeededAt == Self.now)
        // A novel never seen in the catalog has nothing to fall back on.
        #expect(updated["reading"] == nil)
    }

    @Test func catalogNovelsRefreshTheirSnapshot() {
        let stale = NovelSnapshot(Self.novel("a", title: "Old Title"), neededAt: Self.now - Self.day)
        let catalog = ["a": Self.novel("a", title: "New Title", cover: "https://example.com/a.jpg")]
        let updated = NovelSnapshots.updated(
            ["a": stale],
            neededIDs: ["a"],
            catalog: { catalog[$0] },
            now: Self.now
        )

        #expect(updated["a"]?.novel.title == "New Title")
        #expect(updated["a"]?.novel.imageURL == "https://example.com/a.jpg")
        #expect(NovelSnapshots.needsWrite(updated, over: ["a": stale]))
    }

    @Test func snapshotsNoLongerNeededSurviveUntilTheyExpire() {
        let recent = NovelSnapshot(Self.novel("recent"), neededAt: Self.now - 10 * Self.day)
        let expired = NovelSnapshot(
            Self.novel("expired"),
            neededAt: Self.now - NovelSnapshots.retention - Self.day
        )
        let updated = NovelSnapshots.updated(
            ["recent": recent, "expired": expired],
            neededIDs: [],
            catalog: { _ in nil },
            now: Self.now
        )

        #expect(Set(updated.keys) == ["recent"])
    }

    @Test func refreshingOnlyTheNeededDateWaitsADayBeforeWriting() {
        let saved = ["a": NovelSnapshot(Self.novel("a"), neededAt: Self.now)]
        let soon = NovelSnapshots.updated(saved, neededIDs: ["a"], catalog: { _ in nil }, now: Self.now + 60)
        let later = NovelSnapshots.updated(saved, neededIDs: ["a"], catalog: { _ in nil }, now: Self.now + 2 * Self.day)

        #expect(!NovelSnapshots.needsWrite(soon, over: saved))
        #expect(NovelSnapshots.needsWrite(later, over: saved))
    }

    @Test func snapshotsRoundTripThroughTheStore() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("snapshots.json")
        let store = NovelSnapshotStore(fileURL: fileURL)
        let snapshot = NovelSnapshot(
            Self.novel("a", title: "Kept", cover: "https://example.com/a.jpg"),
            neededAt: Self.now
        )

        try await store.save(["a": snapshot])
        let loaded = try await NovelSnapshotStore(fileURL: fileURL).load()

        #expect(loaded["a"]?.novel.title == "Kept")
        #expect(loaded["a"]?.novel.imageURL == "https://example.com/a.jpg")
        #expect(loaded["a"]?.novel.genres == ["Fantasy"])
    }

    // MARK: Reading history

    @Test func readingAChapterAgainMovesItToTheTopWithoutAddingARow() {
        var entries: [ReadingHistoryEntry] = []
        entries = ReadingHistory.recording(Self.visit("c1", number: 1, percentage: 80, at: Self.now), into: entries)
        entries = ReadingHistory.recording(Self.visit("c2", number: 2, percentage: 10, at: Self.now + 60), into: entries)
        entries = ReadingHistory.recording(Self.visit("c1", number: 1, percentage: 30, at: Self.now + 120), into: entries)

        #expect(entries.map(\.chapterID) == ["c1", "c2"])
        #expect(entries[0].lastReadAt == Self.now + 120)
        #expect(entries[0].firstReadAt == Self.now)
        // How far into the chapter only ever grows.
        #expect(entries[0].percentage == 80)
    }

    @Test func accountHistoryCollapsesRepeatedRowsIntoOneEntryPerChapter() {
        let local = ReadingHistory.recording(
            Self.visit("c1", number: 7, percentage: 100, at: Self.now),
            into: []
        )
        let rows = [
            Self.row("c1", at: Self.now + 300),
            Self.row("c1", at: Self.now - 300),
            Self.row("c9", at: Self.now + 100),
            Self.row("c9", at: Self.now + 200),
        ]

        let merged = ReadingHistory.merging(remote: rows, into: local)

        #expect(merged.map(\.chapterID) == ["c1", "c9"])
        #expect(merged[0].lastReadAt == Self.now + 300)
        #expect(merged[0].firstReadAt == Self.now - 300)
        // Details only this Mac knew are kept.
        #expect(merged[0].chapterNumber == 7)
        #expect(merged[0].percentage == 100)
        #expect(merged[1].firstReadAt == Self.now + 100)
        #expect(merged[1].lastReadAt == Self.now + 200)
        #expect(merged[1].chapterNumber == nil)
    }

    @Test func historyStatsPreferTheAccountCountWhenItKnowsMore() {
        let entries = [
            Self.visit("c1", number: 1, percentage: 100, at: Self.now - 40 * Self.day),
            Self.visit("c2", number: 2, percentage: 100, at: Self.now - Self.day),
        ].reduce(into: [ReadingHistoryEntry]()) { $0 = ReadingHistory.recording($1, into: $0) }

        let local = ReadingHistory.stats(entries: entries, novelsFinished: 1, accountChaptersRead: nil, now: Self.now)
        let account = ReadingHistory.stats(entries: entries, novelsFinished: 1, accountChaptersRead: 120, now: Self.now)

        #expect(local == ReadingActivityStats(chaptersRead: 2, novelsFinished: 1, chaptersLast30Days: 1))
        #expect(account.chaptersRead == 120)
    }

    @Test func historyStoreKeepsOwnersApartAndResolvesSyncedChapters() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReadingHistoryStore(fileURL: directory.appendingPathComponent("history.json"))

        try await store.record(ownerID: "device", visit: Self.visit("c1", number: 1, percentage: 50, at: Self.now))
        try await store.merge(ownerID: "user", remote: [Self.row("c5", at: Self.now)])
        try await store.resolveChapters(ownerID: "user", ["c5": (number: 5, title: "Five")])

        #expect(try await store.entries(ownerID: "device").map(\.chapterID) == ["c1"])
        let synced = try await store.entries(ownerID: "user")
        #expect(synced.map(\.chapterID) == ["c5"])
        #expect(synced.first?.chapterNumber == 5)
        #expect(synced.first?.chapterTitle == "Five")
    }

    // MARK: Download ranges

    @Test func presetsStartAtTheChapterBeingReadAndStopAtTheEnd() {
        #expect(NovelDownloadRange.range(for: .next10, currentChapter: 50, totalChapters: 300) == 50...59)
        #expect(NovelDownloadRange.range(for: .next100, currentChapter: 250, totalChapters: 300) == 250...300)
        #expect(NovelDownloadRange.range(for: .rest, currentChapter: 120, totalChapters: 300) == 120...300)
        #expect(NovelDownloadRange.range(for: .all, currentChapter: 120, totalChapters: 300) == 1...300)
        #expect(NovelDownloadRange.range(for: .next50, currentChapter: nil, totalChapters: 300) == 1...50)
        // A chapter past the count (a lagging count) still yields a range.
        #expect(NovelDownloadRange.range(for: .next10, currentChapter: 400, totalChapters: 300) == 300...300)
        #expect(NovelDownloadRange.range(for: .next10, currentChapter: 1, totalChapters: 0) == nil)
    }

    @Test func customRangesAreOrderedAndClampedToTheNovel() {
        #expect(NovelDownloadRange.custom(from: 80, to: 20, totalChapters: 300) == 20...80)
        #expect(NovelDownloadRange.custom(from: 0, to: 9_999, totalChapters: 300) == 1...300)
        #expect(NovelDownloadRange.custom(from: 400, to: 500, totalChapters: 300) == nil)
    }

    @Test func aRangeDownloadOnlyFetchesChaptersNotAlreadySaved() {
        let chapters = (1...10).reversed().map { Self.chapter(number: $0) }
        let saved = OfflineChapterSet([Self.chapter(number: 4), Self.chapter(number: 5)])

        let toFetch = NovelDownloadRange.chaptersToFetch(from: chapters, in: 3...7, excluding: saved)

        #expect(toFetch.map(\.chapterNumber) == [3, 6, 7])
        #expect(saved.count(in: 3...7) == 2)
        #expect(NovelDownloadRange.chaptersToFetch(from: chapters, in: nil, excluding: saved).count == 8)
    }

    @Test func savedChapterSummariesNameTheSpan() {
        #expect(OfflineChapterSet((1...40).map { Self.chapter(number: $0) }).summary == "Chapters 1–40")
        #expect(
            OfflineChapterSet([1, 2, 1_500].map { Self.chapter(number: $0) }).summary
                == "3 chapters · 1–1500"
        )
    }

    // MARK: Partial offline library

    @Test func addingChaptersKeepsEarlierOnesAndTracksWholeNovelCoverage() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OfflineLibraryStore(directory: directory)
        let novel = Self.novel("n")

        try await store.add(novel: novel, chapters: [Self.chapter(number: 1, content: "<p>One</p>")])
        try await store.add(novel: novel, chapters: [Self.chapter(number: 3, content: "<p>Three</p>")])

        #expect(try await store.chapters(for: "n")?.map(\.chapterNumber) == [1, 3])
        #expect(try await store.chapter(id: "chapter-1")?.paragraphs == ["One"])
        #expect(try await store.chapter(id: "chapter-3")?.paragraphs == ["Three"])
        #expect(try await store.downloadedItems().first?.coversWholeNovel == false)

        try await store.add(novel: novel, chapters: [], coversWholeNovel: true)
        let item = try await store.downloadedItems().first
        #expect(item?.coversWholeNovel == true)
        #expect(item?.chapterCount == 2)

        try await store.remove(novelID: "n")
        #expect(try await store.chapter(id: "chapter-1") == nil)
    }

    // MARK: Fixtures

    private static func novel(_ id: String, title: String? = nil, cover: String? = nil) -> Novel {
        Novel(
            id: id,
            title: title ?? "Novel \(id)",
            author: "Author",
            rank: "1",
            totalChapters: "300",
            views: "1000",
            bookmarks: nil,
            status: "Ongoing",
            genres: ["Fantasy"],
            summary: "A summary.",
            imageURL: cover,
            rating: 4.5
        )
    }

    private static func chapter(number: Int, content: String? = nil) -> Chapter {
        Chapter(id: "chapter-\(number)", chapterNumber: number, title: "Chapter \(number)", content: content, url: nil)
    }

    private static func visit(_ chapterID: String, number: Int, percentage: Double, at date: Date) -> ReadingHistory.Visit {
        ReadingHistory.Visit(
            novelID: "n",
            chapterID: chapterID,
            chapterNumber: number,
            chapterTitle: nil,
            novelTitle: "Novel",
            coverURL: nil,
            percentage: percentage,
            readAt: date
        )
    }

    private static func row(_ chapterID: String, at date: Date) -> RemoteReadingHistoryRow {
        RemoteReadingHistoryRow(id: UUID().uuidString, novelId: "n", chapterId: chapterID, visitedAt: date)
    }

    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
