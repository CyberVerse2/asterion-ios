//
//  AsterionTests.swift
//  AsterionTests
//
//  Created by Celestine Ejiofor on 02/03/2026.
//

import AVFoundation
import Testing
@testable import Asterion

struct AsterionTests {
    @Test @MainActor
    func novelListUsesDesktopRankOrderAndNaturalTitleTies() {
        let titles = [
            novel(id: "Book 10", genres: [], rating: 5, rank: "#2"),
            novel(id: "Unranked", genres: [], rating: 5),
            novel(id: "Book 2", genres: [], rating: 1, rank: "Rank 2"),
            novel(id: "First", genres: [], rating: 1, rank: "1"),
            novel(id: "Invalid", genres: [], rating: 5, rank: "unknown")
        ]

        #expect(Novel.ranked(titles).map(\.id) == ["First", "Book 2", "Book 10", "Invalid", "Unranked"])
    }

    @Test @MainActor
    func novelListParsesRanksLikeDesktop() {
        #expect(Novel.rankPosition(from: "Rank #1,234") == 1_234)
        #expect(Novel.rankPosition(from: nil) == .max)
        #expect(Novel.rankPosition(from: "") == .max)
        #expect(Novel.rankPosition(from: "unranked") == .max)
    }

    @Test @MainActor
    func homeUsesInterestsBeforeGeneralPopularity() {
        let fantasy = novel(id: "fantasy", genres: ["Fantasy"], rating: 3.8)
        let popularDrama = novel(id: "drama", genres: ["Drama"], rating: 4.9)

        let result = NovelPersonalizer.order(
            [popularDrama, fantasy],
            preferredGenres: [" fantasy "]
        )

        #expect(result.map(\.id) == ["fantasy", "drama"])
    }

    @Test @MainActor
    func homeUsesRatingToBreakEqualInterestMatches() {
        let lowerRated = novel(id: "lower", genres: ["Fantasy"], rating: 4.1)
        let higherRated = novel(id: "higher", genres: ["FANTASY"], rating: 4.8)

        let result = NovelPersonalizer.order(
            [lowerRated, higherRated],
            preferredGenres: ["fantasy"]
        )

        #expect(result.map(\.id) == ["higher", "lower"])
    }

    @Test @MainActor
    func homeBreaksEqualRatingTiesByRankThenTitle() {
        let ranked = novel(id: "ranked", genres: ["Fantasy"], rating: 4.5, rank: "3")
        let titledB = novel(id: "Beta", genres: ["Fantasy"], rating: 4.5)
        let titledA = novel(id: "Alpha", genres: ["Fantasy"], rating: 4.5)

        let result = NovelPersonalizer.order([titledB, titledA, ranked], preferredGenres: ["fantasy"])

        #expect(result.map(\.id) == ["ranked", "Alpha", "Beta"])
    }

    @Test @MainActor
    func downloadAheadPruningKeepsManualChaptersAndUnreadOnes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineChapterStore(baseDirectory: root.appendingPathComponent("cache"),
                                        documentsDirectory: root.appendingPathComponent("documents"))
        let book = novel(id: "book", genres: [], rating: 4)
        for (number, automatic) in [(1, false), (2, true), (3, true), (4, true)] {
            let chapter = Chapter(id: "c\(number)", chapterNumber: number, title: "Chapter \(number)",
                                  content: "Body \(number)", url: nil)
            _ = try await store.saveDownloadedChapter(
                novelTitle: book.title, chapterNumber: number, chapterTitle: chapter.title,
                content: "\(book.title)\nChapter \(number)\n\nBody \(number)",
                novel: book, chapter: chapter, automatic: automatic
            )
        }

        let removed = await store.pruneDownloadedAheadChapters(novel: book, readingChapterNumber: 3)

        #expect(removed == 1)
        let collection = try #require(await store.downloadedCollections().first)
        #expect(collection.chapters.map(\.id) == ["c1", "c3", "c4"])
        #expect(collection.downloadedAheadCount == 2)
    }

    @Test @MainActor
    func bulkDownloadKeepsEveryChapterInTheManifestOnceFlushed() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("cache")
        let documents = root.appendingPathComponent("documents")
        let store = OfflineChapterStore(baseDirectory: cache, documentsDirectory: documents)
        let book = novel(id: "book", genres: [], rating: 4)
        for number in 1...300 {
            let chapter = Chapter(id: "c\(number)", chapterNumber: number, title: "Chapter \(number)",
                                  content: nil, url: nil)
            _ = try await store.saveDownloadedChapter(
                novelTitle: book.title, chapterNumber: number, chapterTitle: chapter.title,
                content: "\(book.title)\nChapter \(number)\n\nBody \(number)",
                novel: book, chapter: chapter, automatic: true
            )
        }
        // Saving a downloaded-ahead chapter yourself keeps it from being pruned.
        let first = Chapter(id: "c1", chapterNumber: 1, title: "Chapter 1", content: nil, url: nil)
        _ = try await store.saveDownloadedChapter(
            novelTitle: book.title, chapterNumber: 1, chapterTitle: first.title,
            content: "\(book.title)\nChapter 1\n\nBody 1", novel: book, chapter: first
        )
        await store.flushDownloadedManifests()

        // A fresh store reads only what reached disk.
        let reopened = OfflineChapterStore(baseDirectory: cache, documentsDirectory: documents)
        let collection = try #require(await reopened.downloadedCollections().first)
        #expect(collection.novel.id == "book")
        #expect(collection.chapters.map(\.id) == (1...300).map { "c\($0)" })
        #expect(collection.downloadedAheadCount == 299)

        #expect(await reopened.pruneDownloadedAheadChapters(novel: book, readingChapterNumber: 11) == 9)
        let pruned = try #require(await reopened.downloadedCollections().first)
        #expect(pruned.chapterCount == 291)
        #expect(pruned.chapters.first?.id == "c1")
    }

    @Test
    func mediaProgressCompletesAtNinetyPercent() {
        let unfinished = MediaProgressPolicy.normalize(positionSeconds: 899, durationSeconds: 1_000)
        let finished = MediaProgressPolicy.normalize(positionSeconds: 900, durationSeconds: 1_000)

        #expect(unfinished.completed == false)
        #expect(finished.completed == true)
        #expect(finished.percentage == 90)
    }

    @Test
    func mediaProgressNeverExceedsThePlayableDuration() {
        let result = MediaProgressPolicy.normalize(positionSeconds: 1_500, durationSeconds: 1_000)

        #expect(result.positionSeconds == 1_000)
        #expect(result.percentage == 100)
        #expect(result.completed)
    }

    @Test
    func playbackQueueAdvancesToTheNextEpisodeAndStopsAtTheEnd() {
        let item = MediaItemDescriptor(
            mediaType: .anime,
            contentID: "show",
            title: "Show",
            subtitle: nil,
            imageURL: nil
        )
        let queue = PlaybackQueue(sources: [
            .anime(animeID: "a", episodeNumber: 1, title: "E1", item: item),
            .anime(animeID: "a", episodeNumber: 2, title: "E2", item: item),
            .anime(animeID: "a", episodeNumber: 3, title: "E3", item: item),
        ])

        #expect(queue.adjacent(of: "anime-a-1", offset: 1)?.requestID == "anime-a-2")
        #expect(queue.adjacent(of: "anime-a-2", offset: 1)?.requestID == "anime-a-3")
        #expect(queue.adjacent(of: "anime-a-3", offset: 1) == nil)
        #expect(queue.adjacent(of: "anime-a-2", offset: -1)?.requestID == "anime-a-1")
        #expect(queue.adjacent(of: "anime-a-1", offset: -1) == nil)
    }

    @Test
    func playbackQueueAdvancesMoviesAcrossSeasons() {
        let item = MediaItemDescriptor(
            mediaType: .movie,
            contentID: "series",
            title: "Series",
            subtitle: "TV Series",
            imageURL: nil
        )
        let queue = PlaybackQueue(sources: [
            .movie(slug: "s1e1", title: "S1E1", item: item, unitTitle: "E1", seasonNumber: 1, episodeNumber: 1),
            .movie(slug: "s1e2", title: "S1E2", item: item, unitTitle: "E2", seasonNumber: 1, episodeNumber: 2),
            .movie(slug: "s2e1", title: "S2E1", item: item, unitTitle: "E1", seasonNumber: 2, episodeNumber: 1),
        ])

        #expect(queue.adjacent(of: "movie-s1e2", offset: 1)?.requestID == "movie-s2e1")
        #expect(queue.adjacent(of: "movie-s2e1", offset: 1) == nil)
        #expect(queue.adjacent(of: "movie-s2e1", offset: -1)?.requestID == "movie-s1e2")
    }

    @Test
    func continuePolicyPrefersLatestInProgressOverFirstUnfinished() {
        let episodes = [1, 2, 3]
        let now = Date()
        let progress = [
            playbackProgress(unitId: "1", episodeNumber: 1, completed: false, positionSeconds: 40, updatedAt: now.addingTimeInterval(-60)),
            playbackProgress(unitId: "2", episodeNumber: 2, completed: false, positionSeconds: 120, updatedAt: now),
        ]

        let resume = MediaContinuePolicy.resumeUnit(from: episodes, progress: progress) { number, item in
            item.episodeNumber == number
        }

        #expect(resume == 2)
    }

    @Test
    func continuePolicyUsesFirstUnfinishedWhenNothingIsInProgress() {
        let episodes = [1, 2, 3]
        let progress = [
            playbackProgress(unitId: "1", episodeNumber: 1, completed: true, positionSeconds: 1_000, percentage: 100),
        ]

        let resume = MediaContinuePolicy.resumeUnit(from: episodes, progress: progress) { number, item in
            item.episodeNumber == number
        }

        #expect(resume == 2)
    }

    @Test
    func continuePolicyFallsBackToFirstUnitWhenAllComplete() {
        let episodes = [1, 2]
        let progress = [
            playbackProgress(unitId: "1", episodeNumber: 1, completed: true, positionSeconds: 1_000, percentage: 100),
            playbackProgress(unitId: "2", episodeNumber: 2, completed: true, positionSeconds: 1_000, percentage: 100),
        ]

        let resume = MediaContinuePolicy.resumeUnit(from: episodes, progress: progress) { number, item in
            item.episodeNumber == number
        }

        #expect(resume == 1)
    }

    @Test
    func continuePolicyFollowsTheEpisodeJustFinished() {
        // The account keeps only the latest episode, so finishing 2 of 3 must
        // lead to 3, not back to the never-recorded episode 1.
        let episodes = [1, 2, 3]
        let progress = [
            playbackProgress(unitId: "2", episodeNumber: 2, completed: true, positionSeconds: 1_400, percentage: 99),
        ]
        let resume = MediaContinuePolicy.resumeUnit(from: episodes, progress: progress) { number, item in
            item.episodeNumber == number
        }
        #expect(resume == 3)
        #expect(!MediaContinuePolicy.isFinished(episodes, progress: progress) { $1.episodeNumber == $0 })
    }

    @Test
    func continuePolicyMarksATitleFinishedAfterTheFinale() {
        let episodes = [1, 2, 3]
        let progress = [
            playbackProgress(unitId: "3", episodeNumber: 3, completed: true, positionSeconds: 1_420, percentage: 100),
        ]
        #expect(MediaContinuePolicy.isFinished(episodes, progress: progress) { $1.episodeNumber == $0 })
        let resume = MediaContinuePolicy.resumeUnit(from: episodes, progress: progress) { number, item in
            item.episodeNumber == number
        }
        #expect(resume == 1)
    }

    @Test
    func videoDownloadPathsSurviveIOS26PathsAndReinstalls() {
        let device = "/.nofollow/private/var/mobile/Containers/Data/Application/2B6E3794-15CA-480C-912C-4E87A8700797/Library/com.apple.UserManagedAssets.9lmNoF/Show_1.movpkg"
        #expect(OfflineVideoDownloadService.containerRelativePath(device)
            == "Library/com.apple.UserManagedAssets.9lmNoF/Show_1.movpkg")
        let relative = "Library/com.apple.UserManagedAssets.9lmNoF/Show_1.movpkg"
        #expect(OfflineVideoDownloadService.containerRelativePath(relative) == relative)
    }

    @Test
    func downloadAheadPrunesEpisodesWatchedPast() {
        func unit(_ episode: Int) -> MediaPlaybackDescriptor {
            MediaPlaybackDescriptor(
                item: MediaItemDescriptor(mediaType: .anime, contentID: "show", title: "Show", subtitle: nil, imageURL: nil),
                unitID: "1-\(episode)", unitTitle: nil, seasonNumber: 1, episodeNumber: episode
            )
        }
        // Watching 11 (unfinished): 10 is behind, 11 and 12 are kept.
        let watching11 = playbackProgress(unitId: "1-11", episodeNumber: 11, completed: false, positionSeconds: 300)
        #expect(OfflineVideoDownloadService.isWatchedPast(unit(10), latest: watching11))
        #expect(!OfflineVideoDownloadService.isWatchedPast(unit(11), latest: watching11))
        #expect(!OfflineVideoDownloadService.isWatchedPast(unit(12), latest: watching11))
        // Finished 11: 11 can go too.
        let finished11 = playbackProgress(unitId: "1-11", episodeNumber: 11, completed: true, positionSeconds: 1_000)
        #expect(OfflineVideoDownloadService.isWatchedPast(unit(11), latest: finished11))
    }

    @Test
    func downloadAheadQueuesRecentShowsEvenAfterAFinishedEpisode() {
        let now = Date()
        let finishedRecently = playbackProgress(unitId: "1-8", episodeNumber: 8, completed: true, positionSeconds: 1_000, updatedAt: now)
        let abandoned = playbackProgress(unitId: "1-9", episodeNumber: 9, completed: false, positionSeconds: 2, updatedAt: now.addingTimeInterval(-40 * 24 * 3600))
        #expect(DownloadAheadCoordinator.showsToQueue(from: [finishedRecently], now: now).count == 1)
        #expect(DownloadAheadCoordinator.showsToQueue(from: [abandoned], now: now).isEmpty)
    }

    @Test
    func chapterDisplayTitleDropsALeadingChapterNumber() {
        #expect(
            Chapter.strippedChapterPrefix(from: "Chapter 1 My Soon-To-Be Girlfriend Is Dead [1]")
                == "My Soon-To-Be Girlfriend Is Dead [1]"
        )
        #expect(Chapter.strippedChapterPrefix(from: "Chapter 3 Transmigration In The Villain's Body")
            == "Transmigration In The Villain's Body")
        #expect(Chapter.strippedChapterPrefix(from: "Ch. 12: The Gate") == "The Gate")
        #expect(Chapter.strippedChapterPrefix(from: "CHAPTER 4 - A Hardcore Violent Fluffy Romance Game")
            == "A Hardcore Violent Fluffy Romance Game")
        #expect(Chapter.strippedChapterPrefix(from: "The Threshold") == "The Threshold")
        #expect(Chapter.strippedChapterPrefix(from: "Chapter 9") == "")
    }

    private func playbackProgress(
        unitId: String,
        episodeNumber: Int,
        completed: Bool,
        positionSeconds: Double,
        percentage: Double = 20,
        updatedAt: Date = Date()
    ) -> MediaPlaybackProgress {
        MediaPlaybackProgress(
            id: unitId,
            userId: "user",
            mediaType: .anime,
            contentId: "show",
            title: "Show",
            imageURL: nil,
            unitId: unitId,
            unitTitle: "Episode \(episodeNumber)",
            seasonNumber: 1,
            episodeNumber: episodeNumber,
            positionSeconds: positionSeconds,
            durationSeconds: 1_000,
            percentage: percentage,
            completed: completed,
            clientUpdatedAt: updatedAt,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }

    private func novel(id: String, genres: [String], rating: Double, rank: String? = nil) -> Novel {
        Novel(
            id: id,
            title: id,
            author: nil,
            rank: rank,
            totalChapters: nil,
            views: nil,
            bookmarks: nil,
            status: nil,
            genres: genres,
            summary: nil,
            imageUrl: nil,
            rating: rating
        )
    }
}

@MainActor
@Test func readerOnlyTrustsTrulyAdjacentChapters() {
    func chapter(_ number: Int) -> Chapter {
        Chapter(id: "c\(number)", chapterNumber: number, title: "Chapter \(number)", content: nil, url: nil)
    }
    // Opened at 4, read on to 10: the list is [4, 10], so 4 must not count as "previous".
    #expect(!ReaderView.isAdjacent(chapter(4), to: chapter(10), direction: -1))
    #expect(ReaderView.isAdjacent(chapter(9), to: chapter(10), direction: -1))
    #expect(ReaderView.isAdjacent(chapter(11), to: chapter(10), direction: 1))
    #expect(!ReaderView.isAdjacent(chapter(12), to: chapter(10), direction: 1))
    // Unnumbered chapters keep their list order.
    #expect(ReaderView.isAdjacent(chapter(0), to: chapter(10), direction: -1))
}

@MainActor
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
}

// MARK: - Novels phase 2: catalog shaping, Home hero, Continue reloads

@MainActor
private func catalogNovel(
    _ id: String,
    genres: [String] = [],
    rating: Double? = nil,
    rank: String? = nil,
    views: String? = nil,
    status: String? = nil,
    chapters: String? = nil,
    author: String? = nil,
    summary: String? = nil,
    image: String? = "https://example.com/\(UUID().uuidString).jpg"
) -> Novel {
    Novel(
        id: id, title: id, author: author, rank: rank, totalChapters: chapters,
        views: views, bookmarks: nil, status: status, genres: genres,
        summary: summary, imageUrl: image, rating: rating
    )
}

@MainActor
struct NovelCatalogTests {
    @Test
    func countsParseCatalogShorthand() {
        #expect(NovelCatalog.count(from: "766.5K") == 766_500)
        #expect(NovelCatalog.count(from: "1M") == 1_000_000)
        #expect(NovelCatalog.count(from: "2.1M") == 2_100_000)
        #expect(NovelCatalog.count(from: "12,345") == 12_345)
        #expect(NovelCatalog.count(from: "987 views") == 987)
        #expect(NovelCatalog.count(from: nil) == 0)
        #expect(NovelCatalog.count(from: "n/a") == 0)
    }

    @Test
    func genresMatchAcrossSpellingsAndSortByFrequency() {
        #expect(NovelCatalog.genreKey(" Sci-Fi ") == NovelCatalog.genreKey("sci fi"))
        let novels = [
            catalogNovel("a", genres: ["Fantasy", "Sci-fi"]),
            catalogNovel("b", genres: ["Fantasy", "Sci-fi"]),
            catalogNovel("c", genres: ["Fantasy", "SCI-FI", "Romance"]),
        ]
        #expect(NovelCatalog.genres(in: novels) == ["Fantasy", "Sci-fi", "Romance"])
        #expect(NovelCatalog.filter(novels, genre: "Sci-Fi").count == 3)
        #expect(NovelCatalog.filter(novels, genre: "romance").map(\.id) == ["c"])
    }

    @Test
    func moreLikeThisRanksBySharedGenresThenRating() {
        let current = catalogNovel("current", genres: ["Fantasy", "Action", "Romance"])
        let catalog = [
            current,
            catalogNovel("one-shared-high", genres: ["Fantasy"], rating: 4.9),
            catalogNovel("two-shared-low", genres: ["Fantasy", "Action"], rating: 3.1),
            catalogNovel("two-shared-high", genres: ["action", "ROMANCE"], rating: 4.4),
            catalogNovel("none-shared", genres: ["Horror"], rating: 5),
        ]
        let similar = NovelCatalog.similar(to: current, in: catalog)
        #expect(similar.map(\.id) == ["two-shared-high", "two-shared-low", "one-shared-high"])
        #expect(NovelCatalog.similar(to: current, in: catalog, limit: 1).map(\.id) == ["two-shared-high"])
        #expect(NovelCatalog.similar(to: catalogNovel("bare"), in: catalog).isEmpty)
    }

    @Test
    func shelvesFilterAndSortTheCatalog() {
        let novels = [
            catalogNovel("ongoing-popular", rating: 4.0, views: "1.2M", status: "Ongoing"),
            catalogNovel("ongoing-quiet", rating: 4.8, views: "20K", status: "ongoing"),
            catalogNovel("complete", rating: 4.5, views: "500K", status: "Completed"),
            catalogNovel("unrated", views: "3M", status: "Hiatus"),
        ]
        #expect(NovelCatalog.ongoing(novels).map(\.id) == ["ongoing-popular", "ongoing-quiet"])
        #expect(NovelCatalog.completed(novels).map(\.id) == ["complete"])
        #expect(NovelCatalog.topRated(novels).map(\.id) == ["ongoing-quiet", "complete", "ongoing-popular"])
        #expect(NovelCatalog.byPopularity(novels).first?.id == "unrated")
        #expect(NovelCatalog.ranking(novels, by: .rating).last?.id == "unrated")
        #expect(NovelCatalog.ranking(novels, by: .views).map(\.id).first == "unrated")
    }

    @Test
    func searchMatchesTitleAuthorAndGenre() {
        let novels = [
            catalogNovel("Tree of Aeons", genres: ["Isekai"], author: "Spaizzer"),
            catalogNovel("Dual Cultivation", genres: ["Comedy"], author: "Crippledsword"),
        ]
        #expect(NovelCatalog.search(novels, query: "aeons").map(\.id) == ["Tree of Aeons"])
        #expect(NovelCatalog.search(novels, query: "crippled").map(\.id) == ["Dual Cultivation"])
        #expect(NovelCatalog.search(novels, query: "isekai").map(\.id) == ["Tree of Aeons"])
        #expect(NovelCatalog.search(novels, query: "  ").count == 2)
    }

    @Test
    func readActionTitlesNameTheChapter() {
        #expect(NovelReadTarget.title(for: nil) == "Read")
        #expect(NovelReadTarget.title(for: NovelProgress(chapterNumber: 1929, totalChapters: 3171, chapterPercentage: 40))
            == "Continue chapter 1929")
        #expect(NovelReadTarget.title(for: NovelProgress(chapterNumber: 10, totalChapters: 10, chapterPercentage: 99))
            == "Read again")
        #expect(NovelReadTarget.title(for: NovelProgress(chapterNumber: nil, totalChapters: nil, chapterPercentage: 3))
            == "Continue reading")
    }

    @Test
    func chaptersBeforeTheReadingOneAreRead() {
        #expect(ChapterReadState.isRead(chapterNumber: 4, readingChapterNumber: 5))
        #expect(!ChapterReadState.isRead(chapterNumber: 5, readingChapterNumber: 5))
        #expect(!ChapterReadState.isRead(chapterNumber: 6, readingChapterNumber: 5))
        #expect(!ChapterReadState.isRead(chapterNumber: 4, readingChapterNumber: nil))
        #expect(ChapterReadState.isRead(chapterNumber: 9, readingChapterNumber: 10, novelFinished: true))
        #expect(ChapterReadState.isRead(chapterNumber: 10, readingChapterNumber: 10, novelFinished: true))
    }

    @Test
    func chapterPreviewCentresOnTheReadingChapter() {
        #expect(ChapterPreviewWindow.offset(around: 1929, size: 5, total: 3171) == 1926)
        #expect(ChapterPreviewWindow.offset(around: 2, size: 5, total: 3171) == 0)
        #expect(ChapterPreviewWindow.offset(around: 3171, size: 5, total: 3171) == 3166)
        #expect(ChapterPreviewWindow.offset(around: 40, size: 5, total: nil) == 37)
    }

    @Test
    func continueReloadsWhenTheSessionArrivesOrTheChapterChanges() {
        func progress(chapter: String, line: Int) -> ReadingProgress {
            ReadingProgress(id: UUID().uuidString, userId: "u", novelId: "n", chapterId: chapter,
                            currentLine: line, totalLines: 100, percentage: Double(line), updatedAt: Date())
        }
        let base = HomeContinueReload.key(isAuthorized: false, progress: [progress(chapter: "c1", line: 3)])
        #expect(base == HomeContinueReload.key(isAuthorized: false, progress: [progress(chapter: "c1", line: 60)]))
        #expect(base != HomeContinueReload.key(isAuthorized: true, progress: [progress(chapter: "c1", line: 3)]))
        #expect(base != HomeContinueReload.key(isAuthorized: false, progress: [progress(chapter: "c2", line: 3)]))
    }

    @Test
    func localReadingCountsBeforeSyncedProgressArrives() throws {
        // Cold launch: the session token has not reached the API, so the
        // remote list is empty. The novel read last on this device must
        // still be offered to Continue.
        let suite = "asterion.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = ReadingProgressService(defaults: defaults)
        service.updateProgress(novelId: "novel", chapterId: "c12", currentLine: 5, totalLines: 40, syncToCloud: false)

        let relaunched = ReadingProgressService(defaults: defaults)
        let merged = relaunched.mergedProgress(with: [])
        #expect(merged.map(\.novelId) == ["novel"])
        #expect(merged.first?.chapterId == "c12")
    }
}
