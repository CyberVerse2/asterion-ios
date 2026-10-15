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
    @AppStorage("asterion.onboarding.genres") private var preferredGenres = ""
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

    private var continueWatchingItems: [MediaPlaybackProgress] {
        mediaAccountService.snapshot.progress
            .filter { !$0.completed && $0.positionSeconds > 0 }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var continueItems: [HomeContinueItem] {
        let novels = continueReadingItems.map { HomeContinueItem.novel($0) }
        let watching = continueWatchingItems.map { HomeContinueItem.watching($0) }
        let novelSlots = min(novels.count, 4)
        let watchSlots = min(watching.count, 8 - novelSlots)
        return (Array(novels.prefix(novelSlots)) + Array(watching.prefix(watchSlots)))
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private struct ContinueReadingItem: Identifiable {
        let novel: Novel
        let chapter: Chapter
        let allChapters: [Chapter]
        let percentage: Double
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
                        pageTitleSection
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
            .refreshable { await loadNovels(search: debouncedSearch) }
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
            .navigationDestination(item: $continueReadingDestination) { destination in
                ReaderView(
                    initialChapter: destination.chapter,
                    novel: destination.novel,
                    allChapters: destination.allChapters
                )
            }
            .task { await loadNovels() }
            .task {
                guard mode == .home else { return }
                await loadEntertainmentHighlights()
            }
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

    private func popNovelPath() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
    }

    // MARK: - Search

    private var pageTitleSection: some View {
        AsterionPageHeader(
            title: mode == .home ? "Asterion" : "Novels",
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
        HStack {
            Spacer()
            ProgressView()
                .tint(Color.goldAccent)
                .scaleEffect(1.2)
                .padding(40)
            Spacer()
        }
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
            .buttonStyle(AsterionFilledButtonStyle())
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
                homeSection(title: "Continue") {
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
                    .font(.asterionDisplay(22, weight: .medium))
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
            homeSection(title: "Novels") {
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
            homeSection(title: "Anime") {
                horizontalMediaShelf(
                    items: featuredAnime,
                    title: { $0.title },
                    imageURL: { $0.imageURL }
                )
            }
        }

        if !featuredMovies.isEmpty {
            homeSection(title: "Movies") {
                horizontalMediaShelf(
                    items: featuredMovies,
                    title: { $0.title },
                    imageURL: { $0.imageURL }
                )
            }
        }

        if !liveMatches.isEmpty {
            homeSection(title: "Live Football") {
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
                    subtitle: reading.chapter.chapterNumber > 0
                        ? "Chapter \(reading.chapter.chapterNumber)"
                        : reading.chapter.title,
                    percentage: reading.percentage
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
                    subtitle: watching.unitTitle ?? "Resume",
                    percentage: watching.percentage
                ) {
                    AsyncImage(url: watching.imageURL) { phase in
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

    private func homeSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            AsterionSectionLabel(title: title)
            content()
        }
        .padding(.horizontal, pageHorizontalPadding)
        .padding(.top, 26)
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
                percentage: snapshot.progress * 100,
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
        let topEntries = Array(orderedEntries.prefix(6))

        var built: [ContinueReadingItem] = []
        for entry in topEntries {
            let novel = entry.novel
            let p = entry.progress

            let chapter: Chapter?
            if let cached = await OfflineChapterStore.shared.chapter(id: p.chapterId) {
                chapter = cached
            } else {
                do {
                    let fetched = try await apiClient.fetchChapter(id: p.chapterId)
                    await OfflineChapterStore.shared.cacheChapter(fetched)
                    chapter = fetched
                } catch {
                    let listed = await OfflineChapterStore.shared.loadChapterList(novelId: novel.id)
                    chapter = listed.first(where: { $0.id == p.chapterId })
                }
            }
            guard let chapter else { continue }

            let chapterList: [Chapter]
            do {
                let fetchedChapters = try await apiClient.fetchAllChapters(novelId: novel.id)
                await OfflineChapterStore.shared.saveChapterList(
                    novelId: novel.id,
                    chapters: fetchedChapters,
                    mergeWithExisting: true
                )
                chapterList = fetchedChapters
            } catch {
                let cached = await OfflineChapterStore.shared.loadChapterList(novelId: novel.id)
                chapterList = cached.isEmpty ? [chapter] : cached
            }
            let containsCurrent = chapterList.contains(where: { $0.id == chapter.id })
            let allChapters = containsCurrent ? chapterList : ([chapter] + chapterList)

            let totalChapterCount = max(allChapters.count, 1)
            let chapterIndex = Double(max(chapter.chapterNumber - 1, 0))
            let withinChapterFraction = p.percentage / 100.0
            let novelPercentage = min(100, ((chapterIndex + withinChapterFraction) / Double(totalChapterCount)) * 100)

            built.append(
                ContinueReadingItem(
                    novel: novel,
                    chapter: chapter,
                    allChapters: allChapters,
                    percentage: novelPercentage,
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

        return novels.sorted { left, right in
            let leftMatches = matchCount(for: left, preferredGenres: normalizedGenres)
            let rightMatches = matchCount(for: right, preferredGenres: normalizedGenres)
            if leftMatches == rightMatches {
                return left.rankPosition < right.rankPosition
            }
            return leftMatches > rightMatches
        }
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
        VStack(alignment: .leading, spacing: 8) {
            NovelPosterArt(novel: novel)
                .frame(width: posterSize.width, height: posterSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(novel.title)
                .font(.asterionDisplay(17, weight: .medium))
                .foregroundStyle(Color.asterionText)
                .lineLimit(2)
                .frame(width: posterSize.width, height: 44, alignment: .topLeading)
            if let author = novel.author {
                Text(author)
                    .font(.asterionReading(12))
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
                    .frame(width: posterSize.width, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HomeMediaCard: View {
    let title: String
    let imageURL: URL?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var posterSize: CGSize {
        AsterionLayout.shelfPosterSize(horizontalSizeClass)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: imageURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.asterionCard
                }
            }
            .frame(width: posterSize.width, height: posterSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(title)
                .font(.asterionDisplay(17, weight: .medium))
                .foregroundStyle(Color.asterionText)
                .lineLimit(2)
                .frame(width: posterSize.width, height: 44, alignment: .topLeading)
        }
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                if match.isLive {
                    Text("Live")
                        .font(.asterionReading(12, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .overlay(Capsule().stroke(Color.red.opacity(0.35), lineWidth: 1))
                } else {
                    Text(match.kickoff, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .font(.asterionReading(12, weight: .medium))
                        .foregroundStyle(Color.asterionMuted)
                }

                Spacer()

                Text("Watch")
                    .font(.asterionReading(13, weight: .semibold))
                    .foregroundStyle(Color.asterionInk)
            }

            HStack(alignment: .top, spacing: 10) {
                teamColumn(name: homeName, badgeURL: match.teams?.home?.badgeURL)
                Text("vs")
                    .font(.asterionReading(13, weight: .medium))
                    .foregroundStyle(Color.asterionMuted)
                    .padding(.top, 14)
                teamColumn(name: awayName, badgeURL: match.teams?.away?.badgeURL)
            }
        }
        .padding(16)
        .frame(width: 272)
        .asterionInsetSurface(cornerRadius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(match.displayTitle), \(match.isLive ? "live" : "upcoming")")
    }

    private func teamColumn(name: String, badgeURL: URL?) -> some View {
        VStack(spacing: 8) {
            AsyncImage(url: badgeURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Image(systemName: "shield")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Color.asterionMuted)
                }
            }
            .frame(width: 36, height: 36)

            Text(name)
                .font(.asterionSerif(15, weight: .medium))
                .foregroundStyle(Color.asterionText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
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
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(novel.title)
                .font(.asterionDisplay(isWideCanvas ? 20 : 17, weight: .medium))
                .foregroundStyle(Color.asterionText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(novel.author ?? "Unknown")
                .font(.asterionReading(isWideCanvas ? 14 : 13))
                .foregroundStyle(Color.asterionMuted)
                .lineLimit(1)
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
        case "ONGOING":   return Color(red: 0.353, green: 0.608, blue: 0.478)
        case "COMPLETED": return Color(red: 0.545, green: 0.482, blue: 0.42)
        case "HIATUS":    return .orange
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
