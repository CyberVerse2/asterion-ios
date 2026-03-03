import Inject
import SwiftUI

struct NovelDetailView: View {
    @ObserveInjection var inject
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var tabBarState: TabBarState
    @Environment(\.dismiss) private var dismiss
    let novel: Novel

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

    private let previewCount = 5
    private var genreColor: Color { GenreStyle.color(for: novel.genres) }

    private var similarNovels: [Novel] {
        allNovels
            .filter { $0.id != novel.id && $0.genres?.contains(where: { novel.genres?.contains($0) == true }) == true }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                metaStatsSection
                genrePillsSection
                synopsisSection
                startReadingButton
                chapterPreviewSection
                similarNovelsSection
            }
            .padding(.bottom, 100)
        }
        .overlay(alignment: .top) {
            topNavigationBar
        }
        .background(Color.asterionBackground.ignoresSafeArea())
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .task { await loadInitialData() }
        .onAppear { tabBarState.isVisible = false }
        .onDisappear { tabBarState.isVisible = true }
        .edgeSwipeToDismiss { dismiss() }
        .enableInjection()
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack {
            LinearGradient(
                colors: [genreColor.opacity(0.1), Color.asterionBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            MazePatternView()

            VStack(spacing: 0) {
                Spacer().frame(height: 120)

                CoverImageView(novel: novel, size: .lg)
                    .overlay(alignment: .bottomTrailing) {
                        libraryBadge
                            .offset(x: 10, y: 10)
                    }
                    .padding(.bottom, 24)

                Text(novel.title)
                    .font(.asterionSerif(26, weight: .medium))
                    .foregroundStyle(Color.asterionText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 40)

                Text(novel.author ?? "Unknown")
                    .font(.asterionMono(13))
                    .foregroundStyle(Color.asterionMuted)
                    .padding(.top, 8)
            }
            .padding(.bottom, 40)
        }
        .frame(height: 420)
    }

    // MARK: - Metadata Stats

    private var metaStatsSection: some View {
        let items: [(String, String)] = [
            novel.rank.map { ("Rank", "#\($0)") },
            novel.rating.map { ("Rating", "★ \(String(format: "%.1f", $0))") },
            novel.totalChapters.map { ("Chapters", $0) },
            novel.status.map { ("Status", $0) },
            novel.views.map { ("Views", $0) },
        ].compactMap { $0 }

        return HStack(spacing: 28) {
            ForEach(items, id: \.0) { item in
                VStack(spacing: 4) {
                    Text(item.1)
                        .font(.asterionSerif(15, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                    Text(item.0.uppercased())
                        .font(.asterionMono(9))
                        .foregroundStyle(Color.asterionDim)
                        .tracking(2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.asterionCard).frame(height: 1)
        }
    }

    // MARK: - Genre Pills

    @ViewBuilder
    private var genrePillsSection: some View {
        if let genres = novel.genres, !genres.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(genres, id: \.self) { genre in
                        Text(genre)
                            .font(.asterionMono(11))
                            .foregroundStyle(genreColor.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(genreColor.opacity(0.05))
                                    .stroke(genreColor.opacity(0.15), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - Synopsis

    @ViewBuilder
    private var synopsisSection: some View {
        if let summary = novel.summary, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("SYNOPSIS")
                    .font(.asterionMono(10))
                    .foregroundStyle(Color.asterionDim)
                    .tracking(3)

                Text(summary)
                    .font(.asterionSerif(16))
                    .foregroundStyle(Color.asterionSynopsis)
                    .lineSpacing(6)
                    .lineLimit(synopsisExpanded ? nil : 4)

                if summary.count > 200 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            synopsisExpanded.toggle()
                        }
                    } label: {
                        Text(synopsisExpanded ? "Show less" : "Read more")
                            .font(.asterionMono(12))
                            .foregroundStyle(Color.goldAccent)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private var topNavigationBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Text("← Back")
                    .font(.asterionMono(13))
                    .foregroundStyle(Color.asterionMuted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.asterionCard)
                            .stroke(Color.asterionBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                if !isDownloadingAllChapters {
                    Task { await downloadAllChapters() }
                }
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(Color.asterionBorder, lineWidth: 2)
                            .frame(width: 28, height: 28)

                        if isDownloadingAllChapters {
                            Circle()
                                .trim(from: 0, to: downloadProgress)
                                .stroke(
                                    Color.goldAccent,
                                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .frame(width: 28, height: 28)
                        }

                        Image(systemName: downloadIndicatorIconName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(downloadIndicatorColor)
                    }

                    Text(downloadStatusLabel)
                        .font(.asterionMono(11))
                        .foregroundStyle(Color.asterionMuted)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.asterionCard)
                        .stroke(Color.asterionBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isDownloadingAllChapters && downloadTotalCount == 0)
        }
        .padding(.top, 44)
        .padding(.horizontal, 20)
    }

    // MARK: - Start Reading

    @ViewBuilder
    private var libraryBadge: some View {
        if authService.isSignedIn {
            Button {
                Task { await toggleLibrary() }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.asterionCard)
                        .frame(width: 36, height: 36)
                    Circle()
                        .stroke(Color.asterionBorder, lineWidth: 1)
                        .frame(width: 36, height: 36)

                    if libraryActionInFlight {
                        ProgressView()
                            .tint(Color.goldAccent)
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: isInLibrary ? "minus" : "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.goldAccent)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(libraryActionInFlight)
        }
    }

    @ViewBuilder
    private var startReadingButton: some View {
        let targetChapter = continueChapter ?? chapters.first
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
                Text(readingButtonTitle)
                    .font(.asterionSerif(17, weight: .semibold))
                    .foregroundStyle(Color.asterionBackground)
                    .lineLimit(1)
                    .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [genreColor, genreColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .shadow(color: genreColor.opacity(0.3), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private var readingButtonTitle: String {
        guard readingProgress != nil else { return "Start Reading" }
        if let chapterNumber = continueChapter?.chapterNumber, chapterNumber > 0 {
            return "Continue Reading · Ch. \(chapterNumber)"
        }
        return "Continue Reading"
    }

    private var downloadProgress: CGFloat {
        guard downloadTotalCount > 0 else { return 0 }
        return min(1, CGFloat(downloadPreparedCount) / CGFloat(downloadTotalCount))
    }

    private var downloadIndicatorIconName: String {
        if isDownloadingAllChapters { return "arrow.down" }
        if isNovelAvailableOffline { return "checkmark" }
        return "arrow.down.doc"
    }

    private var downloadIndicatorColor: Color {
        isNovelAvailableOffline ? Color(red: 0.353, green: 0.608, blue: 0.478) : Color.goldAccent
    }

    private var downloadStatusLabel: String {
        if isDownloadingAllChapters {
            return "Downloading \(downloadPreparedCount)/\(max(downloadTotalCount, 1))"
        }
        if isNovelAvailableOffline {
            return "Available Offline"
        }
        return "Download All"
    }

    // MARK: - Chapter Preview

    private var chapterPreviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CHAPTERS")
                .font(.asterionMono(10))
                .foregroundStyle(Color.asterionDim)
                .tracking(3)

            if loadingChapters {
                HStack {
                    Spacer()
                    ProgressView().tint(Color.goldAccent)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if let error = chapterError {
                VStack(spacing: 12) {
                    Text(error)
                        .font(.asterionMono(13))
                        .foregroundStyle(Color.asterionMuted)
                    Button("Try Again") {
                        Task { await loadChapters() }
                    }
                    .font(.asterionMono(12))
                    .foregroundStyle(Color.goldAccent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if chapters.isEmpty {
                Text("No chapters available yet")
                    .font(.asterionMono(13))
                    .foregroundStyle(Color.asterionDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    let preview = Array(chapters.prefix(previewCount))
                    ForEach(Array(preview.enumerated()), id: \.element.id) { index, chapter in
                        NavigationLink {
                            ReaderView(
                                initialChapter: chapter,
                                novel: novel,
                                allChapters: chapters
                            )
                        } label: {
                            HStack(spacing: 10) {
                                Text("#\(chapter.chapterNumber)")
                                    .font(.asterionMono(10))
                                    .foregroundStyle(Color.asterionDim)
                                    .frame(width: 36, alignment: .leading)

                                Text(chapter.title)
                                    .font(.asterionSerif(15))
                                    .foregroundStyle(Color.asterionReaderText)
                                    .lineLimit(1)

                                Spacer()

                                Text("›")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.asterionBorder)
                            }
                            .padding(.vertical, 13)
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)

                        if index < preview.count - 1 {
                            Divider().overlay(Color.asterionCard)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.asterionBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))

                NavigationLink {
                    ChaptersView(novel: novel, allChapters: chapters, totalCount: totalChapters)
                } label: {
                    HStack(spacing: 8) {
                        Text("View All Chapters")
                            .font(.asterionMono(13))
                            .foregroundStyle(Color.goldAccent)
                        Text("→")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.goldAccent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.asterionBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    // MARK: - Similar Novels

    @ViewBuilder
    private var similarNovelsSection: some View {
        if !similarNovels.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("YOU'LL LIKE MORE OF THESE")
                    .font(.asterionMono(10))
                    .foregroundStyle(Color.asterionMuted)
                    .tracking(2)
                    .padding(.horizontal, 24)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16),
                    ],
                    spacing: 16
                ) {
                    ForEach(similarNovels, id: \.id) { n in
                        NavigationLink {
                            NovelDetailView(novel: n)
                        } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                CoverImageView(novel: n, size: .tile)
                                    .padding(.bottom, 8)

                                Text(n.title)
                                    .font(.asterionSerif(13, weight: .medium))
                                    .foregroundStyle(Color.asterionText)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)

                                Text(n.author ?? "Unknown")
                                    .font(.asterionMono(10))
                                    .foregroundStyle(Color.asterionMuted)
                                    .padding(.top, 3)

                                if let rating = n.rating {
                                    Text("★ \(String(format: "%.1f", rating))")
                                        .font(.asterionMono(10))
                                        .foregroundStyle(Color.goldAccent)
                                        .padding(.top, 4)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 24)
            .padding(.bottom, 8)
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
            allNovels = try await apiClient.fetchNovels(limit: 100)
            await OfflineChapterStore.shared.saveCatalog(allNovels)
        } catch {
            allNovels = await OfflineChapterStore.shared.loadCatalog()
        }
    }

    private func loadProgress() async {
        do {
            readingProgress = try await apiClient.fetchReadingProgress(novelId: novel.id)
            guard let progress = readingProgress else {
                continueChapter = nil
                return
            }
            continueChapter = try await apiClient.fetchChapter(id: progress.chapterId)
        } catch {
            continueChapter = nil
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
        } catch {
            // Keep the current state when request fails.
        }
    }

    private func downloadAllChapters() async {
        guard !isDownloadingAllChapters else { return }
        isDownloadingAllChapters = true
        downloadError = nil
        downloadPreparedCount = 0
        downloadTotalCount = 0
        defer { isDownloadingAllChapters = false }

        do {
            let chapterList = try await fetchAllChaptersForDownload()
            if chapterList.isEmpty {
                downloadError = "No chapters available to download."
                DownloadLiveActivityManager.shared.end(success: false, completed: 0, total: 1)
                return
            }
            downloadTotalCount = chapterList.count
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

                let chapterHeader: String
                if fullChapter.chapterNumber > 0 {
                    chapterHeader = "Chapter \(fullChapter.chapterNumber): \(fullChapter.title)"
                } else {
                    chapterHeader = fullChapter.title
                }
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
                    content: fileBody
                )
                downloadPreparedCount += 1
                DownloadLiveActivityManager.shared.update(
                    completed: downloadPreparedCount,
                    total: chapterList.count
                )
            }

            isNovelAvailableOffline = true
            DownloadLiveActivityManager.shared.end(
                success: true,
                completed: chapterList.count,
                total: chapterList.count
            )
        } catch {
            downloadError = "Couldn't prepare novel download."
            DownloadLiveActivityManager.shared.end(
                success: false,
                completed: downloadPreparedCount,
                total: max(downloadTotalCount, 1)
            )
        }
    }

    private func fetchAllChaptersForDownload() async throws -> [Chapter] {
        var offset = 0
        let pageSize = 100
        var results: [Chapter] = []

        while true {
            let response = try await apiClient.fetchChapters(novelId: novel.id, limit: pageSize, offset: offset)
            if response.data.isEmpty { break }
            results.append(contentsOf: response.data)

            let total = response.meta?.total ?? response.meta?.count ?? 0
            if total > 0, results.count >= total {
                break
            }
            if response.data.count < pageSize {
                break
            }
            offset += pageSize
        }

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
