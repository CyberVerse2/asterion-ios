import Foundation
import Testing
@testable import AsterionKit

struct NovelRankingTests {
    @Test
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

    @Test
    func novelListParsesRanksLikeDesktop() {
        #expect(Novel.rankPosition(from: "Rank #1,234") == 1_234)
        #expect(Novel.rankPosition(from: nil) == .max)
        #expect(Novel.rankPosition(from: "") == .max)
        #expect(Novel.rankPosition(from: "unranked") == .max)
    }

    @Test
    func homeUsesInterestsBeforeGeneralPopularity() {
        let fantasy = novel(id: "fantasy", genres: ["Fantasy"], rating: 3.8)
        let popularDrama = novel(id: "drama", genres: ["Drama"], rating: 4.9)

        let result = NovelPersonalizer.order(
            [popularDrama, fantasy],
            preferredGenres: [" fantasy "]
        )

        #expect(result.map(\.id) == ["fantasy", "drama"])
    }

    @Test
    func homeUsesRatingToBreakEqualInterestMatches() {
        let lowerRated = novel(id: "lower", genres: ["Fantasy"], rating: 4.1)
        let higherRated = novel(id: "higher", genres: ["FANTASY"], rating: 4.8)

        let result = NovelPersonalizer.order(
            [lowerRated, higherRated],
            preferredGenres: ["fantasy"]
        )

        #expect(result.map(\.id) == ["higher", "lower"])
    }

    @Test
    func homeBreaksEqualRatingTiesByRankThenTitle() {
        let ranked = novel(id: "ranked", genres: ["Fantasy"], rating: 4.5, rank: "3")
        let titledB = novel(id: "Beta", genres: ["Fantasy"], rating: 4.5)
        let titledA = novel(id: "Alpha", genres: ["Fantasy"], rating: 4.5)

        let result = NovelPersonalizer.order([titledB, titledA, ranked], preferredGenres: ["fantasy"])

        #expect(result.map(\.id) == ["ranked", "Alpha", "Beta"])
    }
}

struct ChapterTests {
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

    @Test
    func readerOnlyTrustsTrulyAdjacentChapters() {
        func chapter(_ number: Int) -> Chapter {
            Chapter(id: "c\(number)", chapterNumber: number, title: "Chapter \(number)", content: nil, url: nil)
        }
        // Opened at 4, read on to 10: the list is [4, 10], so 4 must not count as "previous".
        #expect(!Chapter.isAdjacent(chapter(4), to: chapter(10), direction: -1))
        #expect(Chapter.isAdjacent(chapter(9), to: chapter(10), direction: -1))
        #expect(Chapter.isAdjacent(chapter(11), to: chapter(10), direction: 1))
        #expect(!Chapter.isAdjacent(chapter(12), to: chapter(10), direction: 1))
        // Unnumbered chapters keep their list order.
        #expect(Chapter.isAdjacent(chapter(0), to: chapter(10), direction: -1))
    }
}

// MARK: - Novels phase 2: catalog shaping, Home hero, Continue reloads

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
}
