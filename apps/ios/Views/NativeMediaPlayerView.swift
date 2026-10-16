import AVFoundation
import AVKit
import Combine
import SwiftUI
import UIKit
import WebKit

enum PlaybackOrientationLock {
    static var mask: UIInterfaceOrientationMask = defaultMask

    static var defaultMask: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
    }

    @MainActor
    static func beginVideo() {
        mask = .landscape
        apply(.landscape)
    }

    @MainActor
    static func endVideo() {
        mask = defaultMask
        apply(defaultMask)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            apply(defaultMask)
            try? await Task.sleep(for: .milliseconds(200))
            apply(defaultMask)
        }
    }

    @MainActor
    private static func apply(_ orientations: UIInterfaceOrientationMask) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        scene?.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { _ in }
    }
}

enum PlaybackPreparationPolicy {
    static let resolvingOverlayTimeout: TimeInterval = 10
}

struct NativeMediaPlayerView: View {
    let request: PlaybackRequest

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var mediaAccountService: MediaAccountService
    @EnvironmentObject private var offlineVideoDownloadService: OfflineVideoDownloadService
    @State private var activeRequest: PlaybackRequest
    @State private var queue: PlaybackQueue?
    @State private var player: AVPlayer?
    @State private var isResolvingNext = false
    @State private var showResolvingOverlay = false
    @State private var advanceTask: Task<Void, Never>?
    @State private var resolvingOverlayTask: Task<Void, Never>?
    @State private var advanceError: String?
    @State private var playbackError: String?
    @State private var playbackAdvanceObserver: Any?
    @State private var lastObservedPosition = -Double.infinity
    @State private var sleepTask: Task<Void, Never>?
    @State private var sleepMinutes: Int?
    @State private var progressTask: Task<Void, Never>?
    @State private var captionTask: Task<Void, Never>?
    @State private var captionObserver: Any?
    @State private var captionCues: [WebVTTCue] = []
    @State private var activeCaption: String?
    @State private var playbackSessionID = UUID()
    @State private var watchingRateCancellable: AnyCancellable?
    @State private var watchingIsPlaying: Bool?

    init(request: PlaybackRequest) {
        self.request = request
        _activeRequest = State(initialValue: request)
        _queue = State(initialValue: request.queue)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                NativePlayerController(
                    player: player,
                    extras: PlayerChromeExtras(
                        title: activeRequest.title,
                        canDownload: activeRequest.directURL != nil,
                        isDownloaded: offlineVideoDownloadService.isDownloaded(activeRequest),
                        downloadProgress: offlineVideoDownloadService.progress(for: activeRequest),
                        sleepMinutes: sleepMinutes,
                        canPlayNext: canAdvance(by: 1),
                        canPlayPrevious: canAdvance(by: -1),
                        isResolvingNext: isResolvingNext,
                        streamOptions: activeRequest.options.map {
                            PlaybackStreamChoice(id: $0.id, title: $0.title)
                        },
                        selectedStreamID: activeRequest.selectedOptionID
                    ),
                    onClose: closePlayer,
                    onPlaybackFailure: { reportPlaybackFailure($0) },
                    onDownload: {
                        if !offlineVideoDownloadService.isDownloaded(activeRequest) {
                            offlineVideoDownloadService.start(activeRequest)
                        }
                    },
                    onSetSleep: setSleepTimer,
                    onEnded: handlePlaybackEnded,
                    onPlayNext: { advance(by: 1) },
                    onPlayPrevious: { advance(by: -1) },
                    onSelectStream: selectStream
                )
                .ignoresSafeArea()
                captionOverlay
                if activeRequest.options.count > 1 {
                    nativeStreamPickerOverlay
                }
                if showResolvingOverlay {
                    preparingOverlay
                }
                if let playbackError {
                    PlaybackFailureView(
                        message: playbackError,
                        options: activeRequest.options,
                        selectedOptionID: activeRequest.selectedOptionID,
                        onSelect: selectStream
                    ) {
                        retryPlayback()
                    }
                }
            } else if showResolvingOverlay || activeRequest.directURL != nil {
                preparingOverlay
                embedCloseOverlay
            } else if let embedURL = activeRequest.embedURL {
                EmbeddedMediaPlayer(url: embedURL)
                    .id(activeRequest.selectedOptionID ?? embedURL.absoluteString)
                    .ignoresSafeArea()
                embedCloseOverlay
            } else {
                AsterionEmptyState(
                    symbol: "exclamationmark.triangle",
                    title: "Playback unavailable",
                    message: "No playable source came back for this title. Close the player and try another episode or source."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                embedCloseOverlay
            }

            if let advanceError {
                VStack {
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.asterionWarning)
                        Text(advanceError)
                            .font(.asterionReading(14, weight: .medium))
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(Color.asterionText)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(PlayerSmokedCapsule())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 120)
                }
                .allowsHitTesting(false)
            }
        }
        .background {
            WatchingHandoffAdvertiser(payload: handoffPayload) {
                guard let seconds = player?.currentTime().seconds, seconds.isFinite else { return nil }
                return max(0, seconds)
            }
        }
        .edgeSwipeToDismiss { closePlayer() }
        .task { preparePlayer() }
        .onAppear { PlaybackOrientationLock.beginVideo() }
        .onDisappear {
            sleepTask?.cancel()
            advanceTask?.cancel()
            resolvingOverlayTask?.cancel()
            tearDownCurrentItem(saveProgress: true)
            player?.pause()
            player = nil
            WatchingLiveActivityManager.shared.end()
            PlaybackOrientationLock.endVideo()
        }
        .statusBarHidden()
    }

    /// Loading: the artwork's tint glowing in the dark, a small spinner, and
    /// one muted line.
    private var preparingOverlay: some View {
        ZStack {
            if player != nil {
                Color.black.opacity(0.6)
            }
            ArtworkToneReader(url: activeRequest.playback?.item.imageURL) { tone in
                RadialGradient(
                    colors: [tone.opacity(0.32), tone.opacity(0.08), .clear],
                    center: .center,
                    startRadius: 4,
                    endRadius: 300
                )
            }
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.regular)
                    .tint(Color.asterionText)
                Text(showResolvingOverlay ? "Loading next episode…" : "Preparing video…")
                    .font(.asterionReading(14, weight: .medium))
                    .foregroundStyle(Color.asterionMuted)
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showResolvingOverlay ? "Loading next episode" : "Loading video")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var nativeStreamPickerOverlay: some View {
        VStack {
            HStack {
                Spacer()
                streamPickerMenu
            }
            Spacer()
        }
        .padding(16)
    }

    private var embedCloseOverlay: some View {
        VStack {
            HStack {
                Button(action: closePlayer) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                        .frame(width: 40, height: 40)
                        .background(PlayerSmokedCircle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close player")
                Spacer()
                if activeRequest.options.count > 1 {
                    streamPickerMenu
                }
            }
            Spacer()
        }
        .padding(16)
    }

    private var streamPickerMenu: some View {
        Menu {
            ForEach(activeRequest.options) { option in
                Button {
                    selectStream(option.id)
                } label: {
                    if activeRequest.selectedOptionID == option.id {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                Text(activeRequest.selectedOption?.title ?? "Source")
                    .font(.asterionMono(11.5, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 170)
                    .fixedSize()
            }
            .foregroundStyle(Color.asterionText)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(PlayerSmokedCapsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(activeRequest.selectedOption?.title ?? "Playback source")
    }

    private func closePlayer() {
        PlaybackOrientationLock.endVideo()
        dismiss()
    }

    private func retryPlayback() {
        playbackError = nil
        preparePlayer()
    }

    private func reportPlaybackFailure(_ message: String) {
        if let option = activeRequest.selectedOption, activeRequest.options.count > 1 {
            playbackError = "\(option.title) failed. Choose another source.\n\(message)"
        } else {
            playbackError = message
        }
    }

    private func selectStream(_ optionID: String) {
        guard let option = activeRequest.options.first(where: { $0.id == optionID }) else { return }
        guard option.id != activeRequest.selectedOptionID else { return }
        let resume = player?.currentTime().seconds
        saveCurrentProgress()
        playbackError = nil
        tearDownCurrentItem(saveProgress: false)
        player?.pause()
        player = nil
        activeRequest = activeRequest.selecting(option)
        if option.kind == .direct {
            preparePlayer(resumeOverride: resume)
        } else {
            // Embedded players report no position to drive the activity.
            WatchingLiveActivityManager.shared.end()
        }
    }

    private func preparePlayer(resumeOverride: Double? = nil) {
        tearDownCurrentItem(saveProgress: false)
        playbackError = nil
        guard let directURL = offlineVideoDownloadService.localURL(for: activeRequest) ?? activeRequest.directURL else {
            return
        }
        let isLocal = directURL.isFileURL
        let asset = AVURLAsset(
            url: directURL,
            options: isLocal || activeRequest.requestHeaders.isEmpty
                ? nil
                : ["AVURLAssetHTTPHeaderFieldsKey": activeRequest.requestHeaders]
        )
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 20
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        item.externalMetadata = [Self.titleMetadata(activeRequest.title)]
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.allowsExternalPlayback = true
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        newPlayer.defaultRate = 1
        if activeRequest.subtitleTracks.isEmpty {
            newPlayer.appliesMediaSelectionCriteriaAutomatically = false
            Self.selectEmbeddedCaptions(on: item)
        }
        player = newPlayer
        beginPlaybackConfirmation(on: newPlayer)
        beginCaptionReporting(on: newPlayer)

        var startPosition: Double = 0
        if let resumeOverride, resumeOverride.isFinite, resumeOverride > 1 {
            newPlayer.seek(to: CMTime(seconds: resumeOverride, preferredTimescale: 600))
            startPosition = resumeOverride
        } else if let playback = activeRequest.playback,
                  let resumePosition = mediaAccountService.resumePosition(for: playback),
                  resumePosition > 5 {
            newPlayer.seek(to: CMTime(seconds: resumePosition, preferredTimescale: 600))
            startPosition = resumePosition
        }
        beginWatchingActivity(on: newPlayer, startPosition: startPosition)

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        newPlayer.play()
        beginProgressReporting()
    }

    private func canAdvance(by offset: Int) -> Bool {
        queue?.adjacent(of: activeRequest.id, offset: offset) != nil
    }

    private func advance(by offset: Int) {
        guard !isResolvingNext, let next = queue?.adjacent(of: activeRequest.id, offset: offset) else {
            return
        }
        saveCurrentProgress()
        isResolvingNext = true
        showResolvingOverlay = true
        advanceError = nil
        advanceTask?.cancel()
        resolvingOverlayTask?.cancel()
        resolvingOverlayTask = Task {
            try? await Task.sleep(for: .seconds(PlaybackPreparationPolicy.resolvingOverlayTimeout))
            guard !Task.isCancelled else { return }
            showResolvingOverlay = false
        }
        advanceTask = Task {
            do {
                let fetched = try await resolvePlayback(for: next)
                guard !Task.isCancelled else { return }
                replacePlayback(with: fetched)
            } catch {
                guard !Task.isCancelled else { return }
                advanceError = error.localizedDescription
            }
            if !Task.isCancelled {
                isResolvingNext = false
                showResolvingOverlay = false
                resolvingOverlayTask?.cancel()
            }
        }
    }

    private func resolvePlayback(for source: PlaybackSource) async throws -> PlaybackRequest {
        if let record = offlineVideoDownloadService.records.first(where: { $0.id == source.requestID }),
           let localRequest = offlineVideoDownloadService.playbackRequest(for: record) {
            return localRequest
        }
        return try await EntertainmentAPI.shared.fetchPlayback(for: source)
    }

    private func replacePlayback(with nextRequest: PlaybackRequest) {
        tearDownCurrentItem(saveProgress: false)
        player?.pause()
        player = nil
        activeRequest = nextRequest.withQueue(queue)
        playbackSessionID = UUID()
        preparePlayer()
    }

    private func tearDownCurrentItem(saveProgress: Bool) {
        if saveProgress {
            saveCurrentProgress()
        }
        progressTask?.cancel()
        progressTask = nil
        captionTask?.cancel()
        captionTask = nil
        if let captionObserver, let player {
            player.removeTimeObserver(captionObserver)
        }
        captionObserver = nil
        captionCues = []
        activeCaption = nil
        if let playbackAdvanceObserver, let player {
            player.removeTimeObserver(playbackAdvanceObserver)
        }
        playbackAdvanceObserver = nil
        lastObservedPosition = -Double.infinity
        watchingRateCancellable?.cancel()
        watchingRateCancellable = nil
        watchingIsPlaying = nil
    }

    private func beginPlaybackConfirmation(on player: AVPlayer) {
        lastObservedPosition = player.currentTime().seconds
        if let playbackAdvanceObserver {
            player.removeTimeObserver(playbackAdvanceObserver)
        }
        playbackAdvanceObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { time in
            observePlaybackAdvance(position: time.seconds)
        }
    }

    private func observePlaybackAdvance(position: Double) {
        defer { lastObservedPosition = position }
        guard position.isFinite, playbackError == nil else { return }
        guard position > lastObservedPosition + 0.05 else { return }
    }

    private func beginProgressReporting() {
        guard activeRequest.playback != nil else { return }
        progressTask?.cancel()
        progressTask = Task {
            var isFirstReport = true
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(isFirstReport ? 3 : 15))
                guard !Task.isCancelled else { return }
                await reportProgress(started: isFirstReport)
                isFirstReport = false
            }
        }
    }

    private func saveCurrentProgress() {
        guard let playback = activeRequest.playback, let sample = playbackSample else { return }
        let sessionID = playbackSessionID
        Task {
            await mediaAccountService.record(
                playback,
                positionSeconds: sample.position,
                durationSeconds: sample.duration,
                started: false,
                sessionID: sessionID
            )
        }
    }

    private func reportProgress(started: Bool) async {
        guard let playback = activeRequest.playback, let sample = playbackSample else { return }
        updateWatchingActivity()
        await mediaAccountService.record(
            playback,
            positionSeconds: sample.position,
            durationSeconds: sample.duration,
            started: started,
            sessionID: playbackSessionID
        )
    }

    private var playbackSample: (position: Double, duration: Double)? {
        guard let player else { return nil }
        let position = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0
        guard position.isFinite, duration.isFinite, duration > 0 else { return nil }
        return (max(0, position), max(0, duration))
    }

    private var captionOverlay: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                if let activeCaption {
                    Text(activeCaption)
                        .font(.system(size: max(18, geometry.size.height * 0.042), weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 2, x: 0, y: 1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.horizontal, 36)
                        .padding(.bottom, 92)
                        .accessibilityLabel("Subtitles: \(activeCaption)")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }

    private func beginCaptionReporting(on player: AVPlayer) {
        captionTask?.cancel()
        if let captionObserver {
            player.removeTimeObserver(captionObserver)
            self.captionObserver = nil
        }
        captionCues = []
        activeCaption = nil

        let tracks = activeRequest.subtitleTracks
        guard let track = preferredSubtitleTrack(from: tracks) else { return }

        captionTask = Task {
            let cues = await Self.loadSubtitleCues(from: track.fileURL)
            guard !Task.isCancelled else { return }
            captionCues = cues
            let observer = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                queue: .main
            ) { time in
                let seconds = time.seconds
                guard seconds.isFinite else { return }
                activeCaption = WebVTTParser.caption(at: seconds, in: cues)
            }
            captionObserver = observer
        }
    }

    private func preferredSubtitleTrack(from tracks: [AnimeSubtitleTrack]) -> AnimeSubtitleTrack? {
        tracks.first(where: \.isDefault)
            ?? tracks.first(where: { $0.languageCode?.lowercased().hasPrefix("en") == true })
            ?? tracks.first(where: { $0.label.localizedCaseInsensitiveContains("english") })
            ?? tracks.first
    }

    private static func loadSubtitleCues(from url: URL) async -> [WebVTTCue] {
        do {
            if url.isFileURL {
                return try WebVTTParser.parse(fileURL: url)
            }
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, _) = try await URLSession.shared.data(for: request)
            return try WebVTTParser.parse(data: data)
        } catch {
            return []
        }
    }

    private static func selectEmbeddedCaptions(on item: AVPlayerItem) {
        Task {
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) else { return }
            let preferred = AVMediaSelectionGroup.mediaSelectionOptions(
                from: group.options,
                filteredAndSortedAccordingToPreferredLanguages: Locale.preferredLanguages
            ).first
                ?? group.options.first(where: { $0.displayName.localizedCaseInsensitiveContains("english") })
                ?? group.options.first
            if let preferred {
                item.select(preferred, in: group)
            }
        }
    }

    // MARK: Watching Live Activity and Handoff

    /// Anime and movies only; football streams have no meaningful position.
    private var watchingDescriptor: MediaPlaybackDescriptor? {
        guard let playback = activeRequest.playback, playback.item.mediaType != .football else { return nil }
        return playback
    }

    private func handlePlaybackEnded() {
        // Record the episode as finished before anything else plays; the
        // periodic save can be up to 15 s short of the end.
        saveCurrentProgress()
        if canAdvance(by: 1) {
            advance(by: 1)
        } else {
            WatchingLiveActivityManager.shared.end()
        }
    }

    private func beginWatchingActivity(on player: AVPlayer, startPosition: Double) {
        guard let playback = watchingDescriptor else {
            WatchingLiveActivityManager.shared.end()
            return
        }
        watchingIsPlaying = true
        let requestID = activeRequest.id
        Task {
            await WatchingLiveActivityManager.shared.start(
                id: requestID,
                title: playback.item.title,
                mediaType: playback.item.mediaType.rawValue,
                imageURL: playback.item.imageURL?.absoluteString,
                unitLabel: Self.watchingUnitLabel(for: playback),
                positionSeconds: startPosition,
                durationSeconds: 0,
                isPlaying: true
            )
        }
        watchingRateCancellable = player.publisher(for: \.rate)
            .map { $0 > 0 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { isPlaying in
                guard watchingIsPlaying != isPlaying else { return }
                watchingIsPlaying = isPlaying
                updateWatchingActivity()
            }
    }

    /// Called every progress tick (~15 s) and on play/pause.
    private func updateWatchingActivity() {
        guard watchingDescriptor != nil, let player else { return }
        let position = player.currentTime().seconds
        guard position.isFinite else { return }
        let duration = player.currentItem?.duration.seconds ?? 0
        WatchingLiveActivityManager.shared.update(
            positionSeconds: max(0, position),
            durationSeconds: duration.isFinite ? max(0, duration) : 0,
            isPlaying: player.rate > 0
        )
    }

    /// "S1 E3", "Episode 7" or "Film".
    private static func watchingUnitLabel(for playback: MediaPlaybackDescriptor) -> String {
        if isFilm(playback) { return "Film" }
        if let season = playback.seasonNumber, let episode = playback.episodeNumber {
            return "S\(season) E\(episode)"
        }
        if let episode = playback.episodeNumber {
            return "Episode \(episode)"
        }
        return playback.unitTitle ?? "Now playing"
    }

    private static func isFilm(_ playback: MediaPlaybackDescriptor) -> Bool {
        playback.item.mediaType == .movie
            && (playback.unitID == playback.item.contentID
                || (playback.seasonNumber == nil && playback.episodeNumber == nil))
    }

    /// Handoff contract: "cloud.cyberverse.asterion.watching".
    private var handoffPayload: WatchingHandoffPayload? {
        guard player != nil, let playback = watchingDescriptor else { return nil }
        let mediaType: String
        switch playback.item.mediaType {
        case .anime: mediaType = "anime"
        case .movie: mediaType = "movie"
        case .football: return nil
        }
        return WatchingHandoffPayload(
            mediaType: mediaType,
            contentID: playback.item.contentID,
            unitID: Self.isFilm(playback) ? "" : playback.unitID,
            title: playback.item.title,
            imageURL: playback.item.imageURL?.absoluteString
        )
    }

    private func setSleepTimer(minutes: Int?) {
        sleepTask?.cancel()
        sleepMinutes = minutes
        guard let minutes else { return }
        sleepTask = Task {
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            player?.pause()
            sleepMinutes = nil
        }
    }

    private static func titleMetadata(_ title: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierTitle
        item.value = title as NSString
        item.extendedLanguageTag = "und"
        return item
    }
}

private struct WatchingHandoffPayload: Equatable {
    let mediaType: String
    let contentID: String
    let unitID: String
    let title: String
    let imageURL: String?
}

/// Advertises what is playing for Handoff to the Mac. Lives in its own view
/// so the five-second position refresh only re-renders this empty layer,
/// not the player.
private struct WatchingHandoffAdvertiser: View {
    static let activityType = "cloud.cyberverse.asterion.watching"

    let payload: WatchingHandoffPayload?
    let currentPosition: () -> Double?

    @State private var position: Double = 0

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .userActivity(Self.activityType, isActive: payload != nil) { activity in
                guard let payload else { return }
                activity.title = payload.title
                activity.isEligibleForHandoff = true
                activity.isEligibleForSearch = false
                activity.isEligibleForPublicIndexing = false
                var info: [String: Any] = [
                    "mediaType": payload.mediaType,
                    "contentId": payload.contentID,
                    "unitId": payload.unitID,
                    "positionSeconds": position,
                    "title": payload.title,
                ]
                if let imageURL = payload.imageURL, !imageURL.isEmpty {
                    info["imageURL"] = imageURL
                }
                activity.userInfo = info
            }
            .task(id: payload) {
                position = currentPosition() ?? 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    if let value = currentPosition(), abs(value - position) >= 1 {
                        position = value
                    }
                }
            }
    }
}

private struct PlaybackStreamChoice: Equatable, Identifiable {
    let id: String
    let title: String
}

private struct PlayerChromeExtras: Equatable {
    var title: String
    var canDownload: Bool
    var isDownloaded: Bool
    var downloadProgress: Double?
    var sleepMinutes: Int?
    var canPlayNext: Bool
    var canPlayPrevious: Bool
    var isResolvingNext: Bool
    var streamOptions: [PlaybackStreamChoice] = []
    var selectedStreamID: String?
}

private final class LandscapeAVPlayerViewController: AVPlayerViewController {
    var onLayout: (() -> Void)?
    var onClose: (() -> Void)?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var shouldAutorotate: Bool { true }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        onLayout?()
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        if presentingViewController != nil {
            super.dismiss(animated: flag, completion: completion)
        }
        onClose?()
    }
}

private struct NativePlayerController: UIViewControllerRepresentable {
    let player: AVPlayer
    let extras: PlayerChromeExtras
    let onClose: () -> Void
    let onPlaybackFailure: (String) -> Void
    let onDownload: () -> Void
    let onSetSleep: (Int?) -> Void
    let onEnded: () -> Void
    let onPlayNext: () -> Void
    let onPlayPrevious: () -> Void
    let onSelectStream: (String) -> Void

    func makeUIViewController(context: Context) -> LandscapeAVPlayerViewController {
        let controller = LandscapeAVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.speeds = Self.playbackSpeeds
        controller.delegate = context.coordinator
        controller.onClose = { [weak coordinator = context.coordinator] in
            coordinator?.onClose()
        }
        controller.onLayout = { [weak controller, weak coordinator = context.coordinator] in
            guard let controller, let coordinator else { return }
            coordinator.installChrome(in: controller)
        }
        context.coordinator.bind(from: self)
        context.coordinator.attach(player)
        context.coordinator.applySystemMenu(to: controller)
        return controller
    }

    func updateUIViewController(_ controller: LandscapeAVPlayerViewController, context: Context) {
        context.coordinator.bind(from: self)
        controller.onClose = { [weak coordinator = context.coordinator] in
            coordinator?.onClose()
        }
        if controller.player !== player {
            controller.player = player
            context.coordinator.attach(player)
        }
        context.coordinator.applySystemMenu(to: controller)
        context.coordinator.installChrome(in: controller)
    }

    func makeCoordinator() -> PlayerChromeCoordinator {
        PlayerChromeCoordinator()
    }

    private static let playbackSpeeds: [AVPlaybackSpeed] = [
        AVPlaybackSpeed(rate: 0.5, localizedName: "0.5×"),
        AVPlaybackSpeed(rate: 1, localizedName: "1×"),
        AVPlaybackSpeed(rate: 1.25, localizedName: "1.25×"),
        AVPlaybackSpeed(rate: 1.5, localizedName: "1.5×"),
        AVPlaybackSpeed(rate: 2, localizedName: "2×"),
    ]
}

private final class PlayerChromeCoordinator: NSObject, AVPlayerViewControllerDelegate {
    let lifecycle = PlaybackLifecycleObserver()
    var extras = PlayerChromeExtras(
        title: "",
        canDownload: false,
        isDownloaded: false,
        downloadProgress: nil,
        sleepMinutes: nil,
        canPlayNext: false,
        canPlayPrevious: false,
        isResolvingNext: false
    )
    var onClose: () -> Void = {}
    var onPlaybackFailure: (String) -> Void = { _ in }
    var onDownload: () -> Void = {}
    var onSetSleep: (Int?) -> Void = { _ in }
    var onEnded: () -> Void = {}
    var onPlayNext: () -> Void = {}
    var onPlayPrevious: () -> Void = {}
    var onSelectStream: (String) -> Void = { _ in }

    private weak var extrasButton: UIButton?
    private var hookedCloses: Set<ObjectIdentifier> = []

    func bind(from controller: NativePlayerController) {
        extras = controller.extras
        onClose = controller.onClose
        onPlaybackFailure = controller.onPlaybackFailure
        onDownload = controller.onDownload
        onSetSleep = controller.onSetSleep
        onEnded = controller.onEnded
        onPlayNext = controller.onPlayNext
        onPlayPrevious = controller.onPlayPrevious
        onSelectStream = controller.onSelectStream
        lifecycle.onItemEnded = { [weak self] in
            self?.onEnded()
        }
        lifecycle.onFailure = { [weak self] message in
            self?.onPlaybackFailure(message)
        }
    }

    func attach(_ player: AVPlayer) {
        lifecycle.onItemEnded = { [weak self] in
            self?.onEnded()
        }
        lifecycle.onFailure = { [weak self] message in
            self?.onPlaybackFailure(message)
        }
        lifecycle.attach(player)
    }

    func applySystemMenu(to controller: AVPlayerViewController) {
        let items = menuItems()
        let setter = NSSelectorFromString("setTransportBarCustomMenuItems:")
        if controller.responds(to: setter) {
            controller.setValue(items, forKey: "transportBarCustomMenuItems")
        }
        extrasButton?.menu = UIMenu(title: "", children: items)
        extrasButton?.accessibilityLabel = extrasAccessibilityLabel
    }

    func installChrome(in controller: AVPlayerViewController) {
        hookCloseButtons(in: controller.view)
        applySystemMenu(to: controller)
        if controller.responds(to: NSSelectorFromString("setTransportBarCustomMenuItems:")) {
            extrasButton?.removeFromSuperview()
            extrasButton = nil
            return
        }
        if extrasButton?.superview != nil { return }

        let button = makeExtrasButton()
        if let cluster = Self.controlCluster(in: controller.view) {
            if let stack = cluster as? UIStackView {
                stack.addArrangedSubview(button)
            } else {
                cluster.addSubview(button)
                button.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    button.centerYAnchor.constraint(equalTo: cluster.centerYAnchor),
                    button.trailingAnchor.constraint(equalTo: cluster.trailingAnchor),
                    button.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
                    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
                ])
            }
            extrasButton = button
            return
        }

        guard let overlay = controller.contentOverlayView else { return }
        overlay.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            button.bottomAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 36),
        ])
        extrasButton = button
    }

    func playerViewController(
        _ playerViewController: AVPlayerViewController,
        willEndFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator
    ) {
        coordinator.animate(alongsideTransition: nil) { [weak self] context in
            guard !context.isCancelled else { return }
            self?.onClose()
        }
    }

    private func menuItems() -> [UIMenuElement] {
        var items: [UIMenuElement] = []
        if extras.canPlayNext {
            items.append(episodeAction(
                title: extras.isResolvingNext ? "Loading next episode…" : "Next episode",
                image: "forward.end.fill",
                disabled: extras.isResolvingNext,
                handler: { [weak self] in self?.onPlayNext() }
            ))
        }
        if extras.canPlayPrevious {
            items.append(episodeAction(
                title: "Previous episode",
                image: "backward.end.fill",
                disabled: extras.isResolvingNext,
                handler: { [weak self] in self?.onPlayPrevious() }
            ))
        }
        if extras.canDownload {
            items.append(downloadAction())
        }
        if extras.streamOptions.count > 1 {
            items.append(streamMenu())
        }
        items.append(sleepMenu())
        return items
    }

    private func streamMenu() -> UIMenu {
        UIMenu(
            title: "Sources",
            image: UIImage(systemName: "slider.horizontal.3"),
            children: extras.streamOptions.map { option in
                UIAction(
                    title: option.title,
                    state: extras.selectedStreamID == option.id ? .on : .off
                ) { [weak self] _ in
                    self?.onSelectStream(option.id)
                }
            }
        )
    }

    private func episodeAction(
        title: String,
        image: String,
        disabled: Bool,
        handler: @escaping () -> Void
    ) -> UIAction {
        UIAction(
            title: title,
            image: UIImage(systemName: image),
            attributes: disabled ? .disabled : []
        ) { _ in
            handler()
        }
    }

    private func downloadAction() -> UIAction {
        if extras.isDownloaded {
            return UIAction(
                title: "Downloaded",
                image: UIImage(systemName: "checkmark.circle.fill"),
                attributes: .disabled
            ) { _ in }
        }
        if let progress = extras.downloadProgress {
            return UIAction(
                title: "Downloading \(Int(progress * 100))%",
                image: UIImage(systemName: "arrow.down.circle"),
                attributes: .disabled
            ) { _ in }
        }
        return UIAction(title: "Download", image: UIImage(systemName: "arrow.down.circle")) { [weak self] _ in
            self?.onDownload()
        }
    }

    private func sleepMenu() -> UIMenu {
        let off = UIAction(
            title: "Off",
            state: extras.sleepMinutes == nil ? .on : .off
        ) { [weak self] _ in
            self?.onSetSleep(nil)
        }
        let durations = [15, 30, 45, 60].map { minutes in
            UIAction(
                title: minutes == 60 ? "1 hour" : "\(minutes) minutes",
                state: extras.sleepMinutes == minutes ? .on : .off
            ) { [weak self] _ in
                self?.onSetSleep(minutes)
            }
        }
        return UIMenu(title: "Sleep timer", image: UIImage(systemName: "moon.zzz"), children: [off] + durations)
    }

    private var extrasAccessibilityLabel: String {
        if let sleepMinutes = extras.sleepMinutes {
            return "Playback options, sleep \(sleepMinutes) minutes"
        }
        return "Playback options"
    }

    private func makeExtrasButton() -> UIButton {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        button.changesSelectionAsPrimaryAction = false
        button.menu = UIMenu(title: "", children: menuItems())
        button.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        button.tintColor = .white
        button.accessibilityLabel = extrasAccessibilityLabel
        return button
    }

    private func hookCloseButtons(in view: UIView) {
        if let control = view as? UIControl, Self.looksLikeClose(control) {
            let id = ObjectIdentifier(control)
            if !hookedCloses.contains(id) {
                hookedCloses.insert(id)
                control.addAction(
                    UIAction { [weak self] _ in self?.onClose() },
                    for: .touchUpInside
                )
            }
        }
        view.subviews.forEach { hookCloseButtons(in: $0) }
    }

    private static func looksLikeClose(_ control: UIControl) -> Bool {
        let label = (control.accessibilityLabel ?? control.accessibilityIdentifier ?? "").lowercased()
        return label.contains("close") || label == "done" || label.contains("dismiss")
    }

    private static func controlCluster(in view: UIView) -> UIView? {
        if let control = view as? UIControl, looksLikeSystemMenuHost(control) {
            return control.superview
        }
        for subview in view.subviews {
            if let cluster = controlCluster(in: subview) {
                return cluster
            }
        }
        return nil
    }

    private static func looksLikeSystemMenuHost(_ control: UIControl) -> Bool {
        let label = (control.accessibilityLabel ?? "").lowercased()
        return label.contains("speed")
            || label.contains("subtitle")
            || label.contains("caption")
            || label.contains("playback rate")
    }
}

private final class PlaybackLifecycleObserver {
    var onItemEnded: (() -> Void)?
    var onFailure: ((String) -> Void)?

    private var player: AVPlayer?
    private var itemStatusObservation: NSKeyValueObservation?
    private var failedObserver: NSObjectProtocol?
    private var endObserver: NSObjectProtocol?
    private var hasReportedFailure = false

    func attach(_ player: AVPlayer) {
        detach()
        self.player = player
        hasReportedFailure = false
        guard let item = player.currentItem else { return }

        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                if item.status == .failed {
                    self?.reportFailure(
                        item.error?.localizedDescription
                            ?? "The video source could not be played."
                    )
                }
            }
        }
        failedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self?.reportFailure(
                error?.localizedDescription
                    ?? "The video source stopped before playback completed."
            )
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.onItemEnded?()
        }
    }

    private func reportFailure(_ message: String) {
        guard !hasReportedFailure else { return }
        hasReportedFailure = true
        player?.pause()
        onFailure?(message)
    }

    private func detach() {
        itemStatusObservation = nil
        if let failedObserver {
            NotificationCenter.default.removeObserver(failedObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        failedObserver = nil
        endObserver = nil
        player = nil
        hasReportedFailure = false
    }

    deinit {
        detach()
    }
}

private struct PlaybackFailureView: View {
    let message: String
    let options: [PlaybackOption]
    let selectedOptionID: String?
    let onSelect: (String) -> Void
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            AsterionEmptyState(
                symbol: "exclamationmark.triangle",
                title: "This video didn't play",
                message: message
            )
            .padding(.bottom, -28)

            HStack(spacing: 10) {
                Button(action: retry) {
                    Text("Try again")
                        .font(.asterionReading(14.5, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                }
                .buttonStyle(AsterionOutlineButtonStyle())

                if options.count > 1 {
                    Menu {
                        ForEach(options) { option in
                            Button {
                                onSelect(option.id)
                            } label: {
                                if selectedOptionID == option.id {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    } label: {
                        Text("Choose another source")
                            .font(.asterionReading(14.5, weight: .semibold))
                            .foregroundStyle(Color.asterionText)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 11)
                            .background(PlayerSmokedCapsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Color.black.opacity(0.96)
                RadialGradient(
                    colors: [Color.asterionWarning.opacity(0.08), .clear],
                    center: .center,
                    startRadius: 4,
                    endRadius: 320
                )
            }
            .ignoresSafeArea()
        }
    }
}

/// Smoked glass behind player controls that float over video.
private struct PlayerSmokedCircle: View {
    var body: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().fill(Color.black.opacity(0.35)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.16)))
    }
}

private struct PlayerSmokedCapsule: View {
    var body: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(Capsule().fill(Color.black.opacity(0.35)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16)))
    }
}

private struct EmbeddedMediaPlayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}

private struct WebVTTCue: Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

private enum WebVTTParser {
    static func parse(fileURL: URL) throws -> [WebVTTCue] {
        try parse(data: Data(contentsOf: fileURL, options: .mappedIfSafe))
    }

    static func parse(data: Data) throws -> [WebVTTCue] {
        guard var document = String(data: data, encoding: .utf8) else { return [] }
        document = document
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if document.first == "\u{feff}" {
            document.removeFirst()
        }
        guard document.hasPrefix("WEBVTT") else { return [] }

        var cues: [WebVTTCue] = []
        for block in document.components(separatedBy: "\n\n").dropFirst() {
            let lines = block
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timing = lines[timingIndex]
            let parts = timing.components(separatedBy: "-->")
            guard parts.count == 2,
                  let startTime = parseTime(parts[0].trimmingCharacters(in: .whitespaces)),
                  let endTime = parseTime(
                    parts[1].trimmingCharacters(in: .whitespaces)
                        .split(whereSeparator: \Character.isWhitespace)
                        .first
                        .map(String.init) ?? ""
                  ),
                  endTime > startTime
            else { continue }

            let displayText = plainText(
                from: lines.dropFirst(timingIndex + 1).joined(separator: "\n")
            )
            guard !displayText.isEmpty else { continue }
            cues.append(WebVTTCue(startTime: startTime, endTime: endTime, text: displayText))
        }
        return cues.sorted { $0.startTime < $1.startTime }
    }

    static func caption(at time: TimeInterval, in cues: [WebVTTCue]) -> String? {
        let text = cues.lazy
            .filter { $0.startTime <= time && time < $0.endTime }
            .map(\.text)
            .joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    private static func parseTime(_ token: String) -> TimeInterval? {
        let parts = token.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard parts.count == 2 || parts.count == 3,
              let seconds = Double(parts[parts.count - 1]),
              let minutes = Double(parts[parts.count - 2]) else { return nil }
        let hours = parts.count == 3 ? Double(parts[0]) ?? 0 : 0
        return hours * 3_600 + minutes * 60 + seconds
    }

    private static func plainText(from cueText: String) -> String {
        let normalized = cueText
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        var result = ""
        var insideTag = false
        for character in normalized {
            if character == "<" {
                insideTag = true
            } else if character == ">", insideTag {
                insideTag = false
            } else if !insideTag {
                result.append(character)
            }
        }
        return result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
