import AsterionKit
import Inject
import SwiftUI
import Combine

struct NovelDetailView: View {
    @ObserveInjection var inject
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var readingProgressService: ReadingProgressService
    @EnvironmentObject private var tabBarState: TabBarState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var novelLibrary: NovelLibraryService
    @ObservedObject private var downloadManager = NovelDownloadManager.shared
    let novel: Novel
    var onBack: (() -> Void)?

    @State private var chapters: [Chapter] = []
    @State private var totalChapters = 0
    @State private var loadingChapters = false
    @State private var chapterError: String?
    @State private var synopsisExpanded = false
    @State private var allNovels: [Novel] = []
    @State private var readingProgress: ReadingProgress?
    @State private var continueChapter: Chapter?
    @State private var isNovelAvailableOffline = false
    @State private var downloadedChapterIds = Set<String>()
    /// Chapters around the one being read; nil shows the first chapters.
    @State private var previewChapters: [Chapter]?
    @State private var isResolvingPreview = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let previewCount = 5
    private var isDesktop: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }
    private var topBarTopPadding: CGFloat { isDesktop ? 18 : 44 }
    private var isWide: Bool { AsterionLayout.isWide(horizontalSizeClass) }
    private var pagePadding: CGFloat { AsterionLayout.pagePadding(horizontalSizeClass) }
    /// Clears the floating back button that sits over the glow.
    private var heroTopPadding: CGFloat { topBarTopPadding + 52 }
    private var coverURL: URL? { novel.imageUrl.flatMap(URL.init(string:)) }

    /// Ranked by how many genres they share with this novel, then rating.
    private var similarNovels: [Novel] {
        NovelCatalog.similar(to: novel, in: allNovels)
    }

    /// The preview rows: around the chapter being read, else the first ones.
    private var displayedPreview: [Chapter] {
        previewChapters ?? Array(chapters.prefix(previewCount))
    }

    /// Every chapter this page knows, in order, for the reader's neighbours.
    private var knownChapters: [Chapter] {
        var seen = Set<String>()
        return (chapters + (previewChapters ?? []) + (continueChapter.map { [$0] } ?? []))
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.chapterNumber < $1.chapterNumber }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AsterionLayout.sectionSpacing) {
                heroSection
                    .padding(.horizontal, pagePadding)
                    .padding(.top, heroTopPadding)
                chaptersSection
                detailsSection
                moreLikeThisSection
            }
            .padding(.bottom, 100)
            .frame(maxWidth: isWide ? 1180 : .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
            .background(alignment: .top) {
                AsterionCoverBleed(url: coverURL, height: isWide ? 520 : 440)
            }
        }
        .background(Color.asterionBackground)
        .overlay(alignment: .top) {
            AsterionDetailBar(onBack: performBack, topPadding: topBarTopPadding) {
                EmptyView()
            }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .task { await loadInitialData() }
        .onAppear {
            tabBarState.isVisible = false
            // A download may have finished, or been removed in Downloads, meanwhile.
            Task { await refreshOfflineAvailability() }
        }
        .onChange(of: downloadManager.snapshot(for: novel.id)?.phase) { _, phase in
            guard phase == .finished else { return }
            Task {
                await refreshOfflineAvailability()
                await refreshDownloadedPreviewChapters()
            }
        }
        .onDisappear { tabBarState.isVisible = true }
        .edgeSwipeToDismiss { performBack() }
        .enableInjection()
    }

    private func performBack() {
        if let onBack {
            onBack()
        } else {
            dismiss()
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var heroSection: some View {
        if isWide {
            HStack(alignment: .top, spacing: 36) {
                poster(width: 210, height: 315)
                VStack(alignment: .leading, spacing: 0) {
                    titleBlock(titleSize: 36)
                    heroDetails
                }
                .padding(.top, 6)
                .frame(maxWidth: 680, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 18) {
                    poster(width: 124, height: 186)
                    titleBlock(titleSize: 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                heroDetails
            }
        }
    }

    private func poster(width: CGFloat, height: CGFloat) -> some View {
        NovelPosterArt(novel: novel)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1))
            }
            .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
            .accessibilityHidden(true)
    }

    private func titleBlock(titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AsterionEyebrow(text: eyebrow, color: .white.opacity(0.7))

            Text(novel.title)
                .font(.asterionTitle(titleSize, weight: .heavy))
                .foregroundStyle(Color.asterionText)
                .lineLimit(4)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 4)
                .accessibilityAddTraits(.isHeader)

            Text(novel.author ?? "Unknown author")
                .font(.asterionReading(14, weight: .medium))
                .foregroundStyle(Color.asterionMuted)
                .lineLimit(2)
        }
    }

    /// Metadata, synopsis, actions, and progress beneath (or beside) the title.
    private var heroDetails: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !metadataLine.isEmpty {
                Text(metadataLine)
                    .font(.asterionReading(13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(2)
                    .padding(.top, 18)
            }

            synopsisSection
                .padding(.top, 16)

            actionsRow
                .padding(.top, 22)

            heroFooter
                .padding(.top, 16)
        }
    }

    private var eyebrow: String {
        guard let genre = novel.genres?.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !genre.isEmpty else {
            return "Novel"
        }
        return "Novel · \(genre)"
    }

    private var chapterCount: Int {
        if totalChapters > 0 { return totalChapters }
        return novel.catalogChapterCount ?? 0
    }

    /// Where the reader is in the whole novel, once the saved chapter is known.
    private var novelProgress: NovelProgress? {
        guard let readingProgress else { return nil }
        return NovelProgress(
            progress: readingProgress,
            chapterNumber: continueChapter?.chapterNumber,
            totalChapters: chapterCount > 0 ? chapterCount : nil
        )
    }

    private var isFinished: Bool { novelProgress?.isFinished == true }

    /// Chapter 1 (or the first listed chapter) for reading a finished novel again.
    private var firstChapter: Chapter? {
        chapters.first(where: { $0.chapterNumber == 1 }) ?? chapters.first
    }

    private var metadataLine: String {
        let status = novel.status?.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        return [
            chapterCount > 0 ? (chapterCount == 1 ? "1 chapter" : String(chapterCount) + " chapters") : nil,
            status.flatMap { $0.isEmpty ? nil : $0 },
            novel.rating.map { String(format: "★ %.1f", $0) },
            novel.rank.flatMap { $0.isEmpty ? nil : "Rank #\($0.filter(\.isNumber))" },
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    // MARK: - Synopsis

    @ViewBuilder
    private var synopsisSection: some View {
        let otherGenres = (novel.genres ?? []).dropFirst().prefix(3)
        let summary = cleanedSummary
        if !otherGenres.isEmpty || summary != nil {
            VStack(alignment: .leading, spacing: 10) {
                if !otherGenres.isEmpty {
                    Text(otherGenres.joined(separator: " · "))
                        .font(.asterionReading(12.5, weight: .medium))
                        .foregroundStyle(Color.asterionMuted)
                        .lineLimit(1)
                }
                if let summary {
                    Text(summary)
                        .font(.asterionReading(15))
                        .foregroundStyle(Color.asterionSynopsis)
                        .lineSpacing(5)
                        .lineLimit(synopsisExpanded ? nil : 4)
                        .fixedSize(horizontal: false, vertical: true)

                    if summary.count > 180 {
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                                synopsisExpanded.toggle()
                            }
                        } label: {
                            Text(synopsisExpanded ? "Show less" : "More")
                                .font(.asterionReading(14, weight: .semibold))
                                .foregroundStyle(Color.asterionText.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
        }
    }

    private var cleanedSummary: String? {
        guard let summary = novel.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty else { return nil }
        return summary
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: #"\.(\S)"#, with: ". $1", options: .regularExpression)
    }

    // MARK: - Actions

    private var actionsRow: some View {
        HStack(spacing: 10) {
            startReadingButton
            libraryBadge
            downloadChip
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var startReadingButton: some View {
        if let targetChapter = isFinished ? firstChapter : (continueChapter ?? firstChapter) {
            let chapterListForReader: [Chapter] = {
                if chapters.contains(where: { $0.id == targetChapter.id }) {
                    return chapters
                }
                return [targetChapter] + chapters
            }()
            NavigationLink {
                ReaderView(
                    initialChapter: targetChapter,
                    novel: novel,
                    allChapters: chapterListForReader,
                    // Reading again starts at chapter 1, not the saved last page.
                    shouldAutoResumeFromSavedProgress: !isFinished
                )
            } label: {
                Label(readingButtonTitle, systemImage: isFinished ? "book.closed.fill" : "book.fill")
                    .font(.asterionReading(15, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 22)
                    .frame(height: 46)
            }
            .buttonStyle(AsterionFilledButtonStyle())
            .layoutPriority(1)
        } else if loadingChapters {
            AsterionSkeleton(cornerRadius: 23)
                .frame(width: 168, height: 46)
        }
    }

    private var readingButtonTitle: String {
        guard readingProgress != nil else { return "Start reading" }
        if isFinished { return "Finished · Read again" }
        if let chapterNumber = continueChapter?.chapterNumber, chapterNumber > 0 {
            return "Continue chapter " + String(chapterNumber)
        }
        return "Continue reading"
    }

    private var isInLibrary: Bool { novelLibrary.contains(novel.id) }

    /// Works signed out and offline: the save lands on this device at once
    /// and reaches the account when it can.
    private var libraryBadge: some View {
        AsterionCircleIconButton(
            systemName: isInLibrary ? "bookmark.fill" : "bookmark",
            accessibilityLabel: isInLibrary ? "Remove from library" : "Save to library"
        ) {
            toggleLibrary()
        }
    }

    private var downloadChip: some View {
        Button {
            if !effectiveIsDownloading {
                downloadAllChapters()
            }
        } label: {
            ZStack {
                if effectiveIsDownloading {
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: 2)
                        .frame(width: 38, height: 38)
                    Circle()
                        .trim(from: 0, to: max(downloadProgress, 0.04))
                        .stroke(
                            Color.asterionInk,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 38, height: 38)
                        .shadow(color: .white.opacity(0.5), radius: 3)
                }

                Image(systemName: downloadIndicatorIconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(downloadIndicatorColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 46, height: 46)
            .background(DetailSmokedCircle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(downloadStatusLabel)
        .disabled((effectiveIsDownloading && effectiveTotalCount == 0) || (!networkMonitor.isConnected && !effectiveIsDownloading))
        .opacity(!networkMonitor.isConnected && !effectiveIsDownloading ? 0.55 : 1)
    }

    @ViewBuilder
    private var heroFooter: some View {
        VStack(alignment: .leading, spacing: 14) {
            downloadStatus
            readingProgressLine
        }
    }

    @ViewBuilder
    private var downloadStatus: some View {
        if effectiveIsDownloading {
            HStack(spacing: 12) {
                if effectiveTotalCount == 0 {
                    ProgressView()
                        .tint(Color.asterionMuted)
                        .controlSize(.small)
                    Text("Preparing offline download…")
                        .font(.asterionReading(12.5))
                } else {
                    AsterionLightLine(fraction: Double(downloadProgress), height: 2)
                        .frame(maxWidth: 200)
                    Text(verbatim: String(effectivePreparedCount) + "/" + String(effectiveTotalCount) + " · " + String(Int((downloadProgress * 100).rounded())) + "%")
                        .font(.asterionMono(11.5, weight: .medium))
                }
            }
            .foregroundStyle(Color.asterionMuted)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Downloading for offline reading")
            .accessibilityValue(downloadStatusLabel)
        } else if let downloadError {
            Label(downloadError, systemImage: "exclamationmark.triangle.fill")
                .font(.asterionReading(12.5, weight: .medium))
                .foregroundStyle(Color.asterionWarning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var readingProgressLine: some View {
        if let progress = novelProgress, progress.knowsWholeNovel, let label = progress.label {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 12) {
                    AsterionLightLine(fraction: progress.fraction, height: 3)
                        .frame(maxWidth: 320)
                    Text(verbatim: "\(progress.displayPercentage)%")
                        .font(.asterionMono(11.5, weight: .medium))
                        .foregroundStyle(Color.asterionMuted)
                        .accessibilityHidden(true)
                }
                Text(progress.isFinished ? "Finished · " + label : label)
                    .font(.asterionMono(11.5, weight: .medium))
                    .foregroundStyle(Color.asterionMuted)
            }
            .frame(maxWidth: 380, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Reading progress")
            .accessibilityValue(
                [progress.isFinished ? "Finished" : nil, progress.longLabel, "\(progress.displayPercentage) percent"]
                    .compactMap { $0 }
                    .joined(separator: ", ")
            )
        }
    }

    private var downloadSnapshot: NovelDownloadManager.Snapshot? {
        downloadManager.snapshot(for: novel.id)
    }

    private var effectiveIsDownloading: Bool {
        downloadSnapshot?.isActive == true
    }

    private var effectivePreparedCount: Int {
        downloadSnapshot?.completed ?? 0
    }

    private var effectiveTotalCount: Int {
        downloadSnapshot.map { $0.phase == .preparing ? 0 : $0.total } ?? 0
    }

    private var downloadError: String? {
        downloadSnapshot?.errorMessage
    }

    private var downloadProgress: CGFloat {
        guard effectiveTotalCount > 0 else { return 0 }
        return min(1, CGFloat(effectivePreparedCount) / CGFloat(effectiveTotalCount))
    }

    private var downloadIndicatorIconName: String {
        isNovelAvailableOffline ? "checkmark" : "arrow.down"
    }

    private var downloadIndicatorColor: Color {
        isNovelAvailableOffline ? Color.asterionSuccess : Color.asterionInk
    }

    private var downloadStatusLabel: String {
        if effectiveIsDownloading {
            return "Downloading \(effectivePreparedCount)/\(max(effectiveTotalCount, 1))"
        }
        if isNovelAvailableOffline {
            return "Available offline"
        }
        return "Download all"
    }

    // MARK: - Chapters

    private var chaptersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            DetailSectionHeader(
                title: "Chapters",
                count: chapterCount > 0 ? String(chapterCount) : nil
            )
            chapterList
        }
        .padding(.horizontal, pagePadding)
    }

    @ViewBuilder
    private var chapterList: some View {
        if (loadingChapters && chapters.isEmpty) || (isResolvingPreview && chapterError == nil) {
            DetailChapterRowsSkeleton(rows: previewCount)
        } else if let error = chapterError {
            VStack(spacing: 0) {
                AsterionEmptyState(
                    symbol: "exclamationmark.triangle",
                    title: "Chapters didn’t load",
                    message: error
                )
                Button("Try again") { Task { await loadChapters() } }
                    .font(.asterionReading(14, weight: .semibold))
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .buttonStyle(AsterionOutlineButtonStyle())
                    .padding(.top, -24)
                    .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
            .asterionPanel(cornerRadius: 14)
        } else if displayedPreview.isEmpty {
            AsterionEmptyState(
                symbol: "text.page",
                title: "No chapters yet",
                message: "This novel hasn’t published any chapters. Check back after its next release."
            )
            .asterionPanel(cornerRadius: 14)
        } else {
            let preview = displayedPreview
            let readingNumber = continueChapter?.chapterNumber
            let readerContext = knownChapters
            VStack(spacing: 0) {
                ForEach(Array(preview.enumerated()), id: \.element.id) { index, chapter in
                    if index > 0 {
                        DetailRowDivider()
                    }
                    NavigationLink {
                        ReaderView(
                            initialChapter: chapter,
                            novel: novel,
                            allChapters: readerContext,
                            shouldAutoResumeFromSavedProgress: false
                        )
                    } label: {
                        DetailChapterRow(
                            chapter: chapter,
                            isCurrent: !isFinished && readingProgress?.chapterId == chapter.id,
                            isRead: ChapterReadState.isRead(
                                chapterNumber: chapter.chapterNumber,
                                readingChapterNumber: readingNumber,
                                novelFinished: isFinished
                            ),
                            isDownloaded: isNovelAvailableOffline || downloadedChapterIds.contains(chapter.id)
                        )
                    }
                    .buttonStyle(.plain)
                }

                DetailRowDivider(leadingInset: 0)

                NavigationLink {
                    ChaptersView(novel: novel, allChapters: chapters, totalCount: totalChapters)
                } label: {
                    HStack(spacing: 12) {
                        Text("View all chapters")
                            .font(.asterionReading(14, weight: .semibold))
                            .foregroundStyle(Color.asterionText)
                        Spacer(minLength: 8)
                        if chapterCount > 0 {
                            Text(verbatim: String(chapterCount))
                                .font(.asterionMono(11.5, weight: .medium))
                                .foregroundStyle(Color.asterionFaint)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.asterionMuted)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .asterionPanel(cornerRadius: 14)
        }
    }

    // MARK: - Details

    private var detailFacts: [(label: String, value: String)] {
        let genres = (novel.genres ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let views = novel.views?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bookmarks = novel.bookmarks?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rank = novel.rankPosition == .max ? nil : "#" + String(novel.rankPosition)
        let facts: [(String, String?)] = [
            ("Author", novel.author?.trimmingCharacters(in: .whitespacesAndNewlines)),
            ("Status", novel.statusTitle),
            ("Chapters", chapterCount > 0 ? String(chapterCount) : nil),
            ("Genres", genres.isEmpty ? nil : genres.joined(separator: ", ")),
            ("Rating", novel.rating.map { String(format: "%.1f", $0) + " / 5" }),
            ("Views", views.isEmpty ? nil : views),
            ("Bookmarks", bookmarks.isEmpty ? nil : bookmarks),
            ("Rank", rank),
        ]
        return facts.compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return (label, value)
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        let facts = detailFacts
        if !facts.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                DetailSectionHeader(title: "Details")
                VStack(spacing: 0) {
                    ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                        DetailFactRow(
                            label: fact.label,
                            value: fact.value,
                            showsDivider: index < facts.count - 1
                        )
                    }
                }
                .asterionPanel(cornerRadius: 14)
            }
            .frame(maxWidth: isWide ? 760 : .infinity, alignment: .leading)
            .padding(.horizontal, pagePadding)
        }
    }

    // MARK: - More like this

    @ViewBuilder
    private var moreLikeThisSection: some View {
        if !similarNovels.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                DetailSectionHeader(title: "More like this", count: String(similarNovels.count))
                    .padding(.horizontal, pagePadding)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(similarNovels) { similar in
                            NavigationLink {
                                NovelDetailView(novel: similar)
                            } label: {
                                HomeNovelCard(novel: similar)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, pagePadding)
                }
            }
        }
    }

    private func refreshDownloadedPreviewChapters() async {
        var downloaded = Set<String>()
        for chapter in displayedPreview {
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

    // MARK: - Data

    private func loadInitialData() async {
        async let chaptersTask: () = loadChapters()
        async let novelsTask: () = loadAllNovels()
        async let progressTask: () = loadProgress()
        // Picks up saves made on another device (no-op for guests).
        async let libraryTask: () = novelLibrary.refresh()
        _ = await (chaptersTask, novelsTask, progressTask, libraryTask)
        await loadPreviewAroundCurrent()
        await refreshOfflineAvailability()
        await refreshDownloadedPreviewChapters()
    }

    private func loadChapters() async {
        loadingChapters = true
        chapterError = nil
        defer { loadingChapters = false }
        do {
            let response = try await apiClient.fetchChapters(
                novelId: novel.id,
                limit: previewCount,
                offset: 0
            )
            await OfflineChapterStore.shared.saveChapterList(novelId: novel.id, chapters: response.data, mergeWithExisting: true)
            chapters = response.data
            totalChapters = response.meta?.total
                ?? response.meta?.count
                ?? novel.catalogChapterCount
                ?? response.data.count
        } catch {
            let cached = await OfflineChapterStore.shared.loadChapterList(novelId: novel.id)
            if !cached.isEmpty {
                chapters = Array(cached.prefix(previewCount))
                // The cached list may hold only the chapters opened so far.
                totalChapters = max(cached.count, novel.catalogChapterCount ?? 0)
                chapterError = nil
            } else {
                chapterError = error.localizedDescription
            }
        }
    }

    /// The catalog for "More like this". The cached copy (which Home and
    /// Browse keep fresh) is enough; the network is only asked without one.
    private func loadAllNovels() async {
        let cached = await OfflineChapterStore.shared.loadCatalog()
        if !cached.isEmpty {
            allNovels = cached
            return
        }
        if let fetched = try? await apiClient.fetchAllNovels(), !fetched.isEmpty {
            allNovels = fetched
            await OfflineChapterStore.shared.saveCatalog(fetched)
        }
    }

    /// Loads the chapters around the one being read, so the preview shows
    /// where the reader is rather than chapters 1–5. Chapter numbers mostly
    /// track list position, so the page is guessed from the number and
    /// corrected once by the gap; offline, the cached list stands in.
    private func loadPreviewAroundCurrent() async {
        defer { isResolvingPreview = false }
        guard !isFinished, let current = continueChapter, current.chapterNumber > 0 else {
            previewChapters = nil
            return
        }
        // Already among the first rows: the first page shows it well.
        if let index = chapters.firstIndex(where: { $0.id == current.id }), index < previewCount / 2 + 1 {
            previewChapters = nil
            return
        }

        let number = current.chapterNumber
        var offset = ChapterPreviewWindow.offset(
            around: number,
            size: previewCount,
            total: chapterCount > 0 ? chapterCount : nil
        )
        for _ in 0..<2 {
            guard let page = try? await apiClient.fetchChapters(novelId: novel.id, limit: previewCount, offset: offset),
                  let first = page.data.first else { break }
            if page.data.contains(where: { $0.id == current.id || $0.chapterNumber == number }) {
                await OfflineChapterStore.shared.saveChapterList(novelId: novel.id, chapters: page.data, mergeWithExisting: true)
                previewChapters = page.data
                return
            }
            let corrected = max(0, offset + (number - first.chapterNumber) - previewCount / 2)
            guard corrected != offset else { break }
            offset = corrected
        }

        let cached = await OfflineChapterStore.shared.loadChapterList(novelId: novel.id)
            .sorted { $0.chapterNumber < $1.chapterNumber }
        if let index = cached.firstIndex(where: { $0.id == current.id }) {
            let start = max(0, min(index - previewCount / 2, cached.count - previewCount))
            previewChapters = Array(cached[start..<min(start + previewCount, cached.count)])
        } else {
            previewChapters = [current]
        }
    }

    private func loadProgress() async {
        do {
            readingProgress = try await apiClient.fetchReadingProgress(novelId: novel.id)
        } catch {
            readingProgress = nil
        }

        let bestProgress = readingProgressService.currentProgress?.novelId == novel.id
            ? readingProgressService.currentProgress
            : (readingProgress ?? readingProgressService.queuedProgress(for: novel.id))

        guard let bestProgress else {
            continueChapter = nil
            return
        }

        readingProgress = bestProgress
        continueChapter = await resolveContinueChapter(for: bestProgress)
    }

    private func resolveContinueChapter(for progress: ReadingProgress) async -> Chapter? {
        do {
            let chapter = try await apiClient.fetchChapter(id: progress.chapterId)
            await OfflineChapterStore.shared.cacheChapter(chapter)
            return chapter
        } catch {
            if let cached = await OfflineChapterStore.shared.chapter(id: progress.chapterId) {
                return cached
            }

            let cachedChapters = await OfflineChapterStore.shared.loadChapterList(novelId: novel.id)
            if let listed = cachedChapters.first(where: { $0.id == progress.chapterId }) {
                return listed
            }

            if let listed = chapters.first(where: { $0.id == progress.chapterId }) {
                return listed
            }

            return nil
        }
    }

    private func toggleLibrary() {
        if novelLibrary.toggle(novel) {
            Haptics.success()
        } else {
            Haptics.tap()
        }
    }

    private func downloadAllChapters() {
        downloadManager.start(novel: novel, apiClient: apiClient, knownChapters: chapters)
    }

    /// Available offline once the download folder holds every chapter.
    private func refreshOfflineAvailability() async {
        let downloaded = await OfflineChapterStore.shared.downloadedChapterCount(novelTitle: novel.title)
        guard downloaded > 0 else {
            isNovelAvailableOffline = false
            return
        }
        var expected = totalChapters > 0 ? totalChapters : (novel.catalogChapterCount ?? 0)
        if expected == 0 {
            expected = await OfflineChapterStore.shared.loadChapterList(novelId: novel.id).count
        }
        isNovelAvailableOffline = downloaded >= max(1, expected)
    }
}

// MARK: - Detail chrome

/// Smoked circular backing for icon buttons beside the primary action.
private struct DetailSmokedCircle: View {
    var body: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().fill(Color.black.opacity(0.25)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.16)))
    }
}

/// Section heading in the title-card face with a mono count at the trailing edge.
private struct DetailSectionHeader: View {
    let title: String
    var count: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            AsterionSectionLabel(title: title)
            if let count, !count.isEmpty {
                Text(count)
                    .font(.asterionMono(11.5, weight: .medium))
                    .foregroundStyle(Color.asterionFaint)
                    .accessibilityLabel("\(count) items")
            }
        }
    }
}

private struct DetailRowDivider: View {
    var leadingInset: CGFloat = 16

    var body: some View {
        Rectangle()
            .fill(Color.asterionHairline)
            .frame(height: 1)
            .padding(.leading, leadingInset)
    }
}

/// One chapter in a panel: faint mono number, title, and its reading and
/// offline state. The chapter being read is lit with a small white dot.
private struct DetailChapterRow: View {
    let chapter: Chapter
    let isCurrent: Bool
    var isRead = false
    let isDownloaded: Bool

    var body: some View {
        HStack(spacing: 14) {
            ChapterNumberLabel(number: chapter.chapterNumber, isCurrent: isCurrent, isRead: isRead, minWidth: 36)

            Text(chapter.displayTitle.isEmpty ? chapter.labeledTitle : chapter.displayTitle)
                .font(.asterionReading(14.5, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(Color.asterionText.opacity(isCurrent ? 1 : (isRead ? 0.55 : 0.88)))
                .lineLimit(1)
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

            if isDownloaded {
                Image(systemName: "checkmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Color.asterionSuccess)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.asterionFaint)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
        .background(isCurrent ? Color.white.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chapter " + String(chapter.chapterNumber) + ", " + chapter.displayTitle)
        .accessibilityValue(
            [isCurrent ? "Reading" : nil, isRead ? "Read" : nil, isDownloaded ? "Available offline" : nil]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
        .accessibilityAddTraits(.isButton)
    }
}

/// Skeleton rows in a panel while chapters load.
private struct DetailChapterRowsSkeleton: View {
    var rows = 5

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { index in
                if index > 0 {
                    DetailRowDivider()
                }
                HStack(spacing: 14) {
                    AsterionSkeleton(cornerRadius: 3).frame(width: 28, height: 10)
                    AsterionSkeleton(cornerRadius: 3)
                        .frame(width: CGFloat(140 + (index * 53) % 110), height: 10)
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

/// One fact in the Details panel: label on the leading edge, value trailing.
private struct DetailFactRow: View {
    let label: String
    let value: String
    let showsDivider: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.asterionReading(13.5))
                .foregroundStyle(Color.asterionMuted)
            Spacer(minLength: 12)
            Text(value)
                .font(.asterionReading(13.5, weight: .medium))
                .foregroundStyle(Color.asterionText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(Color.asterionHairline)
                    .frame(height: 1)
                    .padding(.leading, 16)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A chapter's mono number, with a small check once it has been read
/// (the chapters before the one being read), like an episode's watched tick.
struct ChapterNumberLabel: View {
    let number: Int
    let isCurrent: Bool
    let isRead: Bool
    var minWidth: CGFloat = 40

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: number > 0 ? String(number) : "–")
                .font(.asterionMono(12, weight: .medium))
                .foregroundStyle(isCurrent ? Color.asterionText : Color.asterionFaint)
            if isRead {
                Image(systemName: "checkmark")
                    .font(.system(size: 7.5, weight: .heavy))
                    .foregroundStyle(Color.asterionSuccess)
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(Color.black.opacity(0.6)))
                    .overlay(Circle().strokeBorder(Color.asterionSuccess.opacity(0.45)))
                    .accessibilityHidden(true)
            }
        }
        .frame(minWidth: minWidth, alignment: .leading)
    }
}

