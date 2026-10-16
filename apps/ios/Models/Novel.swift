import Foundation

struct Novel: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let author: String?
    let rank: String?
    let totalChapters: String?
    let views: String?
    let bookmarks: String?
    let status: String?
    let genres: [String]?
    let summary: String?
    let imageUrl: String?
    let rating: Double?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case title, author, rank, totalChapters, views, bookmarks
        case status, genres, summary, imageUrl, rating
    }

    var rankPosition: Int {
        Self.rankPosition(from: rank)
    }

    static func ranked(_ novels: [Novel]) -> [Novel] {
        novels.sorted { lhs, rhs in
            if lhs.rankPosition != rhs.rankPosition {
                return lhs.rankPosition < rhs.rankPosition
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    static func rankPosition(from raw: String?) -> Int {
        Int(raw?.filter(\.isNumber) ?? "") ?? .max
    }
}

extension Novel {
    /// The catalog's chapter count ("3172", "3,172"), when it has one.
    var catalogChapterCount: Int? {
        NovelProgress.totalChapters(catalog: totalChapters)
    }
}

// MARK: - Catalog facts

extension Novel {
    /// Whether the catalog lists the novel as still publishing.
    var isOngoing: Bool {
        status?.lowercased().contains("ongoing") == true
    }

    /// Whether the catalog lists the novel as fully published. This is the
    /// catalog's status, not whether the reader has finished it.
    var isCompleted: Bool {
        guard let status = status?.lowercased() else { return false }
        return status.contains("complete") || status.contains("finished")
    }

    /// "Ongoing", "Completed", or the catalog's own wording.
    var statusTitle: String? {
        if isOngoing { return "Ongoing" }
        if isCompleted { return "Completed" }
        let trimmed = status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed.localizedCapitalized
    }

    /// Views as a number ("766.5K" → 766500).
    var viewCount: Int { NovelCatalog.count(from: views) }

    /// Bookmarks as a number ("2.2K" → 2200).
    var bookmarkCount: Int { NovelCatalog.count(from: bookmarks) }

    /// "★ 4.3", when the catalog has a rating.
    var ratingLabel: String? {
        rating.map { "★ " + String(format: "%.1f", $0) }
    }

    /// The compact line under a poster: "★ 4.3 · 398 ch · Ongoing".
    /// Numbers are never grouped with separators.
    var compactMetadata: String {
        [
            ratingLabel,
            catalogChapterCount.map { String($0) + " ch" },
            statusTitle,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

/// Client-side shaping of the novel catalog: shelves, filters, rankings and
/// recommendations. The catalog is small (a couple of hundred titles), so
/// everything sorts the whole list in memory.
enum NovelCatalog {
    enum RankingSort: String, CaseIterable, Hashable {
        case rank = "By rank"
        case rating = "By rating"
        case views = "By views"
    }

    /// Parses catalog counts: "12345", "12,345", "1.2K", "3.4M", "987 views".
    static func count(from raw: String?) -> Int {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return 0
        }
        let compact = raw
            .replacingOccurrences(of: "views", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if let suffix = compact.last, let multiplier = ["K": 1_000.0, "M": 1_000_000.0, "B": 1_000_000_000.0][suffix] {
            let number = compact.dropLast().trimmingCharacters(in: .whitespaces)
            guard let value = Double(number) else { return 0 }
            return Int((value * multiplier).rounded())
        }
        return Int(compact.filter(\.isNumber)) ?? 0
    }

    /// Genre key for comparisons: "Sci-Fi", "sci fi" and " SCI-FI " are one genre.
    static func genreKey(_ genre: String) -> String {
        genre
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }

    static func genreKeys(of novel: Novel) -> Set<String> {
        Set((novel.genres ?? []).map { genreKey($0) }.filter { !$0.isEmpty })
    }

    /// The catalog's genres, most common first, each under its most common
    /// spelling.
    static func genres(in novels: [Novel]) -> [String] {
        var counts: [String: Int] = [:]
        var spellings: [String: [String: Int]] = [:]
        for novel in novels {
            var seen = Set<String>()
            for genre in novel.genres ?? [] {
                let trimmed = genre.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = genreKey(trimmed)
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                counts[key, default: 0] += 1
                spellings[key, default: [:]][trimmed, default: 0] += 1
            }
        }
        func display(_ key: String) -> String {
            let options = spellings[key] ?? [:]
            return options.max { lhs, rhs in
                lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
            }?.key ?? key
        }
        return counts.keys
            .sorted { lhs, rhs in
                let left = counts[lhs] ?? 0
                let right = counts[rhs] ?? 0
                return left != right ? left > right : lhs < rhs
            }
            .map(display)
    }

    /// Most read first: views, then rating, then the catalog's rank.
    static func byPopularity(_ novels: [Novel]) -> [Novel] {
        novels.sorted { lhs, rhs in
            if lhs.viewCount != rhs.viewCount { return lhs.viewCount > rhs.viewCount }
            if (lhs.rating ?? 0) != (rhs.rating ?? 0) { return (lhs.rating ?? 0) > (rhs.rating ?? 0) }
            return rankedBefore(lhs, rhs)
        }
    }

    /// Highest rated first. Unrated titles are left out.
    static func topRated(_ novels: [Novel]) -> [Novel] {
        novels
            .filter { $0.rating != nil }
            .sorted { lhs, rhs in
                if lhs.rating != rhs.rating { return (lhs.rating ?? 0) > (rhs.rating ?? 0) }
                if lhs.viewCount != rhs.viewCount { return lhs.viewCount > rhs.viewCount }
                return rankedBefore(lhs, rhs)
            }
    }

    static func ongoing(_ novels: [Novel]) -> [Novel] {
        byPopularity(novels.filter(\.isOngoing))
    }

    static func completed(_ novels: [Novel]) -> [Novel] {
        byPopularity(novels.filter(\.isCompleted))
    }

    /// Titles tagged with `genre`, most read first.
    static func filter(_ novels: [Novel], genre: String) -> [Novel] {
        let key = genreKey(genre)
        return byPopularity(novels.filter { genreKeys(of: $0).contains(key) })
    }

    /// Title, author or genre contains the query, best ranked first.
    static func search(_ novels: [Novel], query: String) -> [Novel] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return Novel.ranked(novels) }
        let key = genreKey(needle)
        return Novel.ranked(novels.filter { novel in
            novel.title.localizedCaseInsensitiveContains(needle)
                || (novel.author?.localizedCaseInsensitiveContains(needle) ?? false)
                || genreKeys(of: novel).contains(key)
        })
    }

    static func ranking(_ novels: [Novel], by sort: RankingSort) -> [Novel] {
        switch sort {
        case .rank: Novel.ranked(novels)
        case .rating: topRated(novels) + byPopularity(novels.filter { $0.rating == nil })
        case .views: byPopularity(novels)
        }
    }

    /// "More like this": titles sharing the most genres with `novel`, then
    /// the best rated. Titles sharing no genre are left out.
    static func similar(to novel: Novel, in catalog: [Novel], limit: Int = 12) -> [Novel] {
        let keys = genreKeys(of: novel)
        guard !keys.isEmpty else { return [] }
        var seen: Set<String> = [novel.id]
        let scored = catalog.compactMap { candidate -> (novel: Novel, shared: Int)? in
            guard seen.insert(candidate.id).inserted else { return nil }
            let shared = genreKeys(of: candidate).intersection(keys).count
            return shared > 0 ? (candidate, shared) : nil
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.shared != rhs.shared { return lhs.shared > rhs.shared }
                if (lhs.novel.rating ?? 0) != (rhs.novel.rating ?? 0) {
                    return (lhs.novel.rating ?? 0) > (rhs.novel.rating ?? 0)
                }
                if lhs.novel.viewCount != rhs.novel.viewCount { return lhs.novel.viewCount > rhs.novel.viewCount }
                return rankedBefore(lhs.novel, rhs.novel)
            }
            .prefix(limit)
            .map(\.novel)
    }

    /// Titles worth a billboard: they have artwork, match the reader's
    /// genres, and rate well. Titles with a synopsis lead.
    static func featured(_ novels: [Novel], preferredGenres: Set<String>, limit: Int = 10) -> [Novel] {
        let withArt = novels.filter { !($0.imageUrl ?? "").isEmpty }
        let ordered = NovelPersonalizer.order(withArt, preferredGenres: preferredGenres)
        let hasSummary: (Novel) -> Bool = { !($0.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return Array((ordered.filter(hasSummary) + ordered.filter { !hasSummary($0) }).prefix(limit))
    }

    /// Up to `count` genres for Discover shelves: the reader's own picks
    /// first (when the catalog has enough of them), then the most common.
    static func shelfGenres(
        _ novels: [Novel],
        preferred: [String],
        count: Int = 2,
        minimumTitles: Int = 4
    ) -> [String] {
        let catalogGenres = genres(in: novels)
        let sizes = Dictionary(grouping: novels.flatMap { genreKeys(of: $0) }, by: { $0 }).mapValues(\.count)
        let eligible = catalogGenres.filter { (sizes[genreKey($0)] ?? 0) >= minimumTitles }
        var picked: [String] = []
        for genre in preferred {
            let key = genreKey(genre)
            if let match = eligible.first(where: { genreKey($0) == key }),
               !picked.contains(where: { genreKey($0) == key }) {
                picked.append(match)
            }
            if picked.count == count { return picked }
        }
        for genre in eligible where !picked.contains(where: { genreKey($0) == genreKey(genre) }) {
            picked.append(genre)
            if picked.count == count { break }
        }
        return picked
    }

    private static func rankedBefore(_ lhs: Novel, _ rhs: Novel) -> Bool {
        if lhs.rankPosition != rhs.rankPosition { return lhs.rankPosition < rhs.rankPosition }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}
