import Foundation

/// One saved novel. `novel` is the catalog entry as it was when saved or last
/// seen, so the shelf can still draw it offline.
public struct NovelLibraryEntry: Identifiable, Codable, Hashable, Sendable {
    public let novelId: String
    public let addedAt: Date
    public var updatedAt: Date?
    public var novel: Novel?

    public init(novelId: String, addedAt: Date, updatedAt: Date? = nil, novel: Novel? = nil) {
        self.novelId = novelId
        self.addedAt = addedAt
        self.updatedAt = updatedAt
        self.novel = novel
    }

    public var id: String { novelId }
}

/// A save or removal the account hasn't confirmed yet.
public struct NovelLibraryChange: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case add
        case remove
    }

    public let novelId: String
    public let kind: Kind
    public let at: Date

    public init(novelId: String, kind: Kind, at: Date) {
        self.novelId = novelId
        self.kind = kind
        self.at = at
    }
}

/// The novels saved on this device, plus the changes still on their way to
/// the account. A guest keeps one ledger (its pending changes are never sent);
/// signing in moves the guest's saves into the account's ledger as queued
/// adds, so nothing saved before sign-in is lost.
///
/// Each novel has at most one pending change, and the latest one wins.
public struct NovelLibraryLedger: Codable, Hashable, Sendable {
    /// Newest first.
    public private(set) var entries: [NovelLibraryEntry]
    /// Oldest first; at most one per novel.
    public private(set) var pending: [NovelLibraryChange]
    /// When the account's list was last applied; nil until the first fetch.
    public private(set) var accountSyncedAt: Date?

    public init(entries: [NovelLibraryEntry] = [], pending: [NovelLibraryChange] = [], accountSyncedAt: Date? = nil) {
        self.entries = entries
        self.pending = pending
        self.accountSyncedAt = accountSyncedAt
        sortEntries()
    }

    public var isEmpty: Bool { entries.isEmpty && pending.isEmpty }

    public var novelIds: [String] { entries.map(\.novelId) }

    public func contains(_ novelId: String) -> Bool {
        entries.contains { $0.novelId == novelId }
    }

    public func entry(for novelId: String) -> NovelLibraryEntry? {
        entries.first { $0.novelId == novelId }
    }

    // MARK: Local changes

    /// Saves the novel here and queues the save for the account. Ignored when
    /// a later change for the same novel is already queued.
    public mutating func add(_ novelId: String, novel: Novel? = nil, at date: Date = Date()) {
        guard record(NovelLibraryChange(novelId: novelId, kind: .add, at: date)) else { return }
        if let index = entries.firstIndex(where: { $0.novelId == novelId }) {
            if let novel { entries[index].novel = novel }
        } else {
            entries.append(NovelLibraryEntry(novelId: novelId, addedAt: date, updatedAt: date, novel: novel))
            sortEntries()
        }
    }

    /// Removes the novel here and queues the removal for the account.
    public mutating func remove(_ novelId: String, at date: Date = Date()) {
        guard record(NovelLibraryChange(novelId: novelId, kind: .remove, at: date)) else { return }
        entries.removeAll { $0.novelId == novelId }
    }

    /// Refreshes the stored catalog entries, so the shelf keeps current
    /// titles and covers for offline use.
    public mutating func remember(_ novels: [Novel]) {
        let byID = Dictionary(novels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for index in entries.indices {
            if let novel = byID[entries[index].novelId] { entries[index].novel = novel }
        }
    }

    // MARK: Account sync

    /// Replaces the saved list with the account's, then re-applies the
    /// changes the account hasn't confirmed, so an offline save or removal
    /// survives a refresh that raced it.
    public mutating func applyAccount(_ remote: [NovelLibraryEntry], at date: Date = Date()) {
        let known = Dictionary(entries.map { ($0.novelId, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var next: [NovelLibraryEntry] = remote.compactMap { entry in
            guard seen.insert(entry.novelId).inserted else { return nil }
            var entry = entry
            if entry.novel == nil { entry.novel = known[entry.novelId]?.novel }
            return entry
        }
        for change in pending {
            switch change.kind {
            case .add:
                guard !next.contains(where: { $0.novelId == change.novelId }) else { continue }
                next.append(known[change.novelId]
                    ?? NovelLibraryEntry(novelId: change.novelId, addedAt: change.at, updatedAt: change.at))
            case .remove:
                next.removeAll { $0.novelId == change.novelId }
            }
        }
        entries = next
        accountSyncedAt = date
        sortEntries()
    }

    /// The account confirmed `change`. A newer change for the same novel
    /// (saved again while the removal was in flight) stays queued.
    public mutating func acknowledge(_ change: NovelLibraryChange) {
        pending.removeAll { $0 == change }
    }

    /// Moves a guest's saves into this (account) ledger as queued adds.
    /// A later change already queued here for the same novel wins.
    public mutating func adopt(guest: NovelLibraryLedger) {
        for entry in guest.entries.sorted(by: { $0.addedAt < $1.addedAt }) {
            add(entry.novelId, novel: entry.novel, at: entry.addedAt)
        }
    }

    // MARK: Private

    /// Queues `change` as the novel's only pending change. False when a
    /// later change is already queued, so the caller leaves `entries` alone.
    private mutating func record(_ change: NovelLibraryChange) -> Bool {
        if let existing = pending.first(where: { $0.novelId == change.novelId }), existing.at > change.at {
            return false
        }
        pending.removeAll { $0.novelId == change.novelId }
        pending.append(change)
        return true
    }

    private mutating func sortEntries() {
        entries.sort {
            if $0.addedAt == $1.addedAt { return $0.novelId < $1.novelId }
            return $0.addedAt > $1.addedAt
        }
    }
}
