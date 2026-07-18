import Foundation
import Testing
@testable import AsterionMac

struct DomainModelTests {
    @Test func animeTitleDecodesTheLiveServiceShapeAndFindsItsShowSlug() throws {
        let data = Data(
            ##"{"episode_label":"Ep 220","id":"naruto-abc12","image_url":"https://example.com/poster.jpg","japanese_title":"Naruto","slug":"naruto-abc12","title":" Naruto &amp;amp; Friends ","type":"TV","url":"https://animixplay.cz/watch/naruto-abc12"}"##.utf8
        )

        let title = try animeDecoder.decode(AnimeTitle.self, from: data)

        #expect(title.id == "naruto-abc12")
        #expect(title.imageURL == URL(string: "https://example.com/poster.jpg"))
        #expect(title.episodeLabel == "Ep 220")
        #expect(title.slug == "naruto-abc12")
        #expect(title.displayTitle == "Naruto & Friends")
        #expect(title.displayJapaneseTitle == "Naruto")
    }

    @Test func animeShowAndEpisodesDecodeTheLiveServiceContract() throws {
        let showData = Data(
            ##"{"date_aired":"Oct 3, 2002 to Feb 8, 2007","description":"A ninja&#039;s story.","dub_episodes":220,"episodes_count":220,"genres":["action","adventure"],"id":"7123","image_url":"https://example.com/poster.jpg","japanese_title":"Naruto","mal_score":"7.99","season":"Fall 2002","slug":"naruto-abc12","status":"Finished Airing","studio":"Pierrot","sub_episodes":220,"title":"Naruto","type":"TV"}"##.utf8
        )
        let episodeData = Data(
            ##"[{"anime_id":"7123","id":"7123:3","number":3}]"##.utf8
        )

        let show = try animeDecoder.decode(AnimeShow.self, from: showData)
        let episodes = try animeDecoder.decode([AnimeEpisode].self, from: episodeData)

        #expect(show.title == "Naruto")
        #expect(show.genres == ["action", "adventure"])
        #expect(show.season == "Fall 2002")
        #expect(show.episodesCount == 220)
        #expect(show.displayDescription == "A ninja's story.")
        #expect(show.displayStudio == "Pierrot")
        #expect(episodes.first?.animeID == "7123")
        #expect(episodes.first?.number == 3)
    }

    @Test func animePlaybackResolvesServiceRelativeVideoURLs() throws {
        let data = Data(
            ##"[{"quality":"HD","server":"MegaPlay","source":"/proxy/m3u8?url=https%3A%2F%2Fexample.com%2Fmaster.m3u8","url":"https://player.example.com/embed/1716"}]"##.utf8
        )
        let source = try #require(animeDecoder.decode([AnimeStreamSource].self, from: data).first)
        let serviceURL = try #require(URL(string: "https://asterion-scraper.cyberverse.cloud"))
        let rawDirectURL = try #require(source.directURL)
        let directURL = AnimeAPI.serviceURL(rawDirectURL, relativeTo: serviceURL)
        let normalized = AnimeStreamSource(
            server: source.server,
            embedURL: AnimeAPI.serviceURL(source.embedURL, relativeTo: serviceURL),
            quality: source.quality,
            directURL: directURL
        )
        let options = AnimePlaybackOption.options(from: [normalized])

        #expect(directURL.host == "asterion-scraper.cyberverse.cloud")
        #expect(directURL.path == "/proxy/m3u8")
        #expect(options.map(\.kind) == [.direct, .embed])
        #expect(options.first?.title == "MegaPlay · Direct · HD")
    }

    @Test func animePlayerRouteRoundTripsThroughWindowState() throws {
        let route = AnimePlayerRoute(
            slug: "naruto-abc12",
            title: "Naruto",
            initialEpisodeID: "7123:220"
        )

        let data = try JSONEncoder().encode(route)
        let decoded = try animeDecoder.decode(AnimePlayerRoute.self, from: data)

        #expect(decoded == route)
        #expect(decoded.initialEpisodeID == "7123:220")
    }

    @Test func longAnimeEpisodeListsSplitIntoSearchableHundredEpisodeRanges() throws {
        let episodes = (1...220).map {
            AnimeEpisode(id: "7123:\($0)", animeID: "7123", number: $0)
        }

        let ranges = AnimeEpisodeRange.pages(for: episodes)

        #expect(ranges.map(\.label) == ["001–100", "101–200", "201–220"])
        #expect(ranges[1].episodes.count == 100)
        #expect(ranges[2].contains(episodeID: "7123:220"))
        #expect(!ranges[0].contains(episodeID: "7123:220"))
    }

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

    @Test func readingProgressStorePersistsAndScopesProgressByAccount() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("progress.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let accountProgress = LocalReadingProgress.pending(
            ownerID: "account-1",
            novelID: "novel-1",
            chapterID: "chapter-12",
            currentLine: 8,
            totalLines: 20,
            now: Date(timeIntervalSince1970: 100)
        )
        let otherAccountProgress = LocalReadingProgress.pending(
            ownerID: "account-2",
            novelID: "novel-2",
            chapterID: "chapter-3",
            currentLine: 2,
            totalLines: 10,
            now: Date(timeIntervalSince1970: 200)
        )

        let writer = ReadingProgressStore(fileURL: fileURL)
        try await writer.save(accountProgress)
        try await writer.save(otherAccountProgress)

        let reader = ReadingProgressStore(fileURL: fileURL)
        #expect(try await reader.progresses(ownerID: "account-1") == [accountProgress])
        #expect(try await reader.progresses(ownerID: "account-2") == [otherAccountProgress])

        let replacement = LocalReadingProgress.pending(
            ownerID: "account-1",
            novelID: "novel-3",
            chapterID: "chapter-7",
            currentLine: 4,
            totalLines: 12,
            now: Date(timeIntervalSince1970: 300)
        )
        try await reader.replaceProgresses(ownerID: "account-1", with: [replacement])

        #expect(try await reader.progresses(ownerID: "account-1") == [replacement])
        #expect(try await reader.progresses(ownerID: "account-2") == [otherAccountProgress])
    }

    @Test func pendingProgressUsesNewestTimestampDuringReconciliation() {
        let pending = LocalReadingProgress.pending(
            ownerID: "account-1",
            novelID: "novel-1",
            chapterID: "chapter-8",
            currentLine: 6,
            totalLines: 10,
            now: Date(timeIntervalSince1970: 200)
        )
        let olderServer = ReadingProgress(
            id: "progress-1",
            userId: "user-1",
            novelId: "novel-1",
            chapterId: "chapter-7",
            currentLine: 9,
            totalLines: 10,
            percentage: 90,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newerServer = ReadingProgress(
            id: "progress-1",
            userId: "user-1",
            novelId: "novel-1",
            chapterId: "chapter-9",
            currentLine: 1,
            totalLines: 10,
            percentage: 10,
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        #expect(pending.shouldUpload(over: nil))
        #expect(pending.shouldUpload(over: olderServer))
        #expect(!pending.shouldUpload(over: newerServer))
    }

    private var animeDecoder: JSONDecoder {
        JSONDecoder()
    }
}
