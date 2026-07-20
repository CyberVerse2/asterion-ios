import Combine
import Foundation

enum MoviePlaybackPhase: Equatable {
    case loading
    case ready
    case starting
    case playing
    case paused

    var label: String {
        switch self {
        case .loading: "Loading"
        case .ready: "Ready"
        case .starting: "Starting"
        case .playing: "Playing"
        case .paused: "Paused"
        }
    }
}

@MainActor
final class MoviePlayerStore: ObservableObject {
    @Published private(set) var show: MovieShow?
    @Published private(set) var episodes: [MovieEpisode] = []
    @Published private(set) var selectedEpisodeID: MovieEpisode.ID?
    @Published private(set) var playbackOptions: [MoviePlaybackOption] = []
    @Published private(set) var currentServerIndex: Int?
    @Published private(set) var attemptedServerIndices: Set<Int> = []
    @Published private(set) var failedServerIndices: Set<Int> = []
    @Published private(set) var serverFailureMessages: [Int: String] = [:]
    @Published private(set) var currentPlaybackAttemptID = UUID()
    @Published private(set) var playbackPhase: MoviePlaybackPhase = .loading
    @Published private(set) var isLoadingShow = false
    @Published private(set) var isLoadingStream = false
    @Published private(set) var showError: String?
    @Published private(set) var streamError: String?

    private let api: MovieAPI
    private var route: MoviePlayerRoute?
    private var offlineRecordsByUnitID: [String: MediaDownloadRecord] = [:]
    private var showRequestID = UUID()
    private var attemptedOptionIDs: Set<String> = []
    private var failureRecordsByOptionID: [String: (title: String, message: String)] = [:]

    init(api: MovieAPI = MovieAPI()) {
        self.api = api
    }

    var selectedEpisode: MovieEpisode? {
        episodes.first { $0.id == selectedEpisodeID }
    }

    var selectedPlaybackOption: MoviePlaybackOption? {
        guard let currentServerIndex,
              playbackOptions.indices.contains(currentServerIndex) else { return nil }
        return playbackOptions[currentServerIndex]
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
                isLoadingStream = true
                do {
                    let sources = try await api.fetchPlaybackSources(slug: route.slug)
                    try setPlaybackOptions(from: sources)
                } catch {
                    streamError = error.localizedDescription
                }
                isLoadingStream = false
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
            resetOptionTracking()
            beginServerAttempt(at: 0)
            streamError = nil
            isLoadingStream = false
            return
        }

        selectedEpisodeID = episode.id
        playbackOptions = []
        resetServerAttempts()
        streamError = nil
        isLoadingStream = true

        do {
            let sources = try await api.fetchPlaybackSources(slug: episode.id)
            guard selectedEpisodeID == episode.id else { return }
            try setPlaybackOptions(from: sources)
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
        } else if let route {
            do {
                let sources = try await api.fetchPlaybackSources(slug: route.slug)
                try setPlaybackOptions(from: sources)
            } catch {
                streamError = error.localizedDescription
            }
        }
    }

    func choosePlaybackOption(_ option: MoviePlaybackOption) {
        guard let index = playbackOptions.firstIndex(of: option) else { return }
        failureRecordsByOptionID.removeValue(forKey: option.id)
        syncServerTracking()
        streamError = nil
        beginServerAttempt(at: index)
    }

    func reportPlaybackEvent(
        _ event: MediaPlaybackLifecycleEvent,
        for option: MoviePlaybackOption,
        attemptID: UUID
    ) async {
        guard let index = currentServerIndex,
              playbackOptions.indices.contains(index),
              playbackOptions[index].id == option.id,
              currentPlaybackAttemptID == attemptID else { return }

        switch event {
        case .loading:
            playbackPhase = .loading
        case .ready:
            if playbackPhase == .loading {
                playbackPhase = .ready
            }
        case .playRequested:
            playbackPhase = .starting
        case .playing:
            playbackPhase = .playing
        case .paused:
            playbackPhase = .paused
        case .failed(let message):
            await reportPlaybackFailure(
                at: index,
                attemptID: attemptID,
                message: message
            )
        }
    }

    private func reportPlaybackFailure(
        at index: Int,
        attemptID: UUID,
        message: String
    ) async {
        let failedOption = playbackOptions[index]
        attemptedOptionIDs.insert(failedOption.id)
        failureRecordsByOptionID[failedOption.id] = (failedOption.title, message)
        syncServerTracking()

        guard failedOption.isAutomatic else {
            advanceToNextWebOptionOrShowError()
            return
        }

        guard let playbackSlug = selectedEpisode?.id ?? route?.slug else {
            advanceToNextWebOptionOrShowError()
            return
        }

        isLoadingStream = true
        defer { isLoadingStream = false }
        do {
            let sources = try await api.fetchPlaybackSources(slug: playbackSlug)
            guard currentPlaybackAttemptID == attemptID else { return }
            let refreshedOptions = MoviePlaybackOption.options(from: sources)
            guard !refreshedOptions.isEmpty else { throw MovieAPIError.noPlaybackSource }
            playbackOptions = refreshedOptions
            syncServerTracking()

            if let nextIndex = refreshedOptions.indices.first(where: {
                refreshedOptions[$0].isAutomatic
                    && !attemptedOptionIDs.contains(refreshedOptions[$0].id)
            }) {
                streamError = nil
                beginServerAttempt(at: nextIndex)
            } else {
                advanceToNextWebOptionOrShowError()
            }
        } catch {
            guard currentPlaybackAttemptID == attemptID else { return }
            advanceToNextWebOptionOrShowError(
                finalMessage: "Playback sources could not be refreshed. \(error.localizedDescription)"
            )
        }
    }

    func isPlaybackOptionFailed(_ option: MoviePlaybackOption) -> Bool {
        guard let index = playbackOptions.firstIndex(of: option) else { return false }
        return failedServerIndices.contains(index)
    }

    private func setPlaybackOptions(from sources: [MovieStreamSource]) throws {
        let options = MoviePlaybackOption.options(from: sources)
        guard !options.isEmpty else { throw MovieAPIError.noPlaybackSource }
        playbackOptions = options
        resetOptionTracking()
        streamError = nil
        beginServerAttempt(
            at: options.firstIndex(where: \.isAutomatic) ?? options.startIndex
        )
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
        resetOptionTracking()
        beginServerAttempt(at: 0)
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
        resetServerAttempts()
        isLoadingStream = false
        streamError = nil
    }

    private func resetServerAttempts() {
        currentServerIndex = nil
        resetOptionTracking()
        currentPlaybackAttemptID = UUID()
        playbackPhase = .loading
    }

    private func beginServerAttempt(at index: Int) {
        guard playbackOptions.indices.contains(index) else { return }
        currentServerIndex = index
        currentPlaybackAttemptID = UUID()
        playbackPhase = .loading
        attemptedOptionIDs.insert(playbackOptions[index].id)
        syncServerTracking()
    }

    private func resetOptionTracking() {
        attemptedOptionIDs = []
        failureRecordsByOptionID = [:]
        syncServerTracking()
    }

    private func syncServerTracking() {
        attemptedServerIndices = Set(playbackOptions.indices.filter {
            attemptedOptionIDs.contains(playbackOptions[$0].id)
        })
        failedServerIndices = Set(playbackOptions.indices.filter {
            failureRecordsByOptionID[playbackOptions[$0].id] != nil
        })
        serverFailureMessages = Dictionary(uniqueKeysWithValues: failedServerIndices.compactMap {
            guard let record = failureRecordsByOptionID[playbackOptions[$0].id] else { return nil }
            return ($0, record.message)
        })
    }

    private func advanceToNextWebOptionOrShowError(finalMessage: String? = nil) {
        if let nextIndex = playbackOptions.indices.first(where: {
            playbackOptions[$0].kind == .web
                && !attemptedOptionIDs.contains(playbackOptions[$0].id)
        }) {
            streamError = nil
            beginServerAttempt(at: nextIndex)
            return
        }

        let details = failureRecordsByOptionID.values
            .map { "\($0.title): \($0.message)" }
            .sorted()
        streamError = ([finalMessage ?? "Every playback source failed."] + details)
            .joined(separator: "\n")
    }
}
