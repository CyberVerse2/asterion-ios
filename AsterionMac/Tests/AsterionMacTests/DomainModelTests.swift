import Foundation
import Testing
@testable import AsterionMac

struct DomainModelTests {
    @Test func footballMatchDecodesTheDeployedServiceShape() throws {
        let data = Data(
            ##"{"id":"nashville-atlanta","title":"Nashville SC vs Atlanta United","category":"football","date":1784350800000,"poster":"poster-id","posterURL":"https://streamed.pk/api/images/proxy/poster.webp","popular":true,"isLive":true,"teams":{"home":{"name":"Nashville SC","badge":"nashville","badgeURL":"https://streamed.pk/api/images/badge/nashville.webp"},"away":{"name":"Atlanta United","badge":"atlanta","badgeURL":"https://streamed.pk/api/images/badge/atlanta.webp"}},"sources":[{"source":"admin","id":"match-1"},{"source":"delta","id":"match-2"}]}"##.utf8
        )

        let match = try animeDecoder.decode(FootballMatch.self, from: data)

        #expect(match.displayTitle == "Nashville SC vs Atlanta United")
        #expect(match.homeTeam?.name == "Nashville SC")
        #expect(match.awayTeam?.badgeURL?.host == "streamed.pk")
        #expect(match.isLive)
        #expect(match.sources.map(\.source) == ["admin", "delta"])
        #expect(Int64(match.kickoff.timeIntervalSince1970 * 1_000) == 1_784_350_800_000)
    }

    @Test func footballSupportsMissingTeamsAndArbitraryStreamProviders() throws {
        let matchData = Data(
            ##"{"id":"international-match","title":"International Match","category":"football","date":1784350800000,"poster":null,"posterURL":null,"popular":false,"isLive":false,"teams":null,"sources":[{"source":"new-provider","id":"source-42"}]}"##.utf8
        )
        let streamData = Data(
            ##"{"streams":[{"id":"source-42","streamNo":3,"language":"","hd":true,"embedUrl":"https://player.example/embed/source-42","source":"new-provider","viewers":1250}],"matchId":"international-match","homeTeam":null,"awayTeam":null}"##.utf8
        )

        let match = try animeDecoder.decode(FootballMatch.self, from: matchData)
        let collection = try animeDecoder.decode(FootballStreamCollection.self, from: streamData)
        let stream = try #require(collection.streams.first)
        let route = FootballPlayerRoute(match: match)
        let roundTrippedRoute = try animeDecoder.decode(
            FootballPlayerRoute.self,
            from: JSONEncoder().encode(route)
        )

        #expect(match.teams == nil)
        #expect(match.sources.first?.source == "new-provider")
        #expect(stream.optionID == "new-provider-source-42-3")
        #expect(stream.displayName == "New-Provider · HD")
        #expect(roundTrippedRoute == route)
    }

    @Test func movieCatalogAndPlaybackDecodeTheLiveServiceShape() throws {
        let titleData = Data(
            ##"{"id":"568145","slug":"obsession-soap2day","title":"Obsession","image_url":"https://example.com/poster.jpg","imdb_rating":"8.0","runtime":"1h 48min","year":"2026","type":"movie","quality":null}"##.utf8
        )
        let streamData = Data(
            ##"[{"server_id":1,"label":"TIK 1","quality":"HLS Direct","embed_url":"https://video.example/master.m3u8","is_hls":true,"proxy_url":"/proxy/hls?url=https://video.example/master.m3u8"}]"##.utf8
        )

        let title = try animeDecoder.decode(MovieTitle.self, from: titleData)
        let source = try #require(animeDecoder.decode([MovieStreamSource].self, from: streamData).first)
        let serviceURL = try #require(URL(string: "https://asterion-movies.cyberverse.cloud"))
        let normalized = MovieStreamSource(
            serverID: source.serverID,
            label: source.label,
            quality: source.quality,
            embedURL: source.embedURL,
            isHLS: source.isHLS,
            proxyURL: source.proxyURL.map { MovieAPI.serviceURL($0, relativeTo: serviceURL) }
        )
        let option = try #require(MoviePlaybackOption.options(from: [normalized]).first)

        #expect(title.slug == "obsession-soap2day")
        #expect(title.displayTitle == "Obsession")
        #expect(title.imdbRating == "8.0")
        #expect(!title.isSeries)
        #expect(option.kind == .direct)
        #expect(option.url.host == "asterion-movies.cyberverse.cloud")
    }

    @Test func movieEpisodesKeepSeasonAndEpisodeIdentity() throws {
        let data = Data(
            ##"[{"id":"episode/show-season-2-episode-3","season":2,"number":3,"title":"Episode 3","url":"https://ww25.soap2day.day/episode/show-season-2-episode-3/"}]"##.utf8
        )

        let episode = try #require(animeDecoder.decode([MovieEpisode].self, from: data).first)

        #expect(episode.season == 2)
        #expect(episode.number == 3)
        #expect(episode.id == "episode/show-season-2-episode-3")
    }

    @Test func moviePlaybackPrefersTheVerifiedNativeSource() throws {
        let options = [
            MoviePlaybackOption(
                id: "direct-1",
                kind: .direct,
                url: try #require(URL(string: "https://video.example/master.m3u8")),
                title: "HLS Direct"
            ),
            MoviePlaybackOption(
                id: "web-2",
                kind: .web,
                url: try #require(URL(string: "https://vidnest.fun/movie/1")),
                title: "VidNest (Ad-Free) · Direct Player"
            ),
            MoviePlaybackOption(
                id: "web-3",
                kind: .web,
                url: try #require(URL(string: "https://player.videasy.net/movie/1")),
                title: "Server 4 · HD 1080P"
            ),
        ]

        #expect(MoviePlaybackOption.preferred(from: options)?.id == "direct-1")
    }

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
            ##"[{"quality":"HD","server":"MegaPlay","source":"/proxy/m3u8?url=https%3A%2F%2Fexample.com%2Fmaster.m3u8","tracks":[{"default":true,"file":"/proxy/subtitle?url=https%3A%2F%2Fexample.com%2FEnglish.vtt","kind":"captions","label":"English"}],"url":"https://player.example.com/embed/1716"}]"##.utf8
        )
        let source = try #require(animeDecoder.decode([AnimeStreamSource].self, from: data).first)
        let serviceURL = try #require(URL(string: "https://asterion-scraper.cyberverse.cloud"))
        let rawDirectURL = try #require(source.directURL)
        let directURL = AnimeAPI.serviceURL(rawDirectURL, relativeTo: serviceURL)
        let normalized = AnimeStreamSource(
            server: source.server,
            embedURL: AnimeAPI.serviceURL(source.embedURL, relativeTo: serviceURL),
            quality: source.quality,
            directURL: directURL,
            tracks: source.tracks.map { track in
                AnimeSubtitleTrack(
                    fileURL: AnimeAPI.serviceURL(track.fileURL, relativeTo: serviceURL),
                    label: track.label,
                    kind: track.kind,
                    languageCode: track.languageCode,
                    isDefault: track.isDefault
                )
            }
        )
        let options = AnimePlaybackOption.options(from: [normalized])

        #expect(directURL.host == "asterion-scraper.cyberverse.cloud")
        #expect(directURL.path == "/proxy/m3u8")
        #expect(options.map(\.kind) == [.direct, .embed])
        #expect(options.first?.title == "MegaPlay · Direct · HD")
        #expect(options.first?.subtitleTracks.first?.label == "English")
        #expect(options.first?.subtitleTracks.first?.fileURL.host == "asterion-scraper.cyberverse.cloud")
        #expect(options.first?.subtitleTracks.first?.isDefault == true)

        let thirdPartyDirectURL = try #require(
            URL(string: "https://mt.nekostream.site/video/master.m3u8")
        )
        let proxiedURL = AnimeAPI.playableDirectURL(thirdPartyDirectURL, relativeTo: serviceURL)
        #expect(proxiedURL.host == "asterion-scraper.cyberverse.cloud")
        #expect(proxiedURL.path == "/proxy/m3u8")
        #expect(proxiedURL.query?.contains("mt.nekostream.site") == true)

        let dubbedSource = AnimeStreamSource(
            server: "VidPlay-1",
            embedURL: try #require(URL(string: "https://vidtube.site/stream/episode/dub")),
            quality: "HD",
            directURL: thirdPartyDirectURL,
            tracks: []
        )
        let dubbedOptions = AnimePlaybackOption.options(from: [dubbedSource])
        #expect(dubbedOptions.first?.variant == .dubbed)
        #expect(dubbedOptions.first?.title == "VidPlay-1 · Dub · Direct · HD")
    }

    @Test func captionedAnimePlaybackBuildsARestrictedVideoDocument() throws {
        let videoURL = try #require(URL(string: "https://media.example/master.m3u8"))
        let subtitleURL = try AnimeSubtitleLoader.dataURL(
            for: Data("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHello".utf8),
            label: "English"
        )
        let track = AnimeSubtitleTrack(
            fileURL: subtitleURL,
            label: "English \"CC\"",
            kind: "captions",
            languageCode: "en",
            isDefault: true
        )

        let html = CaptionedMediaDocument.html(url: videoURL, tracks: [track])

        #expect(html.contains("src=\"https://media.example/master.m3u8\""))
        #expect(html.contains("src=\"data:text/vtt;base64,"))
        #expect(html.contains("label=\"English &quot;CC&quot;\""))
        #expect(html.contains("kind=\"captions\""))
        #expect(html.contains("srclang=\"en\""))
        #expect(html.contains(" default>"))
        #expect(html.contains("default-src 'none'"))
    }

    @Test func animeSubtitleLoaderSendsProviderHeadersAndSurfacesHTTPFailures() async throws {
        let trackURL = try #require(URL(string: "https://media.example/English.vtt"))
        let track = AnimeSubtitleTrack(
            fileURL: trackURL,
            label: "English",
            kind: "captions",
            languageCode: "en",
            isDefault: true
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SubtitleURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            SubtitleURLProtocol.reset()
            session.invalidateAndCancel()
        }

        SubtitleURLProtocol.install { request in
            let response = try #require(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 403,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )
            )
            return (response, Data())
        }

        do {
            _ = try await AnimeSubtitleLoader.load([track], session: session)
            Issue.record("Expected HTTP 403 to be surfaced by the subtitle loader.")
        } catch let error as AnimeSubtitleLoadError {
            #expect(error == .http(label: "English", statusCode: 403))
        }

        let rejectedURL = try #require(URL(string: "https://media.example/French.vtt"))
        let rejectedTrack = AnimeSubtitleTrack(
            fileURL: rejectedURL,
            label: "French",
            kind: "captions",
            languageCode: "fr",
            isDefault: false
        )
        SubtitleURLProtocol.install { request in
            let isWorkingTrack = request.url == trackURL
            guard request.value(forHTTPHeaderField: "Accept")
                == "text/vtt,text/plain;q=0.9,*/*;q=0.1" else {
                throw SubtitleProtocolError.invalidHeader("Accept")
            }
            guard request.value(forHTTPHeaderField: "User-Agent") == "Mozilla/5.0" else {
                throw SubtitleProtocolError.invalidHeader("User-Agent")
            }
            let response = try #require(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: isWorkingTrack ? 200 : 403,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "text/vtt"]
                )
            )
            let data = isWorkingTrack
                ? Data("WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nHello".utf8)
                : Data()
            return (response, data)
        }

        let loadedTracks = try await AnimeSubtitleLoader.load([track], session: session)
        #expect(loadedTracks.first?.fileURL.scheme == "data")

        let partialResult = await AnimeSubtitleLoader.loadAvailable(
            [track, rejectedTrack],
            session: session
        )
        #expect(partialResult.tracks.map(\.label) == ["English"])
        #expect(partialResult.failures == [
            "The French subtitle track returned HTTP 403.",
        ])

        let insecureTrack = AnimeSubtitleTrack(
            fileURL: try #require(URL(string: "http://media.example/English.vtt")),
            label: "English",
            kind: "captions",
            languageCode: "en",
            isDefault: true
        )
        do {
            _ = try await AnimeSubtitleLoader.load([insecureTrack], session: session)
            Issue.record("Expected an insecure subtitle URL to be rejected.")
        } catch let error as AnimeSubtitleLoadError {
            #expect(error == .invalidSource(label: "English"))
        }

        let redirectDelegate = AnimeSubtitleRedirectDelegate()
        let redirectResponse = try #require(
            HTTPURLResponse(
                url: trackURL,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": "http://media.example/English.vtt"]
            )
        )
        let insecureRedirect = URLRequest(
            url: try #require(URL(string: "http://media.example/English.vtt"))
        )
        let redirectResult = await redirectDelegate.urlSession(
            session,
            task: session.dataTask(with: trackURL),
            willPerformHTTPRedirection: redirectResponse,
            newRequest: insecureRedirect
        )
        #expect(redirectResult == nil)
        #expect(redirectDelegate.blockedRedirect)
    }

    @Test func embeddedMediaNavigationAllowsOnlySecureRemotePages() throws {
        let secureURL = try #require(URL(string: "https://player.example/embed/42"))
        let insecureURL = try #require(URL(string: "http://player.example/embed/42"))
        let credentialURL = try #require(URL(string: "https://name:secret@player.example/embed/42"))
        let blankURL = try #require(URL(string: "about:blank"))

        #expect(MediaNavigationPolicy.isSecureRemoteURL(secureURL))
        #expect(!MediaNavigationPolicy.isSecureRemoteURL(insecureURL))
        #expect(!MediaNavigationPolicy.isSecureRemoteURL(credentialURL))
        #expect(!MediaNavigationPolicy.isSecureRemoteURL(blankURL))
        #expect(MediaNavigationPolicy.isSafeSubframeURL(blankURL))

        var navigation = MediaNavigationState(initialURL: secureURL)
        let redirectURL = try #require(URL(string: "https://redirect.example/player/42"))
        let advertisingURL = try #require(URL(string: "https://ads.example/landing"))

        let allowsNewWindow = navigation.allows(advertisingURL, target: .newWindow)
        let allowsBlankSubframe = navigation.allows(blankURL, target: .subframe)
        let allowsInitialRedirect = navigation.allows(
            redirectURL,
            target: .topLevel(isUserLink: false)
        )
        navigation.markInitialNavigationFinished()
        let allowsKnownRedirect = navigation.allows(
            redirectURL,
            target: .topLevel(isUserLink: false)
        )
        let allowsAdvertisingNavigation = navigation.allows(
            advertisingURL,
            target: .topLevel(isUserLink: false)
        )
        let allowsInsecureNavigation = navigation.allows(
            insecureURL,
            target: .topLevel(isUserLink: false)
        )

        #expect(!allowsNewWindow)
        #expect(allowsBlankSubframe)
        #expect(allowsInitialRedirect)
        #expect(allowsKnownRedirect)
        #expect(!allowsAdvertisingNavigation)
        #expect(!allowsInsecureNavigation)
        #expect(MediaNavigationPolicy.allowsHTTPStatus(200))
        #expect(MediaNavigationPolicy.allowsHTTPStatus(399))
        #expect(!MediaNavigationPolicy.allowsHTTPStatus(400))
    }

    @Test func animeSubtitleMetadataDefaultsWithoutLosingTheStream() throws {
        let data = Data(
            ##"[{"quality":"HD","server":"VidPlay","source":"https://media.example/master.m3u8","tracks":[{"file":"https://media.example/English.vtt"}],"url":"https://vidtube.site/stream/episode/sub"}]"##.utf8
        )

        let source = try #require(animeDecoder.decode([AnimeStreamSource].self, from: data).first)
        let track = try #require(source.tracks.first)

        #expect(track.label == "Subtitles")
        #expect(track.kind == "subtitles")
        #expect(track.languageCode == nil)
        #expect(!track.isDefault)
    }

    @Test func animeDirectPlaybackUsesHeadersFromItsProviderPage() throws {
        let source = AnimeStreamSource(
            server: "Vidstream-2",
            embedURL: URL(string: "https://megaplay.buzz/stream/s-2/735790/sub")!,
            quality: "HD",
            directURL: URL(string: "https://cdn.mewstream.buzz/anime/title/master.m3u8")!,
            tracks: []
        )

        let option = try #require(
            AnimePlaybackOption.options(from: [source]).first { $0.kind == .direct }
        )

        #expect(option.requestHeaders["Referer"] == "https://megaplay.buzz/")
        #expect(option.requestHeaders["Origin"] == "https://megaplay.buzz")
        #expect(option.requestHeaders["User-Agent"] == "Mozilla/5.0")
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

    @Test func longNovelChapterListsSplitIntoSearchableHundredChapterRanges() {
        let chapters = (1...250).reversed().map {
            Chapter(id: "chapter-\($0)", chapterNumber: $0, title: "Chapter \($0)", content: nil, url: nil)
        }

        let ranges = NovelChapterRange.pages(for: chapters)

        #expect(ranges.map(\.label) == ["1–100", "101–200", "201–250"])
        #expect(ranges[1].chapters.count == 100)
        #expect(ranges[2].contains(chapterID: "chapter-250"))
        #expect(!ranges[0].contains(chapterID: "chapter-250"))
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

private enum SubtitleProtocolError: Error {
    case invalidHeader(String)
}

private final class SubtitleURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?

    static func install(_ handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
