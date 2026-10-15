import Foundation

struct OfflineLibraryItemSnapshot: Codable {
    let novel: Novel
    let addedAt: Date?
    let updatedAt: Date?
    let lastReadAt: Date?
}

struct DownloadedChapterFile: Identifiable, Codable, Hashable {
    let chapter: Chapter
    let fileURL: URL
    var id: String { chapter.id }
}

struct DownloadedNovelCollection: Identifiable, Hashable {
    let novel: Novel
    let folderURL: URL
    let chapters: [DownloadedChapterFile]
    let byteCount: Int64
    var id: String { folderURL.path }
    var title: String { novel.title }
    var chapterCount: Int { chapters.count }
    var formattedSize: String { ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file) }
}

private struct DownloadedNovelManifest: Codable {
    let novel: Novel
    var chapters: [DownloadedChapterFile]
}

@MainActor
final class OfflineChapterStore {
    static let shared = OfflineChapterStore()

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let directoryOverride: URL?
    private let documentsOverride: URL?

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
        chapter: Chapter? = nil
    ) async throws -> URL {
        let fileManager = FileManager.default
        let documents = documentsDirectory
        let rootFolder = documents.appendingPathComponent("Asterion Downloads", isDirectory: true)
        let novelFolderName = sanitizeFilenameComponent(novelTitle).isEmpty
            ? "novel"
            : sanitizeFilenameComponent(novelTitle)
        let novelFolder = rootFolder.appendingPathComponent(novelFolderName, isDirectory: true)
        if !fileManager.fileExists(atPath: novelFolder.path) {
            try fileManager.createDirectory(at: novelFolder, withIntermediateDirectories: true)
        }

        let chapterPrefix = chapterNumber > 0 ? String(format: "ch-%04d", chapterNumber) : "chapter"
        let chapterSlug = sanitizeFilenameComponent(chapterTitle).isEmpty
            ? "untitled"
            : sanitizeFilenameComponent(chapterTitle)
        let fileName = "\(chapterPrefix)-\(chapterSlug).txt"
        let fileURL = novelFolder.appendingPathComponent(fileName)
        try Data(content.utf8).write(to: fileURL, options: .atomic)
        if let novel, let chapter {
            let manifestURL = novelFolder.appendingPathComponent(".asterion-manifest.json")
            var manifest = (try? Data(contentsOf: manifestURL)).flatMap {
                try? decoder.decode(DownloadedNovelManifest.self, from: $0)
            } ?? DownloadedNovelManifest(novel: novel, chapters: [])
            manifest.chapters.removeAll { $0.id == chapter.id }
            let metadata = Chapter(id: chapter.id, chapterNumber: chapter.chapterNumber,
                                   title: chapter.title, content: nil, url: chapter.url)
            manifest.chapters.append(DownloadedChapterFile(chapter: metadata, fileURL: fileURL))
            try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        }
        return fileURL
    }

    func downloadedCollections() async -> [DownloadedNovelCollection] {
        let documents = documentsDirectory
        let root = documents.appendingPathComponent("Asterion Downloads", isDirectory: true)
        let folders = (try? FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        let catalog = await loadCatalog()
        var collections: [DownloadedNovelCollection] = []
        for folder in folders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let files = ((try? FileManager.default.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? [])
                .filter { $0.pathExtension.lowercased() == "txt" }
            guard !files.isEmpty else { continue }
            let manifest = (try? Data(contentsOf: folder.appendingPathComponent(".asterion-manifest.json"))).flatMap {
                try? decoder.decode(DownloadedNovelManifest.self, from: $0)
            }
            let firstTitle = (try? String(contentsOf: files[0], encoding: .utf8))?.components(separatedBy: .newlines).first
            let novel = manifest?.novel ?? catalog.first { sanitizeFilenameComponent($0.title) == folder.lastPathComponent }
                ?? Novel(id: "offline-\(folder.lastPathComponent)", title: firstTitle ?? folder.lastPathComponent,
                         author: nil, rank: nil, totalChapters: nil, views: nil, bookmarks: nil,
                         status: nil, genres: nil, summary: nil, imageUrl: nil, rating: nil)
            let cached = await loadChapterList(novelId: novel.id)
            let references = files.map { file -> DownloadedChapterFile in
                // Store filenames in the manifest; sandbox container paths can change on reinstall.
                if let metadata = manifest?.chapters.first(where: { $0.fileURL.lastPathComponent == file.lastPathComponent }) {
                    return DownloadedChapterFile(chapter: metadata.chapter, fileURL: file)
                }
                let number = Int(file.deletingPathExtension().lastPathComponent.split(separator: "-").dropFirst().first ?? "") ?? 0
                let raw = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                let title = raw.components(separatedBy: .newlines).dropFirst().first ?? "Chapter \(number)"
                let chapter = cached.first { $0.chapterNumber == number }
                    ?? Chapter(id: "offline-\(folder.lastPathComponent)-\(file.lastPathComponent)",
                               chapterNumber: number, title: title, content: nil, url: nil)
                return DownloadedChapterFile(chapter: chapter, fileURL: file)
            }.sorted { $0.chapter.chapterNumber < $1.chapter.chapterNumber }
            let size = files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            collections.append(DownloadedNovelCollection(novel: novel, folderURL: folder, chapters: references, byteCount: size))
        }
        return collections.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
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

    private func downloadedChapterURL(
        novelTitle: String,
        chapterNumber: Int,
        chapterTitle: String
    ) -> URL {
        let documents = documentsDirectory
        let rootFolder = documents.appendingPathComponent("Asterion Downloads", isDirectory: true)
        let novelFolderName = sanitizeFilenameComponent(novelTitle).isEmpty
            ? "novel"
            : sanitizeFilenameComponent(novelTitle)
        let novelFolder = rootFolder.appendingPathComponent(novelFolderName, isDirectory: true)

        let chapterPrefix = chapterNumber > 0 ? String(format: "ch-%04d", chapterNumber) : "chapter"
        let chapterSlug = sanitizeFilenameComponent(chapterTitle).isEmpty
            ? "untitled"
            : sanitizeFilenameComponent(chapterTitle)
        let fileName = "\(chapterPrefix)-\(chapterSlug).txt"
        return novelFolder.appendingPathComponent(fileName)
    }

    private func sanitizeFilenameComponent(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9._-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
