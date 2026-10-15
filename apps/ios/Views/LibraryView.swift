import Inject
import SwiftUI

struct LibraryView: View {
    @ObserveInjection var inject
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var mediaAccountService: MediaAccountService
    @EnvironmentObject private var tabBarState: TabBarState
    @EnvironmentObject private var readingProgressService: ReadingProgressService

    @State private var novels: [LibraryItem] = []
    @State private var loadingNovels = false
    @State private var failedNovels = false
    @State private var search = ""
    @State private var debouncedSearch = ""
    @State private var filter: LibraryFilter = .all
    @State private var sortOption: SortOption = .lastRead
    @State private var navigationPath = NavigationPath()

    private let pageHorizontalPadding: CGFloat = 24

    enum LibraryFilter: String, CaseIterable {
        case all = "All"
        case novels = "Novels"
        case anime = "Anime"
        case movies = "Movies & TV"
        case football = "Football"
    }

    enum SortOption: String, CaseIterable {
        case lastRead = "Last Read"
        case lastAdded = "Last Added"
        case lastUpdated = "Last Updated"
    }

    struct LibraryItem: Identifiable {
        let novel: Novel
        let addedAt: Date?
        let updatedAt: Date?
        let lastReadAt: Date?
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

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    AsterionPageHeader(title: "Library")

                    SearchInputView(text: $search)
                        .padding(.top, 8)
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

                    if (loadingNovels || mediaAccountService.isLoading) && !hasVisibleContent {
                        ProgressView()
                            .tint(Color.goldAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                    } else if !hasVisibleContent {
                        emptyState
                    }
                }
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.bottom, 32)
                .frame(maxWidth: 1120, alignment: .topLeading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await refresh() }
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
    }

    private var continueWatchingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue")
                .font(.asterionReading(15, weight: .medium))
                .foregroundStyle(Color.asterionText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 13) {
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

    @ViewBuilder
    private var novelSection: some View {
        if !filteredNovels.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    if filter == .all {
                        Text("Novels")
                            .font(.asterionReading(15, weight: .medium))
                            .foregroundStyle(Color.asterionText)
                    }
                    Spacer()
                    Menu(sortOption.rawValue) {
                        Picker("Sort novels", selection: $sortOption) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    }
                    .font(.asterionReading(14))
                    .foregroundStyle(Color.asterionMuted)
                }

                ForEach(filteredNovels) { item in
                    NavigationLink(value: item.novel) {
                        LibraryNovelRow(novel: item.novel)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if filter == .novels, !authService.isSignedIn {
            signInForNovelsState
        } else if failedNovels, filter == .novels {
            inlineMessage("Your novels could not be loaded. Pull down to try again.", systemImage: "wifi.exclamationmark")
        }
    }

    @ViewBuilder
    private var savedMediaSection: some View {
        if !filteredBookmarks.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if filter == .all {
                    Text("Saved")
                        .font(.asterionReading(15, weight: .medium))
                        .foregroundStyle(Color.asterionText)
                }
                ForEach(filteredBookmarks) { bookmark in
                    NavigationLink {
                        MediaDestinationView(
                            mediaType: bookmark.mediaType,
                            contentID: bookmark.contentId,
                            title: bookmark.title,
                            imageURL: bookmark.imageURL
                        )
                    } label: {
                        MediaBookmarkRow(bookmark: bookmark, showsKind: filter == .all)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(debouncedSearch.isEmpty ? "Nothing saved" : "No matches")
                .font(.asterionDisplay(26, weight: .medium))
                .foregroundStyle(Color.asterionText)

            if debouncedSearch.isEmpty {
                Button {
                    tabBarState.selectedTab = .browse
                } label: {
                    Text("Browse the catalog")
                        .font(.asterionReading(16, weight: .semibold))
                        .foregroundStyle(Color.asterionOnInk)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.asterionInk, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Text("Try another title.")
                    .font(.asterionReading(16))
                    .foregroundStyle(Color.asterionMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 28)
    }

    private var signInForNovelsState: some View {
        inlineMessage("Sign in from Account to save novels and keep reading progress across devices.", systemImage: "person.crop.circle.badge.plus")
    }

    private func inlineMessage(_ message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .font(.asterionSerif(14))
            .foregroundStyle(Color.asterionMuted)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .asterionGlassSurface(cornerRadius: 16)
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
                    lastReadAt: progressByNovel[entry.novelId]?.updatedAt
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
                novels = cached.map {
                    LibraryItem(novel: $0.novel, addedAt: $0.addedAt, updatedAt: $0.updatedAt, lastReadAt: $0.lastReadAt)
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

private struct LibraryNovelRow: View {
    let novel: Novel

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            CoverImageView(novel: novel, size: .md)
            VStack(alignment: .leading, spacing: 4) {
                Text(novel.title)
                    .font(.asterionReading(16))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(2)
                Text(novel.author ?? "Unknown author")
                    .font(.asterionReading(13))
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }
}

private struct MediaBookmarkRow: View {
    let bookmark: MediaBookmark
    var showsKind: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            MediaArtwork(url: bookmark.imageURL, width: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(bookmark.title)
                    .font(.asterionReading(16))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(bookmarkCaption)
                    .font(.asterionReading(13))
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }

    private var bookmarkCaption: String {
        if let detail = cleanedSubtitle {
            return detail
        }
        return showsKind ? shortKind : bookmark.mediaType.title
    }

    private var shortKind: String {
        switch bookmark.mediaType {
        case .anime: "Anime"
        case .movie: "Movie"
        case .football: "Football"
        }
    }

    private var cleanedSubtitle: String? {
        guard let raw = bookmark.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        switch raw.lowercased() {
        case "tv series", "tv", "series":
            return "TV series"
        case "movie", "movies", "movies & tv":
            return "Movie"
        default:
            return raw.localizedCapitalized
        }
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
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipped()
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
                ProgressView().tint(Color.goldAccent)
            } else {
                ContentUnavailableView(
                    "Match no longer available",
                    systemImage: "sportscourt",
                    description: Text("It remains in your library until you remove it.")
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
