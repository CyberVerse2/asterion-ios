import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @SceneStorage("selectedSection") private var selectedSectionRaw = AppSection.discover.rawValue
    @SceneStorage("selectedNovelID") private var selectedNovelID = ""
    @State private var searchText = ""

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
        NavigationSplitView {
            SidebarView(selection: section)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } content: {
            if section.wrappedValue == .account {
                AccountSummaryView()
                    .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 340)
            } else {
                NovelListView(
                    section: section.wrappedValue,
                    novels: model.novels(for: section.wrappedValue, search: searchText),
                    selectedNovelID: $selectedNovelID
                )
                .navigationSplitViewColumnWidth(min: 290, ideal: 340, max: 420)
                .searchable(text: $searchText, prompt: "Title, author, or genre")
            }
        } detail: {
            if section.wrappedValue == .account {
                AccountView()
            } else if let selectedNovel {
                NovelDetailView(novel: selectedNovel)
                    .id(selectedNovel.id)
            } else {
                detailPlaceholder
            }
        }
        .focusedSceneValue(\.asterionSection, section)
        .tint(.asterionGold)
        .background(Color.asterionBackground)
        .onAppear {
            if selectedNovelID.isEmpty {
                selectFirstNovel(in: section.wrappedValue)
            }
        }
        .onChange(of: model.novels) {
            ensureSelection()
        }
        .onChange(of: model.libraryNovelIDs) {
            guard section.wrappedValue == .library else { return }
            ensureSelection()
        }
        .onChange(of: searchText) {
            ensureSelection()
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
        .background(Color.asterionBackground)
    }

    private func selectFirstNovel(in section: AppSection) {
        selectedNovelID = model.novels(for: section, search: searchText).first?.id ?? ""
    }

    private func ensureSelection() {
        let visible = model.novels(for: section.wrappedValue, search: searchText)
        if !visible.contains(where: { $0.id == selectedNovelID }) {
            selectedNovelID = visible.first?.id ?? ""
        }
    }
}
