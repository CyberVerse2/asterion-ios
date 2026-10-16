import Foundation

/// Whether a novel is still publishing, read from the catalog's free-text
/// `status` ("Ongoing", "Completed", "completed ").
enum NovelStatus: String, CaseIterable, Sendable {
    case ongoing
    case completed

    init?(catalogValue: String?) {
        guard let value = catalogValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !value.isEmpty else { return nil }
        if value.hasPrefix("complete") || value == "finished" || value == "end" {
            self = .completed
        } else if value.hasPrefix("ongoing") || value == "serializing" || value == "publishing" {
            self = .ongoing
        } else {
            return nil
        }
    }

    var title: String {
        switch self {
        case .ongoing: "Ongoing"
        case .completed: "Completed"
        }
    }
}

/// How a grid of novels is ordered.
enum NovelSort: String, CaseIterable, Identifiable, Sendable {
    case popular
    case rating
    case views
    case chapters
    case title

    var id: String { rawValue }

    var title: String {
        switch self {
        case .popular: "Popular"
        case .rating: "Top rated"
        case .views: "Most read"
        case .chapters: "Most chapters"
        case .title: "Title A–Z"
        }
    }
}

/// A genre and how many catalog novels carry it.
struct NovelGenreCount: Identifiable, Equatable, Sendable {
    let genre: String
    let count: Int

    var id: String { genre.lowercased() }
}

/// One editorial shelf on the novels Discover page.
struct NovelDiscoverShelf: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Hashable, Sendable {
        case topRated
        case mostRead
        case completed
        case ongoing
        case genre(String)
    }

    let kind: Kind
    let title: String
    let subtitle: String
    let novels: [Novel]

    var id: String {
        switch kind {
        case .topRated: "top-rated"
        case .mostRead: "most-read"
        case .completed: "completed"
        case .ongoing: "ongoing"
        case .genre(let genre): "genre:\(genre.lowercased())"
        }
    }

    /// The section the shelf's "See all" opens, and the genre it selects.
    var destination: (section: AppSection, genre: String?) {
        switch kind {
        case .topRated: (.topRated, nil)
        case .mostRead: (.mostRead, nil)
        case .completed: (.completed, nil)
        case .ongoing: (.ongoing, nil)
        case .genre(let genre): (.genres, genre)
        }
    }
}

/// Everything the novels Discover page shows. Hero, Featured, and Trending
/// never share a novel, and every later shelf only uses novels not already
/// on the page, so a small catalog still reads as a full, varied page.
struct NovelDiscoverLayout: Equatable, Sendable {
    var hero: [Novel] = []
    var featured: [Novel] = []
    var trending: [Novel] = []
    var shelves: [NovelDiscoverShelf] = []

    static let empty = NovelDiscoverLayout()

    var allNovelIDs: [String] {
        (hero + featured + trending + shelves.flatMap(\.novels)).map(\.id)
    }
}

/// Novels picked for someone: their genres first, top-rated between.
struct NovelPicks: Equatable, Sendable {
    let novels: [Novel]
    /// The reader's strongest genres, most weighted first; empty when the
    /// picks are only the catalog's top rated.
    let genres: [String]
}

extension Novel {
    /// The catalog's chapter count as a number ("2969", "2,969").
    var chapterCount: Int? {
        NovelProgress.totalChapters(loaded: nil, catalog: totalChapters)
    }

    /// Views as a number; the catalog abbreviates them ("766.5K", "1.1M").
    var viewCount: Int? { NovelCatalog.abbreviatedCount(views) }

    /// Bookmarks as a number ("790", "2.2K").
    var bookmarkCount: Int? { NovelCatalog.abbreviatedCount(bookmarks) }

    var catalogStatus: NovelStatus? { NovelStatus(catalogValue: status) }

    /// Trimmed, non-empty genres without case-insensitive repeats.
    var displayGenres: [String] {
        var seen = Set<String>()
        return (genres ?? []).compactMap { raw in
            let genre = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !genre.isEmpty, seen.insert(genre.lowercased()).inserted else { return nil }
            return genre
        }
    }

    func hasGenre(_ genre: String) -> Bool {
        displayGenres.contains { $0.caseInsensitiveCompare(genre) == .orderedSame }
    }

    /// "4.4", or nil when the novel has no rating.
    var ratingLabel: String? {
        guard let rating, rating.isFinite, rating > 0 else { return nil }
        return String(format: "%.1f", rating)
    }

    /// Short tile caption: "Completed · 2969 ch". Chapter numbers are never
    /// grouped with separators.
    var catalogMetadata: String {
        let parts = [
            catalogStatus?.title,
            chapterCount.map { String($0) + " ch" },
        ].compactMap { $0 }
        return parts.isEmpty ? authorDisplayName : parts.joined(separator: " · ")
    }
}

enum NovelCatalog {
    /// Genres carried by more than this share of the catalog ("Fantasy",
    /// "Action") are too broad to make a distinct shelf.
    static let broadGenreShare = 0.6
    static let heroCount = 6
    static let featuredCount = 10
    static let trendingCount = 12
    static let shelfCount = 12
    static let minimumShelfCount = 4
    static let genreShelfCount = 3
    static let featuredMinimumRating = 4.3

    // MARK: Parsing

    /// Parses catalog counts such as "790", "2,345", "766.5K", "1M", "1.1B".
    static func abbreviatedCount(_ text: String?) -> Int? {
        guard var value = text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: ",", with: ""),
            !value.isEmpty else { return nil }

        var multiplier = 1.0
        if let suffix = value.last, let scale = ["K": 1e3, "M": 1e6, "B": 1e9][suffix] {
            multiplier = scale
            value.removeLast()
        }
        guard let number = Double(value.trimmingCharacters(in: .whitespaces)),
              number.isFinite, number >= 0 else { return nil }
        return Int((number * multiplier).rounded())
    }

    // MARK: Sorting and filtering

    static func sorted(_ novels: [Novel], by sort: NovelSort) -> [Novel] {
        novels.sorted { areInIncreasingOrder($0, $1, by: sort) }
    }

    static func areInIncreasingOrder(_ lhs: Novel, _ rhs: Novel, by sort: NovelSort) -> Bool {
        switch sort {
        case .popular:
            if lhs.numericRank != rhs.numericRank { return lhs.numericRank < rhs.numericRank }
            if let order = descending(lhs.rating, rhs.rating) { return order }
        case .rating:
            if let order = descending(lhs.rating, rhs.rating) { return order }
            if let order = descending(lhs.bookmarkCount, rhs.bookmarkCount) { return order }
            if lhs.numericRank != rhs.numericRank { return lhs.numericRank < rhs.numericRank }
        case .views:
            if let order = descending(lhs.viewCount, rhs.viewCount) { return order }
            if lhs.numericRank != rhs.numericRank { return lhs.numericRank < rhs.numericRank }
        case .chapters:
            if let order = descending(lhs.chapterCount, rhs.chapterCount) { return order }
            if lhs.numericRank != rhs.numericRank { return lhs.numericRank < rhs.numericRank }
        case .title:
            break
        }
        let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
        if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
        return lhs.id < rhs.id
    }

    /// Larger first, missing values last; nil when the two tie.
    private static func descending<Value: Comparable>(_ lhs: Value?, _ rhs: Value?) -> Bool? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?) where lhs != rhs: lhs > rhs
        case (.some, nil): true
        case (nil, .some): false
        default: nil
        }
    }

    /// The novels a section lists, in the order it lists them. Sections with
    /// their own ordering (Rankings, Top rated, Most read) ignore `sort`.
    static func novels(
        _ novels: [Novel],
        in section: AppSection,
        genre: String? = nil,
        sort: NovelSort? = nil
    ) -> [Novel] {
        let filtered: [Novel]
        switch section {
        case .discover, .rankings, .all:
            filtered = novels
        case .topRated:
            filtered = novels.filter { $0.ratingLabel != nil }
        case .mostRead:
            filtered = novels.filter { $0.viewCount != nil }
        case .ongoing:
            filtered = novels.filter { $0.catalogStatus == .ongoing }
        case .completed:
            filtered = novels.filter { $0.catalogStatus == .completed }
        case .genres:
            if let genre = genre?.trimmingCharacters(in: .whitespacesAndNewlines), !genre.isEmpty {
                filtered = novels.filter { $0.hasGenre(genre) }
            } else {
                filtered = novels
            }
        }
        let order = section.hasFixedOrder ? section.defaultSort : (sort ?? section.defaultSort)
        return sorted(filtered, by: order)
    }

    /// Every genre in the catalog, most common first, then A–Z. The first
    /// spelling seen names a genre that appears with different casing.
    static func genreCounts(_ novels: [Novel]) -> [NovelGenreCount] {
        var counts: [String: Int] = [:]
        var names: [String: String] = [:]
        for novel in novels {
            for genre in novel.displayGenres {
                let key = genre.lowercased()
                counts[key, default: 0] += 1
                if names[key] == nil { names[key] = genre }
            }
        }
        return counts
            .map { NovelGenreCount(genre: names[$0.key] ?? $0.key, count: $0.value) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.genre.localizedStandardCompare($1.genre) == .orderedAscending
            }
    }

    // MARK: Search

    /// How well a novel matches a search, best first.
    enum SearchMatch: Int, Comparable, Sendable {
        case titlePrefix
        case titleContains
        case author
        case genre

        static func < (lhs: SearchMatch, rhs: SearchMatch) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    static func match(_ novel: Novel, query rawQuery: String) -> SearchMatch? {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let title = novel.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.range(of: query, options: options.union(.anchored)) != nil { return .titlePrefix }
        if title.range(of: query, options: options) != nil { return .titleContains }
        if novel.authorDisplayName.range(of: query, options: options) != nil { return .author }
        if novel.displayGenres.contains(where: { $0.range(of: query, options: options) != nil }) {
            return .genre
        }
        return nil
    }

    /// Novels matching a search, ranked title prefix > title contains >
    /// author > genre, and by popularity inside each group.
    static func search(_ novels: [Novel], query: String) -> [Novel] {
        novels
            .compactMap { novel in match(novel, query: query).map { (novel, $0) } }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return areInIncreasingOrder(lhs.0, rhs.0, by: .popular)
            }
            .map(\.0)
    }

    // MARK: Similarity

    /// How much sharing a genre says: rare genres ("Xianxia") say more than
    /// ones nearly every novel carries ("Fantasy").
    static func genreWeights(_ novels: [Novel]) -> [String: Double] {
        let total = Double(max(novels.count, 1))
        var weights: [String: Double] = [:]
        for entry in genreCounts(novels) {
            weights[entry.genre.lowercased()] = log((total + 1) / Double(entry.count)) + 0.05
        }
        return weights
    }

    /// Novels most like `novel`: the more (and rarer) genres they share the
    /// higher they rank, then by rating. Topped up with top-rated novels when
    /// too few share a genre.
    static func recommendations(for novel: Novel, in catalog: [Novel], limit: Int = 12) -> [Novel] {
        let weights = genreWeights(catalog)
        let genres = Set(novel.displayGenres.map { $0.lowercased() })
        let candidates = catalog.filter { $0.id != novel.id }

        let similar = candidates
            .map { candidate -> (Novel, Double) in
                let shared = candidate.displayGenres
                    .map { $0.lowercased() }
                    .filter(genres.contains)
                return (candidate, shared.reduce(0) { $0 + (weights[$1] ?? 0) })
            }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if abs(lhs.1 - rhs.1) > 0.000_1 { return lhs.1 > rhs.1 }
                return areInIncreasingOrder(lhs.0, rhs.0, by: .rating)
            }
            .map(\.0)

        var result = Array(similar.prefix(limit))
        if result.count < min(6, limit) {
            let used = Set(result.map(\.id))
            result += sorted(candidates.filter { !used.contains($0.id) }, by: .rating)
                .prefix(limit - result.count)
        }
        return result
    }

    /// Home's novel picks: novels in the reader's genres alternating with the
    /// catalog's top rated, skipping novels they already have.
    static func picks(
        catalog: [Novel],
        basedOn readerNovels: [Novel],
        excluding excludedIDs: Set<String>,
        limit: Int = 16
    ) -> NovelPicks {
        let candidates = catalog.filter { !excludedIDs.contains($0.id) }
        let topRated = sorted(candidates.filter { $0.ratingLabel != nil }, by: .rating)
            + sorted(candidates.filter { $0.ratingLabel == nil }, by: .popular)

        let weights = genreWeights(catalog)
        var affinity: [String: Double] = [:]
        for novel in readerNovels {
            for genre in novel.displayGenres {
                let key = genre.lowercased()
                affinity[key, default: 0] += weights[key] ?? 0
            }
        }
        guard !affinity.isEmpty else {
            return NovelPicks(novels: Array(topRated.prefix(limit)), genres: [])
        }

        let forYou = candidates
            .map { novel in
                (novel, novel.displayGenres.reduce(0) { $0 + (affinity[$1.lowercased()] ?? 0) })
            }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if abs(lhs.1 - rhs.1) > 0.000_1 { return lhs.1 > rhs.1 }
                return areInIncreasingOrder(lhs.0, rhs.0, by: .rating)
            }
            .map(\.0)

        // Two for-you picks to every top-rated one; either list tops up the
        // other once it runs out.
        var seen = Set<String>()
        var result: [Novel] = []
        var forYouQueue = forYou[...]
        var topRatedQueue = topRated[...]
        func pop(_ queue: inout ArraySlice<Novel>) -> Novel? {
            while let next = queue.popFirst() {
                if seen.insert(next.id).inserted { return next }
            }
            return nil
        }
        while result.count < limit {
            let prefersForYou = result.count % 3 != 2
            let next = prefersForYou
                ? pop(&forYouQueue) ?? pop(&topRatedQueue)
                : pop(&topRatedQueue) ?? pop(&forYouQueue)
            guard let next else { break }
            result.append(next)
        }

        let names = Dictionary(
            catalog.flatMap(\.displayGenres).map { ($0.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let strongest = affinity
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(2)
            .map { names[$0.key] ?? $0.key }
        return NovelPicks(novels: result, genres: strongest)
    }

    // MARK: Discover

    /// A seed that changes once a week, so "Featured" rotates weekly.
    static func weekSeed(for date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return (components.yearForWeekOfYear ?? 0) * 100 + (components.weekOfYear ?? 0)
    }

    static func discover(_ catalog: [Novel], seed: Int) -> NovelDiscoverLayout {
        guard !catalog.isEmpty else { return .empty }
        var used = Set<String>()

        func take(_ novels: [Novel], _ count: Int) -> [Novel] {
            var picked: [Novel] = []
            for novel in novels where picked.count < count && !used.contains(novel.id) {
                picked.append(novel)
                used.insert(novel.id)
            }
            return picked
        }

        let popular = sorted(catalog, by: .popular)
        // Hero art carries the page; covers first.
        let withCover = popular.filter { $0.imageURL?.isEmpty == false }
        let hero = take(withCover + popular, heroCount)

        let featuredPool = popular.filter {
            !used.contains($0.id) && ($0.rating ?? 0) >= featuredMinimumRating
        }
        let featured = take(seededShuffle(featuredPool, seed: seed) + popular, featuredCount)
        let trending = take(popular, trendingCount)

        var shelves: [NovelDiscoverShelf] = []
        func addShelf(_ kind: NovelDiscoverShelf.Kind, _ title: String, _ subtitle: String, _ source: [Novel]) {
            let available = source.filter { !used.contains($0.id) }
            guard available.count >= minimumShelfCount else { return }
            shelves.append(
                NovelDiscoverShelf(kind: kind, title: title, subtitle: subtitle, novels: take(available, shelfCount))
            )
        }

        let broadLimit = Int(Double(catalog.count) * broadGenreShare)
        let distinctGenres = genreCounts(catalog)
            .filter { $0.count <= broadLimit && $0.count >= minimumShelfCount }
            .map(\.genre)
        var genreQueue = distinctGenres.makeIterator()
        var genreShelvesAdded = 0
        func addGenreShelf() {
            while genreShelvesAdded < genreShelfCount, let genre = genreQueue.next() {
                let before = shelves.count
                addShelf(
                    .genre(genre),
                    genre,
                    "Popular in \(genre.lowercased())",
                    novels(catalog, in: .genres, genre: genre, sort: .popular)
                )
                if shelves.count > before {
                    genreShelvesAdded += 1
                    return
                }
            }
        }

        addShelf(.topRated, "Top rated", "Rated highest by readers", novels(catalog, in: .topRated))
        addShelf(.mostRead, "Most read", "The most-viewed books on Asterion", novels(catalog, in: .mostRead))
        addGenreShelf()
        addShelf(.completed, "Completed", "Finished stories to read straight through", novels(catalog, in: .completed))
        addGenreShelf()
        addShelf(.ongoing, "Ongoing", "Still publishing new chapters", novels(catalog, in: .ongoing))
        addGenreShelf()

        return NovelDiscoverLayout(hero: hero, featured: featured, trending: trending, shelves: shelves)
    }

    /// Deterministic shuffle (SplitMix64) so a seed always gives one order.
    static func seededShuffle<Element>(_ elements: [Element], seed: Int) -> [Element] {
        var state = UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15
        func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        var result = elements
        guard result.count > 1 else { return result }
        for index in stride(from: result.count - 1, to: 0, by: -1) {
            let swapIndex = Int(next() % UInt64(index + 1))
            result.swapAt(index, swapIndex)
        }
        return result
    }
}
