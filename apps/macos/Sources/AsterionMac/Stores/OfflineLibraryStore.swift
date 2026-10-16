import CryptoKit
import Foundation

enum OfflineLibraryStoreError: LocalizedError, Equatable {
    case duplicateChapterIdentifier(String)
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .duplicateChapterIdentifier(let chapterID):
            "The offline library contains a duplicate chapter identifier: \(chapterID)."
        case .unsupportedSchema(let version):
            "Offline library format \(version) is not supported by this version of Asterion."
        }
    }
}

actor OfflineLibraryStore {
    struct DownloadedNovel: Equatable, Sendable {
        let novel: Novel
        let chapterCount: Int
        let downloadedAt: Date
        /// Whether the saved chapters were the whole novel when last
        /// downloaded. Downloads from before range downloads always were.
        let coversWholeNovel: Bool
    }

    private struct LibraryIndex: Codable, Sendable {
        static let currentSchemaVersion = 1

        var schemaVersion = currentSchemaVersion
        var novels: [String: NovelRecord] = [:]
        var chapters: [String: ChapterLocation] = [:]
    }

    private struct NovelRecord: Codable, Sendable {
        let novel: Novel
        let storageKey: String
        let chapterCount: Int
        let downloadedAt: Date
        /// Absent in records written before range downloads, which always
        /// held the whole novel.
        var coversWholeNovel: Bool?
    }

    private struct ChapterLocation: Codable, Sendable {
        let novelID: String
        let novelStorageKey: String
        let chapterStorageKey: String
    }

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var cachedIndex: LibraryIndex?

    init(directory: URL? = nil) {
        let baseDirectory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        self.directory = baseDirectory
            .appendingPathComponent("Asterion", isDirectory: true)
            .appendingPathComponent("OfflineLibrary", isDirectory: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func downloadedNovelIDs() throws -> Set<String> {
        Set(try loadIndex().novels.keys)
    }

    func downloadedNovels() throws -> [Novel] {
        try downloadedItems().map(\.novel)
    }

    func downloadedItems() throws -> [DownloadedNovel] {
        try loadIndex().novels.values
            .sorted { $0.downloadedAt > $1.downloadedAt }
            .map {
                DownloadedNovel(
                    novel: $0.novel,
                    chapterCount: $0.chapterCount,
                    downloadedAt: $0.downloadedAt,
                    coversWholeNovel: $0.coversWholeNovel ?? true
                )
            }
    }

    func chapters(for novelID: String) throws -> [Chapter]? {
        let index = try loadIndex()
        guard let record = index.novels[novelID] else { return nil }
        let url = chapterListURL(novelStorageKey: record.storageKey)
        return try decoder.decode([Chapter].self, from: Data(contentsOf: url))
    }

    func chapterIDs(for novelID: String) throws -> [String]? {
        let index = try loadIndex()
        guard index.novels[novelID] != nil else { return nil }
        return index.chapters.compactMap { chapterID, location in
            location.novelID == novelID ? chapterID : nil
        }
    }

    func chapter(id: String) throws -> Chapter? {
        let index = try loadIndex()
        guard let location = index.chapters[id] else { return nil }
        let url = chapterURL(
            novelStorageKey: location.novelStorageKey,
            chapterStorageKey: location.chapterStorageKey
        )
        return try decoder.decode(Chapter.self, from: Data(contentsOf: url))
    }

    func save(novel: Novel, chapters: [Chapter]) throws {
        try ensureDirectory()

        let chapterIDs = chapters.map(\.id)
        guard Set(chapterIDs).count == chapterIDs.count else {
            let duplicate = Dictionary(grouping: chapterIDs, by: { $0 })
                .first(where: { $0.value.count > 1 })?.key ?? "unknown"
            throw OfflineLibraryStoreError.duplicateChapterIdentifier(duplicate)
        }

        var updatedIndex = try loadIndex()
        updatedIndex.chapters = updatedIndex.chapters.filter { $0.value.novelID != novel.id }

        let novelStorageKey = Self.storageKey(for: novel.id)
        for chapter in chapters {
            if let existing = updatedIndex.chapters[chapter.id], existing.novelID != novel.id {
                throw OfflineLibraryStoreError.duplicateChapterIdentifier(chapter.id)
            }
            updatedIndex.chapters[chapter.id] = ChapterLocation(
                novelID: novel.id,
                novelStorageKey: novelStorageKey,
                chapterStorageKey: Self.storageKey(for: chapter.id)
            )
        }

        let downloadedAt = Date()
        updatedIndex.novels[novel.id] = NovelRecord(
            novel: novel,
            storageKey: novelStorageKey,
            chapterCount: chapters.count,
            downloadedAt: downloadedAt,
            coversWholeNovel: true
        )

        let stagingDirectory = directory.appendingPathComponent(
            ".staging-\(UUID().uuidString)",
            isDirectory: true
        )
        let stagedChapterDirectory = stagingDirectory.appendingPathComponent(
            "chapters",
            isDirectory: true
        )
        let destinationDirectory = novelDirectory(storageKey: novelStorageKey)
        let backupDirectory = directory.appendingPathComponent(
            ".backup-\(UUID().uuidString)",
            isDirectory: true
        )

        do {
            try FileManager.default.createDirectory(
                at: stagedChapterDirectory,
                withIntermediateDirectories: true
            )

            let chapterSummaries = chapters.map {
                Chapter(
                    id: $0.id,
                    chapterNumber: $0.chapterNumber,
                    title: $0.title,
                    content: nil,
                    url: $0.url
                )
            }
            try encoder.encode(chapterSummaries).write(
                to: stagingDirectory.appendingPathComponent("chapter-list", conformingTo: .json),
                options: [.atomic]
            )

            for chapter in chapters {
                let chapterStorageKey = Self.storageKey(for: chapter.id)
                try encoder.encode(chapter).write(
                    to: stagedChapterDirectory.appendingPathComponent(
                        chapterStorageKey,
                        conformingTo: .json
                    ),
                    options: [.atomic]
                )
            }

            if FileManager.default.fileExists(atPath: destinationDirectory.path) {
                try FileManager.default.moveItem(at: destinationDirectory, to: backupDirectory)
            }

            do {
                try FileManager.default.moveItem(at: stagingDirectory, to: destinationDirectory)
                try writeIndex(updatedIndex)
                if FileManager.default.fileExists(atPath: backupDirectory.path) {
                    try? FileManager.default.removeItem(at: backupDirectory)
                }
            } catch {
                if FileManager.default.fileExists(atPath: destinationDirectory.path) {
                    try? FileManager.default.removeItem(at: destinationDirectory)
                }
                if FileManager.default.fileExists(atPath: backupDirectory.path) {
                    try? FileManager.default.moveItem(at: backupDirectory, to: destinationDirectory)
                }
                throw error
            }
        } catch {
            if FileManager.default.fileExists(atPath: stagingDirectory.path) {
                try? FileManager.default.removeItem(at: stagingDirectory)
            }
            throw error
        }
    }

    /// Adds chapters to a novel's download without rewriting the chapters
    /// already saved, creating the download when there is none. Chapter
    /// files are written before the index, so an interrupted add leaves only
    /// unreferenced files that the next add overwrites.
    func add(novel: Novel, chapters: [Chapter], coversWholeNovel: Bool? = nil) throws {
        var updatedIndex = try loadIndex()
        let existing = updatedIndex.novels[novel.id]
        guard existing != nil || !chapters.isEmpty else { return }

        let chapterIDs = chapters.map(\.id)
        guard Set(chapterIDs).count == chapterIDs.count else {
            let duplicate = Dictionary(grouping: chapterIDs, by: { $0 })
                .first(where: { $0.value.count > 1 })?.key ?? "unknown"
            throw OfflineLibraryStoreError.duplicateChapterIdentifier(duplicate)
        }
        for chapter in chapters {
            if let location = updatedIndex.chapters[chapter.id], location.novelID != novel.id {
                throw OfflineLibraryStoreError.duplicateChapterIdentifier(chapter.id)
            }
        }

        let novelStorageKey = existing?.storageKey ?? Self.storageKey(for: novel.id)
        let chapterDirectory = novelDirectory(storageKey: novelStorageKey)
            .appendingPathComponent("chapters", isDirectory: true)
        try FileManager.default.createDirectory(at: chapterDirectory, withIntermediateDirectories: true)

        for chapter in chapters {
            let chapterStorageKey = Self.storageKey(for: chapter.id)
            try encoder.encode(chapter).write(
                to: chapterDirectory.appendingPathComponent(chapterStorageKey, conformingTo: .json),
                options: [.atomic]
            )
            updatedIndex.chapters[chapter.id] = ChapterLocation(
                novelID: novel.id,
                novelStorageKey: novelStorageKey,
                chapterStorageKey: chapterStorageKey
            )
        }

        var summariesByID: [String: Chapter] = [:]
        if existing != nil,
           let data = try? Data(contentsOf: chapterListURL(novelStorageKey: novelStorageKey)),
           let saved = try? decoder.decode([Chapter].self, from: data) {
            for summary in saved { summariesByID[summary.id] = summary }
        }
        for chapter in chapters {
            summariesByID[chapter.id] = Chapter(
                id: chapter.id,
                chapterNumber: chapter.chapterNumber,
                title: chapter.title,
                content: nil,
                url: chapter.url
            )
        }
        let summaries = summariesByID.values.sorted { $0.chapterNumber < $1.chapterNumber }
        try encoder.encode(summaries).write(
            to: chapterListURL(novelStorageKey: novelStorageKey),
            options: [.atomic]
        )

        updatedIndex.novels[novel.id] = NovelRecord(
            novel: novel,
            storageKey: novelStorageKey,
            chapterCount: summaries.count,
            downloadedAt: chapters.isEmpty ? existing?.downloadedAt ?? Date() : Date(),
            coversWholeNovel: coversWholeNovel ?? existing.map { $0.coversWholeNovel ?? true } ?? false
        )
        try writeIndex(updatedIndex)
    }

    func remove(novelID: String) throws {
        var updatedIndex = try loadIndex()
        guard let record = updatedIndex.novels.removeValue(forKey: novelID) else { return }
        updatedIndex.chapters = updatedIndex.chapters.filter { $0.value.novelID != novelID }

        let sourceDirectory = novelDirectory(storageKey: record.storageKey)
        let removalDirectory = directory.appendingPathComponent(
            ".removing-\(UUID().uuidString)",
            isDirectory: true
        )

        if FileManager.default.fileExists(atPath: sourceDirectory.path) {
            try FileManager.default.moveItem(at: sourceDirectory, to: removalDirectory)
        }

        do {
            try writeIndex(updatedIndex)
            if FileManager.default.fileExists(atPath: removalDirectory.path) {
                try? FileManager.default.removeItem(at: removalDirectory)
            }
        } catch {
            if FileManager.default.fileExists(atPath: removalDirectory.path) {
                try? FileManager.default.moveItem(at: removalDirectory, to: sourceDirectory)
            }
            throw error
        }
    }

    static func storageKey(for identifier: String) -> String {
        SHA256.hash(data: Data(identifier.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func loadIndex() throws -> LibraryIndex {
        if let cachedIndex { return cachedIndex }
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            let empty = LibraryIndex()
            cachedIndex = empty
            return empty
        }

        let index = try decoder.decode(LibraryIndex.self, from: Data(contentsOf: indexURL))
        guard index.schemaVersion == LibraryIndex.currentSchemaVersion else {
            throw OfflineLibraryStoreError.unsupportedSchema(index.schemaVersion)
        }
        cachedIndex = index
        return index
    }

    private func writeIndex(_ index: LibraryIndex) throws {
        try ensureDirectory()
        try encoder.encode(index).write(to: indexURL, options: [.atomic])
        cachedIndex = index
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    private var indexURL: URL {
        directory.appendingPathComponent("library-index", conformingTo: .json)
    }

    private func novelDirectory(storageKey: String) -> URL {
        directory.appendingPathComponent(storageKey, isDirectory: true)
    }

    private func chapterListURL(novelStorageKey: String) -> URL {
        novelDirectory(storageKey: novelStorageKey)
            .appendingPathComponent("chapter-list", conformingTo: .json)
    }

    private func chapterURL(novelStorageKey: String, chapterStorageKey: String) -> URL {
        novelDirectory(storageKey: novelStorageKey)
            .appendingPathComponent("chapters", isDirectory: true)
            .appendingPathComponent(chapterStorageKey, conformingTo: .json)
    }
}
