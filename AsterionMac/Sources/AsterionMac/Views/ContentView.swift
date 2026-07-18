import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @SceneStorage("selectedMode") private var selectedModeRaw = AppMode.novels.rawValue
    @SceneStorage("selectedSection") private var selectedSectionRaw = AppSection.discover.rawValue
    @SceneStorage("selectedAnimeSection") private var selectedAnimeSectionRaw = AnimeSection.discover.rawValue
    @SceneStorage("selectedMovieSection") private var selectedMovieSectionRaw = MovieSection.discover.rawValue
    @SceneStorage("selectedFootballSection") private var selectedFootballSectionRaw = FootballSection.live.rawValue
    @SceneStorage("selectedNovelID") private var selectedNovelID = ""
    @SceneStorage("showsAccount") private var showsAccount = false
    @StateObject private var animeStore = AnimeStore()
    @StateObject private var movieStore = MovieStore()
    @StateObject private var footballStore = FootballStore()
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var searchText = ""
    @State private var showsDownloads = false
    @State private var selectedAnimeBookmarkID: String?
    @State private var selectedMovieBookmarkID: String?

    private var mode: Binding<AppMode> {
        Binding(
            get: { AppMode(rawValue: selectedModeRaw) ?? .novels },
            set: { newValue in
                selectedModeRaw = newValue.rawValue
                showsAccount = false
                searchText = ""
                if newValue == .anime, animeSection.wrappedValue == .bookmarks {
                    selectedAnimeBookmarkID = nil
                } else if newValue == .movies, movieSection.wrappedValue == .bookmarks {
                    selectedMovieBookmarkID = nil
                }
                if newValue == .novels {
                    ensureSelection()
                }
            }
        )
    }

    private var section: Binding<AppSection> {
        Binding(
            get: { AppSection(rawValue: selectedSectionRaw) ?? .discover },
            set: { newValue in
                selectedSectionRaw = newValue.rawValue
                showsAccount = false
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
                showsAccount = false
                searchText = ""
                if newValue == .bookmarks {
                    selectedAnimeBookmarkID = nil
                }
            }
        )
    }

    private var movieSection: Binding<MovieSection> {
        Binding(
            get: { MovieSection(rawValue: selectedMovieSectionRaw) ?? .discover },
            set: { newValue in
                selectedMovieSectionRaw = newValue.rawValue
                showsAccount = false
                searchText = ""
                if newValue == .bookmarks {
                    selectedMovieBookmarkID = nil
                }
            }
        )
    }

    private var footballSection: Binding<FootballSection> {
        Binding(
            get: { FootballSection(rawValue: selectedFootballSectionRaw) ?? .live },
            set: { newValue in
                selectedFootballSectionRaw = newValue.rawValue
                showsAccount = false
                searchText = ""
            }
        )
    }

    private var selectedNovel: Novel? {
        model.novel(id: selectedNovelID)
    }

    private var activeDownloadCount: Int {
        model.offlineDownloads.count(where: \.isDownloading)
    }

    var body: some View {
        navigationContent
        .onAppear {
            if mode.wrappedValue == .novels, selectedNovelID.isEmpty {
                selectFirstNovel(in: section.wrappedValue)
            } else if mode.wrappedValue == .novels {
                ensureSelection()
            }
        }
        .onChange(of: model.novels) {
            if mode.wrappedValue == .novels {
                ensureSelection()
            }
        }
        .onChange(of: model.libraryNovelIDs) {
            guard section.wrappedValue == .library else { return }
            ensureSelection()
        }
        .onChange(of: selectedSectionRaw) {
            if mode.wrappedValue == .novels {
                selectFirstNovel(in: section.wrappedValue)
            }
        }
        .onChange(of: selectedModeRaw) {
            if mode.wrappedValue == .novels {
                ensureSelection()
            }
        }
        .onChange(of: searchText) {
            if mode.wrappedValue == .novels, !showsAccount {
                ensureSelection()
            }
        }
    }

    private var navigationContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                mode: mode.wrappedValue,
                novelSelection: section,
                animeSelection: animeSection,
                movieSelection: movieSection,
                footballSelection: footballSection,
                showsAccount: $showsAccount
            )
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } content: {
            catalogColumn
                .navigationSplitViewColumnWidth(min: 420, ideal: 560, max: 900)
        } detail: {
            detailColumn
                .navigationSplitViewColumnWidth(min: 420, ideal: 620, max: 900)
        }
        .navigationSplitViewStyle(.balanced)
        .catalogSearch(
            text: $searchText,
            prompt: searchPrompt,
            isEnabled: !showsAccount
        )
        .toolbar {
            navigationToolbar
        }
        .focusedSceneValue(\.asterionSection, section)
        .focusedSceneValue(\.asterionMode, mode)
        .focusedSceneValue(\.asterionAnimeSection, animeSection)
        .focusedSceneValue(\.asterionMovieSection, movieSection)
        .focusedSceneValue(\.asterionFootballSection, footballSection)
        .focusedSceneValue(\.asterionShowsAccount, $showsAccount)
        .tint(.asterionAccent)
        .frame(minWidth: 1_040, minHeight: 640)
    }

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            ContentModePicker(selection: mode)
                .frame(width: 360)
                .help("Switch between novels, anime, movies, and football")
        }
        .sharedBackgroundVisibility(.hidden)

        if showsRefreshAction {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await refreshActiveCatalog() }
                } label: {
                    Label(refreshTitle, systemImage: "arrow.clockwise")
                }
                .help(refreshTitle)
            }
        }

        if mode.wrappedValue == .novels, !showsAccount {
            ToolbarSpacer(.fixed)

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsDownloads.toggle()
                } label: {
                    Label("Downloads", systemImage: activeDownloadCount > 0 ? "arrow.down.circle.fill" : "arrow.down.circle")
                }
                .badge(activeDownloadCount)
                .help("Downloads")
                .popover(isPresented: $showsDownloads, arrowEdge: .top) {
                    DownloadCenterView()
                        .environmentObject(model)
                }
            }
        }
    }

    @ViewBuilder
    private var catalogColumn: some View {
        if showsAccount {
            AccountSummaryView()
        } else if mode.wrappedValue == .anime, animeSection.wrappedValue == .bookmarks {
            SavedMediaCatalogView(
                mediaType: .anime,
                bookmarks: bookmarks(for: .anime),
                query: searchText,
                isSignedIn: model.isSignedIn,
                selectedContentID: selectedAnimeBookmarkID,
                select: selectAnimeBookmark
            )
        } else if mode.wrappedValue == .anime {
            AnimeCatalogView(
                store: animeStore,
                section: animeSection.wrappedValue,
                query: searchText
            )
        } else if mode.wrappedValue == .movies, movieSection.wrappedValue == .bookmarks {
            SavedMediaCatalogView(
                mediaType: .movie,
                bookmarks: bookmarks(for: .movie),
                query: searchText,
                isSignedIn: model.isSignedIn,
                selectedContentID: selectedMovieBookmarkID,
                select: selectMovieBookmark
            )
        } else if mode.wrappedValue == .movies {
            MovieCatalogView(
                store: movieStore,
                section: movieSection.wrappedValue,
                query: searchText
            )
        } else if mode.wrappedValue == .football {
            FootballCatalogView(
                store: footballStore,
                section: footballSection.wrappedValue,
                query: searchText
            )
        } else {
            EditorialCatalogView(
                section: section.wrappedValue,
                novels: model.novels(for: section.wrappedValue, search: searchText),
                isSearching: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                selectedNovelID: $selectedNovelID
            )
            .id(section.wrappedValue)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if showsAccount {
            AccountView()
        } else if mode.wrappedValue == .anime,
           animeSection.wrappedValue == .bookmarks,
           !hasSelectedBookmark(for: .anime, contentID: selectedAnimeBookmarkID) {
            savedMediaDetailPlaceholder(for: .anime)
        } else if mode.wrappedValue == .anime {
            AnimeDetailView(store: animeStore)
        } else if mode.wrappedValue == .movies,
                  movieSection.wrappedValue == .bookmarks,
                  !hasSelectedBookmark(for: .movie, contentID: selectedMovieBookmarkID) {
            savedMediaDetailPlaceholder(for: .movie)
        } else if mode.wrappedValue == .movies {
            MovieDetailView(store: movieStore)
        } else if mode.wrappedValue == .football {
            FootballDetailView(store: footballStore)
        } else if let selectedNovel {
            NovelDetailView(novel: selectedNovel)
                .id(selectedNovel.id)
        } else {
            detailPlaceholder
        }
    }

    private var searchPrompt: String {
        switch mode.wrappedValue {
        case .novels: "Search titles, authors, or genres"
        case .anime:
            animeSection.wrappedValue == .bookmarks ? "Search saved anime" : "Search anime"
        case .movies:
            movieSection.wrappedValue == .bookmarks
                ? "Search saved movies and TV shows"
                : "Search movies and TV shows"
        case .football: "Search teams or competitions"
        }
    }

    private var refreshTitle: String {
        switch mode.wrappedValue {
        case .novels: "Refresh Catalog"
        case .anime: "Refresh Anime"
        case .movies: "Refresh Movies"
        case .football: "Refresh Football"
        }
    }

    private var showsRefreshAction: Bool {
        guard !showsAccount else { return false }
        return switch mode.wrappedValue {
        case .novels:
            true
        case .anime:
            animeSection.wrappedValue != .bookmarks
        case .movies:
            movieSection.wrappedValue != .bookmarks
        case .football:
            true
        }
    }

    private var detailPlaceholder: some View {
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
            } else if section.wrappedValue == .library, !model.isSignedIn {
                ContentUnavailableView(
                    "Sign in to view your library",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Choose Account in the sidebar to sign in.")
                )
            } else {
                ContentUnavailableView(
                    "Select a novel",
                    systemImage: "book.closed",
                    description: Text("Choose a title from the middle column.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func selectFirstNovel(in section: AppSection) {
        if section == .discover, searchText.isEmpty {
            selectedNovelID = model.featuredNovels.first?.id ?? ""
        } else {
            selectedNovelID = model.novels(for: section, search: searchText).first?.id ?? ""
        }
    }

    private func ensureSelection() {
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

    private func refreshActiveCatalog() async {
        guard !showsAccount else { return }
        switch mode.wrappedValue {
        case .novels:
            await model.loadCatalog()
        case .anime:
            guard animeSection.wrappedValue != .bookmarks else { return }
            await animeStore.refresh(
                section: animeSection.wrappedValue,
                query: searchText
            )
        case .movies:
            guard movieSection.wrappedValue != .bookmarks else { return }
            await movieStore.refresh(
                section: movieSection.wrappedValue,
                query: searchText
            )
        case .football:
            await footballStore.refresh(section: footballSection.wrappedValue)
        }
    }

    private func bookmarks(for mediaType: MediaAccountType) -> [MediaBookmark] {
        model.mediaBookmarks
            .filter { $0.mediaType == mediaType }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func hasSelectedBookmark(
        for mediaType: MediaAccountType,
        contentID: String?
    ) -> Bool {
        guard let contentID else { return false }
        return model.mediaBookmarks.contains {
            $0.mediaType == mediaType && $0.contentId == contentID
        }
    }

    @MainActor
    private func selectAnimeBookmark(_ bookmark: MediaBookmark) async {
        selectedAnimeBookmarkID = bookmark.contentId
        await animeStore.select(
            AnimeTitle(
                slug: bookmark.contentId,
                title: bookmark.title,
                japaneseTitle: nil,
                imageURL: bookmark.imageURL,
                type: bookmark.subtitle,
                episodeLabel: nil
            )
        )
    }

    @MainActor
    private func selectMovieBookmark(_ bookmark: MediaBookmark) async {
        selectedMovieBookmarkID = bookmark.contentId
        await movieStore.select(
            MovieTitle(
                id: bookmark.contentId,
                slug: bookmark.contentId,
                title: bookmark.title,
                imageURL: bookmark.imageURL,
                imdbRating: nil,
                runtime: nil,
                year: nil,
                type: bookmark.subtitle == "TV Series" ? "tv" : "movie",
                quality: nil
            )
        )
    }

    private func savedMediaDetailPlaceholder(for mediaType: MediaAccountType) -> some View {
        ContentUnavailableView(
            model.isSignedIn ? "Select a bookmark" : "Sign in to view bookmarks",
            systemImage: model.isSignedIn ? "bookmark" : "person.crop.circle.badge.questionmark",
            description: Text(
                model.isSignedIn
                    ? "Choose a saved \(mediaType == .anime ? "anime" : "movie or TV show") from the middle column."
                    : "Your bookmarks follow your Asterion account."
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

private extension View {
    @ViewBuilder
    func catalogSearch(text: Binding<String>, prompt: String, isEnabled: Bool) -> some View {
        if isEnabled {
            searchable(text: text, prompt: prompt)
        } else {
            self
        }
    }
}
