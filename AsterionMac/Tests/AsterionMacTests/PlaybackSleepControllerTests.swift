import Foundation
import Testing
@testable import AsterionMac

@MainActor
struct PlaybackSleepControllerTests {
    @Test func activePlaybackPreventsSleepUntilEverySourceStops() {
        let probe = PlaybackActivityProbe()
        let controller = PlaybackSleepController(
            beginActivity: { probe.begin() },
            endActivity: { probe.end($0) }
        )

        controller.setPlaying(true, sourceID: "player-a")
        controller.setPlaying(true, sourceID: "player-a")
        controller.setPlaying(true, sourceID: "player-b")

        #expect(probe.beginCount == 1)
        #expect(probe.endCount == 0)

        controller.setPlaying(false, sourceID: "player-a")
        #expect(probe.endCount == 0)

        controller.setPlaying(false, sourceID: "player-b")
        controller.setPlaying(false, sourceID: "player-b")

        #expect(probe.beginCount == 1)
        #expect(probe.endCount == 1)
    }

    @Test func stoppingThePlayerReleasesItsSleepActivity() {
        let probe = PlaybackActivityProbe()
        let controller = PlaybackSleepController(
            beginActivity: { probe.begin() },
            endActivity: { probe.end($0) }
        )

        controller.setPlaying(true, sourceID: "embedded-frame")
        controller.stopAll()
        controller.stopAll()

        #expect(probe.beginCount == 1)
        #expect(probe.endCount == 1)
    }

    @Test func webPlayersReportPlaybackLifecycleToTheNativeController() throws {
        let videoURL = try #require(URL(string: "https://media.example/master.m3u8"))
        let captionedDocument = CaptionedMediaDocument.html(
            url: videoURL,
            tracks: []
        )
        let embeddedScript = EmbeddedMediaProgressScript.source(initialPosition: 0)

        #expect(captionedDocument.contains("type: 'playback', isPlaying: true"))
        #expect(captionedDocument.contains("type: 'playback', isPlaying: false"))
        #expect(embeddedScript.contains("type: 'playback', sourceID, isPlaying"))
        #expect(embeddedScript.contains("reportPlaybackActivity(activePlayer !== null)"))
        #expect(embeddedScript.contains("reportPlaybackActivity(false)"))
    }
}

@MainActor
private final class PlaybackActivityProbe {
    private(set) var beginCount = 0
    private(set) var endCount = 0

    func begin() -> any NSObjectProtocol {
        beginCount += 1
        return NSObject()
    }

    func end(_ activity: any NSObjectProtocol) {
        endCount += 1
    }
}
