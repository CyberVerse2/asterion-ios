import AVKit
import SwiftUI
import WebKit

struct MediaDirectPlayer: View {
    let url: URL
    let subtitleTracks: [AnimeSubtitleTrack]

    @State private var player: AVPlayer

    init(url: URL, subtitleTracks: [AnimeSubtitleTrack] = []) {
        self.url = url
        self.subtitleTracks = subtitleTracks
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        Group {
            if subtitleTracks.isEmpty {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else {
                CaptionedMediaPlayer(url: url, subtitleTracks: subtitleTracks)
            }
        }
        .background(.black)
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
                let loadedTracks = try await AnimeSubtitleLoader.load(subtitleTracks)
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

    @State private var errorMessage: String?
    @State private var playerAttempt = 0

    var body: some View {
        ZStack {
            RestrictedMediaWebView(
                url: url,
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
    let onError: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onError: onError)
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
        let signature = CaptionedMediaDocument.signature(url: url, tracks: subtitleTracks)
        guard context.coordinator.loadedSignature != signature else { return }
        loadPlayer(in: webView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.messageName
        )
        webView.loadHTMLString("", baseURL: nil)
    }

    private func loadPlayer(in webView: WKWebView, coordinator: Coordinator) {
        let signature = CaptionedMediaDocument.signature(url: url, tracks: subtitleTracks)
        coordinator.loadedSignature = signature
        let html = CaptionedMediaDocument.html(url: url, tracks: subtitleTracks)
        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        static let messageName = "asterionPlayback"

        var loadedSignature: String?
        private let onError: @MainActor (String) -> Void

        init(onError: @escaping @MainActor (String) -> Void) {
            self.onError = onError
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == Self.messageName,
                  let error = message.body as? String else { return }
            Task { @MainActor in onError(error) }
        }
    }
}

enum CaptionedMediaDocument {
    static func signature(url: URL, tracks: [AnimeSubtitleTrack]) -> String {
        ([url.absoluteString] + tracks.map {
            "\($0.fileURL.absoluteString)|\($0.label)|\($0.kind)|\($0.languageCode ?? "")|\($0.isDefault)"
        }).joined(separator: "\n")
    }

    static func html(url: URL, tracks: [AnimeSubtitleTrack]) -> String {
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
            const report = message => window.webkit.messageHandlers.asterionPlayback.postMessage(message);
            player.addEventListener('error', () => report('The video source could not be played.'));
            document.querySelectorAll('track').forEach(track => {
              track.addEventListener('error', () => report(`The ${track.dataset.label} subtitle track could not be loaded.`));
            });
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
    let url: URL
    let onError: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(initialURL: url, onError: onError)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = true

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
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private(set) var initialURL: URL
        private var navigationState: MediaNavigationState
        private let onError: @MainActor (String) -> Void

        init(initialURL: URL, onError: @escaping @MainActor (String) -> Void) {
            self.initialURL = initialURL
            self.navigationState = MediaNavigationState(initialURL: initialURL)
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

        private func report(_ message: String) {
            Task { @MainActor in onError(message) }
        }
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
