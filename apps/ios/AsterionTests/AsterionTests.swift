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
    func mobileShellKeepsTheFiveTaskDestinations() {
        #expect(AsterionTab.allCases == [.home, .browse, .library, .downloads, .account])
        #expect(Set(AsterionTab.allCases.map(\.label)).count == AsterionTab.allCases.count)
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
    func mediaAccountSupportsEveryLaunchContentType() {
        #expect(Set(MediaAccountType.allCases) == [.anime, .movie, .football])
    }

    @Test
    func playbackPreparationOverlayTimeoutIsTenSeconds() {
        #expect(PlaybackPreparationPolicy.resolvingOverlayTimeout == 10)
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
