import Foundation
import Testing
@testable import AsterionKit

struct NovelProgressTests {
    @Test
    func wholeNovelFractionCombinesChapterAndInChapterPosition() {
        let progress = NovelProgress(chapterNumber: 1929, totalChapters: 3171, chapterPercentage: 50)
        #expect(abs(progress.fraction - (1928.5 / 3171)) < 0.000_001)
        #expect(progress.displayPercentage == 60)
        #expect(progress.knowsWholeNovel)
        #expect(!progress.isFinished)

        let start = NovelProgress(chapterNumber: 1, totalChapters: 10, chapterPercentage: 0)
        #expect(start.fraction == 0)
        #expect(start.displayPercentage == 0)
    }

    @Test
    func labelNamesTheChapterWithoutThousandsSeparators() {
        #expect(NovelProgress(chapterNumber: 1929, totalChapters: 3171, chapterPercentage: 8).label == "Ch. 1929 of 3171")
        #expect(NovelProgress(chapterNumber: 1929, totalChapters: 3171, chapterPercentage: 8).longLabel
            == "Chapter 1929 of 3171")
        #expect(NovelProgress(chapterNumber: 1929, totalChapters: nil, chapterPercentage: 8).label == "Ch. 1929")
        #expect(NovelProgress(chapterNumber: 0, totalChapters: 3171, chapterPercentage: 8).label == nil)
        #expect(NovelProgress(chapterNumber: nil, totalChapters: 3171, chapterPercentage: 8).label == nil)
    }

    @Test
    func unknownTotalFallsBackToTheInChapterPosition() {
        let noTotal = NovelProgress(chapterNumber: 12, totalChapters: nil, chapterPercentage: 42)
        #expect(abs(noTotal.fraction - 0.42) < 0.000_001)
        #expect(!noTotal.knowsWholeNovel)
        #expect(!noTotal.isFinished)

        let noChapter = NovelProgress(chapterNumber: nil, totalChapters: 100, chapterPercentage: 30)
        #expect(abs(noChapter.fraction - 0.3) < 0.000_001)
        #expect(!noChapter.isFinished)
    }

    @Test
    func finishedMeansTheLastChapterAtLeastNinetyFivePercentIn() {
        #expect(NovelProgress(chapterNumber: 3171, totalChapters: 3171, chapterPercentage: 95).isFinished)
        #expect(NovelProgress(chapterNumber: 3171, totalChapters: 3171, chapterPercentage: 100).fraction == 1)
        #expect(NovelProgress(chapterNumber: 3171, totalChapters: 3171, chapterPercentage: 100).displayPercentage == 100)
        #expect(!NovelProgress(chapterNumber: 3171, totalChapters: 3171, chapterPercentage: 94).isFinished)
        #expect(!NovelProgress(chapterNumber: 3170, totalChapters: 3171, chapterPercentage: 100).isFinished)
        // Nearly done but not finished never rounds up to 100%.
        #expect(NovelProgress(chapterNumber: 3171, totalChapters: 3171, chapterPercentage: 90).displayPercentage == 99)
    }

    @Test
    func aChapterPastALaggingCountBoundsTheTotal() {
        let progress = NovelProgress(chapterNumber: 3172, totalChapters: 3171, chapterPercentage: 20)
        #expect(progress.label == "Ch. 3172 of 3172")
        #expect(progress.fraction <= 1)
        #expect(!progress.isFinished)
    }

    @Test
    func chapterCountPrefersLoadedThenCatalogText() {
        #expect(NovelProgress.totalChapters(loaded: 3172, catalog: "3171") == 3172)
        #expect(NovelProgress.totalChapters(loaded: nil, catalog: "3,171") == 3171)
        #expect(NovelProgress.totalChapters(loaded: 0, catalog: "3171 chapters") == 3171)
        #expect(NovelProgress.totalChapters(loaded: nil, catalog: nil) == nil)
        #expect(NovelProgress.totalChapters(loaded: nil, catalog: "ongoing") == nil)
    }

    @Test
    func savedProgressCountsTheLastParagraphAsTheWholeChapter() {
        func saved(line: Int, of total: Int) -> ReadingProgress {
            ReadingProgress(
                id: "p", userId: "u", novelId: "n", chapterId: "c",
                currentLine: line, totalLines: total,
                percentage: Double(line) / Double(total) * 100, updatedAt: nil
            )
        }
        let atEnd = NovelProgress(progress: saved(line: 39, of: 40), chapterNumber: 10, totalChapters: 10)
        #expect(atEnd.chapterPercentage == 100)
        #expect(atEnd.isFinished)

        let midway = NovelProgress(progress: saved(line: 10, of: 40), chapterNumber: 10, totalChapters: 10)
        #expect(midway.chapterPercentage == 25)
        #expect(!midway.isFinished)

        // A one-line placeholder (the widget snapshot fallback) is not "read to the end".
        let placeholder = NovelProgress(progress: saved(line: 0, of: 1), chapterNumber: 10, totalChapters: 10)
        #expect(placeholder.chapterPercentage == 0)
    }

    @Test
    func snapshotsReportWholeNovelProgressAndDecodeOldOnes() throws {
        let snapshot = ContinueReadingSnapshot(
            novelId: "n", novelTitle: "Novel", chapterId: "c", chapterTitle: "Chapter 1929",
            chapterNumber: 1929, progress: 1928.5 / 3171, chapterProgress: 0.5, totalChapters: 3171,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        #expect(snapshot.novelProgress.label == "Ch. 1929 of 3171")
        #expect(abs(snapshot.novelProgress.fraction - snapshot.progress) < 0.000_001)
        #expect(snapshot.inChapterFraction == 0.5)

        let decoded = try JSONDecoder().decode(ContinueReadingSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded.totalChapters == 3171)
        #expect(decoded.chapterProgress == 0.5)

        // Snapshots from before the chapter count was stored kept the in-chapter position.
        let legacy = Data(#"{"novelId":"n","novelTitle":"Novel","chapterId":"c","chapterTitle":"Ch","chapterNumber":12,"progress":0.4}"#.utf8)
        let old = try JSONDecoder().decode(ContinueReadingSnapshot.self, from: legacy)
        #expect(old.inChapterFraction == 0.4)
        #expect(old.novelProgress.label == "Ch. 12")
        #expect(abs(old.novelProgress.fraction - 0.4) < 0.000_001)
    }

    @Test
    func mergingProgressKeepsOnlyTheNewestRecordPerNovel() {
        let old = ReadingProgress(id: "old", userId: "user", novelId: "novel", chapterId: "one",
                                  currentLine: 1, totalLines: 10, percentage: 10,
                                  updatedAt: Date(timeIntervalSince1970: 100))
        let new = ReadingProgress(id: "new", userId: "user", novelId: "novel", chapterId: "two",
                                  currentLine: 2, totalLines: 10, percentage: 20,
                                  updatedAt: Date(timeIntervalSince1970: 200))
        #expect(ReadingProgress.latestByNovel([new, old]) == [new])
    }
}
