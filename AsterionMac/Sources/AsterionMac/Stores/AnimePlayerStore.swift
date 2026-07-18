import Combine
import Foundation

@MainActor
final class AnimePlayerStore: ObservableObject {
    @Published private(set) var show: AnimeShow?
    @Published private(set) var episodes: [AnimeEpisode] = []
    @Published private(set) var selectedEpisodeID: AnimeEpisode.ID?
    @Published private(set) var playbackOptions: [AnimePlaybackOption] = []
    @Published private(set) var selectedPlaybackOption: AnimePlaybackOption?
    @Published private(set) var isLoadingShow = false
    @Published private(set) var isLoadingStream = false
    @Published private(set) var showError: String?
    @Published private(set) var streamError: String?

    private let api: AnimeAPI
    private var route: AnimePlayerRoute?
    private var showRequestID = UUID()

    init(api: AnimeAPI = AnimeAPI()) {
        self.api = api
    }

    var selectedEpisode: AnimeEpisode? {
        episodes.first { $0.id == selectedEpisodeID }
    }

    var previousEpisode: AnimeEpisode? {
        adjacentEpisode(offset: -1)
    }

    var nextEpisode: AnimeEpisode? {
        adjacentEpisode(offset: 1)
    }

    var episodePositionLabel: String {
        guard let selectedEpisode,
              let index = episodes.firstIndex(of: selectedEpisode) else { return "Episode" }
        return "Episode \(selectedEpisode.number) · \(index + 1) of \(episodes.count)"
    }

    func load(route: AnimePlayerRoute, force: Bool = false) async {
        guard force || self.route != route || show == nil else { return }

        self.route = route
        let requestID = UUID()
        showRequestID = requestID
        isLoadingShow = true
        showError = nil
        show = nil
        episodes = []
        resetPlayback()

        do {
            let loadedShow = try await api.fetchShow(slug: route.slug)
            guard !Task.isCancelled, showRequestID == requestID else { return }

            let loadedEpisodes = try await api.fetchEpisodes(showID: loadedShow.id)
            guard !Task.isCancelled, showRequestID == requestID else { return }

            show = loadedShow
            episodes = loadedEpisodes.sorted { $0.number < $1.number }
            isLoadingShow = false

            let requestedEpisode = route.initialEpisodeID.flatMap { episodeID in
                episodes.first { $0.id == episodeID }
            }
            guard let episode = requestedEpisode ?? episodes.last else { return }
            await play(episode)
        } catch {
            guard !Task.isCancelled, showRequestID == requestID else { return }
            showError = error.localizedDescription
            isLoadingShow = false
        }
    }

    func retryShow() async {
        guard let route else { return }
        await load(route: route, force: true)
    }

    func play(_ episode: AnimeEpisode) async {
        guard episodes.contains(episode) else { return }

        selectedEpisodeID = episode.id
        playbackOptions = []
        selectedPlaybackOption = nil
        streamError = nil
        isLoadingStream = true

        do {
            let sources = try await api.fetchStream(
                animeID: episode.animeID,
                episodeNumber: episode.number
            )
            guard selectedEpisodeID == episode.id else { return }

            let options = AnimePlaybackOption.options(from: sources)
            guard !options.isEmpty else { throw AnimeAPIError.noPlaybackSource }

            playbackOptions = options
            selectedPlaybackOption = options.first { $0.kind == .direct } ?? options[0]
            isLoadingStream = false
        } catch {
            guard selectedEpisodeID == episode.id else { return }
            streamError = error.localizedDescription
            isLoadingStream = false
        }
    }

    func playPrevious() async {
        guard let previousEpisode else { return }
        await play(previousEpisode)
    }

    func playNext() async {
        guard let nextEpisode else { return }
        await play(nextEpisode)
    }

    func retryStream() async {
        guard let selectedEpisode else { return }
        await play(selectedEpisode)
    }

    func choosePlaybackOption(_ option: AnimePlaybackOption) {
        guard playbackOptions.contains(option) else { return }
        selectedPlaybackOption = option
    }

    private func adjacentEpisode(offset: Int) -> AnimeEpisode? {
        guard let selectedEpisode,
              let index = episodes.firstIndex(of: selectedEpisode) else { return nil }
        let adjacentIndex = index + offset
        guard episodes.indices.contains(adjacentIndex) else { return nil }
        return episodes[adjacentIndex]
    }

    private func resetPlayback() {
        selectedEpisodeID = nil
        playbackOptions = []
        selectedPlaybackOption = nil
        isLoadingStream = false
        streamError = nil
    }
}
