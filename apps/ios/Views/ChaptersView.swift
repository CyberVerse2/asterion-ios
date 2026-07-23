import Inject
import SwiftUI

struct ChaptersView: View {
    @ObserveInjection var inject
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var tabBarState: TabBarState
    @Environment(\.dismiss) private var dismiss
    let novel: Novel
    let allChapters: [Chapter]
    let totalCount: Int

    @State private var chapters: [Chapter] = []
    @State private var loading = false
    @State private var error: String?
    @State private var page = 0
    @State private var search = ""
    @State private var debouncedSearch = ""
    @State private var resolvedTotalCount: Int
    @State private var searchResultCount: Int?
    @State private var exportingChapterId: String?
    @State private var downloadedChapterIds = Set<String>()
    @State private var showDownloadAlert = false
    @State private var downloadAlertMessage = ""

    private let perPage = 30
    private var activeResultCount: Int { max(0, searchResultCount ?? resolvedTotalCount) }
    private var totalPages: Int { max(1, Int(ceil(Double(activeResultCount) / Double(perPage)))) }
    private var genreColor: Color { GenreStyle.color(for: novel.genres) }
    private var isDesktop: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }
    private var contentMaxWidth: CGFloat { isDesktop ? 920 : .infinity }
    private var pageHorizontalPadding: CGFloat { isDesktop ? 32 : 24 }
    private var topButtonPadding: CGFloat { isDesktop ? 18 : 44 }

    init(novel: Novel, allChapters: [Chapter], totalCount: Int) {
        self.novel = novel
        self.allChapters = allChapters
        self.totalCount = totalCount
        _resolvedTotalCount = State(initialValue: totalCount)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                chaptersHeader
                searchSection
                paginationHeader
                chapterList
                paginationFooter
            }
            .padding(.bottom, 100)
            .frame(maxWidth: contentMaxWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Text("← Back")
                    .font(.asterionMono(13))
                    .foregroundStyle(Color.asterionMuted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.asterionCard.opacity(0.5))
                            .stroke(Color.asterionBorder, lineWidth: 1)
                    )
            }
            .padding(.top, topButtonPadding)
            .padding(.leading, 20)
        }
        .background(Color.asterionBackground.ignoresSafeArea())
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .task { await loadChapters(pg: 0) }
        .onAppear { tabBarState.isVisible = false }
        .onDisappear { tabBarState.isVisible = true }
        .debounceSearch(text: $search, debouncedText: $debouncedSearch)
        .onChange(of: debouncedSearch) { _, _ in
            page = 0
            Task { await loadChapters(pg: 0, searchTerm: debouncedSearch) }
        }
        .onChange(of: page) { _, newPage in
            Task { await loadChapters(pg: newPage, searchTerm: debouncedSearch) }
        }
        .alert("Chapter Download", isPresented: $showDownloadAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloadAlertMessage)
        }
        .edgeSwipeToDismiss { dismiss() }
        .enableInjection()
    }

    private var chaptersHeader: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [genreColor.opacity(0.05), Color.asterionBackground],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(novel.title)
                    .font(.asterionSerif(22))
                    .foregroundStyle(Color.asterionText)

                Text(resolvedTotalCount > 0 ? "\(resolvedTotalCount) chapters" : "Chapters")
                    .font(.asterionMono(11))
                    .foregroundStyle(Color.asterionDim)
            }
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, isDesktop ? 72 : 88)
            .padding(.bottom, 20)
        }
    }

    private var searchSection: some View {
        SearchInputView(text: $search, placeholder: "Search chapters by title or number...")
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 16)
    }

    @ViewBuilder
    private var paginationHeader: some View {
        if totalPages > 1 {
            HStack {
                Text("Page \(page + 1) of \(totalPages)")
                    .font(.asterionMono(10))
                    .foregroundStyle(Color.asterionDim)

                Spacer()

                HStack(spacing: 8) {
                    Button { page = max(0, page - 1) } label: {
                        Text("◂")
                            .font(.system(size: 12))
                            .foregroundStyle(page == 0 ? Color.asterionCard : Color.asterionMuted)
                            .frame(width: 32, height: 32)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.asterionBorder, lineWidth: 1))
                    }
                    .disabled(page == 0)

                    Button { page = min(totalPages - 1, page + 1) } label: {
                        Text("▸")
                            .font(.system(size: 12))
                            .foregroundStyle(page >= totalPages - 1 ? Color.asterionCard : Color.asterionMuted)
                            .frame(width: 32, height: 32)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.asterionBorder, lineWidth: 1))
                    }
                    .disabled(page >= totalPages - 1)
                }
            }
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var chapterList: some View {
        if loading {
            HStack {
                Spacer()
                ProgressView().tint(Color.goldAccent)
                Spacer()
            }
            .padding(.vertical, 40)
        } else if let error {
            VStack(spacing: 12) {
                Text(error)
                    .font(.asterionMono(13))
                    .foregroundStyle(Color.asterionMuted)
                Button("Try Again") {
                    Task { await loadChapters(pg: page, searchTerm: debouncedSearch) }
                }
                .font(.asterionMono(12))
                .foregroundStyle(Color.goldAccent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else if chapters.isEmpty {
            Text(debouncedSearch.isEmpty ? "No chapters found" : "No chapters match your search")
                .font(.asterionMono(13))
                .foregroundStyle(Color.asterionDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                    HStack(spacing: 8) {
                        NavigationLink {
                            ReaderView(
                                initialChapter: chapter,
                                novel: novel,
                                allChapters: navigationChapterContext(for: chapter),
                                shouldAutoResumeFromSavedProgress: false
                            )
                        } label: {
                            HStack(spacing: 10) {
                                Text("#\(chapter.chapterNumber)")
                                    .font(.asterionMono(10))
                                    .foregroundStyle(Color.asterionDim)
                                    .frame(width: 40, alignment: .leading)

                                Text(chapter.title)
                                    .font(.asterionSerif(15))
                                    .foregroundStyle(Color.asterionReaderText)
                                    .lineLimit(1)

                                Spacer()

                                Text("›")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.asterionBorder)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await downloadChapter(chapter) }
                        } label: {
                            ZStack {
                                if exportingChapterId == chapter.id {
                                    ProgressView()
                                        .tint(Color.goldAccent)
                                        .scaleEffect(0.8)
                                } else if downloadedChapterIds.contains(chapter.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color(red: 0.353, green: 0.608, blue: 0.478))
                                } else {
                                    Image(systemName: "arrow.down.doc")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.asterionMuted)
                                }
                            }
                            .frame(width: 28, height: 28)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.asterionBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(exportingChapterId != nil)
                        .padding(.trailing, 12)
                    }

                    if index < chapters.count - 1 {
                        Divider().overlay(Color.asterionCard)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.asterionBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, pageHorizontalPadding)
        }
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if totalPages > 1 && !loading && !chapters.isEmpty {
            HStack(spacing: 8) {
                Button {
                    page = max(0, page - 1)
                } label: {
                    Text("← Previous")
                        .font(.asterionMono(12))
                        .foregroundStyle(page == 0 ? Color.asterionBorder : Color.asterionMuted)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.asterionBorder, lineWidth: 1))
                }
                .disabled(page == 0)

                Button {
                    page = min(totalPages - 1, page + 1)
                } label: {
                    Text("Next →")
                        .font(.asterionMono(12))
                        .foregroundStyle(page >= totalPages - 1 ? Color.asterionBorder : Color.goldAccent)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(page >= totalPages - 1 ? .clear : genreColor.opacity(0.06))
                                .stroke(page >= totalPages - 1 ? Color.asterionBorder : genreColor.opacity(0.3), lineWidth: 1)
                        )
                }
                .disabled(page >= totalPages - 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    private func loadChapters(pg: Int, searchTerm: String = "") async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            if !searchTerm.isEmpty {
                let allChapters = try await fetchAllChaptersForSearch()
                let q = searchTerm.lowercased()
                let filtered = allChapters.filter {
                    $0.title.lowercased().contains(q) || String($0.chapterNumber).contains(q)
                }
                searchResultCount = filtered.count
                let start = min(pg * perPage, filtered.count)
                let end = min(start + perPage, filtered.count)
                chapters = Array(filtered[start..<end])
                await refreshDownloadedChapterState()
                return
            }

            let response = try await apiClient.fetchChapters(
                novelId: novel.id,
                limit: perPage,
                offset: pg * perPage
            )
            await OfflineChapterStore.shared.saveChapterList(novelId: novel.id, chapters: response.data, mergeWithExisting: true)
            resolvedTotalCount = response.meta?.total
                ?? (resolvedTotalCount > 0 ? resolvedTotalCount : max(totalCount, response.data.count))
            searchResultCount = nil
            if searchTerm.isEmpty {
                chapters = response.data
            } else {
                let q = searchTerm.lowercased()
                chapters = response.data.filter {
                    $0.title.lowercased().contains(q) || String($0.chapterNumber).contains(q)
                }
            }
            await refreshDownloadedChapterState()
        } catch {
            let cachedAll = await OfflineChapterStore.shared.loadChapterList(novelId: novel.id)
            if !cachedAll.isEmpty {
                if searchTerm.isEmpty {
                    resolvedTotalCount = cachedAll.count
                    searchResultCount = nil
                }
                let filtered: [Chapter]
                if searchTerm.isEmpty {
                    filtered = cachedAll
                } else {
                    let q = searchTerm.lowercased()
                    filtered = cachedAll.filter {
                        $0.title.lowercased().contains(q) || String($0.chapterNumber).contains(q)
                    }
                    searchResultCount = filtered.count
                }
                let start = min(pg * perPage, filtered.count)
                let end = min(start + perPage, filtered.count)
                chapters = Array(filtered[start..<end])
                self.error = nil
                await refreshDownloadedChapterState()
            } else {
                self.error = error.localizedDescription
            }
        }
    }

    private func fetchAllChaptersForSearch() async throws -> [Chapter] {
        let cached = await OfflineChapterStore.shared.loadChapterList(novelId: novel.id)
        let expectedTotal = max(resolvedTotalCount, totalCount)
        if !cached.isEmpty, expectedTotal > 0, cached.count >= expectedTotal {
            return cached
        }

        let fetched = try await apiClient.fetchAllChapters(novelId: novel.id)
        if !fetched.isEmpty {
            await OfflineChapterStore.shared.saveChapterList(
                novelId: novel.id,
                chapters: fetched,
                mergeWithExisting: true
            )
            resolvedTotalCount = max(
                resolvedTotalCount,
                totalCount,
                fetched.count
            )
            return fetched
        }

        return cached
    }

    private func navigationChapterContext(for chapter: Chapter) -> [Chapter] {
        var merged: [Chapter] = []
        var seen = Set<String>()

        for item in ([chapter] + allChapters + chapters) where !seen.contains(item.id) {
            merged.append(item)
            seen.insert(item.id)
        }

        return merged.sorted { lhs, rhs in
            if lhs.chapterNumber == rhs.chapterNumber {
                return lhs.id < rhs.id
            }
            return lhs.chapterNumber < rhs.chapterNumber
        }
    }

    private func downloadChapter(_ chapter: Chapter) async {
        exportingChapterId = chapter.id
        defer { exportingChapterId = nil }

        let fullChapter: Chapter
        do {
            fullChapter = try await apiClient.fetchChapter(id: chapter.id)
        } catch {
            fullChapter = chapter
        }
        await OfflineChapterStore.shared.cacheChapter(fullChapter)

        let header: String
        if fullChapter.chapterNumber > 0 {
            header = "Chapter \(fullChapter.chapterNumber): \(fullChapter.title)"
        } else {
            header = fullChapter.title
        }
        let content = """
        \(novel.title)
        \(header)

        \(fullChapter.plainContent)
        """
        do {
            let fileURL = try await OfflineChapterStore.shared.saveDownloadedChapter(
                novelTitle: novel.title,
                chapterNumber: fullChapter.chapterNumber,
                chapterTitle: fullChapter.title,
                content: content
            )
            downloadedChapterIds.insert(chapter.id)
            downloadAlertMessage = "Saved to \(fileURL.deletingLastPathComponent().lastPathComponent)"
            showDownloadAlert = true
        } catch {
            downloadAlertMessage = "Couldn't save chapter to local folder."
            showDownloadAlert = true
        }
    }

    private func refreshDownloadedChapterState() async {
        var downloaded = Set<String>()
        for chapter in chapters {
            let exists = await OfflineChapterStore.shared.isChapterDownloaded(
                novelTitle: novel.title,
                chapterNumber: chapter.chapterNumber,
                chapterTitle: chapter.title
            )
            if exists {
                downloaded.insert(chapter.id)
            }
        }
        downloadedChapterIds = downloaded
    }
}
