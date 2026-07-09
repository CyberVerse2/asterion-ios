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
        ZStack {
            Color.asterionCanvas.ignoresSafeArea()
            floatingWorkspace
                .padding(12)
                .ignoresSafeArea(.container, edges: .top)
        }
        .toolbar(removing: .sidebarToggle)
        .focusedSceneValue(\.asterionSection, section)
        .tint(.asterionAccent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var floatingWorkspace: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            FloatingPane(insets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 6)) {
                SidebarView(selection: section, isCompact: $isSidebarCompact)
            }
            .navigationSplitViewColumnWidth(
                min: isSidebarCompact ? 64 : 190,
                ideal: isSidebarCompact ? 64 : 220,
                max: isSidebarCompact ? 64 : 240
            )
        } content: {
            FloatingPane(insets: EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6)) {
                VStack(spacing: 0) {
                    middleHeader

                    Divider()
                        .overlay(Color.asterionBorder.opacity(0.7))

                    if section.wrappedValue == .account {
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
            }
            .navigationSplitViewColumnWidth(min: 520, ideal: 680, max: 1_200)
        } detail: {
            FloatingPane(insets: EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 0)) {
                if section.wrappedValue == .account {
                    AccountView()
                } else if let selectedNovel {
                    NovelDetailView(novel: selectedNovel)
                        .id(selectedNovel.id)
                } else {
                    detailPlaceholder
                }
            }
            .navigationSplitViewColumnWidth(min: 400, ideal: 500, max: 800)
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color.asterionCanvas)
    }

    private var middleHeader: some View {
        HStack(spacing: 12) {
            Text(section.wrappedValue.title)
                .font(.asterionDisplay(16, weight: .semibold))
                .foregroundStyle(Color.asterionText)

            if section.wrappedValue != .account {
                Button {
                    Task { await model.loadCatalog() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.asterionMuted)
                        .frame(width: 30, height: 30)
                        .background(
                            Color.asterionBackground,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                }
                .buttonStyle(AsterionPressButtonStyle())
                .help("Refresh Catalog")
            }

            Spacer(minLength: 20)

            if section.wrappedValue != .account {
                searchField
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(Color.asterionBackground)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.asterionMuted)

            TextField("Search titles, authors, or genres", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.asterionText)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.asterionMuted)
                }
                .buttonStyle(.plain)
                .help("Clear Search")
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 320, height: 34)
        .background(
            Color.asterionBackground,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.asterionBorder.opacity(0.8))
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

private struct FloatingPane<Content: View>: View {
    let insets: EdgeInsets
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.18))
            }
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .padding(insets)
            .background(Color.asterionCanvas)
    }
}
