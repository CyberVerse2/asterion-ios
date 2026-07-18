import Combine
import Foundation

@MainActor
final class MoviePlayerStore: ObservableObject {
    @Published private(set) var show: MovieShow?
    @Published private(set) var episodes: [MovieEpisode] = []
    @Published private(set) var selectedEpisodeID: MovieEpisode.ID?
    @Published private(set) var playbackOptions: [MoviePlaybackOption] = []
    @Published private(set) var selectedPlaybackOption: MoviePlaybackOption?
    @Published private(set) var isLoadingShow = false
    @Published private(set) var isLoadingStream = false
    @Published private(set) var showError: String?
    @Published private(set) var streamError: String?

    private let api: MovieAPI
    private var route: MoviePlayerRoute?
    private var offlineRecordsByUnitID: [String: MediaDownloadRecord] = [:]
    private var showRequestID = UUID()

    init(api: MovieAPI = MovieAPI()) {
        self.api = api
    }

    var selectedEpisode: MovieEpisode? {
        episodes.first { $0.id == selectedEpisodeID }
    }

    var previousEpisode: MovieEpisode? { adjacentEpisode(offset: -1) }
    var nextEpisode: MovieEpisode? { adjacentEpisode(offset: 1) }

    var positionLabel: String {
        guard let selectedEpisode else { return show?.displayTitle ?? "Movie" }
        return "S\(selectedEpisode.season) E\(selectedEpisode.number)"
    }

    func load(
        route: MoviePlayerRoute,
        offlineDownloads: [MediaDownloadRecord],
        force: Bool = false
    ) async {
        guard force || self.route != route || show == nil else { return }

        self.route = route
        offlineRecordsByUnitID = Dictionary(
            uniqueKeysWithValues: offlineDownloads
                .filter(\.isAvailableOffline)
                .map { ($0.unitID, $0) }
        )
        let requestID = UUID()
        showRequestID = requestID
        isLoadingShow = true
        showError = nil
        show = nil
        episodes = []
        resetPlayback()

        let requestedUnitID = route.initialEpisodeID ?? route.slug
        if let offlineRecord = offlineRecordsByUnitID[requestedUnitID],
           loadOffline(record: offlineRecord) {
            return
        }

        do {
            let loadedShow = try await api.fetchShow(slug: route.slug)
            guard !Task.isCancelled, showRequestID == requestID else { return }
            show = loadedShow

            if loadedShow.isSeries {
                let loadedEpisodes = try await api.fetchEpisodes(slug: route.slug)
                guard !Task.isCancelled, showRequestID == requestID else { return }
                episodes = loadedEpisodes.sorted {
                    ($0.season, $0.number) < ($1.season, $1.number)
                }
                isLoadingShow = false

                let requested = route.initialEpisodeID.flatMap { episodeID in
                    episodes.first { $0.id == episodeID }
                }
                guard let episode = requested ?? episodes.first else { return }
                await play(episode)
            } else {
                isLoadingShow = false
                try setPlaybackOptions(from: loadedShow.streams)
            }
        } catch {
            guard !Task.isCancelled, showRequestID == requestID else { return }
            showError = error.localizedDescription
            isLoadingShow = false
        }
    }

    func retryShow() async {
        guard let route else { return }
        await load(
            route: route,
            offlineDownloads: Array(offlineRecordsByUnitID.values),
            force: true
        )
    }

    func play(_ episode: MovieEpisode) async {
        guard episodes.contains(episode) else { return }

        if let record = offlineRecordsByUnitID[episode.id],
           let assetURL = record.localAssetURL,
           FileManager.default.fileExists(atPath: assetURL.path) {
            selectedEpisodeID = episode.id
            let option = MoviePlaybackOption(
                id: "offline-\(record.id)",
                kind: .direct,
                url: assetURL,
                title: "Downloaded"
            )
            playbackOptions = [option]
            selectedPlaybackOption = option
            streamError = nil
            isLoadingStream = false
            return
        }

        selectedEpisodeID = episode.id
        playbackOptions = []
        selectedPlaybackOption = nil
        streamError = nil
        isLoadingStream = true

        do {
            let episodeDetail = try await api.fetchShow(slug: episode.id)
            guard selectedEpisodeID == episode.id else { return }
            try setPlaybackOptions(from: episodeDetail.streams)
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
        if let selectedEpisode {
            await play(selectedEpisode)
        } else if let show {
            do {
                try setPlaybackOptions(from: show.streams)
            } catch {
                streamError = error.localizedDescription
            }
        }
    }

    func choosePlaybackOption(_ option: MoviePlaybackOption) {
        guard playbackOptions.contains(option) else { return }
        selectedPlaybackOption = option
    }

    private func setPlaybackOptions(from sources: [MovieStreamSource]) throws {
        let options = MoviePlaybackOption.options(from: sources)
        guard !options.isEmpty else { throw MovieAPIError.noPlaybackSource }
        playbackOptions = options
        selectedPlaybackOption = MoviePlaybackOption.preferred(from: options)
        streamError = nil
    }

    private func loadOffline(record: MediaDownloadRecord) -> Bool {
        guard let loadedShow = record.movieShow,
              let assetURL = record.localAssetURL,
              FileManager.default.fileExists(atPath: assetURL.path) else {
            return false
        }

        show = loadedShow
        if loadedShow.isSeries {
            episodes = offlineRecordsByUnitID.values
                .compactMap(\.movieEpisode)
                .sorted { ($0.season, $0.number) < ($1.season, $1.number) }
            guard let selectedEpisode = record.movieEpisode else { return false }
            if !episodes.contains(selectedEpisode) {
                episodes.append(selectedEpisode)
                episodes.sort { ($0.season, $0.number) < ($1.season, $1.number) }
            }
            selectedEpisodeID = selectedEpisode.id
        }
        let option = MoviePlaybackOption(
            id: "offline-\(record.id)",
            kind: .direct,
            url: assetURL,
            title: "Downloaded"
        )
        playbackOptions = [option]
        selectedPlaybackOption = option
        isLoadingShow = false
        isLoadingStream = false
        return true
    }

    private func adjacentEpisode(offset: Int) -> MovieEpisode? {
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
