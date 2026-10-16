import Foundation
import Testing
@testable import AsterionMac

private func novel(
    _ id: String,
    title: String? = nil,
    author: String? = nil,
    rank: Int? = nil,
    chapters: String? = nil,
    views: String? = nil,
    bookmarks: String? = nil,
    status: String? = nil,
    genres: [String] = [],
    rating: Double? = nil,
    cover: Bool = true
) -> Novel {
    Novel(
        id: id,
        title: title ?? "Novel \(id)",
        author: author,
        rank: rank.map(String.init),
        totalChapters: chapters,
        views: views,
        bookmarks: bookmarks,
        status: status,
        genres: genres,
        summary: nil,
        imageURL: cover ? "https://example.com/\(id).jpg" : nil,
        rating: rating
    )
}

struct NovelCatalogParsingTests {
    @Test func abbreviatedCountsParseLikeTheCatalogWritesThem() {
        #expect(NovelCatalog.abbreviatedCount("790") == 790)
        #expect(NovelCatalog.abbreviatedCount("2,345") == 2345)
        #expect(NovelCatalog.abbreviatedCount("766.5K") == 766_500)
        #expect(NovelCatalog.abbreviatedCount("1M") == 1_000_000)
        #expect(NovelCatalog.abbreviatedCount("1.1m") == 1_100_000)
        #expect(NovelCatalog.abbreviatedCount(" 2.2K ") == 2200)
        #expect(NovelCatalog.abbreviatedCount("") == nil)
        #expect(NovelCatalog.abbreviatedCount("N/A") == nil)
        #expect(NovelCatalog.abbreviatedCount(nil) == nil)
    }

    @Test func statusReadsTheCatalogsFreeText() {
        #expect(NovelStatus(catalogValue: "Completed") == .completed)
        #expect(NovelStatus(catalogValue: " completed ") == .completed)
        #expect(NovelStatus(catalogValue: "Ongoing") == .ongoing)
        #expect(NovelStatus(catalogValue: "Hiatus") == nil)
        #expect(NovelStatus(catalogValue: nil) == nil)
    }

    @Test func tileMetadataShowsStatusAndUngroupedChapterCount() {
        let book = novel("1", chapters: "2969", status: "Completed", rating: 4.44)
        #expect(book.catalogMetadata == "Completed · 2969 ch")
        #expect(book.ratingLabel == "4.4")

        let bare = novel("2", author: "Ada")
        #expect(bare.catalogMetadata == "Ada")
        #expect(bare.ratingLabel == nil)
    }

    @Test func displayGenresDropBlanksAndCaseRepeats() {
        let book = novel("1", genres: ["Fantasy", " fantasy", "", "Action "])
        #expect(book.displayGenres == ["Fantasy", "Action"])
        #expect(book.hasGenre("ACTION"))
    }
}

struct NovelCatalogSectionTests {
    private let catalog = [
        novel("a", title: "Zeta", rank: 3, chapters: "100", views: "1M", status: "Ongoing", genres: ["Fantasy"], rating: 4.1),
        novel("b", title: "Alpha", rank: 1, chapters: "50", views: "200K", status: "Completed", genres: ["Romance"], rating: 4.8),
        novel("c", title: "Mid", rank: 2, chapters: "3000", views: nil, status: "Completed", genres: ["fantasy", "Horror"], rating: nil),
    ]

    @Test func statusSectionsFilterByStatus() {
        #expect(NovelCatalog.novels(catalog, in: .ongoing).map(\.id) == ["a"])
        #expect(NovelCatalog.novels(catalog, in: .completed).map(\.id) == ["b", "c"])
    }

    @Test func genreSectionMatchesCaseInsensitively() {
        #expect(NovelCatalog.novels(catalog, in: .genres, genre: "FANTASY").map(\.id) == ["c", "a"])
        #expect(NovelCatalog.novels(catalog, in: .genres, genre: "").count == 3)
    }

    @Test func rankedSectionsKeepTheirOwnOrder() {
        #expect(NovelCatalog.novels(catalog, in: .rankings, sort: .title).map(\.id) == ["b", "c", "a"])
        // Unrated and unviewed novels have no place on those shelves.
        #expect(NovelCatalog.novels(catalog, in: .topRated).map(\.id) == ["b", "a"])
        #expect(NovelCatalog.novels(catalog, in: .mostRead).map(\.id) == ["a", "b"])
    }

    @Test func gridSectionsHonorTheChosenSort() {
        #expect(NovelCatalog.novels(catalog, in: .all).map(\.id) == ["b", "c", "a"])
        #expect(NovelCatalog.novels(catalog, in: .all, sort: .chapters).map(\.id) == ["c", "a", "b"])
        #expect(NovelCatalog.novels(catalog, in: .completed, sort: .rating).map(\.id) == ["b", "c"])
    }

    @Test func genreCountsAreMostCommonFirstAndMergeCasing() {
        let counts = NovelCatalog.genreCounts(catalog)
        #expect(counts.first == NovelGenreCount(genre: "Fantasy", count: 2))
        #expect(counts.map(\.genre) == ["Fantasy", "Horror", "Romance"])
    }
}

struct NovelCatalogSearchTests {
    private let catalog = [
        novel("genre", title: "Quiet Days", rank: 1, genres: ["Martial Arts"]),
        novel("author", title: "Other Book", author: "Martial Writer", rank: 2),
        novel("contains", title: "The Martial God", rank: 3),
        novel("prefix", title: "Martial Peak", rank: 9),
        novel("miss", title: "Nothing", rank: 4),
    ]

    @Test func searchRanksTitlePrefixThenTitleThenAuthorThenGenre() {
        #expect(NovelCatalog.search(catalog, query: "martial").map(\.id) == ["prefix", "contains", "author", "genre"])
    }

    @Test func searchIgnoresCaseDiacriticsAndPadding() {
        let books = [novel("1", title: "Café Stories")]
        #expect(NovelCatalog.search(books, query: "  cafe ").map(\.id) == ["1"])
        #expect(NovelCatalog.search(books, query: "   ").isEmpty)
    }

    @Test func matchesInOneTierFollowPopularity() {
        let books = [
            novel("late", title: "Sword B", rank: 40),
            novel("early", title: "Sword A", rank: 2),
        ]
        #expect(NovelCatalog.search(books, query: "sword").map(\.id) == ["early", "late"])
    }
}

struct NovelCatalogRecommendationTests {
    @Test func recommendationsRankBySharedGenresThenRating() {
        let source = novel("source", genres: ["Fantasy", "Xianxia", "Romance"])
        let catalog = [
            source,
            novel("broad", genres: ["Fantasy"], rating: 4.9),
            novel("two", genres: ["Xianxia", "Romance"], rating: 3.0),
            novel("rare-low", genres: ["Xianxia"], rating: 3.5),
            novel("rare-high", genres: ["Xianxia"], rating: 4.5),
            novel("none", genres: ["Horror"], rating: 5.0),
            novel("f1", genres: ["Fantasy"]),
            novel("f2", genres: ["Fantasy"]),
            novel("f3", genres: ["Fantasy", "Horror"]),
        ]

        let ids = NovelCatalog.recommendations(for: source, in: catalog, limit: 4).map(\.id)
        #expect(ids == ["two", "rare-high", "rare-low", "broad"])
        #expect(!ids.contains("source"))
    }

    @Test func recommendationsTopUpWithTopRatedWhenFewShareAGenre() {
        let source = novel("source", genres: ["Mecha"])
        let catalog = [
            source,
            novel("match", genres: ["Mecha"], rating: 2.0),
            novel("best", genres: ["Horror"], rating: 4.9),
            novel("good", genres: ["Drama"], rating: 4.0),
        ]
        #expect(NovelCatalog.recommendations(for: source, in: catalog).map(\.id) == ["match", "best", "good"])
    }

    @Test func picksAlternateReaderGenresWithTopRatedAndSkipOwnedNovels() {
        let owned = novel("owned", genres: ["Horror"])
        let catalog = [
            owned,
            novel("h1", genres: ["Horror"], rating: 3.0),
            novel("h2", genres: ["Horror"], rating: 3.5),
            novel("top", genres: ["Romance"], rating: 5.0),
            novel("next", genres: ["Drama"], rating: 4.5),
        ]

        let picks = NovelCatalog.picks(catalog: catalog, basedOn: [owned], excluding: ["owned"], limit: 4)
        #expect(picks.novels.map(\.id) == ["h2", "h1", "top", "next"])
        #expect(picks.genres == ["Horror"])
    }

    @Test func picksWithoutReadingHistoryAreTopRated() {
        let catalog = [
            novel("low", rating: 3.0),
            novel("high", rating: 4.9),
            novel("unrated", rank: 1),
        ]
        let picks = NovelCatalog.picks(catalog: catalog, basedOn: [], excluding: [])
        #expect(picks.novels.map(\.id) == ["high", "low", "unrated"])
        #expect(picks.genres.isEmpty)
    }
}

struct NovelDiscoverLayoutTests {
    private var catalog: [Novel] {
        (1...160).map { index in
            novel(
                String(index),
                rank: index,
                chapters: String(index * 10),
                views: String(index) + "K",
                status: index.isMultiple(of: 2) ? "Completed" : "Ongoing",
                genres: [
                    "Fantasy",
                    index.isMultiple(of: 3) ? "Romance" : "Action",
                    index.isMultiple(of: 5) ? "Horror" : "Drama",
                    index.isMultiple(of: 7) ? "Mystery" : "",
                ],
                rating: 3.0 + Double(index % 20) / 10
            )
        }
    }

    @Test func noNovelAppearsTwiceAnywhereOnThePage() {
        let layout = NovelCatalog.discover(catalog, seed: 7)
        #expect(Set(layout.allNovelIDs).count == layout.allNovelIDs.count)
    }
}
