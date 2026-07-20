import SwiftUI

struct AnimePlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var mediaDownloads: MediaDownloadManager
    let route: AnimePlayerRoute

    @StateObject private var store = AnimePlayerStore()
    @State private var showsEpisodeList = false
    @State private var selectedEpisodePage = 0
    @State private var episodeSearch = ""
    @State private var episodeSearchError: String?
    @State private var activePlayback: MediaPlaybackDescriptor?
    @State private var preparingPlayback: MediaPlaybackDescriptor?
    @State private var activePlaybackSessionID: String?
    @State private var playbackResumePosition: Double = 0
    @State private var playbackPreparationID = UUID()
    @State private var keepsWindowOnTop = false

    private let longEpisodeThreshold = 40

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
                            .frame(width: usesEpisodeGrid ? 410 : 250)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        Divider()
                    }
                    playerPane
                        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
                }
                .animation(reduceMotion ? nil : AsterionMotion.sidebar, value: showsEpisodeList)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 850, minHeight: 540)
        .background(Color.asterionMediaCanvas)
        .navigationTitle(route.title)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .mediaWindowPinning(isPinned: keepsWindowOnTop)
        .task(id: route) {
            activePlayback = nil
            preparingPlayback = nil
            activePlaybackSessionID = nil
            playbackResumePosition = 0
            playbackPreparationID = UUID()
            await store.load(
                route: route,
                offlineDownloads: mediaDownloads.completedRecords(
                    mediaType: .anime,
                    contentID: route.slug
                )
            )
            preparePlayback()
        }
        .onChange(of: store.episodes) { _, _ in
            revealSelectedEpisode()
        }
        .onChange(of: store.selectedEpisodeID) { _, _ in
            revealSelectedEpisode()
            preparePlayback()
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
            } else if usesEpisodeGrid {
                longEpisodeGrid
            } else {
                shortEpisodeList
            }
        }
        .background(Color.black.opacity(0.92))
    }

    private var shortEpisodeList: some View {
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

    private var longEpisodeGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Menu {
                    ForEach(Array(episodeRanges.enumerated()), id: \.element.id) { index, range in
                        Button(range.label) {
                            selectedEpisodePage = index
                            episodeSearchError = nil
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(currentEpisodeRange?.label ?? "Episodes")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }
                .menuStyle(.borderlessButton)

                Button { selectedEpisodePage -= 1 } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(selectedEpisodePage == 0)
                .help("Previous 100 episodes")

                Button { selectedEpisodePage += 1 } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(selectedEpisodePage >= episodeRanges.count - 1)
                .help("Next 100 episodes")

                Spacer(minLength: 4)

                TextField("Find number", text: $episodeSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.84))
                    .padding(.horizontal, 9)
                    .frame(width: 105, height: 30)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(.white.opacity(0.13), lineWidth: 1)
                    }
                    .onSubmit(findEpisode)
                    .accessibilityLabel("Find episode number")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

            if let episodeSearchError {
                Text(episodeSearchError)
                    .font(.caption2)
                    .foregroundStyle(Color.asterionAccent)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 6),
                        spacing: 7
                    ) {
                        ForEach(currentEpisodeRange?.episodes ?? []) { episode in
                            episodeGridButton(episode)
                                .id(episode.id)
                        }
                    }
                    .padding(.bottom, 12)
                }
                .onAppear {
                    scrollEpisodeGrid(proxy, animated: false)
                }
                .onChange(of: selectedEpisodePage) { _, _ in
                    scrollEpisodeGrid(proxy, animated: true)
                }
                .onChange(of: store.selectedEpisodeID) { _, _ in
                    scrollEpisodeGrid(proxy, animated: true)
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, 4)
    }

    private func episodeGridButton(_ episode: AnimeEpisode) -> some View {
        let isSelected = store.selectedEpisodeID == episode.id
        let isLoading = store.isLoadingStream && isSelected

        return Button {
            episodeSearchError = nil
            Task { await store.play(episode) }
        } label: {
            ZStack {
                Text(String(episode.number))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                }
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.82))
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                isSelected ? Color.asterionAccent : Color.white.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 5)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isSelected ? Color.asterionAccent.opacity(0.95) : .white.opacity(0.035))
            }
        }
        .buttonStyle(.plain)
        .disabled(store.isLoadingStream && !isSelected)
        .accessibilityLabel("Play episode \(episode.number)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var usesEpisodeGrid: Bool {
        store.episodes.count > longEpisodeThreshold
    }

    private var episodeRanges: [AnimeEpisodeRange] {
        AnimeEpisodeRange.pages(for: store.episodes)
    }

    private var currentEpisodeRange: AnimeEpisodeRange? {
        guard episodeRanges.indices.contains(selectedEpisodePage) else { return episodeRanges.first }
        return episodeRanges[selectedEpisodePage]
    }

    private func revealSelectedEpisode() {
        guard let index = episodeRanges.firstIndex(where: { $0.contains(episodeID: store.selectedEpisodeID) }) else {
            selectedEpisodePage = 0
            return
        }
        selectedEpisodePage = index
    }

    private func scrollEpisodeGrid(_ proxy: ScrollViewProxy, animated: Bool) {
        let destination = currentEpisodeRange?.contains(episodeID: store.selectedEpisodeID) == true
            ? store.selectedEpisodeID
            : currentEpisodeRange?.episodes.first?.id
        guard let destination else { return }

        DispatchQueue.main.async {
            if animated, !reduceMotion {
                withAnimation(AsterionMotion.sidebar) {
                    proxy.scrollTo(destination, anchor: .center)
                }
            } else {
                proxy.scrollTo(destination, anchor: .center)
            }
        }
    }

    private func findEpisode() {
        let trimmedSearch = episodeSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(trimmedSearch),
              let episode = store.episodes.first(where: { $0.number == number }) else {
            episodeSearchError = "Episode not found"
            return
        }

        episodeSearchError = nil
        if let index = episodeRanges.firstIndex(where: { $0.contains(episodeID: episode.id) }) {
            selectedEpisodePage = index
        }
        Task { await store.play(episode) }
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

            Spacer(minLength: 24)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
                .accessibilityHidden(true)

            MediaWindowPinButton(isPinned: $keepsWindowOnTop)

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
            } else if preparingPlayback != nil {
                ProgressView("Syncing your place…")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else if let option = store.selectedPlaybackOption,
                      let playback = activePlayback,
                      let sessionID = activePlaybackSessionID {
                switch option.kind {
                case .direct:
                    MediaDirectPlayer(
                        url: option.url,
                        subtitleTracks: option.subtitleTracks,
                        initialPosition: playbackResumePosition,
                        onProgress: { sample in
                            Task {
                                await model.recordMediaPlaybackSample(
                                    playback,
                                    sample: sample,
                                    sessionID: sessionID
                                )
                            }
                        },
                        onEnded: autoplayNextEpisode
                    )
                        .id(option.id)
                case .embed:
                    MediaWebPlayer(
                        url: option.url,
                        initialPosition: playbackResumePosition,
                        onProgress: { sample in
                            Task {
                                await model.recordMediaPlaybackSample(
                                    playback,
                                    sample: sample,
                                    sessionID: sessionID
                                )
                            }
                        },
                        onEnded: autoplayNextEpisode
                    )
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

    private func preparePlayback() {
        guard let show = store.show, let episode = store.selectedEpisode else { return }
        let playback = MediaPlaybackDescriptor(
            item: MediaItemDescriptor(
                mediaType: .anime,
                contentID: show.slug,
                title: show.displayTitle,
                subtitle: show.season ?? show.type,
                imageURL: show.imageURL
            ),
            unitID: episode.id,
            unitTitle: "Episode \(episode.number)",
            seasonNumber: nil,
            episodeNumber: episode.number
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
}
