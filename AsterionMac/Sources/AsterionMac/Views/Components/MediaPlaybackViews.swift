import AVKit
import Combine
import SwiftUI
import WebKit

struct MediaDirectPlayer: View {
    let url: URL
    let subtitleTracks: [AnimeSubtitleTrack]
    let initialPosition: Double
    let autoplays: Bool
    let onProgress: @MainActor @Sendable (MediaPlaybackSample) -> Void
    let onEnded: @MainActor @Sendable () -> Void
    let onFailure: @MainActor @Sendable (String) -> Void
    let onLifecycleEvent: @MainActor @Sendable (MediaPlaybackLifecycleEvent) -> Void

    @StateObject private var controller: DirectMediaPlaybackController
    @State private var captionCharacterScale = CaptionSizing.systemRelativeCharacterSize

    init(
        url: URL,
        subtitleTracks: [AnimeSubtitleTrack] = [],
        initialPosition: Double = 0,
        autoplays: Bool = true,
        onProgress: @escaping @MainActor @Sendable (MediaPlaybackSample) -> Void = { _ in },
        onEnded: @escaping @MainActor @Sendable () -> Void = {},
        onFailure: @escaping @MainActor @Sendable (String) -> Void = { _ in },
        onLifecycleEvent: @escaping @MainActor @Sendable (MediaPlaybackLifecycleEvent) -> Void = { _ in }
    ) {
        self.url = url
        self.subtitleTracks = subtitleTracks
        self.initialPosition = initialPosition
        self.autoplays = autoplays
        self.onProgress = onProgress
        self.onEnded = onEnded
        self.onFailure = onFailure
        self.onLifecycleEvent = onLifecycleEvent
        _controller = StateObject(
            wrappedValue: DirectMediaPlaybackController(
                url: url,
                localSubtitleTracks: url.isFileURL ? subtitleTracks : []
            )
        )
    }

    var body: some View {
        Group {
            if subtitleTracks.isEmpty || url.isFileURL {
                ZStack {
                    NativeMediaPlayerView(player: controller.player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let caption = controller.activeCaption {
                        GeometryReader { geometry in
                            VStack {
                                Spacer()
                                Text(caption)
                                    .font(
                                        .system(
                                            size: CaptionSizing.fontSize(
                                                containerSize: geometry.size,
                                                relativeCharacterSize: captionCharacterScale
                                            ),
                                            weight: .semibold
                                        )
                                    )
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.white)
                                    .shadow(color: .black, radius: 2, x: 0, y: 1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
                                    .padding(.horizontal, 36)
                                    .padding(.bottom, 32)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .allowsHitTesting(false)
                        .accessibilityLabel("Subtitles: \(caption)")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    captionCharacterScale = CaptionSizing.systemRelativeCharacterSize
                    controller.start(
                        initialPosition: initialPosition,
                        autoplays: autoplays,
                        onProgress: onProgress,
                        onEnded: onEnded,
                        onFailure: onFailure,
                        onLifecycleEvent: onLifecycleEvent
                    )
                }
                .onDisappear { controller.stop() }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: CaptionSizing.settingsDidChangeNotification
                    )
                ) { _ in
                    captionCharacterScale = CaptionSizing.systemRelativeCharacterSize
                }
                .overlay(alignment: .top) {
                    if let captionError = controller.captionError {
                        Label(captionError, systemImage: "captions.bubble.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.red.opacity(0.82), in: Capsule())
                            .padding(.top, 12)
                    }
                }
            } else {
                CaptionedMediaPlayer(
                    url: url,
                    subtitleTracks: subtitleTracks,
                    initialPosition: initialPosition,
                    onProgress: onProgress,
                    onEnded: onEnded,
                    onFailure: onFailure
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}

private struct NativeMediaPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> FullFramePlayerView {
        let playerView = FullFramePlayerView()
        playerView.player = player
        playerView.controlsStyle = .floating
        playerView.videoGravity = .resizeAspect
        playerView.showsFullScreenToggleButton = true
        playerView.allowsPictureInPicturePlayback = true
        playerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        playerView.setContentHuggingPriority(.defaultLow, for: .vertical)
        playerView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        playerView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return playerView
    }

    func updateNSView(_ playerView: FullFramePlayerView, context: Context) {
        if playerView.player !== player {
            playerView.player = player
        }
        playerView.videoGravity = .resizeAspect
    }

    static func dismantleNSView(_ playerView: FullFramePlayerView, coordinator: Void) {
        playerView.player = nil
    }
}

private final class FullFramePlayerView: AVPlayerView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
        super.layout()
        videoGravity = .resizeAspect
    }
}

@MainActor
private final class DirectMediaPlaybackController: ObservableObject {
    let player: AVPlayer
    @Published private(set) var activeCaption: String?
    @Published private(set) var captionError: String?

    private let subtitleCues: [WebVTTCue]
    private let sleepController = PlaybackSleepController()
    private var periodicObserver: Any?
    private var timeControlObserver: NSKeyValueObservation?
    private var playbackRateObserver: NSKeyValueObservation?
    private var itemStatusObserver: NSKeyValueObservation?
    private var playbackEndObserver: NSObjectProtocol?
    private var playbackFailedObserver: NSObjectProtocol?
    private var onProgress: (@MainActor @Sendable (MediaPlaybackSample) -> Void)?
    private var onEnded: (@MainActor @Sendable () -> Void)?
    private var onFailure: (@MainActor @Sendable (String) -> Void)?
    private var onLifecycleEvent: (@MainActor @Sendable (MediaPlaybackLifecycleEvent) -> Void)?
    private var lastReportedPosition = -Double.infinity
    private var lastObservedPosition = -Double.infinity
    private var playbackIntentStartedAt: Date?
    private var startingPosition = 0.0
    private var hasConfirmedPlayback = false
    private var hasEnteredPlayingState = false
    private var hasSentPlaybackEnd = false
    private var hasReportedFailure = false
    private var isLifecyclePlaying = false
    private var wasNativePlaybackActive = false

    init(url: URL, localSubtitleTracks: [AnimeSubtitleTrack]) {
        player = AVPlayer(url: url)
        if let track = localSubtitleTracks.first(where: \.isDefault)
            ?? localSubtitleTracks.first {
            do {
                subtitleCues = try WebVTTParser.parse(fileURL: track.fileURL)
                captionError = nil
            } catch {
                subtitleCues = []
                captionError = error.localizedDescription
            }
        } else {
            subtitleCues = []
            captionError = nil
        }
    }

    func start(
        initialPosition: Double,
        autoplays: Bool,
        onProgress: @escaping @MainActor @Sendable (MediaPlaybackSample) -> Void,
        onEnded: @escaping @MainActor @Sendable () -> Void,
        onFailure: @escaping @MainActor @Sendable (String) -> Void,
        onLifecycleEvent: @escaping @MainActor @Sendable (MediaPlaybackLifecycleEvent) -> Void
    ) {
        self.onProgress = onProgress
        self.onEnded = onEnded
        self.onFailure = onFailure
        self.onLifecycleEvent = onLifecycleEvent
        startingPosition = max(0, initialPosition)
        hasConfirmedPlayback = false
        hasEnteredPlayingState = false
        hasSentPlaybackEnd = false
        hasReportedFailure = false
        isLifecyclePlaying = false
        wasNativePlaybackActive = false
        lastReportedPosition = -Double.infinity
        lastObservedPosition = player.currentTime().seconds
        playbackIntentStartedAt = nil
        onLifecycleEvent(.loading)
        if initialPosition > 0, player.currentTime().seconds < 1 {
            player.seek(
                to: CMTime(seconds: initialPosition, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
        if periodicObserver == nil {
            periodicObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
                queue: .main
            ) { [weak self] time in
                Task { @MainActor [weak self] in
                    self?.report(time: time, force: false)
                }
            }
        }
        installPlaybackObserversIfNeeded()
        if autoplays {
            player.play()
        }
        updateNativePlaybackState()
    }

    func stop() {
        if hasConfirmedPlayback {
            report(time: player.currentTime(), force: true)
        }
        removePlaybackObservers()
        if let periodicObserver {
            player.removeTimeObserver(periodicObserver)
            self.periodicObserver = nil
        }
        player.pause()
        wasNativePlaybackActive = false
        sleepController.stopAll()
        activeCaption = nil
        onProgress = nil
        onEnded = nil
        onFailure = nil
        onLifecycleEvent = nil
    }

    private func installPlaybackObserversIfNeeded() {
        if timeControlObserver == nil {
            timeControlObserver = player.observe(
                \.timeControlStatus,
                options: [.initial, .old, .new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.updateNativePlaybackState()
                }
            }
        }

        if playbackRateObserver == nil {
            playbackRateObserver = player.observe(
                \.rate,
                options: [.initial, .new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.updateNativePlaybackState()
                }
            }
        }

        if itemStatusObserver == nil, let currentItem = player.currentItem {
            itemStatusObserver = currentItem.observe(
                \.status,
                options: [.initial, .new]
            ) { [weak self] item, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch item.status {
                    case .readyToPlay:
                        self.onLifecycleEvent?(.ready)
                    case .failed:
                        self.reportFailure(
                            item.error?.localizedDescription
                                ?? "The video source could not be played."
                        )
                    case .unknown:
                        break
                    @unknown default:
                        break
                    }
                }
            }
        }

        if playbackEndObserver == nil, let currentItem = player.currentItem {
            playbackEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: currentItem,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.wasNativePlaybackActive = false
                    self.sleepController.setPlaying(false, sourceID: "native-player")
                    self.report(
                        time: self.player.currentTime(),
                        force: true,
                        allowStoppedPlaybackConfirmation: true
                    )
                    if self.hasEnteredPlayingState, !self.hasSentPlaybackEnd {
                        self.hasSentPlaybackEnd = true
                        self.onEnded?()
                    }
                }
            }
        }

        if playbackFailedObserver == nil, let currentItem = player.currentItem {
            playbackFailedObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: currentItem,
                queue: .main
            ) { [weak self] notification in
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey]
                    as? Error
                Task { @MainActor [weak self] in
                    self?.reportFailure(
                        error?.localizedDescription
                            ?? "The video source stopped before playback completed."
                    )
                }
            }
        }
    }

    private func removePlaybackObservers() {
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        playbackRateObserver?.invalidate()
        playbackRateObserver = nil
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }
        if let playbackFailedObserver {
            NotificationCenter.default.removeObserver(playbackFailedObserver)
            self.playbackFailedObserver = nil
        }
    }

    private func reportFailure(_ message: String) {
        guard !hasReportedFailure else { return }
        hasReportedFailure = true
        isLifecyclePlaying = false
        if hasConfirmedPlayback {
            report(time: player.currentTime(), force: true)
        }
        wasNativePlaybackActive = false
        sleepController.stopAll()
        onLifecycleEvent?(.failed(message))
        onFailure?(message)
    }

    private func updateNativePlaybackState() {
        let requestsPlayback = player.rate > 0
            || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            || player.timeControlStatus == .playing
        if requestsPlayback {
            beginPlaybackIntentIfNeeded()
        } else if player.timeControlStatus == .paused,
                  playbackIntentStartedAt != nil,
                  !hasSentPlaybackEnd {
            playbackIntentStartedAt = nil
            isLifecyclePlaying = false
            onLifecycleEvent?(.paused)
        }

        let shouldPreventSleep = PlaybackSleepController.shouldPreventSleep(
            playbackRate: player.rate,
            isPlaybackPaused: player.timeControlStatus == .paused
        )
        let becameInactive = !shouldPreventSleep && wasNativePlaybackActive
        wasNativePlaybackActive = shouldPreventSleep
        if shouldPreventSleep {
            hasEnteredPlayingState = true
        }
        sleepController.setPlaying(shouldPreventSleep, sourceID: "native-player")
        if becameInactive, hasEnteredPlayingState {
            report(
                time: player.currentTime(),
                force: true,
                allowStoppedPlaybackConfirmation: true
            )
        }
    }

    private func report(
        time: CMTime,
        force: Bool,
        allowStoppedPlaybackConfirmation: Bool = false
    ) {
        let position = time.seconds
        guard position.isFinite, position >= 0 else { return }
        observePlaybackAdvance(position: position)
        let caption = WebVTTParser.caption(at: position, in: subtitleCues)
        if caption != activeCaption {
            activeCaption = caption
        }
        if !hasConfirmedPlayback,
           (player.rate > 0
                || (allowStoppedPlaybackConfirmation && hasEnteredPlayingState)),
           position > startingPosition + 0.25 {
            hasConfirmedPlayback = true
        }
        guard hasConfirmedPlayback else { return }
        guard force || abs(position - lastReportedPosition) >= 15 else { return }

        let rawDuration = player.currentItem?.duration.seconds ?? 0
        let duration = rawDuration.isFinite && rawDuration > 0 ? rawDuration : 0
        lastReportedPosition = position
        onProgress?(
            MediaPlaybackSample(
                positionSeconds: position,
                durationSeconds: duration,
                completed: duration > 0 && position / duration >= 0.90,
                observedAt: Date()
            )
        )
    }

    private func beginPlaybackIntentIfNeeded() {
        guard playbackIntentStartedAt == nil else { return }
        playbackIntentStartedAt = Date()
        lastObservedPosition = player.currentTime().seconds
        onLifecycleEvent?(.playRequested)
    }

    private func observePlaybackAdvance(position: Double) {
        defer { lastObservedPosition = position }
        guard playbackIntentStartedAt != nil,
              !hasReportedFailure,
              position > lastObservedPosition + 0.05 else { return }
        if !isLifecyclePlaying {
            isLifecyclePlaying = true
            onLifecycleEvent?(.playing)
        }
    }

}

private struct CaptionedMediaPlayer: View {
    enum Phase {
        case loading
        case ready([AnimeSubtitleTrack])
        case failure(String)
    }

    let url: URL
    let subtitleTracks: [AnimeSubtitleTrack]
    let initialPosition: Double
    let onProgress: @MainActor @Sendable (MediaPlaybackSample) -> Void
    let onEnded: @MainActor @Sendable () -> Void
    let onFailure: @MainActor @Sendable (String) -> Void

    @State private var phase: Phase = .loading
    @State private var attempt = 0

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView("Loading subtitles…")
                    .tint(.white)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
            case .ready(let loadedTracks):
                CaptionedMediaWebView(
                    url: url,
                    subtitleTracks: loadedTracks,
                    initialPosition: initialPosition,
                    onProgress: onProgress,
                    onEnded: onEnded,
                    onError: {
                        phase = .failure($0)
                        onFailure($0)
                    }
                )
            case .failure(let message):
                PlayerFailureView(message: message) {
                    attempt += 1
                }
            }
        }
        .task(id: attempt) {
            phase = .loading
            do {
                let loadedTracks = try await AnimeSubtitleLoader.load(
                    subtitleTracks,
                    allowsLocalFiles: url.isFileURL
                )
                try Task.checkCancellation()
                phase = .ready(loadedTracks)
            } catch is CancellationError {
                return
            } catch {
                phase = .failure(error.localizedDescription)
            }
        }
    }
}

struct MediaWebPlayer: View {
    let url: URL
    let initialPosition: Double
    let onProgress: @MainActor @Sendable (MediaPlaybackSample) -> Void
    let onEnded: @MainActor @Sendable () -> Void
    let onFailure: @MainActor @Sendable (String) -> Void
    let onLifecycleEvent: @MainActor @Sendable (MediaPlaybackLifecycleEvent) -> Void

    @State private var errorMessage: String?
    @State private var playerAttempt = 0

    init(
        url: URL,
        initialPosition: Double = 0,
        onProgress: @escaping @MainActor @Sendable (MediaPlaybackSample) -> Void = { _ in },
        onEnded: @escaping @MainActor @Sendable () -> Void = {},
        onFailure: @escaping @MainActor @Sendable (String) -> Void = { _ in },
        onLifecycleEvent: @escaping @MainActor @Sendable (MediaPlaybackLifecycleEvent) -> Void = { _ in }
    ) {
        self.url = url
        self.initialPosition = initialPosition
        self.onProgress = onProgress
        self.onEnded = onEnded
        self.onFailure = onFailure
        self.onLifecycleEvent = onLifecycleEvent
    }

    var body: some View {
        ZStack {
            RestrictedMediaWebView(
                url: url,
                initialPosition: initialPosition,
                onProgress: onProgress,
                onEnded: onEnded,
                onLifecycleEvent: onLifecycleEvent,
                onError: {
                    errorMessage = $0
                    onFailure($0)
                }
            )
            .id(playerAttempt)

            if let errorMessage {
                PlayerFailureView(message: errorMessage) {
                    self.errorMessage = nil
                    playerAttempt += 1
                }
            }
        }
        .background(.black)
    }
}

struct MovieFallbackPlayer: View {
    let options: [MoviePlaybackOption]
    let currentServerIndex: Int
    let attemptID: UUID
    let initialPosition: Double
    let onProgress: @MainActor @Sendable (MediaPlaybackSample) -> Void
    let onEnded: @MainActor @Sendable () -> Void
    let onLifecycleEvent: @MainActor @Sendable (
        MoviePlaybackOption,
        UUID,
        MediaPlaybackLifecycleEvent
    ) -> Void

    var body: some View {
        Group {
            if options.indices.contains(currentServerIndex) {
                let option = options[currentServerIndex]
                switch option.kind {
                case .direct:
                    MediaDirectPlayer(
                        url: option.url,
                        initialPosition: initialPosition,
                        autoplays: false,
                        onProgress: onProgress,
                        onEnded: onEnded,
                        onLifecycleEvent: {
                            onLifecycleEvent(option, attemptID, $0)
                        }
                    )
                case .web:
                    MediaWebPlayer(
                        url: option.url,
                        initialPosition: initialPosition,
                        onProgress: onProgress,
                        onEnded: onEnded,
                        onLifecycleEvent: {
                            onLifecycleEvent(option, attemptID, $0)
                        }
                    )
                }
            } else {
                ContentUnavailableView(
                    "No video selected",
                    systemImage: "play.rectangle",
                    description: Text("Choose a playback source.")
                )
                .foregroundStyle(.white)
            }
        }
        .id(attemptID)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}

private struct PlayerFailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
            Text(message)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Try Again", action: retry)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.96))
    }
}

private struct CaptionedMediaWebView: NSViewRepresentable {
    let url: URL
    let subtitleTracks: [AnimeSubtitleTrack]
    let initialPosition: Double
    let onProgress: @MainActor @Sendable (MediaPlaybackSample) -> Void
    let onEnded: @MainActor @Sendable () -> Void
    let onError: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onProgress: onProgress, onEnded: onEnded, onError: onError)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.userContentController.add(context.coordinator, name: Coordinator.messageName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        loadPlayer(in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let signature = CaptionedMediaDocument.signature(
            url: url,
            tracks: subtitleTracks,
            initialPosition: initialPosition
        )
        guard context.coordinator.loadedSignature != signature else { return }
        loadPlayer(in: webView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        coordinator.flushLastProgress()
        coordinator.stopPlaybackActivity()
        webView.evaluateJavaScript("window.__asterionFlush?.();") { [weak webView] _, _ in
            guard let webView else { return }
            webView.configuration.userContentController.removeScriptMessageHandler(
                forName: Coordinator.messageName
            )
            webView.loadHTMLString("", baseURL: nil)
        }
    }

    private func loadPlayer(in webView: WKWebView, coordinator: Coordinator) {
        let signature = CaptionedMediaDocument.signature(
            url: url,
            tracks: subtitleTracks,
            initialPosition: initialPosition
        )
        coordinator.stopPlaybackActivity()
        coordinator.loadedSignature = signature
        let html = CaptionedMediaDocument.html(
            url: url,
            tracks: subtitleTracks,
            initialPosition: initialPosition
        )
        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        static let messageName = "asterionPlayback"

        var loadedSignature: String?
        private let onProgress: @MainActor @Sendable (MediaPlaybackSample) -> Void
        private let onEnded: @MainActor @Sendable () -> Void
        private let onError: @MainActor (String) -> Void
        private let sleepController = PlaybackSleepController()
        private var lastSample: MediaPlaybackSample?

        init(
            onProgress: @escaping @MainActor @Sendable (MediaPlaybackSample) -> Void,
            onEnded: @escaping @MainActor @Sendable () -> Void,
            onError: @escaping @MainActor (String) -> Void
        ) {
            self.onProgress = onProgress
            self.onEnded = onEnded
            self.onError = onError
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == Self.messageName else { return }
            if let error = message.body as? String {
                Task { @MainActor in onError(error) }
                return
            }
            guard let payload = message.body as? [String: Any],
                  let type = payload["type"] as? String else { return }
            if type == "error", let error = payload["message"] as? String {
                stopPlaybackActivity()
                Task { @MainActor in onError(error) }
            } else if type == "playback", let isPlaying = payload["isPlaying"] as? Bool {
                sleepController.setPlaying(isPlaying, sourceID: "captioned-player")
            } else if type == "ended" {
                stopPlaybackActivity()
                Task { @MainActor in onEnded() }
            } else if type == "progress",
                      let position = (payload["position"] as? NSNumber)?.doubleValue,
                      let duration = (payload["duration"] as? NSNumber)?.doubleValue,
                      let completed = payload["completed"] as? Bool {
                let sample = MediaPlaybackSample(
                    positionSeconds: position,
                    durationSeconds: duration,
                    completed: completed,
                    observedAt: Date()
                )
                lastSample = sample
                Task { @MainActor in
                    onProgress(sample)
                }
            }
        }

        func flushLastProgress() {
            guard let lastSample else { return }
            Task { @MainActor in onProgress(lastSample) }
        }

        func stopPlaybackActivity() {
            sleepController.stopAll()
        }
    }
}

enum CaptionedMediaDocument {
    static func signature(
        url: URL,
        tracks: [AnimeSubtitleTrack],
        initialPosition: Double = 0
    ) -> String {
        ([url.absoluteString, String(initialPosition)] + tracks.map {
            "\($0.fileURL.absoluteString)|\($0.label)|\($0.kind)|\($0.languageCode ?? "")|\($0.isDefault)"
        }).joined(separator: "\n")
    }

    static func html(
        url: URL,
        tracks: [AnimeSubtitleTrack],
        initialPosition: Double = 0
    ) -> String {
        let trackElements = tracks.map { track in
            let kind = allowedTrackKind(track.kind)
            let language = track.languageCode.map {
                " srclang=\"\(attribute($0))\""
            } ?? ""
            let defaultTrack = track.isDefault ? " default" : ""
            return """
            <track kind="\(kind)" label="\(attribute(track.label))"\(language) src="\(attribute(track.fileURL.absoluteString))" data-label="\(attribute(track.label))"\(defaultTrack)>
            """
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; media-src https: data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
          <style>
            html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; background: #000; }
            video { width: 100%; height: 100%; display: block; background: #000; object-fit: contain; }
          </style>
        </head>
        <body>
          <video id="player" controls autoplay playsinline aria-label="Video player">
            <source src="\(attribute(url.absoluteString))" type="application/vnd.apple.mpegurl">
            \(trackElements)
          </video>
          <script>
            const player = document.getElementById('player');
            const initialPosition = \(max(0, initialPosition));
            let lastReport = -Infinity;
            let hasPlayed = false;
            const post = payload => window.webkit.messageHandlers.asterionPlayback.postMessage(payload);
            const reportError = message => post({ type: 'error', message });
            const reportProgress = force => {
              if (!hasPlayed) return;
              const position = Number.isFinite(player.currentTime) ? player.currentTime : 0;
              const duration = Number.isFinite(player.duration) ? player.duration : 0;
              if (!force && Math.abs(position - lastReport) < 15) return;
              lastReport = position;
              post({
                type: 'progress',
                position,
                duration,
                completed: duration > 0 && position / duration >= 0.90
              });
            };
            player.addEventListener('loadedmetadata', () => {
              if (initialPosition > 0 && initialPosition < player.duration) {
                player.currentTime = initialPosition;
              }
            });
            player.addEventListener('playing', () => {
              hasPlayed = true;
              post({ type: 'playback', isPlaying: true });
            });
            player.addEventListener('timeupdate', () => reportProgress(false));
            player.addEventListener('pause', () => {
              post({ type: 'playback', isPlaying: false });
              reportProgress(true);
            });
            player.addEventListener('ended', () => {
              post({ type: 'playback', isPlaying: false });
              reportProgress(true);
              post({ type: 'ended' });
            });
            player.addEventListener('error', () => {
              post({ type: 'playback', isPlaying: false });
              reportError('The video source could not be played.');
            });
            document.querySelectorAll('track').forEach(track => {
              track.addEventListener('error', () => reportError(`The ${track.dataset.label} subtitle track could not be loaded.`));
            });
            window.__asterionFlush = () => {
              post({ type: 'playback', isPlaying: false });
              reportProgress(true);
            };
            player.play().catch(() => {});
          </script>
        </body>
        </html>
        """
    }

    private static func allowedTrackKind(_ kind: String) -> String {
        let normalized = kind.lowercased()
        let allowed = ["captions", "chapters", "descriptions", "metadata", "subtitles"]
        return allowed.contains(normalized) ? normalized : "subtitles"
    }

    private static func attribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private struct RestrictedMediaWebView: NSViewRepresentable {
    private static let telemetryContentWorld = WKContentWorld.world(
        name: "cloud.cyberverse.Asterion.media-playback-telemetry"
    )

    let url: URL
    let initialPosition: Double
    let onProgress: @MainActor @Sendable (MediaPlaybackSample) -> Void
    let onEnded: @MainActor @Sendable () -> Void
    let onLifecycleEvent: @MainActor @Sendable (MediaPlaybackLifecycleEvent) -> Void
    let onError: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            initialURL: url,
            onProgress: onProgress,
            onEnded: onEnded,
            onLifecycleEvent: onLifecycleEvent,
            onError: onError
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.userContentController.add(
            context.coordinator,
            contentWorld: Self.telemetryContentWorld,
            name: Coordinator.messageName
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: EmbeddedMediaProgressScript.source(initialPosition: initialPosition),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false,
                in: Self.telemetryContentWorld
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.load(url, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.initialURL != url else { return }
        context.coordinator.load(url, in: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.flushLastProgress()
        coordinator.stop()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.evaluateJavaScript(
            "window.__asterionFlush?.();",
            in: nil,
            in: Self.telemetryContentWorld
        ) { [weak webView] _ in
            guard let webView else { return }
            webView.stopLoading()
            webView.configuration.userContentController.removeScriptMessageHandler(
                forName: Coordinator.messageName,
                contentWorld: Self.telemetryContentWorld
            )
            webView.configuration.userContentController.removeAllUserScripts()
            webView.loadHTMLString("", baseURL: nil)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        static let messageName = "asterionEmbeddedPlayback"

        private(set) var initialURL: URL
        private var navigationState: MediaNavigationState
        private let onProgress: @MainActor @Sendable (MediaPlaybackSample) -> Void
        private let onEnded: @MainActor @Sendable () -> Void
        private let onLifecycleEvent: @MainActor @Sendable (MediaPlaybackLifecycleEvent) -> Void
        private let onError: @MainActor (String) -> Void
        private let sleepController = PlaybackSleepController()
        private var lastSample: MediaPlaybackSample?
        private var awaitsRemoteFrameResponse = false
        private var isActive = false
        private var hasReportedFailure = false
        private var hasReportedReady = false
        private var hasPlaybackIntent = false
        private var isPlaying = false

        init(
            initialURL: URL,
            onProgress: @escaping @MainActor @Sendable (MediaPlaybackSample) -> Void,
            onEnded: @escaping @MainActor @Sendable () -> Void,
            onLifecycleEvent: @escaping @MainActor @Sendable (MediaPlaybackLifecycleEvent) -> Void,
            onError: @escaping @MainActor (String) -> Void
        ) {
            self.initialURL = initialURL
            self.navigationState = MediaNavigationState(initialURL: initialURL)
            self.onProgress = onProgress
            self.onEnded = onEnded
            self.onLifecycleEvent = onLifecycleEvent
            self.onError = onError
        }

        func load(_ url: URL, in webView: WKWebView) {
            stopPlaybackActivity()
            initialURL = url
            navigationState.reset(initialURL: url)
            isActive = true
            hasReportedFailure = false
            hasReportedReady = false
            hasPlaybackIntent = false
            isPlaying = false
            awaitsRemoteFrameResponse = url.absoluteString.contains("2embed.cc/embed")
            onLifecycleEvent(.loading)

            guard MediaNavigationPolicy.isSecureRemoteURL(url) else {
                report("This video source does not use a secure web address.")
                return
            }
            // 2embed requires loading inside an iframe
            if awaitsRemoteFrameResponse {
                let html = """
                <!DOCTYPE html><html><head><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">
                <style>body{margin:0;padding:0;background:#000}iframe{width:100%;height:100vh;border:0}</style>
                </head><body><iframe src=\"\(url.absoluteString)\" allowfullscreen allow=\"autoplay;encrypted-media\"></iframe></body></html>
                """
                webView.loadHTMLString(html, baseURL: url)
            } else {
                webView.load(URLRequest(url: url))
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let targetURL = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            let target: MediaNavigationTarget
            if navigationAction.targetFrame == nil {
                target = .newWindow
            } else if navigationAction.targetFrame?.isMainFrame == false {
                target = .subframe
            } else {
                target = .topLevel(
                    isUserLink: navigationAction.navigationType == .linkActivated
                )
            }
            decisionHandler(navigationState.allows(targetURL, target: target) ? .allow : .cancel)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
        ) {
            if let response = navigationResponse.response as? HTTPURLResponse,
               isPlaybackResponse(navigationResponse),
               !MediaNavigationPolicy.allowsHTTPStatus(response.statusCode) {
                report("The video page returned HTTP \(response.statusCode).")
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            navigationState.markInitialNavigationFinished()
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            report(error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            report(error.localizedDescription)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            stopPlaybackActivity()
            report("The video player stopped unexpectedly.")
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            nil
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == Self.messageName,
                  message.world === RestrictedMediaWebView.telemetryContentWorld,
                  let payload = message.body as? [String: Any],
                  let type = payload["type"] as? String else { return }
            if type == "ended" {
                Task { @MainActor in onEnded() }
                return
            }
            if type == "pageReady",
               let pageURLString = payload["url"] as? String,
               let pageURL = URL(string: pageURLString),
               let isTopLevel = payload["isTopLevel"] as? Bool,
               pageURL.host?.lowercased() == initialURL.host?.lowercased(),
               !awaitsRemoteFrameResponse || !isTopLevel {
                markSourceReady()
                return
            }
            if type == "ready" {
                markSourceReady()
                return
            }
            if type == "userIntent",
               let isTopLevel = payload["isTopLevel"] as? Bool,
               !awaitsRemoteFrameResponse || !isTopLevel {
                beginPlaybackIntentIfNeeded()
                return
            }
            if type == "error" {
                guard hasPlaybackIntent || isPlaying else { return }
                report(
                    payload["message"] as? String
                        ?? "The embedded video could not be played."
                )
                return
            }
            if type == "playback",
               let sourceID = payload["sourceID"] as? String,
               let isPlaying = payload["isPlaying"] as? Bool {
                if isPlaying {
                    confirmPlaybackStarted()
                }
                sleepController.setPlaying(isPlaying, sourceID: sourceID)
                return
            }
            if type == "paused" {
                pausePlaybackAttempt()
                return
            }
            guard type == "progress",
                  let position = (payload["position"] as? NSNumber)?.doubleValue,
                  let duration = (payload["duration"] as? NSNumber)?.doubleValue,
                  let completed = payload["completed"] as? Bool,
                  position.isFinite,
                  duration.isFinite,
                  position > 0 else { return }
            markSourceReady()
            confirmPlaybackStarted()
            let sample = MediaPlaybackSample(
                positionSeconds: position,
                durationSeconds: duration,
                completed: completed,
                observedAt: Date()
            )
            lastSample = sample
            Task { @MainActor in onProgress(sample) }
        }

        func flushLastProgress() {
            guard let lastSample else { return }
            Task { @MainActor in onProgress(lastSample) }
        }

        func stopPlaybackActivity() {
            sleepController.stopAll()
        }

        func stop() {
            isActive = false
            stopPlaybackActivity()
        }

        private func markSourceReady() {
            guard !hasReportedReady else { return }
            hasReportedReady = true
            onLifecycleEvent(.ready)
        }

        private func beginPlaybackIntentIfNeeded() {
            guard !hasPlaybackIntent, !hasReportedFailure else { return }
            hasPlaybackIntent = true
            isPlaying = false
            onLifecycleEvent(.playRequested)
        }

        private func confirmPlaybackStarted() {
            markSourceReady()
            beginPlaybackIntentIfNeeded()
            guard !isPlaying else { return }
            isPlaying = true
            onLifecycleEvent(.playing)
        }

        private func pausePlaybackAttempt() {
            guard hasPlaybackIntent || isPlaying else { return }
            hasPlaybackIntent = false
            isPlaying = false
            onLifecycleEvent(.paused)
        }

        private func isPlaybackResponse(_ navigationResponse: WKNavigationResponse) -> Bool {
            guard let responseURL = navigationResponse.response.url else {
                return navigationResponse.isForMainFrame
            }
            return navigationResponse.isForMainFrame
                || responseURL.host?.lowercased() == initialURL.host?.lowercased()
        }

        private func report(_ message: String) {
            guard isActive, !hasReportedFailure else { return }
            hasReportedFailure = true
            stopPlaybackActivity()
            onLifecycleEvent(.failed(message))
            Task { @MainActor in onError(message) }
        }
    }
}

enum EmbeddedMediaProgressScript {
    static func source(initialPosition: Double) -> String {
        """
        (() => {
          if (globalThis.__asterionProgressInstalled) return;
          globalThis.__asterionProgressInstalled = true;
          const initialPosition = \(max(0, initialPosition));
          const players = new Set();
          const playerState = new WeakMap();
          const sourceID = globalThis.crypto?.randomUUID?.()
            ?? `player-${Date.now()}-${Math.random().toString(36).slice(2)}`;
          let activePlayer = null;
          let reportedPlaybackActive = false;
          let reportedMediaReady = false;
          let selectionQueued = false;

          const post = payload => {
            try {
              window.webkit.messageHandlers.asterionEmbeddedPlayback.postMessage(payload);
            } catch (_) {}
          };

          post({
            type: 'pageReady',
            sourceID,
            url: globalThis.location.href,
            isTopLevel: globalThis.top === globalThis
          });

          const reportUserIntent = () => post({
            type: 'userIntent',
            sourceID,
            url: globalThis.location.href,
            isTopLevel: globalThis.top === globalThis
          });

          globalThis.document.addEventListener('pointerup', event => {
            if (event.isTrusted && players.size === 0) reportUserIntent();
          }, true);

          const stateFor = player => {
            let state = playerState.get(player);
            if (!state) {
              state = {
                hasPlayed: false,
                lastReport: -Infinity,
                resumeApplied: false
              };
              playerState.set(player, state);
            }
            return state;
          };

          const reportPlaybackActivity = isPlaying => {
            if (reportedPlaybackActive === isPlaying) return;
            reportedPlaybackActive = isPlaying;
            post({ type: 'playback', sourceID, isPlaying });
          };

          const reportMediaReady = player => {
            if (reportedMediaReady
                || player.error
                || player.readyState < HTMLMediaElement.HAVE_METADATA) {
              return;
            }
            reportedMediaReady = true;
            post({ type: 'ready', sourceID });
          };

          const reportMediaError = player => {
            const code = player.error?.code;
            const messages = {
              1: 'The embedded video load was aborted.',
              2: 'The embedded video could not be downloaded.',
              3: 'The embedded video could not be decoded.',
              4: 'The embedded video format is not supported.'
            };
            post({
              type: 'error',
              sourceID,
              message: messages[code] ?? 'The embedded video could not be played.'
            });
          };

          const visiblePlayingArea = player => {
            if (!player.isConnected
                || player.paused
                || player.ended
                || player.playbackRate <= 0
                || player.readyState < HTMLMediaElement.HAVE_CURRENT_DATA) {
              return 0;
            }
            if (typeof player.checkVisibility === 'function'
                && !player.checkVisibility({
                  checkOpacity: true,
                  checkVisibilityCSS: true
                })) {
              return 0;
            }

            const style = getComputedStyle(player);
            if (style.display === 'none'
                || style.visibility === 'hidden'
                || style.visibility === 'collapse'
                || Number.parseFloat(style.opacity || '1') <= 0) {
              return 0;
            }

            const bounds = player.getBoundingClientRect();
            const viewportWidth = document.documentElement.clientWidth || window.innerWidth;
            const viewportHeight = document.documentElement.clientHeight || window.innerHeight;
            const width = Math.max(
              0,
              Math.min(bounds.right, viewportWidth) - Math.max(bounds.left, 0)
            );
            const height = Math.max(
              0,
              Math.min(bounds.bottom, viewportHeight) - Math.max(bounds.top, 0)
            );
            return width * height;
          };

          const emit = (player, force) => {
            const state = stateFor(player);
            if (!state.hasPlayed) return;
            const position = Number.isFinite(player.currentTime) ? player.currentTime : 0;
            const duration = Number.isFinite(player.duration) ? player.duration : 0;
            if (position <= 0) return;
            if (!force && Math.abs(position - state.lastReport) < 15) return;
            state.lastReport = position;
            post({
              type: 'progress',
              position,
              duration,
              completed: duration > 0 && position / duration >= 0.90
            });
          };

          const applyResume = player => {
            const state = stateFor(player);
            if (state.resumeApplied || !state.hasPlayed || activePlayer !== player) return;
            if (initialPosition <= 0 || !Number.isFinite(player.duration)) return;
            state.resumeApplied = true;
            if (initialPosition < player.duration) {
              player.currentTime = initialPosition;
            }
          };

          const selectActivePlayer = () => {
            let selected = null;
            let selectedArea = 0;
            players.forEach(player => {
              if (!player.isConnected) {
                players.delete(player);
                return;
              }
              const area = visiblePlayingArea(player);
              if (area > selectedArea) {
                selected = player;
                selectedArea = area;
              }
            });

            if (activePlayer !== selected) {
              if (activePlayer) emit(activePlayer, true);
              activePlayer = selected;
            }
            reportPlaybackActivity(activePlayer !== null);
            if (activePlayer) applyResume(activePlayer);
            return activePlayer;
          };

          const scheduleSelection = () => {
            if (selectionQueued) return;
            selectionQueued = true;
            requestAnimationFrame(() => {
              selectionQueued = false;
              selectActivePlayer();
            });
          };

          const reportIfSelected = (player, force) => {
            const selected = selectActivePlayer();
            if (selected === player) {
              emit(player, force);
            }
          };

          const attach = player => {
            if (!(player instanceof HTMLMediaElement) || players.has(player)) return;
            players.add(player);
            const state = stateFor(player);
            player.addEventListener('play', reportUserIntent);
            player.addEventListener('playing', () => {
              state.hasPlayed = true;
              reportMediaReady(player);
              scheduleSelection();
            });
            player.addEventListener('loadedmetadata', () => {
              reportMediaReady(player);
              scheduleSelection();
            });
            player.addEventListener('canplay', () => {
              reportMediaReady(player);
              scheduleSelection();
            });
            player.addEventListener('durationchange', () => {
              reportMediaReady(player);
              scheduleSelection();
            });
            player.addEventListener('error', () => reportMediaError(player));
            player.addEventListener('timeupdate', () => {
              reportIfSelected(player, false);
            });
            player.addEventListener('pause', () => {
              if (activePlayer === player) emit(player, true);
              post({ type: 'paused', sourceID });
              scheduleSelection();
            });
            player.addEventListener('ended', () => {
              if (activePlayer === player) {
                emit(player, true);
                post({ type: 'ended' });
              }
              scheduleSelection();
            });
            if (!player.paused && !player.ended) {
              state.hasPlayed = true;
            }
            reportMediaReady(player);
            scheduleSelection();
          };

          const scan = root => {
            if (root instanceof HTMLMediaElement) attach(root);
            root.querySelectorAll?.('video, audio').forEach(attach);
          };

          scan(document);
          new MutationObserver(records => {
            records.forEach(record => record.addedNodes.forEach(node => {
              if (node instanceof Element) scan(node);
            }));
          }).observe(document.documentElement, { childList: true, subtree: true });

          window.addEventListener('resize', scheduleSelection);
          window.addEventListener('scroll', scheduleSelection, true);
          window.addEventListener('pagehide', () => {
            const selected = selectActivePlayer();
            if (selected) emit(selected, true);
            reportPlaybackActivity(false);
          });
          globalThis.__asterionFlush = () => {
            const selected = selectActivePlayer();
            if (selected) emit(selected, true);
            reportPlaybackActivity(false);
          };
        })();
        """
    }
}

enum MediaNavigationPolicy {
    static func isSecureRemoteURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host != nil
            && url.user == nil
            && url.password == nil
    }

    static func isSafeSubframeURL(_ url: URL) -> Bool {
        isSecureRemoteURL(url)
            || (url.scheme?.lowercased() == "about" && url.absoluteString == "about:blank")
    }

    static func allowsHTTPStatus(_ statusCode: Int) -> Bool {
        (200..<400).contains(statusCode)
    }
}

enum MediaNavigationTarget: Equatable {
    case newWindow
    case subframe
    case topLevel(isUserLink: Bool)
}

struct MediaNavigationState {
    private var allowedTopLevelHosts: Set<String>
    private var finishedInitialNavigation = false

    init(initialURL: URL) {
        allowedTopLevelHosts = Self.hostSet(for: initialURL)
    }

    mutating func reset(initialURL: URL) {
        allowedTopLevelHosts = Self.hostSet(for: initialURL)
        finishedInitialNavigation = false
    }

    mutating func allows(_ url: URL, target: MediaNavigationTarget) -> Bool {
        switch target {
        case .newWindow:
            return false
        case .subframe:
            return MediaNavigationPolicy.isSafeSubframeURL(url)
        case .topLevel(let isUserLink):
            guard MediaNavigationPolicy.isSecureRemoteURL(url),
                  let host = url.host?.lowercased() else { return false }

            if !finishedInitialNavigation, !isUserLink {
                allowedTopLevelHosts.insert(host)
                return true
            }
            return allowedTopLevelHosts.contains(host)
        }
    }

    mutating func markInitialNavigationFinished() {
        finishedInitialNavigation = true
    }

    private static func hostSet(for url: URL) -> Set<String> {
        Set(url.host.map { [$0.lowercased()] } ?? [])
    }
}
