import AVKit
import SwiftUI
import WebKit

struct AnimePlayerView: View {
    let route: AnimePlayerRoute

    @StateObject private var store = AnimePlayerStore()
    @State private var showsEpisodeList = false

    var body: some View {
        Group {
            if store.isLoadingShow {
                ProgressView("Opening \(route.title)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.showError {
                ContentUnavailableView {
                    Label("Couldn’t open this anime", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await store.retryShow() } }
                }
            } else if let show = store.show {
                HStack(spacing: 0) {
                    if showsEpisodeList {
                        episodeSidebar(show)
                            .frame(width: 250)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        Divider()
                    }
                    playerPane
                        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
                }
                .animation(AsterionMotion.sidebar, value: showsEpisodeList)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 850, minHeight: 540)
        .background(.background)
        .navigationTitle(route.title)
        .task(id: route) {
            await store.load(route: route)
        }
    }

    private func episodeSidebar(_ show: AnimeShow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(show.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)

                HStack(spacing: 5) {
                    if let season = show.season, !season.isEmpty {
                        Text(season)
                    }
                    if show.season?.isEmpty == false {
                        Text("·")
                    }
                    Text("\(store.episodes.count) episodes")
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.46))
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)

            Divider().overlay(.white.opacity(0.06))

            Text("EPISODES")
                .font(.asterionMono(9, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.38))
                .padding(.horizontal, 15)
                .padding(.top, 13)
                .padding(.bottom, 6)

            if store.episodes.isEmpty {
                ContentUnavailableView("No episodes", systemImage: "film.stack")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.episodes) { episode in
                    Button {
                        Task { await store.play(episode) }
                    } label: {
                        HStack(spacing: 10) {
                            Text(String(episode.number))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.38))
                                .frame(width: 30, alignment: .trailing)

                            Text("Episode \(episode.number)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.86))

                            Spacer()

                            if store.isLoadingStream, store.selectedEpisodeID == episode.id {
                                ProgressView()
                                    .controlSize(.small)
                            } else if store.selectedEpisodeID == episode.id {
                                Image(systemName: "play.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.asterionAccent)
                            }
                        }
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        store.selectedEpisodeID == episode.id
                            ? Color.asterionAccent.opacity(0.16)
                            : Color.clear
                    )
                    .accessibilityLabel("Play episode \(episode.number)")
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.black.opacity(0.92))
    }

    private var playerPane: some View {
        VStack(spacing: 0) {
            playerToolbar
            Divider()
            playerStage

            if store.selectedPlaybackOption?.kind == .embed {
                Label(
                    "The web player is supplied by a third party and may include external content.",
                    systemImage: "globe"
                )
                .font(.caption)
                .foregroundStyle(Color.asterionMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.asterionSurface)
            }
        }
    }

    private var playerToolbar: some View {
        HStack(spacing: 12) {
            Button {
                showsEpisodeList.toggle()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.65))
            .help(showsEpisodeList ? "Hide Episodes" : "Show Episodes")
            .accessibilityLabel(showsEpisodeList ? "Hide Episodes" : "Show Episodes")

            Text(store.episodePositionLabel)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.72))

            Spacer()

            Button {
                Task { await store.playPrevious() }
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.72))
            .disabled(store.previousEpisode == nil || store.isLoadingStream)
            .help("Previous Episode")
            .accessibilityLabel("Previous Episode")

            Button {
                Task { await store.playNext() }
            } label: {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.72))
            .disabled(store.nextEpisode == nil || store.isLoadingStream)
            .help("Next Episode")
            .accessibilityLabel("Next Episode")

            if store.playbackOptions.count > 1 {
                Menu {
                    ForEach(store.playbackOptions) { option in
                        Button {
                            store.choosePlaybackOption(option)
                        } label: {
                            if store.selectedPlaybackOption == option {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .menuStyle(.borderlessButton)
                .foregroundStyle(.white.opacity(0.72))
                .help(store.selectedPlaybackOption?.title ?? "Playback Source")
                .accessibilityLabel(store.selectedPlaybackOption?.title ?? "Playback Source")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color.black.opacity(0.94))
    }

    @ViewBuilder
    private var playerStage: some View {
        Group {
            if store.isLoadingStream {
                ProgressView("Preparing episode…")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else if let error = store.streamError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                    Text(error)
                        .multilineTextAlignment(.center)
                    Button("Try Again") { Task { await store.retryStream() } }
                }
                .foregroundStyle(.white)
                .padding()
            } else if let option = store.selectedPlaybackOption {
                switch option.kind {
                case .direct:
                    AnimeDirectPlayer(url: option.url)
                        .id(option.id)
                case .embed:
                    AnimeEmbedPlayer(url: option.url)
                        .id(option.id)
                }
            } else {
                ContentUnavailableView(
                    "Choose an episode",
                    systemImage: "play.rectangle",
                    description: Text("Select an episode from the list to begin watching.")
                )
                .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}

private struct AnimeDirectPlayer: View {
    @State private var player: AVPlayer

    init(url: URL) {
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player.play() }
            .onDisappear { player.pause() }
    }
}

private struct AnimeEmbedPlayer: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.preferences.isElementFullscreenEnabled = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: ()) {
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }
}
