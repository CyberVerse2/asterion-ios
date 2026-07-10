import Foundation

actor ReadingProgressStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        self.fileURL = fileURL ?? baseDirectory
            .appendingPathComponent("Asterion", isDirectory: true)
            .appendingPathComponent("ReadingProgress", isDirectory: true)
            .appendingPathComponent("progress.json", conformingTo: .json)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder
    }

    func progress(ownerID: String, novelID: String) throws -> LocalReadingProgress? {
        try allProgress().first { $0.ownerID == ownerID && $0.novelID == novelID }
    }

    func progresses(ownerID: String) throws -> [LocalReadingProgress] {
        try allProgress().filter { $0.ownerID == ownerID }
    }

    func save(_ progress: LocalReadingProgress) throws {
        var entries = try allProgress()
        entries.removeAll { $0.ownerID == progress.ownerID && $0.novelID == progress.novelID }
        entries.append(progress)
        try write(entries)
    }

    func replaceProgresses(
        ownerID: String,
        with progresses: [LocalReadingProgress]
    ) throws {
        var entries = try allProgress()
        entries.removeAll { $0.ownerID == ownerID }
        entries.append(contentsOf: progresses)
        try write(entries)
    }

    private func allProgress() throws -> [LocalReadingProgress] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode(
            [LocalReadingProgress].self,
            from: Data(contentsOf: fileURL)
        )
    }

    private func write(_ entries: [LocalReadingProgress]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(entries).write(to: fileURL, options: [.atomic])
    }
}
