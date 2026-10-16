import Foundation

/// The little a saved novel needs to stay on Bookmarks, Continue, History and
/// its detail page when the catalog has not loaded or failed. Media bookmarks
/// carry their own title and artwork; novels keep this copy instead.
struct NovelSnapshot: Codable, Hashable, Sendable {
    let id: String
    let title: String
    let author: String?
    let imageURL: String?
    let totalChapters: String?
    let genres: [String]?
    let status: String?
    /// The last time a saved novel, reading progress or history needed it.
    var lastNeededAt: Date

    init(_ novel: Novel, neededAt: Date) {
        id = novel.id
        title = novel.title
        author = novel.author
        imageURL = novel.imageURL
        totalChapters = novel.totalChapters
        genres = novel.genres
        status = novel.status
        lastNeededAt = neededAt
    }

    /// A catalog-shaped novel built from the snapshot. Fields the snapshot
    /// does not keep (summary, rating, rank) stay empty.
    var novel: Novel {
        Novel(
            id: id,
            title: title,
            author: author,
            rank: nil,
            totalChapters: totalChapters,
            views: nil,
            bookmarks: nil,
            status: status,
            genres: genres,
            summary: nil,
            imageURL: imageURL,
            rating: nil
        )
    }

    /// Whether the snapshot already matches the catalog's copy of the novel.
    func matches(_ novel: Novel) -> Bool {
        id == novel.id
            && title == novel.title
            && author == novel.author
            && imageURL == novel.imageURL
            && totalChapters == novel.totalChapters
            && genres == novel.genres
            && status == novel.status
    }
}

enum NovelSnapshots {
    /// Snapshots unused for this long are dropped.
    static let retention: TimeInterval = 180 * 24 * 60 * 60
    /// The most snapshots kept, newest first.
    static let limit = 1_000

    /// Refreshes the snapshots of the novels someone has saved, is reading or
    /// has read. Catalog novels overwrite their snapshot; novels missing from
    /// the catalog keep the last one. Snapshots no longer needed survive for
    /// `retention`, so signing out or switching accounts doesn't lose them.
    static func updated(
        _ existing: [String: NovelSnapshot],
        neededIDs: Set<String>,
        catalog: (String) -> Novel?,
        now: Date
    ) -> [String: NovelSnapshot] {
        var result = existing
        for id in neededIDs {
            if let novel = catalog(id) {
                result[id] = NovelSnapshot(novel, neededAt: now)
            } else if var snapshot = result[id] {
                snapshot.lastNeededAt = now
                result[id] = snapshot
            }
        }

        let cutoff = now.addingTimeInterval(-retention)
        result = result.filter { neededIDs.contains($0.key) || $0.value.lastNeededAt >= cutoff }
        guard result.count > limit else { return result }
        let kept = result.values
            .sorted { $0.lastNeededAt > $1.lastNeededAt }
            .prefix(limit)
        return Dictionary(uniqueKeysWithValues: kept.map { ($0.id, $0) })
    }

    /// Whether `updated` is worth writing over `saved`: a novel was added,
    /// dropped or changed, or one was last needed over a day after its saved
    /// date. Bumping the date alone on every catalog change isn't.
    static func needsWrite(
        _ updated: [String: NovelSnapshot],
        over saved: [String: NovelSnapshot]
    ) -> Bool {
        guard updated.count == saved.count else { return true }
        for (id, snapshot) in updated {
            guard let old = saved[id], old.matches(snapshot.novel) else { return true }
            if snapshot.lastNeededAt.timeIntervalSince(old.lastNeededAt) > 24 * 60 * 60 {
                return true
            }
        }
        return false
    }
}
