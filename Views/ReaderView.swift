import Inject
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var isExportingChapter = false
    @State private var exportDocument: ChapterTextDocument?
    @State private var exportFilename = "chapter.txt"

    private var genreColor: Color { GenreStyle.color(for: novel.genres) }

    private var currentIndex: Int {
        allChapters.firstIndex(where: { $0.id == currentChapter.id }) ?? -1
    }
    private var hasPrev: Bool { currentIndex > 0 }
    private var hasNext: Bool { currentIndex >= 0 && currentIndex < allChapters.count - 1 }
    private var readerHorizontalPadding: CGFloat { horizontalSizeClass == .compact ? 20 : 32 }

    private var paragraphs: [String] {
        currentChapter.plainContent
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }
            .filter { !$0.isEmpty }
            .filter { !shouldFilterMetadataLine($0) }
    }

    init(initialChapter: Chapter, novel: Novel, allChapters: [Chapter]) {
        self.initialChapter = initialChapter
        self.novel = novel
        self.allChapters = allChapters
        self._currentChapter = State(initialValue: initialChapter)
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
        .statusBarHidden(!showControls)
        .onAppear {
            tabBarState.isVisible = false
            scheduleHideControls()
            Task { await restoreProgressAndLoadChapter() }
        }
        .onDisappear { tabBarState.isVisible = true }
        .onDisappear {
            progressSyncTask?.cancel()
            readingProgressService.updateProgress(
                novelId: novel.id,
                chapterId: currentChapter.id,
                currentLine: currentLine,
                totalLines: max(1, paragraphs.count)
            )
        }
        .fileExporter(
            isPresented: $isExportingChapter,
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: exportFilename
        ) { _ in
            exportDocument = nil
        }
        .onChange(of: currentChapter.id) { _, _ in
            currentLine = 0
            withAnimation {
                scrollProxy?.scrollTo("top", anchor: .top)
            }
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
                    .lineSpacing(fontSize * 0.85)
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
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    // MARK: - End of Chapter Nav

    private var endOfChapterNav: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.asterionCard).frame(height: 1)
                .padding(.horizontal, readerHorizontalPadding)

            HStack(spacing: 16) {
                if hasPrev {
                    Button {
                        navigateChapter(direction: -1)
                    } label: {
                        Text("← Previous")
                            .font(.asterionSerif(14))
                            .foregroundStyle(Color.asterionMuted)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.asterionBorder, lineWidth: 1)
                            )
                    }
                }

                if hasNext {
                    Button {
                        navigateChapter(direction: 1)
                    } label: {
                        Text("Next Chapter →")
                            .font(.asterionSerif(14))
                            .foregroundStyle(Color.goldAccent)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(genreColor.opacity(0.1))
                                    .stroke(genreColor.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
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
                    .font(.system(size: 13))
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
                .frame(maxWidth: 160)

            Spacer()

            HStack(spacing: 8) {
                Button {
                    prepareChapterExport()
                } label: {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.asterionMuted)
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
        .padding(.horizontal, 20)
        .padding(.top, 50)
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
            if hasPrev {
                Button { navigateChapter(direction: -1) } label: {
                    Text("◂ Prev")
                        .font(.asterionMono(12))
                        .foregroundStyle(Color.asterionMuted)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .overlay(
                            Capsule().stroke(Color.asterionBorder, lineWidth: 1)
                        )
                }
            }
            if hasNext {
                Button { navigateChapter(direction: 1) } label: {
                    Text("Next ▸")
                        .font(.asterionMono(12))
                        .foregroundStyle(Color.goldAccent)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .overlay(
                            Capsule().stroke(genreColor.opacity(0.5), lineWidth: 1)
                        )
                }
            }
        }
        .padding(.bottom, 34)
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
        showControls.toggle()
        if showControls { scheduleHideControls() }
    }

    private func scheduleHideControls() {
        controlTimer?.cancel()
        controlTimer = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            withAnimation { showControls = false }
        }
    }

    private func navigateChapter(direction: Int) {
        let nextIdx = currentIndex + direction
        guard nextIdx >= 0 && nextIdx < allChapters.count else { return }
        let target = allChapters[nextIdx]

        loadingChapter = true
        Task {
            defer { loadingChapter = false }
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
            readingProgressService.updateProgress(
                novelId: novel.id,
                chapterId: currentChapter.id,
                currentLine: currentLine,
                totalLines: max(1, paragraphs.count)
            )
            scheduleHideControls()
        }
    }

    private func loadInitialChapter() async {
        loadingChapter = true
        defer { loadingChapter = false }
        do {
            currentChapter = try await apiClient.fetchChapter(id: currentChapter.id)
            await OfflineChapterStore.shared.cacheChapter(currentChapter)
            readingProgressService.updateProgress(
                novelId: novel.id,
                chapterId: currentChapter.id,
                currentLine: currentLine,
                totalLines: max(1, paragraphs.count)
            )
        } catch {
            if let cached = await OfflineChapterStore.shared.chapter(id: currentChapter.id) {
                currentChapter = cached
            }
            readingProgressService.updateProgress(
                novelId: novel.id,
                chapterId: currentChapter.id,
                currentLine: currentLine,
                totalLines: max(1, paragraphs.count)
            )
        }
    }

    private func restoreProgressAndLoadChapter() async {
        await readingProgressService.refreshRemoteProgress(novelId: novel.id)
        if let remoteProgress = readingProgressService.currentProgress,
           remoteProgress.novelId == novel.id,
           let savedChapter = allChapters.first(where: { $0.id == remoteProgress.chapterId })
        {
            currentChapter = savedChapter
            pendingRestoreLine = remoteProgress.currentLine
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
    }

    private func scheduleProgressSync() {
        progressSyncTask?.cancel()
        progressSyncTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            readingProgressService.updateProgress(
                novelId: novel.id,
                chapterId: currentChapter.id,
                currentLine: currentLine,
                totalLines: max(1, paragraphs.count)
            )
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

    private func prepareChapterExport() {
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
        Task { await OfflineChapterStore.shared.cacheChapter(currentChapter) }
        exportDocument = ChapterTextDocument(text: content)
        exportFilename = makeDownloadFilename()
        isExportingChapter = true
    }

    private func makeDownloadFilename() -> String {
        let chapterPart = currentChapter.chapterNumber > 0 ? "ch-\(currentChapter.chapterNumber)" : "chapter"
        let base = "\(novel.title)-\(chapterPart)"
        let sanitized = base
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitized.isEmpty ? "chapter.txt" : "\(sanitized).txt"
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

private struct ChapterTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let value = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = value
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return .init(regularFileWithContents: data)
    }
}

private struct ParagraphOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
