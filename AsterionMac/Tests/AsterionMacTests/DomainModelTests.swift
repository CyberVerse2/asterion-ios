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

    @Test func chapterDisplayTitleRemovesRepeatedNumbering() {
        let chapter = Chapter(
            id: "chapter-627",
            chapterNumber: 627,
            title: "Chapter 627 - 627: Needlework",
            content: nil,
            url: nil
        )

        #expect(chapter.displayTitle == "Needlework")
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

    @Test func offlineLibraryPersistsDownloadedNovelAndChapters() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let novel = Novel(
            id: "novel-1", title: "Offline Book", author: "Ada", rank: "#1",
            totalChapters: "2", views: nil, bookmarks: nil, status: nil,
            genres: ["Fantasy"], summary: nil, imageURL: nil, rating: nil
        )
        let chapters = [
            Chapter(id: "chapter-1", chapterNumber: 1, title: "One", content: "<p>First.</p>", url: nil),
            Chapter(id: "chapter-2", chapterNumber: 2, title: "Two", content: "<p>Second.</p>", url: nil),
        ]

        let writer = OfflineLibraryStore(directory: directory)
        try await writer.save(novel: novel, chapters: chapters)

        let reader = OfflineLibraryStore(directory: directory)
        #expect(try await reader.downloadedNovelIDs() == ["novel-1"])
        #expect(try await reader.downloadedNovels().map(\.id) == ["novel-1"])
        #expect(try await reader.chapters(for: "novel-1")?.map(\.id) == ["chapter-1", "chapter-2"])
        #expect(try await reader.chapter(id: "chapter-2")?.paragraphs == ["Second."])
    }

    @Test func offlineDownloadReportsBoundedChapterProgress() {
        var download = OfflineDownload(
            novelID: "novel-1",
            novelTitle: "Offline Book",
            completedChapters: 3,
            totalChapters: 12,
            phase: .downloading,
            errorMessage: nil,
            updatedAt: .now
        )

        #expect(download.id == "novel-1")
        #expect(download.progress == 0.25)
        #expect(download.isDownloading)

        download.completedChapters = 13
        #expect(download.progress == 1)

        download.totalChapters = 0
        #expect(download.progress == 0)
    }

    @Test func offlineDownloadDistinguishesCompletionAndFailure() {
        let completed = OfflineDownload(
            novelID: "novel-1",
            novelTitle: "Complete Book",
            completedChapters: 2,
            totalChapters: 2,
            phase: .completed,
            errorMessage: nil,
            updatedAt: .now
        )
        let failed = OfflineDownload(
            novelID: "novel-2",
            novelTitle: "Failed Book",
            completedChapters: 1,
            totalChapters: 2,
            phase: .failed,
            errorMessage: "The connection was lost.",
            updatedAt: .now
        )

        #expect(completed.progress == 1)
        #expect(!completed.isDownloading)
        #expect(failed.phase == .failed)
        #expect(failed.errorMessage == "The connection was lost.")
    }
}
