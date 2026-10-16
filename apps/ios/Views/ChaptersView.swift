import Inject
import SwiftUI

struct ChaptersView: View {
    @ObserveInjection var inject
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var tabBarState: TabBarState
    @EnvironmentObject private var readingProgressService: ReadingProgressService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
    /// Only the latest load may update the list; typing, searching and paging
    /// used to race and leave one page's chapters under another page's label.
    @State private var loadTask: Task<Void, Never>?
    /// A page set by a jump, already loaded; don't load it again.
    @State private var skipNextPageLoad = false
    /// Chapter a number search jumped to; highlighted and scrolled into view.
    @State private var targetChapterId: String?
    @State private var exportingChapterId: String?
    @State private var downloadedChapterIds = Set<String>()
    @State private var showDownloadAlert = false
    /// This account's saved position from the server, merged with the
    /// device's own reading so another device's progress counts too.
    @State private var syncedProgress: ReadingProgress?
    /// The chapter number of `currentChapterId`; chapters before it are read.
    @State private var currentChapterNumber: Int?
    @State private var downloadAlertMessage = ""
    @FocusState private var searchFocused: Bool

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
    private var contentMaxWidth: CGFloat { AsterionLayout.isWide(horizontalSizeClass) ? 920 : .infinity }
    private var pageHorizontalPadding: CGFloat { AsterionLayout.pagePadding(horizontalSizeClass) }
    private var topBarTopPadding: CGFloat { isDesktop ? 18 : 44 }

    private var headerSubtitle: String {
        if let searchResultCount {
            return searchResultCount == 1 ? "1 match" : String(searchResultCount) + " matches"
        }
        if resolvedTotalCount > 0 {
            return resolvedTotalCount == 1 ? "1 chapter" : String(resolvedTotalCount) + " chapters"
        }
        return "Chapters"
    }

    /// The newest saved position for this novel: synced progress merged with
    /// this device's reading and queued uploads.
    private var currentProgress: ReadingProgress? {
        let candidates = readingProgressService.mergedProgress(with: syncedProgress.map { [$0] } ?? [])
            .filter { $0.novelId == novel.id }
            + [readingProgressService.queuedProgress(for: novel.id)].compactMap { $0 }
        return candidates.max { ($0.lastReadAt ?? .distantPast) < ($1.lastReadAt ?? .distantPast) }
    }

    /// The chapter the reader last had open for this novel, if any.
    private var currentChapterId: String? {
        currentProgress?.chapterId
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
                .background(alignment: .top) {
                    ArtworkGlow(url: novel.imageUrl.flatMap(URL.init(string:)), height: 460, intensity: 0.7)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: page) { _, _ in
                guard targetChapterId == nil else { return }
                withAnimation(.snappy) {
                    proxy.scrollTo("chapters-top", anchor: .top)
                }
            }
            .onChange(of: targetChapterId) { _, id in
                guard let id else { return }
                Task {
                    // Let the new page lay out first.
                    try? await Task.sleep(for: .milliseconds(120))
                    withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
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
        .task { await openAtCurrentChapter() }
        .onChange(of: currentChapterId) { _, _ in
            Task { await resolveCurrentChapterNumber() }
        }
        .onAppear { tabBarState.isVisible = false }
        .onDisappear { tabBarState.isVisible = true }
        .debounceSearch(text: $search, debouncedText: $debouncedSearch)
        .onChange(of: debouncedSearch) { _, query in
            targetChapterId = nil
            if let number = Self.chapterNumber(in: query) {
                startLoad { await jump(toChapter: number) }
            } else {
                if page != 0 { skipNextPageLoad = true; page = 0 }
                startLoad { await loadChapters(pg: 0, searchTerm: titleSearchTerm) }
            }
        }
        .onChange(of: page) { _, newPage in
            if skipNextPageLoad {
                skipNextPageLoad = false
                return
            }
            targetChapterId = nil
            startLoad { await loadChapters(pg: newPage, searchTerm: titleSearchTerm) }
        }
        .alert("Chapter download", isPresented: $showDownloadAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloadAlertMessage)
        }
        .edgeSwipeToDismiss { dismiss() }
        .enableInjection()
    }

    private var chaptersHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsterionEyebrow(text: "Chapters", color: .white.opacity(0.7))

            Text(novel.title)
                .font(.asterionTitle(28, weight: .heavy))
                .foregroundStyle(Color.asterionText)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)

            Text(headerSubtitle)
                .font(.asterionMono(12.5, weight: .medium))
                .foregroundStyle(Color.asterionMuted)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, pageHorizontalPadding)
        .padding(.top, topBarTopPadding + 56)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }

    private var searchSection: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.asterionMuted)
                .accessibilityHidden(true)

            TextField(
                "",
                text: $search,
                prompt: Text("Find a chapter").foregroundStyle(Color.asterionMuted)
            )
            .font(.asterionReading(15))
            .foregroundStyle(Color.asterionText)
            .tint(Color.asterionInk)
            .focused($searchFocused)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            .onSubmit { searchFocused = false }
            .accessibilityLabel("Find a chapter")

            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.asterionFaint)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 44)
        .modifier(ChaptersSmokedBackground(shape: Capsule(), highlighted: searchFocused))
        .padding(.horizontal, pageHorizontalPadding)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var paginationBar: some View {
        if totalPages > 1 {
            paginationControls
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.bottom, 14)
        }
    }

    private func rangeLabel(for index: Int) -> String {
        let start = index * perPage + 1
        let end = max(start, min((index + 1) * perPage, activeResultCount))
        return String(start) + "–" + String(end)
    }

    private var rangeNoun: String { searchResultCount == nil ? "Chapters" : "Matches" }

    private var paginationControls: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(0..<totalPages, id: \.self) { index in
                    Button {
                        page = index
                    } label: {
                        if index == page {
                            Label("\(rangeNoun) \(rangeLabel(for: index))", systemImage: "checkmark")
                        } else {
                            Text("\(rangeNoun) \(rangeLabel(for: index))")
                        }
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Text("\(rangeNoun) \(rangeLabel(for: page))")
                        .font(.asterionMono(12.5, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.asterionMuted)
                }
                .foregroundStyle(Color.asterionText)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .modifier(ChaptersSmokedBackground(shape: Capsule()))
            }
            .accessibilityLabel("Chapter range")
            .accessibilityValue("\(rangeNoun) \(rangeLabel(for: page))")

            Spacer(minLength: 8)

            Text(verbatim: String(page + 1) + " of " + String(totalPages))
                .font(.asterionMono(11.5, weight: .medium))
                .foregroundStyle(Color.asterionFaint)
                .accessibilityLabel("Page " + String(page + 1) + " of " + String(totalPages))

            pageButton(systemName: "chevron.left", label: "Previous") {
                page = max(0, page - 1)
            }
            .disabled(page == 0)

            pageButton(systemName: "chevron.right", label: "Next") {
                page = min(totalPages - 1, page + 1)
            }
            .disabled(page >= totalPages - 1)
        }
    }

    private func pageButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 38, height: 38)
                .modifier(ChaptersSmokedBackground(shape: Circle()))
                .contentShape(Circle())
        }
        .buttonStyle(ChaptersPageButtonStyle())
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var chapterList: some View {
        if loading {
            ChaptersRowsSkeleton(rows: 8)
                .padding(.horizontal, pageHorizontalPadding)
        } else if let error {
            VStack(spacing: 0) {
                AsterionEmptyState(
                    symbol: "exclamationmark.triangle",
                    title: "Chapters didn’t load",
                    message: error
                )
                Button("Try again") {
                    Task { await loadChapters(pg: page, searchTerm: debouncedSearch) }
                }
                .font(.asterionReading(14, weight: .semibold))
                .padding(.horizontal, 20)
                .frame(height: 40)
                .buttonStyle(AsterionOutlineButtonStyle())
                .padding(.top, -24)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
            .asterionPanel(cornerRadius: 14)
            .padding(.horizontal, pageHorizontalPadding)
        } else if chapters.isEmpty {
            AsterionEmptyState(
                symbol: debouncedSearch.isEmpty ? "text.page" : "magnifyingglass",
                title: debouncedSearch.isEmpty ? "No chapters yet" : "Nothing matches",
                message: debouncedSearch.isEmpty
                    ? "This title has no chapters to open."
                    : "Try a chapter number or a few words from the title."
            )
            .asterionPanel(cornerRadius: 14)
            .padding(.horizontal, pageHorizontalPadding)
        } else {
            let currentId = currentChapterId
            VStack(spacing: 0) {
                ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.asterionHairline)
                            .frame(height: 1)
                            .padding(.leading, 16)
                    }
                    chapterRow(
                        chapter,
                        isCurrent: chapter.id == currentId,
                        isRead: chapter.id != currentId && ChapterReadState.isRead(
                            chapterNumber: chapter.chapterNumber,
                            readingChapterNumber: currentChapterNumber
                        )
                    )
                        .background(
                            chapter.id == targetChapterId ? Color.white.opacity(0.07) : Color.clear
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .asterionPanel(cornerRadius: 14)
            .padding(.horizontal, pageHorizontalPadding)
        }
    }

    private func chapterRow(_ chapter: Chapter, isCurrent: Bool, isRead: Bool) -> some View {
        HStack(alignment: .center, spacing: 0) {
            NavigationLink {
                ReaderView(
                    initialChapter: chapter,
                    novel: novel,
                    allChapters: navigationChapterContext(for: chapter),
                    shouldAutoResumeFromSavedProgress: false
                )
            } label: {
                HStack(spacing: 14) {
                    ChapterNumberLabel(number: chapter.chapterNumber, isCurrent: isCurrent, isRead: isRead)

                    Text(chapter.displayTitle.isEmpty ? chapter.labeledTitle : chapter.displayTitle)
                        .font(.asterionReading(14.5, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(Color.asterionText.opacity(isCurrent ? 1 : (isRead ? 0.55 : 0.88)))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isCurrent {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.asterionText)
                                .frame(width: 6, height: 6)
                                .shadow(color: .white.opacity(0.7), radius: 3)
                            Text("Reading")
                                .font(.asterionReading(11.5, weight: .semibold))
                                .foregroundStyle(Color.asterionText)
                        }
                    }
                }
                .padding(.leading, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Chapter " + String(chapter.chapterNumber) + ", " + chapter.displayTitle)
            .accessibilityValue(isCurrent ? "Reading" : (isRead ? "Read" : ""))

            downloadButton(for: chapter)
                .padding(.trailing, 4)
        }
        .frame(minHeight: 50)
        .background(isCurrent ? Color.white.opacity(0.06) : .clear)
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
                        .font(.system(size: downloaded ? 11 : 12.5, weight: .bold))
                        .foregroundStyle(downloaded ? Color.asterionSuccess : Color.asterionMuted)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(exportingChapterId != nil || downloaded)
        .accessibilityLabel(downloaded ? "Downloaded" : "Download chapter " + String(chapter.chapterNumber))
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
                guard !Task.isCancelled else { return }
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
            guard !Task.isCancelled else { return }
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
            guard !Task.isCancelled else { return }
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

    /// A number in the search box is a jump, not a filter.
    private var titleSearchTerm: String {
        Self.chapterNumber(in: debouncedSearch) == nil ? debouncedSearch : ""
    }

    static func chapterNumber(in query: String) -> Int? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"^(?i)(chapter|ch\.?)\s*"#, with: "", options: .regularExpression)
        guard let number = Int(trimmed), number > 0 else { return nil }
        return number
    }

    private func startLoad(_ work: @escaping @MainActor () async -> Void) {
        loadTask?.cancel()
        loadTask = Task { await work() }
    }

    /// Opens on the page holding the chapter being read, not chapter 1. The
    /// synced position is fetched first so reading on another device counts.
    private func openAtCurrentChapter() async {
        if let remote = try? await apiClient.fetchReadingProgress(novelId: novel.id) {
            syncedProgress = remote
        }
        guard currentChapterId != nil else {
            await loadChapters(pg: 0)
            return
        }
        let number = await resolveCurrentChapterNumber()
        if let number, number > 0 {
            await jump(toChapter: number, highlight: false)
        } else {
            await loadChapters(pg: 0)
        }
    }

    /// Finds the number of the chapter being read: from the chapters already
    /// at hand, the cache, then the network.
    @discardableResult
    private func resolveCurrentChapterNumber() async -> Int? {
        guard let currentId = currentChapterId else {
            currentChapterNumber = nil
            return nil
        }
        var number = (allChapters.first { $0.id == currentId }
            ?? chapters.first { $0.id == currentId })?.chapterNumber
        if number == nil {
            number = await ReadingPositionResolver.chapter(id: currentId, novelId: novel.id, apiClient: apiClient)?
                .chapterNumber
        }
        if currentChapterId == currentId { currentChapterNumber = number }
        return number
    }

    /// Loads the page holding chapter `number`. Chapter numbers mostly track
    /// list position, so start there and correct by the gap a few times.
    private func jump(toChapter number: Int, highlight: Bool = true) async {
        loading = true
        error = nil
        defer { loading = false }
        var guess = max(0, (number - 1) / perPage)
        var loaded: [Chapter] = []
        do {
            for _ in 0..<4 {
                let response = try await apiClient.fetchChapters(
                    novelId: novel.id,
                    limit: perPage,
                    offset: guess * perPage
                )
                guard !Task.isCancelled else { return }
                if let total = response.meta?.total { resolvedTotalCount = total }
                loaded = response.data
                guard let first = loaded.first?.chapterNumber, let last = loaded.last?.chapterNumber else { break }
                let lastPage = max(0, totalPages - 1)
                if number < first, guess > 0 {
                    guess = max(0, guess - max(1, (first - number + perPage - 1) / perPage))
                } else if number > last, guess < lastPage {
                    guess = min(lastPage, guess + max(1, (number - last + perPage - 1) / perPage))
                } else {
                    break
                }
            }
            await OfflineChapterStore.shared.saveChapterList(novelId: novel.id, chapters: loaded, mergeWithExisting: true)
        } catch {
            guard !Task.isCancelled else { return }
            let cached = await OfflineChapterStore.shared.loadChapterList(novelId: novel.id)
            guard let index = cached.firstIndex(where: { $0.chapterNumber >= number }) else {
                self.error = error.localizedDescription
                return
            }
            guess = index / perPage
            let start = guess * perPage
            loaded = Array(cached[start..<min(start + perPage, cached.count)])
        }
        guard !Task.isCancelled else { return }
        searchResultCount = nil
        chapters = loaded
        let match = loaded.first { $0.chapterNumber == number }
        targetChapterId = highlight ? match?.id : nil
        if page != guess {
            skipNextPageLoad = true
            page = guess
        }
        if !highlight, let match {
            // Opening on the reading chapter: bring it into view, unhighlighted.
            targetChapterId = match.id
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                if targetChapterId == match.id { targetChapterId = nil }
            }
        }
        await refreshDownloadedChapterState()
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
            Haptics.success()
        } catch {
            downloadAlertMessage = "Couldn't save chapter to local folder."
            showDownloadAlert = true
            Haptics.error()
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

/// Smoked glass behind floating controls: material, a dark wash, and a hairline.
private struct ChaptersSmokedBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(Color.black.opacity(0.25)))
            }
            .overlay(shape.strokeBorder(Color.white.opacity(highlighted ? 0.32 : 0.16)))
    }
}

/// White icon on a smoked circle; dims when there is no page to move to.
private struct ChaptersPageButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.asterionText)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Skeleton chapter rows in a panel while a page of chapters loads.
private struct ChaptersRowsSkeleton: View {
    var rows = 8

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { index in
                if index > 0 {
                    Rectangle()
                        .fill(Color.asterionHairline)
                        .frame(height: 1)
                        .padding(.leading, 16)
                }
                HStack(spacing: 14) {
                    AsterionSkeleton(cornerRadius: 3).frame(width: 30, height: 10)
                    AsterionSkeleton(cornerRadius: 3)
                        .frame(width: CGFloat(140 + (index * 53) % 120), height: 10)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
            }
        }
        .asterionPanel(cornerRadius: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading chapters")
    }
}
