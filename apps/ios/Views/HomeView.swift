import Inject
import SwiftUI

struct HomeView: View {
    enum Mode {
        case home
        case browse
    }

    let mode: Mode
    @ObserveInjection var inject
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var readingProgressService: ReadingProgressService
    @EnvironmentObject private var mediaAccountService: MediaAccountService
    @EnvironmentObject private var offlineVideoDownloadService: OfflineVideoDownloadService
    @State private var novels: [Novel] = []
    @State private var loading = false
    @State private var failed = false
    @State private var search = ""
    @State private var debouncedSearch = ""
    @State private var continueReadingItems: [ContinueReadingItem] = []
    @State private var continueReadingDestination: ContinueReadingDestination?
    @State private var navigationPath = NavigationPath()
    @State private var featuredAnime: [AnimeTitle] = []
    @State private var featuredMovies: [MovieTitle] = []
    @State private var liveMatches: [FootballMatch] = []
    @State private var heroIndex = 0
    @AppStorage("asterion.onboarding.genres") private var preferredGenres = ""
    @AppStorage(DownloadAheadCoordinator.enabledKey) private var downloadAheadEnabled = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(mode: Mode = .home) {
        self.mode = mode
    }

    private var isDesktop: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }
    private var isWideCanvas: Bool { AsterionLayout.isWide(horizontalSizeClass) }
    private var contentMaxWidth: CGFloat { AsterionLayout.pageMaxWidth(horizontalSizeClass) }
    private var pageHorizontalPadding: CGFloat { AsterionLayout.pagePadding(horizontalSizeClass) }
    private let novelPageSize = 50

    private var browseGridColumns: [GridItem] {
        AsterionLayout.posterColumns(horizontalSizeClass)
    }

    private var displayNovels: [Novel] {
        Novel.ranked(novels)
    }

    private var homeNovelShelf: [Novel] {
        Array(personalizedNovels.filter { $0.imageUrl?.isEmpty == false }.prefix(8))
    }

    private var personalizedNovels: [Novel] {
        let interests = Set(
            preferredGenres
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        return NovelPersonalizer.order(novels, preferredGenres: interests)
    }

    /// Billboard items: newest anime, films, and novels interleaved.
    private var heroItems: [HomeHeroItem] {
        let anime = featuredAnime.prefix(2).map(HomeHeroItem.anime)
        let movies = featuredMovies.prefix(2).map(HomeHeroItem.movie)
        let novels = homeNovelShelf.prefix(2).map(HomeHeroItem.novel)
        let lanes = [Array(anime), Array(movies), Array(novels)]
        let longest = lanes.map(\.count).max() ?? 0
        return (0..<longest).flatMap { index in
            lanes.compactMap { lane in lane.indices.contains(index) ? lane[index] : nil }
        }
    }

    private var homeSkeleton: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            AsterionSkeleton(cornerRadius: 3).frame(width: 90, height: 10)
            AsterionSkeleton(cornerRadius: 6).frame(width: 260, height: 34)
            AsterionSkeleton(cornerRadius: 4).frame(width: 200, height: 12)
            AsterionSkeleton(cornerRadius: 22).frame(width: 150, height: 44)
                .padding(.top, 6)
        }
        .padding(.horizontal, pageHorizontalPadding)
        .padding(.bottom, 28)
        .frame(height: 520, alignment: .bottomLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var continueWatchingItems: [MediaPlaybackProgress] {
        mediaAccountService.snapshot.progress
            .filter { !$0.completed && $0.positionSeconds > 0 }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Reading and watching merged by recency: whatever was opened last
    /// leads, whichever kind it is.
    private var continueItems: [HomeContinueItem] {
        let novels = continueReadingItems
            .filter { !$0.progress.isFinished }
            .map { HomeContinueItem.novel($0) }
        let watching = continueWatchingItems.map { HomeContinueItem.watching($0) }
        return Array(
            (novels + watching)
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(Self.continueSlots)
        )
    }

    private static let continueSlots = 8

    private struct ContinueReadingItem: Identifiable {
        let novel: Novel
        let chapter: Chapter
        let allChapters: [Chapter]
        let progress: NovelProgress
        let updatedAt: Date
        var id: String { novel.id }
    }

    private enum HomeContinueItem: Identifiable {
        case novel(ContinueReadingItem)
        case watching(MediaPlaybackProgress)

        var id: String {
            switch self {
            case .novel(let item): "novel-\(item.id)"
            case .watching(let item): "watch-\(item.id)"
            }
        }

        var updatedAt: Date {
            switch self {
            case .novel(let item): item.updatedAt
            case .watching(let item): item.updatedAt
            }
        }
    }

    private struct ContinueReadingDestination: Identifiable, Hashable {
        let novel: Novel
        let chapter: Chapter
        let allChapters: [Chapter]
        var id: String { "\(novel.id)-\(chapter.id)" }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            BrowseCatalogChrome {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if mode == .home {
                        if heroItems.isEmpty {
                            if loading || novels.isEmpty {
                                homeSkeleton
                            } else {
                                pageTitleSection
                                    .padding(.top, 64)
                            }
                        } else {
                            HomeHero(items: heroItems, selection: $heroIndex)
                        }
                    }
                    if mode == .browse {
                        searchSection
                    }

                    if mode == .home {
                        contentSection
                    } else if loading && novels.isEmpty {
                        loadingSection
                    } else if failed && novels.isEmpty {
                        errorSection
                    } else if novels.isEmpty {
                        emptySection
                    } else {
                        contentSection
                    }
                }
                .padding(.bottom, 24)
                .frame(maxWidth: contentMaxWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
            .ignoresSafeArea(.container, edges: mode == .home ? .top : [])
            .overlay(alignment: .top) {
                if mode == .home {
                    // Keeps the status bar legible over artwork and shelves.
                    LinearGradient(
                        colors: [Color.asterionBackground.opacity(0.85), Color.asterionBackground.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 64)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if mode == .home {
                    AsterionCircleIconButton(systemName: "magnifyingglass", accessibilityLabel: "Search everything") {
                        navigationPath.append(HomeSearchRoute())
                    }
                    .padding(.top, 6)
                    .padding(.trailing, 16)
                }
            }
            .refreshable {
                await loadNovels(search: debouncedSearch)
                scheduleDownloadAhead(force: true)
            }
            .background {
                AsterionBackdrop()
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Novel.self) { novel in
                NovelDetailView(novel: novel) {
                    popNovelPath()
                }
            }
            .navigationDestination(for: AnimeTitle.self) { title in
                AnimeDetailView(title: title)
            }
            .navigationDestination(for: MovieTitle.self) { title in
                MovieDetailView(title: title)
            }
            .navigationDestination(for: FootballMatch.self) { match in
                FootballDetailView(match: match)
            }
            .navigationDestination(for: HomeSearchRoute.self) { _ in
                HomeSearchView()
            }
            .navigationDestination(item: $continueReadingDestination) { destination in
                ReaderView(
                    initialChapter: destination.chapter,
                    novel: destination.novel,
                    allChapters: destination.allChapters
                )
            }
            .task {
                await loadNovels()
                scheduleDownloadAhead()
            }
            .task {
                guard mode == .home else { return }
                await loadEntertainmentHighlights()
            }
            .onAppear { scheduleDownloadAhead() }
            .debounceSearch(text: $search, debouncedText: $debouncedSearch)
            .onChange(of: debouncedSearch) { _, newValue in
                Task { await loadNovels(search: newValue) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .asterionContinueReadingRequested)) { _ in
                Task { await openContinueReadingFromWidget() }
            }
            }
        }
        .enableInjection()
    }

    /// Keeps the next chapters and episodes of in-progress titles ready offline.
    private func scheduleDownloadAhead(force: Bool = false) {
        guard mode == .home, downloadAheadEnabled, debouncedSearch.isEmpty else { return }
        let reading = continueReadingItems.map {
            DownloadAheadNovel(novel: $0.novel, currentChapter: $0.chapter, chapters: $0.allChapters)
        }
        DownloadAheadCoordinator.shared.schedule(
            novels: reading,
            watching: mediaAccountService.snapshot.progress,
            apiClient: apiClient,
            videoDownloads: offlineVideoDownloadService,
            force: force
        )
    }

    private func popNovelPath() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
    }

    // MARK: - Search

    private var pageTitleSection: some View {
        AsterionPageHeader(
            title: mode == .home ? "Home" : "Novels",
            style: mode == .home ? .wordmark : .page
        )
        .padding(.horizontal, pageHorizontalPadding)
        .padding(.top, isDesktop ? 12 : 0)
        .padding(.bottom, 12)
    }

    private var searchSection: some View {
        SearchInputView(text: $search)
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.vertical, 8)
    }

    // MARK: - Loading / Error / Empty

    private var loadingSection: some View {
        LazyVGrid(columns: browseGridColumns, spacing: 18) {
            ForEach(0..<6, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    AsterionSkeleton(cornerRadius: 10)
                        .aspectRatio(2 / 3, contentMode: .fit)
                    AsterionSkeleton(cornerRadius: 3).frame(width: 110, height: 10)
                    AsterionSkeleton(cornerRadius: 3).frame(width: 70, height: 8)
                }
            }
        }
        .padding(.horizontal, pageHorizontalPadding)
        .padding(.top, 8)
        .accessibilityLabel("Loading novels")
    }

    private var errorSection: some View {
        VStack(spacing: 16) {
            AsterionEmptyState(
                symbol: "wifi.exclamationmark",
                title: "Couldn't load novels",
                message: "Pull down or try again when the connection returns."
            )
            Button {
                Task { await loadNovels(search: debouncedSearch) }
            } label: {
                Text("Try again")
                    .font(.asterionReading(15, weight: .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
            }
            .buttonStyle(AsterionOutlineButtonStyle())
        }
        .padding(.vertical, 20)
    }

    private var emptySection: some View {
        AsterionEmptyState(
            symbol: "book.closed",
            title: debouncedSearch.isEmpty ? "No novels found" : "No novels match your search",
            message: debouncedSearch.isEmpty ? "The catalog will appear here." : "Try another title or author."
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var contentSection: some View {
        if mode == .browse {
            browseGridSection
        } else {
            if debouncedSearch.isEmpty && !continueItems.isEmpty {
                homeSection(title: "Continue", detail: "Pick up where you left off") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 13) {
                            ForEach(continueItems) { item in
                                continueLink(for: item)
                            }
                        }
                    }
                }
            }
            catalogShelves
        }
    }

    // MARK: - Browse Grid

    private var browseGridSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !debouncedSearch.isEmpty {
                Text("Results")
                    .font(.asterionTitle(17, weight: .bold))
                    .foregroundStyle(Color.asterionText)
            }

            LazyVGrid(columns: browseGridColumns, spacing: isWideCanvas ? 16 : 14) {
                ForEach(displayNovels) { novel in
                    NavigationLink(value: novel) {
                        NovelTileCard(novel: novel)
                    }
                    .buttonStyle(.plain)
                }
            }

        }
        .padding(.horizontal, pageHorizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var catalogShelves: some View {
        if !homeNovelShelf.isEmpty {
            homeSection(title: "Novels", detail: "Picked for you") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 13) {
                        ForEach(homeNovelShelf) { novel in
                            NavigationLink(value: novel) {
                                HomeNovelCard(novel: novel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }

        if !featuredAnime.isEmpty {
            homeSection(title: "Anime", detail: "Popular now") {
                horizontalMediaShelf(
                    items: featuredAnime,
                    title: { $0.title },
                    imageURL: { $0.imageURL }
                )
            }
        }

        if !featuredMovies.isEmpty {
            homeSection(title: "Films", detail: "Trending") {
                horizontalMediaShelf(
                    items: featuredMovies,
                    title: { $0.title },
                    imageURL: { $0.imageURL }
                )
            }
        }

        if !liveMatches.isEmpty {
            homeSection(title: "Football", detail: liveMatches.contains(where: \.isLive) ? "In play now" : "Coming up") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(liveMatches) { match in
                            NavigationLink(value: match) {
                                HomeMatchCard(match: match)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func continueLink(for item: HomeContinueItem) -> some View {
        switch item {
        case .novel(let reading):
            NavigationLink {
                ReaderView(
                    initialChapter: reading.chapter,
                    novel: reading.novel,
                    allChapters: reading.allChapters
                )
            } label: {
                AsterionReadingContinueCard(
                    title: reading.novel.title,
                    progress: reading.progress,
                    coverURL: reading.novel.imageUrl.flatMap(URL.init(string:))
                ) {
                    NovelPosterArt(novel: reading.novel)
                }
            }
            .buttonStyle(.plain)
        case .watching(let watching):
            NavigationLink {
                MediaDestinationView(
                    mediaType: watching.mediaType,
                    contentID: watching.contentId,
                    title: watching.title,
                    imageURL: watching.imageURL
                )
            } label: {
                AsterionContinueCard(
                    title: watching.title,
                    subtitle: watching.unitTitle ?? watching.mediaType.title,
                    percentage: watching.percentage
                ) {
                    AsyncImage(url: watching.imageURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color.asterionSurface
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func homeSection<Content: View>(
        title: String,
        detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            AsterionSectionLabel(title: title, detail: detail)
                .padding(.horizontal, pageHorizontalPadding)
            content()
                .contentMargins(.horizontal, pageHorizontalPadding, for: .scrollContent)
        }
        .padding(.top, 30)
    }

    private func horizontalMediaShelf<Item: Identifiable & Hashable>(
        items: [Item],
        title: @escaping (Item) -> String,
        imageURL: @escaping (Item) -> URL?
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 13) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        HomeMediaCard(title: title(item), imageURL: imageURL(item))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func loadEntertainmentHighlights() async {
        async let animeRequest = EntertainmentAPI.shared.fetchPopularAnime()
        async let movieRequest = EntertainmentAPI.shared.fetchMovies(kind: .movies)
        async let footballRequest = EntertainmentAPI.shared.fetchFootball(section: .live)

        if let anime = try? await animeRequest {
            featuredAnime = Array(anime.filter { $0.imageURL != nil }.prefix(8))
        }
        if let movies = try? await movieRequest {
            featuredMovies = Array(movies.filter { $0.imageURL != nil }.prefix(8))
        }
        if let matches = try? await footballRequest {
            liveMatches = Array(matches.prefix(6))
        }
    }

    // MARK: - Data

    private func loadNovels(search: String = "") async {
        loading = novels.isEmpty
        defer { loading = false }

        do {
            if mode == .browse {
                // Match desktop: sort the complete catalog, not each source page.
                novels = try await apiClient.fetchAllNovels(search: search)
            } else {
                novels = try await apiClient.fetchNovelsPage(limit: novelPageSize, search: search).data
            }
            if !novels.isEmpty {
                await OfflineChapterStore.shared.saveCatalog(novels)
            }
            if search.isEmpty {
                await loadContinueReading()
            } else {
                continueReadingItems = []
            }
            failed = false
        } catch {
            if !Task.isCancelled {
                let cached = await OfflineChapterStore.shared.loadCatalog()
                if !cached.isEmpty {
                    if search.isEmpty {
                        novels = cached
                    } else {
                        let q = search.lowercased()
                        novels = cached.filter {
                            $0.title.lowercased().contains(q) || ($0.author?.lowercased().contains(q) ?? false)
                        }
                    }
                    if search.isEmpty {
                        await loadContinueReading()
                    } else {
                        continueReadingItems = []
                    }
                    failed = false
                } else if novels.isEmpty {
                    failed = true
                }
            }
        }
    }

    private func loadContinueReading() async {
        var byNovel: [String: ReadingProgress] = [:]
        if let remote = try? await apiClient.fetchAllReadingProgress() {
            for item in remote {
                byNovel[item.novelId] = item
            }
        }
        for item in readingProgressService.queuedProgressList() {
            if let existing = byNovel[item.novelId],
               (existing.lastReadAt ?? .distantPast) >= (item.lastReadAt ?? .distantPast) {
                continue
            }
            byNovel[item.novelId] = item
        }
        if let snapshot = ContinueReadingStore.loadSnapshot(), byNovel[snapshot.novelId] == nil {
            byNovel[snapshot.novelId] = ReadingProgress(
                id: "snapshot-\(snapshot.novelId)",
                userId: "local",
                novelId: snapshot.novelId,
                chapterId: snapshot.chapterId,
                currentLine: 0,
                totalLines: 1,
                percentage: snapshot.inChapterFraction * 100,
                updatedAt: snapshot.updatedAt
            )
        }
        continueReadingItems = await buildContinueReadingItems(from: Array(byNovel.values))
    }

    private func buildContinueReadingItems(from progress: [ReadingProgress]) async -> [ContinueReadingItem] {
        let catalogById = Dictionary(uniqueKeysWithValues: novels.map { ($0.id, $0) })
        let cachedById = Dictionary(
            uniqueKeysWithValues: (await OfflineChapterStore.shared.loadCatalog()).map { ($0.id, $0) }
        )
        let sortedProgress = progress.sorted {
            ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast)
        }
        var seenNovelIds = Set<String>()
        var orderedEntries: [(novel: Novel, progress: ReadingProgress)] = []
        for p in sortedProgress where seenNovelIds.insert(p.novelId).inserted {
            guard let novel = await resolveContinueNovel(
                id: p.novelId,
                catalogById: catalogById,
                cachedById: cachedById
            ) else { continue }
            orderedEntries.append((novel: novel, progress: p))
        }
        // Finished novels drop out, so look a little past the visible slots.
        let candidates = Array(orderedEntries.prefix(Self.continueSlots + 4))

        var built: [ContinueReadingItem] = []
        for entry in candidates where built.count < Self.continueSlots {
            let novel = entry.novel
            let p = entry.progress

            guard let chapter = await ReadingPositionResolver.chapter(
                id: p.chapterId,
                novelId: novel.id,
                apiClient: apiClient
            ) else { continue }

            // A finished novel by the catalog's count skips the chapter list.
            let catalogProgress = NovelProgress(
                progress: p,
                chapterNumber: chapter.chapterNumber,
                totalChapters: novel.catalogChapterCount
            )
            if catalogProgress.isFinished { continue }

            let chapterList: [Chapter]
            var loadedChapterCount: Int?
            do {
                let fetchedChapters = try await apiClient.fetchAllChapters(novelId: novel.id)
                await OfflineChapterStore.shared.saveChapterList(
                    novelId: novel.id,
                    chapters: fetchedChapters,
                    mergeWithExisting: true
                )
                chapterList = fetchedChapters
                loadedChapterCount = fetchedChapters.count
            } catch {
                let cached = await OfflineChapterStore.shared.loadChapterList(novelId: novel.id)
                chapterList = cached.isEmpty ? [chapter] : cached
            }
            let containsCurrent = chapterList.contains(where: { $0.id == chapter.id })
            let allChapters = containsCurrent ? chapterList : ([chapter] + chapterList)

            let progress = NovelProgress(
                progress: p,
                chapterNumber: chapter.chapterNumber,
                totalChapters: NovelProgress.totalChapters(
                    loaded: loadedChapterCount,
                    catalog: novel.totalChapters
                )
            )
            if progress.isFinished { continue }

            built.append(
                ContinueReadingItem(
                    novel: novel,
                    chapter: chapter,
                    allChapters: allChapters,
                    progress: progress,
                    updatedAt: p.lastReadAt ?? .distantPast
                )
            )
        }

        return built
    }

    private func resolveContinueNovel(
        id: String,
        catalogById: [String: Novel],
        cachedById: [String: Novel]
    ) async -> Novel? {
        if let novel = catalogById[id] { return novel }
        if let novel = cachedById[id] { return novel }
        return try? await apiClient.fetchNovel(id: id)
    }

    private func openContinueReadingFromWidget() async {
        guard let snapshot = ContinueReadingStore.loadSnapshot() else { return }

        let novel: Novel
        if let existing = novels.first(where: { $0.id == snapshot.novelId }) {
            novel = existing
        } else {
            let cachedNovels = await OfflineChapterStore.shared.loadCatalog()
            if let cached = cachedNovels.first(where: { $0.id == snapshot.novelId }) {
                novel = cached
            } else if let fetched = try? await apiClient.fetchNovel(id: snapshot.novelId) {
                novel = fetched
            } else {
                return
            }
        }

        let chapter: Chapter
        if let cachedChapter = await OfflineChapterStore.shared.chapter(id: snapshot.chapterId) {
            chapter = cachedChapter
        } else if let fetchedChapter = try? await apiClient.fetchChapter(id: snapshot.chapterId) {
            chapter = fetchedChapter
            await OfflineChapterStore.shared.cacheChapter(fetchedChapter)
        } else {
            return
        }

        let chapterList: [Chapter]
        let cachedList = await OfflineChapterStore.shared.loadChapterList(novelId: novel.id)
        if !cachedList.isEmpty {
            chapterList = cachedList
        } else if let fetchedChapters = try? await apiClient.fetchAllChapters(novelId: novel.id) {
            await OfflineChapterStore.shared.saveChapterList(
                novelId: novel.id,
                chapters: fetchedChapters,
                mergeWithExisting: true
            )
            chapterList = fetchedChapters
        } else {
            chapterList = [chapter]
        }

        let allChapters = chapterList.contains(where: { $0.id == chapter.id }) ? chapterList : ([chapter] + chapterList)
        continueReadingDestination = nil
        continueReadingDestination = ContinueReadingDestination(
            novel: novel,
            chapter: chapter,
            allChapters: allChapters
        )
    }
}

enum NovelPersonalizer {
    static func order(_ novels: [Novel], preferredGenres: Set<String>) -> [Novel] {
        let normalizedGenres = Set(
            preferredGenres.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        )

        // Score once so the comparator stays cheap and deterministic.
        let scored = novels.map { novel in
            (novel: novel, matches: matchCount(for: novel, preferredGenres: normalizedGenres))
        }
        return scored.sorted { left, right in
            if left.matches != right.matches {
                return left.matches > right.matches
            }
            let leftRating = left.novel.rating ?? 0
            let rightRating = right.novel.rating ?? 0
            if leftRating != rightRating {
                return leftRating > rightRating
            }
            if left.novel.rankPosition != right.novel.rankPosition {
                return left.novel.rankPosition < right.novel.rankPosition
            }
            return left.novel.title.localizedStandardCompare(right.novel.title) == .orderedAscending
        }
        .map(\.novel)
    }

    private static func matchCount(for novel: Novel, preferredGenres: Set<String>) -> Int {
        Set(
            (novel.genres ?? []).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        )
        .intersection(preferredGenres)
        .count
    }
}

private struct HomeNovelCard: View {
    let novel: Novel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var posterSize: CGSize {
        AsterionLayout.shelfPosterSize(horizontalSizeClass)
    }

    var body: some View {
        HomePosterCaption(
            title: novel.title,
            subtitle: novel.author ?? "Unknown author",
            width: posterSize.width
        ) {
            NovelPosterArt(novel: novel)
                .frame(width: posterSize.width, height: posterSize.height)
        }
    }
}

private struct HomeMediaCard: View {
    let title: String
    let imageURL: URL?
    var subtitle: String? = nil
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var posterSize: CGSize {
        AsterionLayout.shelfPosterSize(horizontalSizeClass)
    }

    var body: some View {
        HomePosterCaption(title: title, subtitle: subtitle, width: posterSize.width) {
            AsyncImage(url: imageURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.asterionSurface
                }
            }
            .frame(width: posterSize.width, height: posterSize.height)
        }
    }
}

/// Poster with its title and subtitle set beneath the art.
struct HomePosterCaption<Artwork: View>: View {
    let title: String
    var subtitle: String?
    let width: CGFloat
    @ViewBuilder var artwork: () -> Artwork

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            artwork()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08))
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.asterionReading(13, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.asterionReading(11.5))
                        .foregroundStyle(Color.asterionMuted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(width: width, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct HomeMatchCard: View {
    let match: FootballMatch

    private var homeName: String {
        match.teams?.home?.name ?? match.displayTitle.components(separatedBy: " vs ").first ?? match.title
    }

    private var awayName: String {
        match.teams?.away?.name
            ?? match.displayTitle.components(separatedBy: " vs ").dropFirst().first
            ?? ""
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                if match.isLive {
                    AsterionLiveBadge()
                } else {
                    AsterionEyebrow(
                        text: match.kickoff.formatted(.relative(presentation: .named)),
                        color: .asterionMuted
                    )
                }
                Spacer()
            }

            HStack(alignment: .center, spacing: 8) {
                teamColumn(name: homeName, badgeURL: match.teams?.home?.badgeURL)
                VStack(spacing: 3) {
                    Text(match.isLive ? "vs" : match.kickoff.formatted(date: .omitted, time: .shortened))
                        .font(.asterionMono(match.isLive ? 12 : 15, weight: .semibold))
                        .foregroundStyle(match.isLive ? Color.asterionMuted : Color.asterionText)
                    if !match.isLive {
                        Text(match.kickoff.formatted(.dateTime.weekday(.abbreviated).day()))
                            .font(.asterionReading(10.5, weight: .medium))
                            .foregroundStyle(Color.asterionMuted)
                    }
                }
                .frame(width: 70)
                teamColumn(name: awayName, badgeURL: match.teams?.away?.badgeURL)
            }
        }
        .padding(16)
        .frame(width: 290)
        .asterionPanel(cornerRadius: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(match.displayTitle), \(match.isLive ? "live" : "upcoming")")
    }

    private func teamColumn(name: String, badgeURL: URL?) -> some View {
        VStack(spacing: 8) {
            AsyncImage(url: badgeURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Text(Self.initials(for: name))
                        .font(.system(size: 12, weight: .bold).width(.expanded))
                        .foregroundStyle(Color.asterionText.opacity(0.8))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.16)))
                }
            }
            .frame(width: 42, height: 42)

            Text(name)
                .font(.asterionReading(12.5, weight: .semibold))
                .foregroundStyle(Color.asterionText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    static func initials(for name: String) -> String {
        let words = name.split(separator: " ").filter { !$0.isEmpty }
        let letters = words.count > 1 ? words.prefix(2).compactMap(\.first) : Array((words.first ?? "").prefix(3))
        return String(letters).uppercased()
    }
}

// MARK: - Novel Tile Card

struct NovelTileCard: View {
    let novel: Novel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isWideCanvas: Bool { AsterionLayout.isWide(horizontalSizeClass) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay {
                    NovelPosterArt(novel: novel)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(novel.title)
                    .font(.asterionReading(isWideCanvas ? 14 : 13, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(novel.author ?? "Unknown author")
                    .font(.asterionReading(isWideCanvas ? 12.5 : 11.5))
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

// MARK: - Status Pill

struct StatusPill: View {
    let status: String

    private var pillColor: Color {
        switch status.uppercased() {
        case "ONGOING":   return Color.asterionSuccess
        case "COMPLETED": return Color.asterionMuted
        case "HIATUS":    return Color.asterionWarning
        default:          return Color.asterionDim
        }
    }

    var body: some View {
        Text(status)
            .font(.asterionMono(9))
            .foregroundStyle(pillColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(pillColor.opacity(0.12), in: Capsule())
    }
}

// MARK: - Hero

private extension MovieTitle {
    var isSeries: Bool { type?.lowercased() == "tv" }
}

enum HomeHeroItem: Identifiable, Hashable {
    case novel(Novel)
    case anime(AnimeTitle)
    case movie(MovieTitle)

    var id: String {
        switch self {
        case .novel(let novel): "novel-\(novel.id)"
        case .anime(let title): "anime-\(title.id)"
        case .movie(let title): "movie-\(title.id)"
        }
    }

    var title: String {
        switch self {
        case .novel(let novel): novel.title
        case .anime(let title): title.title
        case .movie(let title): title.title
        }
    }

    var imageURL: URL? {
        switch self {
        case .novel(let novel): novel.imageUrl.flatMap(URL.init(string:))
        case .anime(let title): title.imageURL
        case .movie(let title): title.imageURL
        }
    }

    var eyebrow: String {
        switch self {
        case .novel(let novel): novel.genres?.first.map { "Novel · \($0)" } ?? "Novel"
        case .anime: "Popular anime"
        case .movie(let title): title.isSeries ? "Trending series" : "Trending film"
        }
    }

    var metadata: String {
        switch self {
        case .novel(let novel):
            return [novel.author, novel.rating.map { String(format: "★ %.1f", $0) }]
                .compactMap { $0 }
                .joined(separator: " · ")
        case .anime(let title):
            return [title.type?.uppercased(), title.episodeLabel]
                .compactMap { $0 }
                .joined(separator: " · ")
        case .movie(let title):
            return [title.isSeries ? "Series" : "Film", title.year, title.imdbRating.map { "★ \($0)" }]
                .compactMap { $0 }
                .joined(separator: " · ")
        }
    }

    var summary: String? {
        guard case .novel(let novel) = self else { return nil }
        let trimmed = novel.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.flatMap { $0.isEmpty ? nil : $0 }
    }

    var actionTitle: String {
        switch self {
        case .novel: "View novel"
        case .anime: "View anime"
        case .movie(let title): title.isSeries ? "View series" : "View film"
        }
    }

    var actionSymbol: String {
        switch self {
        case .novel: "book.pages"
        case .anime, .movie: "play.fill"
        }
    }
}

/// Full-bleed billboard at the top of Home. Each artwork fills the frame,
/// fades into the room, and casts its tone onto the page beneath.
private struct HomeHero: View {
    let items: [HomeHeroItem]
    @Binding var selection: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var cycleFill: CGFloat = 0

    private let cycleDuration: Double = 8

    private var height: CGFloat {
        AsterionLayout.isWide(horizontalSizeClass) ? 600 : 560
    }

    private var safeSelection: Int {
        min(max(selection, 0), max(items.count - 1, 0))
    }

    var body: some View {
        ZStack(alignment: .top) {
            // The glow is laid out at the hero's height but drawn taller, so
            // it spills under the shelves that follow.
            ArtworkGlow(
                url: items.indices.contains(safeSelection) ? items[safeSelection].imageURL : nil,
                height: height + 360
            )
            .frame(height: height, alignment: .top)

            TabView(selection: $selection) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    page(item)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: height)
            .overlay(alignment: .bottomTrailing) {
                if items.count > 1 {
                    pageIndicator
                        .padding(.trailing, 20)
                        .padding(.bottom, 32)
                }
            }
        }
        .task(id: "\(safeSelection)-\(items.count)") {
            await runCycle()
        }
        .accessibilityElement(children: .contain)
    }

    private func page(_ item: HomeHeroItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: item.imageURL, transaction: Transaction(animation: .easeOut(duration: 0.3))) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.asterionSurface.opacity(0.4)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.5),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.45), location: 0),
                        .init(color: .clear, location: 0.22),
                        .init(color: .clear, location: 0.42),
                        .init(color: .black.opacity(0.35), location: 0.75),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                AsterionEyebrow(text: item.eyebrow, color: .white.opacity(0.72))

                Text(item.title)
                    .font(.asterionTitle(32, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.4), radius: 16, y: 4)
                    .accessibilityAddTraits(.isHeader)

                if !item.metadata.isEmpty {
                    Text(item.metadata)
                        .font(.asterionReading(13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }

                if let summary = item.summary {
                    Text(summary)
                        .font(.asterionReading(14))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineSpacing(2)
                        .lineLimit(2)
                }

                destination(for: item)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 20)
            .padding(.trailing, items.count > 1 ? 70 : 0)
            .padding(.bottom, 28)
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func destination(for item: HomeHeroItem) -> some View {
        let label = Label(item.actionTitle, systemImage: item.actionSymbol)
            .font(.asterionReading(15, weight: .semibold))
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
        switch item {
        case .novel(let novel):
            NavigationLink(value: novel) { label }
                .buttonStyle(AsterionFilledButtonStyle())
        case .anime(let title):
            NavigationLink(value: title) { label }
                .buttonStyle(AsterionFilledButtonStyle())
        case .movie(let title):
            NavigationLink(value: title) { label }
                .buttonStyle(AsterionFilledButtonStyle())
        }
    }

    private var pageIndicator: some View {
        VStack(spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                Button {
                    withAnimation(.snappy) { selection = index }
                } label: {
                    ZStack(alignment: .top) {
                        Capsule().fill(.white.opacity(0.26))
                        if index == safeSelection {
                            Capsule()
                                .fill(.white)
                                .frame(height: 24 * (reduceMotion ? 1 : cycleFill))
                        }
                    }
                    .frame(width: 5, height: index == safeSelection ? 24 : 5)
                    .contentShape(Rectangle().inset(by: -8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Featured item \(index + 1) of \(items.count)")
                .accessibilityAddTraits(index == safeSelection ? .isSelected : [])
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.2), value: safeSelection)
    }

    private func runCycle() async {
        cycleFill = 0
        guard items.count > 1, !reduceMotion else { return }
        await Task.yield()
        withAnimation(.linear(duration: cycleDuration)) {
            cycleFill = 1
        }
        do {
            try await Task.sleep(for: .seconds(cycleDuration))
            while scenePhase != .active {
                try await Task.sleep(for: .seconds(1))
            }
        } catch {
            return
        }
        withAnimation(.easeInOut(duration: 0.5)) {
            selection = (safeSelection + 1) % items.count
        }
    }
}

// MARK: - Search everything

/// Pushed onto Home's stack by the floating search button.
private struct HomeSearchRoute: Hashable {}

/// One field across novels, anime, films and series, and football fixtures.
/// Results push through Home's own navigation destinations.
private struct HomeSearchView: View {
    @EnvironmentObject private var apiClient: APIClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var novels: [Novel] = []
    @State private var anime: [AnimeTitle] = []
    @State private var films: [MovieTitle] = []
    @State private var matches: [FootballMatch] = []
    @State private var matchPool: [FootballMatch]?
    @State private var pending: Set<HomeSearchSection> = []
    @State private var failed: Set<HomeSearchSection> = []

    private var pageHorizontalPadding: CGFloat { AsterionLayout.pagePadding(horizontalSizeClass) }
    private var contentMaxWidth: CGFloat { AsterionLayout.pageMaxWidth(horizontalSizeClass) }
    private var trimmedQuery: String { debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var hasResults: Bool {
        !novels.isEmpty || !anime.isEmpty || !films.isEmpty || !matches.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AsterionCircleIconButton(systemName: "chevron.left", accessibilityLabel: "Back") {
                    dismiss()
                }
                SearchInputView(text: $query, placeholder: "Novels, anime, films, teams", autoFocus: true)
            }
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .frame(maxWidth: contentMaxWidth)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    results
                }
                .padding(.bottom, 32)
                .frame(maxWidth: contentMaxWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity)
        .background { AsterionBackdrop() }
        .toolbar(.hidden, for: .navigationBar)
        .debounceSearch(text: $query, debouncedText: $debouncedQuery)
        .task(id: trimmedQuery) {
            await search(trimmedQuery)
        }
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        if trimmedQuery.isEmpty {
            AsterionEmptyState(
                symbol: "magnifyingglass",
                title: "Search everything",
                message: "Find novels, anime, films and series, or a team's next match."
            )
            .padding(.top, 40)
        } else if !hasResults && pending.isEmpty {
            if failed.count == HomeSearchSection.allCases.count {
                AsterionEmptyState(
                    symbol: "wifi.exclamationmark",
                    title: "Couldn't search right now",
                    message: "Check the connection and try again."
                )
                .padding(.top, 40)
            } else {
                AsterionEmptyState(
                    symbol: "magnifyingglass",
                    title: "No results",
                    message: "Try another title, author, or team."
                )
                .padding(.top, 40)
            }
        } else {
            ForEach(HomeSearchSection.allCases, id: \.self) { section in
                sectionView(section)
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: HomeSearchSection) -> some View {
        let count = count(for: section)
        if count > 0 {
            shelf(section, count: count) {
                switch section {
                case .novels:
                    ForEach(novels) { novel in
                        NavigationLink(value: novel) { HomeNovelCard(novel: novel) }
                            .buttonStyle(.plain)
                    }
                case .anime:
                    ForEach(anime) { title in
                        NavigationLink(value: title) {
                            HomeMediaCard(
                                title: title.title,
                                imageURL: title.imageURL,
                                subtitle: [title.type?.uppercased(), title.episodeLabel]
                                    .compactMap { $0 }
                                    .joined(separator: " · ")
                            )
                        }
                        .buttonStyle(.plain)
                    }
                case .films:
                    ForEach(films) { title in
                        NavigationLink(value: title) {
                            HomeMediaCard(
                                title: title.title,
                                imageURL: title.imageURL,
                                subtitle: [title.isSeries ? "Series" : "Film", title.year]
                                    .compactMap { $0 }
                                    .joined(separator: " · ")
                            )
                        }
                        .buttonStyle(.plain)
                    }
                case .matches:
                    ForEach(matches) { match in
                        NavigationLink(value: match) { HomeMatchCard(match: match) }
                            .buttonStyle(.plain)
                    }
                }
            }
        } else if pending.contains(section) {
            shelf(section, count: nil) {
                ForEach(0..<4, id: \.self) { _ in
                    skeletonCard(for: section)
                }
            }
        }
    }

    private func shelf<Content: View>(
        _ section: HomeSearchSection,
        count: Int?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(section.title)
                    .font(.asterionTitle(17, weight: .bold))
                    .foregroundStyle(Color.asterionText)
                    .accessibilityAddTraits(.isHeader)
                if let count {
                    Text(count, format: .number)
                        .font(.asterionMono(12, weight: .medium))
                        .foregroundStyle(Color.asterionMuted)
                        .accessibilityLabel("\(count) results")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, pageHorizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 13) {
                    content()
                }
            }
            .contentMargins(.horizontal, pageHorizontalPadding, for: .scrollContent)
        }
        .padding(.top, 24)
    }

    @ViewBuilder
    private func skeletonCard(for section: HomeSearchSection) -> some View {
        if section == .matches {
            AsterionSkeleton(cornerRadius: 14)
                .frame(width: 290, height: 150)
        } else {
            let size = AsterionLayout.shelfPosterSize(horizontalSizeClass)
            VStack(alignment: .leading, spacing: 9) {
                AsterionSkeleton(cornerRadius: 10)
                    .frame(width: size.width, height: size.height)
                AsterionSkeleton(cornerRadius: 3).frame(width: size.width * 0.8, height: 10)
                AsterionSkeleton(cornerRadius: 3).frame(width: size.width * 0.5, height: 8)
            }
        }
    }

    private func count(for section: HomeSearchSection) -> Int {
        switch section {
        case .novels: novels.count
        case .anime: anime.count
        case .films: films.count
        case .matches: matches.count
        }
    }

    // MARK: Loading

    private func search(_ term: String) async {
        guard !term.isEmpty else {
            novels = []
            anime = []
            films = []
            matches = []
            pending = []
            failed = []
            return
        }
        pending = Set(HomeSearchSection.allCases)
        failed = []

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadNovels(term) }
            group.addTask { await self.loadAnime(term) }
            group.addTask { await self.loadFilms(term) }
            group.addTask { await self.loadMatches(term) }
        }
    }

    private func finish(_ section: HomeSearchSection, term: String, succeeded: Bool) -> Bool {
        guard !Task.isCancelled, term == trimmedQuery else { return false }
        pending.remove(section)
        if !succeeded { failed.insert(section) }
        return true
    }

    private func loadNovels(_ term: String) async {
        do {
            let found = try await apiClient.fetchNovelsPage(limit: 24, search: term).data
            guard finish(.novels, term: term, succeeded: true) else { return }
            novels = found
        } catch {
            // Offline: fall back to the cached catalog.
            let cached = await OfflineChapterStore.shared.loadCatalog()
            let needle = term.lowercased()
            let local = cached.filter {
                $0.title.lowercased().contains(needle) || ($0.author?.lowercased().contains(needle) ?? false)
            }
            guard finish(.novels, term: term, succeeded: !local.isEmpty) else { return }
            novels = Array(local.prefix(24))
        }
    }

    private func loadAnime(_ term: String) async {
        let found = try? await EntertainmentAPI.shared.fetchAnime(query: term)
        guard finish(.anime, term: term, succeeded: found != nil) else { return }
        anime = Array((found ?? []).prefix(24))
    }

    private func loadFilms(_ term: String) async {
        let found = try? await EntertainmentAPI.shared.fetchMovies(kind: .movies, query: term)
        guard finish(.films, term: term, succeeded: found != nil) else { return }
        films = Array((found ?? []).prefix(24))
    }

    private func loadMatches(_ term: String) async {
        if matchPool == nil {
            async let live = try? EntertainmentAPI.shared.fetchFootball(section: .live)
            async let schedule = try? EntertainmentAPI.shared.fetchFootball(section: .schedule)
            let fetchedLive = await live
            let fetchedSchedule = await schedule
            if fetchedLive != nil || fetchedSchedule != nil {
                var seen = Set<String>()
                matchPool = ((fetchedLive ?? []) + (fetchedSchedule ?? []))
                    .filter { seen.insert($0.id).inserted }
            }
        }
        guard let pool = matchPool else {
            if finish(.matches, term: term, succeeded: false) { matches = [] }
            return
        }
        let found = pool.filter { $0.matchesTeam(term) }
        guard finish(.matches, term: term, succeeded: true) else { return }
        matches = Array(found.prefix(24))
    }
}

private enum HomeSearchSection: CaseIterable, Hashable {
    case novels
    case anime
    case films
    case matches

    var title: String {
        switch self {
        case .novels: "Novels"
        case .anime: "Anime"
        case .films: "Films & series"
        case .matches: "Matches"
        }
    }
}

private extension FootballMatch {
    /// Matches by either team's name, falling back to the fixture title.
    func matchesTeam(_ term: String) -> Bool {
        let needle = term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let names = [teams?.home?.name, teams?.away?.name, title].compactMap { $0 }
        return names.contains {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(needle)
        }
    }
}
