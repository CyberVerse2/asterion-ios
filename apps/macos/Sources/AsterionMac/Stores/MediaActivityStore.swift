import Foundation

struct LocalMediaBookmarkMutation: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let ownerID: String
    let item: MediaItemDescriptor
    let isSaved: Bool
    let clientEventAt: Date
    let previousBookmark: MediaBookmark?
}

struct LocalMediaPlaybackEvent: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let ownerID: String
    let playback: MediaPlaybackDescriptor
    let positionSeconds: Double
    let durationSeconds: Double
    let completed: Bool?
    let started: Bool
    let sessionID: String
    let clientEventAt: Date
}

struct RejectedMediaActivity: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case bookmark
        case playback
    }

    let id: String
    let kind: Kind
    let mediaType: MediaAccountType
    let contentID: String
    let unitID: String?
    let title: String
    let message: String
    let rejectedAt: Date
}

struct LocalMediaAccountSnapshot: Sendable {
    let bookmarks: [MediaBookmark]
    let progress: [MediaPlaybackProgress]
    let history: [MediaHistoryEntry]
    let stats: MediaAccountStats
    let rejectedItems: [RejectedMediaActivity]
}

actor MediaActivityStore {
    private static let maximumPlaybackSeconds = 7 * 24 * 60 * 60.0
    private static let countedSessionLimit = 4_096
    private static let countedSessionRetention = 90 * 24 * 60 * 60.0
    private static let rejectedItemLimit = 50
    private static let historyLimit = 500

    private struct StoredState: Codable {
        var owners: [String: OwnerState] = [:]
    }

    private struct OwnerState: Codable {
        var bookmarks: [MediaBookmark] = []
        var progress: [MediaPlaybackProgress] = []
        var history: [MediaHistoryEntry] = []
        var pendingBookmarkMutations: [LocalMediaBookmarkMutation] = []
        var pendingEvents: [LocalMediaPlaybackEvent] = []
        var countedSessionStartedAt: [String: Date] = [:]
        var rejectedItems: [RejectedMediaActivity] = []
        var stats: MediaAccountStats?
    }

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
            .appendingPathComponent("MediaActivity", isDirectory: true)
            .appendingPathComponent("activity.json", conformingTo: .json)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder
    }

    func snapshot(ownerID: String) throws -> LocalMediaAccountSnapshot {
        var owner = try read().owners[ownerID] ?? OwnerState()
        updateStats(&owner)
        return LocalMediaAccountSnapshot(
            bookmarks: owner.bookmarks.sorted { $0.updatedAt > $1.updatedAt },
            progress: owner.progress.sorted { $0.clientUpdatedAt > $1.clientUpdatedAt },
            history: owner.history.sorted { $0.lastViewedAt > $1.lastViewedAt },
            stats: owner.stats ?? .empty,
            rejectedItems: owner.rejectedItems.sorted { $0.rejectedAt > $1.rejectedAt }
        )
    }

    func pendingBookmarkMutations(ownerID: String) throws -> [LocalMediaBookmarkMutation] {
        let owner = try read().owners[ownerID] ?? OwnerState()
        return owner.pendingBookmarkMutations.sorted { $0.clientEventAt < $1.clientEventAt }
    }

    func pendingEvents(ownerID: String) throws -> [LocalMediaPlaybackEvent] {
        let owner = try read().owners[ownerID] ?? OwnerState()
        return owner.pendingEvents.sorted { $0.clientEventAt < $1.clientEventAt }
    }

    @discardableResult
    func recordBookmark(
        ownerID: String,
        item: MediaItemDescriptor,
        isSaved: Bool,
        clientEventAt: Date
    ) throws -> LocalMediaBookmarkMutation {
        var state = try read()
        var owner = state.owners[ownerID] ?? OwnerState()
        let existing = owner.bookmarks.first { $0.key == item.key }
        owner.rejectedItems.removeAll {
            $0.kind == .bookmark
                && $0.mediaType == item.mediaType
                && $0.contentID == item.contentID
        }
        owner.bookmarks.removeAll { $0.key == item.key }
        if isSaved {
            owner.bookmarks.append(
                MediaBookmark(
                    id: existing?.id ?? "local-bookmark-\(UUID().uuidString)",
                    userId: ownerID,
                    mediaType: item.mediaType,
                    contentId: item.contentID,
                    title: item.title,
                    subtitle: item.subtitle,
                    imageURL: item.imageURL,
                    createdAt: existing?.createdAt ?? clientEventAt,
                    updatedAt: clientEventAt
                )
            )
        }

        let mutation = LocalMediaBookmarkMutation(
            id: UUID().uuidString,
            ownerID: ownerID,
            item: item,
            isSaved: isSaved,
            clientEventAt: clientEventAt,
            previousBookmark: existing
        )
        owner.pendingBookmarkMutations.removeAll { $0.item.key == item.key }
        owner.pendingBookmarkMutations.append(mutation)
        updateStats(&owner)
        state.owners[ownerID] = owner
        try write(state)
        return mutation
    }

    @discardableResult
    func rejectBookmarkMutation(
        ownerID: String,
        mutation: LocalMediaBookmarkMutation,
        message: String,
        rejectedAt: Date
    ) throws -> Bool {
        var state = try read()
        guard var owner = state.owners[ownerID] else { return false }
        owner.pendingBookmarkMutations.removeAll { $0.id == mutation.id }
        let newerMutation = owner.pendingBookmarkMutations.last {
            $0.item.key == mutation.item.key
        }
        if newerMutation == nil {
            owner.bookmarks.removeAll { $0.key == mutation.item.key }
            if let previous = mutation.previousBookmark {
                owner.bookmarks.append(previous)
            }
            appendRejection(
                RejectedMediaActivity(
                    id: UUID().uuidString,
                    kind: .bookmark,
                    mediaType: mutation.item.mediaType,
                    contentID: mutation.item.contentID,
                    unitID: nil,
                    title: mutation.item.title,
                    message: message,
                    rejectedAt: rejectedAt
                ),
                to: &owner
            )
        }
        updateStats(&owner)
        state.owners[ownerID] = owner
        try write(state)
        return newerMutation == nil
    }

    func resolveBookmarkMutation(
        ownerID: String,
        mutationID: String,
        key: MediaAccountKey,
        result: MediaBookmarkMutationResult
    ) throws {
        var state = try read()
        guard var owner = state.owners[ownerID] else { return }
        owner.pendingBookmarkMutations.removeAll { $0.id == mutationID }
        let newerMutation = owner.pendingBookmarkMutations.last { $0.item.key == key }
        if newerMutation == nil {
            owner.bookmarks.removeAll { $0.key == key }
            if result.isSaved, let bookmark = result.bookmark {
                owner.bookmarks.append(bookmark)
            }
            owner.rejectedItems.removeAll {
                $0.kind == .bookmark
                    && $0.mediaType == key.mediaType
                    && $0.contentID == key.contentID
            }
        }
        updateStats(&owner)
        state.owners[ownerID] = owner
        try write(state)
    }

    @discardableResult
    func record(
        ownerID: String,
        playback: MediaPlaybackDescriptor,
        positionSeconds: Double,
        durationSeconds: Double,
        completed: Bool?,
        started: Bool,
        sessionID: String,
        clientEventAt: Date
    ) throws -> LocalMediaPlaybackEvent {
        var state = try read()
        var owner = state.owners[ownerID] ?? OwnerState()
        owner.rejectedItems.removeAll {
            $0.kind == .playback
                && $0.mediaType == playback.item.mediaType
                && $0.contentID == playback.item.contentID
                && $0.unitID == playback.unitID
        }
        pruneCountedSessions(&owner, relativeTo: clientEventAt)

        let boundedDuration = max(0, min(durationSeconds, Self.maximumPlaybackSeconds))
        let maximumPosition = boundedDuration > 0
            ? boundedDuration
            : Self.maximumPlaybackSeconds
        let boundedPosition = max(0, min(positionSeconds, maximumPosition))
        let percentage = boundedDuration > 0
            ? min(100, boundedPosition / boundedDuration * 100)
            : 0
        let isCompleted = completed ?? (percentage >= 90)
        let progressIndex = owner.progress.firstIndex { $0.key == playback.item.key }
        let previousProgress = progressIndex.map { owner.progress[$0] }

        if previousProgress == nil || clientEventAt >= previousProgress!.clientUpdatedAt {
            let progress = MediaPlaybackProgress(
                id: previousProgress?.id ?? "local-progress-\(UUID().uuidString)",
                userId: ownerID,
                mediaType: playback.item.mediaType,
                contentId: playback.item.contentID,
                title: playback.item.title,
                imageURL: playback.item.imageURL,
                unitId: playback.unitID,
                unitTitle: playback.unitTitle,
                seasonNumber: playback.seasonNumber,
                episodeNumber: playback.episodeNumber,
                positionSeconds: boundedPosition,
                durationSeconds: boundedDuration,
                percentage: percentage,
                completed: isCompleted,
                clientUpdatedAt: clientEventAt,
                createdAt: previousProgress?.createdAt ?? clientEventAt,
                updatedAt: clientEventAt
            )
            if let progressIndex {
                owner.progress[progressIndex] = progress
            } else {
                owner.progress.append(progress)
            }
        }

        let historyIndex = owner.history.firstIndex {
            $0.mediaType == playback.item.mediaType
                && $0.contentId == playback.item.contentID
                && $0.unitId == playback.unitID
        }
        let previousHistory = historyIndex.map { owner.history[$0] }
        let countsSession = started
            && owner.countedSessionStartedAt.updateValue(clientEventAt, forKey: sessionID) == nil
        let metadataIsNewer = previousHistory.map { clientEventAt >= $0.clientUpdatedAt } ?? true
        let history = MediaHistoryEntry(
            id: previousHistory?.id ?? "local-history-\(UUID().uuidString)",
            userId: ownerID,
            mediaType: playback.item.mediaType,
            contentId: playback.item.contentID,
            title: metadataIsNewer ? playback.item.title : previousHistory?.title ?? playback.item.title,
            imageURL: metadataIsNewer ? playback.item.imageURL : previousHistory?.imageURL,
            unitId: playback.unitID,
            unitTitle: metadataIsNewer ? playback.unitTitle : previousHistory?.unitTitle,
            seasonNumber: metadataIsNewer ? playback.seasonNumber : previousHistory?.seasonNumber,
            episodeNumber: metadataIsNewer ? playback.episodeNumber : previousHistory?.episodeNumber,
            positionSeconds: max(previousHistory?.positionSeconds ?? 0, boundedPosition),
            durationSeconds: max(previousHistory?.durationSeconds ?? 0, boundedDuration),
            percentage: max(previousHistory?.percentage ?? 0, percentage),
            completed: previousHistory?.completed == true || isCompleted,
            visitCount: (previousHistory?.visitCount ?? 0) + (countsSession ? 1 : 0),
            clientUpdatedAt: max(previousHistory?.clientUpdatedAt ?? clientEventAt, clientEventAt),
            firstViewedAt: min(previousHistory?.firstViewedAt ?? clientEventAt, clientEventAt),
            lastViewedAt: max(previousHistory?.lastViewedAt ?? clientEventAt, clientEventAt),
            createdAt: previousHistory?.createdAt ?? clientEventAt,
            updatedAt: max(previousHistory?.updatedAt ?? clientEventAt, clientEventAt)
        )
        if let historyIndex {
            owner.history[historyIndex] = history
        } else {
            owner.history.append(history)
        }
        pruneHistory(&owner)

        if var stats = owner.stats {
            if previousHistory == nil { stats.historyEntries += 1 }
            if previousHistory?.completed != true, history.completed {
                switch history.mediaType {
                case .anime: stats.animeEpisodesCompleted += 1
                case .movie: stats.movieUnitsCompleted += 1
                case .football: break
                }
            }
            let cutoff = clientEventAt.addingTimeInterval(-30 * 24 * 60 * 60)
            if previousHistory?.lastViewedAt ?? .distantPast < cutoff,
               history.lastViewedAt >= cutoff {
                stats.activityLast30Days += 1
            }
            owner.stats = stats
        }

        let event = LocalMediaPlaybackEvent(
            id: UUID().uuidString,
            ownerID: ownerID,
            playback: playback,
            positionSeconds: boundedPosition,
            durationSeconds: boundedDuration,
            completed: isCompleted,
            started: started,
            sessionID: sessionID,
            clientEventAt: clientEventAt
        )
        if let pendingIndex = owner.pendingEvents.lastIndex(where: {
            $0.playback.item.key == playback.item.key
                && $0.playback.unitID == playback.unitID
                && $0.sessionID == sessionID
        }) {
            let pending = owner.pendingEvents[pendingIndex]
            let latest = event.clientEventAt >= pending.clientEventAt ? event : pending
            let mergedCompleted = event.completed == true || pending.completed == true
                ? true
                : latest.completed
            owner.pendingEvents[pendingIndex] = LocalMediaPlaybackEvent(
                id: latest.id,
                ownerID: latest.ownerID,
                playback: latest.playback,
                positionSeconds: latest.positionSeconds,
                durationSeconds: latest.durationSeconds,
                completed: mergedCompleted,
                started: event.started || pending.started,
                sessionID: latest.sessionID,
                clientEventAt: latest.clientEventAt
            )
        } else {
            owner.pendingEvents.append(event)
        }

        updateStats(&owner)
        state.owners[ownerID] = owner
        try write(state)
        return owner.pendingEvents.first {
            $0.playback.item.key == playback.item.key
                && $0.playback.unitID == playback.unitID
                && $0.sessionID == sessionID
        } ?? event
    }

    @discardableResult
    func rejectPlaybackEvent(
        ownerID: String,
        event: LocalMediaPlaybackEvent,
        message: String,
        rejectedAt: Date
    ) throws -> Bool {
        var state = try read()
        guard var owner = state.owners[ownerID] else { return false }
        owner.pendingEvents.removeAll { $0.id == event.id }
        let newerEvent = owner.pendingEvents.contains {
            $0.playback.item.key == event.playback.item.key
                && $0.playback.unitID == event.playback.unitID
                && $0.clientEventAt > event.clientEventAt
        }
        if !newerEvent {
            appendRejection(
                RejectedMediaActivity(
                    id: UUID().uuidString,
                    kind: .playback,
                    mediaType: event.playback.item.mediaType,
                    contentID: event.playback.item.contentID,
                    unitID: event.playback.unitID,
                    title: event.playback.item.title,
                    message: message,
                    rejectedAt: rejectedAt
                ),
                to: &owner
            )
        }
        state.owners[ownerID] = owner
        try write(state)
        return !newerEvent
    }

    func acknowledge(ownerID: String, eventID: String) throws {
        var state = try read()
        guard var owner = state.owners[ownerID] else { return }
        let acknowledged = owner.pendingEvents.first { $0.id == eventID }
        owner.pendingEvents.removeAll { $0.id == eventID }
        if let acknowledged {
            owner.rejectedItems.removeAll {
                $0.kind == .playback
                    && $0.mediaType == acknowledged.playback.item.mediaType
                    && $0.contentID == acknowledged.playback.item.contentID
                    && $0.unitID == acknowledged.playback.unitID
            }
        }
        state.owners[ownerID] = owner
        try write(state)
    }

    func mergeRemote(
        ownerID: String,
        bookmarks: [MediaBookmark]? = nil,
        progress: [MediaPlaybackProgress],
        history: [MediaHistoryEntry],
        stats: MediaAccountStats?
    ) throws {
        var state = try read()
        var owner = state.owners[ownerID] ?? OwnerState()

        if let bookmarks {
            let pendingByKey = Dictionary(
                uniqueKeysWithValues: owner.pendingBookmarkMutations.map { ($0.item.key, $0) }
            )
            let pendingSaved = owner.bookmarks.filter {
                pendingByKey[$0.key]?.isSaved == true
            }
            owner.bookmarks = bookmarks.filter { pendingByKey[$0.key] == nil } + pendingSaved
        }

        for remote in progress {
            if let index = owner.progress.firstIndex(where: { $0.key == remote.key }) {
                if remote.clientUpdatedAt >= owner.progress[index].clientUpdatedAt {
                    owner.progress[index] = remote
                }
            } else {
                owner.progress.append(remote)
            }
        }

        for remote in history {
            if let index = owner.history.firstIndex(where: {
                $0.mediaType == remote.mediaType
                    && $0.contentId == remote.contentId
                    && $0.unitId == remote.unitId
            }) {
                owner.history[index] = mergeHistory(local: owner.history[index], remote: remote)
            } else {
                owner.history.append(remote)
            }
        }
        pruneHistory(&owner)
        if let stats { owner.stats = stats }
        updateStats(&owner)
        state.owners[ownerID] = owner
        try write(state)
    }

    private func mergeHistory(
        local: MediaHistoryEntry,
        remote: MediaHistoryEntry
    ) -> MediaHistoryEntry {
        let latest = remote.clientUpdatedAt >= local.clientUpdatedAt ? remote : local
        return MediaHistoryEntry(
            id: remote.id,
            userId: remote.userId,
            mediaType: latest.mediaType,
            contentId: latest.contentId,
            title: latest.title,
            imageURL: latest.imageURL,
            unitId: latest.unitId,
            unitTitle: latest.unitTitle,
            seasonNumber: latest.seasonNumber,
            episodeNumber: latest.episodeNumber,
            positionSeconds: max(local.positionSeconds, remote.positionSeconds),
            durationSeconds: max(local.durationSeconds, remote.durationSeconds),
            percentage: max(local.percentage, remote.percentage),
            completed: local.completed || remote.completed,
            visitCount: max(local.visitCount, remote.visitCount),
            clientUpdatedAt: max(local.clientUpdatedAt, remote.clientUpdatedAt),
            firstViewedAt: min(local.firstViewedAt, remote.firstViewedAt),
            lastViewedAt: max(local.lastViewedAt, remote.lastViewedAt),
            createdAt: min(local.createdAt, remote.createdAt),
            updatedAt: max(local.updatedAt, remote.updatedAt)
        )
    }

    private func updateStats(_ owner: inout OwnerState) {
        var stats = owner.stats ?? .empty
        stats.savedAnime = owner.bookmarks.count { $0.mediaType == .anime }
        stats.savedMovies = owner.bookmarks.count { $0.mediaType == .movie }
        stats.savedMatches = owner.bookmarks.count { $0.mediaType == .football }
        stats.titlesInProgress = owner.progress.count { !$0.completed }
        stats.animeEpisodesCompleted = max(
            stats.animeEpisodesCompleted,
            owner.history.count { $0.mediaType == .anime && $0.completed }
        )
        stats.movieUnitsCompleted = max(
            stats.movieUnitsCompleted,
            owner.history.count { $0.mediaType == .movie && $0.completed }
        )
        stats.historyEntries = max(stats.historyEntries, owner.history.count)
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        stats.activityLast30Days = max(
            stats.activityLast30Days,
            owner.history.count { $0.lastViewedAt >= thirtyDaysAgo }
        )
        owner.stats = stats
    }

    private func pruneCountedSessions(_ owner: inout OwnerState, relativeTo eventDate: Date) {
        let cutoff = eventDate.addingTimeInterval(-Self.countedSessionRetention)
        owner.countedSessionStartedAt = owner.countedSessionStartedAt.filter { $0.value >= cutoff }
        guard owner.countedSessionStartedAt.count >= Self.countedSessionLimit else { return }
        owner.countedSessionStartedAt = Dictionary(
            uniqueKeysWithValues: owner.countedSessionStartedAt
                .sorted { $0.value > $1.value }
                .prefix(Self.countedSessionLimit - 1)
                .map { ($0.key, $0.value) }
        )
    }

    private func pruneHistory(_ owner: inout OwnerState) {
        guard owner.history.count > Self.historyLimit else { return }
        owner.history = Array(
            owner.history
                .sorted { $0.lastViewedAt > $1.lastViewedAt }
                .prefix(Self.historyLimit)
        )
    }

    private func appendRejection(
        _ rejection: RejectedMediaActivity,
        to owner: inout OwnerState
    ) {
        owner.rejectedItems.removeAll {
            $0.kind == rejection.kind
                && $0.mediaType == rejection.mediaType
                && $0.contentID == rejection.contentID
                && $0.unitID == rejection.unitID
        }
        owner.rejectedItems.append(rejection)
        if owner.rejectedItems.count > Self.rejectedItemLimit {
            owner.rejectedItems = Array(
                owner.rejectedItems
                    .sorted { $0.rejectedAt > $1.rejectedAt }
                    .prefix(Self.rejectedItemLimit)
            )
        }
    }

    private func read() throws -> StoredState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return StoredState() }
        return try decoder.decode(StoredState.self, from: Data(contentsOf: fileURL))
    }

    private func write(_ state: StoredState) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(state).write(to: fileURL, options: .atomic)
    }
}
