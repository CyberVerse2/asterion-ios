import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    @SceneStorage("selectedDestination") private var selectedDestinationRaw = AppDestination.home.rawValue
    @SceneStorage("selectedSection") private var selectedSectionRaw = AppSection.discover.rawValue
    @SceneStorage("selectedAnimeSection") private var selectedAnimeSectionRaw = AnimeSection.discover.rawValue
    @SceneStorage("selectedMovieSection") private var selectedMovieSectionRaw = MovieSection.discover.rawValue
    @SceneStorage("selectedFootballSection") private var selectedFootballSectionRaw = FootballSection.live.rawValue
    @SceneStorage("selectedNovelID") private var selectedNovelID = ""

    @StateObject private var animeStore = AnimeStore()
    @StateObject private var movieStore = MovieStore()
    @StateObject private var footballStore = FootballStore()
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var searchText = ""
    @State private var detailSelection: AppDetailSelection?

    private var destination: Binding<AppDestination> {
        Binding(
            get: { AppDestination(rawValue: selectedDestinationRaw) ?? .home },
            set: { newValue in
                let current = AppDestination(rawValue: selectedDestinationRaw) ?? .home
                guard newValue != current else { return }
                selectedDestinationRaw = newValue.rawValue
                searchText = ""
                detailSelection = nil
                if newValue == .novels {
                    ensureNovelSelection()
                }
            }
        )
    }

    private var section: Binding<AppSection> {
        Binding(
            get: { AppSection(rawValue: selectedSectionRaw) ?? .discover },
            set: { newValue in
                selectedSectionRaw = newValue.rawValue
                searchText = ""
                selectFirstNovel(in: newValue)
            }
        )
    }

    private var animeSection: Binding<AnimeSection> {
        Binding(
            get: { AnimeSection(rawValue: selectedAnimeSectionRaw) ?? .discover },
            set: { newValue in
                selectedAnimeSectionRaw = newValue.rawValue
                searchText = ""
            }
        )
    }

    private var movieSection: Binding<MovieSection> {
        Binding(
            get: { MovieSection(rawValue: selectedMovieSectionRaw) ?? .discover },
            set: { newValue in
                selectedMovieSectionRaw = newValue.rawValue
                searchText = ""
            }
        )
    }

    private var footballSection: Binding<FootballSection> {
        Binding(
            get: { FootballSection(rawValue: selectedFootballSectionRaw) ?? .live },
            set: { newValue in
                selectedFootballSectionRaw = newValue.rawValue
                searchText = ""
            }
        )
    }

    private var selectedNovel: Novel? {
        model.novel(id: selectedNovelID)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                selection: destination,
                searchText: $searchText
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 320)
        } detail: {
            mainContent
        }
        .navigationSplitViewStyle(.prominentDetail)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .focusedSceneValue(\.asterionDestination, destination)
        .focusedSceneValue(\.asterionSection, section)
        .focusedSceneValue(\.asterionAnimeSection, animeSection)
        .focusedSceneValue(\.asterionMovieSection, movieSection)
        .focusedSceneValue(\.asterionFootballSection, footballSection)
        .tint(.asterionAccent)
        .frame(minWidth: 1_040, minHeight: 640)
        .onAppear {
            if destination.wrappedValue == .novels, selectedNovelID.isEmpty {
                selectFirstNovel(in: section.wrappedValue)
            }
        }
        .onChange(of: model.novels) {
            if destination.wrappedValue == .novels {
                ensureNovelSelection()
            }
        }
        .onChange(of: selectedSectionRaw) {
            if destination.wrappedValue == .novels {
                selectFirstNovel(in: section.wrappedValue)
            }
        }
        .onChange(of: searchText) {
            if destination.wrappedValue == .novels {
                ensureNovelSelection()
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            if showsCatalogContextBar {
                CatalogContextBar(
                    animeStore: animeStore,
                    movieStore: movieStore,
                    destination: destination.wrappedValue,
                    novelSection: section,
                    animeSection: animeSection,
                    movieSection: movieSection,
                    footballSection: footballSection
                )
            }

            responsiveContent
        }
    }

    private var responsiveContent: some View {
        Group {
            if usesDetailPane {
                GeometryReader { geometry in
                    let dividerWidth = 1.0
                    let availableWidth = max(0, geometry.size.width - dividerWidth)
                    let minimumCatalogWidth = 480.0
                    let detailWidth = min(
                        max(300, availableWidth * 0.30),
                        max(0, availableWidth - minimumCatalogWidth)
                    )

                    HStack(spacing: 0) {
                        primaryColumn
                            .frame(width: availableWidth - detailWidth)

                        Divider()
                            .frame(width: dividerWidth)

                        detailColumn
                            .frame(width: detailWidth)
                    }
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height,
                        alignment: .leading
                    )
                }
            } else {
                primaryColumn
            }
        }
    }

    private var usesDetailPane: Bool {
        switch destination.wrappedValue {
        case .home, .continueActivity, .bookmarks, .history:
            detailSelection != nil
        case .novels, .anime, .movies, .football, .account:
            true
        case .downloads:
            false
        }
    }

    private var showsCatalogContextBar: Bool {
        switch destination.wrappedValue {
        case .novels, .anime, .movies, .football:
            true
        default:
            false
        }
    }

    @ViewBuilder
    private var primaryColumn: some View {
        switch destination.wrappedValue {
        case .home:
            HomeDashboardView(
                animeStore: animeStore,
                movieStore: movieStore,
                footballStore: footballStore,
                query: searchText,
                selectNovel: selectNovelDetail,
                selectAnime: selectAnimeDetail,
                selectMovie: selectMovieDetail,
                selectFootball: selectFootballDetail
            )

        case .novels:
            EditorialCatalogView(
                section: section.wrappedValue,
                novels: model.novels(for: section.wrappedValue, search: searchText),
                isSearching: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                selectedNovelID: $selectedNovelID
            )
            .id(section.wrappedValue)

        case .anime:
            AnimeCatalogView(
                store: animeStore,
                section: animeSection.wrappedValue,
                query: searchText
            )

        case .movies:
            MovieCatalogView(
                store: movieStore,
                section: movieSection.wrappedValue,
                query: searchText
            )

        case .football:
            FootballCatalogView(
                store: footballStore,
                section: footballSection.wrappedValue,
                query: searchText
            )

        case .continueActivity:
            UnifiedActivityView(
                mode: .continueActivity,
                query: searchText,
                selectReading: { selectNovelDetail($0.novel) },
                selectProgress: selectProgressDetail,
                selectHistory: selectHistoryDetail
            )

        case .bookmarks:
            UnifiedBookmarksView(
                query: searchText,
                selectNovel: selectNovelDetail,
                selectMedia: selectBookmarkDetail
            )

        case .downloads:
            DownloadCenterView(presentation: .library)

        case .history:
            UnifiedActivityView(
                mode: .history,
                query: searchText,
                selectReading: { selectNovelDetail($0.novel) },
                selectProgress: selectProgressDetail,
                selectHistory: selectHistoryDetail
            )

        case .account:
            AccountSummaryView()
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch destination.wrappedValue {
        case .home, .continueActivity, .bookmarks, .history:
            selectedGlobalDetail
        case .novels:
            if let selectedNovel {
                NovelDetailView(novel: selectedNovel)
                    .id(selectedNovel.id)
            } else {
                novelDetailPlaceholder
            }
        case .anime:
            AnimeDetailView(store: animeStore)
        case .movies:
            MovieDetailView(store: movieStore)
        case .football:
            FootballDetailView(store: footballStore)
        case .account:
            AccountView()
        case .downloads:
            EmptyView()
        }
    }

    @ViewBuilder
    private var selectedGlobalDetail: some View {
        Group {
            switch detailSelection {
            case .novel(let novelID):
                if let novel = model.novel(id: novelID) {
                    NovelDetailView(novel: novel)
                        .id(novel.id)
                } else {
                    detailUnavailable(
                        title: "Novel unavailable",
                        message: "This novel is no longer in the current catalog."
                    )
                }
            case .anime:
                AnimeDetailView(store: animeStore)
            case .movie:
                MovieDetailView(store: movieStore)
            case .football:
                FootballDetailView(store: footballStore)
            case .loading(let title):
                ProgressView("Loading \(title)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable(let title, let message):
                detailUnavailable(title: title, message: message)
            case nil:
                detailUnavailable(
                    title: "Select something",
                    message: "Choose a title or match to see its details."
                )
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                detailSelection = nil
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .help("Close details")
            .accessibilityLabel("Close details")
            .padding(12)
        }
    }

    private func detailUnavailable(title: String, message: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: "sidebar.right",
            description: Text(message)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private var novelDetailPlaceholder: some View {
        Group {
            if model.isLoadingCatalog {
                ProgressView("Loading the Asterion catalog…")
            } else if let error = model.catalogError {
                ContentUnavailableView {
                    Label("Catalog unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await model.loadCatalog() } }
                }
            } else {
                ContentUnavailableView(
                    "Select a novel",
                    systemImage: "book.closed",
                    description: Text("Choose a title from the catalog.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func selectNovelDetail(_ novel: Novel) {
        detailSelection = .novel(novel.id)
    }

    private func selectAnimeDetail(_ title: AnimeTitle) {
        animeStore.selectFromDashboard(title)
        detailSelection = .anime
    }

    private func selectMovieDetail(_ title: MovieTitle) {
        movieStore.selectFromDashboard(title)
        detailSelection = .movie
    }

    private func selectFootballDetail(_ match: FootballMatch) {
        footballStore.select(match)
        detailSelection = .football
    }

    private func selectBookmarkDetail(_ bookmark: MediaBookmark) {
        selectMediaDetail(
            mediaType: bookmark.mediaType,
            contentID: bookmark.contentId,
            title: bookmark.title,
            subtitle: bookmark.subtitle,
            imageURL: bookmark.imageURL
        )
    }

    private func selectProgressDetail(_ progress: MediaPlaybackProgress) {
        selectMediaDetail(
            mediaType: progress.mediaType,
            contentID: progress.contentId,
            title: progress.title,
            subtitle: progress.seasonNumber == nil ? nil : "TV Series",
            imageURL: progress.imageURL
        )
    }

    private func selectHistoryDetail(_ history: MediaHistoryEntry) {
        selectMediaDetail(
            mediaType: history.mediaType,
            contentID: history.contentId,
            title: history.title,
            subtitle: history.seasonNumber == nil ? nil : "TV Series",
            imageURL: history.imageURL
        )
    }

    private func selectMediaDetail(
        mediaType: MediaAccountType,
        contentID: String,
        title: String,
        subtitle: String?,
        imageURL: URL?
    ) {
        switch mediaType {
        case .anime:
            selectAnimeDetail(
                AnimeTitle(
                    slug: contentID,
                    title: title,
                    japaneseTitle: nil,
                    imageURL: imageURL,
                    type: subtitle,
                    episodeLabel: nil
                )
            )
        case .movie:
            selectMovieDetail(
                MovieTitle(
                    id: contentID,
                    slug: contentID,
                    title: title,
                    imageURL: imageURL,
                    imdbRating: nil,
                    runtime: nil,
                    year: nil,
                    type: subtitle == "TV Series" ? "tv" : "movie",
                    quality: nil
                )
            )
        case .football:
            loadFootballDetail(contentID: contentID, title: title)
        }
    }

    private func loadFootballDetail(contentID: String, title: String) {
        if let match = footballStore.matches.first(where: { $0.id == contentID }) {
            selectFootballDetail(match)
            return
        }

        detailSelection = .loading(title)
        Task { @MainActor in
            await footballStore.load(section: .live)
            if let match = footballStore.matches.first(where: { $0.id == contentID }) {
                selectFootballDetail(match)
            } else {
                detailSelection = .unavailable(
                    title: "Match unavailable",
                    message: "This match is no longer in the current live feed."
                )
            }
        }
    }

    private func selectFirstNovel(in section: AppSection) {
        if section == .discover, searchText.isEmpty {
            selectedNovelID = model.featuredNovels.first?.id ?? ""
        } else {
            selectedNovelID = model.novels(for: section, search: searchText).first?.id ?? ""
        }
    }

    private func ensureNovelSelection() {
        let visible = model.novels(for: section.wrappedValue, search: searchText)
        let visibleIDs: Set<String>
        if section.wrappedValue == .discover, searchText.isEmpty {
            visibleIDs = Set(
                model.featuredNovels.map(\.id)
                    + model.trendingNovels.map(\.id)
                    + model.continueReadingEntries.map(\.novel.id)
            )
        } else {
            visibleIDs = Set(visible.map(\.id))
        }

        if !visibleIDs.contains(selectedNovelID) {
            selectFirstNovel(in: section.wrappedValue)
        }
    }
}

private enum AppDetailSelection {
    case novel(String)
    case anime
    case movie
    case football
    case loading(String)
    case unavailable(title: String, message: String)
}
