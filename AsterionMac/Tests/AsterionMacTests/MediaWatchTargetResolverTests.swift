import Foundation
import Testing
@testable import AsterionMac

struct MediaWatchTargetResolverTests {
    @Test func completedEpisodeAdvancesToTheNextEpisode() throws {
        let target = try #require(
            MediaWatchTargetResolver.resolve(
                orderedUnitIDs: ["episode-1", "episode-2", "episode-3"],
                progress: progress(unitID: "episode-2", percentage: 100, completed: true, at: 20),
                history: [history(unitID: "episode-2", percentage: 100, completed: true, at: 20)]
            )
        )

        #expect(target == MediaWatchTarget(unitID: "episode-3", action: .next))
    }

    @Test func completedEpisodesAreSkippedWhenChoosingWhatComesNext() throws {
        let target = try #require(
            MediaWatchTargetResolver.resolve(
                orderedUnitIDs: ["episode-1", "episode-2", "episode-3", "episode-4"],
                progress: progress(unitID: "episode-2", percentage: 100, completed: true, at: 30),
                history: [
                    history(unitID: "episode-2", percentage: 100, completed: true, at: 30),
                    history(unitID: "episode-3", percentage: 100, completed: true, at: 20),
                ]
            )
        )

        #expect(target == MediaWatchTarget(unitID: "episode-4", action: .next))
    }

    @Test func completedSeasonFinaleAdvancesToTheNextSeason() throws {
        let target = try #require(
            MediaWatchTargetResolver.resolve(
                orderedUnitIDs: ["s1-e1", "s1-e2", "s2-e1"],
                progress: progress(unitID: "s1-e2", percentage: 100, completed: true, at: 20),
                history: [history(unitID: "s1-e2", percentage: 100, completed: true, at: 20)]
            )
        )

        #expect(target == MediaWatchTarget(unitID: "s2-e1", action: .next))
    }

    @Test func incompleteCurrentEpisodeResumesEvenIfItsHistoryWasPreviouslyCompleted() throws {
        let target = try #require(
            MediaWatchTargetResolver.resolve(
                orderedUnitIDs: ["episode-1", "episode-2", "episode-3"],
                progress: progress(unitID: "episode-2", percentage: 35, completed: false, at: 40),
                history: [history(unitID: "episode-2", percentage: 100, completed: true, at: 40)]
            )
        )

        #expect(target == MediaWatchTarget(unitID: "episode-2", action: .resume(percentage: 35)))
    }

    @Test func newestWatchRecordWinsAcrossProgressAndHistory() throws {
        let target = try #require(
            MediaWatchTargetResolver.resolve(
                orderedUnitIDs: ["episode-1", "episode-2", "episode-3", "episode-4"],
                progress: progress(unitID: "episode-2", percentage: 100, completed: true, at: 20),
                history: [history(unitID: "episode-4", percentage: 42, completed: false, at: 50)]
            )
        )

        #expect(target == MediaWatchTarget(unitID: "episode-4", action: .resume(percentage: 42)))
    }

    @Test func fullyCompletedTitleOffersARewatchFromTheFirstUnit() throws {
        let target = try #require(
            MediaWatchTargetResolver.resolve(
                orderedUnitIDs: ["episode-1", "episode-2"],
                progress: progress(unitID: "episode-2", percentage: 100, completed: true, at: 20),
                history: [
                    history(unitID: "episode-1", percentage: 100, completed: true, at: 10),
                    history(unitID: "episode-2", percentage: 100, completed: true, at: 20),
                ]
            )
        )

        #expect(target == MediaWatchTarget(unitID: "episode-1", action: .rewatch))
    }

    @Test func completedStandaloneMovieOffersARewatch() throws {
        let target = try #require(
            MediaWatchTargetResolver.resolve(
                orderedUnitIDs: ["movie"],
                progress: progress(unitID: "movie", percentage: 100, completed: true, at: 20),
                history: [history(unitID: "movie", percentage: 100, completed: true, at: 20)]
            )
        )

        #expect(target == MediaWatchTarget(unitID: "movie", action: .rewatch))
    }

    @Test func unwatchedTitleStartsFromTheFirstUnit() throws {
        let target = try #require(
            MediaWatchTargetResolver.resolve(
                orderedUnitIDs: ["episode-1", "episode-2"],
                progress: nil,
                history: []
            )
        )

        #expect(target == MediaWatchTarget(unitID: "episode-1", action: .start))
    }

    private func progress(
        unitID: String,
        percentage: Double,
        completed: Bool,
        at timestamp: TimeInterval
    ) -> MediaPlaybackProgress {
        let date = Date(timeIntervalSince1970: timestamp)
        return MediaPlaybackProgress(
            id: "progress-\(unitID)",
            userId: "user",
            mediaType: .anime,
            contentId: "show",
            title: "Show",
            imageURL: nil,
            unitId: unitID,
            unitTitle: nil,
            seasonNumber: nil,
            episodeNumber: nil,
            positionSeconds: percentage,
            durationSeconds: 100,
            percentage: percentage,
            completed: completed,
            clientUpdatedAt: date,
            createdAt: date,
            updatedAt: date
        )
    }

    private func history(
        unitID: String,
        percentage: Double,
        completed: Bool,
        at timestamp: TimeInterval
    ) -> MediaHistoryEntry {
        let date = Date(timeIntervalSince1970: timestamp)
        return MediaHistoryEntry(
            id: "history-\(unitID)",
            userId: "user",
            mediaType: .anime,
            contentId: "show",
            title: "Show",
            imageURL: nil,
            unitId: unitID,
            unitTitle: nil,
            seasonNumber: nil,
            episodeNumber: nil,
            positionSeconds: percentage,
            durationSeconds: 100,
            percentage: percentage,
            completed: completed,
            visitCount: 1,
            clientUpdatedAt: date,
            firstViewedAt: date,
            lastViewedAt: date,
            createdAt: date,
            updatedAt: date
        )
    }
}
