import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @SceneStorage("selectedSection") private var selectedSectionRaw = AppSection.discover.rawValue
    @SceneStorage("selectedNovelID") private var selectedNovelID = ""
    @State private var searchText = ""
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var isSidebarCompact = false

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

    private var selectedNovel: Novel? {
        model.novel(id: selectedNovelID)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: section, isCompact: $isSidebarCompact)
                .navigationSplitViewColumnWidth(
                    min: isSidebarCompact ? 64 : 190,
                    ideal: isSidebarCompact ? 64 : 220,
                    max: isSidebarCompact ? 64 : 240
                )
        } content: {
            if section.wrappedValue == .account {
                AccountSummaryView()
                    .navigationSplitViewColumnWidth(min: 520, ideal: 650, max: 760)
            } else {
                EditorialCatalogView(
                    section: section.wrappedValue,
                    novels: model.novels(for: section.wrappedValue, search: searchText),
                    isSearching: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    selectedNovelID: $selectedNovelID
                )
                .id(section.wrappedValue)
                .navigationSplitViewColumnWidth(min: 520, ideal: 650, max: 760)
            }
        } detail: {
            if section.wrappedValue == .account {
                AccountView()
                    .navigationSplitViewColumnWidth(min: 400, ideal: 480, max: 520)
            } else if let selectedNovel {
                NovelDetailView(novel: selectedNovel)
                    .id(selectedNovel.id)
                    .navigationSplitViewColumnWidth(min: 400, ideal: 480, max: 520)
            } else {
                detailPlaceholder
                    .navigationSplitViewColumnWidth(min: 400, ideal: 480, max: 520)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .catalogSearch(
            text: $searchText,
            isEnabled: section.wrappedValue != .account
        )
        .toolbar(removing: .sidebarToggle)
        .focusedSceneValue(\.asterionSection, section)
        .tint(.asterionAccent)
        .background(Color.asterionBackground)
        .preferredColorScheme(.light)
        .onAppear {
            restoreAllColumns()
            if selectedNovelID.isEmpty {
                selectFirstNovel(in: section.wrappedValue)
            } else {
                ensureSelection()
            }
        }
        .onChange(of: model.novels) {
            ensureSelection()
        }
        .onChange(of: model.libraryNovelIDs) {
            guard section.wrappedValue == .library else { return }
            ensureSelection()
        }
        .onChange(of: selectedSectionRaw) {
            selectFirstNovel(in: section.wrappedValue)
        }
        .onChange(of: searchText) {
            ensureSelection()
        }
        .onChange(of: columnVisibility) {
            restoreAllColumns()
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
        .background(Color.asterionSurface)
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

    private func restoreAllColumns() {
        guard columnVisibility != .all else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            columnVisibility = .all
        }
    }
}

private extension View {
    @ViewBuilder
    func catalogSearch(text: Binding<String>, isEnabled: Bool) -> some View {
        if isEnabled {
            searchable(text: text, prompt: "Search titles, authors, or genres")
        } else {
            self
        }
    }
}
