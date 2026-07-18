import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @SceneStorage("selectedMode") private var selectedModeRaw = AppMode.novels.rawValue
    @SceneStorage("selectedSection") private var selectedSectionRaw = AppSection.discover.rawValue
    @SceneStorage("selectedAnimeSection") private var selectedAnimeSectionRaw = AnimeSection.discover.rawValue
    @SceneStorage("selectedNovelID") private var selectedNovelID = ""
    @StateObject private var animeStore = AnimeStore()
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

    private var selectedNovel: Novel? {
        model.novel(id: selectedNovelID)
    }

    private var activeDownloadCount: Int {
        model.offlineDownloads.count(where: \.isDownloading)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                mode: mode.wrappedValue,
                novelSelection: section,
                animeSelection: animeSection
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
            prompt: mode.wrappedValue == .anime
                ? "Search anime"
                : "Search titles, authors, or genres",
            isEnabled: mode.wrappedValue == .anime || section.wrappedValue != .account
        )
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Content", selection: mode) {
                    ForEach(AppMode.allCases, id: \.self) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .help("Switch between novels and anime")
            }

            if mode.wrappedValue == .anime || section.wrappedValue != .account {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            if mode.wrappedValue == .anime {
                                await animeStore.refresh(
                                    section: animeSection.wrappedValue,
                                    query: searchText
                                )
                            } else {
                                await model.loadCatalog()
                            }
                        }
                    } label: {
                        Label(
                            mode.wrappedValue == .anime ? "Refresh Anime" : "Refresh Catalog",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .help(mode.wrappedValue == .anime ? "Refresh Anime" : "Refresh Catalog")
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
        .focusedSceneValue(\.asterionSection, section)
        .focusedSceneValue(\.asterionMode, mode)
        .focusedSceneValue(\.asterionAnimeSection, animeSection)
        .tint(.asterionAccent)
        .frame(minWidth: 1_040, minHeight: 640)
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

    @ViewBuilder
    private var catalogColumn: some View {
        if mode.wrappedValue == .anime {
            AnimeCatalogView(
                store: animeStore,
                section: animeSection.wrappedValue,
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
        } else if section.wrappedValue == .account {
            AccountView()
        } else if let selectedNovel {
            NovelDetailView(novel: selectedNovel)
                .id(selectedNovel.id)
        } else {
            detailPlaceholder
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
