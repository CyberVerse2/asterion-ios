import Foundation
import Testing
@testable import AsterionKit

struct MediaProgressTests {
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
}

struct MediaContinuePolicyTests {
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
}

struct DownloadAheadPolicyTests {
    @Test
    func videoDownloadPathsSurviveIOS26PathsAndReinstalls() {
        let device = "/.nofollow/private/var/mobile/Containers/Data/Application/2B6E3794-15CA-480C-912C-4E87A8700797/Library/com.apple.UserManagedAssets.9lmNoF/Show_1.movpkg"
        #expect(OfflineVideoPaths.containerRelativePath(device)
            == "Library/com.apple.UserManagedAssets.9lmNoF/Show_1.movpkg")
        let relative = "Library/com.apple.UserManagedAssets.9lmNoF/Show_1.movpkg"
        #expect(OfflineVideoPaths.containerRelativePath(relative) == relative)
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
        #expect(DownloadAheadPolicy.isWatchedPast(unit(10), latest: watching11))
        #expect(!DownloadAheadPolicy.isWatchedPast(unit(11), latest: watching11))
        #expect(!DownloadAheadPolicy.isWatchedPast(unit(12), latest: watching11))
        // Finished 11: 11 can go too.
        let finished11 = playbackProgress(unitId: "1-11", episodeNumber: 11, completed: true, positionSeconds: 1_000)
        #expect(DownloadAheadPolicy.isWatchedPast(unit(11), latest: finished11))
    }

    @Test
    func downloadAheadQueuesRecentShowsEvenAfterAFinishedEpisode() {
        let now = Date()
        let finishedRecently = playbackProgress(unitId: "1-8", episodeNumber: 8, completed: true, positionSeconds: 1_000, updatedAt: now)
        let abandoned = playbackProgress(unitId: "1-9", episodeNumber: 9, completed: false, positionSeconds: 2, updatedAt: now.addingTimeInterval(-40 * 24 * 3600))
        #expect(DownloadAheadPolicy.showsToQueue(from: [finishedRecently], now: now).count == 1)
        #expect(DownloadAheadPolicy.showsToQueue(from: [abandoned], now: now).isEmpty)
    }
}

struct MediaRecentActivityTests {
    @Test
    func watchingManyEpisodesUsesOnlyOneRecentSlotPerShow() {
        let episodes = (1...12).map { episode in
            entry(id: "episode-\(episode)", contentId: "show", episode: episode, time: Double(episode))
        }
        let recent = MediaHistoryEntry.latestPerTitle(episodes.reversed())

        #expect(recent.count == 1)
        #expect(recent.first?.episodeNumber == 12)
    }

    @Test
    func rewatchingAnEarlierEpisodeMakesItTheLatestActivity() {
        let recent = MediaHistoryEntry.latestPerTitle([
            entry(id: "episode-10", contentId: "show", episode: 10, time: 100),
            entry(id: "episode-2", contentId: "show", episode: 2, time: 200),
            entry(id: "other", contentId: "other-show", episode: 1, time: 150)
        ])

        #expect(recent.map(\.contentId) == ["show", "other-show"])
        #expect(recent.first?.episodeNumber == 2)
    }

    @Test
    func titlesWithTheSameIdInDifferentMediaTypesStaySeparate() {
        let recent = MediaHistoryEntry.latestPerTitle([
            entry(id: "anime", contentId: "shared-id", type: .anime, episode: 1, time: 100),
            entry(id: "tv", contentId: "shared-id", type: .movie, episode: 1, time: 200)
        ])

        #expect(recent.map(\.mediaType) == [.movie, .anime])
    }

    private func entry(id: String, contentId: String, type: MediaAccountType = .anime,
                       episode: Int, time: Double) -> MediaHistoryEntry {
        let date = Date(timeIntervalSince1970: time)
        return MediaHistoryEntry(
            id: id, userId: "user", mediaType: type, contentId: contentId, title: contentId,
            imageURL: nil, unitId: "\(episode)", unitTitle: "Episode \(episode)", seasonNumber: 1,
            episodeNumber: episode, positionSeconds: 100, durationSeconds: 1_000,
            percentage: 10, completed: false, visitCount: 1, clientUpdatedAt: date,
            firstViewedAt: date, lastViewedAt: date, createdAt: date, updatedAt: date
        )
    }
}
