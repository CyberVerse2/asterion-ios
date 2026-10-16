import Foundation

/// Keeps `NovelSnapshot`s on this Mac so saved novels outlive a failed catalog.
actor NovelSnapshotStore {
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
            .appendingPathComponent("NovelSnapshots", isDirectory: true)
            .appendingPathComponent("snapshots.json", conformingTo: .json)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder
    }

    func load() throws -> [String: NovelSnapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let snapshots = try decoder.decode([NovelSnapshot].self, from: Data(contentsOf: fileURL))
        return Dictionary(snapshots.map { ($0.id, $0) }, uniquingKeysWith: { lhs, rhs in
            lhs.lastNeededAt >= rhs.lastNeededAt ? lhs : rhs
        })
    }

    func save(_ snapshots: [String: NovelSnapshot]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let ordered = snapshots.values.sorted { $0.id < $1.id }
        try encoder.encode(ordered).write(to: fileURL, options: [.atomic])
    }
}
