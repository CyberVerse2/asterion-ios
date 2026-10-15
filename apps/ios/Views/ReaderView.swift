import Inject
import Combine
import SwiftUI
import WidgetKit

private enum ReaderThemePreference: String, CaseIterable {
    case system = "System"
    case parchment = "Parchment"
    case night = "Night"
}

private enum ReaderTypefacePreference: String, CaseIterable {
    case literary = "Literary"
    case classic = "Classic"
    case accessible = "Accessible"
}

struct ReaderView: View {
    @ObserveInjection var inject
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var readingProgressService: ReadingProgressService
    @EnvironmentObject private var tabBarState: TabBarState
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var readingActivityService: ReadingActivityService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let initialChapter: Chapter
    let novel: Novel
    let allChapters: [Chapter]
    let shouldAutoResumeFromSavedProgress: Bool
    let offlineOnly: Bool
    let offlineChapterFiles: [DownloadedChapterFile]
    @State private var lastReadingTick: Date?
    @State private var readerVisible = false
    private let readingTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    @State private var currentChapter: Chapter
    @State private var showControls = true
    @State private var fontSize: CGFloat = 20
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
    @State private var showReaderSettings = false
    @State private var showChapterPicker = false
    @State private var currentBookmarkID: String?
    @State private var bookmarkActionInFlight = false
    @State private var alertTitle = "Chapter Download"
    @AppStorage("asterion.reader.theme") private var readerThemeRaw = ReaderThemePreference.system.rawValue
    @AppStorage("asterion.reader.typeface") private var readerTypefaceRaw = ReaderTypefacePreference.literary.rawValue
    @AppStorage("asterion.reader.line-spacing") private var savedLineSpacing = 0.85

    private var readerTheme: ReaderThemePreference {
        ReaderThemePreference(rawValue: readerThemeRaw) ?? .system
    }
    private var readerTypeface: ReaderTypefacePreference {
        ReaderTypefacePreference(rawValue: readerTypefaceRaw) ?? .literary
    }
    private var readerBackground: Color {
        switch readerTheme {
        case .system: Color.asterionBackground
        case .parchment: Color(red: 0.94, green: 0.90, blue: 0.80)
        case .night: Color(red: 0.035, green: 0.04, blue: 0.05)
        }
    }
    private var readerForeground: Color {
        switch readerTheme {
        case .system: Color.asterionReaderText
        case .parchment: Color(red: 0.18, green: 0.15, blue: 0.11)
        case .night: Color(red: 0.86, green: 0.84, blue: 0.79)
        }
    }
    private var readerFont: Font {
        switch readerTypeface {
        case .literary: .asterionLiterary(fontSize)
        case .classic: .system(size: fontSize, design: .serif)
        case .accessible: .system(size: fontSize, weight: .regular, design: .rounded)
        }
    }
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
        if offlineOnly { return hasPrev }
        if currentChapter.chapterNumber > 1 { return true }
        return hasPrev
    }

    private var canNavigateNext: Bool {
        if offlineOnly { return hasNext }
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
    private var topBarTopPadding: CGFloat { isDesktop ? 18 : 44 }
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
        shouldAutoResumeFromSavedProgress: Bool = true,
        offlineOnly: Bool = false,
        offlineChapterFiles: [DownloadedChapterFile] = []
    ) {
        self.initialChapter = initialChapter
        self.novel = novel
        self.allChapters = allChapters
        self.shouldAutoResumeFromSavedProgress = shouldAutoResumeFromSavedProgress
        self.offlineOnly = offlineOnly
        self.offlineChapterFiles = offlineChapterFiles
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
                readerBackground.opacity(0.92).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView().tint(Color.asterionInk)
                    Text("Loading chapter")
                        .font(.asterionReading(14))
                        .foregroundStyle(Color.asterionMuted)
                }
            }
        }
        .background(readerBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .statusBarHidden(isDesktop ? false : !showControls)
        .onAppear {
            readerVisible = true
            lastReadingTick = .now
            tabBarState.isVisible = false
            if !isDesktop { scheduleHideControls() }
            Task { await restoreProgressAndLoadChapter() }
            Task { await refreshCurrentChapterDownloadState() }
            Task { await updateReadingLiveActivity() }
            Task { await refreshCurrentBookmark() }
        }
        .onDisappear { tabBarState.isVisible = true }
        .onDisappear {
            recordReadingTime()
            readerVisible = false
            lastReadingTick = nil
            progressSyncTask?.cancel()
            liveActivityUpdateTask?.cancel()
            Task { await ReadingLiveActivityManager.shared.end() }
            syncReadingPosition(reloadWidget: true)
        }
        .onReceive(readingTimer) { _ in
            guard readerVisible, scenePhase == .active else { return }
            recordReadingTime()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, readerVisible { lastReadingTick = .now }
            else { recordReadingTime(); lastReadingTick = nil }
        }
        .alert(alertTitle, isPresented: $showDownloadAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloadAlertMessage)
        }
        .edgeSwipeToDismiss { dismiss() }
        .sheet(isPresented: $showReaderSettings) {
            readerSettingsSheet
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showChapterPicker) {
            chapterPickerSheet
                .presentationDetents([.medium, .large])
        }
        .onChange(of: currentChapter.id) { _, _ in
            currentLine = 0
            withAnimation {
                scrollProxy?.scrollTo("top", anchor: .top)
            }
            Task { await refreshCurrentChapterDownloadState() }
            Task { await refreshCurrentBookmark() }
            scheduleReadingLiveActivityUpdate()
        }
        .enableInjection()
    }

    // MARK: - Chapter Heading

    private var chapterHeading: some View {
        VStack(spacing: 10) {
            Spacer().frame(height: 72)

            Text(novel.title)
                .font(.asterionReading(13))
                .foregroundStyle(Color.asterionMuted)
                .lineLimit(1)

            if currentChapter.chapterNumber > 0 {
                Text("Chapter \(currentChapter.chapterNumber)")
                    .font(.asterionReading(13, weight: .medium))
                    .foregroundStyle(Color.asterionMuted)
            }

            if !currentChapter.displayTitle.isEmpty {
                Text(currentChapter.displayTitle)
                    .font(.asterionDisplay(28, weight: .medium))
                    .foregroundStyle(Color.asterionText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, readerHorizontalPadding)
        .padding(.bottom, 22)
    }

    // MARK: - Chapter Content

    private var chapterContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, para in
                Text(para)
                    .id(lineAnchorId(for: index))
                    .font(readerFont)
                    .lineSpacing(fontSize * savedLineSpacing)
                    .foregroundStyle(readerForeground)
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
        HStack(spacing: 10) {
            if shouldShowPrevButton {
                Button {
                    navigateChapter(direction: -1)
                } label: {
                    Text("Previous")
                        .font(.asterionReading(15, weight: .medium))
                        .foregroundStyle(canNavigatePrev ? Color.asterionText : Color.asterionMuted)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 13)
                        .background(Color.asterionCard, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canNavigatePrev)
            }

            Button {
                navigateChapter(direction: 1)
            } label: {
                Text("Next chapter")
                    .font(.asterionReading(15, weight: .semibold))
                    .foregroundStyle(canNavigateNext ? Color.asterionOnInk : Color.asterionMuted)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(
                        canNavigateNext ? Color.asterionInk : Color.asterionCard,
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canNavigateNext)
        }
        .padding(.top, 28)
        .padding(.bottom, 36)
    }

    // MARK: - Top Control Bar

    private var topControlBar: some View {
        AsterionDetailBar(onBack: { dismiss() }, topPadding: topBarTopPadding) {
            HStack(spacing: 8) {
                Button { fontSize = max(14, fontSize - 1) } label: {
                    Text("A−")
                        .font(.asterionReading(14, weight: .medium))
                        .modifier(ReaderChromeCircle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Smaller text")

                Button { fontSize = min(28, fontSize + 1) } label: {
                    Text("A+")
                        .font(.asterionReading(15, weight: .medium))
                        .modifier(ReaderChromeCircle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Larger text")

                Menu {
                    Button {
                        showChapterPicker = true
                    } label: {
                        Label("Choose chapter", systemImage: "list.number")
                    }

                    Button {
                        Task { await toggleCurrentBookmark() }
                    } label: {
                        Label(
                            currentBookmarkID == nil ? "Bookmark chapter" : "Remove bookmark",
                            systemImage: currentBookmarkID == nil ? "bookmark" : "bookmark.fill"
                        )
                    }
                    .disabled(bookmarkActionInFlight)

                    Button {
                        Task { await downloadCurrentChapterToFolder() }
                    } label: {
                        Label(
                            isCurrentChapterDownloaded ? "Downloaded" : "Download chapter",
                            systemImage: isCurrentChapterDownloaded ? "checkmark" : "arrow.down"
                        )
                    }

                    ShareLink(item: exportText, subject: Text(novel.title)) {
                        Label("Share chapter", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showReaderSettings = true
                    } label: {
                        Label("Reading settings", systemImage: "textformat.size")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .modifier(ReaderChromeCircle())
                }
                .accessibilityLabel("More")
            }
        }
        .background {
            LinearGradient(
                colors: [readerBackground, readerBackground.opacity(0.96), readerBackground.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        }
        .opacity(showControls ? 1 : 0)
        .animation(.easeInOut(duration: 0.35), value: showControls)
        .allowsHitTesting(showControls)
    }

    // MARK: - Bottom Control Bar

    private var bottomControlBar: some View {
        HStack(spacing: 10) {
            if shouldShowPrevButton {
                Button { navigateChapter(direction: -1) } label: {
                    Text("Previous")
                        .font(.asterionReading(15, weight: .medium))
                        .foregroundStyle(canNavigatePrev ? Color.asterionText : Color.asterionMuted)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 13)
                        .background(Color.asterionCard, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canNavigatePrev)
            }

            Button { navigateChapter(direction: 1) } label: {
                Text("Next chapter")
                    .font(.asterionReading(15, weight: .semibold))
                    .foregroundStyle(canNavigateNext ? Color.asterionOnInk : Color.asterionMuted)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(
                        canNavigateNext ? Color.asterionInk : Color.asterionCard,
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canNavigateNext)
        }
        .padding(.bottom, bottomBarBottomPadding)
        .padding(.top, 20)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [readerBackground.opacity(0), readerBackground.opacity(0.94), readerBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .opacity(showControls ? 1 : 0)
        .animation(.easeInOut(duration: 0.35), value: showControls)
        .allowsHitTesting(showControls)
    }

    private var readerSettingsSheet: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $readerThemeRaw) {
                        ForEach(ReaderThemePreference.allCases, id: \.rawValue) { theme in
                            Text(theme.rawValue).tag(theme.rawValue)
                        }
                    }
                    Picker("Typeface", selection: $readerTypefaceRaw) {
                        ForEach(ReaderTypefacePreference.allCases, id: \.rawValue) { typeface in
                            Text(typeface.rawValue).tag(typeface.rawValue)
                        }
                    }
                }

                Section("Text") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Size")
                            Spacer()
                            Text("\(Int(fontSize)) pt")
                                .foregroundStyle(Color.asterionMuted)
                        }
                        Slider(value: $fontSize, in: 14...30, step: 1)
                            .tint(Color.asterionInk)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Line spacing")
                            Spacer()
                            Text(savedLineSpacing, format: .number.precision(.fractionLength(1)))
                                .foregroundStyle(Color.asterionMuted)
                        }
                        Slider(value: $savedLineSpacing, in: 0.5...1.4, step: 0.1)
                            .tint(Color.asterionInk)
                    }
                }

                Section("Preview") {
                    Text("A good reader disappears, leaving only the world on the page.")
                        .font(readerFont)
                        .lineSpacing(fontSize * savedLineSpacing)
                        .foregroundStyle(readerForeground)
                        .padding(.vertical, 12)
                        .listRowBackground(readerBackground)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.asterionBackground)
            .navigationTitle("Reading settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showReaderSettings = false }
                }
            }
        }
    }

    private var chapterPickerSheet: some View {
        NavigationStack {
            List(navigationChapters) { chapter in
                Button {
                    showChapterPicker = false
                    Task { await openChapter(chapter) }
                } label: {
                    HStack(spacing: 12) {
                        Text(chapter.chapterNumber > 0 ? "\(chapter.chapterNumber)" : "•")
                            .font(.asterionReading(13, weight: .medium))
                            .foregroundStyle(Color.asterionMuted)
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                        Text(chapter.displayTitle.isEmpty ? chapter.labeledTitle : chapter.displayTitle)
                            .font(.asterionReading(16))
                            .foregroundStyle(Color.asterionText)
                            .lineLimit(2)
                        Spacer()
                        if chapter.id == currentChapter.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.asterionInk)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .scrollContentBackground(.hidden)
            .background(Color.asterionBackground)
            .navigationTitle("Chapters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showChapterPicker = false }
                }
            }
        }
    }

    private var exportText: String {
        let chapterLabel = currentChapter.labeledTitle
        return """
        \(novel.title)
        \(chapterLabel)

        \(paragraphs.joined(separator: "\n\n"))
        """
    }

    // MARK: - Actions

    private func openChapter(_ chapter: Chapter) async {
        recordReadingTime()
        if offlineOnly {
            guard let loaded = loadOfflineChapter(chapter) else { return }
            currentLine = 0
            currentChapter = loaded
            syncReadingPosition()
            scheduleHideControls()
            return
        }
        currentLine = 0
        loadingChapter = true
        defer { loadingChapter = false; lastReadingTick = .now }
        do {
            currentChapter = try await apiClient.fetchChapter(id: chapter.id)
            await OfflineChapterStore.shared.cacheChapter(currentChapter)
        } catch {
            currentChapter = await OfflineChapterStore.shared.chapter(id: chapter.id) ?? chapter
        }
        syncReadingPosition()
        scheduleHideControls()
    }

    private func refreshCurrentBookmark() async {
        guard authService.isSignedIn, !offlineOnly else {
            currentBookmarkID = nil
            return
        }
        do {
            currentBookmarkID = try await apiClient.fetchBookmarks().first {
                $0.novelId == novel.id && $0.chapterId == currentChapter.id
            }?.id
        } catch {
            currentBookmarkID = nil
        }
    }

    private func toggleCurrentBookmark() async {
        guard authService.isSignedIn else {
            alertTitle = "Sign in to bookmark"
            downloadAlertMessage = "You can keep reading as a guest. Sign in from Account when you want bookmarks on every device."
            showDownloadAlert = true
            return
        }
        bookmarkActionInFlight = true
        defer { bookmarkActionInFlight = false }
        do {
            if let currentBookmarkID {
                _ = try await apiClient.deleteBookmark(id: currentBookmarkID)
                self.currentBookmarkID = nil
            } else {
                currentBookmarkID = try await apiClient.createBookmark(
                    novelId: novel.id,
                    chapterId: currentChapter.id
                ).id
            }
        } catch {
            alertTitle = "Bookmark unavailable"
            downloadAlertMessage = "The bookmark could not be saved. Please try again."
            showDownloadAlert = true
        }
    }

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
        recordReadingTime()
        loadingChapter = true
        Task {
            defer { loadingChapter = false; lastReadingTick = .now }

            let target: Chapter?
            let nextIdx = currentIndex + direction
            if nextIdx >= 0 && nextIdx < navigationChapters.count {
                target = navigationChapters[nextIdx]
            } else {
                target = await fetchAdjacentChapterFallback(direction: direction)
            }

            guard let target else { return }
            if offlineOnly {
                guard let loaded = loadOfflineChapter(target) else { return }
                currentLine = 0
                currentChapter = loaded
                syncReadingPosition()
                scheduleHideControls()
                return
            }
            currentLine = 0

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
        guard !offlineOnly else { return nil }
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
        if offlineOnly { syncReadingPosition(); return }
        loadingChapter = true
        defer { loadingChapter = false; lastReadingTick = .now }
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
        if offlineOnly {
            if shouldAutoResumeFromSavedProgress,
               let saved = readingProgressService.localProgress.first(where: { $0.novelId == novel.id }),
               let chapter = allChapters.first(where: { $0.id == saved.chapterId }) {
                currentChapter = chapter
                currentLine = saved.currentLine
                pendingRestoreLine = saved.currentLine
            }
            guard let loaded = loadOfflineChapter(currentChapter) else { return }
            currentChapter = loaded
            lastReadingTick = .now
            syncReadingPosition()
            await Task.yield()
            restoreScrollPositionIfNeeded()
            return
        }
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
            totalLines: totalLines,
            syncToCloud: !novel.id.hasPrefix("offline-") && !currentChapter.id.hasPrefix("offline-")
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

    private func recordReadingTime() {
        let now = Date()
        defer { lastReadingTick = now }
        guard readerVisible, let lastReadingTick, !loadingChapter, !paragraphs.isEmpty else { return }
        readingActivityService.record(novelID: novel.id, chapterID: currentChapter.id,
                                      seconds: now.timeIntervalSince(lastReadingTick), endingAt: now)
    }

    private func loadOfflineChapter(_ chapter: Chapter) -> Chapter? {
        if let file = offlineChapterFiles.first(where: { $0.id == chapter.id }),
           let loaded = try? OfflineChapterStore.shared.downloadedChapter(file) {
            return loaded
        }
        if chapter.content?.isEmpty == false { return chapter }
        alertTitle = "Chapter unavailable"
        downloadAlertMessage = "This chapter file could not be opened. Download it again from the novel page."
        showDownloadAlert = true
        return nil
    }

    private func lineAnchorId(for index: Int) -> String {
        "line-\(index)"
    }

    private func downloadCurrentChapterToFolder() async {
        alertTitle = "Chapter Download"
        let chapterHeader = currentChapter.labeledTitle
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
                content: content,
                novel: novel,
                chapter: currentChapter
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
        if lowered == currentChapter.title.lowercased()
            || lowered == currentChapter.displayTitle.lowercased() {
            return true
        }

        if lowered.range(of: #"^chapter\s*\d+(\s*[:\-].*)?$"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }
}

private struct ReaderChromeCircle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(Color.asterionInk)
            .frame(width: 36, height: 36)
            .background(Color.asterionCard, in: Circle())
    }
}

private struct ParagraphOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
