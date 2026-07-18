import AVKit
import SwiftUI
import WebKit

struct MediaDirectPlayer: View {
    let url: URL
    let subtitleTracks: [AnimeSubtitleTrack]
    let initialPosition: Double
    let onProgress: @MainActor @Sendable (MediaPlaybackSample) -> Void
    let onEnded: @MainActor @Sendable () -> Void

    @StateObject private var controller: DirectMediaPlaybackController

    init(
        url: URL,
        subtitleTracks: [AnimeSubtitleTrack] = [],
        initialPosition: Double = 0,
        onProgress: @escaping @MainActor @Sendable (MediaPlaybackSample) -> Void = { _ in },
        onEnded: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.url = url
        self.subtitleTracks = subtitleTracks
        self.initialPosition = initialPosition
        self.onProgress = onProgress
        self.onEnded = onEnded
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
                        VStack {
                            Spacer()
                            Text(caption)
                                .font(.system(size: 20, weight: .semibold))
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
                        .allowsHitTesting(false)
                        .accessibilityLabel("Subtitles: \(caption)")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    controller.start(
                        initialPosition: initialPosition,
                        onProgress: onProgress,
                        onEnded: onEnded
                    )
                }
                .onDisappear { controller.stop() }
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
                    onEnded: onEnded
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
    private var periodicObserver: Any?
    private var timeControlObserver: NSKeyValueObservation?
    private var playbackEndObserver: NSObjectProtocol?
    private var onProgress: (@MainActor @Sendable (MediaPlaybackSample) -> Void)?
    private var onEnded: (@MainActor @Sendable () -> Void)?
    private var lastReportedPosition = -Double.infinity
    private var startingPosition = 0.0
    private var hasConfirmedPlayback = false
    private var hasEnteredPlayingState = false
    private var hasSentPlaybackEnd = false

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
        onProgress: @escaping @MainActor @Sendable (MediaPlaybackSample) -> Void,
        onEnded: @escaping @MainActor @Sendable () -> Void
    ) {
        self.onProgress = onProgress
        self.onEnded = onEnded
        startingPosition = max(0, initialPosition)
        hasConfirmedPlayback = false
        hasEnteredPlayingState = false
        hasSentPlaybackEnd = false
        lastReportedPosition = -Double.infinity
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
        player.play()
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
        activeCaption = nil
        onProgress = nil
        onEnded = nil
    }

    private func installPlaybackObserversIfNeeded() {
        if timeControlObserver == nil {
            timeControlObserver = player.observe(
                \.timeControlStatus,
                options: [.old, .new]
            ) { [weak self] _, change in
                let enteredPlaying = change.newValue == .playing
                let becamePaused = change.newValue == .paused
                    && change.oldValue != .paused
                let pausedAfterPlaying = change.oldValue == .playing

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if enteredPlaying || pausedAfterPlaying {
                        self.hasEnteredPlayingState = true
                    }
                    if becamePaused, self.hasEnteredPlayingState {
                        self.report(
                            time: self.player.currentTime(),
                            force: true,
                            allowStoppedPlaybackConfirmation: true
                        )
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
    }

    private func removePlaybackObservers() {
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }
    }

    private func report(
        time: CMTime,
        force: Bool,
        allowStoppedPlaybackConfirmation: Bool = false
    ) {
        let position = time.seconds
        guard position.isFinite, position >= 0 else { return }
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
                    onError: { phase = .failure($0) }
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

    @State private var errorMessage: String?
    @State private var playerAttempt = 0

    init(
        url: URL,
        initialPosition: Double = 0,
        onProgress: @escaping @MainActor @Sendable (MediaPlaybackSample) -> Void = { _ in },
        onEnded: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.url = url
        self.initialPosition = initialPosition
        self.onProgress = onProgress
        self.onEnded = onEnded
    }

    var body: some View {
        ZStack {
            RestrictedMediaWebView(
                url: url,
                initialPosition: initialPosition,
                onProgress: onProgress,
                onEnded: onEnded,
                onError: { errorMessage = $0 }
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
                Task { @MainActor in onError(error) }
            } else if type == "ended" {
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
            player.addEventListener('playing', () => { hasPlayed = true; });
            player.addEventListener('timeupdate', () => reportProgress(false));
            player.addEventListener('pause', () => reportProgress(true));
            player.addEventListener('ended', () => {
              reportProgress(true);
              post({ type: 'ended' });
            });
            player.addEventListener('error', () => reportError('The video source could not be played.'));
            document.querySelectorAll('track').forEach(track => {
              track.addEventListener('error', () => reportError(`The ${track.dataset.label} subtitle track could not be loaded.`));
            });
            window.__asterionFlush = () => reportProgress(true);
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
    let onError: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            initialURL: url,
            onProgress: onProgress,
            onEnded: onEnded,
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
        private let onError: @MainActor (String) -> Void
        private var lastSample: MediaPlaybackSample?

        init(
            initialURL: URL,
            onProgress: @escaping @MainActor @Sendable (MediaPlaybackSample) -> Void,
            onEnded: @escaping @MainActor @Sendable () -> Void,
            onError: @escaping @MainActor (String) -> Void
        ) {
            self.initialURL = initialURL
            self.navigationState = MediaNavigationState(initialURL: initialURL)
            self.onProgress = onProgress
            self.onEnded = onEnded
            self.onError = onError
        }

        func load(_ url: URL, in webView: WKWebView) {
            initialURL = url
            navigationState.reset(initialURL: url)

            guard MediaNavigationPolicy.isSecureRemoteURL(url) else {
                report("This video source does not use a secure web address.")
                return
            }
            webView.load(URLRequest(url: url))
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
            if navigationResponse.isForMainFrame,
               let response = navigationResponse.response as? HTTPURLResponse,
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
            guard type == "progress",
                  let position = (payload["position"] as? NSNumber)?.doubleValue,
                  let duration = (payload["duration"] as? NSNumber)?.doubleValue,
                  let completed = payload["completed"] as? Bool,
                  position.isFinite,
                  duration.isFinite,
                  position > 0 else { return }
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

        private func report(_ message: String) {
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
          let activePlayer = null;
          let selectionQueued = false;

          const post = payload => {
            try {
              window.webkit.messageHandlers.asterionEmbeddedPlayback.postMessage(payload);
            } catch (_) {}
          };

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
            if (selected === player) emit(player, force);
          };

          const attach = player => {
            if (!(player instanceof HTMLMediaElement) || players.has(player)) return;
            players.add(player);
            const state = stateFor(player);
            player.addEventListener('playing', () => {
              state.hasPlayed = true;
              scheduleSelection();
            });
            player.addEventListener('loadedmetadata', scheduleSelection);
            player.addEventListener('durationchange', scheduleSelection);
            player.addEventListener('timeupdate', () => reportIfSelected(player, false));
            player.addEventListener('pause', () => {
              if (activePlayer === player) emit(player, true);
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
          });
          globalThis.__asterionFlush = () => {
            const selected = selectActivePlayer();
            if (selected) emit(selected, true);
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
