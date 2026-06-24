import Inject
import SwiftUI

struct HomeView: View {
    @ObserveInjection var inject
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var readingProgressService: ReadingProgressService
    @State private var novels: [Novel] = []
    @State private var loading = false
    @State private var failed = false
    @State private var search = ""
    @State private var debouncedSearch = ""
    @State private var showAll = false
    @State private var continueReadingItems: [ContinueReadingItem] = []
    @State private var continueReadingDestination: ContinueReadingDestination?
    @State private var navigationPath: [Novel] = []

    private let initialCount = 6
    private var isDesktop: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }
    private var contentMaxWidth: CGFloat { isDesktop ? 1460 : .infinity }
    private var pageHorizontalPadding: CGFloat { isDesktop ? 46 : 24 }
    private var browseGridColumns: [GridItem] {
        if isDesktop {
            return [GridItem(.adaptive(minimum: 270, maximum: 340), spacing: 22)]
        }
        return [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
    }

    private var displayNovels: [Novel] {
        if !debouncedSearch.isEmpty || showAll { return novels }
        return Array(novels.prefix(initialCount))
    }

    private struct ContinueReadingItem: Identifiable {
        let novel: Novel
        let chapter: Chapter
        let allChapters: [Chapter]
        let percentage: Double
        var id: String { novel.id }
    }

    private struct ContinueReadingDestination: Identifiable, Hashable {
        let novel: Novel
        let chapter: Chapter
        let allChapters: [Chapter]
        var id: String { "\(novel.id)-\(chapter.id)" }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pageTitleSection
                    searchSection

                    if loading && novels.isEmpty {
                        loadingSection
                    } else if failed && novels.isEmpty {
                        errorSection
                    } else if novels.isEmpty {
                        emptySection
                    } else {
                        contentSection
                    }
                }
                .padding(.bottom, 24)
                .frame(maxWidth: contentMaxWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .refreshable { await loadNovels(search: debouncedSearch) }
            .background {
                Color.asterionBackground.ignoresSafeArea()
                MazePatternView().ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Novel.self) { novel in
                NovelDetailView(novel: novel) {
                    popNovelPath()
                }
            }
            .navigationDestination(item: $continueReadingDestination) { destination in
                ReaderView(
                    initialChapter: destination.chapter,
                    novel: destination.novel,
                    allChapters: destination.allChapters
                )
            }
            .task { await loadNovels() }
            .debounceSearch(text: $search, debouncedText: $debouncedSearch)
            .onChange(of: debouncedSearch) { _, newValue in
                Task { await loadNovels(search: newValue) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .asterionContinueReadingRequested)) { _ in
                Task { await openContinueReadingFromWidget() }
            }
        }
        .enableInjection()
    }

    private func popNovelPath() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
    }

    // MARK: - Search

    private var pageTitleSection: some View {
        Text("Asterion")
            .font(.asterionSerif(isDesktop ? 68 : 48, weight: .semibold))
            .foregroundStyle(Color.asterionText)
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, isDesktop ? 26 : 14)
            .padding(.bottom, isDesktop ? 16 : 8)
    }

    private var searchSection: some View {
        SearchInputView(text: $search, placeholder: "Search novels...")
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.vertical, 8)
    }

    // MARK: - Loading / Error / Empty

    private var loadingSection: some View {
        HStack {
            Spacer()
            ProgressView()
                .tint(Color.goldAccent)
                .scaleEffect(1.2)
                .padding(40)
            Spacer()
        }
    }

    private var errorSection: some View {
        VStack(spacing: 12) {
            Text("⚠")
                .font(.system(size: 32))
                .opacity(0.4)
            Text(failed ? "Couldn't load novels" : "")
                .font(.asterionMono(13))
                .foregroundStyle(Color.asterionMuted)
            Button {
                Task { await loadNovels(search: debouncedSearch) }
            } label: {
                Text("Try Again")
                    .font(.asterionMono(13))
                    .foregroundStyle(Color.goldAccent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .overlay(
                        Capsule().stroke(Color.asterionBorder, lineWidth: 1)
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var emptySection: some View {
        VStack(spacing: 12) {
            Text("📚")
                .font(.system(size: 36))
                .opacity(0.3)
            Text(debouncedSearch.isEmpty ? "No novels found" : "No novels match your search")
                .font(.asterionMono(13))
                .foregroundStyle(Color.asterionDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentSection: some View {
        if debouncedSearch.isEmpty && !continueReadingItems.isEmpty {
            continueReadingSection
        }
        browseGridSection
    }

    // MARK: - Continue Reading

    private var continueReadingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CONTINUE READING")
                .font(.asterionMono(10))
                .foregroundStyle(Color.asterionMuted)
                .tracking(3)

            ForEach(continueReadingItems) { item in
                NavigationLink {
                    ReaderView(
                        initialChapter: item.chapter,
                        novel: item.novel,
                        allChapters: item.allChapters
                    )
                } label: {
                    ContinueReadingCard(
                        novel: item.novel,
                        chapterNum: item.chapter.chapterNumber,
                        chapterTitle: item.chapter.title,
                        percentage: item.percentage
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, pageHorizontalPadding)
        .padding(.vertical, 20)
    }

    // MARK: - Browse Grid

    private var browseGridSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(debouncedSearch.isEmpty ? "BROWSE ALL" : "Results for \"\(debouncedSearch)\"")
                .font(.asterionMono(10))
                .foregroundStyle(Color.asterionMuted)
                .tracking(debouncedSearch.isEmpty ? 3 : 0)

            LazyVGrid(columns: browseGridColumns, spacing: isDesktop ? 22 : 12) {
                ForEach(Array(displayNovels.enumerated()), id: \.element.id) { index, novel in
                    NavigationLink(value: novel) {
                        NovelTileCard(novel: novel)
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.06), value: novels.count)
                }
            }

            if debouncedSearch.isEmpty && !showAll && novels.count > initialCount {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { showAll = true }
                } label: {
                    Text("Show More (\(novels.count - initialCount) more)")
                        .font(.asterionMono(13))
                        .foregroundStyle(Color.asterionMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.asterionCard.opacity(0.25))
                                .stroke(Color.asterionBorder, lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal, pageHorizontalPadding)
        .padding(.vertical, 12)
    }

    // MARK: - Data

    private func loadNovels(search: String = "") async {
        loading = true
        defer { loading = false }
        do {
            novels = try await apiClient.fetchNovels(limit: 50, search: search)
            await OfflineChapterStore.shared.saveCatalog(novels)
            if search.isEmpty {
                await loadContinueReading()
            } else {
                continueReadingItems = []
            }
            failed = false
        } catch {
            let cached = await OfflineChapterStore.shared.loadCatalog()
            if !cached.isEmpty {
                if search.isEmpty {
                    novels = cached
                } else {
                    let q = search.lowercased()
                    novels = cached.filter {
                        $0.title.lowercased().contains(q) || ($0.author?.lowercased().contains(q) ?? false)
                    }
                }
                if search.isEmpty {
                    await loadContinueReading()
                } else {
                    continueReadingItems = []
                }
                failed = false
            } else if novels.isEmpty {
                failed = true
            }
        }
    }

    private func loadContinueReading() async {
        do {
            let progress = try await apiClient.fetchAllReadingProgress()
            continueReadingItems = await buildContinueReadingItems(from: progress)
        } catch {
            let queued = readingProgressService.queuedProgressList()
            continueReadingItems = await buildContinueReadingItems(from: queued)
        }
    }

    private func buildContinueReadingItems(from progress: [ReadingProgress]) async -> [ContinueReadingItem] {
        let novelsById = Dictionary(uniqueKeysWithValues: novels.map { ($0.id, $0) })
        let sortedProgress = progress.sorted {
            ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast)
        }
        var seenNovelIds = Set<String>()
        var orderedEntries: [(novel: Novel, progress: ReadingProgress)] = []
        for p in sortedProgress {
            guard !seenNovelIds.contains(p.novelId), let novel = novelsById[p.novelId] else { continue }
            orderedEntries.append((novel: novel, progress: p))
            seenNovelIds.insert(p.novelId)
        }
        let topEntries = Array(orderedEntries.prefix(2))

        var built: [ContinueReadingItem] = []
        for entry in topEntries {
            let novel = entry.novel
            let p = entry.progress

            let chapter: Chapter?
            if let cached = await OfflineChapterStore.shared.chapter(id: p.chapterId) {
                chapter = cached
            } else {
                do {
                    let fetched = try await apiClient.fetchChapter(id: p.chapterId)
                    await OfflineChapterStore.shared.cacheChapter(fetched)
                    chapter = fetched
                } catch {
                    let listed = await OfflineChapterStore.shared.loadChapterList(novelId: novel.id)
                    chapter = listed.first(where: { $0.id == p.chapterId })
                }
            }
            guard let chapter else { continue }

            let chapterList: [Chapter]
            do {
                let fetchedChapters = try await apiClient.fetchAllChapters(novelId: novel.id)
                await OfflineChapterStore.shared.saveChapterList(
                    novelId: novel.id,
                    chapters: fetchedChapters,
                    mergeWithExisting: true
                )
                chapterList = fetchedChapters
            } catch {
                let cached = await OfflineChapterStore.shared.loadChapterList(novelId: novel.id)
                chapterList = cached.isEmpty ? [chapter] : cached
            }
            let containsCurrent = chapterList.contains(where: { $0.id == chapter.id })
            let allChapters = containsCurrent ? chapterList : ([chapter] + chapterList)

            let totalChapterCount = max(allChapters.count, 1)
            let chapterIndex = Double(max(chapter.chapterNumber - 1, 0))
            let withinChapterFraction = p.percentage / 100.0
            let novelPercentage = min(100, ((chapterIndex + withinChapterFraction) / Double(totalChapterCount)) * 100)

            built.append(
                ContinueReadingItem(
                    novel: novel,
                    chapter: chapter,
                    allChapters: allChapters,
                    percentage: novelPercentage
                )
            )
        }

        return built
    }

    private func openContinueReadingFromWidget() async {
        guard let snapshot = ContinueReadingStore.loadSnapshot() else { return }

        let novel: Novel
        if let existing = novels.first(where: { $0.id == snapshot.novelId }) {
            novel = existing
        } else {
            let cachedNovels = await OfflineChapterStore.shared.loadCatalog()
            if let cached = cachedNovels.first(where: { $0.id == snapshot.novelId }) {
                novel = cached
            } else if let fetched = try? await apiClient.fetchNovel(id: snapshot.novelId) {
                novel = fetched
            } else {
                return
            }
        }

        let chapter: Chapter
        if let cachedChapter = await OfflineChapterStore.shared.chapter(id: snapshot.chapterId) {
            chapter = cachedChapter
        } else if let fetchedChapter = try? await apiClient.fetchChapter(id: snapshot.chapterId) {
            chapter = fetchedChapter
            await OfflineChapterStore.shared.cacheChapter(fetchedChapter)
        } else {
            return
        }

        let chapterList: [Chapter]
        let cachedList = await OfflineChapterStore.shared.loadChapterList(novelId: novel.id)
        if !cachedList.isEmpty {
            chapterList = cachedList
        } else if let fetchedChapters = try? await apiClient.fetchAllChapters(novelId: novel.id) {
            await OfflineChapterStore.shared.saveChapterList(
                novelId: novel.id,
                chapters: fetchedChapters,
                mergeWithExisting: true
            )
            chapterList = fetchedChapters
        } else {
            chapterList = [chapter]
        }

        let allChapters = chapterList.contains(where: { $0.id == chapter.id }) ? chapterList : ([chapter] + chapterList)
        continueReadingDestination = nil
        continueReadingDestination = ContinueReadingDestination(
            novel: novel,
            chapter: chapter,
            allChapters: allChapters
        )
    }
}

// MARK: - Continue Reading Card

private struct ContinueReadingCard: View {
    let novel: Novel
    let chapterNum: Int
    let chapterTitle: String
    let percentage: Double

    private var color: Color { GenreStyle.color(for: novel.genres) }

    private var pct: Double { min(100, max(0, percentage)) }

    var body: some View {
        HStack(spacing: 14) {
            CoverImageView(novel: novel, size: .md)

            VStack(alignment: .leading, spacing: 3) {
                Text(novel.title)
                    .font(.asterionSerif(17, weight: .medium))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(1)

                if chapterNum > 0 {
                    Text("Ch. \(chapterNum) · \(chapterTitle)")
                        .font(.asterionMono(11))
                        .foregroundStyle(Color.asterionDim)
                } else {
                    Text(chapterTitle)
                        .font(.asterionMono(11))
                        .foregroundStyle(Color.asterionDim)
                }

                HStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.asterionBorder)

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [color, color.opacity(0.65)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * pct / 100)
                        }
                    }
                    .frame(height: 3)

                    Text("\(Int(pct))%")
                        .font(.asterionMono(10))
                        .foregroundStyle(Color.asterionDim)
                        .fixedSize()
                }
                .padding(.top, 7)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color.asterionCard, Color.asterionCardHover],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .stroke(Color.asterionBorder, lineWidth: 1)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0), color, color.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
                .opacity(0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Novel Tile Card

private struct NovelTileCard: View {
    let novel: Novel
    private var isDesktop: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isDesktop ? 8 : 4) {
            if let rank = novel.rank {
                HStack {
                    Spacer()
                    Text("#\(rank)")
                        .font(.asterionMono(isDesktop ? 12 : 9))
                        .foregroundStyle(Color.asterionDim)
                }
            }

            CoverImageView(novel: novel, size: isDesktop ? .desktopTile : .tile)
                .padding(.bottom, isDesktop ? 12 : 8)

            Text(novel.title)
                .font(.asterionSerif(isDesktop ? 22 : 15, weight: .medium))
                .foregroundStyle(Color.asterionText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(novel.author ?? "Unknown")
                .font(.asterionMono(isDesktop ? 13 : 11))
                .foregroundStyle(Color.asterionMuted)
                .lineLimit(1)

            HStack(spacing: 6) {
                if let rating = novel.rating {
                    Text("★ \(String(format: "%.1f", rating))")
                        .font(.asterionMono(isDesktop ? 12 : 10))
                        .foregroundStyle(Color.goldAccent)
                }
                if let status = novel.status {
                    StatusPill(status: status)
                }
            }
            .padding(.top, 4)

            if let chapters = novel.totalChapters {
                Text("\(chapters) chapters")
                    .font(.asterionMono(isDesktop ? 11 : 9))
                    .foregroundStyle(Color.asterionBorderHover)
                    .padding(.top, 2)
            }
        }
        .padding(isDesktop ? 24 : 16)
        .frame(minHeight: isDesktop ? 270 : nil, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.asterionCard)
                .stroke(Color.asterionBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Status Pill

struct StatusPill: View {
    let status: String

    private var pillColor: Color {
        switch status.uppercased() {
        case "ONGOING":   return Color(red: 0.353, green: 0.608, blue: 0.478)
        case "COMPLETED": return Color(red: 0.545, green: 0.482, blue: 0.42)
        case "HIATUS":    return .orange
        default:          return Color.asterionDim
        }
    }

    var body: some View {
        Text(status)
            .font(.asterionMono(9))
            .foregroundStyle(pillColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .overlay(
                Capsule().stroke(pillColor.opacity(0.4), lineWidth: 1)
            )
    }
}
