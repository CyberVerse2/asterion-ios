import Foundation
import Testing
@testable import AsterionMac

/// The Handoff contract shared with the iOS app. Paragraph indices and unit
/// ids must mean the same thing on both sides.
struct HandoffContractTests {
    @Test func paragraphsMatchTheIOSReaderSplit() {
        let chapter = Chapter(
            id: "chapter-12",
            chapterNumber: 12,
            title: "Chapter 12: The Gate",
            content: """
            <p>Chapter 12: The Gate</p><p>The Gate</p>\
            <p>Translator: Someone</p>\
            <p>  First   real   line.  </p>\
            <p>&nbsp;</p>\
            <p>Join us on Discord!</p>\
            <p>Second &amp; last.<br/>Third.</p>\
            <p>Read at www.example.com</p>
            """,
            url: nil
        )

        // iOS drops the headings, credits and plugs, collapses whitespace and
        // keeps the "&nbsp;" line, so the macOS indices line up with it.
        #expect(chapter.paragraphs == ["First real line.", "", "Second & last.", "Third."])
    }

    @Test func resolveLinePrefersTheIndexWhenCountsAgree() {
        #expect(AsterionHandoff.resolveLine(line: 7, lineCount: 20, progress: 0.9, paragraphCount: 20) == 7)
        // Older senders send only the index.
        #expect(AsterionHandoff.resolveLine(line: 7, lineCount: nil, progress: nil, paragraphCount: 20) == 7)
        #expect(AsterionHandoff.resolveLine(line: 70, lineCount: nil, progress: nil, paragraphCount: 20) == 19)
    }

    @Test func resolveLineFallsBackToTheFractionWhenCountsDiffer() {
        #expect(AsterionHandoff.resolveLine(line: 10, lineCount: 21, progress: 0.5, paragraphCount: 41) == 20)
        #expect(AsterionHandoff.resolveLine(line: nil, lineCount: nil, progress: 1, paragraphCount: 5) == 4)
        #expect(AsterionHandoff.resolveLine(line: nil, lineCount: nil, progress: nil, paragraphCount: 5) == nil)
    }

    @Test func readingRequestToleratesMissingOptionalKeys() throws {
        let activity = NSUserActivity(activityType: AsterionHandoff.readingActivityType)
        activity.userInfo = ["novelId": "novel-1", "chapterId": "chapter-1", "line": 3]

        let request = try #require(AsterionHandoff.ReadingRequest(activity: activity))

        #expect(request.route == ReaderRoute(novelID: "novel-1", chapterID: "chapter-1"))
        #expect(request.resolvedLine(paragraphCount: 10) == 3)
        #expect(request.novelTitle == "")
    }

    @Test func animeUnitIDsTranslateBetweenTheContractAndMacEpisodeIDs() {
        #expect(AsterionHandoff.handoffAnimeUnitID(fromEpisodeID: "abc-12:5") == "abc-12-5")
        #expect(AsterionHandoff.animeEpisodeID(fromHandoffUnitID: "abc-12-5") == "abc-12:5")
        // Already in macOS form, or not an episode id at all: left alone.
        #expect(AsterionHandoff.animeEpisodeID(fromHandoffUnitID: "abc:5") == "abc:5")
        #expect(AsterionHandoff.animeEpisodeID(fromHandoffUnitID: "") == "")
        #expect(AsterionHandoff.handoffAnimeUnitID(fromEpisodeID: "plain") == "plain")
    }

    @Test func watchingRequestFromIOSResolvesTheMacEpisode() throws {
        let activity = NSUserActivity(activityType: AsterionHandoff.watchingActivityType)
        activity.userInfo = [
            "mediaType": "anime",
            "contentId": "frieren",
            "unitId": "x9k2-4",
            "positionSeconds": 312.5,
            "title": "Frieren",
        ]

        let request = try #require(AsterionHandoff.WatchingRequest(activity: activity))

        #expect(request.unitID == "x9k2:4")
        #expect(request.animeRoute.initialEpisodeID == "x9k2:4")
        #expect(request.positionSeconds == 312.5)
    }

    @Test func filmWatchingRequestHasNoEpisode() throws {
        let activity = NSUserActivity(activityType: AsterionHandoff.watchingActivityType)
        activity.userInfo = ["mediaType": "movie", "contentId": "dune", "unitId": "", "title": "Dune"]

        let request = try #require(AsterionHandoff.WatchingRequest(activity: activity))

        #expect(request.episodeID == nil)
        #expect(request.movieRoute.initialEpisodeID == nil)
        #expect(request.positionSeconds == nil)
    }
}
