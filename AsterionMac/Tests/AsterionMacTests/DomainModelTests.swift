import Foundation
import Testing
@testable import AsterionMac

struct DomainModelTests {
    @Test func novelDecodesBackendFieldsAndNormalizesRank() throws {
        let data = Data(
            ##"{"_id":"42","title":"The Maze","author":"Ada","rank":"#17","imageUrl":"https://example.com/cover.jpg"}"##.utf8
        )

        let novel = try JSONDecoder().decode(Novel.self, from: data)

        #expect(novel.id == "42")
        #expect(novel.imageURL == "https://example.com/cover.jpg")
        #expect(novel.numericRank == 17)
    }

    @Test func chapterConvertsHTMLIntoReadableParagraphs() throws {
        let data = Data(
            #"{"_id":"chapter-1","chapterNumber":1,"title":"Arrival","content":"<p>First &amp; foremost.</p><p>Second line.<br/>Still second.</p>"}"#.utf8
        )

        let chapter = try JSONDecoder().decode(Chapter.self, from: data)

        #expect(chapter.paragraphs == ["First & foremost.", "Second line.", "Still second."])
    }

    @Test func unknownRanksSortAfterNumericRanks() {
        let ranked = Novel(
            id: "1", title: "Ranked", author: nil, rank: "2", totalChapters: nil,
            views: nil, bookmarks: nil, status: nil, genres: nil, summary: nil,
            imageURL: nil, rating: nil
        )
        let unranked = Novel(
            id: "2", title: "Unranked", author: nil, rank: nil, totalChapters: nil,
            views: nil, bookmarks: nil, status: nil, genres: nil, summary: nil,
            imageURL: nil, rating: nil
        )

        #expect([unranked, ranked].sorted { $0.numericRank < $1.numericRank }.first?.id == ranked.id)
    }

    @Test func malformedAuthorMarkupIsNormalized() {
        let novel = Novel(
            id: "1", title: "Lord of Mysteries", author: #"Editor:+CK/" class="a1" title="Cuttlefish That Loves DivingEditor: CK"&gt;Cuttlefish"#,
            rank: nil, totalChapters: nil, views: nil, bookmarks: nil, status: nil,
            genres: nil, summary: nil, imageURL: nil, rating: nil
        )

        #expect(novel.authorDisplayName == "Cuttlefish That Loves Diving")
    }
}
