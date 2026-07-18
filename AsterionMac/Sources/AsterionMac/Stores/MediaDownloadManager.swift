import AVFoundation
import CryptoKit
import Foundation

@MainActor
final class MediaDownloadManager: NSObject, ObservableObject, AVAssetDownloadDelegate, @unchecked Sendable {
    @Published private(set) var downloads: [MediaDownloadRecord] = []
    @Published private(set) var storageError: String?

    private struct DownloadIndex: Codable {
        static let currentSchemaVersion = 1

        var schemaVersion = currentSchemaVersion
        var records: [MediaDownloadRecord] = []
    }

    private static let sessionIdentifier = "cloud.cyberverse.Asterion.media-downloads"
    private let animeAPI: AnimeAPI
    private let movieAPI: MovieAPI
    private let directory: URL
    private let indexURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var recordsByID: [String: MediaDownloadRecord] = [:]
    private var activeTasks: [String: AVAssetDownloadTask] = [:]
    private var pendingAssetLocations: [String: URL] = [:]
    private var progressMonitor: Task<Void, Never>?
    private var session: AVAssetDownloadURLSession!

    init(
        animeAPI: AnimeAPI = AnimeAPI(),
        movieAPI: MovieAPI = MovieAPI(),
        directory: URL? = nil
    ) {
        self.animeAPI = animeAPI
        self.movieAPI = movieAPI

        let baseDirectory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let mediaDirectory = baseDirectory
            .appendingPathComponent("Asterion", isDirectory: true)
            .appendingPathComponent("MediaDownloads", isDirectory: true)
        self.directory = mediaDirectory
        self.indexURL = mediaDirectory.appendingPathComponent("download-index", conformingTo: .json)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        super.init()

        loadIndex()

        let configuration = URLSessionConfiguration.background(
            withIdentifier: Self.sessionIdentifier
        )
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        session = AVAssetDownloadURLSession(
            configuration: configuration,
            assetDownloadDelegate: self,
            delegateQueue: nil
        )
        restoreTasks()
    }

    deinit {
        progressMonitor?.cancel()
    }

    var activeCount: Int { downloads.count(where: \.isActive) }
    var completedCount: Int { downloads.count(where: \.isAvailableOffline) }

    func record(
        mediaType: MediaAccountType,
        contentID: String,
        unitID: String
    ) -> MediaDownloadRecord? {
        recordsByID[
            MediaDownloadRecord.identifier(
                mediaType: mediaType,
                contentID: contentID,
                unitID: unitID
            )
        ]
    }

    func completedRecords(
        mediaType: MediaAccountType,
        contentID: String
    ) -> [MediaDownloadRecord] {
        downloads.filter {
            $0.mediaType == mediaType
                && $0.contentID == contentID
                && $0.isAvailableOffline
        }
    }

    func downloadAnime(show: AnimeShow, episode: AnimeEpisode) async throws {
        let id = MediaDownloadRecord.identifier(
            mediaType: .anime,
            contentID: show.slug,
            unitID: episode.id
        )
        try ensureCanStart(id: id, title: "Episode \(episode.number)")

        let record = MediaDownloadRecord(
            id: id,
            mediaType: .anime,
            contentID: show.slug,
            contentTitle: show.displayTitle,
            unitID: episode.id,
            unitTitle: "Episode \(episode.number)",
            imageURL: show.imageURL,
            animeShow: show,
            animeEpisode: episode,
            movieShow: nil,
            movieEpisode: nil,
            phase: .preparing,
            progress: 0,
            localAssetURL: nil,
            subtitleTracks: [],
            errorMessage: nil,
            updatedAt: Date()
        )
        try saveRecord(record)

        do {
            let sources = try await animeAPI.fetchStream(
                animeID: episode.animeID,
                episodeNumber: episode.number
            )
            guard let source = preferredAnimeSource(from: sources),
                  let streamURL = source.directURL else {
                throw MediaDownloadError.noDownloadableSource(title: record.unitTitle)
            }
            let tracks = try await prepareSubtitleTracks(source.tracks, downloadID: id)
            try startAssetDownload(
                recordID: id,
                streamURL: streamURL,
                title: "\(show.displayTitle) · Episode \(episode.number)",
                subtitleTracks: tracks
            )
        } catch {
            failRecord(id: id, message: error.localizedDescription)
            throw error
        }
    }

    func downloadMovie(show: MovieShow, episode: MovieEpisode?) async throws {
        let unitID = episode?.id ?? show.slug
        let unitTitle = episode.map { "S\($0.season) E\($0.number)" } ?? "Movie"
        let id = MediaDownloadRecord.identifier(
            mediaType: .movie,
            contentID: show.slug,
            unitID: unitID
        )
        try ensureCanStart(id: id, title: unitTitle)

        let storedShow = movieMetadata(from: show)
        let record = MediaDownloadRecord(
            id: id,
            mediaType: .movie,
            contentID: show.slug,
            contentTitle: show.displayTitle,
            unitID: unitID,
            unitTitle: unitTitle,
            imageURL: show.imageURL,
            animeShow: nil,
            animeEpisode: nil,
            movieShow: storedShow,
            movieEpisode: episode,
            phase: .preparing,
            progress: 0,
            localAssetURL: nil,
            subtitleTracks: [],
            errorMessage: nil,
            updatedAt: Date()
        )
        try saveRecord(record)

        do {
            let sourceShow = try await movieAPI.fetchShow(slug: unitID)
            guard let streamURL = preferredMovieStreamURL(from: sourceShow.streams) else {
                throw MediaDownloadError.noDownloadableSource(title: unitTitle)
            }
            try startAssetDownload(
                recordID: id,
                streamURL: streamURL,
                title: "\(show.displayTitle) · \(unitTitle)",
                subtitleTracks: []
            )
        } catch {
            failRecord(id: id, message: error.localizedDescription)
            throw error
        }
    }

    func retry(_ record: MediaDownloadRecord) async throws {
        try await remove(record)
        switch record.mediaType {
        case .anime:
            guard let show = record.animeShow,
                  let episode = record.animeEpisode else {
                throw MediaDownloadError.invalidStoredDownload
            }
            try await downloadAnime(show: show, episode: episode)
        case .movie:
            guard let show = record.movieShow else {
                throw MediaDownloadError.invalidStoredDownload
            }
            try await downloadMovie(show: show, episode: record.movieEpisode)
        case .football:
            throw MediaDownloadError.invalidStoredDownload
        }
    }

    func remove(_ record: MediaDownloadRecord) async throws {
        activeTasks[record.id]?.cancel()
        activeTasks.removeValue(forKey: record.id)

        if let assetURL = record.localAssetURL,
           FileManager.default.fileExists(atPath: assetURL.path) {
            try FileManager.default.removeItem(at: assetURL)
        }
        let auxiliaryDirectory = auxiliaryDirectory(downloadID: record.id)
        if FileManager.default.fileExists(atPath: auxiliaryDirectory.path) {
            try FileManager.default.removeItem(at: auxiliaryDirectory)
        }

        recordsByID.removeValue(forKey: record.id)
        pendingAssetLocations.removeValue(forKey: record.id)
        publishRecords()
        try saveIndex()
        storageError = nil
    }

    private func ensureCanStart(id: String, title: String) throws {
        if recordsByID[id]?.isActive == true {
            throw MediaDownloadError.alreadyDownloading(title: title)
        }
        if let existing = recordsByID[id] {
            if let assetURL = existing.localAssetURL,
               FileManager.default.fileExists(atPath: assetURL.path) {
                try FileManager.default.removeItem(at: assetURL)
            }
            let auxiliaryDirectory = auxiliaryDirectory(downloadID: existing.id)
            if FileManager.default.fileExists(atPath: auxiliaryDirectory.path) {
                try FileManager.default.removeItem(at: auxiliaryDirectory)
            }
            pendingAssetLocations.removeValue(forKey: id)
            recordsByID.removeValue(forKey: id)
        }
    }

    private func startAssetDownload(
        recordID: String,
        streamURL: URL,
        title: String,
        subtitleTracks: [AnimeSubtitleTrack]
    ) throws {
        let asset = AVURLAsset(url: streamURL)
        let configuration = AVAssetDownloadConfiguration(asset: asset, title: title)
        configuration.auxiliaryContentConfigurations = []
        let task = session.makeAssetDownloadTask(downloadConfiguration: configuration)
        task.taskDescription = recordID
        activeTasks[recordID] = task

        guard var record = recordsByID[recordID] else {
            task.cancel()
            throw MediaDownloadError.missingDownload
        }
        record.phase = .downloading
        record.subtitleTracks = subtitleTracks
        record.errorMessage = nil
        record.updatedAt = Date()
        try saveRecord(record)

        startProgressMonitorIfNeeded()
        task.resume()
    }

    private func preferredAnimeSource(from sources: [AnimeStreamSource]) -> AnimeStreamSource? {
        let directSources = sources.filter { $0.directURL != nil }
        return directSources.first { source in
            source.tracks.contains {
                $0.isDefault
                    || $0.languageCode?.lowercased().hasPrefix("en") == true
                    || $0.label.localizedCaseInsensitiveContains("English")
            }
        } ?? directSources.first
    }

    private func preferredMovieStreamURL(from sources: [MovieStreamSource]) -> URL? {
        let source = sources.first { $0.isHLS && $0.proxyURL != nil }
            ?? sources.first { $0.isHLS }
        return source.map { $0.proxyURL ?? $0.embedURL }
    }

    private func prepareSubtitleTracks(
        _ tracks: [AnimeSubtitleTrack],
        downloadID: String
    ) async throws -> [AnimeSubtitleTrack] {
        guard !tracks.isEmpty else { return [] }
        let selected = tracks.filter {
            $0.isDefault
                || $0.languageCode?.lowercased().hasPrefix("en") == true
                || $0.label.localizedCaseInsensitiveContains("English")
        }
        let tracksToLoad = selected.isEmpty ? Array(tracks.prefix(1)) : selected
        let loaded = try await AnimeSubtitleLoader.load(tracksToLoad)

        let directory = auxiliaryDirectory(downloadID: downloadID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try loaded.enumerated().map { index, track in
            guard track.fileURL.scheme == "data",
                  let comma = track.fileURL.absoluteString.firstIndex(of: ","),
                  let data = Data(
                    base64Encoded: String(track.fileURL.absoluteString[track.fileURL.absoluteString.index(after: comma)...])
                  ) else {
                throw AnimeSubtitleLoadError.invalidPayload(label: track.label)
            }
            let fileURL = directory.appendingPathComponent("subtitle-\(index).vtt")
            try data.write(to: fileURL, options: [.atomic])
            return AnimeSubtitleTrack(
                fileURL: fileURL,
                label: track.label,
                kind: track.kind,
                languageCode: track.languageCode,
                isDefault: track.isDefault || index == 0
            )
        }
    }

    private func movieMetadata(from show: MovieShow) -> MovieShow {
        MovieShow(
            slug: show.slug,
            title: show.title,
            type: show.type,
            imageURL: show.imageURL,
            description: show.description,
            imdbRating: show.imdbRating,
            tmdbRating: show.tmdbRating,
            rottenTomatoes: show.rottenTomatoes,
            metacritic: show.metacritic,
            genres: show.genres,
            director: show.director,
            actors: show.actors,
            duration: show.duration,
            releaseYear: show.releaseYear,
            releaseDate: show.releaseDate,
            country: show.country,
            seasons: show.seasons,
            streams: []
        )
    }

    private func restoreTasks() {
        session.getAllTasks { [weak self] tasks in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let restored = tasks.compactMap { $0 as? AVAssetDownloadTask }
                let restoredIDs = Set(restored.compactMap(\.taskDescription))
                for task in restored {
                    guard let id = task.taskDescription,
                          self.recordsByID[id] != nil else {
                        task.cancel()
                        continue
                    }
                    self.activeTasks[id] = task
                }

                for record in self.recordsByID.values
                where record.isActive && !restoredIDs.contains(record.id) {
                    self.failRecord(
                        id: record.id,
                        message: "The download stopped before macOS could preserve it. Try again."
                    )
                }
                self.startProgressMonitorIfNeeded()
            }
        }
    }

    private func startProgressMonitorIfNeeded() {
        guard progressMonitor == nil, !activeTasks.isEmpty else { return }
        progressMonitor = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.progressMonitor = nil }
            while !Task.isCancelled, !self.activeTasks.isEmpty {
                for (id, task) in self.activeTasks {
                    guard var record = self.recordsByID[id], record.phase == .downloading else {
                        continue
                    }
                    record.progress = min(max(task.progress.fractionCompleted, 0), 1)
                    record.updatedAt = Date()
                    self.setRecord(record, save: false)
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func setRecord(_ record: MediaDownloadRecord, save: Bool) {
        recordsByID[record.id] = record
        publishRecords()
        guard save else { return }
        do {
            try saveIndex()
            storageError = nil
        } catch {
            storageError = "Downloads could not be saved: \(error.localizedDescription)"
        }
    }

    private func saveRecord(_ record: MediaDownloadRecord) throws {
        recordsByID[record.id] = record
        publishRecords()
        do {
            try saveIndex()
            storageError = nil
        } catch {
            storageError = "Downloads could not be saved: \(error.localizedDescription)"
            throw error
        }
    }

    private func failRecord(id: String, message: String) {
        guard var record = recordsByID[id] else { return }
        record.phase = .failed
        record.errorMessage = message
        record.updatedAt = Date()
        activeTasks.removeValue(forKey: id)
        pendingAssetLocations.removeValue(forKey: id)
        setRecord(record, save: true)
    }

    private func completeRecord(id: String) {
        guard var record = recordsByID[id],
              let location = pendingAssetLocations[id] ?? record.localAssetURL,
              FileManager.default.fileExists(atPath: location.path) else {
            failRecord(id: id, message: "macOS finished the download without a playable offline asset.")
            return
        }
        record.phase = .completed
        record.progress = 1
        record.localAssetURL = location
        record.errorMessage = nil
        record.updatedAt = Date()
        activeTasks.removeValue(forKey: id)
        pendingAssetLocations.removeValue(forKey: id)
        setRecord(record, save: true)
    }

    private func publishRecords() {
        downloads = recordsByID.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func loadIndex() {
        do {
            guard FileManager.default.fileExists(atPath: indexURL.path) else { return }
            let index = try decoder.decode(DownloadIndex.self, from: Data(contentsOf: indexURL))
            guard index.schemaVersion == DownloadIndex.currentSchemaVersion else {
                storageError = "Downloads could not be opened because their saved format is unsupported."
                return
            }
            let validatedRecords = index.records.map { storedRecord in
                guard storedRecord.phase == .completed else { return storedRecord }
                guard let assetURL = storedRecord.localAssetURL,
                      FileManager.default.fileExists(atPath: assetURL.path) else {
                    var invalidRecord = storedRecord
                    invalidRecord.phase = .failed
                    invalidRecord.progress = 0
                    invalidRecord.localAssetURL = nil
                    invalidRecord.errorMessage = "The downloaded video is no longer on this Mac. Download it again."
                    invalidRecord.updatedAt = Date()
                    return invalidRecord
                }
                return storedRecord
            }
            recordsByID = Dictionary(uniqueKeysWithValues: validatedRecords.map { ($0.id, $0) })
            publishRecords()
            if validatedRecords != index.records {
                try saveIndex()
            }
            storageError = nil
        } catch {
            recordsByID = [:]
            downloads = []
            storageError = "Downloads could not be opened: \(error.localizedDescription)"
        }
    }

    private func saveIndex() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let index = DownloadIndex(records: Array(recordsByID.values))
        try encoder.encode(index).write(to: indexURL, options: [.atomic])
    }

    private func auxiliaryDirectory(downloadID: String) -> URL {
        let storageKey = SHA256.hash(data: Data(downloadID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory
            .appendingPathComponent("Auxiliary", isDirectory: true)
            .appendingPathComponent(storageKey, isDirectory: true)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        willDownloadTo location: URL
    ) {
        guard let id = assetDownloadTask.taskDescription else { return }
        Task { @MainActor [weak self] in
            guard let self, var record = self.recordsByID[id] else { return }
            self.pendingAssetLocations[id] = location
            record.localAssetURL = location
            record.updatedAt = Date()
            self.setRecord(record, save: true)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let id = task.taskDescription else { return }
        Task { @MainActor [weak self] in
            if let error {
                self?.failRecord(id: id, message: error.localizedDescription)
            } else {
                self?.completeRecord(id: id)
            }
        }
    }
}
