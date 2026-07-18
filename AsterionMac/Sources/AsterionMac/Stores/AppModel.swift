import ClerkKit
import Foundation

private struct MediaOutboxRejectedError: LocalizedError {
    let messages: [String]

    var errorDescription: String? {
        messages.joined(separator: " ")
    }
}

@MainActor
final class AppModel: ObservableObject {
    private static let offlineDownloadConcurrency = 6
    private static let deviceProgressOwnerID = "device"

    private enum AccountErrorSource: CaseIterable {
        case authentication
        case localProgress
        case progressSync
        case profileSync
        case librarySync
        case progressSave
        case libraryMutation
        case mediaSync
        case localMediaActivity
        case rejectedMediaActivity
        case mediaBookmarkMutation
        case mediaProgressSave
        case signOut
    }

    struct ContinueReadingEntry: Identifiable {
        let novel: Novel
        let progress: ReadingProgress

        var id: String { novel.id }
    }

    struct SignedInUser: Equatable {
        let id: String
        let name: String
        let email: String?
        let imageURL: URL?
    }

    @Published private(set) var novels: [Novel] = []
    @Published private(set) var libraryNovelIDs: Set<String> = []
    @Published private(set) var progressByNovelID: [String: ReadingProgress] = [:]
    @Published private(set) var downloadedNovelIDs: Set<String> = []
    @Published private(set) var signedInUser: SignedInUser?
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var isUpdatingLibrary = false
    @Published private(set) var offlineDownloadByNovelID: [String: OfflineDownload] = [:]
    @Published private(set) var catalogState: CatalogLoadState = .idle
    @Published private(set) var chapterListStateByNovelID: [String: ChapterListLoadState] = [:]
    @Published private(set) var catalogError: String?
    @Published private(set) var accountError: String?
    @Published private(set) var mediaBookmarksByKey: [MediaAccountKey: MediaBookmark] = [:]
    @Published private(set) var mediaProgressByKey: [MediaAccountKey: MediaPlaybackProgress] = [:]
    @Published private(set) var mediaHistory: [MediaHistoryEntry] = []
    @Published private(set) var mediaStats = MediaAccountStats.empty
    @Published private(set) var updatingMediaBookmarkKeys: Set<MediaAccountKey> = []
    @Published private(set) var mediaBookmarkError: String?

    let api = APIClient()
    private let offlineLibrary = OfflineLibraryStore()
    private let readingProgressStore = ReadingProgressStore()
    private let mediaActivityStore = MediaActivityStore()
    private let networkStatus = NetworkStatusMonitor()
    private lazy var progressUploadQueue = ReadingProgressUploadQueue(api: api)
    private lazy var mediaProgressUploadQueue = MediaProgressUploadQueue(api: api)

    private var chapterByID: [String: Chapter] = [:]
    private var remoteNovelIDs: Set<String> = []
    private var progressSaveGenerationByKey: [String: UInt] = [:]
    private var accountErrors: [AccountErrorSource: String] = [:]
    private var hasStarted = false
    private var isSynchronizingSession = false
    private var shouldResynchronizeSession = false
    private var authEventsTask: Task<Void, Never>?
    private var networkEventsTask: Task<Void, Never>?
    private var mediaOutboxTask: Task<Void, Never>?
    private var startedMediaSessionIDs: Set<String> = []
    private var mediaHydratedOwnerID: String?
    private var mediaHydrationWaiters: [CheckedContinuation<Void, Never>] = []

    deinit {
        authEventsTask?.cancel()
        networkEventsTask?.cancel()
        mediaOutboxTask?.cancel()
        networkStatus.cancel()
    }

    var isSignedIn: Bool { signedInUser != nil }

    var mediaBookmarks: [MediaBookmark] {
        mediaBookmarksByKey.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    var continueWatching: [MediaPlaybackProgress] {
        mediaProgressByKey.values
            .filter { !$0.completed }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var offlineDownloads: [OfflineDownload] {
        offlineDownloadByNovelID.values.sorted { lhs, rhs in
            if lhs.isDownloading != rhs.isDownloading {
                return lhs.isDownloading
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    var featuredNovels: [Novel] {
        Array(
            novels
                .sorted {
                    if $0.numericRank == $1.numericRank {
                        return ($0.rating ?? 0) > ($1.rating ?? 0)
                    }
                    return $0.numericRank < $1.numericRank
                }
                .prefix(4)
        )
    }

    var trendingNovels: [Novel] {
        Array(
            novels
                .sorted {
                    if ($0.rating ?? 0) == ($1.rating ?? 0) {
                        return $0.numericRank < $1.numericRank
                    }
                    return ($0.rating ?? 0) > ($1.rating ?? 0)
                }
                .prefix(8)
        )
    }

    var continueReadingEntries: [ContinueReadingEntry] {
        progressByNovelID.values
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            .compactMap { progress in
                novel(id: progress.novelId).map {
                    ContinueReadingEntry(novel: $0, progress: progress)
                }
            }
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        await loadOfflineLibrary()
        async let catalog: Void = loadCatalog()
        async let session: Void = restoreSession()
        _ = await (catalog, session)

        authEventsTask = Task { @MainActor [weak self] in
            for await _ in Clerk.shared.auth.events {
                guard let self else { return }
                await self.synchronizeSession()
            }
        }

        let networkUpdates = networkStatus.updates()
        networkEventsTask = Task { @MainActor [weak self] in
            var receivedInitialStatus = false
            for await isOnline in networkUpdates {
                if !receivedInitialStatus {
                    receivedInitialStatus = true
                    continue
                }
                guard isOnline, let self else { continue }
                await self.synchronizeSession()
            }
        }
    }

    func loadCatalog() async {
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        do {
            let remoteNovels = try await api.fetchAllNovels()
            remoteNovelIDs = Set(remoteNovels.map(\.id))
            do {
                let offlineNovels = try await offlineLibrary.downloadedNovels()
                novels = mergedNovels(primary: remoteNovels, secondary: offlineNovels)
                catalogState = .remote
                catalogError = nil
            } catch let offlineError {
                novels = remoteNovels
                catalogState = .remoteWithOfflineError(offlineError.localizedDescription)
                catalogError = catalogState.notice
            }
        } catch let remoteError {
            do {
                let offlineNovels = try await offlineLibrary.downloadedNovels()
                novels = offlineNovels
                remoteNovelIDs = []
                if offlineNovels.isEmpty {
                    let message = "The catalog could not be loaded. \(remoteError.localizedDescription)"
                    catalogState = .failed(message)
                    catalogError = message
                } else {
                    catalogState = .offline(remoteError: remoteError.localizedDescription)
                    catalogError = catalogState.notice
                }
            } catch let offlineError {
                let message = "The catalog and offline library could not be loaded. Catalog: \(remoteError.localizedDescription) Offline library: \(offlineError.localizedDescription)"
                catalogState = .failed(message)
                catalogError = message
            }
        }
    }

    func novels(for section: AppSection, search: String) -> [Novel] {
        let source: [Novel]
        switch section {
        case .discover:
            source = novels.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .rankings:
            source = novels.sorted {
                if $0.numericRank == $1.numericRank {
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                return $0.numericRank < $1.numericRank
            }
        case .library:
            source = novels.filter { libraryNovelIDs.contains($0.id) || downloadedNovelIDs.contains($0.id) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .account:
            source = []
        }

        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return source }
        return source.filter { novel in
            novel.title.localizedCaseInsensitiveContains(query)
                || novel.authorDisplayName.localizedCaseInsensitiveContains(query)
                || novel.genres?.contains(where: { $0.localizedCaseInsensitiveContains(query) }) == true
        }
    }

    func novel(id: String) -> Novel? {
        novels.first { $0.id == id }
    }

    func chapters(for novelID: String) async throws -> [Chapter] {
        do {
            let chapters = try await api.fetchAllChapters(novelID: novelID)
            cacheChapterContent(chapters)
            chapterListStateByNovelID[novelID] = .remote
            return chapters
        } catch let remoteError {
            do {
                if let offlineChapters = try await offlineLibrary.chapters(for: novelID) {
                    cacheChapterContent(offlineChapters)
                    chapterListStateByNovelID[novelID] = .offline(
                        remoteError: remoteError.localizedDescription
                    )
                    return offlineChapters
                }
            } catch let offlineError {
                let message = "The latest chapters and downloaded copy could not be loaded. Latest chapters: \(remoteError.localizedDescription) Downloaded copy: \(offlineError.localizedDescription)"
                chapterListStateByNovelID[novelID] = .failed(message)
                throw ChapterListLoadError.unavailable(message)
            }
            chapterListStateByNovelID[novelID] = .failed(remoteError.localizedDescription)
            throw remoteError
        }
    }

    func chapterListState(for novelID: String) -> ChapterListLoadState {
        chapterListStateByNovelID[novelID] ?? .idle
    }

    func chapter(id: String) async throws -> Chapter {
        if let cached = chapterByID[id], cached.content?.isEmpty == false {
            return cached
        }

        if let offlineChapter = try await offlineLibrary.chapter(id: id) {
            chapterByID[id] = offlineChapter
            return offlineChapter
        }

        let chapter = try await api.fetchChapter(id: id)
        chapterByID[id] = chapter
        return chapter
    }

    func downloadForOffline(novel: Novel) async throws {
        guard offlineDownloadByNovelID[novel.id]?.isDownloading != true else {
            throw OfflineDownloadError.alreadyInProgress(novelTitle: novel.title)
        }

        offlineDownloadByNovelID[novel.id] = OfflineDownload(
            novelID: novel.id,
            novelTitle: novel.title,
            completedChapters: 0,
            totalChapters: 0,
            phase: .downloading,
            errorMessage: nil,
            updatedAt: Date()
        )

        do {
            let chapterSummaries = try await api.fetchAllChapters(novelID: novel.id)
            updateOfflineDownload(novelID: novel.id) { download in
                download.totalChapters = chapterSummaries.count
            }

            let fullChapters = try await fetchChaptersForOfflineDownload(
                chapterSummaries,
                novelID: novel.id
            )

            let sortedChapters = fullChapters.sorted { $0.chapterNumber < $1.chapterNumber }
            try await offlineLibrary.save(novel: novel, chapters: sortedChapters)
            downloadedNovelIDs.insert(novel.id)
            for chapter in sortedChapters {
                chapterByID[chapter.id] = chapter
            }
            novels = mergedNovels(primary: novels, secondary: [novel])
            updateOfflineDownload(novelID: novel.id) { download in
                download.phase = .completed
                download.completedChapters = download.totalChapters
                download.errorMessage = nil
            }
        } catch {
            updateOfflineDownload(novelID: novel.id) { download in
                download.phase = .failed
                download.errorMessage = error.localizedDescription
            }
            throw error
        }
    }

    func offlineDownload(for novelID: String) -> OfflineDownload? {
        offlineDownloadByNovelID[novelID]
    }

    func removeOfflineDownload(novelID: String) async throws {
        guard offlineDownloadByNovelID[novelID]?.isDownloading != true else {
            throw OfflineDownloadError.alreadyInProgress(
                novelTitle: offlineDownloadByNovelID[novelID]?.novelTitle ?? "This novel"
            )
        }

        let offlineChapterIDs = try await offlineLibrary.chapterIDs(for: novelID) ?? []
        try await offlineLibrary.remove(novelID: novelID)

        downloadedNovelIDs.remove(novelID)
        offlineDownloadByNovelID.removeValue(forKey: novelID)
        for chapterID in offlineChapterIDs {
            chapterByID.removeValue(forKey: chapterID)
        }
        if !remoteNovelIDs.contains(novelID) {
            novels.removeAll { $0.id == novelID }
        }
        chapterListStateByNovelID[novelID] = .idle
    }

    private func fetchChaptersForOfflineDownload(
        _ summaries: [Chapter],
        novelID: String
    ) async throws -> [Chapter] {
        let api = api
        let workerCount = min(Self.offlineDownloadConcurrency, summaries.count)
        var iterator = summaries.makeIterator()
        var completed: [Chapter] = []
        completed.reserveCapacity(summaries.count)

        return try await withThrowingTaskGroup(of: Chapter.self) { group in
            for _ in 0..<workerCount {
                guard let summary = iterator.next() else { break }
                group.addTask {
                    if summary.content?.isEmpty == false { return summary }
                    return try await api.fetchChapter(id: summary.id)
                }
            }

            while let chapter = try await group.next() {
                completed.append(chapter)
                updateOfflineDownload(novelID: novelID) { download in
                    download.completedChapters = completed.count
                }

                if let summary = iterator.next() {
                    group.addTask {
                        if summary.content?.isEmpty == false { return summary }
                        return try await api.fetchChapter(id: summary.id)
                    }
                }
            }

            return completed
        }
    }

    func toggleLibrary(novelID: String) async {
        guard isSignedIn else {
            setAccountError(
                .libraryMutation,
                "Sign in to save novels to your library."
            )
            return
        }

        isUpdatingLibrary = true
        defer { isUpdatingLibrary = false }
        do {
            if libraryNovelIDs.contains(novelID) {
                try await api.removeFromLibrary(novelID: novelID)
                libraryNovelIDs.remove(novelID)
            } else {
                _ = try await api.addToLibrary(novelID: novelID)
                libraryNovelIDs.insert(novelID)
            }
            setAccountError(.libraryMutation, nil)
        } catch {
            setAccountError(.libraryMutation, error.localizedDescription)
        }
    }

    func isMediaBookmarked(_ key: MediaAccountKey) -> Bool {
        mediaBookmarksByKey[key] != nil
    }

    func isUpdatingMediaBookmark(_ key: MediaAccountKey) -> Bool {
        updatingMediaBookmarkKeys.contains(key)
    }

    func toggleMediaBookmark(_ item: MediaItemDescriptor) async {
        guard let ownerID = signedInUser?.id else {
            let message = "Sign in to save \(item.mediaType.title.lowercased()) to your account."
            mediaBookmarkError = message
            setAccountError(.mediaBookmarkMutation, message)
            return
        }
        guard updatingMediaBookmarkKeys.insert(item.key).inserted else { return }
        defer { updatingMediaBookmarkKeys.remove(item.key) }

        let mutation: LocalMediaBookmarkMutation
        do {
            mutation = try await mediaActivityStore.recordBookmark(
                ownerID: ownerID,
                item: item,
                isSaved: mediaBookmarksByKey[item.key] == nil,
                clientEventAt: Date()
            )
            try await loadLocalMediaActivity(ownerID: ownerID)
            setAccountError(.localMediaActivity, nil)
        } catch {
            let message = "The bookmark could not be saved on this Mac: \(error.localizedDescription)"
            mediaBookmarkError = message
            setAccountError(.localMediaActivity, message)
            return
        }

        do {
            try await uploadMediaBookmarkMutation(mutation)
            guard signedInUser?.id == ownerID else { return }
            try await loadLocalMediaActivity(ownerID: ownerID)
            mediaBookmarkError = nil
            setAccountError(.mediaBookmarkMutation, nil)
        } catch {
            if isPermanentMediaSyncError(error) {
                let recordedRejection = (try? await mediaActivityStore.rejectBookmarkMutation(
                    ownerID: ownerID,
                    mutation: mutation,
                    message: error.localizedDescription,
                    rejectedAt: Date()
                )) ?? false
                try? await loadLocalMediaActivity(ownerID: ownerID)
                if recordedRejection {
                    let message = "\(item.title) could not sync: \(error.localizedDescription)"
                    mediaBookmarkError = message
                    setAccountError(.mediaBookmarkMutation, message)
                } else {
                    mediaBookmarkError = nil
                    setAccountError(.mediaBookmarkMutation, nil)
                }
                return
            }
            let message = "The bookmark is saved on this Mac and will sync automatically: \(error.localizedDescription)"
            mediaBookmarkError = message
            setAccountError(.mediaBookmarkMutation, message)
            scheduleMediaOutboxFlush(ownerID: ownerID)
        }
    }

    func resumePosition(for playback: MediaPlaybackDescriptor) -> Double {
        guard let progress = mediaProgressByKey[playback.item.key],
              progress.unitId == playback.unitID,
              !progress.completed else { return 0 }
        return max(0, progress.positionSeconds)
    }

    func preparedResumePosition(for playback: MediaPlaybackDescriptor) async -> Double {
        guard let ownerID = signedInUser?.id else { return 0 }
        await waitForMediaHydration(ownerID: ownerID)
        guard signedInUser?.id == ownerID else { return 0 }
        return resumePosition(for: playback)
    }

    func recordMediaPlaybackSample(
        _ playback: MediaPlaybackDescriptor,
        sample: MediaPlaybackSample,
        sessionID: String
    ) async {
        guard sample.positionSeconds.isFinite,
              sample.durationSeconds.isFinite,
              sample.positionSeconds > 0 else { return }
        guard let ownerID = signedInUser?.id else { return }
        await waitForMediaHydration(ownerID: ownerID)
        guard signedInUser?.id == ownerID else { return }
        let started = !startedMediaSessionIDs.contains(sessionID)
        await saveMediaPlayback(
            playback,
            positionSeconds: sample.positionSeconds,
            durationSeconds: sample.durationSeconds,
            completed: sample.completed,
            started: started,
            sessionID: sessionID,
            clientEventAt: sample.observedAt
        )
    }

    private func saveMediaPlayback(
        _ playback: MediaPlaybackDescriptor,
        positionSeconds: Double,
        durationSeconds: Double,
        completed: Bool? = nil,
        started: Bool = false,
        sessionID: String,
        clientEventAt: Date
    ) async {
        guard let ownerID = signedInUser?.id else { return }
        let event: LocalMediaPlaybackEvent
        do {
            event = try await mediaActivityStore.record(
                ownerID: ownerID,
                playback: playback,
                positionSeconds: positionSeconds,
                durationSeconds: durationSeconds,
                completed: completed,
                started: started,
                sessionID: sessionID,
                clientEventAt: clientEventAt
            )
            try await loadLocalMediaActivity(ownerID: ownerID)
            if started { startedMediaSessionIDs.insert(sessionID) }
            setAccountError(.localMediaActivity, nil)
        } catch {
            setAccountError(
                .localMediaActivity,
                "Watch progress could not be saved on this Mac: \(error.localizedDescription)"
            )
            return
        }

        do {
            let result = try await mediaProgressUploadQueue.submit(
                MediaProgressUploadQueue.Request(
                    ownerID: ownerID,
                    playback: event.playback,
                    positionSeconds: event.positionSeconds,
                    durationSeconds: event.durationSeconds,
                    completed: event.completed,
                    started: event.started,
                    sessionID: event.sessionID,
                    clientEventAt: event.clientEventAt
                )
            )
            guard signedInUser?.id == ownerID else { return }
            try await mediaActivityStore.acknowledge(ownerID: ownerID, eventID: event.id)
            try await mediaActivityStore.mergeRemote(
                ownerID: ownerID,
                progress: result.progress.map { [$0] } ?? [],
                history: result.history.map { [$0] } ?? [],
                stats: nil
            )
            try await loadLocalMediaActivity(ownerID: ownerID)
            setAccountError(.mediaProgressSave, nil)
        } catch MediaProgressUploadQueueError.superseded {
            return
        } catch is CancellationError {
            return
        } catch {
            if isPermanentMediaSyncError(error) {
                let recordedRejection = (try? await mediaActivityStore.rejectPlaybackEvent(
                    ownerID: ownerID,
                    event: event,
                    message: error.localizedDescription,
                    rejectedAt: Date()
                )) ?? false
                try? await loadLocalMediaActivity(ownerID: ownerID)
                if recordedRejection {
                    setAccountError(
                        .mediaProgressSave,
                        "\(playback.item.title) could not sync: \(error.localizedDescription)"
                    )
                } else {
                    setAccountError(.mediaProgressSave, nil)
                }
                return
            }
            setAccountError(
                .mediaProgressSave,
                "Watch progress is saved on this Mac and will sync automatically: \(error.localizedDescription)"
            )
            scheduleMediaOutboxFlush(ownerID: ownerID)
        }
    }

    func fetchProgress(novelID: String) async throws -> ReadingProgress? {
        let ownerID = progressOwnerID
        if let local = try await readingProgressStore.progress(ownerID: ownerID, novelID: novelID) {
            return local.readingProgress
        }
        guard isSignedIn else { return nil }

        do {
            guard let server = try await api.fetchProgress(novelID: novelID) else { return nil }
            try await readingProgressStore.save(.synced(ownerID: ownerID, server: server))
            progressByNovelID[novelID] = server
            setAccountError(.progressSave, nil)
            return server
        } catch {
            setAccountError(
                .progressSave,
                "Progress is unavailable until the connection returns: \(error.localizedDescription)"
            )
            return nil
        }
    }

    func saveProgress(novelID: String, chapterID: String, currentLine: Int, totalLines: Int) async {
        let ownerID = progressOwnerID
        let saveKey = progressSaveKey(ownerID: ownerID, novelID: novelID)
        let generation = (progressSaveGenerationByKey[saveKey] ?? 0) &+ 1
        progressSaveGenerationByKey[saveKey] = generation
        let pending = LocalReadingProgress.pending(
            ownerID: ownerID,
            novelID: novelID,
            chapterID: chapterID,
            currentLine: currentLine,
            totalLines: totalLines
        )

        do {
            try await readingProgressStore.save(pending)
            guard progressSaveGenerationByKey[saveKey] == generation else { return }
            progressByNovelID[novelID] = pending.readingProgress
        } catch {
            setAccountError(
                .progressSave,
                "Reading progress could not be saved locally: \(error.localizedDescription)"
            )
            return
        }

        guard signedInUser?.id == ownerID else { return }

        do {
            let saved = try await progressUploadQueue.submit(
                ReadingProgressUploadQueue.Request(
                    ownerID: ownerID,
                    novelID: novelID,
                    chapterID: chapterID,
                    currentLine: currentLine,
                    totalLines: totalLines
                )
            )
            let current = try await readingProgressStore.progress(ownerID: ownerID, novelID: novelID)
            guard current?.revision == pending.revision else { return }
            try await readingProgressStore.save(.synced(ownerID: ownerID, server: saved))
            if progressOwnerID == ownerID {
                progressByNovelID[novelID] = saved
            }
            setAccountError(.progressSave, nil)
        } catch ReadingProgressUploadQueueError.superseded {
            return
        } catch is CancellationError {
            return
        } catch {
            setAccountError(
                .progressSave,
                "Progress is saved offline and will sync automatically: \(error.localizedDescription)"
            )
        }
    }

    func signOut() async {
        do {
            try await Clerk.shared.auth.signOut()
            await synchronizeSession()
            setAccountError(.signOut, nil)
        } catch {
            setAccountError(.signOut, error.localizedDescription)
        }
    }

    private func restoreSession() async {
        var refreshError: Error?
        if Clerk.shared.user == nil {
            do {
                try await Clerk.shared.refreshClient()
            } catch {
                refreshError = error
            }
        }
        await synchronizeSession()
        if let refreshError {
            setAccountError(
                .authentication,
                "The saved account session could not be restored: \(refreshError.localizedDescription)"
            )
        }
    }

    private func synchronizeSession() async {
        guard !isSynchronizingSession else {
            shouldResynchronizeSession = true
            return
        }
        isSynchronizingSession = true
        defer {
            isSynchronizingSession = false
            if shouldResynchronizeSession {
                shouldResynchronizeSession = false
                Task { @MainActor [weak self] in
                    await self?.synchronizeSession()
                }
            }
        }

        guard let clerkUser = Clerk.shared.user else {
            await progressUploadQueue.cancelAll()
            await mediaProgressUploadQueue.cancelAll()
            mediaOutboxTask?.cancel()
            mediaOutboxTask = nil
            startedMediaSessionIDs = []
            finishMediaHydration(ownerID: nil)
            signedInUser = nil
            libraryNovelIDs = []
            mediaBookmarksByKey = [:]
            mediaProgressByKey = [:]
            mediaHistory = []
            mediaStats = .empty
            updatingMediaBookmarkKeys = []
            mediaBookmarkError = nil
            await api.setToken(nil)
            clearRemoteAccountErrors()
            do {
                try await loadLocalProgress(ownerID: Self.deviceProgressOwnerID)
                setAccountError(.localProgress, nil)
            } catch {
                progressByNovelID = [:]
                setAccountError(
                    .localProgress,
                    "Local reading progress could not be loaded: \(error.localizedDescription)"
                )
            }
            return
        }

        let email = clerkUser.emailAddresses.first?.emailAddress
        let fullName = [clerkUser.firstName, clerkUser.lastName]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = fullName.isEmpty ? (email ?? "Asterion Reader") : fullName
        let changesOwner = signedInUser?.id != clerkUser.id
        await progressUploadQueue.cancelAll(exceptOwnerID: clerkUser.id)
        await mediaProgressUploadQueue.cancelAll(exceptOwnerID: clerkUser.id)
        if changesOwner {
            mediaOutboxTask?.cancel()
            mediaOutboxTask = nil
            startedMediaSessionIDs = []
            finishMediaHydration(ownerID: nil)
            mediaBookmarksByKey = [:]
            mediaProgressByKey = [:]
            mediaHistory = []
            mediaStats = .empty
            updatingMediaBookmarkKeys = []
            mediaBookmarkError = nil
        }
        signedInUser = SignedInUser(
            id: clerkUser.id,
            name: name,
            email: email,
            imageURL: URL(string: clerkUser.imageUrl)
        )

        do {
            try await loadLocalProgress(ownerID: clerkUser.id)
            setAccountError(.localProgress, nil)
        } catch {
            setAccountError(
                .localProgress,
                "Local reading progress could not be loaded: \(error.localizedDescription)"
            )
        }

        do {
            try await loadLocalMediaActivity(ownerID: clerkUser.id)
            setAccountError(.localMediaActivity, nil)
        } catch {
            setAccountError(
                .localMediaActivity,
                "Local watch progress could not be loaded: \(error.localizedDescription)"
            )
        }

        do {
            let token = try await Clerk.shared.auth.getToken()
            await api.setToken(token)
            setAccountError(.authentication, nil)
        } catch {
            setAccountError(
                .authentication,
                "The account session could not be authenticated: \(error.localizedDescription)"
            )
            finishMediaHydration(ownerID: clerkUser.id)
            return
        }

        async let progressSync: Void = synchronizeProgressForSession(ownerID: clerkUser.id)
        async let profileSync: Void = synchronizeProfileForSession(
            email: email,
            name: name,
            avatarURL: clerkUser.imageUrl
        )
        async let librarySync: Void = synchronizeLibraryForSession()
        async let mediaSync: Void = synchronizeMediaAccountForSession(ownerID: clerkUser.id)
        _ = await (progressSync, profileSync, librarySync, mediaSync)
    }

    private var progressOwnerID: String {
        signedInUser?.id ?? Self.deviceProgressOwnerID
    }

    private func loadLocalProgress(ownerID: String) async throws {
        let local = try await readingProgressStore.progresses(ownerID: ownerID)
        progressByNovelID = Dictionary(
            uniqueKeysWithValues: local.map { ($0.novelID, $0.readingProgress) }
        )
    }

    private func synchronizeProgressForSession(ownerID: String) async {
        do {
            try await synchronizeReadingProgress(ownerID: ownerID)
            setAccountError(.progressSync, nil)
        } catch {
            setAccountError(
                .progressSync,
                "Reading progress is using the local copy until sync succeeds: \(error.localizedDescription)"
            )
        }
    }

    private func synchronizeProfileForSession(
        email: String?,
        name: String,
        avatarURL: String?
    ) async {
        do {
            _ = try await api.updateProfile(
                email: email,
                username: name,
                avatarURL: avatarURL
            )
            setAccountError(.profileSync, nil)
        } catch {
            setAccountError(
                .profileSync,
                "The profile could not be updated: \(error.localizedDescription)"
            )
        }
    }

    private func synchronizeLibraryForSession() async {
        do {
            let records = try await api.fetchLibrary()
            libraryNovelIDs = Set(records.map(\.novelId))
            setAccountError(.librarySync, nil)
        } catch {
            setAccountError(
                .librarySync,
                "The saved library could not be loaded: \(error.localizedDescription)"
            )
        }
    }

    private func synchronizeMediaAccountForSession(ownerID: String) async {
        defer { finishMediaHydration(ownerID: ownerID) }
        var failures: [String] = []

        do {
            try await flushMediaOutbox(ownerID: ownerID)
        } catch let error as MediaOutboxRejectedError {
            failures.append(error.localizedDescription)
        } catch {
            failures.append("Pending watch activity could not be uploaded: \(error.localizedDescription)")
            scheduleMediaOutboxFlush(ownerID: ownerID)
        }

        do {
            let server = try await api.fetchMediaAccount()
            try await mediaActivityStore.mergeRemote(
                ownerID: ownerID,
                bookmarks: server.bookmarks,
                progress: server.progress,
                history: server.history,
                stats: server.stats
            )
        } catch {
            failures.append("Account media could not be downloaded: \(error.localizedDescription)")
        }

        do {
            try await loadLocalMediaActivity(ownerID: ownerID)
        } catch {
            failures.append("The media copy on this Mac could not be loaded: \(error.localizedDescription)")
        }

        if failures.isEmpty {
            setAccountError(.mediaSync, nil)
        } else {
            setAccountError(
                .mediaSync,
                "Watch activity is using the copy on this Mac until sync succeeds. "
                    + failures.joined(separator: " ")
            )
        }
    }

    private func loadLocalMediaActivity(ownerID: String) async throws {
        let snapshot = try await mediaActivityStore.snapshot(ownerID: ownerID)
        mediaBookmarksByKey = Dictionary(
            uniqueKeysWithValues: snapshot.bookmarks.map { ($0.key, $0) }
        )
        mediaProgressByKey = Dictionary(
            uniqueKeysWithValues: snapshot.progress.map { ($0.key, $0) }
        )
        mediaHistory = Array(snapshot.history.prefix(100))
        mediaStats = snapshot.stats
        let rejectedMessage = snapshot.rejectedItems.isEmpty
            ? nil
            : snapshot.rejectedItems
                .map { "\($0.title): \($0.message)" }
                .joined(separator: "\n")
        setAccountError(.rejectedMediaActivity, rejectedMessage)
    }

    private func uploadMediaBookmarkMutation(
        _ mutation: LocalMediaBookmarkMutation
    ) async throws {
        guard signedInUser?.id == mutation.ownerID else { throw CancellationError() }
        let result: MediaBookmarkMutationResult
        if mutation.isSaved {
            result = try await api.saveMediaBookmark(
                mutation.item,
                clientEventAt: mutation.clientEventAt
            )
        } else {
            result = try await api.deleteMediaBookmark(
                mutation.item,
                clientEventAt: mutation.clientEventAt
            )
        }
        try await mediaActivityStore.resolveBookmarkMutation(
            ownerID: mutation.ownerID,
            mutationID: mutation.id,
            key: mutation.item.key,
            result: result
        )
    }

    private func flushMediaOutbox(ownerID: String) async throws {
        guard signedInUser?.id == ownerID else { throw CancellationError() }
        var rejectedMessages: [String] = []

        let bookmarkMutations = try await mediaActivityStore.pendingBookmarkMutations(
            ownerID: ownerID
        )
        for mutation in bookmarkMutations {
            try Task.checkCancellation()
            do {
                try await uploadMediaBookmarkMutation(mutation)
            } catch where isPermanentMediaSyncError(error) {
                let recordedRejection = try await mediaActivityStore.rejectBookmarkMutation(
                    ownerID: ownerID,
                    mutation: mutation,
                    message: error.localizedDescription,
                    rejectedAt: Date()
                )
                if recordedRejection {
                    rejectedMessages.append("\(mutation.item.title): \(error.localizedDescription)")
                }
            }
        }

        let pendingEvents = try await mediaActivityStore.pendingEvents(ownerID: ownerID)
        for event in pendingEvents {
            try Task.checkCancellation()
            guard signedInUser?.id == ownerID else { throw CancellationError() }
            do {
                let result = try await mediaProgressUploadQueue.submit(
                    MediaProgressUploadQueue.Request(
                        ownerID: ownerID,
                        playback: event.playback,
                        positionSeconds: event.positionSeconds,
                        durationSeconds: event.durationSeconds,
                        completed: event.completed,
                        started: event.started,
                        sessionID: event.sessionID,
                        clientEventAt: event.clientEventAt
                    )
                )
                try await mediaActivityStore.acknowledge(ownerID: ownerID, eventID: event.id)
                try await mediaActivityStore.mergeRemote(
                    ownerID: ownerID,
                    progress: result.progress.map { [$0] } ?? [],
                    history: result.history.map { [$0] } ?? [],
                    stats: nil
                )
            } catch where isPermanentMediaSyncError(error) {
                let recordedRejection = try await mediaActivityStore.rejectPlaybackEvent(
                    ownerID: ownerID,
                    event: event,
                    message: error.localizedDescription,
                    rejectedAt: Date()
                )
                if recordedRejection {
                    rejectedMessages.append("\(event.playback.item.title): \(error.localizedDescription)")
                }
            }
        }

        if !rejectedMessages.isEmpty {
            throw MediaOutboxRejectedError(messages: rejectedMessages)
        }
    }

    private func scheduleMediaOutboxFlush(ownerID: String) {
        guard signedInUser?.id == ownerID, mediaOutboxTask == nil else { return }
        mediaOutboxTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.mediaOutboxTask = nil }
            var retryDelay = Duration.seconds(2)

            while !Task.isCancelled, self.signedInUser?.id == ownerID {
                do {
                    try await self.flushMediaOutbox(ownerID: ownerID)
                    try await self.loadLocalMediaActivity(ownerID: ownerID)
                    self.mediaBookmarkError = nil
                    self.setAccountError(.mediaBookmarkMutation, nil)
                    self.setAccountError(.mediaProgressSave, nil)
                    self.setAccountError(.mediaSync, nil)
                    return
                } catch let error as MediaOutboxRejectedError {
                    try? await self.loadLocalMediaActivity(ownerID: ownerID)
                    self.setAccountError(.mediaSync, error.localizedDescription)
                    return
                } catch is CancellationError {
                    return
                } catch {
                    self.setAccountError(
                        .mediaSync,
                        "Saved media activity will retry automatically: \(error.localizedDescription)"
                    )
                }

                do {
                    try await Task.sleep(for: retryDelay)
                } catch {
                    return
                }
                retryDelay = min(retryDelay * 2, .seconds(300))
            }
        }
    }

    private func finishMediaHydration(ownerID: String?) {
        mediaHydratedOwnerID = ownerID
        let waiters = mediaHydrationWaiters
        mediaHydrationWaiters = []
        waiters.forEach { $0.resume() }
    }

    private func waitForMediaHydration(ownerID: String) async {
        guard mediaHydratedOwnerID != ownerID,
              signedInUser?.id == ownerID else { return }
        await withCheckedContinuation { continuation in
            guard mediaHydratedOwnerID != ownerID,
                  signedInUser?.id == ownerID else {
                continuation.resume()
                return
            }
            mediaHydrationWaiters.append(continuation)
        }
    }

    private func isPermanentMediaSyncError(_ error: Error) -> Bool {
        guard case APIError.http(let statusCode, _) = error else { return false }
        return (400..<500).contains(statusCode)
            && ![401, 408, 425, 429].contains(statusCode)
    }

    private func synchronizeReadingProgress(ownerID: String) async throws {
        let serverProgress = try await api.fetchAllProgress()
        let localProgress = try await readingProgressStore.progresses(ownerID: ownerID)
        let serverByNovelID = Dictionary(
            uniqueKeysWithValues: serverProgress.map { ($0.novelId, $0) }
        )
        let localByNovelID = Dictionary(
            uniqueKeysWithValues: localProgress.map { ($0.novelID, $0) }
        )
        let novelIDs = Set(serverByNovelID.keys).union(localByNovelID.keys)
        for novelID in novelIDs.sorted() {
            let local = localByNovelID[novelID]
            let server = serverByNovelID[novelID]

            if let local, (local.shouldUpload(over: server) || server == nil) {
                let current = try await readingProgressStore.progress(
                    ownerID: ownerID,
                    novelID: novelID
                )
                guard current?.revision == local.revision else { continue }

                let saved: ReadingProgress
                do {
                    saved = try await progressUploadQueue.submit(
                        ReadingProgressUploadQueue.Request(
                            ownerID: ownerID,
                            novelID: local.novelID,
                            chapterID: local.chapterID,
                            currentLine: local.currentLine,
                            totalLines: local.totalLines
                        )
                    )
                } catch ReadingProgressUploadQueueError.superseded {
                    continue
                }

                let latest = try await readingProgressStore.progress(
                    ownerID: ownerID,
                    novelID: novelID
                )
                guard latest?.revision == local.revision else { continue }
                try await readingProgressStore.save(.synced(ownerID: ownerID, server: saved))
            } else if let server {
                let latest = try await readingProgressStore.progress(
                    ownerID: ownerID,
                    novelID: novelID
                )
                guard latest?.revision == local?.revision else { continue }
                try await readingProgressStore.save(.synced(ownerID: ownerID, server: server))
            }
        }

        try await loadLocalProgress(ownerID: ownerID)
    }

    private func loadOfflineLibrary() async {
        do {
            let downloadedItems = try await offlineLibrary.downloadedItems()
            downloadedNovelIDs = Set(downloadedItems.map(\.novel.id))
            let offlineNovels = downloadedItems.map(\.novel)
            novels = mergedNovels(primary: novels, secondary: offlineNovels)
            for item in downloadedItems {
                offlineDownloadByNovelID[item.novel.id] = OfflineDownload(
                    novelID: item.novel.id,
                    novelTitle: item.novel.title,
                    completedChapters: item.chapterCount,
                    totalChapters: item.chapterCount,
                    phase: .completed,
                    errorMessage: nil,
                    updatedAt: item.downloadedAt
                )
            }
        } catch {
            catalogError = error.localizedDescription
            catalogState = .failed(error.localizedDescription)
        }
    }

    private func mergedNovels(primary: [Novel], secondary: [Novel]) -> [Novel] {
        var seen = Set<String>()
        var result: [Novel] = []
        for novel in primary + secondary where !seen.contains(novel.id) {
            seen.insert(novel.id)
            result.append(novel)
        }
        return result
    }

    private func cacheChapterContent(_ chapters: [Chapter]) {
        for chapter in chapters where chapter.content?.isEmpty == false {
            chapterByID[chapter.id] = chapter
        }
    }

    private func progressSaveKey(ownerID: String, novelID: String) -> String {
        ownerID + "\u{0}" + novelID
    }

    private func setAccountError(_ source: AccountErrorSource, _ message: String?) {
        if let message, !message.isEmpty {
            accountErrors[source] = message
        } else {
            accountErrors.removeValue(forKey: source)
        }
        accountError = AccountErrorSource.allCases
            .compactMap { accountErrors[$0] }
            .joined(separator: "\n")
        if accountError?.isEmpty == true {
            accountError = nil
        }
    }

    private func clearRemoteAccountErrors() {
        for source in [
            AccountErrorSource.authentication,
            .progressSync,
            .profileSync,
            .librarySync,
            .progressSave,
            .libraryMutation,
            .mediaSync,
            .localMediaActivity,
            .rejectedMediaActivity,
            .mediaBookmarkMutation,
            .mediaProgressSave,
        ] {
            accountErrors.removeValue(forKey: source)
        }
        accountError = AccountErrorSource.allCases
            .compactMap { accountErrors[$0] }
            .joined(separator: "\n")
        if accountError?.isEmpty == true {
            accountError = nil
        }
    }

    private func updateOfflineDownload(
        novelID: String,
        update: (inout OfflineDownload) -> Void
    ) {
        guard var download = offlineDownloadByNovelID[novelID] else { return }
        update(&download)
        download.updatedAt = Date()
        offlineDownloadByNovelID[novelID] = download
    }
}
