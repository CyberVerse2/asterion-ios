import SwiftUI

struct MoviePlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var mediaDownloads: MediaDownloadManager
    let route: MoviePlayerRoute

    @StateObject private var store = MoviePlayerStore()
    @State private var showsEpisodeList = false
    @State private var selectedSeason: Int?
    @State private var activePlayback: MediaPlaybackDescriptor?
    @State private var preparingPlayback: MediaPlaybackDescriptor?
    @State private var activePlaybackSessionID: String?
    @State private var playbackResumePosition: Double = 0
    @State private var playbackPreparationID = UUID()
    @State private var keepsWindowOnTop = false

    var body: some View {
        Group {
            if store.isLoadingShow {
                PlayerLoadingState(message: "Opening \(route.title)…")
            } else if let error = store.showError {
                PlayerErrorState(
                    title: "Couldn’t open this title",
                    message: error,
                    retry: { Task { await store.retryShow() } }
                )
            } else if let show = store.show {
                HStack(spacing: 0) {
                    if show.isSeries, showsEpisodeList {
                        episodeSidebar(show)
                            .frame(width: 290)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        Rectangle()
                            .fill(Color.asterionHairline)
                            .frame(width: 1)
                    }

                    playerPane(show)
                        .frame(minWidth: 580, maxWidth: .infinity, maxHeight: .infinity)
                }
                .animation(reduceMotion ? nil : AsterionMotion.sidebar, value: showsEpisodeList)
            } else {
                PlayerLoadingState(message: "Opening \(route.title)…")
            }
        }
        .frame(minWidth: 850, minHeight: 540)
        .background(.black)
        .navigationTitle(route.title)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .mediaWindowPinning(isPinned: keepsWindowOnTop)
        .task(id: route) {
            showsEpisodeList = false
            activePlayback = nil
            preparingPlayback = nil
            activePlaybackSessionID = nil
            playbackResumePosition = 0
            playbackPreparationID = UUID()
            await store.load(
                route: route,
                offlineDownloads: mediaDownloads.completedRecords(
                    mediaType: .movie,
                    contentID: route.slug
                )
            )
            preparePlayback()
        }
        .onChange(of: store.selectedEpisode) { _, episode in
            if let episode { selectedSeason = episode.season }
            preparePlayback()
        }
    }

    private func episodeSidebar(_ show: MovieShow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Episodes")
                        .font(.asterionTitle(16, weight: .bold))
                        .foregroundStyle(Color.asterionText)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Text(store.episodes.count.formatted())
                        .font(.asterionMono(11, weight: .medium))
                        .foregroundStyle(Color.asterionFaint)
                        .accessibilityLabel("\(store.episodes.count) episodes")
                }
                Text(show.displayTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if availableSeasons.count > 1 {
                Menu {
                    Picker("Season", selection: seasonBinding) {
                        ForEach(availableSeasons, id: \.self) { season in
                            Text("Season \(season)").tag(season)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    HStack(spacing: 6) {
                        Text("Season")
                            .font(.system(size: 12, weight: .semibold))
                        Text(String(seasonBinding.wrappedValue))
                            .font(.asterionMono(12, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(Color.asterionText.opacity(0.86))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background { PlayerChromeCapsule() }
                    .contentShape(Capsule())
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel("Season \(seasonBinding.wrappedValue)")
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }

            Rectangle()
                .fill(Color.asterionHairline)
                .frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(episodesForSelectedSeason) { episode in
                            episodeRow(episode)
                                .id(episode.id)
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    guard let selected = store.selectedEpisodeID else { return }
                    proxy.scrollTo(selected, anchor: .center)
                }
            }
        }
        .background(Color.asterionSurface)
    }

    private func episodeRow(_ episode: MovieEpisode) -> some View {
        let isSelected = store.selectedEpisodeID == episode.id

        return Button {
            Task { await store.play(episode) }
        } label: {
            PlayerEpisodeRowLabel(
                number: String(episode.number),
                title: episode.title,
                isSelected: isSelected,
                isLoading: store.isLoadingStream && isSelected,
                progress: isSelected ? nil : partialProgress(for: episode)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play \(episode.title), episode \(episode.number)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func partialProgress(for episode: MovieEpisode) -> Double? {
        guard let show = store.show,
              let progress = model.mediaProgressByKey[
                  MediaAccountKey(mediaType: .movie, contentID: show.slug)
              ],
              progress.unitId == episode.id,
              !progress.completed,
              progress.percentage > 0.5,
              progress.percentage < 99.5 else { return nil }
        return progress.percentage / 100
    }

    private func playerPane(_ show: MovieShow) -> some View {
        VStack(spacing: 0) {
            playerToolbar(show)
            playerStage

            if store.selectedPlaybackOption?.kind == .web {
                PlayerThirdPartyNotice(
                    text: "This player is supplied by a third party and may include external content."
                )
            }
        }
    }

    private func playerToolbar(_ show: MovieShow) -> some View {
        HStack(spacing: 8) {
            if show.isSeries {
                Button {
                    showsEpisodeList.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(PlayerChromeButtonStyle(isLit: showsEpisodeList))
                .help(showsEpisodeList ? "Hide episodes" : "Show episodes")
                .accessibilityLabel(showsEpisodeList ? "Hide episodes" : "Show episodes")
            }

            PlayerTitleLabel(
                title: show.displayTitle,
                detail: show.isSeries ? toolbarEpisodeDetail : nil
            )
            .padding(.leading, show.isSeries ? 6 : 4)

            Spacer(minLength: 24)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
                .accessibilityHidden(true)

            PlayerPinButton(isPinned: $keepsWindowOnTop)

            if show.isSeries {
                Button { Task { await store.playPrevious() } } label: {
                    Image(systemName: "backward.end.fill")
                }
                .buttonStyle(PlayerChromeButtonStyle())
                .disabled(store.previousEpisode == nil || store.isLoadingStream)
                .help("Previous episode")
                .accessibilityLabel("Previous episode")

                Button { Task { await store.playNext() } } label: {
                    Image(systemName: "forward.end.fill")
                }
                .buttonStyle(PlayerChromeButtonStyle())
                .disabled(store.nextEpisode == nil || store.isLoadingStream)
                .help("Next episode")
                .accessibilityLabel("Next episode")
            }

            if store.playbackOptions.count > 1 {
                Menu {
                    ForEach(store.playbackOptions) { option in
                        let isActive = option == store.selectedPlaybackOption
                        let hasFailed = store.isPlaybackOptionFailed(option)
                        Button {
                            store.choosePlaybackOption(option)
                        } label: {
                            HStack {
                                Text(
                                    isActive
                                        ? "\(option.title) · \(store.playbackPhase.label)"
                                        : option.title
                                )
                                    .strikethrough(hasFailed)
                                    .foregroundStyle(hasFailed ? .secondary : .primary)
                                if hasFailed {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                }
                                if option.kind == .web {
                                    Image(systemName: "globe")
                                }
                                if isActive {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    PlayerChromeMenuLabel(systemImage: "slider.horizontal.3")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .fixedSize()
                .help(store.selectedPlaybackOption?.title ?? "Playback source")
                .accessibilityLabel(store.selectedPlaybackOption?.title ?? "Playback source")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(Color.black)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.asterionHairline)
                .frame(height: 1)
        }
    }

    /// "S1 E3 · Episode title" in the player bar; the show title sits beside it.
    private var toolbarEpisodeDetail: String? {
        guard let episode = store.selectedEpisode else { return nil }
        let title = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !title.lowercased().hasPrefix("episode") else {
            return store.positionLabel
        }
        return "\(store.positionLabel) · \(title)"
    }

    @ViewBuilder
    private var playerStage: some View {
        Group {
            if store.isLoadingStream {
                PlayerLoadingState(message: "Preparing video…", artworkURL: store.show?.imageURL)
            } else if let error = store.streamError {
                PlayerErrorState(
                    title: "This video didn’t load",
                    message: error,
                    retry: { Task { await retryStreamPreservingProgress() } }
                )
            } else if preparingPlayback != nil {
                PlayerLoadingState(message: "Syncing your place…", artworkURL: store.show?.imageURL)
            } else if let currentServerIndex = store.currentServerIndex,
                      let playback = activePlayback,
                      let sessionID = activePlaybackSessionID {
                MovieFallbackPlayer(
                    options: store.playbackOptions,
                    currentServerIndex: currentServerIndex,
                    attemptID: store.currentPlaybackAttemptID,
                    initialPosition: playbackResumePosition,
                    onProgress: { sample in
                        playbackResumePosition = sample.positionSeconds
                        Task {
                            await model.recordMediaPlaybackSample(
                                playback,
                                sample: sample,
                                sessionID: sessionID
                            )
                        }
                    },
                    onEnded: autoplayNextEpisode,
                    onLifecycleEvent: { option, attemptID, event in
                        store.reportPlaybackEvent(
                            event,
                            for: option,
                            attemptID: attemptID
                        )
                    }
                )
            } else {
                AsterionEmptyState(
                    systemImage: "play.rectangle",
                    title: "No video selected",
                    message: "Choose an episode or playback source to start watching."
                )
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

    private func preparePlayback() {
        guard let show = store.show else { return }
        let episode = store.selectedEpisode
        let playback = MediaPlaybackDescriptor(
            item: MediaItemDescriptor(
                mediaType: .movie,
                contentID: show.slug,
                title: show.displayTitle,
                subtitle: show.isSeries ? "TV Series" : "Movie",
                imageURL: show.imageURL
            ),
            unitID: episode?.id ?? show.slug,
            unitTitle: episode?.title,
            seasonNumber: episode?.season,
            episodeNumber: episode?.number
        )
        guard activePlayback != playback, preparingPlayback != playback else { return }
        let preparationID = UUID()
        playbackPreparationID = preparationID
        preparingPlayback = playback
        activePlayback = nil
        activePlaybackSessionID = nil
        Task { @MainActor in
            let resumePosition = await model.preparedResumePosition(for: playback)
            guard playbackPreparationID == preparationID,
                  preparingPlayback == playback else { return }
            playbackResumePosition = resumePosition
            activePlayback = playback
            activePlaybackSessionID = UUID().uuidString
            preparingPlayback = nil
        }
    }

    private func autoplayNextEpisode() {
        guard store.nextEpisode != nil else { return }
        Task { await store.playNext() }
    }

    private func retryStreamPreservingProgress() async {
        if let activePlayback {
            let savedPosition = await model.preparedResumePosition(for: activePlayback)
            playbackResumePosition = max(playbackResumePosition, savedPosition)
        }
        await store.retryStream()
    }
}
