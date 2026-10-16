import Foundation

/// The chapters each owner (an account, or "device" when signed out) has
/// read on this Mac, plus what synced from the account.
actor ReadingHistoryStore {
    private struct StoredState: Codable {
        var owners: [String: [ReadingHistoryEntry]] = [:]
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var cachedState: StoredState?

    init(fileURL: URL? = nil) {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        self.fileURL = fileURL ?? baseDirectory
            .appendingPathComponent("Asterion", isDirectory: true)
            .appendingPathComponent("ReadingHistory", isDirectory: true)
            .appendingPathComponent("history.json", conformingTo: .json)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder
    }

    func entries(ownerID: String) throws -> [ReadingHistoryEntry] {
        try read().owners[ownerID] ?? []
    }

    @discardableResult
    func record(ownerID: String, visit: ReadingHistory.Visit) throws -> [ReadingHistoryEntry] {
        try update(ownerID: ownerID) { ReadingHistory.recording(visit, into: $0) }
    }

    @discardableResult
    func merge(ownerID: String, remote rows: [RemoteReadingHistoryRow]) throws -> [ReadingHistoryEntry] {
        guard !rows.isEmpty else { return try entries(ownerID: ownerID) }
        return try update(ownerID: ownerID) { ReadingHistory.merging(remote: rows, into: $0) }
    }

    /// The next batch of chapters the account hasn't seen.
    func pendingUploads(
        ownerID: String,
        limit: Int = ReadingHistory.uploadBatchLimit
    ) throws -> [ReadingHistory.Upload] {
        ReadingHistory.pendingUploads(in: try entries(ownerID: ownerID), limit: limit)
    }

    /// Records that the account now holds `uploads`.
    @discardableResult
    func markUploaded(ownerID: String, _ uploads: [ReadingHistory.Upload]) throws -> [ReadingHistoryEntry] {
        guard !uploads.isEmpty else { return try entries(ownerID: ownerID) }
        return try update(ownerID: ownerID) { ReadingHistory.markingUploaded(uploads, in: $0) }
    }

    /// Fills in chapter numbers and titles resolved after a synced row arrived.
    @discardableResult
    func resolveChapters(
        ownerID: String,
        _ markers: [String: (number: Int, title: String)]
    ) throws -> [ReadingHistoryEntry] {
        guard !markers.isEmpty else { return try entries(ownerID: ownerID) }
        return try update(ownerID: ownerID) { entries in
            entries.map { entry in
                guard entry.chapterNumber == nil, let marker = markers[entry.chapterID] else { return entry }
                var resolved = entry
                resolved.chapterNumber = marker.number
                resolved.chapterTitle = resolved.chapterTitle ?? marker.title
                return resolved
            }
        }
    }

    private func update(
        ownerID: String,
        _ transform: ([ReadingHistoryEntry]) -> [ReadingHistoryEntry]
    ) throws -> [ReadingHistoryEntry] {
        var state = try read()
        let updated = transform(state.owners[ownerID] ?? [])
        state.owners[ownerID] = updated
        try write(state)
        return updated
    }

    private func read() throws -> StoredState {
        if let cachedState { return cachedState }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cachedState = StoredState()
            return StoredState()
        }
        let state = try decoder.decode(StoredState.self, from: Data(contentsOf: fileURL))
        cachedState = state
        return state
    }

    private func write(_ state: StoredState) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(state).write(to: fileURL, options: [.atomic])
        cachedState = state
    }
}
