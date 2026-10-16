import SwiftUI

struct HomeDashboardView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    @ObservedObject var animeStore: AnimeStore
    @ObservedObject var movieStore: MovieStore
    @ObservedObject var footballStore: FootballStore

    let query: String
    let selectNovel: (Novel) -> Void
    let selectAnime: (AnimeTitle) -> Void
    let selectMovie: (MovieTitle) -> Void
    let selectFootball: (FootballMatch) -> Void
    let showNovels: () -> Void
    @State private var featuredIndex = 0

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resumeItems: [HomeResumeItem] {
        let reading = model.continueReadingEntries.map(HomeResumeItem.reading)
        let watching = model.continueWatching
            .filter { $0.mediaType == .anime || $0.mediaType == .movie }
            .map(HomeResumeItem.watching)
        return (reading + watching).sorted { $0.updatedAt > $1.updatedAt }
    }

    private var footballMatches: [FootballMatch] {
        footballStore.matches
            .filter { $0.isLive || $0.kickoff >= .now }
            .sorted {
                if $0.isLive != $1.isLive { return $0.isLive }
                return $0.kickoff < $1.kickoff
            }
    }

    private var freshItems: [HomeCatalogItem] {
        let anime = Array(animeStore.newReleaseTitles.prefix(8)).map(HomeCatalogItem.anime)
        let movies = Array(movieStore.titles.prefix(8)).map(HomeCatalogItem.movie)
        let novels = Array(model.heroNovels.prefix(6)).map(HomeCatalogItem.novel)
        return interleaved(anime, movies, novels)
    }

    private var searchItems: [HomeCatalogItem] {
        // Ranked by relevance: title prefix, title, author, then genre.
        let novels = NovelCatalog.search(model.novels, query: normalizedQuery).map(HomeCatalogItem.novel)
        let anime = animeStore.titles.map(HomeCatalogItem.anime)
        let movies = movieStore.titles.map(HomeCatalogItem.movie)
        return interleaved(anime, movies, novels)
    }

    var body: some View {
        Group {
            if normalizedQuery.count == 1 {
                AsterionEmptyState(
                    systemImage: "character.cursor.ibeam",
                    title: "Keep typing",
                    message: "Search needs at least two characters to look across novels, anime, films, and matches."
                )
            } else if normalizedQuery.isEmpty {
                if freshItems.isEmpty, resumeItems.isEmpty, isLoadingDashboard {
                    AsterionCatalogSkeleton()
                } else {
                    dashboard
                }
            } else {
                searchResults
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.asterionMediaCanvas)
        .task(id: normalizedQuery) {
            await loadContent()
        }
    }

    private var isLoadingDashboard: Bool {
        animeStore.isLoadingCatalog || movieStore.isLoadingCatalog || model.isLoadingCatalog
    }

    private var heroItems: [HomeCatalogItem] {
        Array(freshItems.prefix(6))
    }

    private var dashboard: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: AsterionLayout.sectionSpacing) {
                if !heroItems.isEmpty {
                    hero
                } else {
                    AsterionPageHeader("Home", subtitle: greeting)
                }

                if !resumeItems.isEmpty {
                    continueShelf
                }

                novelShelf

                if !footballMatches.isEmpty {
                    footballShelf
                }

                if !animeStore.seasonalTitles.isEmpty {
                    posterShelf(
                        title: animeStore.season.title,
                        subtitle: "Airing this season",
                        items: animeStore.seasonalTitles.map(HomeCatalogItem.anime),
                        showsKind: false
                    )
                }

                if !movieStore.titles.isEmpty {
                    posterShelf(
                        title: "Films and series",
                        subtitle: "Trending now",
                        items: Array(movieStore.titles.prefix(16)).map(HomeCatalogItem.movie),
                        showsKind: false
                    )
                }

                serviceNotices
                    .padding(.horizontal, AsterionLayout.pageInset)
            }
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .hidingScrollIndicators()
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
        if let name = model.signedInUser?.name.split(separator: " ").first {
            return "\(part), \(name)."
        }
        return "\(part)."
    }

    @ViewBuilder
    private var hero: some View {
        let items = heroItems
        let safeIndex = min(featuredIndex, items.count - 1)
        let item = items[safeIndex]
        AsterionHero(
            imageURL: item.imageURL,
            fallbackSystemImage: item.systemImage,
            eyebrow: "New in \(item.kindTitle)",
            title: item.title,
            summary: item.featureSummary,
            index: safeIndex,
            count: items.count,
            select: { featuredIndex = $0 }
        ) {
            HStack(spacing: 8) {
                Text(item.badge)
                Text("·")
                Text(item.subtitle)
            }
        } actions: {
            Button { select(item) } label: {
                Label(item.primaryActionTitle, systemImage: "arrow.right")
            }
            .buttonStyle(.asterionPrimary)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var continueShelf: some View {
        HomeSection(title: "Continue", subtitle: "Pick up where you left off") {
            HomeHorizontalShelf(
                items: resumeItems,
                itemWidth: AsterionCardMetrics.landscapeWidth,
                spacing: 16,
                height: AsterionCardMetrics.landscapeShelfHeight,
                card: { item in
                    HomeContinueCard(item: item) { resume(item) }
                }
            )
        }
    }

    @ViewBuilder
    private var novelShelf: some View {
        let picks = model.novelPicks
        if model.isLoadingCatalog, picks.novels.isEmpty {
            HomeSection(title: "Novels", subtitle: "Finding your next read") {
                AsterionSkeletonShelf()
            }
        } else if !picks.novels.isEmpty {
            HomeSection(title: "Novels", subtitle: novelShelfSubtitle(picks)) {
                Button(action: showNovels) {
                    HStack(spacing: 4) {
                        Text("See all")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9.5, weight: .bold))
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.asterionMuted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open Novels")
            } content: {
                HomeHorizontalShelf(
                    items: picks.novels.map(HomeCatalogItem.novel),
                    itemWidth: AsterionCardMetrics.posterWidth,
                    spacing: 18,
                    height: AsterionCardMetrics.posterShelfHeight,
                    card: { item in
                        HomePosterCard(item: item, showsKind: false) { select(item) }
                    }
                )
            }
        }
    }

    private func novelShelfSubtitle(_ picks: NovelPicks) -> String {
        guard !picks.genres.isEmpty else { return "Top rated by readers" }
        return "Top rated, and more " + picks.genres.joined(separator: " and ").lowercased() + " for you"
    }

    private var footballShelf: some View {
        HomeSection(title: "Football", subtitle: "Live and upcoming") {
            HomeHorizontalShelf(
                items: Array(footballMatches.prefix(12)),
                itemWidth: AsterionCardMetrics.matchWidth,
                spacing: 16,
                height: AsterionCardMetrics.matchShelfHeight,
                card: { match in
                    HomeMatchCard(match: match) { selectFootball(match) }
                }
            )
        }
    }

    private func posterShelf(
        title: String,
        subtitle: String?,
        items: [HomeCatalogItem],
        showsKind: Bool
    ) -> some View {
        HomeSection(title: title, subtitle: subtitle) {
            HomeHorizontalShelf(
                items: items,
                itemWidth: AsterionCardMetrics.posterWidth,
                spacing: 18,
                height: AsterionCardMetrics.posterShelfHeight,
                card: { item in
                    HomePosterCard(item: item, showsKind: showsKind) { select(item) }
                }
            )
        }
    }

    @ViewBuilder
    private var serviceNotices: some View {
        let notices = [
            model.catalogError.map { "Novels: \($0)" },
            animeStore.catalogError.map { "Anime: \($0)" },
            animeStore.seasonError.map { "Seasonal anime: \($0)" },
            animeStore.newReleasesError.map { "Anime releases: \($0)" },
            movieStore.catalogError.map { "Movies: \($0)" },
            footballStore.error.map { "Football: \($0)" },
        ].compactMap { $0 }

        if !notices.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Some shelves could not load")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                ForEach(notices, id: \.self) { notice in
                    Label(notice, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.asterionMuted)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .asterionPanel(cornerRadius: 14)
        }
    }

    private var searchResults: some View {
        Group {
            if isSearchPending, searchItems.isEmpty {
                AsterionEmptyState(
                    systemImage: "magnifyingglass",
                    title: "Searching",
                    message: "Looking for “\(normalizedQuery)” across novels, anime, films, and matches."
                )
            } else if searchItems.isEmpty, footballStore.matches.isEmpty {
                AsterionEmptyState(
                    systemImage: "magnifyingglass",
                    title: "Nothing matches “\(normalizedQuery)”",
                    message: "Try a shorter title, an author, a team, or a competition."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AsterionLayout.sectionSpacing) {
                        AsterionPageHeader(
                            "Results",
                            subtitle: "\(searchItems.count + footballStore.matches.count) matches for “\(normalizedQuery)”"
                        )

                        if !searchItems.isEmpty {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: AsterionCardMetrics.posterWidth, maximum: AsterionCardMetrics.posterWidth), spacing: 20)],
                                alignment: .leading,
                                spacing: 28
                            ) {
                                ForEach(searchItems) { item in
                                    HomePosterCard(item: item) { select(item) }
                                }
                            }
                            .padding(.horizontal, AsterionLayout.pageInset)
                        }

                        if !footballStore.matches.isEmpty {
                            HomeSection(title: "Matches") {
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: AsterionCardMetrics.matchWidth, maximum: AsterionCardMetrics.matchWidth), spacing: 16)],
                                    alignment: .leading,
                                    spacing: 16
                                ) {
                                    ForEach(footballStore.matches) { match in
                                        HomeMatchCard(match: match) { selectFootball(match) }
                                    }
                                }
                                .padding(.horizontal, AsterionLayout.pageInset)
                            }
                        }

                        serviceNotices
                            .padding(.horizontal, AsterionLayout.pageInset)
                    }
                    .padding(.bottom, 56)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .hidingScrollIndicators()
            }
        }
    }

    /// Results are still on their way from at least one catalog. Novels
    /// filter locally but still need the catalog itself to have loaded.
    private var isSearchPending: Bool {
        animeStore.isLoadingCatalog
            || movieStore.isLoadingCatalog
            || model.isLoadingCatalog
            || (model.novels.isEmpty && model.catalogState == .idle)
    }

    private func loadContent() async {
        if normalizedQuery.isEmpty {
            footballStore.updateSearch("")
            async let anime: Void = animeStore.loadCatalog(
                section: .discover,
                query: "",
                selectsInitialTitle: false
            )
            async let season: Void = animeStore.loadCurrentSeason()
            async let releases: Void = animeStore.loadDiscoverNewReleases()
            async let movies: Void = movieStore.loadCatalog(
                section: .discover,
                query: "",
                selectsInitialTitle: false
            )
            async let football: Void = footballStore.load(section: .popular)
            async let novels: Void = model.loadCatalogIfNeeded()
            _ = await (anime, season, releases, movies, football, novels)
            return
        }

        guard normalizedQuery.count >= 2 else { return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        footballStore.updateSearch(normalizedQuery)
        async let anime: Void = animeStore.loadCatalog(
            section: .discover,
            query: normalizedQuery,
            selectsInitialTitle: false
        )
        async let movies: Void = movieStore.loadCatalog(
            section: .discover,
            query: normalizedQuery,
            selectsInitialTitle: false
        )
        async let novels: Void = model.novels.isEmpty ? model.loadCatalogIfNeeded() : ()
        _ = await (anime, movies, novels)
    }

    private func resume(_ item: HomeResumeItem) {
        switch item {
        case .reading(let entry):
            openWindow(
                value: ReaderRoute(
                    novelID: entry.novel.id,
                    chapterID: entry.progress.chapterId
                )
            )
        case .watching(let progress):
            if progress.mediaType == .anime {
                openWindow(
                    value: AnimePlayerRoute(
                        slug: progress.contentId,
                        title: progress.title,
                        initialEpisodeID: progress.unitId
                    )
                )
            } else {
                openWindow(
                    value: MoviePlayerRoute(
                        slug: progress.contentId,
                        title: progress.title,
                        initialEpisodeID: progress.unitId
                    )
                )
            }
        }
    }

    private func select(_ item: HomeCatalogItem) {
        switch item {
        case .novel(let novel): selectNovel(novel)
        case .anime(let title): selectAnime(title)
        case .movie(let title): selectMovie(title)
        }
    }

    private func interleaved(
        _ first: [HomeCatalogItem],
        _ second: [HomeCatalogItem],
        _ third: [HomeCatalogItem]
    ) -> [HomeCatalogItem] {
        let collections = [first, second, third]
        let count = collections.map(\.count).max() ?? 0
        return (0..<count).flatMap { index in
            collections.compactMap { items in
                items.indices.contains(index) ? items[index] : nil
            }
        }
    }
}
