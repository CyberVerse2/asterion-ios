import Inject
import SwiftUI
import WidgetKit

struct ReaderView: View {
    @ObserveInjection var inject
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var readingProgressService: ReadingProgressService
    @EnvironmentObject private var tabBarState: TabBarState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let initialChapter: Chapter
    let novel: Novel
    let allChapters: [Chapter]
    let shouldAutoResumeFromSavedProgress: Bool

    @State private var currentChapter: Chapter
    @State private var showControls = true
    @State private var fontSize: CGFloat = 19
    @State private var controlTimer: Task<Void, Never>?
    @State private var loadingChapter = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var currentLine = 0
    @State private var paragraphOffsets: [Int: CGFloat] = [:]
    @State private var pendingRestoreLine: Int?
    @State private var progressSyncTask: Task<Void, Never>?
    @State private var liveActivityUpdateTask: Task<Void, Never>?
    @State private var showDownloadAlert = false
    @State private var downloadAlertMessage = ""
    @State private var isCurrentChapterDownloaded = false

    private var genreColor: Color { GenreStyle.color(for: novel.genres) }
    private var isDesktop: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    private var navigationChapters: [Chapter] {
        var merged: [Chapter] = []
        var seen = Set<String>()
        for chapter in ([currentChapter] + allChapters) where !seen.contains(chapter.id) {
            merged.append(chapter)
            seen.insert(chapter.id)
        }
        return merged.sorted { lhs, rhs in
            if lhs.chapterNumber == rhs.chapterNumber {
                return lhs.id < rhs.id
            }
            return lhs.chapterNumber < rhs.chapterNumber
        }
    }

    private var totalChapterCountHint: Int? {
        Int(novel.totalChapters?.filter(\.isNumber) ?? "")
    }

    private var shouldShowPrevButton: Bool {
        if currentChapter.chapterNumber > 0 {
            return currentChapter.chapterNumber > 1
        }
        return hasPrev
    }

    private var canNavigatePrev: Bool {
        if currentChapter.chapterNumber > 1 { return true }
        return hasPrev
    }

    private var canNavigateNext: Bool {
        if let totalChapterCountHint, currentChapter.chapterNumber > 0 {
            return currentChapter.chapterNumber < totalChapterCountHint
        }
        return hasNext || currentChapter.chapterNumber > 0
    }

    private var currentIndex: Int {
        navigationChapters.firstIndex(where: { $0.id == currentChapter.id }) ?? -1
    }
    private var hasPrev: Bool { currentIndex > 0 }
    private var hasNext: Bool { currentIndex >= 0 && currentIndex < navigationChapters.count - 1 }
    private var isLargeIPadLayout: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
        #endif
    }
    private var readerHorizontalPadding: CGFloat {
        if isDesktop { return 40 }
        if horizontalSizeClass == .compact { return 20 }
        return isLargeIPadLayout ? 24 : 32
    }
    private var readerMaxContentWidth: CGFloat {
        if isDesktop { return 780 }
        if isLargeIPadLayout { return 1120 }
        return 640
    }
    private var topBarTitleMaxWidth: CGFloat {
        if isDesktop { return 420 }
        return isLargeIPadLayout ? 360 : 160
    }
    private var topBarHorizontalPadding: CGFloat {
        if isDesktop { return 28 }
        return isLargeIPadLayout ? 20 : 20
    }
    private var topBarTopPadding: CGFloat { isDesktop ? 18 : 40 }
    private var bottomBarBottomPadding: CGFloat { isDesktop ? 22 : 34 }

    private var paragraphs: [String] {
        currentChapter.plainContent
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }
            .filter { !$0.isEmpty }
            .filter { !shouldFilterMetadataLine($0) }
    }

    init(
        initialChapter: Chapter,
        novel: Novel,
        allChapters: [Chapter],
        shouldAutoResumeFromSavedProgress: Bool = true
    ) {
        self.initialChapter = initialChapter
        self.novel = novel
        self.allChapters = allChapters
        self.shouldAutoResumeFromSavedProgress = shouldAutoResumeFromSavedProgress
        self._currentChapter = State(initialValue: initialChapter)
        #if targetEnvironment(macCatalyst)
        self._fontSize = State(initialValue: 20)
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            self._fontSize = State(initialValue: 21)
        }
        #endif
    }

    var body: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        chapterHeading
                            .id("top")
                        chapterContent
                        endOfChapterNav
                    }
                }
                .coordinateSpace(name: "readerScroll")
                .onAppear { scrollProxy = proxy }
                .onPreferenceChange(ParagraphOffsetPreferenceKey.self) { offsets in
                    paragraphOffsets = offsets
                    guard !offsets.isEmpty else { return }
                    updateCurrentLineFromOffsets(offsets)
                }
                .simultaneousGesture(
                    TapGesture().onEnded { toggleControls() }
                )
                .overlay(alignment: .top) {
                    topControlBar
                }
                .overlay(alignment: .bottom) {
                    bottomControlBar
                }
            }

            if loadingChapter {
                Color.asterionBackground.opacity(0.85).ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView().tint(Color.goldAccent)
                    Text("Loading chapter...")
                        .font(.asterionMono(12))
                        .foregroundStyle(Color.asterionDim)
                }
            }
        }
        .background(Color.asterionBackground.ignoresSafeArea())
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .statusBarHidden(isDesktop ? false : !showControls)
        .onAppear {
            tabBarState.isVisible = false
            if !isDesktop { scheduleHideControls() }
            Task { await restoreProgressAndLoadChapter() }
            Task { await refreshCurrentChapterDownloadState() }
            Task { await updateReadingLiveActivity() }
        }
        .onDisappear { tabBarState.isVisible = true }
        .onDisappear {
            progressSyncTask?.cancel()
            liveActivityUpdateTask?.cancel()
            Task { await ReadingLiveActivityManager.shared.end() }
            syncReadingPosition(reloadWidget: true)
        }
        .alert("Chapter Download", isPresented: $showDownloadAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloadAlertMessage)
        }
        .edgeSwipeToDismiss { dismiss() }
        .onChange(of: currentChapter.id) { _, _ in
            currentLine = 0
            withAnimation {
                scrollProxy?.scrollTo("top", anchor: .top)
            }
            Task { await refreshCurrentChapterDownloadState() }
            scheduleReadingLiveActivityUpdate()
        }
        .enableInjection()
    }

    // MARK: - Chapter Heading

    private var chapterHeading: some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 80)

            if currentChapter.chapterNumber > 0 {
                Text("CHAPTER \(currentChapter.chapterNumber)")
                    .font(.asterionMono(10))
                    .foregroundStyle(Color.asterionBorderHover)
                    .tracking(4)
            }

            Text(currentChapter.title)
                .font(.asterionSerif(22, weight: .light))
                .foregroundStyle(Color.asterionMuted)
                .italic()
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Rectangle()
                .fill(Color.asterionBorder)
                .frame(width: 40, height: 1)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, readerHorizontalPadding)
        .padding(.bottom, 10)
    }

    // MARK: - Chapter Content

    private var chapterContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, para in
                Text(para)
                    .id(lineAnchorId(for: index))
                    .font(.asterionSerif(fontSize))
                    .lineSpacing(fontSize * (isLargeIPadLayout ? 0.95 : 0.85))
                    .foregroundStyle(Color.asterionReaderText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, index > 0 ? readerHorizontalPadding : 0)
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ParagraphOffsetPreferenceKey.self,
                                value: [index: geo.frame(in: .named("readerScroll")).minY]
                            )
                        }
                    }
            }
        }
        .padding(.horizontal, readerHorizontalPadding)
        .padding(.bottom, 140)
        .frame(maxWidth: readerMaxContentWidth)
        .frame(maxWidth: .infinity)
    }

    // MARK: - End of Chapter Nav

    private var endOfChapterNav: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.asterionCard).frame(height: 1)
                .padding(.horizontal, readerHorizontalPadding)

            HStack(spacing: 16) {
                if shouldShowPrevButton {
                    Button {
                        navigateChapter(direction: -1)
                    } label: {
                        Text("← Previous")
                            .font(.asterionSerif(14))
                            .foregroundStyle(canNavigatePrev ? Color.asterionMuted : Color.asterionBorder)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.asterionCard)
                                    .stroke(Color.asterionBorder, lineWidth: 1)
                            )
                    }
                    .disabled(!canNavigatePrev)
                }

                Button {
                    navigateChapter(direction: 1)
                } label: {
                    Text("Next Chapter →")
                        .font(.asterionSerif(14))
                        .foregroundStyle(canNavigateNext ? Color.goldAccent : Color.asterionBorder)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.asterionCard)
                                .stroke(
                                    canNavigateNext ? genreColor.opacity(0.3) : Color.asterionBorder,
                                    lineWidth: 1
                                )
                        )
                }
                .disabled(!canNavigateNext)
            }
            .padding(.vertical, 40)
        }
        .padding(.bottom, 20)
    }

    // MARK: - Top Control Bar

    private var topControlBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("← Back")
                    .font(.asterionMono(13))
                    .foregroundStyle(Color.asterionMuted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .overlay(
                        Capsule().stroke(Color.asterionBorder, lineWidth: 1)
                    )
            }

            Spacer()

            Text(novel.title)
                .font(.asterionMono(11))
                .foregroundStyle(Color.asterionDim)
                .lineLimit(1)
                .frame(maxWidth: topBarTitleMaxWidth)

            Spacer()

            HStack(spacing: 8) {
                Button {
                    Task { await downloadCurrentChapterToFolder() }
                } label: {
                    Image(systemName: isCurrentChapterDownloaded ? "checkmark.circle.fill" : "arrow.down.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(
                            isCurrentChapterDownloaded
                                ? Color(red: 0.353, green: 0.608, blue: 0.478)
                                : Color.asterionMuted
                        )
                        .frame(width: 32, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.asterionBorder, lineWidth: 1)
                        )
                }
                Button { fontSize = max(14, fontSize - 1) } label: {
                    Text("A-")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.asterionMuted)
                        .frame(width: 32, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.asterionBorder, lineWidth: 1)
                        )
                }
                Button { fontSize = min(28, fontSize + 1) } label: {
                    Text("A+")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.asterionMuted)
                        .frame(width: 32, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.asterionBorder, lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal, topBarHorizontalPadding)
        .padding(.top, topBarTopPadding)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [Color.asterionBackground, Color.asterionBackground, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .opacity(showControls ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: showControls)
        .allowsHitTesting(showControls)
    }

    // MARK: - Bottom Control Bar

    private var bottomControlBar: some View {
        HStack(spacing: 24) {
            if shouldShowPrevButton {
                Button { navigateChapter(direction: -1) } label: {
                    Text("◂ Prev")
                        .font(.asterionMono(12))
                        .foregroundStyle(canNavigatePrev ? Color.asterionMuted : Color.asterionBorder)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.asterionCard)
                                .stroke(Color.asterionBorder, lineWidth: 1)
                        )
                }
                .disabled(!canNavigatePrev)
            }
            Button { navigateChapter(direction: 1) } label: {
                Text("Next ▸")
                    .font(.asterionMono(12))
                    .foregroundStyle(canNavigateNext ? Color.goldAccent : Color.asterionBorder)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.asterionCard)
                            .stroke(
                                canNavigateNext ? genreColor.opacity(0.5) : Color.asterionBorder,
                                lineWidth: 1
                            )
                    )
            }
            .disabled(!canNavigateNext)
        }
        .padding(.bottom, bottomBarBottomPadding)
        .padding(.top, 16)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.clear, Color.asterionBackground, Color.asterionBackground],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .opacity(showControls ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: showControls)
        .allowsHitTesting(showControls)
    }

    // MARK: - Actions

    private func toggleControls() {
        guard !isDesktop else { return }
        showControls.toggle()
        if showControls { scheduleHideControls() }
    }

    private func scheduleHideControls() {
        guard !isDesktop else { return }
        controlTimer?.cancel()
        controlTimer = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            withAnimation { showControls = false }
        }
    }

    private func navigateChapter(direction: Int) {
        loadingChapter = true
        Task {
            defer { loadingChapter = false }

            let target: Chapter?
            let nextIdx = currentIndex + direction
            if nextIdx >= 0 && nextIdx < navigationChapters.count {
                target = navigationChapters[nextIdx]
            } else {
                target = await fetchAdjacentChapterFallback(direction: direction)
            }

            guard let target else { return }

            do {
                let full = try await apiClient.fetchChapter(id: target.id)
                currentChapter = full
                await OfflineChapterStore.shared.cacheChapter(full)
            } catch {
                if let cached = await OfflineChapterStore.shared.chapter(id: target.id) {
                    currentChapter = cached
                } else {
                    currentChapter = target
                }
            }
            syncReadingPosition()
            scheduleHideControls()
        }
    }

    private func fetchAdjacentChapterFallback(direction: Int) async -> Chapter? {
        guard currentChapter.chapterNumber > 0 else { return nil }
        let targetNumber = currentChapter.chapterNumber + direction
        guard targetNumber > 0 else { return nil }

        if let totalChapterCountHint, targetNumber > totalChapterCountHint {
            return nil
        }

        do {
            // API is offset-based and chapter order is ascending.
            let response = try await apiClient.fetchChapters(
                novelId: novel.id,
                limit: 1,
                offset: max(0, targetNumber - 1)
            )
            if let chapter = response.data.first {
                await OfflineChapterStore.shared.saveChapterList(
                    novelId: novel.id,
                    chapters: response.data,
                    mergeWithExisting: true
                )
                return chapter
            }
        } catch {
            // Fall through to offline cache fallback.
        }

        let cached = await OfflineChapterStore.shared.loadChapterList(novelId: novel.id)
        return cached.first(where: { $0.chapterNumber == targetNumber })
    }

    private func loadInitialChapter() async {
        loadingChapter = true
        defer { loadingChapter = false }
        do {
            currentChapter = try await apiClient.fetchChapter(id: currentChapter.id)
            await OfflineChapterStore.shared.cacheChapter(currentChapter)
            syncReadingPosition()
        } catch {
            if let cached = await OfflineChapterStore.shared.chapter(id: currentChapter.id) {
                currentChapter = cached
            }
            syncReadingPosition()
        }
    }

    private func restoreProgressAndLoadChapter() async {
        if shouldAutoResumeFromSavedProgress {
            await readingProgressService.refreshRemoteProgress(novelId: novel.id)
            let bestProgress = readingProgressService.currentProgress?.novelId == novel.id
                ? readingProgressService.currentProgress
                : readingProgressService.queuedProgress(for: novel.id)

            if let bestProgress {
                if let savedChapter = navigationChapters.first(where: { $0.id == bestProgress.chapterId }) {
                    currentChapter = savedChapter
                    pendingRestoreLine = bestProgress.currentLine
                    currentLine = bestProgress.currentLine
                } else if let cachedChapter = await OfflineChapterStore.shared.chapter(id: bestProgress.chapterId) {
                    currentChapter = cachedChapter
                    pendingRestoreLine = bestProgress.currentLine
                    currentLine = bestProgress.currentLine
                } else {
                    do {
                        let fetched = try await apiClient.fetchChapter(id: bestProgress.chapterId)
                        currentChapter = fetched
                        pendingRestoreLine = bestProgress.currentLine
                        currentLine = bestProgress.currentLine
                        await OfflineChapterStore.shared.cacheChapter(fetched)
                    } catch {
                        // Keep initial chapter when saved chapter cannot be loaded.
                    }
                }
            }
        }
        await loadInitialChapter()
        await MainActor.run {
            restoreScrollPositionIfNeeded()
        }
    }

    private func updateCurrentLineFromOffsets(_ offsets: [Int: CGFloat]) {
        // Use a stable target below the top controls for better perceived resume accuracy.
        let targetY: CGFloat = 120
        guard let best = offsets.min(by: { abs($0.value - targetY) < abs($1.value - targetY) }) else {
            return
        }
        let clamped = max(0, min(best.key, max(0, paragraphs.count - 1)))
        guard clamped != currentLine else { return }
        currentLine = clamped
        scheduleProgressSync()
        scheduleReadingLiveActivityUpdate()
    }

    private func scheduleProgressSync() {
        progressSyncTask?.cancel()
        progressSyncTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            syncReadingPosition()
        }
    }

    private func scheduleReadingLiveActivityUpdate() {
        liveActivityUpdateTask?.cancel()
        liveActivityUpdateTask = Task {
            try? await Task.sleep(for: .seconds(0.75))
            guard !Task.isCancelled else { return }
            await updateReadingLiveActivity()
        }
    }

    private func updateReadingLiveActivity() async {
        await ReadingLiveActivityManager.shared.startOrUpdate(
            novelTitle: novel.title,
            chapterTitle: currentChapter.title,
            currentLine: currentLine,
            totalLines: max(1, paragraphs.count)
        )
    }

    private func syncReadingPosition(reloadWidget: Bool = false) {
        let totalLines = max(1, paragraphs.count)
        let percentage = totalLines > 0 ? min(1, Double(currentLine) / Double(totalLines)) : 0

        readingProgressService.updateProgress(
            novelId: novel.id,
            chapterId: currentChapter.id,
            currentLine: currentLine,
            totalLines: totalLines
        )

        ContinueReadingStore.saveSnapshot(
            ContinueReadingSnapshot(
                novelId: novel.id,
                novelTitle: novel.title,
                chapterId: currentChapter.id,
                chapterTitle: currentChapter.title,
                chapterNumber: currentChapter.chapterNumber,
                progress: percentage,
                updatedAt: Date()
            )
        )

        if reloadWidget {
            WidgetCenter.shared.reloadTimelines(ofKind: "ReadingWidget")
        }
    }

    private func restoreScrollPositionIfNeeded() {
        guard let pendingRestoreLine else { return }
        let targetLine = max(0, min(pendingRestoreLine, max(0, paragraphs.count - 1)))
        currentLine = targetLine
        withAnimation(.easeOut(duration: 0.25)) {
            scrollProxy?.scrollTo(lineAnchorId(for: targetLine), anchor: .top)
        }
        self.pendingRestoreLine = nil
    }

    private func lineAnchorId(for index: Int) -> String {
        "line-\(index)"
    }

    private func downloadCurrentChapterToFolder() async {
        let chapterHeader: String
        if currentChapter.chapterNumber > 0 {
            chapterHeader = "Chapter \(currentChapter.chapterNumber): \(currentChapter.title)"
        } else {
            chapterHeader = currentChapter.title
        }
        let body = paragraphs.joined(separator: "\n\n")
        let content = """
        \(novel.title)
        \(chapterHeader)

        \(body)
        """
        do {
            await OfflineChapterStore.shared.cacheChapter(currentChapter)
            let fileURL = try await OfflineChapterStore.shared.saveDownloadedChapter(
                novelTitle: novel.title,
                chapterNumber: currentChapter.chapterNumber,
                chapterTitle: currentChapter.title,
                content: content
            )
            isCurrentChapterDownloaded = true
            downloadAlertMessage = "Saved to \(fileURL.deletingLastPathComponent().lastPathComponent)"
            showDownloadAlert = true
        } catch {
            downloadAlertMessage = "Couldn't save chapter to local folder."
            showDownloadAlert = true
        }
    }

    private func refreshCurrentChapterDownloadState() async {
        isCurrentChapterDownloaded = await OfflineChapterStore.shared.isChapterDownloaded(
            novelTitle: novel.title,
            chapterNumber: currentChapter.chapterNumber,
            chapterTitle: currentChapter.title
        )
    }

    private func shouldFilterMetadataLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        let compact = lowered.replacingOccurrences(of: " ", with: "")

        let hasPromoKeyword =
            lowered.contains("discord") ||
            lowered.contains("patreon") ||
            lowered.contains("ko-fi") ||
            lowered.contains("kofi") ||
            lowered.contains("buymeacoffee") ||
            lowered.contains("buy me a coffee") ||
            lowered.contains("telegram") ||
            lowered.contains("facebook") ||
            lowered.contains("twitter") ||
            lowered.contains("x.com") ||
            lowered.contains("instagram")

        let looksLikeUrlOrSourcePlug =
            lowered.contains("http://") ||
            lowered.contains("https://") ||
            lowered.contains("www.") ||
            lowered.contains(".com") ||
            lowered.contains(".net") ||
            lowered.contains(".org") ||
            lowered.contains("read at ") ||
            lowered.contains("read on ") ||
            lowered.contains("published on ")

        if lowered.hasPrefix("translator:") ||
            lowered.hasPrefix("editor:") ||
            lowered.hasPrefix("edited by") ||
            lowered.hasPrefix("proofreader:") ||
            lowered.hasPrefix("raw provider:") ||
            lowered.hasPrefix("source:") ||
            lowered.hasPrefix("author note:") ||
            lowered.hasPrefix("a/n:") ||
            lowered.hasPrefix("note:") ||
            lowered.hasPrefix("tl:") ||
            lowered.hasPrefix("t/l:") ||
            lowered.hasPrefix("edit:") ||
            lowered.hasPrefix("credits:")
        {
            return true
        }

        if hasPromoKeyword || looksLikeUrlOrSourcePlug {
            return true
        }

        if compact == "atlasstudios" || compact.contains("atlasstudioseditor") {
            return true
        }

        // ReaderView already renders a dedicated title header.
        if lowered == currentChapter.title.lowercased() {
            return true
        }

        if lowered.range(of: #"^chapter\s*\d+(\s*[:\-].*)?$"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }
}

private struct ParagraphOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
