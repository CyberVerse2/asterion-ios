import Foundation
import Testing
@testable import Asterion

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
