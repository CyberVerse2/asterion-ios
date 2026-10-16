import AsterionKit
import Inject
import SwiftUI

struct HomeView: View {
    @ObserveInjection var inject
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var readingProgressService: ReadingProgressService
    @EnvironmentObject private var mediaAccountService: MediaAccountService
    @EnvironmentObject private var offlineVideoDownloadService: OfflineVideoDownloadService
    @State private var novels: [Novel] = []
    @State private var loading = false
    @State private var catalogRefreshedAt: Date?
    @State private var continueReadingItems: [ContinueReadingItem] = []
    @State private var continueReadingDestination: ContinueReadingDestination?
    @State private var navigationPath = NavigationPath()
    @State private var featuredAnime: [AnimeTitle] = []
    @State private var featuredMovies: [MovieTitle] = []
    @State private var liveMatches: [FootballMatch] = []
    @State private var heroIndex = 0
    @AppStorage("asterion.onboarding.genres") private var preferredGenres = ""
    @AppStorage("asterion.onboarding.contentTypes") private var preferredContentTypes = ""
    @AppStorage(DownloadAheadCoordinator.enabledKey) private var downloadAheadEnabled = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isDesktop: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }
    private var contentMaxWidth: CGFloat { AsterionLayout.pageMaxWidth(horizontalSizeClass) }
    private var pageHorizontalPadding: CGFloat { AsterionLayout.pagePadding(horizontalSizeClass) }

    private var preferredGenreSet: Set<String> {
        Set(
            preferredGenres
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    /// The whole catalog ordered for this reader: their genres, then rating
    /// and rank. Billboard novels come from the front of it.
    private var featuredNovels: [Novel] {
        NovelCatalog.featured(novels, preferredGenres: preferredGenreSet, limit: 16)
    }

    private var heroNovelIDs: Set<String> {
        Set(heroItems.compactMap { item in
            if case .novel(let novel) = item { return novel.id }
            return nil
        })
    }

    private var homeNovelShelf: [Novel] {
        Array(featuredNovels.filter { !heroNovelIDs.contains($0.id) }.prefix(8))
    }

    /// Billboard items, interleaved in the order of the reader's onboarding
    /// picks: a reader who chose Novels sees a novel first.
    private var heroItems: [HomeHeroItem] {
        HomeHeroLane.fill(
            slots: HomeHeroLane.slots(picks: preferredContentTypes),
            novels: featuredNovels.map(HomeHeroItem.novel),
            anime: featuredAnime.map(HomeHeroItem.anime),
            films: featuredMovies.map(HomeHeroItem.movie)
        )
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

    /// Rebuilds Continue whenever what it is built from changes: the API
    /// gaining (or losing) its session token, or the reader moving to another
    /// chapter. Before this, the shelf was built once on first appearance —
    /// on a cold launch that ran before the session token reached the API, so
    /// synced progress came back empty and the shelf stayed stale until Home
    /// re-appeared (e.g. after visiting Library).
    private var continueReloadKey: String {
        HomeContinueReload.key(
            isAuthorized: apiClient.isAuthorized,
            progress: readingProgressService.localProgress
        )
    }

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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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

                    contentSection
                }
                .padding(.bottom, 24)
                .frame(maxWidth: contentMaxWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .ignoresSafeArea(.container, edges: .top)
            .overlay(alignment: .top) {
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
            .overlay(alignment: .topTrailing) {
                AsterionCircleIconButton(systemName: "magnifyingglass", accessibilityLabel: "Search everything") {
                    navigationPath.append(HomeSearchRoute())
                }
                .padding(.top, 6)
                .padding(.trailing, 16)
            }
            .refreshable {
                await loadNovels(force: true)
                await loadContinueReading()
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
            }
            .task(id: continueReloadKey) {
                await loadContinueReading()
                scheduleDownloadAhead()
            }
            .task {
                await loadEntertainmentHighlights()
            }
            .onAppear { scheduleDownloadAhead() }
            .onReceive(NotificationCenter.default.publisher(for: .asterionContinueReadingRequested)) { _ in
                Task { await openContinueReadingFromWidget() }
            }
        }
        .enableInjection()
    }

    /// Keeps the next chapters and episodes of in-progress titles ready offline.
    private func scheduleDownloadAhead(force: Bool = false) {
        guard downloadAheadEnabled else { return }
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

    private var pageTitleSection: some View {
        AsterionPageHeader(title: "Home", style: .wordmark)
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, isDesktop ? 12 : 0)
            .padding(.bottom, 12)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentSection: some View {
        if !continueItems.isEmpty {
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
                AsterionContinueCard(
                    title: reading.novel.title,
                    progress: reading.progress,
                    fallbackSubtitle: reading.chapter.title
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

    /// The whole catalog, so featured novels are chosen by rating, rank and
    /// the reader's genres rather than by the order of the first page. The
    /// cached copy shows at once; the network copy replaces it at most every
    /// ten minutes (Home's tasks re-run each time the tab appears).
    private func loadNovels(force: Bool = false) async {
        if novels.isEmpty {
            let cached = await OfflineChapterStore.shared.loadCatalog()
            if !cached.isEmpty { novels = cached }
        }
        if !force, let catalogRefreshedAt, Date().timeIntervalSince(catalogRefreshedAt) < 600 {
            return
        }
        loading = novels.isEmpty
        defer { loading = false }
        do {
            let fetched = try await apiClient.fetchAllNovels()
            guard !Task.isCancelled else { return }
            if !fetched.isEmpty {
                novels = fetched
                catalogRefreshedAt = Date()
                await OfflineChapterStore.shared.saveCatalog(fetched)
            }
        } catch {
            // Keep the cached catalog.
        }
    }

    /// Every source of reading progress, newest per novel: synced progress
    /// (when the API has a session), this device's own reading (which also
    /// covers guests and the moments before the session token arrives),
    /// queued uploads, and the widget's snapshot.
    private func loadContinueReading() async {
        let remote = (try? await apiClient.fetchAllReadingProgress()) ?? []
        guard !Task.isCancelled else { return }
        var byNovel: [String: ReadingProgress] = [:]
        for item in readingProgressService.mergedProgress(with: remote) + readingProgressService.queuedProgressList() {
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
        let progress = Array(byNovel.values)

        // First from what is on the device, so the shelf appears at once…
        let quick = await buildContinueReadingItems(from: progress, refreshChapterLists: false)
        guard !Task.isCancelled else { return }
        continueReadingItems = quick

        // …then with fresh chapter lists, which correct the chapter counts.
        let refreshed = await buildContinueReadingItems(from: progress, refreshChapterLists: true)
        guard !Task.isCancelled else { return }
        continueReadingItems = refreshed
    }

    private func buildContinueReadingItems(
        from progress: [ReadingProgress],
        refreshChapterLists: Bool
    ) async -> [ContinueReadingItem] {
        let catalogById = Dictionary(novels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let cachedById = Dictionary(
            (await OfflineChapterStore.shared.loadCatalog()).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let sortedProgress = progress.sorted {
            ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast)
        }
        var seenNovelIds = Set<String>()
        var orderedEntries: [(novel: Novel, progress: ReadingProgress)] = []
        for p in sortedProgress where seenNovelIds.insert(p.novelId).inserted {
            guard !Task.isCancelled else { return [] }
            guard let novel = await resolveContinueNovel(
                id: p.novelId,
                catalogById: catalogById,
                cachedById: cachedById
            ) else { continue }
            orderedEntries.append((novel: novel, progress: p))
            // Finished novels drop out, so look a little past the visible slots.
            if orderedEntries.count >= Self.continueSlots + 4 { break }
        }

        var built: [ContinueReadingItem] = []
        for entry in orderedEntries where built.count < Self.continueSlots {
            guard !Task.isCancelled else { return built }
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

            var chapterList = await OfflineChapterStore.shared.loadChapterList(novelId: novel.id)
            var loadedChapterCount: Int?
            if refreshChapterLists || chapterList.isEmpty,
               let fetchedChapters = try? await apiClient.fetchAllChapters(novelId: novel.id),
               !fetchedChapters.isEmpty {
                await OfflineChapterStore.shared.saveChapterList(
                    novelId: novel.id,
                    chapters: fetchedChapters,
                    mergeWithExisting: true
                )
                chapterList = fetchedChapters
                loadedChapterCount = fetchedChapters.count
            }
            if chapterList.isEmpty { chapterList = [chapter] }
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

/// The billboard's rotation of novels, anime and films, ordered by what the
/// reader picked in onboarding.
enum HomeHeroLane: CaseIterable, Hashable {
    case novels
    case anime
    case films

    /// Onboarding's content-type title for this lane.
    var pickTitle: String {
        switch self {
        case .novels: "Novels"
        case .anime: "Anime"
        case .films: "Movies & TV"
        }
    }

    /// Billboard slots in order. Picked lanes lead and show more often (three
    /// slots for a single pick, two each otherwise); the rest get one. With
    /// no saved picks, Novels counts as picked, matching onboarding's default.
    static func slots(picks rawPicks: String) -> [HomeHeroLane] {
        let picks = Set(
            rawPicks.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        var picked = allCases.filter { picks.contains($0.pickTitle.lowercased()) }
        if picked.isEmpty { picked = [.novels] }
        let others = allCases.filter { !picked.contains($0) }
        let pickedCount = picked.count == 1 ? 3 : 2
        let lanes = picked.map { ($0, pickedCount) } + others.map { ($0, 1) }
        let rounds = lanes.map(\.1).max() ?? 0
        return (0..<rounds).flatMap { round in
            lanes.compactMap { lane, count in round < count ? lane : nil }
        }
    }

    /// Fills `slots` from each lane's items in turn; a lane that runs out
    /// simply leaves its later slots out.
    static func fill<Item>(slots: [HomeHeroLane], novels: [Item], anime: [Item], films: [Item]) -> [Item] {
        var cursors: [HomeHeroLane: Int] = [:]
        return slots.compactMap { lane in
            let items: [Item] = switch lane {
            case .novels: novels
            case .anime: anime
            case .films: films
            }
            let index = cursors[lane, default: 0]
            guard items.indices.contains(index) else { return nil }
            cursors[lane] = index + 1
            return items[index]
        }
    }
}

struct HomeNovelCard: View {
    let novel: Novel
    /// Replaces the catalog line under the poster.
    var subtitle: String? = nil
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var posterSize: CGSize {
        AsterionLayout.shelfPosterSize(horizontalSizeClass)
    }

    var body: some View {
        HomePosterCaption(
            title: novel.title,
            subtitle: subtitle ?? (novel.compactMetadata.isEmpty ? (novel.author ?? "Novel") : novel.compactMetadata),
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

                Text(novel.compactMetadata.isEmpty ? (novel.author ?? "Novel") : novel.compactMetadata)
                    .font(.asterionReading(isWideCanvas ? 12.5 : 11.5))
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([novel.title, novel.author.map { "by " + $0 }].compactMap { $0 }.joined(separator: ", "))
        .accessibilityValue(novel.compactMetadata)
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
            return [
                novel.ratingLabel,
                novel.catalogChapterCount.map { String($0) + " chapters" },
                novel.statusTitle,
                novel.author,
            ]
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
            HStack(spacing: 10) {
                NovelReadButton(novel: novel)
                NovelDetailsButton(novel: novel)
            }
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

// MARK: - Novel read action

extension NovelReadTarget {
    /// Resolves the target from synced and local progress, then the cached
    /// chapter list or the first page of chapters.
    static func resolve(
        novel: Novel,
        apiClient: APIClient,
        progressService: ReadingProgressService
    ) async -> NovelReadTarget? {
        let remote = try? await apiClient.fetchReadingProgress(novelId: novel.id)
        let saved = progressService.mergedProgress(with: remote.flatMap { $0 }.map { [$0] } ?? [])
            .first { $0.novelId == novel.id }
            ?? progressService.queuedProgress(for: novel.id)
        var cachedList = await OfflineChapterStore.shared.loadChapterList(novelId: novel.id)

        if let saved,
           let chapter = await ReadingPositionResolver.chapter(id: saved.chapterId, novelId: novel.id, apiClient: apiClient) {
            let progress = NovelProgress(
                progress: saved,
                chapterNumber: chapter.chapterNumber,
                totalChapters: NovelProgress.totalChapters(
                    loaded: cachedList.count >= (novel.catalogChapterCount ?? .max) ? cachedList.count : nil,
                    catalog: novel.totalChapters
                )
            )
            if !progress.isFinished {
                let list = cachedList.contains(where: { $0.id == chapter.id }) ? cachedList : [chapter] + cachedList
                return NovelReadTarget(chapter: chapter, chapters: list, progress: progress, resumesSavedPosition: true)
            }
            if let first = await firstChapter(novel: novel, cachedList: &cachedList, apiClient: apiClient) {
                return NovelReadTarget(chapter: first, chapters: cachedList, progress: progress, resumesSavedPosition: false)
            }
            return nil
        }

        guard let first = await firstChapter(novel: novel, cachedList: &cachedList, apiClient: apiClient) else {
            return nil
        }
        return NovelReadTarget(chapter: first, chapters: cachedList, progress: nil, resumesSavedPosition: false)
    }

    private static func firstChapter(novel: Novel, cachedList: inout [Chapter], apiClient: APIClient) async -> Chapter? {
        if let first = cachedList.first(where: { $0.chapterNumber == 1 }) { return first }
        if let page = try? await apiClient.fetchChapters(novelId: novel.id, limit: 5, offset: 0), !page.data.isEmpty {
            await OfflineChapterStore.shared.saveChapterList(novelId: novel.id, chapters: page.data, mergeWithExisting: true)
            cachedList = page.data + cachedList.filter { chapter in !page.data.contains { $0.id == chapter.id } }
            return page.data.first(where: { $0.chapterNumber == 1 }) ?? page.data.first
        }
        return cachedList.min { $0.chapterNumber < $1.chapterNumber }
    }
}

/// A novel's one lit action, straight into the reader: "Read",
/// "Continue chapter 1929" or "Read again". Falls back to the novel's page
/// when no chapter can be reached.
struct NovelReadButton: View {
    let novel: Novel
    var compact = false

    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var readingProgressService: ReadingProgressService
    @State private var target: NovelReadTarget?
    @State private var resolving = true

    private var fontSize: CGFloat { compact ? 14 : 15 }
    private var horizontalPadding: CGFloat { compact ? 18 : 22 }
    private var verticalPadding: CGFloat { compact ? 11 : 13 }

    var body: some View {
        Group {
            if let target {
                NavigationLink {
                    ReaderView(
                        initialChapter: target.chapter,
                        novel: novel,
                        allChapters: target.chapters,
                        shouldAutoResumeFromSavedProgress: target.resumesSavedPosition
                    )
                } label: {
                    label(target.title, symbol: NovelReadTarget.symbol(for: target.progress))
                }
            } else if resolving {
                Button {} label: {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.asterionOnInk)
                        Text("Read")
                    }
                    .font(.asterionReading(fontSize, weight: .semibold))
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                }
                .disabled(true)
            } else {
                NavigationLink(value: novel) {
                    label("View novel", symbol: "book.pages")
                }
            }
        }
        .buttonStyle(AsterionFilledButtonStyle())
        .layoutPriority(1)
        .task(id: "\(novel.id)-\(readingProgressService.localProgress.first { $0.novelId == novel.id }?.chapterId ?? "")") {
            let resolved = await NovelReadTarget.resolve(
                novel: novel,
                apiClient: apiClient,
                progressService: readingProgressService
            )
            guard !Task.isCancelled else { return }
            target = resolved
            resolving = false
        }
    }

    private func label(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.asterionReading(fontSize, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .fixedSize(horizontal: true, vertical: false)
    }
}

/// The smoked "Details" capsule beside a novel's read action.
struct NovelDetailsButton: View {
    let novel: Novel
    var compact = false

    var body: some View {
        NavigationLink(value: novel) {
            Text("Details")
                .font(.asterionReading(compact ? 14 : 15, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, compact ? 16 : 20)
                .padding(.vertical, compact ? 11 : 13)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(AsterionOutlineButtonStyle())
        .accessibilityLabel("Details for \(novel.title)")
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
                        NavigationLink(value: novel) {
                            HomeNovelCard(novel: novel, subtitle: searchSubtitle(for: novel))
                        }
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

    /// Like the media rows beside it: what the title is and how much of it
    /// there is ("398 chapters · Ongoing"), then the author when the catalog
    /// has neither.
    private func searchSubtitle(for novel: Novel) -> String {
        let facts = [
            novel.catalogChapterCount.map { $0 == 1 ? "1 chapter" : String($0) + " chapters" },
            novel.statusTitle,
        ].compactMap { $0 }
        if !facts.isEmpty { return facts.joined(separator: " · ") }
        return novel.author ?? "Novel"
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
