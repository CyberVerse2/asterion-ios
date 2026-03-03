import Inject
import SwiftUI

struct LibraryView: View {
    @ObserveInjection var inject
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var authService: AuthService
    @State private var items: [LibraryItem] = []
    @State private var loading = false
    @State private var failed = false
    @State private var search = ""
    @State private var debouncedSearch = ""
    @State private var sortOption: SortOption = .lastRead

    enum SortOption: String, CaseIterable {
        case lastRead = "Last Read"
        case lastAdded = "Last Added"
        case lastUpdated = "Last Updated"
    }

    struct LibraryItem: Identifiable {
        let novel: Novel
        let addedAt: Date?
        let updatedAt: Date?
        let lastReadAt: Date?
        var id: String { novel.id }
    }

    private var filteredItems: [LibraryItem] {
        var result = items
        if !debouncedSearch.isEmpty {
            let q = debouncedSearch.lowercased()
            result = result.filter {
                $0.novel.title.lowercased().contains(q) || ($0.novel.author?.lowercased().contains(q) ?? false)
            }
        }
        switch sortOption {
        case .lastRead:
            result.sort { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
        case .lastAdded:
            result.sort { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        case .lastUpdated:
            result.sort { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SearchInputView(text: $search, placeholder: "Search by title or author...")
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)

                    if authService.isSignedIn && !items.isEmpty {
                        sortPicker
                    }

                    if loading && items.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView().tint(Color.goldAccent).scaleEffect(1.2)
                            Spacer()
                        }
                        .padding(40)
                    } else if failed && items.isEmpty {
                        VStack(spacing: 12) {
                            Text("⚠").font(.system(size: 32)).opacity(0.4)
                            Text("Couldn't load library")
                                .font(.asterionMono(13))
                                .foregroundStyle(Color.asterionMuted)
                            Button {
                                Task { await loadLibrary() }
                            } label: {
                                Text("Try Again")
                                    .font(.asterionMono(13))
                                    .foregroundStyle(Color.goldAccent)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if !authService.isSignedIn {
                        VStack(spacing: 12) {
                            Text("🔐").font(.system(size: 36)).opacity(0.35)
                            Text("Sign in to view your library")
                                .font(.asterionMono(13))
                                .foregroundStyle(Color.asterionDim)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if filteredItems.isEmpty {
                        VStack(spacing: 12) {
                            Text("📚").font(.system(size: 36)).opacity(0.3)
                            Text(debouncedSearch.isEmpty ? "Library is empty" : "No results")
                                .font(.asterionMono(13))
                                .foregroundStyle(Color.asterionDim)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredItems) { item in
                                NavigationLink(value: item.novel) {
                                    LibraryRow(novel: item.novel)
                                }
                                .buttonStyle(.plain)

                                Divider().overlay(Color.asterionCard)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable { await loadLibrary() }
            .background(Color.asterionBackground.ignoresSafeArea())
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: Novel.self) { novel in
                NovelDetailView(novel: novel)
            }
            .task { await loadLibrary() }
            .debounceSearch(text: $search, debouncedText: $debouncedSearch)
        }
        .enableInjection()
    }

    private var sortPicker: some View {
        HStack(spacing: 6) {
            ForEach(SortOption.allCases, id: \.self) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { sortOption = option }
                } label: {
                    Text(option.rawValue)
                        .font(.asterionMono(10))
                        .foregroundStyle(sortOption == option ? Color.goldAccent : Color.asterionDim)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(sortOption == option ? Color.goldAccent.opacity(0.1) : .clear)
                                .stroke(sortOption == option ? Color.goldAccent.opacity(0.4) : Color.asterionBorder, lineWidth: 1)
                        )
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private func loadLibrary() async {
        loading = true
        defer { loading = false }
        guard authService.isSignedIn else {
            items = []
            failed = false
            return
        }
        do {
            async let libraryFetch = apiClient.fetchMyLibrary()
            async let progressFetch = apiClient.fetchAllReadingProgress()
            async let novelsFetch = apiClient.fetchNovels(limit: 500, search: "")

            let libraryItems = try await libraryFetch
            let progressList = try await progressFetch
            let allNovels = try await novelsFetch

            if libraryItems.isEmpty {
                items = []
                failed = false
                return
            }

            let progressByNovelId = Dictionary(uniqueKeysWithValues: progressList.map { ($0.novelId, $0) })
            let novelById = Dictionary(uniqueKeysWithValues: allNovels.map { ($0.id, $0) })

            items = libraryItems.compactMap { libEntry in
                guard let novel = novelById[libEntry.novelId] else { return nil }
                return LibraryItem(
                    novel: novel,
                    addedAt: libEntry.createdAt,
                    updatedAt: libEntry.updatedAt,
                    lastReadAt: progressByNovelId[libEntry.novelId]?.updatedAt
                )
            }
            await OfflineChapterStore.shared.saveLibrarySnapshot(
                items.map {
                    OfflineLibraryItemSnapshot(
                        novel: $0.novel,
                        addedAt: $0.addedAt,
                        updatedAt: $0.updatedAt,
                        lastReadAt: $0.lastReadAt
                    )
                }
            )
            failed = false
        } catch {
            let cached = await OfflineChapterStore.shared.loadLibrarySnapshot()
            if !cached.isEmpty {
                items = cached.map {
                    LibraryItem(
                        novel: $0.novel,
                        addedAt: $0.addedAt,
                        updatedAt: $0.updatedAt,
                        lastReadAt: $0.lastReadAt
                    )
                }
                failed = false
            } else if items.isEmpty {
                failed = true
            }
        }
    }
}

// MARK: - Library Row

private struct LibraryRow: View {
    let novel: Novel

    var body: some View {
        HStack(spacing: 16) {
            CoverImageView(novel: novel, size: .sm)

            VStack(alignment: .leading, spacing: 3) {
                Text(novel.title)
                    .font(.asterionSerif(16, weight: .medium))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(1)

                HStack(spacing: 0) {
                    Text(novel.author ?? "Unknown")
                        .font(.asterionMono(11))
                        .foregroundStyle(Color.asterionMuted)
                    if let genre = novel.genres?.first {
                        Text(" · \(genre)")
                            .font(.asterionMono(11))
                            .foregroundStyle(Color.asterionMuted)
                    }
                }

                HStack(spacing: 8) {
                    if let rating = novel.rating {
                        Text("★ \(String(format: "%.1f", rating))")
                            .font(.asterionMono(10))
                            .foregroundStyle(Color.goldAccent)
                    }
                    if let chapters = novel.totalChapters {
                        Text("\(chapters) ch.")
                            .font(.asterionMono(9))
                            .foregroundStyle(Color.asterionBorderHover)
                    }
                    if let status = novel.status {
                        Text(status)
                            .font(.asterionMono(9))
                            .foregroundStyle(Color.asterionDim)
                    }
                }
                .padding(.top, 3)
            }

            Spacer(minLength: 0)

            Text("›")
                .font(.system(size: 16))
                .foregroundStyle(Color.asterionBorder)
        }
        .padding(.vertical, 16)
    }
}
