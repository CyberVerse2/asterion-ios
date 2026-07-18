import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @SceneStorage("selectedMode") private var selectedModeRaw = AppMode.novels.rawValue
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
    @State private var showsDownloads = false

    private var mode: Binding<AppMode> {
        Binding(
            get: { AppMode(rawValue: selectedModeRaw) ?? .novels },
            set: { newValue in
                selectedModeRaw = newValue.rawValue
                searchText = ""
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
                searchText = ""
                if newValue.showsNovelCatalog {
                    selectFirstNovel(in: newValue)
                }
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

    private var activeDownloadCount: Int {
        model.offlineDownloads.count(where: \.isDownloading)
    }

    var body: some View {
        navigationContent
        .onAppear {
            if mode.wrappedValue == .novels,
               section.wrappedValue.showsNovelCatalog,
               selectedNovelID.isEmpty {
                selectFirstNovel(in: section.wrappedValue)
            } else if mode.wrappedValue == .novels, section.wrappedValue.showsNovelCatalog {
                ensureSelection()
            }
        }
        .onChange(of: model.novels) {
            if mode.wrappedValue == .novels, section.wrappedValue.showsNovelCatalog {
                ensureSelection()
            }
        }
        .onChange(of: model.libraryNovelIDs) {
            guard section.wrappedValue == .library else { return }
            ensureSelection()
        }
        .onChange(of: selectedSectionRaw) {
            if mode.wrappedValue == .novels, section.wrappedValue.showsNovelCatalog {
                selectFirstNovel(in: section.wrappedValue)
            }
        }
        .onChange(of: selectedModeRaw) {
            if mode.wrappedValue == .novels, section.wrappedValue.showsNovelCatalog {
                ensureSelection()
            }
        }
        .onChange(of: searchText) {
            if mode.wrappedValue == .novels, section.wrappedValue.showsNovelCatalog {
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
                footballSelection: footballSection
            )
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } content: {
            catalogColumn
                .navigationSplitViewColumnWidth(min: 480, ideal: 620, max: 900)
        } detail: {
            detailColumn
                .navigationSplitViewColumnWidth(min: 520, ideal: 660, max: 900)
        }
        .navigationSplitViewStyle(.balanced)
        .catalogSearch(
            text: $searchText,
            prompt: searchPrompt,
            isEnabled: mode.wrappedValue != .novels || section.wrappedValue != .account
        )
        .toolbar {
            navigationToolbar
        }
        .focusedSceneValue(\.asterionSection, section)
        .focusedSceneValue(\.asterionMode, mode)
        .focusedSceneValue(\.asterionAnimeSection, animeSection)
        .focusedSceneValue(\.asterionMovieSection, movieSection)
        .focusedSceneValue(\.asterionFootballSection, footballSection)
        .tint(.asterionAccent)
        .frame(minWidth: 1_040, minHeight: 640)
    }

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Content", selection: mode) {
                ForEach(AppMode.allCases, id: \.self) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 360)
            .help("Switch between novels, anime, movies, and football")
        }

        if mode.wrappedValue != .novels || section.wrappedValue != .account {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await refreshActiveCatalog() }
                } label: {
                    Label(refreshTitle, systemImage: "arrow.clockwise")
                }
                .help(refreshTitle)
            }
        }

        if mode.wrappedValue == .novels, section.wrappedValue.showsNovelCatalog {
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
        if mode.wrappedValue == .anime {
            AnimeCatalogView(
                store: animeStore,
                section: animeSection.wrappedValue,
                query: searchText
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
        } else if section.wrappedValue == .account {
            AccountSummaryView()
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
        if mode.wrappedValue == .anime {
            AnimeDetailView(store: animeStore)
        } else if mode.wrappedValue == .movies {
            MovieDetailView(store: movieStore)
        } else if mode.wrappedValue == .football {
            FootballDetailView(store: footballStore)
        } else if section.wrappedValue == .account {
            AccountView()
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
        case .anime: "Search anime"
        case .movies: "Search movies and TV shows"
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
        guard section.showsNovelCatalog else { return }
        if section == .discover, searchText.isEmpty {
            selectedNovelID = model.featuredNovels.first?.id ?? ""
        } else {
            selectedNovelID = model.novels(for: section, search: searchText).first?.id ?? ""
        }
    }

    private func ensureSelection() {
        guard section.wrappedValue.showsNovelCatalog else { return }
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
        switch mode.wrappedValue {
        case .novels:
            await model.loadCatalog()
        case .anime:
            await animeStore.refresh(
                section: animeSection.wrappedValue,
                query: searchText
            )
        case .movies:
            await movieStore.refresh(
                section: movieSection.wrappedValue,
                query: searchText
            )
        case .football:
            await footballStore.refresh(section: footballSection.wrappedValue)
        }
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
