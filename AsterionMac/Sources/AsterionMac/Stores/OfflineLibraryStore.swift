import Foundation

actor OfflineLibraryStore {
    struct OfflineNovel: Codable, Sendable {
        let novel: Novel
        let chapters: [Chapter]
        let downloadedAt: Date
    }

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

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
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func downloadedNovelIDs() async throws -> Set<String> {
        let files = try packageURLs()
        return Set(files.map { $0.deletingPathExtension().lastPathComponent })
    }

    func downloadedNovels() async throws -> [Novel] {
        try await packages()
            .sorted { $0.downloadedAt > $1.downloadedAt }
            .map(\.novel)
    }

    func contains(novelID: String) async -> Bool {
        FileManager.default.fileExists(atPath: packageURL(for: novelID).path)
    }

    func chapters(for novelID: String) async throws -> [Chapter]? {
        try await package(for: novelID)?.chapters
    }

    func chapter(id: String) async throws -> Chapter? {
        for package in try await packages() {
            if let chapter = package.chapters.first(where: { $0.id == id }) {
                return chapter
            }
        }
        return nil
    }

    func save(novel: Novel, chapters: [Chapter]) async throws {
        try ensureDirectory()
        let package = OfflineNovel(novel: novel, chapters: chapters, downloadedAt: Date())
        let data = try encoder.encode(package)
        try data.write(to: packageURL(for: novel.id), options: [.atomic])
    }

    private func packages() async throws -> [OfflineNovel] {
        var result: [OfflineNovel] = []
        for url in try packageURLs() {
            let data = try Data(contentsOf: url)
            result.append(try decoder.decode(OfflineNovel.self, from: data))
        }
        return result
    }

    private func package(for novelID: String) async throws -> OfflineNovel? {
        let url = packageURL(for: novelID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(OfflineNovel.self, from: data)
    }

    private func packageURLs() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    private func packageURL(for novelID: String) -> URL {
        directory.appendingPathComponent(novelID, conformingTo: .json)
    }
}
