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

    private var liveMatches: [FootballMatch] {
        footballStore.matches.filter(\.isLive)
    }

    private var freshItems: [HomeCatalogItem] {
        let anime = Array(animeStore.newReleaseTitles.prefix(8)).map(HomeCatalogItem.anime)
        let movies = Array(movieStore.titles.prefix(8)).map(HomeCatalogItem.movie)
        let novels = Array(model.featuredNovels.prefix(6)).map(HomeCatalogItem.novel)
        return interleaved(anime, movies, novels)
    }

    private var searchItems: [HomeCatalogItem] {
        let novels = model.novels(for: .discover, search: normalizedQuery).map(HomeCatalogItem.novel)
        let anime = animeStore.titles.map(HomeCatalogItem.anime)
        let movies = movieStore.titles.map(HomeCatalogItem.movie)
        return interleaved(anime, movies, novels)
    }

    var body: some View {
        Group {
            if normalizedQuery.count == 1 {
                ContentUnavailableView(
                    "Keep typing",
                    systemImage: "character.cursor.ibeam",
                    description: Text("Enter at least two characters to search across Asterion.")
                )
            } else if normalizedQuery.isEmpty {
                dashboard
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

    private var dashboard: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 42) {
                if !resumeItems.isEmpty {
                    continueShelf
                }

                if !liveMatches.isEmpty {
                    liveShelf
                }

                if !animeStore.seasonalTitles.isEmpty {
                    posterShelf(
                        title: animeStore.season.title,
                        items: animeStore.seasonalTitles.map(HomeCatalogItem.anime)
                    )
                }

                if !freshItems.isEmpty {
                    posterShelf(
                        title: "Fresh across Asterion",
                        items: freshItems
                    )
                }

                serviceNotices
            }
            .padding(.top, 32)
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .hidingScrollIndicators()
    }

    private var continueShelf: some View {
        HomeSection(title: "Continue") {
            HomeHorizontalShelf(
                items: resumeItems,
                itemWidth: 294,
                spacing: 18,
                height: 172,
                card: { item in
                    HomeContinueCard(item: item) { resume(item) }
                        .padding(.vertical, 3)
                }
            )
        }
    }

    private var liveShelf: some View {
        HomeSection(title: "Live now") {
            HomeHorizontalShelf(
                items: liveMatches,
                itemWidth: 330,
                spacing: 14,
                height: 180,
                card: { match in
                    HomeMatchCard(match: match) { selectFootball(match) }
                        .padding(.vertical, 3)
                }
            )
        }
    }

    private func posterShelf(
        title: String,
        items: [HomeCatalogItem]
    ) -> some View {
        HomeSection(title: title) {
            HomeHorizontalShelf(
                items: items,
                itemWidth: 168,
                spacing: 18,
                height: 258,
                card: { item in
                    HomePosterCard(item: item) { select(item) }
                        .padding(.vertical, 3)
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
                ForEach(notices, id: \.self) { notice in
                    Label(notice, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.asterionMuted)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.asterionCard, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var searchResults: some View {
        Group {
            if (animeStore.isLoadingCatalog || movieStore.isLoadingCatalog), searchItems.isEmpty {
                ProgressView("Searching Asterion…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchItems.isEmpty, footballStore.matches.isEmpty {
                ContentUnavailableView(
                    "No results",
                    systemImage: "magnifyingglass",
                    description: Text("Try another title, author, team, or competition.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        HomeSection(
                            title: "Search results",
                            subtitle: "Results across novels, anime, movies, and TV shows."
                        ) {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 156, maximum: 168), spacing: 22)],
                                alignment: .leading,
                                spacing: 26
                            ) {
                                ForEach(searchItems) { item in
                                    HomePosterCard(item: item) { select(item) }
                                }
                            }
                        }

                        if !footballStore.matches.isEmpty {
                            HomeSection(title: "Football", subtitle: "Matching live fixtures.") {
                                LazyVStack(spacing: 10) {
                                    ForEach(footballStore.matches) { match in
                                        HomeMatchCard(match: match) { selectFootball(match) }
                                    }
                                }
                            }
                        }

                        serviceNotices
                    }
                    .padding(.top, 26)
                    .padding(.bottom, 56)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .hidingScrollIndicators()
            }
        }
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
            async let football: Void = footballStore.load(section: .live)
            _ = await (anime, season, releases, movies, football)
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
        _ = await (anime, movies)
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
