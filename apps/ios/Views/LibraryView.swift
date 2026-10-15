import Inject
import SwiftUI

struct LibraryView: View {
    @ObserveInjection var inject
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var mediaAccountService: MediaAccountService
    @EnvironmentObject private var tabBarState: TabBarState
    @EnvironmentObject private var readingProgressService: ReadingProgressService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var novels: [LibraryItem] = []
    @State private var loadingNovels = false
    @State private var failedNovels = false
    @State private var search = ""
    @State private var debouncedSearch = ""
    @State private var filter: LibraryFilter = .all
    @State private var sortOption: SortOption = .lastRead
    @State private var navigationPath = NavigationPath()

    private var pageHorizontalPadding: CGFloat { AsterionLayout.pagePadding(horizontalSizeClass) }

    enum LibraryFilter: String, CaseIterable {
        case all = "All"
        case novels = "Novels"
        case anime = "Anime"
        case movies = "Movies & TV"
        case football = "Football"
    }

    enum SortOption: String, CaseIterable {
        case lastRead = "Last read"
        case lastAdded = "Last added"
        case lastUpdated = "Last updated"
    }

    struct LibraryItem: Identifiable {
        let novel: Novel
        let addedAt: Date?
        let updatedAt: Date?
        let lastReadAt: Date?
        var percentage: Double? = nil
        var id: String { novel.id }
    }

    private var filteredNovels: [LibraryItem] {
        guard filter == .all || filter == .novels else { return [] }
        var result = novels.filter { matchesSearch(title: $0.novel.title, subtitle: $0.novel.author) }
        switch sortOption {
        case .lastRead:
            result.sort {
                let lhs = readingProgressService.lastReadAt(for: $0.id, remote: $0.lastReadAt) ?? .distantPast
                let rhs = readingProgressService.lastReadAt(for: $1.id, remote: $1.lastReadAt) ?? .distantPast
                if lhs == rhs { return $0.novel.title.localizedStandardCompare($1.novel.title) == .orderedAscending }
                return lhs > rhs
            }
        case .lastAdded:
            result.sort { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        case .lastUpdated:
            result.sort { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        }
        return result
    }

    private var filteredBookmarks: [MediaBookmark] {
        mediaAccountService.snapshot.bookmarks.filter { bookmark in
            mediaTypeMatchesFilter(bookmark.mediaType)
                && matchesSearch(title: bookmark.title, subtitle: bookmark.subtitle)
        }
    }

    private var continueWatching: [MediaPlaybackProgress] {
        guard filter == .all || filter == .anime || filter == .movies else { return [] }
        return mediaAccountService.snapshot.progress
            .filter {
                !$0.completed
                    && $0.positionSeconds > 0
                    && mediaTypeMatchesFilter($0.mediaType)
                    && matchesSearch(title: $0.title, subtitle: $0.unitTitle)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var hasVisibleContent: Bool {
        !filteredNovels.isEmpty || !filteredBookmarks.isEmpty || !continueWatching.isEmpty
    }

    private var isLoadingFirstPage: Bool {
        (loadingNovels || mediaAccountService.isLoading) && !hasVisibleContent
    }

    /// "12 saved · 3 in progress", across every kind of title.
    private var librarySubtitle: String {
        let saved = novels.count + mediaAccountService.snapshot.bookmarks.count
        let readingNow = novels.filter { item in
            let started = readingProgressService.lastReadAt(for: item.id, remote: item.lastReadAt) != nil
            return started && (item.percentage ?? 0) < 100
        }.count
        let watchingNow = mediaAccountService.snapshot.progress.filter { !$0.completed && $0.positionSeconds > 0 }.count
        let inProgress = readingNow + watchingNow
        guard saved > 0 || inProgress > 0 else {
            return "Everything you save to read or watch lives here."
        }
        return "\(saved) saved · \(inProgress) in progress"
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 18) {
                        AsterionPageHeader(title: "Library", subtitle: librarySubtitle)
                        SearchInputView(text: $search, placeholder: "Search your library")
                    }

                    filterPicker

                    if !continueWatching.isEmpty {
                        continueWatchingSection
                    }

                    if filter == .all || filter == .novels {
                        novelSection
                    }

                    if filter != .novels {
                        savedMediaSection
                    }

                    if isLoadingFirstPage {
                        loadingGrid
                    } else if !hasVisibleContent, !showsNovelSpecificState {
                        emptyState
                    }
                }
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.bottom, 40)
                .frame(maxWidth: AsterionLayout.pageMaxWidth(horizontalSizeClass), alignment: .topLeading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await refresh() }
            .asterionStatusBarScrim()
            .background { AsterionBackdrop() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Novel.self) { novel in
                NovelDetailView(novel: novel) { popNavigation() }
            }
            .task(id: authService.isSignedIn) { await refresh() }
            .onChange(of: tabBarState.selectedTab) { _, tab in
                guard tab == .library else { return }
                Task { await loadNovels() }
            }
            .debounceSearch(text: $search, debouncedText: $debouncedSearch)
        }
        .enableInjection()
    }

    private var filterPicker: some View {
        AsterionIndexTabs(
            items: LibraryFilter.allCases,
            title: { $0.rawValue },
            rank: .subheader,
            selection: $filter
        )
        .padding(.horizontal, -pageHorizontalPadding)
        .padding(.vertical, -6)
    }

    // MARK: - Continue

    private var continueWatchingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            AsterionSectionLabel(title: "Continue watching", detail: "\(continueWatching.count)")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(continueWatching) { item in
                        NavigationLink {
                            MediaDestinationView(
                                mediaType: item.mediaType,
                                contentID: item.contentId,
                                title: item.title,
                                imageURL: item.imageURL
                            )
                        } label: {
                            AsterionContinueCard(
                                title: item.title,
                                subtitle: item.unitTitle ?? "Resume",
                                percentage: item.percentage
                            ) {
                                AsyncImage(url: item.imageURL) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        Color.asterionCard
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, pageHorizontalPadding)
            }
            .padding(.horizontal, -pageHorizontalPadding)
        }
    }

    // MARK: - Novels

    private var showsNovelSpecificState: Bool {
        filter == .novels && filteredNovels.isEmpty && (!authService.isSignedIn || failedNovels)
    }

    @ViewBuilder
    private var novelSection: some View {
        if !filteredNovels.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    AsterionSectionLabel(
                        title: filter == .all ? "Novels" : "Saved novels",
                        detail: "\(filteredNovels.count)"
                    )
                    sortMenu
                }

                LazyVGrid(columns: AsterionLayout.posterColumns(horizontalSizeClass), spacing: 24) {
                    ForEach(filteredNovels) { item in
                        NavigationLink(value: item.novel) {
                            LibraryPosterTile(
                                title: item.novel.title,
                                subtitle: item.novel.author ?? "Unknown author",
                                progress: item.percentage.map { $0 / 100 }
                            ) {
                                NovelPosterArt(novel: item.novel)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else if filter == .novels, !authService.isSignedIn {
            signInForNovelsState
        } else if failedNovels, filter == .novels {
            novelsFailedState
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort novels", selection: $sortOption) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(sortOption.rawValue)
                    .font(.asterionReading(12.5, weight: .semibold))
            }
            .foregroundStyle(Color.asterionText.opacity(0.85))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.asterionBorder))
            .fixedSize()
        }
        .accessibilityLabel("Sort novels")
        .accessibilityValue(sortOption.rawValue)
    }

    // MARK: - Saved media

    @ViewBuilder
    private var savedMediaSection: some View {
        if !filteredBookmarks.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                AsterionSectionLabel(
                    title: filter == .all ? "Saved" : "Saved \(filter.rawValue.lowercased())",
                    detail: "\(filteredBookmarks.count)"
                )

                LazyVGrid(columns: AsterionLayout.posterColumns(horizontalSizeClass), spacing: 24) {
                    ForEach(filteredBookmarks) { bookmark in
                        NavigationLink {
                            MediaDestinationView(
                                mediaType: bookmark.mediaType,
                                contentID: bookmark.contentId,
                                title: bookmark.title,
                                imageURL: bookmark.imageURL
                            )
                        } label: {
                            LibraryPosterTile(
                                title: bookmark.title,
                                subtitle: bookmarkCaption(bookmark, showsKind: filter == .all),
                                progress: nil
                            ) {
                                BookmarkArtwork(bookmark: bookmark)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - States

    private var loadingGrid: some View {
        LazyVGrid(columns: AsterionLayout.posterColumns(horizontalSizeClass), spacing: 24) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 9) {
                    AsterionSkeleton(cornerRadius: 10)
                        .aspectRatio(2 / 3, contentMode: .fit)
                    AsterionSkeleton(cornerRadius: 4)
                        .frame(width: 110, height: 11)
                    AsterionSkeleton(cornerRadius: 4)
                        .frame(width: 70, height: 9)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading your library")
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            if !debouncedSearch.isEmpty {
                AsterionEmptyState(
                    symbol: "magnifyingglass",
                    title: "No matches",
                    message: "Nothing in your library matches \u{201C}\(debouncedSearch)\u{201D}. Try another title or author."
                )
            } else {
                AsterionEmptyState(
                    symbol: emptySymbol,
                    title: emptyTitle,
                    message: emptyMessage
                )

                Button {
                    tabBarState.selectedTab = .browse
                } label: {
                    Text("Browse the catalog")
                        .font(.asterionReading(15, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 13)
                }
                .buttonStyle(AsterionFilledButtonStyle())
                .padding(.top, -24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var emptySymbol: String {
        switch filter {
        case .all: "books.vertical"
        case .novels: "book.closed"
        case .anime: MediaAccountType.anime.systemImage
        case .movies: MediaAccountType.movie.systemImage
        case .football: MediaAccountType.football.systemImage
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .all: "Nothing saved yet"
        case .novels: "No novels saved yet"
        case .anime: "No anime saved yet"
        case .movies: "No films or series saved yet"
        case .football: "No matches saved yet"
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .all: "Save a novel, a series, or a match and it will be waiting for you here."
        case .novels: "Add a novel from its page and it will be here, ready to pick up where you left off."
        case .anime: "Save a show from its page to keep it close."
        case .movies: "Save a film or series from its page to keep it close."
        case .football: "Save a match to find it again quickly."
        }
    }

    private var signInForNovelsState: some View {
        inlineMessage(
            "Sign in from Account to save novels and keep reading progress across devices.",
            systemImage: "person.crop.circle.badge.plus"
        )
    }

    private var novelsFailedState: some View {
        VStack(spacing: 4) {
            AsterionEmptyState(
                symbol: "wifi.exclamationmark",
                title: "Your novels could not be loaded",
                message: "Check your connection, then try again."
            )
            Button {
                Task { await loadNovels() }
            } label: {
                Text("Try again")
                    .font(.asterionReading(15, weight: .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
            }
            .buttonStyle(AsterionOutlineButtonStyle())
            .padding(.top, -24)
        }
        .frame(maxWidth: .infinity)
    }

    private func inlineMessage(_ message: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.asterionMuted)
            Text(message)
                .font(.asterionReading(14))
                .foregroundStyle(Color.asterionMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .asterionPanel(cornerRadius: 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    private func bookmarkCaption(_ bookmark: MediaBookmark, showsKind: Bool) -> String {
        if let raw = bookmark.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            switch raw.lowercased() {
            case "tv series", "tv", "series":
                return "TV series"
            case "movie", "movies", "movies & tv":
                return "Movie"
            default:
                return raw.localizedCapitalized
            }
        }
        guard showsKind else { return bookmark.mediaType.title }
        switch bookmark.mediaType {
        case .anime: return "Anime"
        case .movie: return "Movie"
        case .football: return "Football"
        }
    }

    private func matchesSearch(title: String, subtitle: String?) -> Bool {
        let query = debouncedSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(query)
            || (subtitle?.localizedCaseInsensitiveContains(query) ?? false)
    }

    private func mediaTypeMatchesFilter(_ mediaType: MediaAccountType) -> Bool {
        switch filter {
        case .all: true
        case .novels: false
        case .anime: mediaType == .anime
        case .movies: mediaType == .movie
        case .football: mediaType == .football
        }
    }

    private func refresh() async {
        await mediaAccountService.refresh()
        await loadNovels()
    }

    private func loadNovels() async {
        loadingNovels = true
        defer { loadingNovels = false }
        guard authService.isSignedIn else {
            novels = []
            failedNovels = false
            return
        }
        do {
            async let libraryFetch = apiClient.fetchMyLibrary()
            async let progressFetch = apiClient.fetchAllReadingProgress()
            async let novelsFetch = apiClient.fetchAllNovels()
            let (libraryEntries, progressEntries, catalog) = try await (libraryFetch, progressFetch, novelsFetch)
            let progressByNovel = Dictionary(uniqueKeysWithValues:
                readingProgressService.mergedProgress(with: progressEntries).map { ($0.novelId, $0) })
            let novelByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
            novels = libraryEntries.compactMap { entry in
                guard let novel = novelByID[entry.novelId] else { return nil }
                return LibraryItem(
                    novel: novel,
                    addedAt: entry.createdAt,
                    updatedAt: entry.updatedAt,
                    lastReadAt: progressByNovel[entry.novelId]?.updatedAt,
                    percentage: progressByNovel[entry.novelId]?.percentage
                )
            }
            await OfflineChapterStore.shared.saveLibrarySnapshot(
                novels.map {
                    OfflineLibraryItemSnapshot(
                        novel: $0.novel,
                        addedAt: $0.addedAt,
                        updatedAt: $0.updatedAt,
                        lastReadAt: $0.lastReadAt
                    )
                }
            )
            failedNovels = false
        } catch {
            let cached = await OfflineChapterStore.shared.loadLibrarySnapshot()
            if !cached.isEmpty {
                let local = Dictionary(
                    readingProgressService.localProgress.map { ($0.novelId, $0.percentage) },
                    uniquingKeysWith: { first, _ in first }
                )
                novels = cached.map {
                    LibraryItem(
                        novel: $0.novel,
                        addedAt: $0.addedAt,
                        updatedAt: $0.updatedAt,
                        lastReadAt: $0.lastReadAt,
                        percentage: local[$0.novel.id]
                    )
                }
                failedNovels = false
            } else {
                failedNovels = true
            }
        }
    }

    private func popNavigation() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
    }
}

/// 2:3 poster with its title beneath the art and, when started, a line of
/// light along the bottom edge of the artwork.
private struct LibraryPosterTile<Artwork: View>: View {
    let title: String
    let subtitle: String
    let progress: Double?
    @ViewBuilder var artwork: () -> Artwork

    private var visibleProgress: Double? {
        guard let progress, progress > 0 else { return nil }
        return progress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay { artwork() }
                .overlay(alignment: .bottom) {
                    if let visibleProgress {
                        ZStack(alignment: .bottom) {
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 44)
                            AsterionLightLine(fraction: visibleProgress, height: 3)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 10)
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
                Text(subtitle)
                    .font(.asterionReading(11.5))
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(visibleProgress.map { "\(Int(($0 * 100).rounded())) percent read" } ?? "")
    }
}

private struct BookmarkArtwork: View {
    let bookmark: MediaBookmark

    var body: some View {
        Color.asterionCard
            .overlay {
                Image(systemName: bookmark.mediaType.systemImage)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Color.asterionFaint)
            }
            .overlay {
                AsyncImage(url: bookmark.imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    }
                }
            }
            .clipped()
    }
}

struct MediaArtwork: View {
    var url: URL?
    var width: CGFloat = 72

    private var height: CGFloat { width * 1.5 }

    var body: some View {
        Color.asterionCard
            .frame(width: width, height: height)
            .overlay {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.asterionBorder)
            }
    }
}

struct MediaDestinationView: View {
    let mediaType: MediaAccountType
    let contentID: String
    let title: String
    let imageURL: URL?

    var body: some View {
        switch mediaType {
        case .anime:
            AnimeDetailView(
                title: AnimeTitle(
                    slug: contentID,
                    title: title,
                    japaneseTitle: nil,
                    imageURL: imageURL,
                    type: nil,
                    episodeLabel: nil
                )
            )
        case .movie:
            MovieDetailView(
                title: MovieTitle(
                    id: contentID,
                    slug: contentID,
                    title: title,
                    imageURL: imageURL,
                    imdbRating: nil,
                    runtime: nil,
                    year: nil,
                    type: nil,
                    quality: nil
                )
            )
        case .football:
            SavedFootballDestination(matchID: contentID, title: title)
        }
    }
}

private struct SavedFootballDestination: View {
    let matchID: String
    let title: String
    @State private var match: FootballMatch?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let match {
                FootballDetailView(match: match)
            } else if isLoading {
                ProgressView().tint(Color.asterionInk)
            } else {
                AsterionEmptyState(
                    symbol: "sportscourt",
                    title: "Match no longer available",
                    message: "It stays in your library until you remove it."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AsterionBackdrop() }
        .navigationTitle(title)
        .task { await findMatch() }
    }

    private func findMatch() async {
        defer { isLoading = false }
        do {
            async let liveFetch = EntertainmentAPI.shared.fetchFootball(section: .live)
            async let scheduleFetch = EntertainmentAPI.shared.fetchFootball(section: .schedule)
            async let popularFetch = EntertainmentAPI.shared.fetchFootball(section: .popular)
            let (live, schedule, popular) = try await (liveFetch, scheduleFetch, popularFetch)
            match = (live + schedule + popular).first { $0.id == matchID }
        } catch {
            match = nil
        }
    }
}
