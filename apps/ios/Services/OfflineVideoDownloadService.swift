@preconcurrency import AVFoundation
import AsterionKit
import Combine
import Foundation

nonisolated struct OfflineVideoRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let relativePath: String
    let playback: MediaPlaybackDescriptor?
    let downloadedAt: Date
}

nonisolated struct OfflineVideoTransfer: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let progress: Double
}

private nonisolated struct OfflineVideoTaskMetadata: Codable, Sendable {
    let id: String
    let title: String
    let playback: MediaPlaybackDescriptor?
}

@MainActor
final class OfflineVideoDownloadService: NSObject, ObservableObject {
    @Published private(set) var records: [OfflineVideoRecord]
    @Published private(set) var transfers: [OfflineVideoTransfer] = []
    @Published private(set) var lastError: String?
    /// Request IDs saved by "Download ahead" rather than by the user.
    @Published private(set) var downloadedAheadIDs: Set<String>

    private static let recordsKey = "asterion.offline-video.records.v1"
    private static let downloadedAheadKey = "asterion.offline-video.downloaded-ahead.v1"
    private var progressByID: [String: Double] = [:]
    private var metadataByTaskID: [Int: OfflineVideoTaskMetadata] = [:]
    private var session: AVAssetDownloadURLSession!
    private var restoreTask: Task<Void, Never>?

    override init() {
        records = Self.loadRecords().map(Self.repairingPath)
        downloadedAheadIDs = Set(UserDefaults.standard.stringArray(forKey: Self.downloadedAheadKey) ?? [])
        super.init()

        let configuration = URLSessionConfiguration.background(
            withIdentifier: "cyberverse.Asterion.offline-video"
        )
        configuration.allowsCellularAccess = true
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        session = AVAssetDownloadURLSession(
            configuration: configuration,
            assetDownloadDelegate: self,
            delegateQueue: .main
        )
        removeMissingRecords()
        saveRecords()
        restoreActiveTasks()
    }

    /// Resolves once downloads still running from an earlier launch are known,
    /// so "Download ahead" doesn't queue a second copy of one in flight.
    func waitUntilRestored() async {
        await restoreTask?.value
    }

    func start(_ request: PlaybackRequest) {
        start(request, automatic: false)
    }

    /// `automatic` downloads come from "Download ahead": they fail quietly and may be pruned once watched.
    func start(_ request: PlaybackRequest, automatic: Bool) {
        if !automatic, downloadedAheadIDs.contains(request.id) {
            // The user asked for it themselves, so it is theirs to keep.
            setDownloadedAhead(request.id, false)
        }
        guard let directURL = request.directURL else {
            if !automatic {
                lastError = "This stream does not expose a downloadable video source."
            }
            return
        }
        guard localURL(forRequestID: request.id) == nil,
              !progressByID.keys.contains(request.id) else { return }

        let metadata = OfflineVideoTaskMetadata(
            id: request.id,
            title: request.title,
            playback: request.playback
        )
        let asset = AVURLAsset(
            url: directURL,
            options: request.requestHeaders.isEmpty
                ? nil
                : ["AVURLAssetHTTPHeaderFieldsKey": request.requestHeaders]
        )
        guard let task = session.makeAssetDownloadTask(
            asset: asset,
            assetTitle: request.title,
            assetArtworkData: nil,
            options: nil
        ) else {
            if !automatic {
                lastError = "The video download could not be prepared."
            }
            return
        }
        if automatic {
            setDownloadedAhead(request.id, true)
        }
        if let data = try? JSONEncoder().encode(metadata) {
            task.taskDescription = data.base64EncodedString()
        }
        metadataByTaskID[task.taskIdentifier] = metadata
        progressByID[request.id] = 0
        rebuildTransfers()
        lastError = nil
        task.resume()
    }

    func cancel(requestID: String) {
        session.getAllTasks { tasks in
            for task in tasks where Self.metadata(from: task)?.id == requestID {
                task.cancel()
            }
        }
        progressByID.removeValue(forKey: requestID)
        setDownloadedAhead(requestID, false)
        rebuildTransfers()
    }

    func remove(_ record: OfflineVideoRecord) {
        if let url = localURL(for: record) {
            try? FileManager.default.removeItem(at: url)
        }
        records.removeAll { $0.id == record.id }
        setDownloadedAhead(record.id, false)
        saveRecords()
    }

    func isDownloadedAhead(id: String) -> Bool {
        downloadedAheadIDs.contains(id)
    }

    /// True while a transfer for this request is running.
    func isTransferring(id: String) -> Bool {
        progressByID.keys.contains(id)
    }

    /// Deletes "Download ahead" episodes the viewer has since finished.
    /// Removes "Download ahead" episodes the viewer has moved past. The
    /// account keeps only the latest episode per title, so compare episode
    /// numbers rather than looking for each episode's own record.
    func pruneWatchedDownloadsAhead(progress: [MediaPlaybackProgress]) {
        let latestByTitle = Dictionary(
            progress.map { ("\($0.mediaType.rawValue):\($0.contentId)", $0) },
            uniquingKeysWith: { $0.updatedAt >= $1.updatedAt ? $0 : $1 }
        )
        for record in records where downloadedAheadIDs.contains(record.id) {
            guard let playback = record.playback,
                  let latest = latestByTitle["\(playback.item.mediaType.rawValue):\(playback.item.contentID)"]
            else { continue }
            if DownloadAheadPolicy.isWatchedPast(playback, latest: latest) {
                remove(record)
            }
        }
    }

    private func setDownloadedAhead(_ id: String, _ isAhead: Bool) {
        let changed = isAhead ? downloadedAheadIDs.insert(id).inserted : downloadedAheadIDs.remove(id) != nil
        guard changed else { return }
        UserDefaults.standard.set(Array(downloadedAheadIDs), forKey: Self.downloadedAheadKey)
    }

    func localURL(for request: PlaybackRequest) -> URL? {
        localURL(forRequestID: request.id)
    }

    func isDownloaded(_ request: PlaybackRequest) -> Bool {
        isDownloaded(id: request.id)
    }

    func isDownloaded(id: String) -> Bool {
        localURL(forRequestID: id) != nil
    }

    func progress(for request: PlaybackRequest) -> Double? {
        progress(forID: request.id)
    }

    func progress(forID id: String) -> Double? {
        progressByID[id]
    }

    func playbackRequest(for record: OfflineVideoRecord) -> PlaybackRequest? {
        guard let url = localURL(for: record) else { return nil }
        return PlaybackRequest(
            id: record.id,
            title: record.title,
            directURL: url,
            embedURL: nil,
            requestHeaders: [:],
            playback: record.playback
        )
    }

    private func restoreActiveTasks() {
        restoreTask = Task { [weak self] in
            guard let session = self?.session else { return }
            let tasks = await session.allTasks
            guard let self else { return }
            for task in tasks where task.state == .running || task.state == .suspended {
                guard let metadata = Self.metadata(from: task) else { continue }
                metadataByTaskID[task.taskIdentifier] = metadata
                progressByID[metadata.id] = max(0, min(1, task.progress.fractionCompleted))
            }
            rebuildTransfers()
            if metadataByTaskID.isEmpty {
                removeOrphanedPackages()
            }
        }
    }

    /// Deletes downloaded packages no record points to: copies left behind
    /// when a record's path could not be resolved, and partial packages from
    /// failed downloads. Only runs when nothing is downloading, and only for
    /// packages untouched for an hour.
    private func removeOrphanedPackages() {
        let fileManager = FileManager.default
        let library = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
        let kept = Set(records.compactMap { localURL(for: $0)?.standardizedFileURL.path })
        let folders = (try? fileManager.contentsOfDirectory(at: library, includingPropertiesForKeys: nil)) ?? []
        for folder in folders where folder.lastPathComponent.hasPrefix("com.apple.UserManagedAssets") {
            let packages = (try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )) ?? []
            for package in packages where package.pathExtension == "movpkg"
                && !kept.contains(package.standardizedFileURL.path) {
                // A download that finished while the app was closed reports
                // its package after launch; leave anything recent alone.
                let modified = (try? package.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                guard modified < Date().addingTimeInterval(-3600) else { continue }
                try? fileManager.removeItem(at: package)
            }
        }
    }

    private func finish(task: AVAssetDownloadTask, location: URL) {
        guard let metadata = metadataByTaskID[task.taskIdentifier] ?? Self.metadata(from: task) else {
            return
        }
        records.removeAll { $0.id == metadata.id }
        records.insert(
            OfflineVideoRecord(
                id: metadata.id,
                title: metadata.title,
                relativePath: Self.storedRelativePath(for: location),
                playback: metadata.playback,
                downloadedAt: Date()
            ),
            at: 0
        )
        progressByID.removeValue(forKey: metadata.id)
        metadataByTaskID.removeValue(forKey: task.taskIdentifier)
        saveRecords()
        rebuildTransfers()
        lastError = nil
    }

    private func fail(task: URLSessionTask, error: Error) {
        guard let metadata = metadataByTaskID[task.taskIdentifier] ?? Self.metadata(from: task) else {
            return
        }
        progressByID.removeValue(forKey: metadata.id)
        metadataByTaskID.removeValue(forKey: task.taskIdentifier)
        rebuildTransfers()
        let wasAhead = downloadedAheadIDs.contains(metadata.id)
        // The system reports the package location before it reports the
        // error, so a failed download had already been recorded with a
        // partial package. Drop both, or it would pass as downloaded.
        if let partial = records.first(where: { $0.id == metadata.id }),
           partial.downloadedAt > Date().addingTimeInterval(-60) {
            remove(partial)
        }
        setDownloadedAhead(metadata.id, false)
        if (error as NSError).code != NSURLErrorCancelled, !wasAhead {
            lastError = error.localizedDescription
        }
    }

    private func update(task: AVAssetDownloadTask, loadedSeconds: Double, expectedSeconds: Double) {
        guard let metadata = metadataByTaskID[task.taskIdentifier] ?? Self.metadata(from: task) else {
            return
        }
        guard expectedSeconds.isFinite, expectedSeconds > 0 else { return }
        progressByID[metadata.id] = min(1, max(0, loadedSeconds / expectedSeconds))
        metadataByTaskID[task.taskIdentifier] = metadata
        rebuildTransfers()
    }

    private func rebuildTransfers() {
        transfers = metadataByTaskID.values
            .reduce(into: [String: OfflineVideoTaskMetadata]()) { result, metadata in
                result[metadata.id] = metadata
            }
            .values
            .map {
                OfflineVideoTransfer(
                    id: $0.id,
                    title: $0.title,
                    progress: progressByID[$0.id] ?? 0
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func localURL(forRequestID id: String) -> URL? {
        guard let record = records.first(where: { $0.id == id }) else { return nil }
        return localURL(for: record)
    }

    private func localURL(for record: OfflineVideoRecord) -> URL? {
        Self.existingURL(forRelativePath: OfflineVideoPaths.containerRelativePath(record.relativePath))
    }

    /// Records saved by earlier builds hold percent-encoded paths
    /// ("Clevatess%20%C2%B7%20Episode…"); try the path as stored and decoded.
    private static func existingURL(forRelativePath relative: String) -> URL? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        var candidates = [relative]
        if let decoded = relative.removingPercentEncoding, decoded != relative {
            candidates.append(decoded)
        }
        for candidate in candidates {
            let url = home.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private func removeMissingRecords() {
        let existing = records.filter { localURL(for: $0) != nil }
        guard existing.count != records.count else { return }
        records = existing
        saveRecords()
    }

    private func saveRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Self.recordsKey)
    }

    private static func loadRecords() -> [OfflineVideoRecord] {
        guard let data = UserDefaults.standard.data(forKey: recordsKey),
              let records = try? JSONDecoder().decode([OfflineVideoRecord].self, from: data) else {
            return []
        }
        return records
    }

    /// The container-relative path of a finished package, in whichever
    /// spelling (decoded or percent-encoded) actually exists on disk.
    private static func storedRelativePath(for location: URL) -> String {
        let decoded = OfflineVideoPaths.containerRelativePath(location.path(percentEncoded: false))
        if existingURL(forRelativePath: decoded) != nil { return decoded }
        return OfflineVideoPaths.containerRelativePath(location.path(percentEncoded: true))
    }

    private static func repairingPath(_ record: OfflineVideoRecord) -> OfflineVideoRecord {
        let relative = OfflineVideoPaths.containerRelativePath(record.relativePath)
        guard relative != record.relativePath else { return record }
        return OfflineVideoRecord(
            id: record.id,
            title: record.title,
            relativePath: relative,
            playback: record.playback,
            downloadedAt: record.downloadedAt
        )
    }

    private nonisolated static func metadata(from task: URLSessionTask) -> OfflineVideoTaskMetadata? {
        guard let encoded = task.taskDescription,
              let data = Data(base64Encoded: encoded) else { return nil }
        return try? JSONDecoder().decode(OfflineVideoTaskMetadata.self, from: data)
    }
}

extension OfflineVideoDownloadService: AVAssetDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        Task { @MainActor in
            finish(task: assetDownloadTask, location: location)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad: CMTimeRange
    ) {
        let expectedSeconds = timeRangeExpectedToLoad.duration.seconds
        let loadedSeconds = loadedTimeRanges.reduce(0.0) { total, value in
            let duration = value.timeRangeValue.duration.seconds
            return total + (duration.isFinite ? duration : 0)
        }
        Task { @MainActor in
            update(
                task: assetDownloadTask,
                loadedSeconds: loadedSeconds,
                expectedSeconds: expectedSeconds
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        Task { @MainActor in
            fail(task: task, error: error)
        }
    }
}
