import Inject
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var isExportingNovel = false
    @State private var novelExportDocument: NovelChaptersFolderDocument?
    @State private var novelExportFilename = "novel-chapters"
    @State private var downloadError: String?
    @State private var downloadPreparedCount = 0
    @State private var downloadTotalCount = 0

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
                downloadAllButton
                chapterPreviewSection
                similarNovelsSection
            }
            .padding(.bottom, 100)
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Text("← Back")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.asterionMuted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.asterionCard.opacity(0.5))
                            .stroke(Color.asterionBorder, lineWidth: 1)
                    )
            }
            .padding(.top, 54)
            .padding(.leading, 20)
        }
        .background(Color.asterionBackground.ignoresSafeArea())
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .fileExporter(
            isPresented: $isExportingNovel,
            document: novelExportDocument,
            contentType: .folder,
            defaultFilename: novelExportFilename
        ) { _ in
            novelExportDocument = nil
        }
        .task { await loadInitialData() }
        .onAppear { tabBarState.isVisible = false }
        .onDisappear { tabBarState.isVisible = true }
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
                VStack(spacing: 2) {
                    if readingProgress != nil {
                        Text("Continue Reading · \(continueChapterTitle)")
                            .font(.asterionSerif(16, weight: .semibold))
                            .foregroundStyle(Color.asterionBackground)
                            .lineLimit(1)
                    } else {
                        Text("Start Reading")
                            .font(.asterionSerif(17, weight: .semibold))
                            .foregroundStyle(Color.asterionBackground)
                            .tracking(1)
                    }
                }
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

    private var continueChapterTitle: String {
        guard let continueChapter else { return "Resume where you left off" }
        return continueChapter.chapterNumber > 0
            ? "Ch. \(continueChapter.chapterNumber) · \(continueChapter.title)"
            : continueChapter.title
    }

    @ViewBuilder
    private var downloadAllButton: some View {
        Button {
            Task { await downloadAllChapters() }
        } label: {
            HStack(spacing: 8) {
                if isDownloadingAllChapters {
                    ProgressView()
                        .tint(Color.goldAccent)
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.goldAccent)
                }
                Text(
                    isDownloadingAllChapters
                        ? "Preparing \(downloadPreparedCount)/\(max(downloadTotalCount, 1))..."
                        : "Download All Chapters"
                )
                    .font(.asterionMono(13))
                    .foregroundStyle(Color.goldAccent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.asterionBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDownloadingAllChapters)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)

        if isDownloadingAllChapters, downloadTotalCount > 0 {
            ProgressView(value: Double(downloadPreparedCount), total: Double(downloadTotalCount))
                .tint(Color.goldAccent)
                .padding(.horizontal, 24)
                .padding(.bottom, 6)
        }

        if let downloadError {
            Text(downloadError)
                .font(.asterionMono(11))
                .foregroundStyle(.orange.opacity(0.9))
                .padding(.horizontal, 24)
                .padding(.bottom, 6)
        }
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

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
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
                                .frame(width: 130)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                }
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
            DownloadLiveActivityManager.shared.start(novelTitle: novel.title, total: chapterList.count)

            var chapterFiles: [ChapterExportEntry] = []

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
                chapterFiles.append(
                    ChapterExportEntry(
                        chapterNumber: fullChapter.chapterNumber,
                        title: fullChapter.title,
                        text: fileBody
                    )
                )
                downloadPreparedCount += 1
                DownloadLiveActivityManager.shared.update(
                    completed: downloadPreparedCount,
                    total: chapterList.count
                )
            }

            novelExportDocument = NovelChaptersFolderDocument(
                novelTitle: novel.title,
                chapters: chapterFiles
            )
            novelExportFilename = makeNovelDownloadFilename()
            isExportingNovel = true
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

    private func makeNovelDownloadFilename() -> String {
        let base = "\(novel.title)-chapters"
        let sanitized = base
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitized.isEmpty ? "novel-chapters" : sanitized
    }
}

private struct ChapterExportEntry {
    let chapterNumber: Int
    let title: String
    let text: String
}

private struct NovelChaptersFolderDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }

    let novelTitle: String
    let chapters: [ChapterExportEntry]

    init(novelTitle: String, chapters: [ChapterExportEntry]) {
        self.novelTitle = novelTitle
        self.chapters = chapters
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnknown)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        var children: [String: FileWrapper] = [:]

        for (index, chapter) in chapters.enumerated() {
            let chapterIndex = index + 1
            let numberLabel = chapter.chapterNumber > 0 ? chapter.chapterNumber : chapterIndex
            let rawName = String(
                format: "%04d-ch-%d-%@.txt",
                chapterIndex,
                numberLabel,
                chapter.title
            )
            let fileName = sanitizeFilenameComponent(rawName)
            children[fileName] = FileWrapper(regularFileWithContents: Data(chapter.text.utf8))
        }

        let readme = """
        \(novelTitle)
        Downloaded chapters: \(chapters.count)
        """
        children["README.txt"] = FileWrapper(regularFileWithContents: Data(readme.utf8))
        return FileWrapper(directoryWithFileWrappers: children)
    }

    private func sanitizeFilenameComponent(_ value: String) -> String {
        let sanitized = value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9._-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitized.isEmpty ? UUID().uuidString + ".txt" : sanitized
    }
}
