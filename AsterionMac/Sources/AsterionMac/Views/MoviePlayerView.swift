import SwiftUI

struct MoviePlayerView: View {
    let route: MoviePlayerRoute

    @StateObject private var store = MoviePlayerStore()
    @State private var showsEpisodeList = false
    @State private var selectedSeason: Int?

    var body: some View {
        Group {
            if store.isLoadingShow {
                ProgressView("Opening \(route.title)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.showError {
                ContentUnavailableView {
                    Label("Couldn’t open this title", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await store.retryShow() } }
                }
            } else if let show = store.show {
                HStack(spacing: 0) {
                    if show.isSeries, showsEpisodeList {
                        episodeSidebar(show)
                            .frame(width: 270)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        Divider()
                    }

                    playerPane(show)
                        .frame(minWidth: 580, maxWidth: .infinity, maxHeight: .infinity)
                }
                .animation(AsterionMotion.sidebar, value: showsEpisodeList)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 850, minHeight: 540)
        .background(.black)
        .navigationTitle(route.title)
        .task(id: route) {
            showsEpisodeList = false
            await store.load(route: route)
        }
        .onChange(of: store.selectedEpisode) { _, episode in
            if let episode { selectedSeason = episode.season }
        }
    }

    private func episodeSidebar(_ show: MovieShow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(show.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
                Text("\(store.episodes.count) episodes")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.46))
            }
            .padding(15)

            Divider().overlay(.white.opacity(0.08))

            if availableSeasons.count > 1 {
                Picker("Season", selection: seasonBinding) {
                    ForEach(availableSeasons, id: \.self) { season in
                        Text("Season \(season)").tag(season)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }

            List(episodesForSelectedSeason) { episode in
                Button {
                    Task { await store.play(episode) }
                } label: {
                    HStack(spacing: 10) {
                        Text(String(episode.number))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.38))
                            .frame(width: 28, alignment: .trailing)
                        Text(episode.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.86))
                        Spacer()
                        if store.isLoadingStream, store.selectedEpisodeID == episode.id {
                            ProgressView().controlSize(.small)
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
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(Color.black.opacity(0.94))
    }

    private func playerPane(_ show: MovieShow) -> some View {
        VStack(spacing: 0) {
            playerToolbar(show)
            Divider().overlay(.white.opacity(0.08))
            playerStage

            if store.selectedPlaybackOption?.kind == .web {
                Label(
                    "This player is supplied by a third party and may include external content.",
                    systemImage: "globe"
                )
                .font(.caption)
                .foregroundStyle(.white.opacity(0.44))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(.black)
            }
        }
    }

    private func playerToolbar(_ show: MovieShow) -> some View {
        HStack(spacing: 12) {
            if show.isSeries {
                Button {
                    showsEpisodeList.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(showsEpisodeList ? "Hide Episodes" : "Show Episodes")
            }

            Text(store.positionLabel)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)

            Spacer()

            if show.isSeries {
                Button { Task { await store.playPrevious() } } label: {
                    Image(systemName: "backward.end.fill")
                }
                .disabled(store.previousEpisode == nil || store.isLoadingStream)
                .help("Previous Episode")

                Button { Task { await store.playNext() } } label: {
                    Image(systemName: "forward.end.fill")
                }
                .disabled(store.nextEpisode == nil || store.isLoadingStream)
                .help("Next Episode")
            }

            if store.playbackOptions.count > 1 {
                Menu {
                    ForEach(store.playbackOptions) { option in
                        Button {
                            store.choosePlaybackOption(option)
                        } label: {
                            if option == store.selectedPlaybackOption {
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
                .help(store.selectedPlaybackOption?.title ?? "Playback Source")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.72))
        .controlSize(.small)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color.black.opacity(0.96))
    }

    @ViewBuilder
    private var playerStage: some View {
        Group {
            if store.isLoadingStream {
                ProgressView("Preparing video…")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else if let error = store.streamError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.title)
                    Text(error).multilineTextAlignment(.center)
                    Button("Try Again") { Task { await store.retryStream() } }
                }
                .foregroundStyle(.white)
                .padding()
            } else if let option = store.selectedPlaybackOption {
                switch option.kind {
                case .direct:
                    MediaDirectPlayer(url: option.url).id(option.id)
                case .web:
                    MediaWebPlayer(url: option.url).id(option.id)
                }
            } else {
                ContentUnavailableView(
                    "No video selected",
                    systemImage: "play.rectangle",
                    description: Text("Choose an episode or playback source.")
                )
                .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }

    private var availableSeasons: [Int] {
        Array(Set(store.episodes.map(\.season))).sorted(by: >)
    }

    private var seasonBinding: Binding<Int> {
        Binding(
            get: { selectedSeason ?? store.selectedEpisode?.season ?? availableSeasons.first ?? 0 },
            set: { selectedSeason = $0 }
        )
    }

    private var episodesForSelectedSeason: [MovieEpisode] {
        let season = selectedSeason ?? store.selectedEpisode?.season ?? availableSeasons.first
        guard let season else { return [] }
        return store.episodes.filter { $0.season == season }
    }
}
