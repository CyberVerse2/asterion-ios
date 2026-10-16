import SwiftUI

struct NovelDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let novel: Novel
    let selectNovel: (Novel) -> Void

    @State private var chapters: [Chapter] = []
    @State private var chapterSearchResults: [Chapter] = []
    @State private var totalChapterCount = 0
    @State private var firstChapter: Chapter?
    @State private var progressChapter: Chapter?
    @State private var progress: ReadingProgress?
    @State private var isLoading = false
    @State private var isLoadingChapterPage = false
    @State private var errorMessage: String?
    @State private var chapterSearchError: String?
    @State private var downloadRequestError: String?
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var showsFullSynopsis = false
    @State private var selectedChapterRange = 0
    @State private var chapterSearch = ""
    @State private var showsDownloadPlanner = false

    private var isInLibrary: Bool {
        model.libraryNovelIDs.contains(novel.id)
    }

    /// Chapters of this novel on this Mac.
    private var savedChapters: OfflineChapterSet {
        offlineDownload?.saved ?? OfflineChapterSet()
    }

    private var isDownloading: Bool {
        offlineDownload?.isDownloading == true
    }

    private var offlineDownload: OfflineDownload? { model.offlineDownload(for: novel.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AsterionLayout.sectionSpacing) {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    sourceNotices
                }
                .asterionDetailInset()

                AsterionDetailSection(title: "Chapters", count: chapterCountLabel) {
                    chapterList
                }

                if !facts.isEmpty {
                    AsterionDetailSection(title: "Details") {
                        detailsPanel
                    }
                }

                if !recommendations.isEmpty {
                    AsterionDetailSection(
                        title: "More like this",
                        count: String(recommendations.count),
                        bleedsContent: true
                    ) {
                        recommendationShelf
                    }
                }
            }
            .asterionDetailPageFrame()
            .background(alignment: .top) {
                AsterionDetailBackdrop(url: coverURL)
            }
            .id("detail-top")
        }
        .hidingScrollIndicators()
        .scrollPosition($scrollPosition)
        .background(Color.asterionMediaCanvas)
        .safeAreaInset(edge: .bottom) { accountErrorBar }
        .task(id: novel.id) {
            showsFullSynopsis = false
            chapterSearch = ""
            selectedChapterRange = 0
            await load()
            await Task.yield()
            // Scroll to the true top edge; an id anchor lined the page up
            // under the toolbar instead, so it jumped once loaded.
            scrollPosition.scrollTo(edge: .top)
        }
        .task(id: chapterSearch) {
            await searchChapters()
        }
        .sheet(isPresented: $showsDownloadPlanner) {
            NovelDownloadPlannerView(
                novelTitle: novel.title,
                totalChapters: totalChapterCount,
                currentChapter: isFinished ? nil : progressChapter?.chapterNumber,
                saved: savedChapters,
                onDownload: { range in
                    Task { await startDownload(range: range) }
                },
                onRemove: savedChapters.isEmpty && offlineDownload == nil ? nil : {
                    Task { await removeDownload() }
                }
            )
        }
    }

    private var coverURL: URL? {
        novel.imageURL.flatMap(URL.init(string:))
    }

    private var hero: some View {
        AsterionDetailHero(
            imageURL: coverURL,
            fallbackSystemImage: "book.closed",
            eyebrow: eyebrow,
            title: novel.title,
            byline: novel.authorDisplayName,
            metadata: novelMetadata,
            secondaryMetadata: novelStatistics,
            summary: cleanSummary,
            showsFullSummary: $showsFullSynopsis
        ) {
            readAction
            saveAction
            downloadAction
        } footer: {
            downloadStatus

            if let novelProgress, let fraction = novelProgress.fraction {
                AsterionDetailProgress(
                    fraction: fraction,
                    caption: novelProgress.longLabel
                )
                .animation(reduceMotion ? nil : AsterionMotion.reveal, value: fraction)
            }
        }
    }

    /// How far through the whole novel the reader is. The saved percentage
    /// is only the position inside the current chapter.
    private var novelProgress: NovelProgress? {
        guard let progress else { return nil }
        return NovelProgress(
            progress: progress,
            chapterNumber: progressChapter?.chapterNumber,
            totalChapters: NovelProgress.totalChapters(
                loaded: totalChapterCount,
                catalog: novel.totalChapters
            )
        )
    }

    private var isFinished: Bool {
        novelProgress?.isFinished == true
    }

    private var eyebrow: String {
        guard let genre = novel.genres?.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !genre.isEmpty else {
            return "Novel"
        }
        return "Novel · \(genre)"
    }

    private var novelMetadata: [String] {
        // The loaded chapter list is authoritative; the catalog count can lag.
        let chapterCount = totalChapterCount > 0
            ? String(totalChapterCount)
            : novel.totalChapters.flatMap { $0.isEmpty ? nil : $0 } ?? "—"
        let status = novel.status?.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        let otherGenres = (novel.genres ?? []).dropFirst().prefix(2).joined(separator: ", ")
        return [
            "\(chapterCount) chapters",
            status.flatMap { $0.isEmpty ? nil : $0 },
            otherGenres.isEmpty ? nil : otherGenres,
        ].compactMap { $0 }
    }

    private var novelStatistics: [String] {
        [
            novel.rating.map { String(format: "%.1f rating", $0) },
            novel.views.flatMap { $0.isEmpty ? nil : "\($0) views" },
        ].compactMap { $0 }
    }

    private var readAction: some View {
        Button {
            openPreferredChapter()
        } label: {
            Label(readButtonTitle, systemImage: readButtonSymbol)
                .lineLimit(1)
        }
        .layoutPriority(1)
        .buttonStyle(.asterionPrimary)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(totalChapterCount == 0)
    }

    private var saveAction: some View {
        Button {
            Task { await model.toggleLibrary(novelID: novel.id) }
        } label: {
            Image(systemName: isInLibrary ? "bookmark.fill" : "bookmark")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.asterionSecondary)
        .help(isInLibrary ? "Saved" : "Save to Library")
        .accessibilityLabel(isInLibrary ? "Saved" : "Save to Library")
        .disabled(!model.isSignedIn || model.isUpdatingLibrary)
        .animation(reduceMotion ? nil : AsterionMotion.hover, value: isInLibrary)
    }

    /// Opens the chapter download planner, or stops the download running.
    private var downloadAction: some View {
        Button {
            if isDownloading {
                model.cancelOfflineDownload(novelID: novel.id)
            } else {
                showsDownloadPlanner = true
            }
        } label: {
            Image(systemName: downloadButtonIcon)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.asterionSecondary)
        .help(downloadButtonTitle)
        .accessibilityLabel(downloadButtonTitle)
        .disabled(!isDownloading && totalChapterCount == 0 && savedChapters.isEmpty)
        .animation(reduceMotion ? nil : AsterionMotion.hover, value: downloadButtonIcon)
    }

    @ViewBuilder
    private var sourceNotices: some View {
        if let notice = model.catalogState.notice {
            sourceNotice(
                message: notice,
                icon: "wifi.exclamationmark"
            )
        }

        if case .offline = model.chapterListState(for: novel.id),
           let notice = model.chapterListState(for: novel.id).notice {
            sourceNotice(
                message: notice,
                icon: "arrow.down.to.line"
            )
        }
    }

    private func sourceNotice(message: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.asterionMuted)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.asterionText.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .asterionPanel(cornerRadius: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
    }

    @ViewBuilder
    private var downloadStatus: some View {
        if let download = offlineDownload, download.phase == .downloading {
            HStack(spacing: 12) {
                if download.totalChapters == 0 {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing offline download…")
                        .font(.system(size: 12))
                } else {
                    AsterionLightLine(fraction: download.progress, height: 2)
                        .frame(maxWidth: 200)
                    Text(verbatim: String(download.completedChapters) + "/" + String(download.totalChapters) + " · " + download.progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.asterionMono(11.5, weight: .medium))
                }
            }
            .foregroundStyle(Color.asterionMuted)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Downloading for offline reading")
        } else if let message = offlineDownload?.errorMessage ?? downloadRequestError {
            AsterionDetailNotice(message: message)
        } else if let download = offlineDownload, download.isPartial {
            Label {
                Text(verbatim: download.saved.summary + " downloaded"
                    + (download.phase == .cancelled ? " · stopped" : ""))
            } icon: {
                Image(systemName: "arrow.down.circle")
            }
            .font(.system(size: 12))
            .foregroundStyle(Color.asterionMuted)
        }
    }

    @ViewBuilder
    private var chapterList: some View {
        if isLoading || isLoadingChapterPage {
            VStack(alignment: .leading, spacing: 14) {
                if !isLoading {
                    chapterBrowserControls
                }
                AsterionDetailRowsSkeleton()
            }
        } else if let errorMessage {
            AsterionEmptyState(
                systemImage: "exclamationmark.triangle",
                title: "Chapters didn’t load",
                message: errorMessage
            ) {
                Button("Try again") { Task { await load() } }
                    .buttonStyle(.asterionSecondary)
            }
            .frame(minHeight: 240)
            .asterionPanel(cornerRadius: 14)
        } else if totalChapterCount == 0 {
            AsterionEmptyState(
                systemImage: "text.page",
                title: "No chapters yet",
                message: "This novel hasn’t published any chapters. Check back after its next release."
            )
            .frame(minHeight: 240)
            .asterionPanel(cornerRadius: 14)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                chapterBrowserControls

                if let chapterSearchError {
                    AsterionEmptyState(
                        systemImage: "exclamationmark.magnifyingglass",
                        title: "Search unavailable",
                        message: chapterSearchError
                    )
                    .frame(minHeight: 220)
                    .asterionPanel(cornerRadius: 14)
                } else if displayedChapters.isEmpty {
                    AsterionEmptyState(
                        systemImage: "magnifyingglass",
                        title: "No matching chapters",
                        message: "Nothing matches “\(chapterSearch)”. Try a chapter number or a word from its title."
                    )
                    .frame(minHeight: 220)
                    .asterionPanel(cornerRadius: 14)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(displayedChapters.enumerated()), id: \.element.id) { index, chapter in
                            if index > 0 {
                                AsterionDetailRowDivider(leadingInset: 18)
                            }
                            chapterRow(chapter)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .asterionPanel(cornerRadius: 14)
                }
            }
        }
    }

    private var chapterBrowserControls: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(0..<chapterPageCount, id: \.self) { index in
                    Button("Chapters \(chapterRangeLabel(index))") {
                        Task { await selectChapterRange(index) }
                    }
                }
            } label: {
                Text("Chapters \(chapterRangeLabel(selectedChapterRange))")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 16)
            .asterionSmokedCapsule()
            .accessibilityLabel("Chapter range")
            .accessibilityValue("Chapters \(chapterRangeLabel(selectedChapterRange))")

            Button {
                Task { await selectChapterRange(selectedChapterRange - 1) }
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.asterionSecondary)
            .disabled(selectedChapterRange == 0)
            .help("Previous \(NovelChapterRange.pageSize) chapters")
            .accessibilityLabel("Previous \(NovelChapterRange.pageSize) chapters")

            Button {
                Task { await selectChapterRange(selectedChapterRange + 1) }
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.asterionSecondary)
            .disabled(selectedChapterRange >= chapterPageCount - 1)
            .help("Next \(NovelChapterRange.pageSize) chapters")
            .accessibilityLabel("Next \(NovelChapterRange.pageSize) chapters")

            Button {
                Task {
                    await selectChapterRange(max(chapterPageCount - 1, 0))
                    // Chapters run oldest first, so the newest is at the end.
                    if let latest = chapters.max(by: { $0.chapterNumber < $1.chapterNumber }) {
                        scrollToChapter(latest.id, anchor: .bottom)
                    }
                }
            } label: {
                Label("Latest", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.asterionSecondary)
            .help("Jump to the newest chapters")

            if let progressChapter, !isFinished {
                Button {
                    Task { await showReadingChapter(progressChapter) }
                } label: {
                    Label {
                        Text(verbatim: "Ch. " + String(progressChapter.chapterNumber))
                            .font(.asterionMono(12.5, weight: .semibold))
                    } icon: {
                        Image(systemName: "bookmark.fill")
                    }
                }
                .buttonStyle(.asterionSecondary)
                .help("Show the chapter you're reading")
                .accessibilityLabel(Text(verbatim: "Show chapter " + String(progressChapter.chapterNumber) + ", the chapter you're reading"))
            }

            Spacer(minLength: 12)

            AsterionDetailSearchField(
                prompt: "Find chapter or title",
                text: $chapterSearch,
                accessibilityLabel: "Find chapter number or title",
                onSubmit: openExactChapterMatch
            )
            .frame(minWidth: 180, idealWidth: 240, maxWidth: 300)
        }
        .controlSize(.regular)
    }

    private func chapterRow(_ chapter: Chapter) -> some View {
        NovelChapterRow(
            chapter: chapter,
            isCurrent: progress?.chapterId == chapter.id,
            isDownloaded: savedChapters.contains(chapter.id)
        ) {
            open(chapter)
        }
        .onHover { hovering in
            guard hovering else { return }
            model.prefetchChapter(id: chapter.id)
        }
    }

    private var displayedChapters: [Chapter] {
        let query = chapterSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = query.isEmpty ? chapters : chapterSearchResults
        // Reading order: oldest first; "Latest" jumps to the newest.
        return matches.sorted { $0.chapterNumber < $1.chapterNumber }
    }

    private func openExactChapterMatch() {
        let query = chapterSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(query) else { return }
        Task {
            if let chapter = try? await model.chapter(novelID: novel.id, number: number) {
                open(chapter)
            }
        }
    }

    @ViewBuilder
    private var accountErrorBar: some View {
        if let error = model.accountError {
            AsterionDetailNotice(message: error)
                .padding(.vertical, 10)
                .padding(.horizontal, AsterionLayout.pageInset)
                .frame(maxWidth: .infinity)
                .background(Color.asterionSurface)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.asterionHairline).frame(height: 1)
                }
        }
    }

    private var cleanSummary: String {
        let cleaned = (novel.summary ?? "")
            .replacingOccurrences(of: "Show More", with: "")
            .replacingOccurrences(
                of: "\\s+on [A-Z][a-z]+ \\d{1,2}, \\d{4}.*$",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "([.!?])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }

    private var readButtonTitle: String {
        guard progress != nil else { return "Start reading" }
        if isFinished { return "Finished · Read again" }
        guard let chapter = progressChapter else {
            return "Continue reading"
        }
        return "Continue chapter " + String(chapter.chapterNumber)
    }

    private var readButtonSymbol: String {
        if progress == nil { return "book.pages.fill" }
        return isFinished ? "book.closed.fill" : "book.fill"
    }

    private var downloadButtonTitle: String {
        if let download = offlineDownload, download.isDownloading {
            guard download.totalChapters > 0 else { return "Stop download" }
            return "Stop download (\(Int(download.progress * 100))%)"
        }
        if offlineDownload?.phase == .failed { return "Retry or choose chapters to download" }
        if offlineDownload?.coversWholeNovel == true { return "Downloaded · Manage download" }
        return "Download chapters…"
    }

    private var downloadButtonIcon: String {
        if isDownloading { return "xmark" }
        if offlineDownload?.phase == .failed { return "arrow.clockwise.circle" }
        if offlineDownload?.coversWholeNovel == true { return "checkmark.circle" }
        return "arrow.down.to.line"
    }

    private var chapterCountLabel: String? {
        totalChapterCount == 0 ? nil : String(totalChapterCount) + " chapters"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let chapterRequest = model.chapterPage(for: novel.id, offset: 0)
            async let progressRequest = model.fetchProgress(novelID: novel.id)
            let firstPage = try await chapterRequest
            progress = try await progressRequest
            totalChapterCount = firstPage.total
            firstChapter = firstPage.chapters.first

            if let progress {
                progressChapter = try? await model.chapter(id: progress.chapterId)
            } else {
                progressChapter = nil
            }

            let targetRange = progressChapter.map {
                max(($0.chapterNumber - 1) / NovelChapterRange.pageSize, 0)
            } ?? max(firstPage.pageCount - 1, 0)
            selectedChapterRange = min(targetRange, max(firstPage.pageCount - 1, 0))
            if selectedChapterRange == 0 {
                chapters = firstPage.chapters
            } else {
                let page = try await model.chapterPage(
                    for: novel.id,
                    offset: selectedChapterRange * NovelChapterRange.pageSize
                )
                chapters = page.chapters
            }
            errorMessage = nil
            if let progressChapter {
                model.prefetchChapter(novelID: novel.id, number: progressChapter.chapterNumber + 1)
            } else if let firstChapter {
                model.prefetchChapter(id: firstChapter.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startDownload(range: ClosedRange<Int>?) async {
        downloadRequestError = nil
        do {
            try await model.downloadForOffline(novel: novel, chapterRange: range)
        } catch {
            downloadRequestError = error.localizedDescription
        }
    }

    private func removeDownload() async {
        downloadRequestError = nil
        do {
            try await model.removeOfflineDownload(novelID: novel.id)
            await load()
        } catch {
            downloadRequestError = error.localizedDescription
        }
    }

    /// Brings the chapter being read into view, switching to its range.
    private func showReadingChapter(_ chapter: Chapter) async {
        let range = max((chapter.chapterNumber - 1) / NovelChapterRange.pageSize, 0)
        if range != selectedChapterRange || !chapterSearch.isEmpty {
            await selectChapterRange(min(range, max(chapterPageCount - 1, 0)))
        }
        let target = chapters.first { $0.id == chapter.id }
            ?? chapters.first { $0.chapterNumber == chapter.chapterNumber }
        if let target { scrollToChapter(target.id, anchor: .center) }
    }

    private func scrollToChapter(_ id: String, anchor: UnitPoint) {
        Task {
            await Task.yield()
            withAnimation(reduceMotion ? nil : AsterionMotion.reveal) {
                scrollPosition.scrollTo(id: id, anchor: anchor)
            }
        }
    }

    private func openPreferredChapter() {
        // A finished novel reads again from the start.
        if let progressChapter, !isFinished {
            open(progressChapter)
            return
        }

        if let firstChapter {
            open(firstChapter)
        }
    }

    private func open(_ chapter: Chapter) {
        openWindow(value: ReaderRoute(novelID: novel.id, chapterID: chapter.id))
    }

    private var chapterPageCount: Int {
        totalChapterCount == 0
            ? 0
            : Int(ceil(Double(totalChapterCount) / Double(NovelChapterRange.pageSize)))
    }

    private func chapterRangeLabel(_ index: Int) -> String {
        guard totalChapterCount > 0 else { return "—" }
        let start = index * NovelChapterRange.pageSize + 1
        let end = min(start + NovelChapterRange.pageSize - 1, totalChapterCount)
        return "\(start)–\(end)"
    }

    private func selectChapterRange(_ index: Int) async {
        guard index >= 0, index < chapterPageCount else { return }
        chapterSearch = ""
        isLoadingChapterPage = true
        defer { isLoadingChapterPage = false }
        do {
            let page = try await model.chapterPage(
                for: novel.id,
                offset: index * NovelChapterRange.pageSize
            )
            chapters = page.chapters
            selectedChapterRange = index
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func searchChapters() async {
        let query = chapterSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            chapterSearchResults = []
            chapterSearchError = nil
            return
        }

        chapterSearchResults = []
        chapterSearchError = nil
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            let page = try await model.chapterPage(
                for: novel.id,
                offset: 0,
                search: query
            )
            guard !Task.isCancelled else { return }
            chapterSearchResults = page.chapters
            chapterSearchError = nil
        } catch is CancellationError {
            return
        } catch {
            chapterSearchError = error.localizedDescription
        }
    }

    private var recommendationShelf: some View {
        HomeHorizontalShelf(
            items: recommendations,
            itemWidth: AsterionCardMetrics.posterWidth,
            spacing: 18,
            height: AsterionCardMetrics.posterShelfHeight
        ) { recommendation in
            EditorialBookTile(novel: recommendation, isSelected: false, rank: nil) {
                selectNovel(recommendation)
            }
        }
    }

    /// Novels sharing the most (and rarest) genres, then the best rated.
    private var recommendations: [Novel] {
        NovelCatalog.recommendations(for: novel, in: model.novels, limit: 12)
    }

    // MARK: Details

    private var facts: [NovelDetailFact] {
        // The loaded chapter list is authoritative; the catalog count can lag.
        let chapters = NovelProgress.totalChapters(
            loaded: totalChapterCount,
            catalog: novel.totalChapters
        )
        let genres = novel.displayGenres
        return [
            NovelDetailFact(label: "Author", value: novel.authorDisplayName),
            (novel.catalogStatus?.title ?? trimmed(novel.status)?.capitalized)
                .map { NovelDetailFact(label: "Status", value: $0) },
            chapters.map { NovelDetailFact(label: "Chapters", value: String($0)) },
            genres.isEmpty ? nil : NovelDetailFact(label: "Genres", value: genres.joined(separator: " · ")),
            novel.ratingLabel.map { NovelDetailFact(label: "Rating", value: $0 + " / 5") },
            trimmed(novel.views).map { NovelDetailFact(label: "Views", value: $0) },
            trimmed(novel.bookmarks).map { NovelDetailFact(label: "Bookmarks", value: $0) },
            novel.numericRank == .max
                ? nil
                : NovelDetailFact(label: "Ranking", value: "#" + String(novel.numericRank)),
        ].compactMap { $0 }
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private var detailsPanel: some View {
        let facts = facts
        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 0, alignment: .leading),
                GridItem(.flexible(), spacing: 0, alignment: .leading),
            ],
            alignment: .leading,
            spacing: 0
        ) {
            ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                AsterionDetailFactRow(label: fact.label, value: fact.value)
                    .overlay(alignment: .top) {
                        if index >= 2 {
                            Rectangle()
                                .fill(Color.asterionHairline)
                                .frame(height: 1)
                        }
                    }
            }
        }
        .padding(.vertical, 4)
        .asterionPanel(cornerRadius: 14)
    }

}

private struct NovelDetailFact: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

/// One chapter in the chapter panel: mono number, title, and its state.
private struct NovelChapterRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let chapter: Chapter
    let isCurrent: Bool
    let isDownloaded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Text(verbatim: String(chapter.chapterNumber))
                    .font(.asterionMono(12, weight: .medium))
                    .foregroundStyle(isCurrent ? Color.asterionText : Color.asterionFaint)
                    .frame(minWidth: 44, alignment: .leading)

                Text(chapter.displayTitle)
                    .font(.system(size: 13.5, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(Color.asterionText.opacity(isCurrent || isHovering ? 1 : 0.88))
                    .lineLimit(1)

                Spacer(minLength: 12)

                if isCurrent {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.asterionText)
                            .frame(width: 6, height: 6)
                            .shadow(color: .white.opacity(0.7), radius: 3)
                        Text("Reading")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color.asterionText)
                    }
                }

                if isDownloaded {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Color.asterionSuccess)
                        .help("Available offline")
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.asterionMuted)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(.horizontal, 18)
            .frame(height: 46)
            .background(isCurrent ? Color.white.opacity(0.06) : (isHovering ? Color.white.opacity(0.04) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : AsterionMotion.hover, value: isHovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Chapter " + String(chapter.chapterNumber) + ", " + chapter.displayTitle))
        .accessibilityValue(
            [isCurrent ? "Reading" : nil, isDownloaded ? "Available offline" : nil]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
        .accessibilityAddTraits(.isButton)
    }
}
