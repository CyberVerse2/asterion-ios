import Foundation
import Testing
@testable import AsterionMac

@MainActor
struct PlaybackSleepControllerTests {
    @Test func keyboardSeekPreservesPlaybackIntent() {
        #expect(
            NativeMediaSeekPolicy.shouldResume(
                playbackRate: 1,
                timeControlStatus: .playing
            )
        )
        #expect(
            NativeMediaSeekPolicy.shouldResume(
                playbackRate: 0,
                timeControlStatus: .waitingToPlayAtSpecifiedRate
            )
        )
        #expect(
            !NativeMediaSeekPolicy.shouldResume(
                playbackRate: 0,
                timeControlStatus: .paused
            )
        )
    }

    @Test func nativePlayerKeyboardControlsUseStandardVideoBindings() {
        #expect(
            NativeMediaKeyboardCommand.resolve(
                keyCode: 123,
                charactersIgnoringModifiers: nil,
                modifiers: []
            ) == .seek(-10)
        )
        #expect(
            NativeMediaKeyboardCommand.resolve(
                keyCode: 124,
                charactersIgnoringModifiers: nil,
                modifiers: []
            ) == .seek(10)
        )
        #expect(
            NativeMediaKeyboardCommand.resolve(
                keyCode: 126,
                charactersIgnoringModifiers: nil,
                modifiers: []
            ) == .adjustVolume(0.1)
        )
        #expect(
            NativeMediaKeyboardCommand.resolve(
                keyCode: 125,
                charactersIgnoringModifiers: nil,
                modifiers: []
            ) == .adjustVolume(-0.1)
        )
        #expect(
            NativeMediaKeyboardCommand.resolve(
                keyCode: 46,
                charactersIgnoringModifiers: "m",
                modifiers: []
            ) == .toggleMute
        )
        #expect(
            NativeMediaKeyboardCommand.resolve(
                keyCode: 49,
                charactersIgnoringModifiers: " ",
                modifiers: []
            ) == .togglePlayback
        )
    }

    @Test func nativePlayerLeavesModifiedArrowShortcutsToTheApp() {
        #expect(
            NativeMediaKeyboardCommand.resolve(
                keyCode: 124,
                charactersIgnoringModifiers: nil,
                modifiers: [.command]
            ) == nil
        )
    }

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

    @Test func nativePlaybackPreventsSleepWhilePlayingOrBuffering() {
        #expect(
            PlaybackSleepController.shouldPreventSleep(
                playbackRate: 1,
                isPlaybackPaused: false
            )
        )
        #expect(
            PlaybackSleepController.shouldPreventSleep(
                playbackRate: 0,
                isPlaybackPaused: false
            )
        )
        #expect(
            !PlaybackSleepController.shouldPreventSleep(
                playbackRate: 0,
                isPlaybackPaused: true
            )
        )
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

    @Test func webPlayersCheckpointProgressBeforeReportingPlaybackFailure() throws {
        let videoURL = try #require(URL(string: "https://media.example/master.m3u8"))
        let captionedDocument = CaptionedMediaDocument.html(
            url: videoURL,
            tracks: []
        )
        let embeddedScript = EmbeddedMediaProgressScript.source(initialPosition: 120)

        let captionedError = try #require(
            captionedDocument.range(of: "reportError('The video source could not be played.');")
        )
        let captionedCheckpoint = try #require(
            captionedDocument[..<captionedError.lowerBound]
                .range(of: "reportProgress(true);", options: .backwards)
        )
        let embeddedError = try #require(
            embeddedScript.range(of: "reportMediaError(player);")
        )
        let embeddedCheckpoint = try #require(
            embeddedScript[..<embeddedError.lowerBound]
                .range(of: "if (activePlayer === player) emit(player, true);", options: .backwards)
        )

        #expect(captionedCheckpoint.upperBound <= captionedError.lowerBound)
        #expect(embeddedCheckpoint.upperBound <= embeddedError.lowerBound)
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
