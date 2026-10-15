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
    @State private var detailShelf: DetailShelf = .chapters
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private enum DetailShelf: String, CaseIterable {
        case chapters = "Chapters"
        case moreLikeThis = "More like this"
    }

    private let previewCount = 5
    private var genreColor: Color { GenreStyle.color(for: novel.genres) }
    private var isDesktop: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }
    private var topBarTopPadding: CGFloat { isDesktop ? 18 : 44 }

    private var similarNovels: [Novel] {
        allNovels
            .filter { $0.id != novel.id && $0.genres?.contains(where: { novel.genres?.contains($0) == true }) == true }
            .prefix(12)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            if isDesktop {
                desktopContent
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    heroSection
                    metaStatsSection
                    startReadingButton
                    synopsisSection
                    detailShelfSection
                }
                .padding(.bottom, 100)
                .background(alignment: .top) {
                    AsterionCoverBleed(url: novel.imageUrl.flatMap(URL.init(string:)))
                }
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

    private var desktopContent: some View {
        HStack(alignment: .top, spacing: 36) {
            desktopBookPanel
                .frame(width: 320)

            VStack(alignment: .leading, spacing: 0) {
                metaStatsSection
                genrePillsSection
                synopsisSection
                startReadingButton
                detailShelfSection
            }
            .frame(maxWidth: 720, alignment: .topLeading)
        }
        .padding(.top, 82)
        .padding(.horizontal, 36)
        .padding(.bottom, 80)
        .frame(maxWidth: 1180)
        .frame(maxWidth: .infinity)
    }

    private var desktopBookPanel: some View {
        VStack(spacing: 18) {
            CoverImageView(novel: novel, size: .lg)
                .scaleEffect(1.08)
                .padding(.bottom, 6)

            Text(novel.title)
                .font(.asterionSerif(30, weight: .medium))
                .foregroundStyle(Color.asterionText)
                .multilineTextAlignment(.center)
                .lineLimit(4)

            Text(novel.author ?? "Unknown")
                .font(.asterionMono(13))
                .foregroundStyle(Color.asterionMuted)
        }
        .padding(.top, 28)
        .padding(.horizontal, 28)
        .padding(.bottom, 30)
        .asterionGlassSurface(cornerRadius: 18)
    }

    // MARK: - Hero

    private var heroSection: some View {
        AsterionDetailHero(
            title: novel.title,
            subtitle: novel.author ?? "Unknown"
        ) {
            NovelPosterArt(novel: novel)
                .frame(width: 132, height: 198)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    // MARK: - Metadata Stats

    private var metaStatsSection: some View {
        let items: [AsterionDetailStat] = [
            novel.rank.map { AsterionDetailStat(label: "Rank", value: "#\($0)") },
            novel.rating.map { AsterionDetailStat(label: "Rating", value: String(format: "%.1f", $0)) },
            novel.totalChapters.map { AsterionDetailStat(label: "Chapters", value: $0) },
            novel.status.map { AsterionDetailStat(label: "Status", value: $0) },
        ].compactMap { $0 }

        return AsterionDetailStatsRow(items: items)
    }

    // MARK: - Genre Pills

    @ViewBuilder
    private var genrePillsSection: some View {
        if let genres = novel.genres, !genres.isEmpty {
            AsterionChipRow(chips: genres, tint: genreColor)
        }
    }

    // MARK: - Synopsis

    @ViewBuilder
    private var synopsisSection: some View {
        if let summary = novel.summary, !summary.isEmpty {
            AsterionSynopsisBlock(text: summary, genres: novel.genres ?? [], expanded: $synopsisExpanded)
        }
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
                        .trim(from: 0, to: downloadProgress)
                        .stroke(
                            Color.asterionInk,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 40, height: 40)
                }

                Image(systemName: downloadIndicatorIconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(downloadIndicatorColor)
            }
            .frame(width: 48, height: 48)
            .background(Color.asterionCard, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(downloadStatusLabel)
        .disabled((effectiveIsDownloading && effectiveTotalCount == 0) || (!networkMonitor.isConnected && !effectiveIsDownloading))
        .opacity(!networkMonitor.isConnected && !effectiveIsDownloading ? 0.55 : 1)
    }

    private func performBack() {
        if let onBack {
            onBack()
        } else {
            dismiss()
        }
    }

    // MARK: - Start Reading

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

    @ViewBuilder
    private var startReadingButton: some View {
        let targetChapter = continueChapter ?? chapters.first
        HStack(spacing: 10) {
            if let targetChapter {
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
                        allChapters: chapterListForReader
                    )
                } label: {
                    AsterionPrimaryActionLabel(title: readingButtonTitle)
                }
                .buttonStyle(.plain)
            }

            libraryBadge
            downloadChip
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var readingButtonTitle: String {
        guard readingProgress != nil else { return "Start Reading" }
        if let chapterNumber = continueChapter?.chapterNumber, chapterNumber > 0 {
            return "Continue Reading · Ch. \(chapterNumber)"
        }
        return "Continue Reading"
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
        isNovelAvailableOffline ? Color(red: 0.353, green: 0.608, blue: 0.478) : Color.goldAccent
    }

    private var downloadStatusLabel: String {
        if effectiveIsDownloading {
            return "Downloading \(effectivePreparedCount)/\(max(effectiveTotalCount, 1))"
        }
        if isNovelAvailableOffline {
            return "Available Offline"
        }
        return "Download All"
    }

    // MARK: - Chapters / More like this

    private var detailShelfSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AsterionIndexTabs(
                items: DetailShelf.allCases,
                title: { $0.rawValue },
                rank: .section,
                selection: $detailShelf
            )

            switch detailShelf {
            case .chapters:
                chapterList
            case .moreLikeThis:
                moreLikeThisGrid
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var chapterList: some View {
        if loadingChapters {
            ProgressView()
                .tint(Color.asterionInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if let error = chapterError {
            VStack(spacing: 10) {
                Text(error)
                    .font(.asterionReading(14))
                    .foregroundStyle(Color.asterionMuted)
                Button("Try again") { Task { await loadChapters() } }
                    .font(.asterionReading(15, weight: .medium))
                    .foregroundStyle(Color.asterionInk)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        } else if chapters.isEmpty {
            Text("No chapters yet")
                .font(.asterionReading(15))
                .foregroundStyle(Color.asterionMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        } else {
            VStack(spacing: 0) {
                let preview = Array(chapters.prefix(previewCount))
                ForEach(Array(preview.enumerated()), id: \.element.id) { index, chapter in
                    NavigationLink {
                        ReaderView(
                            initialChapter: chapter,
                            novel: novel,
                            allChapters: chapters,
                            shouldAutoResumeFromSavedProgress: false
                        )
                    } label: {
                        AsterionUnitRow(
                            index: "#\(chapter.chapterNumber)",
                            title: chapter.displayTitle
                        )
                    }
                    .buttonStyle(.plain)

                    if index < preview.count - 1 {
                        Divider().overlay(Color.asterionBorder)
                    }
                }
            }
            .padding(.horizontal, 24)

            NavigationLink {
                ChaptersView(novel: novel, allChapters: chapters, totalCount: totalChapters)
            } label: {
                Text("View all chapters")
                    .font(.asterionReading(14, weight: .medium))
                    .foregroundStyle(Color.asterionInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.asterionCard, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var moreLikeThisGrid: some View {
        if similarNovels.isEmpty {
            Text("Nothing similar yet")
                .font(.asterionReading(15))
                .foregroundStyle(Color.asterionMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        } else {
            LazyVGrid(
                columns: AsterionLayout.posterColumns(horizontalSizeClass),
                spacing: 14
            ) {
                ForEach(similarNovels) { similar in
                    NavigationLink {
                        NovelDetailView(novel: similar)
                    } label: {
                        NovelTileCard(novel: similar)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
        }
    }

    // MARK: - Data

    private func loadInitialData() async {
        async let chaptersTask: () = loadChapters()
        async let novelsTask: () = loadAllNovels()
        async let progressTask: () = loadProgress()
        async let libraryTask: () = loadLibraryState()
        _ = await (chaptersTask, novelsTask, progressTask, libraryTask)
        await refreshOfflineAvailability()
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
                ?? Int(novel.totalChapters?.filter(\.isNumber) ?? "")
                ?? response.data.count
        } catch {
            let cached = await OfflineChapterStore.shared.loadChapterList(novelId: novel.id)
            if !cached.isEmpty {
                chapters = Array(cached.prefix(previewCount))
                totalChapters = cached.count
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
            } else {
                _ = try await apiClient.addNovelToLibrary(novelId: novel.id)
                isInLibrary = true
            }
            NotificationCenter.default.post(name: .asterionSavedNovelsChanged, object: nil)
        } catch {
            // Keep the current state when request fails.
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
        } catch {
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
