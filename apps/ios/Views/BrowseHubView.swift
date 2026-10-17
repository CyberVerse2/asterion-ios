import AsterionKit
import SwiftUI
import UserNotifications

struct BrowseHubView: View {
    @State private var selection: BrowseContent = .novels

    var body: some View {
        selectedContent
            .environment(\.browseSelection, $selection)
            .background { AsterionBackdrop() }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selection {
        case .novels:
            NovelCatalogView()
        case .anime:
            AnimeCatalogView()
        case .moviesTV:
            MovieCatalogView()
        case .football:
            FootballCatalogView()
        }
    }
}

enum BrowseContent: String, CaseIterable, Identifiable {
    case novels
    case anime
    case moviesTV
    case football

    var id: String { rawValue }

    var title: String {
        switch self {
        case .novels: "Novels"
        case .anime: "Anime"
        case .moviesTV: "Movies & TV"
        case .football: "Football"
        }
    }

    var symbol: String {
        switch self {
        case .novels: "book.closed"
        case .anime: "play.tv"
        case .moviesTV: "film"
        case .football: "soccerball"
        }
    }
}

private struct BrowseSelectionKey: EnvironmentKey {
    static let defaultValue: Binding<BrowseContent>? = nil
}

extension EnvironmentValues {
    var browseSelection: Binding<BrowseContent>? {
        get { self[BrowseSelectionKey.self] }
        set { self[BrowseSelectionKey.self] = newValue }
    }
}

struct BrowseContentPicker: View {
    @Binding var selection: BrowseContent

    var body: some View {
        AsterionIndexTabs(
            items: BrowseContent.allCases,
            title: { $0.title },
            selection: $selection
        )
    }
}

/// Catalog switcher pinned above a Browse page: the big title-card words sit
/// just under the status bar, and the page scrolls beneath them.
struct BrowseCatalogChrome<Content: View>: View {
    @Environment(\.browseSelection) private var browseSelection
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            if let browseSelection {
                BrowseContentPicker(selection: browseSelection)
                    .padding(.top, 4)
                    .background(Color.asterionBackground)
                    .zIndex(1)
            }
            content
        }
        .background { AsterionBackdrop() }
    }
}

// MARK: - Anime catalog

struct AnimeCatalogView: View {
    private static let types = ["tv", "movie", "ova", "ona", "special", "music"]

    @State private var section: AnimeBrowseSection = .discover
    @State private var titles: [AnimeTitle] = []
    @State private var genres: [String] = []
    @State private var selectedGenre: String?
    @State private var selectedType = "tv"
    @State private var query = ""
    @State private var isLoading = true
    @State private var error: String?

    private var spotlight: AnimeTitle? {
        guard section == .discover,
              query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              titles.count > 1 else { return nil }
        return titles.first
    }

    var body: some View {
        NavigationStack {
            BrowseCatalogChrome {
                VStack(spacing: 0) {
                    AsterionIndexTabs(
                        items: AnimeBrowseSection.allCases,
                        title: { $0.rawValue },
                        rank: .subheader,
                        selection: $section
                    )

                    CatalogScrollView(
                        query: $query,
                        noun: "anime",
                        glowURL: spotlight?.imageURL,
                        isLoading: isLoading,
                        error: error,
                        isEmpty: titles.isEmpty,
                        retry: { await load() }
                    ) {
                        if let spotlight {
                            CatalogSpotlight(
                                eyebrow: "Featured anime",
                                title: spotlight.title,
                                metadata: Self.metadata(for: spotlight),
                                imageURL: spotlight.imageURL,
                                actionTitle: "View anime",
                                value: spotlight
                            )
                        }

                        if section == .genres, !genres.isEmpty, let selectedGenre {
                            CatalogFilterChips(
                                items: genres,
                                title: Self.displayName,
                                selection: Binding(
                                    get: { selectedGenre },
                                    set: { self.selectedGenre = $0 }
                                )
                            )
                        }

                        if section == .types {
                            CatalogFilterChips(
                                items: Self.types,
                                title: Self.displayName,
                                selection: $selectedType
                            )
                        }

                        if spotlight != nil {
                            MediaSectionHeader(title: "Recently updated", count: "\(titles.count - 1)")
                                .padding(.top, 8)
                        }

                        catalogPosterGrid
                    }
                }
                .navigationDestination(for: AnimeTitle.self) { title in
                    AnimeDetailView(title: title)
                }
                .toolbar(.hidden, for: .navigationBar)
                .task(id: catalogTaskID) {
                    if !query.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
                    guard !Task.isCancelled else { return }
                    await load()
                }
            }
        }
    }

    private var catalogTaskID: String {
        "\(section.rawValue)-\(query)-\(selectedGenre ?? "")-\(selectedType)"
    }

    private var gridTitles: [AnimeTitle] {
        spotlight == nil ? titles : Array(titles.dropFirst())
    }

    private var catalogPosterGrid: some View {
        CatalogPosterGrid {
            ForEach(gridTitles) { title in
                NavigationLink(value: title) {
                    EntertainmentPosterCard(
                        title: title.title,
                        imageURL: title.imageURL,
                        subtitle: Self.metadata(for: title)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private static func metadata(for title: AnimeTitle) -> String {
        [title.type?.uppercased(), title.episodeLabel]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func load() async {
        isLoading = titles.isEmpty
        defer { isLoading = false }
        do {
            titles = try await fetchTitles()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func fetchTitles() async throws -> [AnimeTitle] {
        let api = EntertainmentAPI.shared
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { return try await api.fetchAnime(query: q) }

        switch section {
        case .discover, .updated:
            return try await api.fetchAnime()
        case .added:
            return try await api.fetchAnimeReleases()
        case .popular:
            return try await api.fetchPopularAnime()
        case .airing:
            return try await api.fetchAnimeStatus("currently-airing")
        case .upcoming:
            return try await api.fetchAnimeStatus("not-yet-aired")
        case .completed:
            return try await api.fetchAnimeStatus("finished-airing")
        case .schedule:
            return try await api.fetchAnimeSchedule()
        case .genres:
            if genres.isEmpty {
                genres = try await api.fetchAnimeGenres()
                selectedGenre = genres.first
            }
            guard let selectedGenre else { return [] }
            return try await api.fetchAnimeGenre(selectedGenre)
        case .types:
            return try await api.fetchAnimeType(selectedType)
        }
    }

    nonisolated private static func displayName(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

// MARK: - Movie catalog

struct MovieCatalogView: View {
    @State private var section: MovieBrowseSection = .discover
    @State private var titles: [MovieTitle] = []
    @State private var genres: [MovieGenre] = []
    @State private var selectedGenre: MovieGenre?
    @State private var query = ""
    @State private var isLoading = true
    @State private var error: String?

    private var spotlight: MovieTitle? {
        guard section == .discover,
              query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              titles.count > 1 else { return nil }
        return titles.first
    }

    private var gridTitles: [MovieTitle] {
        spotlight == nil ? titles : Array(titles.dropFirst())
    }

    var body: some View {
        NavigationStack {
            BrowseCatalogChrome {
                VStack(spacing: 0) {
                    AsterionIndexTabs(
                        items: MovieBrowseSection.allCases,
                        title: { $0.rawValue },
                        rank: .subheader,
                        selection: $section
                    )

                    CatalogScrollView(
                        query: $query,
                        noun: "titles",
                        glowURL: spotlight?.imageURL,
                        isLoading: isLoading,
                        error: error,
                        isEmpty: titles.isEmpty,
                        retry: { await load() }
                    ) {
                        if let spotlight {
                            let isSeries = spotlight.type?.lowercased() == "tv"
                            CatalogSpotlight(
                                eyebrow: isSeries ? "Trending series" : "Trending film",
                                title: spotlight.title,
                                metadata: [
                                    spotlight.year,
                                    spotlight.runtime,
                                    spotlight.imdbRating.map { "★ \($0)" },
                                ]
                                .compactMap { $0 }
                                .filter { !$0.isEmpty }
                                .joined(separator: " · "),
                                imageURL: spotlight.imageURL,
                                actionTitle: isSeries ? "View series" : "View film",
                                value: spotlight
                            )
                        }

                        if section == .genres, !genres.isEmpty, let selectedGenre {
                            CatalogFilterChips(
                                items: genres,
                                title: \.title,
                                selection: Binding(
                                    get: { selectedGenre },
                                    set: { self.selectedGenre = $0 }
                                )
                            )
                        }

                        if spotlight != nil {
                            MediaSectionHeader(title: "Trending now", count: "\(titles.count - 1)")
                                .padding(.top, 8)
                        }

                        CatalogPosterGrid {
                            ForEach(gridTitles) { title in
                                NavigationLink(value: title) {
                                    EntertainmentPosterCard(
                                        title: title.title,
                                        imageURL: title.imageURL,
                                        subtitle: Self.metadata(for: title)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .navigationDestination(for: MovieTitle.self) { title in
                    MovieDetailView(title: title)
                }
                .toolbar(.hidden, for: .navigationBar)
                .task(id: "\(section.rawValue)-\(query)-\(selectedGenre?.slug ?? "")") {
                    if !query.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
                    guard !Task.isCancelled else { return }
                    await load()
                }
            }
        }
    }

    fileprivate static func metadata(for title: MovieTitle) -> String {
        [title.year, title.imdbRating.map { "★ \($0)" }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func load() async {
        isLoading = titles.isEmpty
        defer { isLoading = false }
        do {
            titles = try await fetchTitles()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func fetchTitles() async throws -> [MovieTitle] {
        let api = EntertainmentAPI.shared
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { return try await api.fetchMovies(kind: .movies, query: q) }

        switch section {
        case .discover:
            return try await api.fetchTrendingMovies()
        case .movies:
            return try await api.fetchMovies(kind: .movies)
        case .tvShows:
            return try await api.fetchMovies(kind: .tv)
        case .popular:
            return try await api.fetchPopularMovies()
        case .genres:
            if genres.isEmpty {
                genres = try await api.fetchMovieGenres()
                selectedGenre = genres.first
            }
            guard let selectedGenre else { return [] }
            return try await api.fetchMovies(genreSlug: selectedGenre.slug)
        }
    }
}

// MARK: - Novel catalog

enum NovelBrowseSection: String, CaseIterable, Hashable {
    case discover = "Discover"
    case ranking = "Ranking"
    case ongoing = "Ongoing"
    case completed = "Completed"
    case genres = "Genres"
}

/// Browse → Novels, built like the anime and film catalogs: section tabs, a
/// featured spotlight in its artwork's glow, shelves, genre chips, and the
/// whole catalog in a grid. The catalog is small, so it loads once (cached
/// copy first) and every section sorts and filters it on the device.
struct NovelCatalogView: View {
    @EnvironmentObject private var apiClient: APIClient
    @AppStorage("asterion.onboarding.genres") private var preferredGenres = ""
    @State private var section: NovelBrowseSection = .discover
    @State private var novels: [Novel] = []
    @State private var selectedGenre: String?
    @State private var query = ""
    @State private var isLoading = true
    @State private var error: String?
    @State private var refreshedAt: Date?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !trimmedQuery.isEmpty }

    private var preferredGenreList: [String] {
        preferredGenres
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    private var spotlight: Novel? {
        guard section == .discover, !isSearching else { return nil }
        return NovelCatalog.featured(novels, preferredGenres: Set(preferredGenreList), limit: 1).first
    }

    private var genres: [String] { NovelCatalog.genres(in: novels) }

    private var activeGenre: String? {
        if let selectedGenre { return selectedGenre }
        return NovelCatalog.shelfGenres(novels, preferred: preferredGenreList, count: 1, minimumTitles: 1).first
            ?? genres.first
    }

    private var searchResults: [Novel] { NovelCatalog.search(novels, query: trimmedQuery) }

    var body: some View {
        NavigationStack {
            BrowseCatalogChrome {
                VStack(spacing: 0) {
                    AsterionIndexTabs(
                        items: NovelBrowseSection.allCases,
                        title: { $0.rawValue },
                        rank: .subheader,
                        selection: $section
                    )

                    CatalogScrollView(
                        query: $query,
                        noun: "novels",
                        glowURL: spotlight?.imageUrl.flatMap(URL.init(string:)),
                        isLoading: isLoading,
                        error: error,
                        isEmpty: novels.isEmpty || (isSearching && searchResults.isEmpty),
                        retry: { await load(force: true) }
                    ) {
                        content
                    }
                }
                .navigationDestination(for: Novel.self) { novel in
                    NovelDetailView(novel: novel)
                }
                .toolbar(.hidden, for: .navigationBar)
                .task { await load() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isSearching {
            MediaSectionHeader(title: "Results", count: String(searchResults.count))
            novelGrid(searchResults)
        } else {
            switch section {
            case .discover:
                discover
            case .ranking:
                RankingView(novels: novels)
            case .ongoing:
                let ongoing = NovelCatalog.ongoing(novels)
                MediaSectionHeader(title: "Still publishing", count: String(ongoing.count))
                novelGrid(ongoing)
            case .completed:
                let completed = NovelCatalog.completed(novels)
                MediaSectionHeader(title: "Complete stories", count: String(completed.count))
                novelGrid(completed)
            case .genres:
                if let activeGenre {
                    CatalogFilterChips(
                        items: genres,
                        title: { $0 },
                        selection: Binding(
                            get: { activeGenre },
                            set: { selectedGenre = $0 }
                        )
                    )
                    let matches = NovelCatalog.filter(novels, genre: activeGenre)
                    MediaSectionHeader(title: activeGenre, count: String(matches.count))
                    novelGrid(matches)
                }
            }
        }
    }

    @ViewBuilder
    private var discover: some View {
        if let spotlight {
            NovelSpotlight(novel: spotlight)
        }

        let shelfGenres = NovelCatalog.shelfGenres(novels, preferred: preferredGenreList)

        NovelShelf(title: "Top rated", novels: Array(NovelCatalog.topRated(novels).prefix(12))) {
            section = .ranking
        }
        NovelShelf(title: "Most read", novels: Array(NovelCatalog.byPopularity(novels).prefix(12)))
        if let genre = shelfGenres.first {
            genreShelf(genre)
        }
        NovelShelf(title: "Ongoing", novels: Array(NovelCatalog.ongoing(novels).prefix(12))) {
            section = .ongoing
        }
        if shelfGenres.count > 1 {
            genreShelf(shelfGenres[1])
        }
        NovelShelf(title: "Completed", novels: Array(NovelCatalog.completed(novels).prefix(12))) {
            section = .completed
        }
    }

    private func genreShelf(_ genre: String) -> some View {
        NovelShelf(title: genre, novels: Array(NovelCatalog.filter(novels, genre: genre).prefix(12))) {
            selectedGenre = genre
            section = .genres
        }
    }

    private func novelGrid(_ items: [Novel]) -> some View {
        CatalogPosterGrid {
            ForEach(items) { novel in
                NavigationLink(value: novel) {
                    NovelTileCard(novel: novel)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Cached catalog first, then the network at most every ten minutes
    /// (the task re-runs each time the page appears).
    private func load(force: Bool = false) async {
        if novels.isEmpty {
            let cached = await OfflineChapterStore.shared.loadCatalog()
            if !cached.isEmpty {
                novels = cached
                isLoading = false
            }
        }
        if !force, let refreshedAt, Date().timeIntervalSince(refreshedAt) < 600 {
            isLoading = false
            return
        }
        isLoading = novels.isEmpty
        defer { isLoading = false }
        do {
            let fetched = try await apiClient.fetchAllNovels()
            guard !Task.isCancelled else { return }
            if !fetched.isEmpty {
                novels = fetched
                await OfflineChapterStore.shared.saveCatalog(fetched)
            }
            refreshedAt = Date()
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            if novels.isEmpty { self.error = error.localizedDescription }
        }
    }
}

/// The featured novel on Discover: cover and title card, a line of
/// synopsis, and the read action straight into the reader.
private struct NovelSpotlight: View {
    let novel: Novel

    private var summary: String? {
        let trimmed = novel.summary?
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.flatMap { $0.isEmpty ? nil : $0 }
    }

    private var metadata: String {
        [
            novel.ratingLabel,
            novel.catalogChapterCount.map { String($0) + " chapters" },
            novel.statusTitle,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CatalogSpotlightLayout(
                eyebrow: novel.genres?.first.map { "Featured novel · " + $0 } ?? "Featured novel",
                title: novel.title,
                metadata: metadata,
                subtitle: novel.author
            ) {
                NovelPosterArt(novel: novel)
            } actions: {
                EmptyView()
            }

            if let summary {
                Text(summary)
                    .font(.asterionReading(14))
                    .foregroundStyle(Color.asterionSynopsis)
                    .lineSpacing(3)
                    .lineLimit(3)
                    .frame(maxWidth: 620, alignment: .leading)
            }

            HStack(spacing: 10) {
                NovelReadButton(novel: novel, compact: true)
                NovelDetailsButton(novel: novel, compact: true)
                Spacer(minLength: 0)
            }
        }
        .padding(.bottom, 6)
    }
}

/// A titled horizontal shelf of novel posters, with "See all" when a
/// section holds the rest.
private struct NovelShelf: View {
    let title: String
    let novels: [Novel]
    var seeAll: (() -> Void)? = nil

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if !novels.isEmpty {
            let inset = AsterionLayout.pagePadding(horizontalSizeClass)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title)
                        .font(.asterionTitle(17, weight: .bold))
                        .foregroundStyle(Color.asterionText)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    if let seeAll {
                        Button("See all", action: seeAll)
                            .font(.asterionReading(13, weight: .semibold))
                            .foregroundStyle(Color.asterionMuted)
                            .buttonStyle(.plain)
                            .accessibilityLabel("See all \(title)")
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 13) {
                        ForEach(novels) { novel in
                            NavigationLink(value: novel) {
                                HomeNovelCard(novel: novel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, inset)
                }
                .padding(.horizontal, -inset)
            }
            .padding(.top, 6)
        }
    }
}

// MARK: - Catalog scaffolding

private enum CatalogPlaceholder {
    case posters
    case matches
}

private struct CatalogScrollView<Content: View>: View {
    @Binding var query: String
    var noun: String = "titles"
    var placeholder: CatalogPlaceholder = .posters
    var glowURL: URL? = nil
    let isLoading: Bool
    let error: String?
    let isEmpty: Bool
    let retry: () async -> Void
    @ViewBuilder let content: Content

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SearchInputView(text: $query)
                    .padding(.bottom, 4)

                if isLoading && isEmpty {
                    CatalogSkeleton(style: placeholder)
                } else if let error, isEmpty {
                    CatalogErrorView(title: "Couldn't load \(noun)", message: error, retry: retry)
                } else if isEmpty {
                    AsterionEmptyState(
                        symbol: isSearching ? "magnifyingglass" : "square.grid.2x2",
                        title: isSearching ? "No \(noun) match your search" : "Nothing here yet",
                        message: isSearching
                            ? "Try a different title or spelling."
                            : "Pull down to refresh, or pick another section."
                    )
                } else {
                    content
                }
            }
            .padding(.horizontal, AsterionLayout.pagePadding(horizontalSizeClass))
            .padding(.top, 6)
            .padding(.bottom, 36)
            .frame(maxWidth: AsterionLayout.pageMaxWidth(horizontalSizeClass), alignment: .leading)
            .frame(maxWidth: .infinity)
            .background(alignment: .top) {
                if let glowURL {
                    ArtworkGlow(url: glowURL, height: 560, intensity: 0.85)
                        // Rise out of the section bar instead of starting at a hard edge.
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.28),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .transition(.opacity)
                }
            }
        }
        .background { AsterionBackdrop() }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await retry() }
    }
}

/// Two columns on a phone, adaptive on iPad.
private struct CatalogPosterGrid<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(
            columns: AsterionLayout.posterColumns(horizontalSizeClass),
            alignment: .leading,
            spacing: 22
        ) {
            content
        }
    }
}

/// Placeholders shaped like the content they stand in for.
private struct CatalogSkeleton: View {
    let style: CatalogPlaceholder

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        switch style {
        case .posters:
            CatalogPosterGrid {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 9) {
                        Color.clear
                            .aspectRatio(2 / 3, contentMode: .fit)
                            .overlay { AsterionSkeleton(cornerRadius: 10) }
                        AsterionSkeleton(cornerRadius: 4)
                            .frame(height: 12)
                            .padding(.trailing, 28)
                        AsterionSkeleton(cornerRadius: 4)
                            .frame(width: 64, height: 10)
                    }
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Loading")
        case .matches:
            LazyVGrid(columns: FootballCatalogView.columns(horizontalSizeClass), spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    AsterionSkeleton(cornerRadius: 14)
                        .frame(height: 138)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Loading")
        }
    }
}

/// What went wrong, and a way to try again.
private struct CatalogErrorView: View {
    var title: String = "Something went wrong"
    let message: String
    let retry: () async -> Void

    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: 4) {
            AsterionEmptyState(symbol: "wifi.exclamationmark", title: title, message: message)
                .padding(.bottom, -24)
            Button {
                Task {
                    isRetrying = true
                    await retry()
                    isRetrying = false
                }
            } label: {
                HStack(spacing: 8) {
                    if isRetrying {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.asterionText)
                    }
                    Text("Try again")
                }
                .font(.asterionReading(14.5, weight: .semibold))
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
            }
            .buttonStyle(AsterionOutlineButtonStyle())
            .disabled(isRetrying)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

/// Featured title at the top of a Discover page: poster, title card, and one
/// lit action, standing in the glow its artwork casts.
private struct CatalogSpotlight<Value: Hashable>: View {
    let eyebrow: String
    let title: String
    let metadata: String
    let imageURL: URL?
    let actionTitle: String
    let value: Value

    var body: some View {
        CatalogSpotlightLayout(eyebrow: eyebrow, title: title, metadata: metadata) {
            AsyncImage(url: imageURL, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.asterionSurface
                }
            }
        } actions: {
            NavigationLink(value: value) {
                Label(actionTitle, systemImage: "play.fill")
                    .font(.asterionReading(14, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
            }
            .buttonStyle(AsterionFilledButtonStyle())
            .padding(.top, 4)
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
    }
}

/// The spotlight's poster-beside-title-card layout, shared by every catalog.
private struct CatalogSpotlightLayout<Poster: View, Actions: View>: View {
    let eyebrow: String
    let title: String
    let metadata: String
    var subtitle: String? = nil
    @ViewBuilder var poster: () -> Poster
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            poster()
                .frame(width: 118, height: 177)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1))
                }
                .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                AsterionEyebrow(text: eyebrow, color: .white.opacity(0.7))

                Text(title)
                    .font(.asterionTitle(23, weight: .heavy))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.asterionReading(13.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)
                }

                if !metadata.isEmpty {
                    Text(metadata)
                        .font(.asterionReading(13, weight: .medium))
                        .foregroundStyle(Color.asterionMuted)
                        .lineLimit(2)
                }

                actions()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 6)
    }
}

/// Poster with its title and subtitle set beneath the art, sized by its grid
/// column (the flexible sibling of `HomePosterCaption`).
private struct EntertainmentPosterCard: View {
    let title: String
    let imageURL: URL?
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay {
                    AsyncImage(url: imageURL, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color.asterionSurface
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.system(size: 20, weight: .light))
                                        .foregroundStyle(Color.asterionFaint)
                                }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.asterionBorder)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.asterionReading(13, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.asterionReading(11.5))
                        .foregroundStyle(Color.asterionMuted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct CatalogFilterChips<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        let inset = AsterionLayout.pagePadding(horizontalSizeClass)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    let selected = selection == item
                    Button {
                        if selection != item { Haptics.selection() }
                        withAnimation(.snappy) { selection = item }
                    } label: {
                        Text(title(item))
                            .font(.asterionReading(13, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .asterionGlassPill(isSelected: selected)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, inset)
        }
        .padding(.horizontal, -inset)
        .padding(.bottom, 4)
    }
}

// MARK: - Detail scaffolding

private enum MediaDetailShelf: String, CaseIterable, Hashable {
    case episodes = "Episodes"
    case moreLikeThis = "More like this"
}

/// Shelf heading: title-card title with a mono count.
private struct MediaSectionHeader: View {
    let title: String
    var count: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.asterionTitle(17, weight: .bold))
                .foregroundStyle(Color.asterionText)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let count, !count.isEmpty {
                Text(count)
                    .font(.asterionMono(11.5, weight: .medium))
                    .foregroundStyle(Color.asterionFaint)
            }
        }
    }
}

/// Top of a detail page: poster beside an eyebrow, the expanded title, and
/// one metadata line.
private struct MediaDetailHeader<Poster: View>: View {
    let eyebrow: String
    let title: String
    let metadata: String
    @ViewBuilder var poster: () -> Poster

    var body: some View {
        HStack(alignment: .bottom, spacing: 18) {
            poster()
            VStack(alignment: .leading, spacing: 8) {
                if !eyebrow.isEmpty {
                    AsterionEyebrow(text: eyebrow, color: .white.opacity(0.7))
                }

                Text(title)
                    .font(.asterionTitle(26, weight: .heavy))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(4)
                    .minimumScaleFactor(0.65)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 3)
                    .accessibilityAddTraits(.isHeader)

                if !metadata.isEmpty {
                    Text(metadata)
                        .font(.asterionReading(13, weight: .medium))
                        .foregroundStyle(Color.asterionMuted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 76)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The page's one lit action. Shows a small spinner while a stream resolves.
private struct MediaPlayButton: View {
    let title: String
    var systemImage: String = "play.fill"
    var isBusy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.asterionOnInk)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .bold))
                }
                Text(isBusy ? "Finding stream…" : title)
                    .lineLimit(1)
            }
            .font(.asterionReading(15, weight: .semibold))
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(AsterionFilledButtonStyle())
    }
}

/// Resume progress under the actions.
private struct MediaResumeLine: View {
    let fraction: Double
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            AsterionLightLine(fraction: fraction, height: 3)
                .frame(maxWidth: 280)
            Text("\(caption) · \(Int((fraction * 100).rounded()))%")
                .font(.asterionMono(11, weight: .medium))
                .foregroundStyle(Color.asterionFaint)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }
}

/// Inline failure under the actions, in the warning signal colour.
private struct MediaDetailNotice: View {
    let message: String
    var isError: Bool = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isError ? Color.asterionWarning : Color.asterionSuccess)
            Text(message)
                .font(.asterionReading(13.5))
                .foregroundStyle(Color.asterionMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Episode skeletons while a detail page loads.
private struct MediaEpisodeSkeleton: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AsterionSkeleton(cornerRadius: 999)
                .frame(width: 190, height: 34)
            LazyVGrid(columns: AsterionLayout.episodeColumns(horizontalSizeClass), spacing: 14) {
                ForEach(0..<3, id: \.self) { _ in
                    Color.clear
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay { AsterionSkeleton(cornerRadius: 14) }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .accessibilityElement()
        .accessibilityLabel("Loading episodes")
    }
}

/// Watch state laid over an episode card: a white ring for the current
/// episode, a light line for partial progress, a green check once watched.
private struct EpisodeWatchState: ViewModifier {
    let isCurrent: Bool
    let fraction: Double?
    let isWatched: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.asterionInk, lineWidth: 1.5)
                        .shadow(color: .white.opacity(0.3), radius: 8)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if let fraction, fraction > 0, !isWatched {
                    AsterionLightLine(fraction: fraction, height: 3)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isWatched {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.asterionSuccess)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                        .overlay(Circle().strokeBorder(Color.asterionSuccess.opacity(0.45)))
                        .padding(10)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

private extension View {
    func episodeWatchState(isCurrent: Bool, fraction: Double?, isWatched: Bool) -> some View {
        modifier(EpisodeWatchState(isCurrent: isCurrent, fraction: fraction, isWatched: isWatched))
    }
}

private func emptyShelfMessage(_ text: String) -> some View {
    Text(text)
        .font(.asterionReading(14))
        .foregroundStyle(Color.asterionMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
}

/// "More like this": a caption-poster grid inside a tab, or a horizontal
/// shelf when it stands alone.
private struct SimilarPosterGrid<Item: Identifiable, Destination: View>: View {
    enum Layout {
        case grid
        case shelf
    }

    let items: [Item]
    var layout: Layout = .grid
    let title: (Item) -> String
    let imageURL: (Item) -> URL?
    let eyebrow: (Item) -> String
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ViewBuilder let destination: (Item) -> Destination

    var body: some View {
        if items.isEmpty {
            emptyShelfMessage("Nothing similar yet")
        } else {
            switch layout {
            case .grid:
                LazyVGrid(
                    columns: AsterionLayout.posterColumns(horizontalSizeClass),
                    alignment: .leading,
                    spacing: 22
                ) {
                    ForEach(items) { item in
                        NavigationLink {
                            destination(item)
                        } label: {
                            EntertainmentPosterCard(
                                title: title(item),
                                imageURL: imageURL(item),
                                subtitle: eyebrow(item)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
            case .shelf:
                let size = AsterionLayout.shelfPosterSize(horizontalSizeClass)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 13) {
                        ForEach(items) { item in
                            NavigationLink {
                                destination(item)
                            } label: {
                                HomePosterCaption(title: title(item), subtitle: eyebrow(item), width: size.width) {
                                    AsyncImage(url: imageURL(item)) { phase in
                                        if let image = phase.image {
                                            image.resizable().scaledToFill()
                                        } else {
                                            Color.asterionSurface
                                        }
                                    }
                                    .frame(width: size.width, height: size.height)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}

private func similarAnimeTitles(to show: AnimeShow) async -> [AnimeTitle] {
    let api = EntertainmentAPI.shared
    var pool: [AnimeTitle] = []
    if let first = show.genres.first {
        let candidates = [
            first,
            first.lowercased(),
            first.lowercased().replacingOccurrences(of: " ", with: "-"),
        ]
        for candidate in candidates {
            if let fetched = try? await api.fetchAnimeGenre(candidate), !fetched.isEmpty {
                pool = fetched
                break
            }
        }
    }
    if pool.isEmpty {
        pool = (try? await api.fetchPopularAnime()) ?? []
    }
    var seen = Set<String>()
    return pool
        .filter { $0.slug != show.slug && seen.insert($0.slug).inserted }
        .prefix(12)
        .map { $0 }
}

private func similarMovieTitles(to show: MovieShow) async -> [MovieTitle] {
    let api = EntertainmentAPI.shared
    var pool: [MovieTitle] = []
    if let genres = try? await api.fetchMovieGenres(),
       let match = genres.first(where: { genre in
           show.genres.contains { $0.caseInsensitiveCompare(genre.title) == .orderedSame }
       })
    {
        pool = (try? await api.fetchMovies(genreSlug: match.slug)) ?? []
    }
    if pool.isEmpty {
        pool = (try? await api.fetchPopularMovies()) ?? []
    }
    var seen = Set<String>()
    return pool
        .filter { $0.slug != show.slug && seen.insert($0.slug).inserted }
        .prefix(12)
        .map { $0 }
}

private func nonEmpty(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

// MARK: - Anime detail

struct AnimeDetailView: View {
    let title: AnimeTitle

    @EnvironmentObject private var tabBarState: TabBarState
    @EnvironmentObject private var mediaAccountService: MediaAccountService
    @EnvironmentObject private var offlineVideoDownloadService: OfflineVideoDownloadService
    @Environment(\.dismiss) private var dismiss
    @State private var show: AnimeShow?
    @State private var episodes: [AnimeEpisode] = []
    @State private var playback: PlaybackRequest?
    @State private var isLoading = true
    @State private var playbackEpisodeID: String?
    @State private var isMassDownloading = false
    @State private var massDownloadCompleted = 0
    @State private var massDownloadTotal = 0
    @State private var episodePage = 0
    @State private var error: String?
    @State private var playbackError: String?
    @State private var synopsisExpanded = false
    @State private var detailShelf: MediaDetailShelf = .episodes
    @State private var similarTitles: [AnimeTitle] = []
    private let episodePageSize = 50

    private var eyebrow: String {
        (["Anime"] + [nonEmpty(show?.type ?? title.type)?.uppercased(), shortStatus].compactMap { $0 })
            .joined(separator: " · ")
    }

    private var shortStatus: String? {
        guard let status = nonEmpty(show?.status) else { return nil }
        switch status.lowercased() {
        case "currently airing", "airing", "ongoing": return "Airing"
        case "finished airing", "completed", "finished": return "Finished"
        case "not yet aired", "upcoming": return "Upcoming"
        default: return status
        }
    }

    private var metadata: String {
        let episodeCount = max(show?.episodesCount ?? 0, episodes.count)
        let genres = (show?.genres ?? [])
            .prefix(2)
            .map { $0.replacingOccurrences(of: "-", with: " ").capitalized }
            .joined(separator: ", ")
        return [
            show?.malScore.flatMap { nonEmpty($0) }.map { "★ \($0)" },
            episodeCount > 0 ? "\(episodeCount) episodes" : nonEmpty(title.episodeLabel),
            nonEmpty(show?.season) ?? nonEmpty(show?.dateAired),
            nonEmpty(show?.studio),
            genres.isEmpty ? nil : genres,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MediaDetailHeader(
                    eyebrow: eyebrow,
                    title: show?.title ?? title.title,
                    metadata: metadata
                ) {
                    AsterionDetailPoster(url: show?.imageURL ?? title.imageURL)
                }

                HStack(spacing: 10) {
                    if let episode = nextAnimeEpisode {
                        MediaPlayButton(
                            title: animePlayTitle(for: episode),
                            isBusy: playbackEpisodeID == episode.id
                        ) {
                            Task { await play(episode) }
                        }
                        .disabled(playbackEpisodeID != nil)
                    }

                    MediaSaveButton(item: mediaItem)
                    if !episodes.isEmpty {
                        MediaMassDownloadButton(
                            isComplete: pendingAnimeDownloads.isEmpty,
                            isBusy: isMassDownloading,
                            progress: massDownloadProgress,
                            accessibilityLabel: massDownloadLabel
                        ) {
                            Task { await downloadAllEpisodes() }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

                if let episode = nextAnimeEpisode,
                   let progress = animeProgress(for: episode),
                   !progress.completed, progress.percentage > 0 {
                    MediaResumeLine(fraction: progress.percentage / 100, caption: "Episode \(episode.number)")
                }

                if let playbackError {
                    MediaDetailNotice(message: playbackError)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }

                if let summary = show?.description, !summary.isEmpty {
                    AsterionSynopsisBlock(text: summary, expanded: $synopsisExpanded)
                }

                if isLoading {
                    MediaEpisodeSkeleton()
                } else if let error {
                    CatalogErrorView(title: "Couldn't load this anime", message: error) { await load() }
                } else {
                    detailShelfSection
                }
            }
            .padding(.bottom, 48)
            .background(alignment: .top) {
                AsterionCoverBleed(url: show?.imageURL ?? title.imageURL)
            }
        }
        .background(Color.asterionBackground)
        .overlay(alignment: .top) {
            AsterionDetailBar(onBack: { dismiss() }) { EmptyView() }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .onAppear { tabBarState.isVisible = false }
        .onDisappear { tabBarState.isVisible = true }
        .edgeSwipeToDismiss { dismiss() }
        .task { await load() }
        .fullScreenCover(item: $playback, onDismiss: PlaybackOrientationLock.endVideo) { request in
            NativeMediaPlayerView(request: request)
        }
    }

    private var episodePages: [[AnimeEpisode]] {
        stride(from: 0, to: episodes.count, by: episodePageSize).map { start in
            Array(episodes[start..<min(start + episodePageSize, episodes.count)])
        }
    }

    private var visibleEpisodes: [AnimeEpisode] {
        guard episodePages.indices.contains(episodePage) else { return episodes }
        return episodePages[episodePage]
    }

    private var detailShelfSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AsterionIndexTabs(
                items: MediaDetailShelf.allCases,
                title: { $0.rawValue },
                rank: .section,
                selection: $detailShelf
            )

            switch detailShelf {
            case .episodes:
                if episodes.isEmpty {
                    emptyShelfMessage("No episodes yet")
                } else {
                    episodeSection
                }
            case .moreLikeThis:
                SimilarPosterGrid(
                    items: similarTitles,
                    title: { $0.title },
                    imageURL: { $0.imageURL },
                    eyebrow: {
                        [$0.type?.uppercased(), $0.episodeLabel].compactMap { $0 }.joined(separator: " · ")
                    }
                ) { title in
                    AnimeDetailView(title: title)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var watchedCount: Int {
        episodes.filter { animeProgress(for: $0)?.completed == true }.count
    }

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                [
                    "\(episodes.count) \(episodes.count == 1 ? "episode" : "episodes")",
                    watchedCount > 0 ? "\(watchedCount) watched" : nil,
                ]
                .compactMap { $0 }
                .joined(separator: " · ")
            )
            .font(.asterionMono(11.5, weight: .medium))
            .foregroundStyle(Color.asterionFaint)
            .padding(.horizontal, 20)

            if episodePages.count > 1 {
                AsterionFilterPills(
                    titles: episodePages.map { page in
                        "\(page.first?.number ?? 0)–\(page.last?.number ?? 0)"
                    },
                    selectedIndex: episodePage,
                    onSelect: { episodePage = $0 }
                )
            }

            AsterionEpisodeShelf(title: nil, items: visibleEpisodes) { episode in
                let requestID = "anime-\(episode.animeID)-\(episode.number)"
                let progress = animeProgress(for: episode)
                AsterionEpisodeCard(
                    number: episode.number,
                    title: "Episode \(episode.number)",
                    subtitle: animeEpisodeStatus(episode),
                    imageURL: show?.imageURL ?? title.imageURL,
                    isBusy: playbackEpisodeID == episode.id,
                    downloadProgress: offlineVideoDownloadService.progress(forID: requestID),
                    isDownloaded: offlineVideoDownloadService.isDownloaded(id: requestID),
                    onPlay: { Task { await play(episode) } },
                    onDownload: { Task { await download(episode) } }
                )
                .episodeWatchState(
                    isCurrent: nextAnimeEpisode?.id == episode.id,
                    fraction: progress.map { $0.percentage / 100 },
                    isWatched: progress?.completed == true
                )
            }
        }
    }

    private var nextAnimeEpisode: AnimeEpisode? {
        MediaContinuePolicy.resumeUnit(
            from: episodes,
            progress: mediaAccountService.snapshot.progress,
            matches: matchesAnimeProgress
        )
    }

    private func matchesAnimeProgress(_ episode: AnimeEpisode, _ item: MediaPlaybackProgress) -> Bool {
        item.mediaType == .anime && item.contentId == title.slug && item.episodeNumber == episode.number
    }

    private func animeProgress(for episode: AnimeEpisode) -> MediaPlaybackProgress? {
        mediaAccountService.snapshot.progress.first { matchesAnimeProgress(episode, $0) }
    }

    private var isAnimeFinished: Bool {
        MediaContinuePolicy.isFinished(episodes, progress: mediaAccountService.snapshot.progress, matches: matchesAnimeProgress)
    }

    private func animePlayTitle(for episode: AnimeEpisode) -> String {
        if isAnimeFinished { return "Finished · Watch again" }
        if MediaContinuePolicy.isInProgress(episode, progress: mediaAccountService.snapshot.progress, matches: matchesAnimeProgress) {
            return "Resume episode \(episode.number)"
        }
        return "Watch episode \(episode.number)"
    }

    private func animeEpisodeStatus(_ episode: AnimeEpisode) -> String {
        let progress = animeProgress(for: episode)
        if progress?.completed == true { return "Watched" }
        if let progress, progress.percentage > 0 {
            return "Continue · \(Int(progress.percentage.rounded()))%"
        }
        if nextAnimeEpisode?.id == episode.id { return isAnimeFinished ? "Watch again" : "Up next" }
        return "Available"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedShow = try await EntertainmentAPI.shared.fetchAnimeShow(slug: title.slug)
            show = loadedShow
            async let episodesFetch = EntertainmentAPI.shared.fetchAnimeEpisodes(showID: loadedShow.id)
            async let similarFetch = similarAnimeTitles(to: loadedShow)
            episodes = try await episodesFetch.sorted { $0.number < $1.number }
            similarTitles = await similarFetch
            episodePage = 0
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func play(_ episode: AnimeEpisode) async {
        playbackEpisodeID = episode.id
        playbackError = nil
        defer { playbackEpisodeID = nil }
        do {
            playback = try await animePlayback(for: episode)
        } catch {
            playbackError = error.localizedDescription
        }
    }

    private var pendingAnimeDownloads: [AnimeEpisode] {
        episodes.filter { episode in
            !offlineVideoDownloadService.isDownloaded(id: "anime-\(episode.animeID)-\(episode.number)")
        }
    }

    private var massDownloadProgress: CGFloat {
        guard massDownloadTotal > 0 else { return 0 }
        return min(1, CGFloat(massDownloadCompleted) / CGFloat(massDownloadTotal))
    }

    private var massDownloadLabel: String {
        if isMassDownloading {
            return "Downloading \(massDownloadCompleted)/\(max(massDownloadTotal, 1))"
        }
        if pendingAnimeDownloads.isEmpty {
            return "Available offline"
        }
        return "Download all episodes"
    }

    private func download(_ episode: AnimeEpisode) async {
        do {
            let request = try await animePlayback(for: episode)
            offlineVideoDownloadService.start(request)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func downloadAllEpisodes() async {
        let pending = pendingAnimeDownloads
        guard !pending.isEmpty, !isMassDownloading else { return }
        isMassDownloading = true
        massDownloadTotal = pending.count
        massDownloadCompleted = 0
        defer { isMassDownloading = false }
        for episode in pending {
            do {
                let request = try await animePlayback(for: episode)
                offlineVideoDownloadService.start(request)
            } catch {
                self.error = error.localizedDescription
            }
            massDownloadCompleted += 1
        }
    }

    private func animePlayback(for episode: AnimeEpisode) async throws -> PlaybackRequest {
        let request = try await EntertainmentAPI.shared.fetchAnimePlayback(
            animeID: episode.animeID,
            episodeNumber: episode.number,
            title: "\(show?.title ?? title.title) · Episode \(episode.number)",
            item: mediaItem
        )
        return request.withQueue(animePlaybackQueue)
    }

    private var animePlaybackQueue: PlaybackQueue? {
        guard episodes.count > 1 else { return nil }
        let showTitle = show?.title ?? title.title
        return PlaybackQueue(
            sources: episodes.map { episode in
                .anime(
                    animeID: episode.animeID,
                    episodeNumber: episode.number,
                    title: "\(showTitle) · Episode \(episode.number)",
                    item: mediaItem
                )
            }
        )
    }

    private var mediaItem: MediaItemDescriptor {
        MediaItemDescriptor(
            mediaType: .anime,
            contentID: title.slug,
            title: show?.title ?? title.title,
            subtitle: show?.type ?? title.type,
            imageURL: show?.imageURL ?? title.imageURL
        )
    }
}

// MARK: - Movie detail

struct MovieDetailView: View {
    let title: MovieTitle

    @EnvironmentObject private var tabBarState: TabBarState
    @EnvironmentObject private var mediaAccountService: MediaAccountService
    @EnvironmentObject private var offlineVideoDownloadService: OfflineVideoDownloadService
    @Environment(\.dismiss) private var dismiss
    @State private var show: MovieShow?
    @State private var episodes: [MovieEpisode] = []
    @State private var playback: PlaybackRequest?
    @State private var isLoading = true
    @State private var playbackID: String?
    @State private var isMassDownloading = false
    @State private var massDownloadCompleted = 0
    @State private var massDownloadTotal = 0
    @State private var selectedSeason: Int?
    @State private var error: String?
    @State private var playbackError: String?
    @State private var synopsisExpanded = false
    @State private var detailShelf: MediaDetailShelf = .episodes
    @State private var similarTitles: [MovieTitle] = []

    private var isSeries: Bool { show?.isSeries == true }

    private var movieShelves: [MediaDetailShelf] {
        isSeries ? MediaDetailShelf.allCases : [.moreLikeThis]
    }

    private var eyebrow: String {
        let kind: String? = if show != nil {
            isSeries ? "Series" : "Film"
        } else {
            title.type.map { $0.lowercased() == "tv" ? "Series" : "Film" }
        }
        return [kind, nonEmpty(show?.releaseYear ?? title.year)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var metadata: String {
        let genres = (show?.genres ?? []).prefix(2).joined(separator: ", ")
        return [
            (show?.imdbRating ?? title.imdbRating).flatMap { nonEmpty($0) }.map { "★ \($0)" },
            isSeries && seasons.count > 0 ? "\(seasons.count) \(seasons.count == 1 ? "season" : "seasons")" : nil,
            isSeries && !episodes.isEmpty ? "\(episodes.count) episodes" : nil,
            isSeries ? nil : nonEmpty(show?.duration ?? title.runtime),
            genres.isEmpty ? nil : genres,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var seasons: [Int] {
        Array(Set(episodes.map(\.season))).sorted()
    }

    private var activeSeason: Int {
        selectedSeason ?? seasons.first ?? 1
    }

    private var episodesForActiveSeason: [MovieEpisode] {
        episodes.filter { $0.season == activeSeason }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MediaDetailHeader(
                    eyebrow: eyebrow,
                    title: show?.title ?? title.title,
                    metadata: metadata
                ) {
                    AsterionDetailPoster(url: show?.imageURL ?? title.imageURL)
                }

                HStack(spacing: 10) {
                    primaryPlay
                    MediaSaveButton(item: mediaItem)
                    if canMassDownloadMovies {
                        MediaMassDownloadButton(
                            isComplete: pendingMovieDownloads.isEmpty && movieAlreadyDownloaded,
                            isBusy: isMassDownloading,
                            progress: movieMassDownloadProgress,
                            accessibilityLabel: movieMassDownloadLabel
                        ) {
                            Task { await downloadAllMovies() }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

                if isSeries, let episode = nextMovieEpisode,
                   let progress = movieProgress(for: episode),
                   !progress.completed, progress.percentage > 0 {
                    MediaResumeLine(
                        fraction: progress.percentage / 100,
                        caption: "S\(episode.season) E\(episode.number)"
                    )
                }

                if let playbackError {
                    MediaDetailNotice(message: playbackError)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }

                if let summary = show?.description, !summary.isEmpty {
                    AsterionSynopsisBlock(text: summary, expanded: $synopsisExpanded)
                }

                if isLoading {
                    MediaEpisodeSkeleton()
                } else if let error {
                    CatalogErrorView(title: "Couldn't load this title", message: error) { await load() }
                } else {
                    movieDetailShelf
                }
            }
            .padding(.bottom, 48)
            .background(alignment: .top) {
                AsterionCoverBleed(url: show?.imageURL ?? title.imageURL)
            }
        }
        .background(Color.asterionBackground)
        .overlay(alignment: .top) {
            AsterionDetailBar(onBack: { dismiss() }) { EmptyView() }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .onAppear { tabBarState.isVisible = false }
        .onDisappear { tabBarState.isVisible = true }
        .edgeSwipeToDismiss { dismiss() }
        .task { await load() }
        .fullScreenCover(item: $playback, onDismiss: PlaybackOrientationLock.endVideo) { request in
            NativeMediaPlayerView(request: request)
        }
    }

    @ViewBuilder
    private var primaryPlay: some View {
        if isSeries, let episode = nextMovieEpisode {
            let unitTitle = episode.title.isEmpty ? "Episode \(episode.number)" : episode.title
            playControl(
                slug: episode.id,
                label: moviePlayTitle(for: episode),
                playbackLabel: unitTitle
            )
        } else if !isSeries {
            playControl(
                slug: title.slug,
                label: "Watch movie",
                playbackLabel: title.title
            )
        }
    }

    private var movieDetailShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            if movieShelves.count > 1 {
                AsterionIndexTabs(
                    items: movieShelves,
                    title: { $0.rawValue },
                    rank: .section,
                    selection: $detailShelf
                )
            } else {
                MediaSectionHeader(
                    title: MediaDetailShelf.moreLikeThis.rawValue,
                    count: similarTitles.isEmpty ? nil : "\(similarTitles.count)"
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }

            switch detailShelf {
            case .episodes:
                if episodes.isEmpty {
                    emptyShelfMessage("No episodes yet")
                } else {
                    episodeLists
                }
            case .moreLikeThis:
                SimilarPosterGrid(
                    items: similarTitles,
                    layout: movieShelves.count > 1 ? .grid : .shelf,
                    title: { $0.title },
                    imageURL: { $0.imageURL },
                    eyebrow: { MovieCatalogView.metadata(for: $0) }
                ) { title in
                    MovieDetailView(title: title)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var episodeLists: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                "\(episodesForActiveSeason.count) \(episodesForActiveSeason.count == 1 ? "episode" : "episodes")"
                    + (seasons.count > 1 ? " · season \(activeSeason)" : "")
            )
            .font(.asterionMono(11.5, weight: .medium))
            .foregroundStyle(Color.asterionFaint)
            .padding(.horizontal, 20)

            if seasons.count > 1 {
                AsterionFilterPills(
                    titles: seasons.map { "Season \($0)" },
                    selectedIndex: seasons.firstIndex(of: activeSeason) ?? 0,
                    onSelect: { selectedSeason = seasons[$0] }
                )
            }

            AsterionEpisodeShelf(title: nil, items: episodesForActiveSeason) { episode in
                let requestID = "movie-\(episode.id)"
                let progress = movieProgress(for: episode)
                AsterionEpisodeCard(
                    number: episode.number,
                    title: episode.title.isEmpty ? "Episode \(episode.number)" : episode.title,
                    subtitle: movieEpisodeStatus(episode),
                    imageURL: show?.imageURL ?? title.imageURL,
                    isBusy: playbackID == episode.id,
                    downloadProgress: offlineVideoDownloadService.progress(forID: requestID),
                    isDownloaded: offlineVideoDownloadService.isDownloaded(id: requestID),
                    onPlay: { Task { await play(slug: episode.id, label: episode.title) } },
                    onDownload: { Task { await download(episode) } }
                )
                .episodeWatchState(
                    isCurrent: nextMovieEpisode?.id == episode.id,
                    fraction: progress.map { $0.percentage / 100 },
                    isWatched: progress?.completed == true
                )
            }
        }
    }

    private var nextMovieEpisode: MovieEpisode? {
        MediaContinuePolicy.resumeUnit(
            from: episodes,
            progress: mediaAccountService.snapshot.progress,
            matches: matchesMovieProgress
        )
    }

    private func matchesMovieProgress(_ episode: MovieEpisode, _ item: MediaPlaybackProgress) -> Bool {
        item.mediaType == .movie && item.contentId == title.slug && item.unitId == episode.id
    }

    private func movieProgress(for episode: MovieEpisode) -> MediaPlaybackProgress? {
        mediaAccountService.snapshot.progress.first { matchesMovieProgress(episode, $0) }
    }

    private var isSeriesFinished: Bool {
        MediaContinuePolicy.isFinished(episodes, progress: mediaAccountService.snapshot.progress, matches: matchesMovieProgress)
    }

    private func moviePlayTitle(for episode: MovieEpisode) -> String {
        let unit = "S\(episode.season) E\(episode.number)"
        if isSeriesFinished { return "Finished · Watch again" }
        if MediaContinuePolicy.isInProgress(episode, progress: mediaAccountService.snapshot.progress, matches: matchesMovieProgress) {
            return "Resume \(unit)"
        }
        return "Watch \(unit)"
    }

    private func movieEpisodeStatus(_ episode: MovieEpisode) -> String {
        let progress = movieProgress(for: episode)
        if progress?.completed == true { return "Watched" }
        if let progress, progress.percentage > 0 {
            return "Continue · \(Int(progress.percentage.rounded()))%"
        }
        if nextMovieEpisode?.id == episode.id { return isSeriesFinished ? "Watch again" : "Up next" }
        return "Available"
    }

    private func playControl(slug: String, label: String, playbackLabel: String) -> some View {
        MediaPlayButton(title: label, isBusy: playbackID == slug) {
            Task { await play(slug: slug, label: playbackLabel) }
        }
        .disabled(playbackID != nil)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedShow = try await EntertainmentAPI.shared.fetchMovieShow(slug: title.slug)
            show = loadedShow
            async let similarFetch = similarMovieTitles(to: loadedShow)
            if loadedShow.isSeries {
                episodes = try await EntertainmentAPI.shared.fetchMovieEpisodes(slug: title.slug)
                    .sorted { ($0.season, $0.number) < ($1.season, $1.number) }
                selectedSeason = nextMovieEpisode?.season ?? episodes.first?.season
                detailShelf = .episodes
            } else {
                detailShelf = .moreLikeThis
            }
            similarTitles = await similarFetch
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func play(slug: String, label: String) async {
        playbackID = slug
        playbackError = nil
        defer { playbackID = nil }
        do {
            playback = try await moviePlayback(slug: slug, label: label)
        } catch {
            playbackError = error.localizedDescription
        }
    }

    private var canMassDownloadMovies: Bool {
        isSeries ? !episodes.isEmpty : !isLoading
    }

    private var pendingMovieDownloads: [MovieEpisode] {
        episodes.filter { episode in
            !offlineVideoDownloadService.isDownloaded(id: "movie-\(episode.id)")
        }
    }

    private var movieAlreadyDownloaded: Bool {
        if isSeries { return pendingMovieDownloads.isEmpty && !episodes.isEmpty }
        return offlineVideoDownloadService.isDownloaded(id: "movie-\(title.slug)")
    }

    private var movieMassDownloadProgress: CGFloat {
        guard massDownloadTotal > 0 else { return 0 }
        return min(1, CGFloat(massDownloadCompleted) / CGFloat(massDownloadTotal))
    }

    private var movieMassDownloadLabel: String {
        if isMassDownloading {
            return "Downloading \(massDownloadCompleted)/\(max(massDownloadTotal, 1))"
        }
        if movieAlreadyDownloaded {
            return "Available offline"
        }
        return isSeries ? "Download all episodes" : "Download movie"
    }

    private func download(_ episode: MovieEpisode) async {
        do {
            let request = try await moviePlayback(slug: episode.id, label: episode.title)
            offlineVideoDownloadService.start(request)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func downloadAllMovies() async {
        guard !isMassDownloading else { return }
        isMassDownloading = true
        defer { isMassDownloading = false }

        if isSeries {
            let pending = pendingMovieDownloads
            guard !pending.isEmpty else { return }
            massDownloadTotal = pending.count
            massDownloadCompleted = 0
            for episode in pending {
                do {
                    let request = try await moviePlayback(slug: episode.id, label: episode.title)
                    offlineVideoDownloadService.start(request)
                } catch {
                    self.error = error.localizedDescription
                }
                massDownloadCompleted += 1
            }
            return
        }

        guard !movieAlreadyDownloaded else { return }
        massDownloadTotal = 1
        massDownloadCompleted = 0
        do {
            let request = try await moviePlayback(slug: title.slug, label: title.title)
            offlineVideoDownloadService.start(request)
        } catch {
            self.error = error.localizedDescription
        }
        massDownloadCompleted = 1
    }

    private func moviePlayback(slug: String, label: String) async throws -> PlaybackRequest {
        let episode = episodes.first { $0.id == slug }
        let request = try await EntertainmentAPI.shared.fetchMoviePlayback(
            slug: slug,
            title: show?.isSeries == true ? "\(show?.title ?? title.title) · \(label)" : title.title,
            item: mediaItem,
            unitTitle: show?.isSeries == true ? label : "Movie",
            seasonNumber: episode?.season,
            episodeNumber: episode?.number
        )
        return request.withQueue(moviePlaybackQueue)
    }

    private var moviePlaybackQueue: PlaybackQueue? {
        guard isSeries, episodes.count > 1 else { return nil }
        let showTitle = show?.title ?? title.title
        return PlaybackQueue(
            sources: episodes.map { episode in
                let unitTitle = episode.title.isEmpty ? "Episode \(episode.number)" : episode.title
                return .movie(
                    slug: episode.id,
                    title: "\(showTitle) · \(unitTitle)",
                    item: mediaItem,
                    unitTitle: unitTitle,
                    seasonNumber: episode.season,
                    episodeNumber: episode.number
                )
            }
        )
    }

    private var mediaItem: MediaItemDescriptor {
        MediaItemDescriptor(
            mediaType: .movie,
            contentID: title.slug,
            title: show?.title ?? title.title,
            subtitle: show?.isSeries == true ? "TV Series" : "Movie",
            imageURL: show?.imageURL ?? title.imageURL
        )
    }
}

// MARK: - Football

private extension FootballMatch {
    /// The feed often labels fixtures only with the sport itself.
    var hasGenericCategory: Bool {
        ["football", "soccer", ""].contains(
            category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }

    var homeName: String {
        teams?.home?.name ?? displayTitle.components(separatedBy: " vs ").first ?? title
    }

    var awayName: String {
        teams?.away?.name
            ?? displayTitle.components(separatedBy: " vs ").dropFirst().first
            ?? ""
    }

    /// "in 14 minutes", "Tomorrow", … rather than repeating the sport.
    var relativeKickoff: String {
        kickoff.formatted(.relative(presentation: .named))
    }
}

/// Club crest, or its initials in a smoked disc when the feed has none.
private struct TeamCrest: View {
    let name: String
    let url: URL?
    var size: CGFloat = 42

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
            } else {
                Text(Self.initials(for: name))
                    .font(.system(size: size * 0.29, weight: .bold).width(.expanded))
                    .foregroundStyle(Color.asterionText.opacity(0.82))
                    .minimumScaleFactor(0.6)
                    .frame(width: size * 0.92, height: size * 0.92)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.16)))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    static func initials(for name: String) -> String {
        let words = name.split(separator: " ").filter { !$0.isEmpty }
        let letters = words.count > 1 ? words.prefix(2).compactMap(\.first) : Array((words.first ?? "").prefix(3))
        return String(letters).uppercased()
    }
}

struct FootballCatalogView: View {
    @State private var section: FootballCatalogSection = .live
    @State private var matches: [FootballMatch] = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var error: String?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    fileprivate static func columns(_ sizeClass: UserInterfaceSizeClass?) -> [GridItem] {
        if AsterionLayout.isWide(sizeClass) {
            return [GridItem(.adaptive(minimum: 320, maximum: 460), spacing: 14, alignment: .top)]
        }
        return [GridItem(.flexible(minimum: 0))]
    }

    private var filteredMatches: [FootballMatch] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return matches }
        return matches.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(normalized)
                || $0.category.localizedCaseInsensitiveContains(normalized)
        }
    }

    var body: some View {
        NavigationStack {
            BrowseCatalogChrome {
                VStack(spacing: 0) {
                    AsterionIndexTabs(
                        items: FootballCatalogSection.allCases,
                        title: { $0.rawValue },
                        rank: .subheader,
                        selection: $section
                    )

                    CatalogScrollView(
                        query: $query,
                        noun: "matches",
                        placeholder: .matches,
                        isLoading: isLoading,
                        error: error,
                        isEmpty: filteredMatches.isEmpty,
                        retry: { await load() }
                    ) {
                        LazyVGrid(columns: Self.columns(horizontalSizeClass), spacing: 12) {
                            ForEach(filteredMatches) { match in
                                NavigationLink(value: match) {
                                    FootballMatchCard(match: match)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .navigationDestination(for: FootballMatch.self) { match in
                        FootballDetailView(match: match)
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .task(id: section) { await load() }
                }
            }
        }
    }

    private func load() async {
        isLoading = matches.isEmpty
        defer { isLoading = false }
        do {
            matches = try await EntertainmentAPI.shared.fetchFootball(section: section)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct FootballMatchCard: View {
    let match: FootballMatch

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                if match.isLive {
                    AsterionLiveBadge()
                } else {
                    AsterionEyebrow(text: match.relativeKickoff)
                }
                Spacer(minLength: 8)
                if !match.hasGenericCategory {
                    Text(match.category.capitalized)
                        .font(.asterionReading(11.5, weight: .medium))
                        .foregroundStyle(Color.asterionFaint)
                        .lineLimit(1)
                }
            }

            HStack(alignment: .center, spacing: 8) {
                teamColumn(name: match.homeName, badgeURL: match.teams?.home?.badgeURL)

                VStack(spacing: 3) {
                    if match.isLive {
                        Text("vs")
                            .font(.asterionMono(12, weight: .semibold))
                            .foregroundStyle(Color.asterionMuted)
                    } else {
                        Text(match.kickoff.formatted(date: .omitted, time: .shortened))
                            .font(.asterionMono(16, weight: .semibold))
                            .foregroundStyle(Color.asterionText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(match.kickoff.formatted(.dateTime.weekday(.abbreviated).day()))
                            .font(.asterionReading(10.5, weight: .medium))
                            .foregroundStyle(Color.asterionMuted)
                    }
                }
                .frame(width: 84)

                teamColumn(name: match.awayName, badgeURL: match.teams?.away?.badgeURL)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .asterionPanel(cornerRadius: 14)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(match.displayTitle), "
                + (match.isLive
                    ? "live"
                    : match.kickoff.formatted(date: .abbreviated, time: .shortened))
        )
    }

    private func teamColumn(name: String, badgeURL: URL?) -> some View {
        VStack(spacing: 8) {
            TeamCrest(name: name, url: badgeURL, size: 42)
            Text(name)
                .font(.asterionReading(12.5, weight: .semibold))
                .foregroundStyle(Color.asterionText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }
}

struct FootballDetailView: View {
    let match: FootballMatch

    private enum MatchFollowTiming {
        static let matchLength: TimeInterval = 2.5 * 60 * 60
    }

    @EnvironmentObject private var tabBarState: TabBarState
    @Environment(\.dismiss) private var dismiss
    @State private var playback: PlaybackRequest?
    @State private var isLoadingPlayback = false
    @State private var message: String?
    @State private var messageIsError = false
    /// The last resolved stream list, kept so the panel can offer each source.
    @State private var resolvedRequest: PlaybackRequest?
    /// Whether this match has a kickoff Live Activity running.
    @State private var isFollowing = false
    /// Whether a kickoff reminder is pending for this match.
    @State private var isReminderSet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AsterionLayout.sectionSpacing) {
                faceOff

                VStack(alignment: .leading, spacing: 14) {
                    MediaSectionHeader(title: "Streams", count: streamCount)
                    streamPanel
                }

                VStack(alignment: .leading, spacing: 14) {
                    MediaSectionHeader(title: "Match details")
                    detailsPanel
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 84)
            .padding(.bottom, 48)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .background(alignment: .top) {
                AsterionCoverBleed(url: match.posterURL ?? match.teams?.home?.badgeURL)
            }
        }
        .background(Color.asterionBackground)
        .overlay(alignment: .top) {
            AsterionDetailBar(onBack: { dismiss() }) { EmptyView() }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .onAppear {
            tabBarState.isVisible = false
            refreshFollowState()
        }
        .task(id: match.kickoff) { await refreshReminderState() }
        .onDisappear { tabBarState.isVisible = true }
        .edgeSwipeToDismiss { dismiss() }
        .fullScreenCover(item: $playback, onDismiss: PlaybackOrientationLock.endVideo) { request in
            NativeMediaPlayerView(request: request)
        }
    }

    // MARK: Face-off

    private var faceOff: some View {
        VStack(spacing: 24) {
            AsterionEyebrow(
                text: match.hasGenericCategory
                    ? (match.isLive ? "In play" : "Upcoming match")
                    : match.category,
                color: .white.opacity(0.7)
            )

            HStack(alignment: .top, spacing: 8) {
                team(name: match.homeName, badgeURL: match.teams?.home?.badgeURL)
                centerStatus
                    .padding(.top, 18)
                team(name: match.awayName, badgeURL: match.teams?.away?.badgeURL)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(match.displayTitle)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    if match.isLive {
                        MediaPlayButton(title: "Watch live", isBusy: isLoadingPlayback) {
                            Task { await watch() }
                        }
                        .disabled(isLoadingPlayback)
                    } else if canRemind {
                        MediaPlayButton(
                            title: isReminderSet ? "Reminder on" : "Remind me",
                            systemImage: isReminderSet ? "bell.badge.fill" : "bell.fill"
                        ) {
                            Task { await toggleReminder() }
                        }
                        .accessibilityLabel(isReminderSet ? "Cancel kickoff reminder" : "Remind me before kickoff")
                    }

                    MediaSaveButton(item: mediaItem)
                }

                if canFollow {
                    followButton
                }

                if let message {
                    MediaDetailNotice(message: message, isError: messageIsError)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func team(name: String, badgeURL: URL?) -> some View {
        VStack(spacing: 14) {
            TeamCrest(name: name, url: badgeURL, size: 72)
                .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
                .background {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.1), .white.opacity(0)],
                                center: .center,
                                startRadius: 4,
                                endRadius: 60
                            )
                        )
                        .frame(width: 120, height: 120)
                }
            Text(name)
                .font(.asterionTitle(17, weight: .bold))
                .foregroundStyle(Color.asterionText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var centerStatus: some View {
        VStack(spacing: 7) {
            if match.isLive {
                AsterionLiveBadge()
                    .scaleEffect(1.2)
                    .padding(.bottom, 4)
                Text("vs")
                    .font(.asterionMono(13, weight: .semibold))
                    .foregroundStyle(Color.asterionMuted)
            } else {
                Text(match.kickoff.formatted(date: .omitted, time: .shortened))
                    .font(.asterionMono(24, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(match.kickoff.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.asterionReading(12, weight: .medium))
                    .foregroundStyle(Color.asterionMuted)
                Text(match.relativeKickoff)
                    .font(.asterionMono(10.5, weight: .medium))
                    .foregroundStyle(Color.asterionFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: 100)
    }

    // MARK: Streams

    private var streamCount: String? {
        if let options = resolvedRequest?.options, !options.isEmpty {
            return "\(options.count) \(options.count == 1 ? "stream" : "streams")"
        }
        guard !match.sources.isEmpty else { return nil }
        return "\(match.sources.count) \(match.sources.count == 1 ? "source" : "sources")"
    }

    @ViewBuilder
    private var streamPanel: some View {
        if let request = resolvedRequest, !request.options.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(request.options.enumerated()), id: \.element.id) { index, option in
                    Button {
                        playback = request.selecting(option)
                    } label: {
                        streamRow(
                            index: index,
                            name: Self.streamName(option.title),
                            tags: Self.streamTags(option.title),
                            isSelected: option.id == request.selectedOption?.id,
                            showsDivider: index < request.options.count - 1
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Watch on \(option.title)")
                }
            }
            .asterionPanel(cornerRadius: 14)
        } else if match.sources.isEmpty {
            AsterionEmptyState(
                symbol: "antenna.radiowaves.left.and.right",
                title: "No streams listed",
                message: "Providers usually appear shortly before kickoff. Check back closer to the match."
            )
            .asterionPanel(cornerRadius: 14)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 0) {
                    ForEach(Array(match.sources.enumerated()), id: \.offset) { index, source in
                        Button {
                            Task { await watch() }
                        } label: {
                            streamRow(
                                index: index,
                                name: source.source.capitalized,
                                tags: [],
                                isSelected: false,
                                showsDivider: index < match.sources.count - 1
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!match.isLive || isLoadingPlayback)
                        .accessibilityLabel("\(source.source.capitalized) stream")
                    }
                }
                .asterionPanel(cornerRadius: 14)

                Text(
                    match.isLive
                        ? "Quality and language show once a stream opens."
                        : "Streams open at kickoff."
                )
                .font(.asterionReading(12))
                .foregroundStyle(Color.asterionFaint)
                .padding(.horizontal, 4)
            }
        }
    }

    private func streamRow(
        index: Int,
        name: String,
        tags: [String],
        isSelected: Bool,
        showsDivider: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", index + 1))
                .font(.asterionMono(12, weight: .medium))
                .foregroundStyle(isSelected ? Color.asterionText : Color.asterionFaint)
                .frame(width: 26, alignment: .leading)

            Text(name)
                .font(.asterionReading(14.5, weight: .medium))
                .foregroundStyle(Color.asterionText)
                .lineLimit(1)

            Spacer(minLength: 8)

            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.asterionMono(10.5, weight: .semibold))
                    .foregroundStyle(tag == "HD" ? Color.asterionText : Color.asterionMuted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(tag == "HD" ? 0.12 : 0.06), in: Capsule())
            }

            Image(systemName: isSelected ? "checkmark" : "play.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? Color.asterionInk : Color.asterionFaint)
                .frame(width: 16)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(Color.asterionHairline)
                    .frame(height: 1)
                    .padding(.leading, 54)
            }
        }
    }

    /// Option titles read "Source · EN · HD".
    private static func streamName(_ title: String) -> String {
        title.components(separatedBy: " · ").first ?? title
    }

    private static func streamTags(_ title: String) -> [String] {
        Array(title.components(separatedBy: " · ").dropFirst())
    }

    // MARK: Details

    private var detailsPanel: some View {
        VStack(spacing: 0) {
            factRow(
                label: "Kickoff",
                value: match.kickoff.formatted(date: .abbreviated, time: .shortened),
                showsDivider: true
            )
            if !match.hasGenericCategory {
                factRow(label: "Competition", value: match.category.capitalized, showsDivider: true)
            }
            factRow(label: "Status", value: statusDescription, showsDivider: false)
        }
        .asterionPanel(cornerRadius: 14)
    }

    private var statusDescription: String {
        if match.isLive { return "In play" }
        return match.kickoff > Date() ? "Upcoming" : "Not live"
    }

    private func factRow(label: String, value: String, showsDivider: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.asterionReading(13.5))
                .foregroundStyle(Color.asterionMuted)
            Spacer(minLength: 12)
            Text(value)
                .font(.asterionReading(13.5, weight: .medium))
                .foregroundStyle(Color.asterionText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(Color.asterionHairline)
                    .frame(height: 1)
                    .padding(.leading, 16)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func watch() async {
        isLoadingPlayback = true
        defer { isLoadingPlayback = false }
        do {
            let request = try await EntertainmentAPI.shared.fetchFootballPlayback(match: match)
            resolvedRequest = request
            playback = request
            message = nil
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }

    private var canRemind: Bool {
        KickoffReminder.fireDate(kickoff: match.kickoff) != nil
    }

    private func refreshReminderState() async {
        await KickoffReminderService.refresh(matchID: match.id, title: match.displayTitle, kickoff: match.kickoff)
        isReminderSet = await KickoffReminderService.isScheduled(matchID: match.id)
    }

    private func toggleReminder() async {
        if isReminderSet {
            KickoffReminderService.cancel(matchID: match.id)
            withAnimation(.easeOut(duration: 0.2)) { isReminderSet = false }
            message = "Reminder cancelled."
            messageIsError = false
            return
        }
        do {
            switch try await KickoffReminderService.schedule(
                matchID: match.id, title: match.displayTitle, kickoff: match.kickoff) {
            case .scheduled:
                withAnimation(.easeOut(duration: 0.2)) { isReminderSet = true }
                Haptics.success()
                message = "We’ll remind you 15 minutes before kickoff."
                messageIsError = false
            case .denied:
                message = "Notifications are off. You can turn them on in Settings."
                messageIsError = true
            case .tooLate:
                message = "This match is about to start."
                messageIsError = false
            }
        } catch {
            message = "Couldn’t set the reminder. Try again in a moment."
            messageIsError = true
        }
    }

    // MARK: Follow in Dynamic Island

    /// Upcoming or in-play matches; nothing to follow once it is over.
    private var canFollow: Bool {
        match.isLive || Date() < match.kickoff.addingTimeInterval(MatchFollowTiming.matchLength)
    }

    private var followButton: some View {
        Button(action: toggleFollow) {
            HStack(spacing: 8) {
                Image(systemName: isFollowing ? "checkmark" : "dot.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                Text(isFollowing ? "Following in Dynamic Island" : "Follow in Dynamic Island")
                    .lineLimit(1)
            }
            .font(.asterionReading(14, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(AsterionOutlineButtonStyle())
        .accessibilityLabel(isFollowing ? "Stop following in Dynamic Island" : "Follow in Dynamic Island")
        .accessibilityHint("Shows a kickoff countdown on the Lock Screen and in the Dynamic Island.")
    }

    private func refreshFollowState() {
        let manager = MatchLiveActivityManager.shared
        isFollowing = manager.isFollowing(matchID: match.id)
        if isFollowing, match.isLive {
            manager.update(matchID: match.id, isLive: true)
        }
    }

    private func toggleFollow() {
        let manager = MatchLiveActivityManager.shared
        if isFollowing {
            manager.unfollow(matchID: match.id)
            withAnimation(.easeOut(duration: 0.2)) { isFollowing = false }
            message = nil
            return
        }

        let result = manager.follow(
            matchID: match.id,
            home: match.homeName,
            away: match.awayName,
            competition: match.hasGenericCategory ? "" : match.category.capitalized,
            kickoff: match.kickoff,
            isLive: match.isLive,
            homeBadgeURL: match.teams?.home?.badgeURL?.absoluteString,
            awayBadgeURL: match.teams?.away?.badgeURL?.absoluteString
        )
        switch result {
        case .following:
            withAnimation(.easeOut(duration: 0.2)) { isFollowing = true }
            message = match.isLive
                ? "Following live on the Lock Screen and in the Dynamic Island."
                : "Kickoff countdown is on the Lock Screen and in the Dynamic Island."
            messageIsError = false
        case .activitiesDisabled:
            message = "Live Activities are off for Asterion. You can turn them on in Settings."
            messageIsError = true
        case let .tooEarly(opensAt):
            message = "You can follow from \(opensAt.formatted(date: .abbreviated, time: .shortened)), eight hours before kickoff."
            messageIsError = false
        case .finished:
            message = "This match has finished."
            messageIsError = false
        case .failed:
            message = "Couldn’t start the Live Activity. Try again in a moment."
            messageIsError = true
        }
    }

    private var mediaItem: MediaItemDescriptor {
        MediaItemDescriptor(
            mediaType: .football,
            contentID: match.id,
            title: match.displayTitle,
            subtitle: match.category.capitalized,
            imageURL: match.posterURL
        )
    }
}

private struct MediaSaveButton: View {
    let item: MediaItemDescriptor

    @EnvironmentObject private var mediaAccountService: MediaAccountService
    @State private var isWorking = false

    private var isSaved: Bool { mediaAccountService.isBookmarked(item) }

    var body: some View {
        AsterionCircleIconButton(
            systemName: isSaved ? "bookmark.fill" : "bookmark",
            isBusy: isWorking,
            accessibilityLabel: isSaved ? "Remove from library" : "Save to library"
        ) {
            Task {
                isWorking = true
                await mediaAccountService.toggleBookmark(item)
                isWorking = false
                if isSaved { Haptics.success() } else { Haptics.tap() }
            }
        }
        .disabled(isWorking)
    }
}
