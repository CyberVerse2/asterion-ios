import Foundation

struct OfflineLibraryItemSnapshot: Codable {
    let novel: Novel
    let addedAt: Date?
    let updatedAt: Date?
    let lastReadAt: Date?
}

@MainActor
final class OfflineChapterStore {
    static let shared = OfflineChapterStore()

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private var baseDirectory: URL {
        let fileManager = FileManager.default
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
        content: String
    ) async throws -> URL {
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? baseDirectory
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
        return fileURL
    }

    private func sanitizeFilenameComponent(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9._-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
