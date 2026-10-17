import SwiftUI

struct AnimePlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive
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
    @State private var handoffPosition: Double = 0
    @State private var handoffThrottle = AsterionHandoffThrottle()

    private let longEpisodeThreshold = 40

    var body: some View {
        Group {
            if store.isLoadingShow {
                PlayerLoadingState(message: "Opening \(route.title)…")
            } else if let error = store.showError {
                PlayerErrorState(
                    title: "Couldn’t open this anime",
                    message: error,
                    retry: { Task { await store.retryShow() } }
                )
            } else if let show = store.show {
                HStack(spacing: 0) {
                    if showsEpisodeList {
                        episodeSidebar(show)
                            .frame(width: usesEpisodeGrid ? 410 : 270)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        Rectangle()
                            .fill(Color.asterionHairline)
                            .frame(width: 1)
                    }
                    playerPane
                        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
                }
                .animation(reduceMotion ? nil : AsterionMotion.sidebar, value: showsEpisodeList)
            } else {
                PlayerLoadingState(message: "Opening \(route.title)…")
            }
        }
        .frame(minWidth: 850, minHeight: 540)
        .background(Color.black)
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
        .userActivity(
            AsterionHandoff.watchingActivityType,
            isActive: appearsActive && activePlayback != nil
        ) { activity in
            guard let playback = activePlayback else { return }
            AsterionHandoff.configureWatching(
                activity,
                mediaType: .anime,
                contentID: playback.item.contentID,
                unitID: playback.unitID,
                positionSeconds: handoffPosition,
                title: playback.item.title,
                imageURL: playback.item.imageURL
            )
        }
        .onChange(of: AsterionHandoffInbox.shared.watchingRequest?.id) { _, requestID in
            guard requestID != nil else { return }
            continueHandoff()
        }
        .onAppear { AsterionHandoffInbox.shared.playerAppeared(route) }
        .onDisappear {
            handoffThrottle.cancel()
            AsterionHandoffInbox.shared.playerDisappeared(route)
        }
    }

    /// A Handoff for the show this window is already playing: switch to the
    /// handed-off episode, or restart the current one at the handed-off time.
    private func continueHandoff() {
        guard let request = AsterionHandoffInbox.shared.watchingRequest,
              request.mediaType == .anime,
              request.animeRoute == route,
              let show = store.show,
              show.slug == request.contentID else { return }
        if let episodeID = request.episodeID, episodeID != store.selectedEpisodeID {
            guard let episode = store.episodes.first(where: { $0.id == episodeID }) else { return }
            Task { await store.play(episode) }
        } else {
            activePlayback = nil
            preparingPlayback = nil
            activePlaybackSessionID = nil
            preparePlayback()
        }
    }

    private func episodeSidebar(_ show: AnimeShow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Episodes")
                        .font(.asterionTitle(16, weight: .bold))
                        .foregroundStyle(Color.asterionText)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Text(verbatim: String(store.episodes.count))
                        .font(.asterionMono(11, weight: .medium))
                        .foregroundStyle(Color.asterionFaint)
                        .accessibilityLabel("\(store.episodes.count) episodes")
                }

                Text(
                    [show.displayTitle, show.season]
                        .compactMap { $0?.isEmpty == false ? $0 : nil }
                        .joined(separator: " · ")
                )
                .font(.system(size: 12))
                .foregroundStyle(Color.asterionMuted)
                .lineLimit(2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Rectangle()
                .fill(Color.asterionHairline)
                .frame(height: 1)

            if store.episodes.isEmpty {
                AsterionEmptyState(
                    systemImage: "film.stack",
                    title: "No episodes",
                    message: "Episodes will appear here once they’re available."
                )
            } else if usesEpisodeGrid {
                longEpisodeGrid
                    .padding(.top, 12)
            } else {
                shortEpisodeList
            }
        }
        .background(Color.asterionSurface)
    }

    private var shortEpisodeList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.episodes) { episode in
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

    private func episodeRow(_ episode: AnimeEpisode) -> some View {
        let isSelected = store.selectedEpisodeID == episode.id
        let progress = isSelected ? nil : partialProgress(for: episode)

        return Button {
            Task { await store.play(episode) }
        } label: {
            PlayerEpisodeRowLabel(
                number: String(episode.number),
                title: "Episode \(episode.number)",
                isSelected: isSelected,
                isLoading: store.isLoadingStream && isSelected,
                progress: progress
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play episode \(episode.number)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func partialProgress(for episode: AnimeEpisode) -> Double? {
        guard let show = store.show,
              let progress = model.mediaProgressByKey[
                  MediaAccountKey(mediaType: .anime, contentID: show.slug)
              ],
              progress.unitId == episode.id,
              !progress.completed,
              progress.percentage > 0.5,
              progress.percentage < 99.5 else { return nil }
        return progress.percentage / 100
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
                    HStack(spacing: 6) {
                        Text(currentEpisodeRange?.label ?? "Episodes")
                            .font(.asterionMono(11.5, weight: .semibold))
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

                Button { selectedEpisodePage -= 1 } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(selectedEpisodePage == 0)
                .help("Previous 100 episodes")
                .accessibilityLabel("Previous 100 episodes")

                Button { selectedEpisodePage += 1 } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(selectedEpisodePage >= episodeRanges.count - 1)
                .help("Next 100 episodes")
                .accessibilityLabel("Next 100 episodes")

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    Image(systemName: "number")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.asterionFaint)
                    TextField("Find number", text: $episodeSearch)
                        .textFieldStyle(.plain)
                        .font(.asterionMono(12, weight: .medium))
                        .foregroundStyle(Color.asterionText)
                        .onSubmit(findEpisode)
                        .accessibilityLabel("Find episode number")
                }
                .padding(.horizontal, 11)
                .frame(width: 118, height: 30)
                .background(Color.black.opacity(0.28), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(
                            episodeSearchError == nil
                                ? Color.white.opacity(0.10)
                                : Color.asterionWarning.opacity(0.6)
                        )
                }
            }
            .buttonStyle(PlayerChromeButtonStyle())
            .controlSize(.small)

            if let episodeSearchError {
                Label(episodeSearchError, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.asterionWarning)
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
        .padding(.horizontal, 14)
    }

    private func episodeGridButton(_ episode: AnimeEpisode) -> some View {
        let isSelected = store.selectedEpisodeID == episode.id
        let isLoading = store.isLoadingStream && isSelected

        return Button {
            episodeSearchError = nil
            Task { await store.play(episode) }
        } label: {
            PlayerEpisodeGridCell(
                number: String(episode.number),
                isSelected: isSelected,
                isLoading: isLoading,
                progress: isSelected ? nil : partialProgress(for: episode)
            )
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
            playerStage
        }
    }

    private var playerToolbar: some View {
        HStack(spacing: 8) {
            Button {
                showsEpisodeList.toggle()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(PlayerChromeButtonStyle(isLit: showsEpisodeList))
            .help(showsEpisodeList ? "Hide episodes" : "Show episodes")
            .accessibilityLabel(showsEpisodeList ? "Hide episodes" : "Show episodes")

            PlayerTitleLabel(
                title: store.show?.displayTitle ?? route.title,
                detail: store.episodePositionLabel
            )
            .padding(.leading, 6)

            Spacer(minLength: 24)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
                .accessibilityHidden(true)

            PlayerPinButton(isPinned: $keepsWindowOnTop)

            Button {
                Task { await store.playPrevious() }
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(PlayerChromeButtonStyle())
            .disabled(store.previousEpisode == nil || store.isLoadingStream)
            .help("Previous episode")
            .accessibilityLabel("Previous episode")

            Button {
                Task { await store.playNext() }
            } label: {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(PlayerChromeButtonStyle())
            .disabled(store.nextEpisode == nil || store.isLoadingStream)
            .help("Next episode")
            .accessibilityLabel("Next episode")

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

    @ViewBuilder
    private var playerStage: some View {
        Group {
            if store.isLoadingStream {
                PlayerLoadingState(message: "Preparing episode…", artworkURL: store.show?.imageURL)
            } else if let error = store.streamError {
                PlayerErrorState(
                    title: "This episode didn’t load",
                    message: error,
                    retry: { Task { await retryStreamPreservingProgress() } }
                )
            } else if preparingPlayback != nil {
                PlayerLoadingState(message: "Syncing your place…", artworkURL: store.show?.imageURL)
            } else if let option = store.selectedPlaybackOption,
                      let playback = activePlayback,
                      let sessionID = activePlaybackSessionID {
                switch option.kind {
                case .direct:
                    MediaDirectPlayer(
                        url: option.url,
                        subtitleTracks: option.subtitleTracks,
                        requestHeaders: option.requestHeaders,
                        initialPosition: playbackResumePosition,
                        onProgress: { sample in
                            playbackResumePosition = sample.positionSeconds
                            let position = sample.positionSeconds
                            handoffThrottle.submit { handoffPosition = position }
                            Task {
                                await model.recordMediaPlaybackSample(
                                    playback,
                                    sample: sample,
                                    sessionID: sessionID
                                )
                            }
                        },
                        onEnded: autoplayNextEpisode,
                        onFailure: {
                            store.reportPlaybackFailure($0, for: option)
                        }
                    )
                        .id(option.id)
                case .embed:
                    MediaWebPlayer(
                        url: option.url,
                        initialPosition: playbackResumePosition,
                        onProgress: { sample in
                            playbackResumePosition = sample.positionSeconds
                            let position = sample.positionSeconds
                            handoffThrottle.submit { handoffPosition = position }
                            Task {
                                await model.recordMediaPlaybackSample(
                                    playback,
                                    sample: sample,
                                    sessionID: sessionID
                                )
                            }
                        },
                        onEnded: autoplayNextEpisode,
                        onFailure: {
                            store.reportPlaybackFailure($0, for: option)
                        }
                    )
                        .id(option.id)
                }
            } else {
                AsterionEmptyState(
                    systemImage: "play.rectangle",
                    title: "Choose an episode",
                    message: "Pick an episode from the list to start watching."
                ) {
                    if !showsEpisodeList {
                        Button {
                            showsEpisodeList = true
                        } label: {
                            Label("Show episodes", systemImage: "sidebar.left")
                        }
                        .buttonStyle(.asterionSecondary)
                    }
                }
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
            let handoffStart = AsterionHandoffInbox.shared.takePlaybackPosition(
                mediaType: .anime,
                contentID: show.slug,
                unitID: episode.id
            )
            playbackResumePosition = handoffStart ?? resumePosition
            handoffThrottle.cancel()
            handoffPosition = playbackResumePosition
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
