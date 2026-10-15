import Foundation
import Testing
@testable import Asterion

@MainActor
struct ReaderFeatureTests {
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
        let monday = date("2026-10-05T10:00:00Z")
        let sunday = date("2026-10-04T10:00:00Z")
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
        let now = date("2026-10-05T10:00:00Z")
        let visits = [(date("2026-10-04T10:00:00Z"), "one"), (date("2026-10-03T10:00:00Z"), "two")]
        let stats = ReadingStatistics.calculate(days: [], visits: visits, goal: 1, now: now,
                                                 timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(stats.streak == 2)
        let broken = ReadingStatistics.calculate(days: [], visits: visits, goal: 1,
            now: date("2026-10-06T10:00:00Z"), timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(broken.streak == 0)
    }

    @Test
    func streakHandlesDaylightSavingAndGoalsNeverOverfill() {
        let visits = ["2026-10-31T18:00:00Z", "2026-11-01T18:00:00Z", "2026-11-02T18:00:00Z"]
            .enumerated().map { (date($0.element), "chapter-\($0.offset)") }
        let stats = ReadingStatistics.calculate(days: [], visits: visits, goal: 1,
            now: date("2026-11-02T20:00:00Z"), timeZone: TimeZone(identifier: "America/New_York")!)
        #expect(stats.streak == 3)
        #expect(stats.goalFraction == 1)
    }

    @Test
    func readingTimePersistsAndStaysWithTheRightAccount() {
        let suite = "ReaderFeatureTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = ReadingActivityService(defaults: defaults)
        service.setUser("one")
        service.record(novelID: "novel", chapterID: "chapter", seconds: 15)
        service.record(novelID: "novel", chapterID: "chapter", seconds: 15)
        let restored = ReadingActivityService(defaults: defaults)
        restored.setUser("one")
        #expect(restored.days.reduce(0) { $0 + $1.seconds } == 30)
        #expect(restored.days.flatMap(\.chapterIDs).count == 1)
        restored.setUser("two")
        #expect(restored.days.isEmpty)
        restored.record(novelID: "novel", chapterID: "chapter", seconds: -10)
        #expect(restored.days.isEmpty)
    }

    @Test
    func downloadedChapterOpensFromItsFileWithOriginalIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineChapterStore(baseDirectory: root.appendingPathComponent("cache"),
                                        documentsDirectory: root.appendingPathComponent("documents"))
        let novel = sampleNovel()
        let chapter = Chapter(id: "chapter-id", chapterNumber: 12, title: "Chapter 12: The Gate",
                              content: "A real chapter body.", url: nil)
        _ = try await store.saveDownloadedChapter(novelTitle: novel.title, chapterNumber: 12,
            chapterTitle: chapter.title, content: "\(novel.title)\nChapter 12: The Gate\n\nA real chapter body.",
            novel: novel, chapter: chapter)
        let collections = await store.downloadedCollections()
        let collection = try #require(collections.first)
        #expect(collection.novel.id == novel.id)
        #expect(collection.chapterCount == 1)
        let loaded = try store.downloadedChapter(collection.chapters[0])
        #expect(loaded.id == "chapter-id")
        #expect(loaded.plainContent == "A real chapter body.")
    }

    @Test
    func legacyDownloadsStillOpenAndUseCachedChapterIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineChapterStore(baseDirectory: root.appendingPathComponent("cache"), documentsDirectory: root)
        let novel = sampleNovel()
        let chapter = Chapter(id: "legacy-id", chapterNumber: 2, title: "Chapter 2: Arrival", content: nil, url: nil)
        await store.saveCatalog([novel])
        await store.saveChapterList(novelId: novel.id, chapters: [chapter])
        _ = try await store.saveDownloadedChapter(novelTitle: novel.title, chapterNumber: 2,
            chapterTitle: chapter.title, content: "\(novel.title)\nChapter 2: Arrival\n\nLegacy body.")
        let collection = try #require(await store.downloadedCollections().first)
        let loaded = try store.downloadedChapter(collection.chapters[0])
        #expect(loaded.id == "legacy-id")
        #expect(loaded.plainContent == "Legacy body.")
    }

    @Test
    func downloadsRemainReadableWhenTheAppContainerMoves() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("old")
        let new = root.appendingPathComponent("new")
        let store = OfflineChapterStore(baseDirectory: root.appendingPathComponent("cache"), documentsDirectory: old)
        let novel = sampleNovel()
        let chapter = Chapter(id: "id", chapterNumber: 1, title: "Chapter 1: Start", content: nil, url: nil)
        _ = try await store.saveDownloadedChapter(novelTitle: novel.title, chapterNumber: 1,
            chapterTitle: chapter.title, content: "\(novel.title)\nChapter 1: Start\n\nBody.", novel: novel, chapter: chapter)
        await store.flushDownloadedManifests()
        try FileManager.default.moveItem(at: old, to: new)
        let relocated = OfflineChapterStore(baseDirectory: root.appendingPathComponent("cache"), documentsDirectory: new)
        let collection = try #require(await relocated.downloadedCollections().first)
        #expect(collection.novel.id == novel.id)
        #expect(collection.chapters[0].id == "id")
        #expect(try relocated.downloadedChapter(collection.chapters[0]).plainContent == "Body.")
    }

    @Test
    func legacyOfflineChaptersKeepTheirPositionWithoutUploadingSyntheticIDs() {
        let suite = "ReaderFeatureTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = ReadingProgressService(defaults: defaults)
        service.updateProgress(novelId: "offline-novel", chapterId: "offline-chapter",
                               currentLine: 42, totalLines: 100, syncToCloud: false)
        #expect(service.pendingSyncCount == 0)
        let restored = ReadingProgressService(defaults: defaults)
        #expect(restored.localProgress.first?.currentLine == 42)
    }

    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private func sampleNovel() -> Novel {
        Novel(id: "novel-id", title: "The Novel", author: nil, rank: nil, totalChapters: "100",
              views: nil, bookmarks: nil, status: nil, genres: nil, summary: nil, imageUrl: nil, rating: nil)
    }
}
