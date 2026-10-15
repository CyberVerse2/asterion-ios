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
    private var isDesktop: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }
    private var contentMaxWidth: CGFloat { isDesktop ? 920 : .infinity }
    private var pageHorizontalPadding: CGFloat { isDesktop ? 32 : 24 }
    private var topBarTopPadding: CGFloat { isDesktop ? 18 : 44 }

    private var headerSubtitle: String {
        if let searchResultCount {
            return searchResultCount == 1 ? "1 match" : "\(searchResultCount.formatted()) matches"
        }
        if resolvedTotalCount > 0 {
            return resolvedTotalCount == 1 ? "1 chapter" : "\(resolvedTotalCount.formatted()) chapters"
        }
        return "Chapters"
    }

    init(novel: Novel, allChapters: [Chapter], totalCount: Int) {
        self.novel = novel
        self.allChapters = allChapters
        self.totalCount = totalCount
        _resolvedTotalCount = State(initialValue: totalCount)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("chapters-top")
                    chaptersHeader
                    searchSection
                    paginationBar
                    chapterList
                    paginationFooter
                }
                .padding(.bottom, 100)
                .frame(maxWidth: contentMaxWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .onChange(of: page) { _, _ in
                withAnimation(.snappy) {
                    proxy.scrollTo("chapters-top", anchor: .top)
                }
            }
        }
        .overlay(alignment: .top) {
            AsterionDetailBar(onBack: { dismiss() }, topPadding: topBarTopPadding) {
                EmptyView()
            }
        }
        .background { AsterionBackdrop() }
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
        VStack(alignment: .leading, spacing: 8) {
            Text(novel.title)
                .font(.asterionDisplay(32, weight: .medium))
                .foregroundStyle(Color.asterionText)
                .tracking(-0.6)
                .lineLimit(3)
                .minimumScaleFactor(0.8)

            Text(headerSubtitle)
                .font(.asterionReading(15))
                .foregroundStyle(Color.asterionSynopsis)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, pageHorizontalPadding)
        .padding(.top, isDesktop ? 72 : 88)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }

    private var searchSection: some View {
        SearchInputView(text: $search, placeholder: "Find a chapter")
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, 20)
            .padding(.bottom, 18)
    }

    @ViewBuilder
    private var paginationBar: some View {
        if totalPages > 1 {
            paginationControls
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.bottom, 8)
        }
    }

    private var paginationControls: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(page + 1) of \(totalPages)")
                .font(.asterionReading(13))
                .foregroundStyle(Color.asterionMuted)
                .monospacedDigit()

            Spacer()

            HStack(spacing: 20) {
                Button("Previous") { page = max(0, page - 1) }
                    .disabled(page == 0)
                    .foregroundStyle(page == 0 ? Color.asterionBorder : Color.asterionText)

                Button("Next") { page = min(totalPages - 1, page + 1) }
                    .disabled(page >= totalPages - 1)
                    .foregroundStyle(page >= totalPages - 1 ? Color.asterionBorder : Color.asterionText)
            }
            .font(.asterionReading(15, weight: .medium))
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var chapterList: some View {
        if loading {
            ProgressView()
                .tint(Color.asterionInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if let error {
            VStack(spacing: 12) {
                Text(error)
                    .font(.asterionReading(15))
                    .foregroundStyle(Color.asterionMuted)
                    .multilineTextAlignment(.center)
                Button("Try again") {
                    Task { await loadChapters(pg: page, searchTerm: debouncedSearch) }
                }
                .font(.asterionReading(15, weight: .medium))
                .foregroundStyle(Color.asterionInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .padding(.horizontal, pageHorizontalPadding)
        } else if chapters.isEmpty {
            AsterionEmptyState(
                symbol: "book.closed",
                title: debouncedSearch.isEmpty ? "No chapters yet" : "Nothing matches",
                message: debouncedSearch.isEmpty
                    ? "This title has no chapters to open."
                    : "Try a chapter number or a few words from the title."
            )
        } else {
            VStack(spacing: 0) {
                ForEach(chapters) { chapter in
                    chapterRow(chapter)
                }
            }
            .padding(.horizontal, pageHorizontalPadding)
        }
    }

    private func chapterRow(_ chapter: Chapter) -> some View {
        HStack(alignment: .center, spacing: 4) {
            NavigationLink {
                ReaderView(
                    initialChapter: chapter,
                    novel: novel,
                    allChapters: navigationChapterContext(for: chapter),
                    shouldAutoResumeFromSavedProgress: false
                )
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("\(chapter.chapterNumber)")
                        .font(.asterionReading(13, weight: .medium))
                        .foregroundStyle(Color.asterionMuted)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)

                    Text(chapter.displayTitle)
                        .font(.asterionReading(16))
                        .foregroundStyle(Color.asterionText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            downloadButton(for: chapter)
        }
    }

    private func downloadButton(for chapter: Chapter) -> some View {
        let downloaded = downloadedChapterIds.contains(chapter.id)
        return Button {
            Task { await downloadChapter(chapter) }
        } label: {
            ZStack {
                if exportingChapterId == chapter.id {
                    ProgressView()
                        .tint(Color.asterionInk)
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: downloaded ? "checkmark" : "arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(downloaded ? Color.asterionText : Color.asterionMuted)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(exportingChapterId != nil || downloaded)
        .accessibilityLabel(downloaded ? "Downloaded" : "Download chapter \(chapter.chapterNumber)")
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if totalPages > 1 && !loading && !chapters.isEmpty {
            paginationControls
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.top, 20)
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

        let header = fullChapter.labeledTitle
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
                content: content,
                novel: novel,
                chapter: fullChapter
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
