import ClerkKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    private static let offlineDownloadConcurrency = 32
    private static let deviceProgressOwnerID = "device"

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
    @Published var catalogError: String?
    @Published var accountError: String?

    let api = APIClient()
    private let offlineLibrary = OfflineLibraryStore()
    private let readingProgressStore = ReadingProgressStore()
    private let networkStatus = NetworkStatusMonitor()

    private var chaptersByNovelID: [String: [Chapter]] = [:]
    private var chapterByID: [String: Chapter] = [:]
    private var hasStarted = false
    private var isSynchronizingSession = false
    private var shouldResynchronizeSession = false
    private var authEventsTask: Task<Void, Never>?
    private var networkEventsTask: Task<Void, Never>?

    deinit {
        authEventsTask?.cancel()
        networkEventsTask?.cancel()
        networkStatus.cancel()
    }

    var isSignedIn: Bool { signedInUser != nil }

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
            let offlineNovels = try await offlineLibrary.downloadedNovels()
            novels = mergedNovels(primary: remoteNovels, secondary: offlineNovels)
            catalogError = nil
        } catch {
            do {
                let offlineNovels = try await offlineLibrary.downloadedNovels()
                novels = offlineNovels
                catalogError = offlineNovels.isEmpty ? error.localizedDescription : nil
            } catch {
                catalogError = error.localizedDescription
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

    func chapters(for novelID: String, forceRefresh: Bool = false) async throws -> [Chapter] {
        if !forceRefresh, let cached = chaptersByNovelID[novelID] {
            return cached
        }

        if !forceRefresh, let offlineChapters = try await offlineLibrary.chapters(for: novelID) {
            chaptersByNovelID[novelID] = offlineChapters
            for chapter in offlineChapters {
                if chapter.content?.isEmpty == false {
                    chapterByID[chapter.id] = chapter
                }
            }
            return offlineChapters
        }

        let chapters: [Chapter]
        do {
            chapters = try await api.fetchAllChapters(novelID: novelID)
        } catch {
            if let offlineChapters = try await offlineLibrary.chapters(for: novelID) {
                chaptersByNovelID[novelID] = offlineChapters
                return offlineChapters
            }
            throw error
        }
        chaptersByNovelID[novelID] = chapters
        for chapter in chapters {
            if chapter.content?.isEmpty == false {
                chapterByID[chapter.id] = chapter
            }
        }
        return chapters
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
            chaptersByNovelID[novel.id] = sortedChapters
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
            accountError = "Sign in to save novels to your library."
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
            accountError = nil
        } catch {
            accountError = error.localizedDescription
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
            return server
        } catch {
            accountError = "Progress is unavailable until the connection returns: \(error.localizedDescription)"
            return nil
        }
    }

    func saveProgress(novelID: String, chapterID: String, currentLine: Int, totalLines: Int) async {
        let ownerID = progressOwnerID
        let pending = LocalReadingProgress.pending(
            ownerID: ownerID,
            novelID: novelID,
            chapterID: chapterID,
            currentLine: currentLine,
            totalLines: totalLines
        )

        do {
            try await readingProgressStore.save(pending)
            progressByNovelID[novelID] = pending.readingProgress
        } catch {
            accountError = "Reading progress could not be saved locally: \(error.localizedDescription)"
            return
        }

        guard isSignedIn else { return }

        do {
            let saved = try await api.saveProgress(
                novelID: novelID,
                chapterID: chapterID,
                currentLine: currentLine,
                totalLines: totalLines
            )
            let current = try await readingProgressStore.progress(ownerID: ownerID, novelID: novelID)
            guard current?.revision == pending.revision else { return }
            try await readingProgressStore.save(.synced(ownerID: ownerID, server: saved))
            progressByNovelID[novelID] = saved
            accountError = nil
        } catch {
            accountError = "Progress is saved offline and will sync automatically: \(error.localizedDescription)"
        }
    }

    func signOut() async {
        do {
            try await Clerk.shared.auth.signOut()
            await synchronizeSession()
        } catch {
            accountError = error.localizedDescription
        }
    }

    private func restoreSession() async {
        if Clerk.shared.user == nil {
            _ = try? await Clerk.shared.refreshClient()
        }
        await synchronizeSession()
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
            signedInUser = nil
            libraryNovelIDs = []
            await api.setToken(nil)
            do {
                try await loadLocalProgress(ownerID: Self.deviceProgressOwnerID)
                accountError = nil
            } catch {
                progressByNovelID = [:]
                accountError = "Local reading progress could not be loaded: \(error.localizedDescription)"
            }
            return
        }

        let email = clerkUser.emailAddresses.first?.emailAddress
        let fullName = [clerkUser.firstName, clerkUser.lastName]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = fullName.isEmpty ? (email ?? "Asterion Reader") : fullName
        signedInUser = SignedInUser(
            id: clerkUser.id,
            name: name,
            email: email,
            imageURL: URL(string: clerkUser.imageUrl)
        )

        do {
            try await loadLocalProgress(ownerID: clerkUser.id)
        } catch {
            accountError = "Local reading progress could not be loaded: \(error.localizedDescription)"
        }

        do {
            let token = try await Clerk.shared.auth.getToken()
            await api.setToken(token)

            try await synchronizeReadingProgress(ownerID: clerkUser.id)

            _ = try await api.updateProfile(
                email: email,
                username: name,
                avatarURL: clerkUser.imageUrl
            )
            let records = try await api.fetchLibrary()
            libraryNovelIDs = Set(records.map(\.novelId))
            accountError = nil
        } catch {
            accountError = "Using local progress until sync succeeds: \(error.localizedDescription)"
        }
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
        var resolvedLocal: [LocalReadingProgress] = []
        var resolvedProgress: [String: ReadingProgress] = [:]

        for novelID in novelIDs.sorted() {
            let local = localByNovelID[novelID]
            let server = serverByNovelID[novelID]

            if let local, (local.shouldUpload(over: server) || server == nil) {
                let saved = try await api.saveProgress(
                    novelID: local.novelID,
                    chapterID: local.chapterID,
                    currentLine: local.currentLine,
                    totalLines: local.totalLines
                )
                resolvedLocal.append(.synced(ownerID: ownerID, server: saved))
                resolvedProgress[novelID] = saved
            } else if let server {
                resolvedLocal.append(.synced(ownerID: ownerID, server: server))
                resolvedProgress[novelID] = server
            }
        }

        try await readingProgressStore.replaceProgresses(
            ownerID: ownerID,
            with: resolvedLocal
        )
        progressByNovelID = resolvedProgress
    }

    private func loadOfflineLibrary() async {
        do {
            downloadedNovelIDs = try await offlineLibrary.downloadedNovelIDs()
            let offlineNovels = try await offlineLibrary.downloadedNovels()
            novels = mergedNovels(primary: novels, secondary: offlineNovels)
        } catch {
            catalogError = error.localizedDescription
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
