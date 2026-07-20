import SwiftUI

struct HomeDashboardView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var mediaDownloads: MediaDownloadManager
    @Environment(\.openWindow) private var openWindow

    @ObservedObject var animeStore: AnimeStore
    @ObservedObject var movieStore: MovieStore
    @ObservedObject var footballStore: FootballStore

    let query: String
    let selectNovel: (Novel) -> Void
    let selectAnime: (AnimeTitle) -> Void
    let selectMovie: (MovieTitle) -> Void
    let selectFootball: (FootballMatch) -> Void
    let showAccount: () -> Void
    let showDownloads: () -> Void

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
        .background(.background)
        .navigationTitle("Home")
        .task(id: normalizedQuery) {
            await loadContent()
        }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                homeHeader

                if let first = resumeItems.first {
                    ResumeSpotlight(item: first) { resume(first) }
                } else {
                    welcomeSpotlight
                }

                if !resumeItems.isEmpty {
                    continueShelf
                }

                if !liveMatches.isEmpty {
                    liveShelf
                }

                if !animeStore.seasonalTitles.isEmpty {
                    posterShelf(
                        title: animeStore.season.title,
                        subtitle: "Anime airing in the current season.",
                        items: animeStore.seasonalTitles.map(HomeCatalogItem.anime)
                    )
                }

                if !freshItems.isEmpty {
                    posterShelf(
                        title: "Fresh across Asterion",
                        subtitle: "New anime, trending movies, and standout novels.",
                        items: freshItems
                    )
                }

                activityOverview
                serviceNotices
            }
            .frame(maxWidth: 1_180, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 26)
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .hidingScrollIndicators()
    }

    private var homeHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.asterionDisplay(30, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                Text("Your stories, screens, and live matches in one place.")
                    .font(.callout)
                    .foregroundStyle(Color.asterionMuted)
            }
            Spacer()
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.asterionMono(11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.asterionMuted)
                .textCase(.uppercase)
        }
    }

    private var greeting: String {
        guard let name = model.signedInUser?.name
            .split(separator: " ")
            .first
            .map(String.init), !name.isEmpty else {
            return "Welcome to Asterion"
        }
        return "Welcome back, \(name)"
    }

    private var welcomeSpotlight: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("MAKE ASTERION YOURS")
                    .font(.asterionMono(10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Color.asterionAccent)
                Text("Start a story. Watch something unforgettable.")
                    .font(.asterionDisplay(27, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                Text("Your latest novel, episode, or movie will be ready to resume here.")
                    .font(.callout)
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(2)
                if let first = freshItems.first {
                    Button("Explore \(first.kindTitle)") { select(first) }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .tint(.asterionAccent)
                }
            }
            Spacer()
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 82, weight: .light))
                .foregroundStyle(Color.asterionAccent.opacity(0.72))
                .accessibilityHidden(true)
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.asterionCard, Color.asterionAccent.opacity(0.13)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.08))
        }
    }

    private var continueShelf: some View {
        HomeSection(title: "Continue", subtitle: "Pick up exactly where you stopped.") {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(resumeItems) { item in
                        HomeContinueCard(item: item) { resume(item) }
                    }
                }
                .padding(.vertical, 3)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var liveShelf: some View {
        HomeSection(title: "Live now", subtitle: "Matches currently in play.") {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(liveMatches) { match in
                        HomeMatchCard(match: match) { selectFootball(match) }
                    }
                }
                .padding(.vertical, 3)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func posterShelf(
        title: String,
        subtitle: String,
        items: [HomeCatalogItem]
    ) -> some View {
        HomeSection(title: title, subtitle: subtitle) {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(items) { item in
                        HomePosterCard(item: item) { select(item) }
                    }
                }
                .padding(.vertical, 3)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var activityOverview: some View {
        HomeSection(title: "Your Asterion", subtitle: "A quick look at your library and activity.") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 14)],
                spacing: 14
            ) {
                HomeMetricCard(
                    value: model.libraryNovelIDs.count + model.mediaBookmarks.count,
                    label: "Saved titles",
                    systemImage: "bookmark.fill",
                    action: showAccount
                )
                HomeMetricCard(
                    value: model.offlineDownloads.count { $0.phase == .completed }
                        + mediaDownloads.completedCount,
                    label: "Downloads",
                    systemImage: "arrow.down.circle.fill",
                    action: showDownloads
                )
                HomeMetricCard(
                    value: resumeItems.count,
                    label: "In progress",
                    systemImage: "play.circle.fill",
                    action: showAccount
                )
                HomeMetricCard(
                    value: model.mediaStats.activityLast30Days,
                    label: "Watched recently",
                    systemImage: "calendar.badge.clock",
                    action: showAccount
                )
            }
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
                                columns: [GridItem(.adaptive(minimum: 122, maximum: 150), spacing: 22)],
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
                    .frame(maxWidth: 1_180, alignment: .leading)
                    .padding(.horizontal, 32)
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

