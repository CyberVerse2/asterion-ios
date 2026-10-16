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
    @ObservedObject private var downloadStore = NovelDownloadProgressStore.shared
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
    @State private var isInLibrary = false
    @State private var libraryActionInFlight = false
    @State private var isDownloadingAllChapters = false
    @State private var downloadError: String?
    @State private var downloadPreparedCount = 0
    @State private var downloadTotalCount = 0
    @State private var isNovelAvailableOffline = false
    @State private var downloadedChapterIds = Set<String>()
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

    private var similarNovels: [Novel] {
        allNovels
            .filter { $0.id != novel.id && $0.genres?.contains(where: { novel.genres?.contains($0) == true }) == true }
            .prefix(12)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AsterionLayout.sectionSpacing) {
                heroSection
                    .padding(.horizontal, pagePadding)
                    .padding(.top, heroTopPadding)
                chaptersSection
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
        .onAppear { tabBarState.isVisible = false }
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
            chapterCount > 0 ? (chapterCount == 1 ? "1 chapter" : "\(chapterCount.formatted()) chapters") : nil,
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

    private var libraryBadge: some View {
        AsterionCircleIconButton(
            systemName: isInLibrary ? "bookmark.fill" : "bookmark",
            isBusy: libraryActionInFlight,
            accessibilityLabel: isInLibrary ? "Remove from library" : "Save to library"
        ) {
            Task { await toggleLibrary() }
        }
        .disabled(libraryActionInFlight || !networkMonitor.isConnected)
        .opacity(!networkMonitor.isConnected ? 0.55 : 1)
    }

    private var downloadChip: some View {
        Button {
            if !effectiveIsDownloading {
                Task { await downloadAllChapters() }
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
                    Text("\(effectivePreparedCount)/\(effectiveTotalCount) · \(Int((downloadProgress * 100).rounded()))%")
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

    private var persistedDownloadSnapshot: NovelDownloadProgressStore.Snapshot? {
        downloadStore.snapshot(for: novel.id)
    }

    private var effectiveIsDownloading: Bool {
        isDownloadingAllChapters || persistedDownloadSnapshot?.isActive == true
    }

    private var effectivePreparedCount: Int {
        if let snapshot = persistedDownloadSnapshot {
            return snapshot.completed
        }
        return downloadPreparedCount
    }

    private var effectiveTotalCount: Int {
        if let snapshot = persistedDownloadSnapshot {
            return snapshot.total
        }
        return downloadTotalCount
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
                count: chapterCount > 0 ? chapterCount.formatted() : nil
            )
            chapterList
        }
        .padding(.horizontal, pagePadding)
    }

    @ViewBuilder
    private var chapterList: some View {
        if loadingChapters && chapters.isEmpty {
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
        } else if chapters.isEmpty {
            AsterionEmptyState(
                symbol: "text.page",
                title: "No chapters yet",
                message: "This novel hasn’t published any chapters. Check back after its next release."
            )
            .asterionPanel(cornerRadius: 14)
        } else {
            let preview = Array(chapters.prefix(previewCount))
            VStack(spacing: 0) {
                ForEach(Array(preview.enumerated()), id: \.element.id) { index, chapter in
                    if index > 0 {
                        DetailRowDivider()
                    }
                    NavigationLink {
                        ReaderView(
                            initialChapter: chapter,
                            novel: novel,
                            allChapters: chapters,
                            shouldAutoResumeFromSavedProgress: false
                        )
                    } label: {
                        DetailChapterRow(
                            chapter: chapter,
                            isCurrent: readingProgress?.chapterId == chapter.id,
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
                            Text(chapterCount.formatted())
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

    // MARK: - More like this

    @ViewBuilder
    private var moreLikeThisSection: some View {
        if !similarNovels.isEmpty {
            let posterSize = AsterionLayout.shelfPosterSize(horizontalSizeClass)
            VStack(alignment: .leading, spacing: 14) {
                DetailSectionHeader(title: "More like this", count: "\(similarNovels.count)")
                    .padding(.horizontal, pagePadding)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(similarNovels) { similar in
                            NavigationLink {
                                NovelDetailView(novel: similar)
                            } label: {
                                HomePosterCaption(
                                    title: similar.title,
                                    subtitle: similar.author ?? "Unknown author",
                                    width: posterSize.width
                                ) {
                                    NovelPosterArt(novel: similar)
                                        .frame(width: posterSize.width, height: posterSize.height)
                                }
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
        for chapter in chapters.prefix(previewCount) {
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
        async let libraryTask: () = loadLibraryState()
        _ = await (chaptersTask, novelsTask, progressTask, libraryTask)
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

    private func loadAllNovels() async {
        do {
            allNovels = try await apiClient.fetchAllNovels()
            await OfflineChapterStore.shared.saveCatalog(allNovels)
        } catch {
            allNovels = await OfflineChapterStore.shared.loadCatalog()
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

    private func loadLibraryState() async {
        guard authService.isSignedIn else {
            isInLibrary = false
            return
        }
        do {
            let library = try await apiClient.fetchMyLibrary()
            isInLibrary = library.contains(where: { $0.novelId == novel.id })
        } catch {
            isInLibrary = false
        }
    }

    private func toggleLibrary() async {
        guard authService.isSignedIn, !libraryActionInFlight else { return }
        libraryActionInFlight = true
        defer { libraryActionInFlight = false }
        do {
            if isInLibrary {
                _ = try await apiClient.removeNovelFromLibrary(novelId: novel.id)
                isInLibrary = false
                Haptics.tap()
            } else {
                _ = try await apiClient.addNovelToLibrary(novelId: novel.id)
                isInLibrary = true
                Haptics.success()
            }
            NotificationCenter.default.post(name: .asterionSavedNovelsChanged, object: nil)
        } catch {
            // Keep the current state when request fails.
            Haptics.error()
        }
    }

    private func downloadAllChapters() async {
        guard !effectiveIsDownloading else { return }
        isDownloadingAllChapters = true
        downloadError = nil
        downloadPreparedCount = 0
        downloadTotalCount = 0
        defer { isDownloadingAllChapters = false }

        do {
            let chapterList = try await fetchAllChaptersForDownload()
            if chapterList.isEmpty {
                downloadError = "No chapters available to download."
                downloadStore.fail(
                    novelId: novel.id,
                    completed: 0,
                    total: 1,
                    message: "No chapters available to download."
                )
                DownloadLiveActivityManager.shared.end(success: false, completed: 0, total: 1)
                Haptics.error()
                return
            }
            downloadTotalCount = chapterList.count
            downloadStore.start(novelId: novel.id, total: chapterList.count)
            await DownloadLiveActivityManager.shared.start(
                novelTitle: novel.title,
                novelImageURL: novel.imageUrl,
                total: chapterList.count
            )

            for chapter in chapterList {
                let fullChapter: Chapter
                if let cached = await OfflineChapterStore.shared.chapter(id: chapter.id),
                   !(cached.content ?? "").isEmpty
                {
                    fullChapter = cached
                } else if !(chapter.content ?? "").isEmpty {
                    fullChapter = chapter
                } else {
                    do {
                        fullChapter = try await apiClient.fetchChapter(id: chapter.id)
                    } catch {
                        fullChapter = chapter
                    }
                }

                let chapterHeader = fullChapter.labeledTitle
                await OfflineChapterStore.shared.cacheChapter(fullChapter)

                let fileBody = """
                \(novel.title)
                \(chapterHeader)

                \(fullChapter.plainContent)
                """
                _ = try await OfflineChapterStore.shared.saveDownloadedChapter(
                    novelTitle: novel.title,
                    chapterNumber: fullChapter.chapterNumber,
                    chapterTitle: fullChapter.title,
                    content: fileBody,
                    novel: novel,
                    chapter: fullChapter
                )
                downloadPreparedCount += 1
                downloadStore.update(
                    novelId: novel.id,
                    completed: downloadPreparedCount,
                    total: chapterList.count,
                    statusText: "Downloading"
                )
                DownloadLiveActivityManager.shared.update(
                    completed: downloadPreparedCount,
                    total: chapterList.count
                )
            }

            await OfflineChapterStore.shared.flushDownloadedManifests()
            isNovelAvailableOffline = true
            downloadStore.finish(
                novelId: novel.id,
                completed: chapterList.count,
                total: chapterList.count
            )
            DownloadLiveActivityManager.shared.end(
                success: true,
                completed: chapterList.count,
                total: chapterList.count
            )
            Haptics.success()
        } catch {
            await OfflineChapterStore.shared.flushDownloadedManifests()
            downloadError = "Couldn't prepare novel download."
            downloadStore.fail(
                novelId: novel.id,
                completed: downloadPreparedCount,
                total: max(downloadTotalCount, 1),
                message: "Download failed."
            )
            DownloadLiveActivityManager.shared.end(
                success: false,
                completed: downloadPreparedCount,
                total: max(downloadTotalCount, 1)
            )
            Haptics.error()
        }
    }

    private func fetchAllChaptersForDownload() async throws -> [Chapter] {
        let results = try await apiClient.fetchAllChapters(novelId: novel.id)

        if results.isEmpty, !chapters.isEmpty {
            return chapters
        }
        await OfflineChapterStore.shared.saveChapterList(novelId: novel.id, chapters: results, mergeWithExisting: true)
        return results
    }

    private func refreshOfflineAvailability() async {
        let cachedChapterList = await OfflineChapterStore.shared.loadChapterList(novelId: novel.id)
        guard !cachedChapterList.isEmpty else {
            isNovelAvailableOffline = false
            return
        }

        let expectedTotal = totalChapters > 0
            ? totalChapters
            : (Int(novel.totalChapters?.filter(\.isNumber) ?? "") ?? cachedChapterList.count)
        if cachedChapterList.count < max(1, expectedTotal) {
            isNovelAvailableOffline = false
            return
        }

        for chapter in cachedChapterList {
            guard let cached = await OfflineChapterStore.shared.chapter(id: chapter.id),
                  !(cached.content ?? "").isEmpty
            else {
                isNovelAvailableOffline = false
                return
            }
        }
        isNovelAvailableOffline = true
    }
}

@MainActor
private final class NovelDownloadProgressStore: ObservableObject {
    static let shared = NovelDownloadProgressStore()

    struct Snapshot {
        let completed: Int
        let total: Int
        let statusText: String
        let isActive: Bool
    }

    @Published private var state: [String: Snapshot] = [:]

    func snapshot(for novelId: String) -> Snapshot? {
        state[novelId]
    }

    func start(novelId: String, total: Int) {
        state[novelId] = Snapshot(
            completed: 0,
            total: max(total, 1),
            statusText: "Preparing",
            isActive: true
        )
    }

    func update(novelId: String, completed: Int, total: Int, statusText: String) {
        state[novelId] = Snapshot(
            completed: max(0, min(completed, max(total, 1))),
            total: max(total, 1),
            statusText: statusText,
            isActive: true
        )
    }

    func finish(novelId: String, completed: Int, total: Int) {
        state[novelId] = Snapshot(
            completed: max(0, min(completed, max(total, 1))),
            total: max(total, 1),
            statusText: "Completed",
            isActive: false
        )
    }

    func fail(novelId: String, completed: Int, total: Int, message: String) {
        state[novelId] = Snapshot(
            completed: max(0, min(completed, max(total, 1))),
            total: max(total, 1),
            statusText: message,
            isActive: false
        )
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
    let isDownloaded: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(chapter.chapterNumber > 0 ? String(chapter.chapterNumber) : "–")
                .font(.asterionMono(12, weight: .medium))
                .foregroundStyle(isCurrent ? Color.asterionText : Color.asterionFaint)
                .frame(minWidth: 36, alignment: .leading)

            Text(chapter.displayTitle.isEmpty ? chapter.labeledTitle : chapter.displayTitle)
                .font(.asterionReading(14.5, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(Color.asterionText.opacity(isCurrent ? 1 : 0.88))
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
        .accessibilityLabel("Chapter \(chapter.chapterNumber), \(chapter.displayTitle)")
        .accessibilityValue(
            [isCurrent ? "Reading" : nil, isDownloaded ? "Available offline" : nil]
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
