import Foundation
import Network
import UIKit

struct OfflineLibraryItemSnapshot: Codable {
    let novel: Novel
    let addedAt: Date?
    let updatedAt: Date?
    let lastReadAt: Date?
}

nonisolated struct DownloadedChapterFile: Identifiable, Codable, Hashable {
    let chapter: Chapter
    let fileURL: URL
    /// Saved by "Download ahead" rather than by the reader. Optional so older manifests still decode.
    var isAutomatic: Bool? = nil
    var id: String { chapter.id }
    var isDownloadedAhead: Bool { isAutomatic == true }
}

nonisolated struct DownloadedNovelCollection: Identifiable, Hashable {
    let novel: Novel
    let folderURL: URL
    let chapters: [DownloadedChapterFile]
    let byteCount: Int64
    var id: String { folderURL.path }
    var title: String { novel.title }
    var chapterCount: Int { chapters.count }
    var downloadedAheadCount: Int { chapters.filter(\.isDownloadedAhead).count }
    var formattedSize: String { ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file) }
}

private nonisolated struct DownloadedNovelManifest: Codable {
    let novel: Novel
    var chapters: [DownloadedChapterFile]
}

/// A manifest held in memory while chapters are saved into its folder.
private nonisolated struct CachedManifest {
    let folder: URL
    private(set) var manifest: DownloadedNovelManifest
    private var indexByID: [String: Int] = [:]

    init(folder: URL, manifest: DownloadedNovelManifest) {
        self.folder = folder
        // Older manifests could hold an id twice; the last entry is the one that was saved last.
        var seen = Set<String>()
        let chapters = Array(manifest.chapters.reversed().filter { seen.insert($0.id).inserted }.reversed())
        for (index, entry) in chapters.enumerated() {
            indexByID[entry.id] = index
        }
        self.manifest = DownloadedNovelManifest(novel: manifest.novel, chapters: chapters)
    }

    mutating func save(_ file: DownloadedChapterFile) {
        if let index = indexByID[file.id] {
            manifest.chapters[index] = file
        } else {
            indexByID[file.id] = manifest.chapters.count
            manifest.chapters.append(file)
        }
    }

    mutating func remove(_ ids: Set<String>) {
        manifest.chapters.removeAll { ids.contains($0.id) }
        indexByID = Dictionary(uniqueKeysWithValues: manifest.chapters.enumerated().map { ($1.id, $0) })
    }
}

@MainActor
final class OfflineChapterStore {
    static let shared = OfflineChapterStore()

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let directoryOverride: URL?
    private let documentsOverride: URL?

    private nonisolated static let manifestFileName = ".asterion-manifest.json"
    /// How long a saved chapter waits for its manifest write, so a bulk
    /// download rewrites the manifest every few seconds, not once per chapter.
    private static let manifestWriteDelay: Duration = .seconds(2)

    /// Manifests of the folders chapters are being saved into, keyed by folder path.
    private var manifests: [String: CachedManifest] = [:]
    /// Folders whose manifest changed since it was last written. Always cached.
    private var dirtyManifestFolders: Set<String> = []
    private var scheduledManifestWrite: Task<Void, Never>?
    /// The latest manifest write. Each write waits for the one before it.
    private var manifestWrite: Task<Void, Never>?
    /// Bumped when the cache is dropped, so a load that raced the drop starts over.
    private var manifestGeneration = 0
    private var backgroundObserver: NSObjectProtocol?
    private var backgroundFlushTask: UIBackgroundTaskIdentifier = .invalid

    init(baseDirectory: URL? = nil, documentsDirectory: URL? = nil) {
        directoryOverride = baseDirectory
        documentsOverride = documentsDirectory
    }

    private var documentsDirectory: URL {
        documentsOverride ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? baseDirectory
    }

    private var baseDirectory: URL {
        let fileManager = FileManager.default
        if let directoryOverride {
            try? fileManager.createDirectory(at: directoryOverride, withIntermediateDirectories: true)
            return directoryOverride
        }
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("offline_chapters", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func cacheChapter(_ chapter: Chapter) async {
        let fileURL = baseDirectory.appendingPathComponent("\(chapter.id).json")
        guard let data = try? encoder.encode(chapter) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func chapter(id: String) async -> Chapter? {
        let fileURL = baseDirectory.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(Chapter.self, from: data)
    }

    func saveLibrarySnapshot(_ items: [OfflineLibraryItemSnapshot]) async {
        let fileURL = baseDirectory.appendingPathComponent("library_snapshot.json")
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func loadLibrarySnapshot() async -> [OfflineLibraryItemSnapshot] {
        let fileURL = baseDirectory.appendingPathComponent("library_snapshot.json")
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([OfflineLibraryItemSnapshot].self, from: data)) ?? []
    }

    func saveChapterList(novelId: String, chapters: [Chapter], mergeWithExisting: Bool = true) async {
        let fileURL = baseDirectory.appendingPathComponent("chapter_list_\(novelId).json")
        let merged: [Chapter]
        if mergeWithExisting, let existingData = try? Data(contentsOf: fileURL),
           let existing = try? decoder.decode([Chapter].self, from: existingData)
        {
            var byId = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
            for chapter in chapters {
                byId[chapter.id] = chapter
            }
            merged = byId.values.sorted { lhs, rhs in
                if lhs.chapterNumber == rhs.chapterNumber { return lhs.id < rhs.id }
                return lhs.chapterNumber < rhs.chapterNumber
            }
        } else {
            merged = chapters.sorted { lhs, rhs in
                if lhs.chapterNumber == rhs.chapterNumber { return lhs.id < rhs.id }
                return lhs.chapterNumber < rhs.chapterNumber
            }
        }

        guard let data = try? encoder.encode(merged) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func loadChapterList(novelId: String) async -> [Chapter] {
        let fileURL = baseDirectory.appendingPathComponent("chapter_list_\(novelId).json")
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([Chapter].self, from: data)) ?? []
    }

    func saveCatalog(_ novels: [Novel]) async {
        let fileURL = baseDirectory.appendingPathComponent("novel_catalog.json")
        guard let data = try? encoder.encode(novels) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func loadCatalog() async -> [Novel] {
        let fileURL = baseDirectory.appendingPathComponent("novel_catalog.json")
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([Novel].self, from: data)) ?? []
    }

    func saveDownloadedChapter(
        novelTitle: String,
        chapterNumber: Int,
        chapterTitle: String,
        content: String,
        novel: Novel? = nil,
        chapter: Chapter? = nil,
        automatic: Bool = false
    ) async throws -> URL {
        let novelFolder = novelFolderURL(novelTitle: novelTitle)
        let fileURL = downloadedChapterURL(novelTitle: novelTitle, chapterNumber: chapterNumber, chapterTitle: chapterTitle)
        let data = Data(content.utf8)
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: novelFolder, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        }.value
        if let novel, let chapter, await loadManifest(folder: novelFolder, novel: novel) {
            let metadata = Chapter(id: chapter.id, chapterNumber: chapter.chapterNumber,
                                   title: chapter.title, content: nil, url: chapter.url)
            // A manual save of the same chapter clears the "downloaded ahead" mark, so pruning keeps it.
            manifests[novelFolder.path]!.save(
                DownloadedChapterFile(chapter: metadata, fileURL: fileURL, isAutomatic: automatic ? true : nil)
            )
            markManifestChanged(novelFolder)
        }
        return fileURL
    }

    /// Writes the manifests saved chapters are waiting on and drops the in-memory copies.
    /// Download runs call this when they finish; it also runs when the app enters the background.
    func flushDownloadedManifests() async {
        let write = startManifestWrite()
        manifests.removeAll()
        manifestGeneration += 1
        await write?.value
    }

    /// Makes sure the folder's manifest is in `manifests`, reading it from disk once.
    /// With no manifest on disk, starts one for `novel`; returns false if there is neither.
    private func loadManifest(folder: URL, novel: Novel?) async -> Bool {
        let key = folder.path
        while manifests[key] == nil {
            let generation = manifestGeneration
            let pendingWrite = manifestWrite
            let url = folder.appendingPathComponent(Self.manifestFileName)
            let loaded = await Task.detached(priority: .userInitiated) { () -> DownloadedNovelManifest? in
                await pendingWrite?.value
                return (try? Data(contentsOf: url)).flatMap {
                    try? JSONDecoder().decode(DownloadedNovelManifest.self, from: $0)
                }
            }.value
            // The cache was dropped while reading, so this copy may be missing a write; read again.
            guard generation == manifestGeneration else { continue }
            guard manifests[key] == nil else { break }
            guard let manifest = loaded ?? novel.map({ DownloadedNovelManifest(novel: $0, chapters: []) }) else {
                return false
            }
            manifests[key] = CachedManifest(folder: folder, manifest: manifest)
        }
        return true
    }

    private func markManifestChanged(_ folder: URL) {
        dirtyManifestFolders.insert(folder.path)
        observeBackgroundIfNeeded()
        guard scheduledManifestWrite == nil else { return }
        scheduledManifestWrite = Task { [weak self] in
            try? await Task.sleep(for: Self.manifestWriteDelay)
            guard !Task.isCancelled, let self else { return }
            self.scheduledManifestWrite = nil
            self.startManifestWrite()
        }
    }

    /// Encodes and writes the changed manifests off the main thread, after any earlier write.
    /// Returns the latest write so callers can wait for everything saved so far to reach disk.
    @discardableResult
    private func startManifestWrite() -> Task<Void, Never>? {
        scheduledManifestWrite?.cancel()
        scheduledManifestWrite = nil
        guard !dirtyManifestFolders.isEmpty else { return manifestWrite }
        let pending = dirtyManifestFolders.compactMap { manifests[$0] }
            .map { ($0.folder.appendingPathComponent(Self.manifestFileName), $0.manifest) }
        dirtyManifestFolders.removeAll()
        let previous = manifestWrite
        let write = Task.detached(priority: .utility) {
            await previous?.value
            let encoder = JSONEncoder()
            for (url, manifest) in pending {
                guard let data = try? encoder.encode(manifest) else { continue }
                try? data.write(to: url, options: .atomic)
            }
        }
        manifestWrite = write
        return write
    }

    /// Downloads pause in the background, so write what they saved before the app is suspended.
    private func observeBackgroundIfNeeded() {
        guard backgroundObserver == nil else { return }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushInBackground() }
        }
    }

    private func flushInBackground() {
        guard backgroundFlushTask == .invalid else { return }
        backgroundFlushTask = UIApplication.shared.beginBackgroundTask(withName: "Asterion.downloads.manifest") { [weak self] in
            MainActor.assumeIsolated { self?.endBackgroundFlush() }
        }
        Task {
            await flushDownloadedManifests()
            endBackgroundFlush()
        }
    }

    private func endBackgroundFlush() {
        guard backgroundFlushTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundFlushTask)
        backgroundFlushTask = .invalid
    }

    /// The last scan, so Downloads can show its list instantly on reopen.
    private(set) var cachedCollections: [DownloadedNovelCollection]?

    func downloadedCollections() async -> [DownloadedNovelCollection] {
        let root = documentsDirectory.appendingPathComponent("Asterion Downloads", isDirectory: true)
        let base = baseDirectory
        // The scan reads manifests from disk; let pending writes land first.
        await startManifestWrite()?.value
        // Thousands of chapter files: scan off the main thread.
        let collections = await Task.detached(priority: .userInitiated) {
            Self.scanCollections(root: root, baseDirectory: base)
        }.value
        cachedCollections = collections
        return collections
    }

    /// Builds the collections from the folders on disk. The manifest is
    /// indexed by filename once, and the catalog, cached chapter lists and
    /// chapter files are only read for files the manifest doesn't describe.
    private nonisolated static func scanCollections(root: URL, baseDirectory: URL) -> [DownloadedNovelCollection] {
        let fileManager = FileManager.default
        let decoder = JSONDecoder()
        let folders = (try? fileManager.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var catalog: [Novel]?
        var collections: [DownloadedNovelCollection] = []

        for folder in folders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let files = ((try? fileManager.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? [])
                .filter { $0.pathExtension.lowercased() == "txt" }
            guard !files.isEmpty else { continue }

            let manifest = (try? Data(contentsOf: folder.appendingPathComponent(manifestFileName))).flatMap {
                try? decoder.decode(DownloadedNovelManifest.self, from: $0)
            }
            // Store filenames in the manifest; sandbox container paths can change on reinstall.
            var described: [String: DownloadedChapterFile] = [:]
            for entry in manifest?.chapters ?? [] {
                described[entry.fileURL.lastPathComponent] = entry
            }

            let novel: Novel
            if let manifestNovel = manifest?.novel {
                novel = manifestNovel
            } else {
                if catalog == nil {
                    catalog = (try? Data(contentsOf: baseDirectory.appendingPathComponent("novel_catalog.json")))
                        .flatMap { try? decoder.decode([Novel].self, from: $0) } ?? []
                }
                let folderName = folder.lastPathComponent
                novel = catalog?.first { Self.sanitizeFilenameComponent($0.title) == folderName }
                    ?? Novel(id: "offline-\(folderName)", title: firstLines(of: files[0], count: 1).first ?? folderName,
                             author: nil, rank: nil, totalChapters: nil, views: nil, bookmarks: nil,
                             status: nil, genres: nil, summary: nil, imageUrl: nil, rating: nil)
            }

            var cachedByNumber: [Int: Chapter]?
            var size: Int64 = 0
            var references: [DownloadedChapterFile] = []
            references.reserveCapacity(files.count)
            for file in files {
                size += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                let name = file.lastPathComponent
                if let metadata = described[name] {
                    references.append(DownloadedChapterFile(
                        chapter: metadata.chapter,
                        fileURL: file,
                        isAutomatic: metadata.isAutomatic
                    ))
                    continue
                }
                if cachedByNumber == nil {
                    let list = (try? Data(contentsOf: baseDirectory.appendingPathComponent("chapter_list_\(novel.id).json")))
                        .flatMap { try? decoder.decode([Chapter].self, from: $0) } ?? []
                    cachedByNumber = Dictionary(list.map { ($0.chapterNumber, $0) }, uniquingKeysWith: { first, _ in first })
                }
                let number = Int(file.deletingPathExtension().lastPathComponent.split(separator: "-").dropFirst().first ?? "") ?? 0
                let chapter = cachedByNumber?[number]
                    ?? Chapter(id: "offline-\(folder.lastPathComponent)-\(name)",
                               chapterNumber: number,
                               title: firstLines(of: file, count: 2).dropFirst().first ?? "Chapter \(number)",
                               content: nil, url: nil)
                references.append(DownloadedChapterFile(chapter: chapter, fileURL: file))
            }
            references.sort { $0.chapter.chapterNumber < $1.chapter.chapterNumber }
            collections.append(DownloadedNovelCollection(novel: novel, folderURL: folder, chapters: references, byteCount: size))
        }
        return collections.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The first lines of a chapter file without reading the whole chapter.
    private nonisolated static func firstLines(of file: URL, count: Int) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return [] }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 1024)) ?? Data()
        let text = String(decoding: head, as: UTF8.self)
        return Array(text.components(separatedBy: .newlines).prefix(count))
    }

    func downloadedChapter(_ file: DownloadedChapterFile) throws -> Chapter {
        let raw = try String(contentsOf: file.fileURL, encoding: .utf8)
        let lines = raw.components(separatedBy: .newlines)
        let hasHeader = lines.count > 2 && lines[1].range(of: #"^Chapter\s+\d+"#, options: .regularExpression) != nil
        let body = (hasHeader ? lines.dropFirst(2).joined(separator: "\n") : raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Chapter(id: file.chapter.id, chapterNumber: file.chapter.chapterNumber,
                       title: file.chapter.title, content: body, url: file.chapter.url)
    }

    /// Removes chapters that "Download ahead" saved and the reader has since moved past.
    /// Chapters the user downloaded themselves are never touched.
    @discardableResult
    func pruneDownloadedAheadChapters(novel: Novel, readingChapterNumber: Int) async -> Int {
        guard readingChapterNumber > 1 else { return 0 }
        let folder = novelFolderURL(novelTitle: novel.title)
        guard await loadManifest(folder: folder, novel: nil) else { return 0 }
        let stale = manifests[folder.path]!.manifest.chapters.filter {
            $0.isDownloadedAhead && $0.chapter.chapterNumber > 0 && $0.chapter.chapterNumber < readingChapterNumber
        }
        guard !stale.isEmpty else { return 0 }
        manifests[folder.path]!.remove(Set(stale.map(\.id)))
        markManifestChanged(folder)
        // The manifest may hold an old container path; the filename is what is stable.
        let staleFiles = stale.map { folder.appendingPathComponent($0.fileURL.lastPathComponent) }
        await Task.detached(priority: .utility) {
            for url in staleFiles {
                try? FileManager.default.removeItem(at: url)
            }
        }.value
        return stale.count
    }

    func isChapterDownloaded(
        novelTitle: String,
        chapterNumber: Int,
        chapterTitle: String
    ) async -> Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(
            atPath: downloadedChapterURL(
                novelTitle: novelTitle,
                chapterNumber: chapterNumber,
                chapterTitle: chapterTitle
            ).path
        )
    }

    private func novelFolderURL(novelTitle: String) -> URL {
        let rootFolder = documentsDirectory.appendingPathComponent("Asterion Downloads", isDirectory: true)
        let folderName = Self.sanitizeFilenameComponent(novelTitle).isEmpty
            ? "novel"
            : Self.sanitizeFilenameComponent(novelTitle)
        return rootFolder.appendingPathComponent(folderName, isDirectory: true)
    }

    private func downloadedChapterURL(
        novelTitle: String,
        chapterNumber: Int,
        chapterTitle: String
    ) -> URL {
        let chapterPrefix = chapterNumber > 0 ? String(format: "ch-%04d", chapterNumber) : "chapter"
        let chapterSlug = Self.sanitizeFilenameComponent(chapterTitle).isEmpty
            ? "untitled"
            : Self.sanitizeFilenameComponent(chapterTitle)
        let fileName = "\(chapterPrefix)-\(chapterSlug).txt"
        return novelFolderURL(novelTitle: novelTitle).appendingPathComponent(fileName)
    }

    private nonisolated static func sanitizeFilenameComponent(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9._-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

// MARK: - Download ahead

/// An in-progress novel, as Home resolved it for "Continue".
struct DownloadAheadNovel {
    let novel: Novel
    let currentChapter: Chapter
    let chapters: [Chapter]
}

/// Keeps the next few chapters and episodes of whatever the user is in the
/// middle of ready offline. Runs one conservative, sequential pass at a time,
/// only on an unmetered connection, and prunes what it saved once it is read.
@MainActor
final class DownloadAheadCoordinator {
    static let shared = DownloadAheadCoordinator()

    static let enabledKey = "asterion.downloadAhead.enabled"
    static let chaptersAhead = 5
    static let episodesAhead = 2
    private static let maximumShows = 3
    private static let minimumInterval: TimeInterval = 10 * 60

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private let store: OfflineChapterStore
    private var activePass: Task<Void, Never>?
    private var lastDownloadPassAt: Date?
    private var lastPassSignature: String?

    init(store: OfflineChapterStore? = nil) {
        self.store = store ?? .shared
    }

    var isRunning: Bool { activePass != nil }

    /// Starts a pass unless one is running, or the same positions were handled recently.
    /// A new reading or watching position, or `force` (pull to refresh), skips the cool-down.
    func schedule(
        novels: [DownloadAheadNovel],
        watching progress: [MediaPlaybackProgress],
        apiClient: APIClient,
        videoDownloads: OfflineVideoDownloadService,
        force: Bool = false
    ) {
        guard Self.isEnabled, activePass == nil else { return }
        guard !novels.isEmpty || !progress.isEmpty else { return }
        let signature = Self.signature(novels: novels, progress: progress)
        if !force, signature == lastPassSignature, let lastDownloadPassAt,
           Date().timeIntervalSince(lastDownloadPassAt) < Self.minimumInterval {
            return
        }
        activePass = Task { [weak self] in
            await self?.runPass(
                novels: novels,
                progress: progress,
                apiClient: apiClient,
                videoDownloads: videoDownloads,
                signature: signature
            )
            await self?.store.flushDownloadedManifests()
            self?.activePass = nil
        }
    }

    private static func signature(novels: [DownloadAheadNovel], progress: [MediaPlaybackProgress]) -> String {
        let reading = novels.map { "\($0.novel.id):\($0.currentChapter.id)" }.sorted()
        let watching = showsToQueue(from: progress).map { "\($0.contentId):\($0.unitId)" }.sorted()
        return (reading + ["|"] + watching).joined(separator: ",")
    }

    private func runPass(
        novels: [DownloadAheadNovel],
        progress: [MediaPlaybackProgress],
        apiClient: APIClient,
        videoDownloads: OfflineVideoDownloadService,
        signature: String
    ) async {
        // Pruning is local, so it runs on any connection.
        for entry in novels {
            await store.pruneDownloadedAheadChapters(
                novel: entry.novel,
                readingChapterNumber: entry.currentChapter.chapterNumber
            )
        }
        videoDownloads.pruneWatchedDownloadsAhead(progress: progress)

        guard await Self.isOnUnmeteredNetwork() else { return }
        lastDownloadPassAt = Date()
        lastPassSignature = signature

        for entry in novels {
            guard Self.isEnabled, !Task.isCancelled else { return }
            await downloadChaptersAhead(for: entry, apiClient: apiClient)
        }

        let shows = Self.showsToQueue(from: progress)
        for item in shows {
            guard Self.isEnabled, !Task.isCancelled else { return }
            guard await Self.isOnUnmeteredNetwork() else { return }
            switch item.mediaType {
            case .anime:
                await queueAnimeEpisodesAhead(after: item, videoDownloads: videoDownloads)
            case .movie:
                await queueSeriesEpisodesAhead(after: item, videoDownloads: videoDownloads)
            default:
                break
            }
        }
    }

    // MARK: Chapters

    private func downloadChaptersAhead(for entry: DownloadAheadNovel, apiClient: APIClient) async {
        let novel = entry.novel
        let ordered = entry.chapters.sorted { lhs, rhs in
            if lhs.chapterNumber == rhs.chapterNumber { return lhs.id < rhs.id }
            return lhs.chapterNumber < rhs.chapterNumber
        }
        guard let index = ordered.firstIndex(where: { $0.id == entry.currentChapter.id })
            ?? ordered.firstIndex(where: { $0.chapterNumber == entry.currentChapter.chapterNumber })
        else { return }
        let upcoming = ordered.dropFirst(index + 1).prefix(Self.chaptersAhead)

        for chapter in upcoming {
            guard Self.isEnabled, !Task.isCancelled else { return }
            if await store.isChapterDownloaded(
                novelTitle: novel.title,
                chapterNumber: chapter.chapterNumber,
                chapterTitle: chapter.title
            ) { continue }

            let full: Chapter
            if let cached = await store.chapter(id: chapter.id), !(cached.content ?? "").isEmpty {
                full = cached
            } else if let fetched = try? await apiClient.fetchChapter(id: chapter.id) {
                await store.cacheChapter(fetched)
                full = fetched
            } else {
                // The source is struggling; try again on a later pass.
                return
            }
            guard !(full.content ?? "").isEmpty else { continue }
            if full.title != chapter.title, await store.isChapterDownloaded(
                novelTitle: novel.title,
                chapterNumber: full.chapterNumber,
                chapterTitle: full.title
            ) { continue }

            let body = "\(novel.title)\n\(full.labeledTitle)\n\n\(full.plainContent)"
            _ = try? await store.saveDownloadedChapter(
                novelTitle: novel.title,
                chapterNumber: full.chapterNumber,
                chapterTitle: full.title,
                content: body,
                novel: novel,
                chapter: full,
                automatic: true
            )
        }
    }

    // MARK: Episodes

    /// Most recent in-progress anime and series, one entry per title.
    private static func showsToQueue(from progress: [MediaPlaybackProgress]) -> [MediaPlaybackProgress] {
        var seen = Set<String>()
        return progress
            .filter { item in
                guard !item.completed, item.positionSeconds > 0 else { return false }
                switch item.mediaType {
                case .anime: return item.episodeNumber != nil
                case .movie: return item.episodeNumber != nil || item.seasonNumber != nil
                default: return false
                }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .filter { seen.insert("\($0.mediaType.rawValue):\($0.contentId)").inserted }
            .prefix(maximumShows)
            .map { $0 }
    }

    private func queueAnimeEpisodesAhead(
        after item: MediaPlaybackProgress,
        videoDownloads: OfflineVideoDownloadService
    ) async {
        guard let current = item.episodeNumber,
              let show = try? await EntertainmentAPI.shared.fetchAnimeShow(slug: item.contentId),
              let episodes = try? await EntertainmentAPI.shared.fetchAnimeEpisodes(showID: show.id)
        else { return }

        var seenNumbers = Set<Int>()
        let upcoming = episodes
            .filter { $0.number > current }
            .sorted { $0.number < $1.number }
            .filter { seenNumbers.insert($0.number).inserted }
            .prefix(Self.episodesAhead)
        let descriptor = MediaItemDescriptor(
            mediaType: .anime,
            contentID: item.contentId,
            title: show.title,
            subtitle: show.type,
            imageURL: show.imageURL ?? item.imageURL
        )
        for episode in upcoming {
            guard Self.isEnabled, !Task.isCancelled else { return }
            let id = "anime-\(episode.animeID)-\(episode.number)"
            guard !videoDownloads.isDownloaded(id: id), !videoDownloads.isTransferring(id: id) else { continue }
            guard let request = try? await EntertainmentAPI.shared.fetchAnimePlayback(
                animeID: episode.animeID,
                episodeNumber: episode.number,
                title: "\(show.title) · Episode \(episode.number)",
                item: descriptor
            ) else { continue }
            videoDownloads.start(request, automatic: true)
        }
    }

    private func queueSeriesEpisodesAhead(
        after item: MediaPlaybackProgress,
        videoDownloads: OfflineVideoDownloadService
    ) async {
        guard let episodes = try? await EntertainmentAPI.shared.fetchMovieEpisodes(slug: item.contentId) else {
            return
        }
        let ordered = episodes.sorted { lhs, rhs in
            if lhs.season == rhs.season { return lhs.number < rhs.number }
            return lhs.season < rhs.season
        }
        guard let index = ordered.firstIndex(where: { $0.id == item.unitId })
            ?? ordered.firstIndex(where: { $0.season == item.seasonNumber && $0.number == item.episodeNumber })
        else { return }
        let descriptor = MediaItemDescriptor(
            mediaType: .movie,
            contentID: item.contentId,
            title: item.title,
            subtitle: "TV Series",
            imageURL: item.imageURL
        )
        for episode in ordered.dropFirst(index + 1).prefix(Self.episodesAhead) {
            guard Self.isEnabled, !Task.isCancelled else { return }
            let id = "movie-\(episode.id)"
            guard !videoDownloads.isDownloaded(id: id), !videoDownloads.isTransferring(id: id) else { continue }
            let unitTitle = episode.title.isEmpty ? "Episode \(episode.number)" : episode.title
            guard let request = try? await EntertainmentAPI.shared.fetchMoviePlayback(
                slug: episode.id,
                title: "\(item.title) · \(unitTitle)",
                item: descriptor,
                unitTitle: unitTitle,
                seasonNumber: episode.season,
                episodeNumber: episode.number
            ) else { continue }
            videoDownloads.start(request, automatic: true)
        }
    }

    // MARK: Network

    /// Wi-Fi or wired: connected, not expensive (cellular, hotspot), not Low Data Mode.
    nonisolated static func isOnUnmeteredNetwork() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let probe = DownloadAheadPathProbe()
            monitor.pathUpdateHandler = { path in
                guard probe.claim() else { return }
                monitor.cancel()
                continuation.resume(
                    returning: path.status == .satisfied && !path.isExpensive && !path.isConstrained
                )
            }
            monitor.start(queue: DispatchQueue(label: "Asterion.DownloadAhead.path"))
        }
    }
}

/// Lets the path handler resume its continuation exactly once.
private nonisolated final class DownloadAheadPathProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
