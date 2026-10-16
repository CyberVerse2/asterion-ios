import Foundation
import Testing
@testable import AsterionMac

struct NovelProgressTests {
    @Test func wholeNovelFractionCombinesChapterAndPositionInsideIt() throws {
        let progress = NovelProgress(chapterNumber: 3, totalChapters: 10, chapterPercentage: 50)

        let fraction = try #require(progress.fraction)
        #expect(abs(fraction - 0.25) < 0.000_1)
        #expect(progress.displayPercentage == 25)
        #expect(!progress.isFinished)
    }

    @Test func labelNeverGroupsLargeChapterNumbers() {
        let progress = NovelProgress(chapterNumber: 1929, totalChapters: 3171, chapterPercentage: 40)

        #expect(progress.label == "Ch. 1929 of 3171")
        #expect(progress.longLabel == "Chapter 1929 of 3171")
    }

    @Test func labelOmitsTheCountWhenItIsUnknown() {
        let progress = NovelProgress(chapterNumber: 12, totalChapters: nil, chapterPercentage: 40)

        #expect(progress.label == "Ch. 12")
        #expect(progress.fraction == nil)
        #expect(!progress.isFinished)
    }

    @Test func unresolvedChapterHasNoLabelOrFraction() {
        let progress = NovelProgress(chapterNumber: nil, totalChapters: 300, chapterPercentage: 68)

        #expect(progress.label == nil)
        #expect(progress.fraction == nil)
        #expect(progress.displayPercentage == nil)
        #expect(!progress.isFinished)
    }

    @Test func finishedNeedsTheLastChapterAndMostOfIt() {
        #expect(NovelProgress(chapterNumber: 3171, totalChapters: 3171, chapterPercentage: 95).isFinished)
        #expect(NovelProgress(chapterNumber: 3171, totalChapters: 3171, chapterPercentage: 100).isFinished)
        #expect(!NovelProgress(chapterNumber: 3171, totalChapters: 3171, chapterPercentage: 94.9).isFinished)
        #expect(!NovelProgress(chapterNumber: 3170, totalChapters: 3171, chapterPercentage: 100).isFinished)
    }

    @Test func finishedNovelReportsTheWholeNovelRead() {
        let progress = NovelProgress(chapterNumber: 10, totalChapters: 10, chapterPercentage: 96)

        #expect(progress.fraction == 1)
        #expect(progress.displayPercentage == 100)
    }

    @Test func nearlyFinishedNovelNeverRoundsUpToOneHundredPercent() {
        let progress = NovelProgress(chapterNumber: 1000, totalChapters: 1000, chapterPercentage: 90)

        #expect(!progress.isFinished)
        #expect(progress.displayPercentage == 99)
    }

    @Test func chapterBeyondALaggingCountBoundsTheCount() throws {
        let progress = NovelProgress(chapterNumber: 120, totalChapters: 100, chapterPercentage: 50)

        #expect(progress.label == "Ch. 120 of 120")
        let fraction = try #require(progress.fraction)
        #expect(fraction < 1)
        #expect(!progress.isFinished)
    }

    @Test func percentagesAreClampedAndInvalidCountsIgnored() {
        let over = NovelProgress(chapterNumber: 1, totalChapters: 2, chapterPercentage: 140)
        #expect(over.chapterPercentage == 100)

        let nan = NovelProgress(chapterNumber: 1, totalChapters: 2, chapterPercentage: .nan)
        #expect(nan.chapterPercentage == 0)

        let zero = NovelProgress(chapterNumber: 0, totalChapters: 0, chapterPercentage: 50)
        #expect(zero.chapterNumber == nil)
        #expect(zero.totalChapters == nil)
    }

    @Test func reachingTheLastParagraphCountsAsReadingTheChapter() {
        let atEnd = NovelProgress(
            progress: readingProgress(currentLine: 9, totalLines: 10),
            chapterNumber: 50,
            totalChapters: 50
        )
        #expect(atEnd.chapterPercentage == 100)
        #expect(atEnd.isFinished)

        let midway = NovelProgress(
            progress: readingProgress(currentLine: 4, totalLines: 10),
            chapterNumber: 50,
            totalChapters: 50
        )
        #expect(midway.chapterPercentage == 40)
        #expect(!midway.isFinished)
    }

    @Test func loadedChapterCountWinsOverTheCatalog() {
        #expect(NovelProgress.totalChapters(loaded: 3171, catalog: "3000") == 3171)
        #expect(NovelProgress.totalChapters(loaded: 0, catalog: "3000") == 3000)
        #expect(NovelProgress.totalChapters(loaded: nil, catalog: "3,171") == 3171)
        #expect(NovelProgress.totalChapters(loaded: nil, catalog: "3171 Chapters") == 3171)
        #expect(NovelProgress.totalChapters(loaded: nil, catalog: "") == nil)
        #expect(NovelProgress.totalChapters(loaded: nil, catalog: nil) == nil)
    }

    private func readingProgress(currentLine: Int, totalLines: Int) -> ReadingProgress {
        ReadingProgress(
            id: "progress",
            userId: "user",
            novelId: "novel",
            chapterId: "chapter",
            currentLine: currentLine,
            totalLines: totalLines,
            percentage: Double(currentLine) / Double(totalLines) * 100,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
