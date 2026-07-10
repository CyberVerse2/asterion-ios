import ClerkKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    private static let offlineDownloadConcurrency = 32

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

    private var chaptersByNovelID: [String: [Chapter]] = [:]
    private var chapterByID: [String: Chapter] = [:]
    private var hasStarted = false
    private var authEventsTask: Task<Void, Never>?

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
        guard isSignedIn else { return nil }
        return try await api.fetchProgress(novelID: novelID)
    }

    func saveProgress(novelID: String, chapterID: String, currentLine: Int, totalLines: Int) async {
        guard isSignedIn else { return }
        do {
            let saved = try await api.saveProgress(
                novelID: novelID,
                chapterID: chapterID,
                currentLine: currentLine,
                totalLines: totalLines
            )
            progressByNovelID[novelID] = saved
        } catch {
            accountError = "Reading progress could not be synced: \(error.localizedDescription)"
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
        guard let clerkUser = Clerk.shared.user else {
            signedInUser = nil
            libraryNovelIDs = []
            progressByNovelID = [:]
            await api.setToken(nil)
            return
        }

        do {
            let token = try await Clerk.shared.auth.getToken()
            await api.setToken(token)

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

            _ = try await api.updateProfile(
                email: email,
                username: name,
                avatarURL: clerkUser.imageUrl
            )
            let records = try await api.fetchLibrary()
            libraryNovelIDs = Set(records.map(\.novelId))
            let progress = try await api.fetchAllProgress()
            progressByNovelID = Dictionary(uniqueKeysWithValues: progress.map { ($0.novelId, $0) })
            accountError = nil
        } catch {
            accountError = error.localizedDescription
        }
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
