import AVFoundation
import Inject
import Combine
import MediaPlayer
import NaturalLanguage
import SwiftUI
import UIKit
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

/// Handoff contract shared with the macOS app (keep the keys in step).
private enum ReaderHandoff {
    static let readingActivityType = "cloud.cyberverse.asterion.reading"
    /// Advertised position is refreshed at most this often.
    static let minimumUpdateInterval: TimeInterval = 5

    /// "progress" key: 0 at the first paragraph, 1 at the last.
    static func progress(line: Int, lineCount: Int) -> Double {
        guard lineCount > 1 else { return 0 }
        return min(1, max(0, Double(line) / Double(lineCount - 1)))
    }

    /// Prefers the sender's paragraph index when both sides split the chapter
    /// into the same number of paragraphs (or the sender didn't say), and
    /// otherwise maps the sender's fraction onto this chapter.
    static func resolveLine(line: Int, lineCount: Int?, progress: Double?, paragraphCount: Int) -> Int {
        let lastLine = max(0, paragraphCount - 1)
        if let lineCount, let progress, paragraphCount > 0, lineCount != paragraphCount {
            return min(lastLine, max(0, Int((progress * Double(lastLine)).rounded())))
        }
        return paragraphCount > 0 ? min(line, lastLine) : line
    }
}

private struct ReaderHandoffPosition: Equatable {
    var chapterID = ""
    var chapterTitle = ""
    var line = 0
    var lineCount = 0
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
    /// Line to open at, overriding saved progress (used by Handoff). Nil keeps the default behaviour.
    let initialLine: Int?
    /// Handoff only: the sender's paragraph count and 0...1 position, used to
    /// place `initialLine` when this device splits the chapter differently.
    let initialLineCount: Int?
    let initialLineProgress: Double?
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
    @AppStorage("asterion.reader.listen-rate") private var listenRate = 1.0
    @StateObject private var speech = ReaderSpeechController()
    @State private var handoffPosition = ReaderHandoffPosition()
    @State private var lastHandoffUpdate = Date.distantPast
    @State private var handoffUpdateTask: Task<Void, Never>?

    private var readerTheme: ReaderThemePreference {
        ReaderThemePreference(rawValue: readerThemeRaw) ?? .system
    }
    private var readerTypeface: ReaderTypefacePreference {
        ReaderTypefacePreference(rawValue: readerTypefaceRaw) ?? .literary
    }
    private var readerBackground: Color { Self.paper(for: readerTheme) }
    private var readerForeground: Color { Self.ink(for: readerTheme) }
    /// Window appearance while reading: System follows the device, the other
    /// themes pin the status bar to match their page.
    private var readerWindowStyle: UIUserInterfaceStyle {
        switch readerTheme {
        case .system: .unspecified
        case .parchment: .light
        case .night: .dark
        }
    }
    private static func paper(for theme: ReaderThemePreference) -> Color {
        switch theme {
        case .system: Color.asterionReaderPaper
        case .parchment: Color(red: 0.94, green: 0.90, blue: 0.80)
        case .night: Color(red: 0.035, green: 0.04, blue: 0.05)
        }
    }
    private static func ink(for theme: ReaderThemePreference) -> Color {
        switch theme {
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
        novel.catalogChapterCount
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
    private var topBarTopPadding: CGFloat { isDesktop ? 18 : 8 }
    private var bottomBarBottomPadding: CGFloat { isDesktop ? 22 : 34 }

    private var paragraphs: [String] { paragraphs(for: currentChapter) }

    private func paragraphs(for chapter: Chapter) -> [String] {
        chapter.plainContent
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }
            .filter { !$0.isEmpty }
            .filter { !shouldFilterMetadataLine($0, chapter: chapter) }
    }

    init(
        initialChapter: Chapter,
        novel: Novel,
        allChapters: [Chapter],
        shouldAutoResumeFromSavedProgress: Bool = true,
        offlineOnly: Bool = false,
        offlineChapterFiles: [DownloadedChapterFile] = [],
        initialLine: Int? = nil,
        initialLineCount: Int? = nil,
        initialLineProgress: Double? = nil
    ) {
        self.initialChapter = initialChapter
        self.novel = novel
        self.allChapters = allChapters
        self.shouldAutoResumeFromSavedProgress = shouldAutoResumeFromSavedProgress
        self.offlineOnly = offlineOnly
        self.offlineChapterFiles = offlineChapterFiles
        self.initialLine = initialLine.map { max(0, $0) }
        self.initialLineCount = initialLineCount
        self.initialLineProgress = initialLineProgress
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
                .overlay(alignment: .top) {
                    ReaderIslandProgress(fraction: chapterFraction, ink: readerForeground)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }

            if loadingChapter {
                readerLoadingOverlay
            }
        }
        .background(readerBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .statusBarHidden(isDesktop ? false : !showControls)
        .onAppear { WindowAppearance.apply(readerWindowStyle) }
        .onChange(of: readerThemeRaw) { _, _ in
            WindowAppearance.apply(readerWindowStyle)
        }
        .onDisappear { WindowAppearance.apply(.dark) }
        .onAppear {
            readerVisible = true
            lastReadingTick = .now
            tabBarState.isVisible = false
            if !isDesktop { scheduleHideControls() }
            Task { await restoreProgressAndLoadChapter() }
            Task { await refreshCurrentChapterDownloadState() }
            Task { await updateReadingLiveActivity() }
            Task { await refreshCurrentBookmark() }
            connectSpeechCallbacks()
        }
        .onDisappear { tabBarState.isVisible = true }
        .onDisappear {
            speech.stop()
            handoffUpdateTask?.cancel()
            recordReadingTime()
            readerVisible = false
            lastReadingTick = nil
            progressSyncTask?.cancel()
            liveActivityUpdateTask?.cancel()
            Task { await ReadingLiveActivityManager.shared.end() }
            syncReadingPosition(reloadWidget: true)
        }
        .onReceive(readingTimer) { _ in
            // Listening with the screen locked counts as reading time too.
            guard readerVisible, scenePhase == .active || speech.isPlaying else { return }
            recordReadingTime()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, readerVisible { lastReadingTick = .now }
            else { recordReadingTime(); lastReadingTick = nil }
        }
        .onChange(of: listenRate) { _, rate in
            // Slider steps drift (1.2000000001); keep the stored rate on tenths.
            let tidy = (rate * 10).rounded() / 10
            if tidy != rate { listenRate = tidy; return }
            speech.setRate(rate)
        }
        .userActivity(ReaderHandoff.readingActivityType, isActive: readerVisible && canAdvertiseHandoff) { activity in
            activity.title = "\(novel.title) · \(handoffPosition.chapterTitle)"
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = false
            activity.isEligibleForPrediction = false
            activity.userInfo = [
                "novelId": novel.id,
                "chapterId": handoffPosition.chapterID,
                "line": handoffPosition.line,
                "lineCount": handoffPosition.lineCount,
                "progress": ReaderHandoff.progress(line: handoffPosition.line, lineCount: handoffPosition.lineCount),
                "novelTitle": novel.title,
                "chapterTitle": handoffPosition.chapterTitle,
            ]
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
                .presentationBackground(Color.asterionBackground)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showChapterPicker) {
            chapterPickerSheet
                .presentationDetents([.medium, .large])
                .presentationBackground(Color.asterionBackground)
                .preferredColorScheme(.dark)
        }
        .onChange(of: loadingChapter) { _, isLoading in
            if !isLoading { scheduleReadingLiveActivityUpdate() }
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
        VStack(alignment: .leading, spacing: 10) {
            Spacer().frame(height: 72)

            AsterionEyebrow(text: novel.title, color: readerForeground.opacity(0.5))

            if currentChapter.chapterNumber > 0 {
                Text(verbatim: "Chapter \(currentChapter.chapterNumber)")
                    .font(.asterionMono(12, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(readerForeground.opacity(0.55))
            }

            if !currentChapter.displayTitle.isEmpty {
                Text(currentChapter.displayTitle)
                    .font(.asterionReading(isLargeIPadLayout || isDesktop ? 32 : 28, weight: .semibold))
                    .foregroundStyle(readerForeground)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, readerHorizontalPadding)
        .frame(maxWidth: readerMaxContentWidth)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 28)
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
                    .background { spokenParagraphHighlight(isSpoken: isSpokenParagraph(index)) }
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

    private func isSpokenParagraph(_ index: Int) -> Bool {
        speech.isActive && speech.spokenParagraph == index
    }

    /// A soft wash in the page's own ink behind the paragraph being read aloud.
    private func spokenParagraphHighlight(isSpoken: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(readerForeground.opacity(isSpoken ? 0.08 : 0))
            .padding(.horizontal, -12)
            .padding(.vertical, -8)
            .animation(.easeInOut(duration: 0.3), value: isSpoken)
            .accessibilityHidden(true)
    }

    // MARK: - End of Chapter Nav

    /// Sits on the page itself, so it is drawn in the page's own ink.
    private var endOfChapterNav: some View {
        VStack(spacing: 18) {
            Rectangle()
                .fill(readerForeground.opacity(0.12))
                .frame(height: 1)

            VStack(spacing: 4) {
                Text("End of chapter")
                    .font(.asterionReading(12.5))
                    .foregroundStyle(readerForeground.opacity(0.5))
                if currentChapter.chapterNumber > 0 {
                    Text(chapterPositionLabel)
                        .font(.asterionMono(11, weight: .medium))
                        .foregroundStyle(readerForeground.opacity(0.5))
                }
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 12) {
                if shouldShowPrevButton {
                    Button {
                        navigateChapter(direction: -1)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .bold))
                            Text("Previous")
                        }
                    }
                    .buttonStyle(ReaderPageCapsuleStyle(ink: readerForeground, paper: readerBackground))
                    .disabled(!canNavigatePrev)
                    .accessibilityLabel("Previous chapter")
                }

                Spacer(minLength: 0)

                Button {
                    navigateChapter(direction: 1)
                } label: {
                    HStack(spacing: 7) {
                        Text("Next chapter")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                }
                .buttonStyle(ReaderPageCapsuleStyle(ink: readerForeground, paper: readerBackground, isProminent: true))
                .disabled(!canNavigateNext)
                .accessibilityLabel("Next chapter")
            }
        }
        .padding(.horizontal, readerHorizontalPadding)
        .frame(maxWidth: readerMaxContentWidth)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 110)
        .accessibilityElement(children: .contain)
    }

    private var chapterPositionLabel: String {
        if let totalChapterCountHint, totalChapterCountHint > 0 {
            return String(currentChapter.chapterNumber) + " of " + String(totalChapterCountHint)
        }
        return "Chapter " + String(currentChapter.chapterNumber)
    }

    // MARK: - Loading

    private var readerLoadingOverlay: some View {
        ZStack {
            readerBackground.opacity(0.92)

            ArtworkToneReader(url: novel.imageUrl.flatMap(URL.init(string:))) { tone in
                RadialGradient(
                    colors: [tone.opacity(0.16), tone.opacity(0.04), .clear],
                    center: .center,
                    startRadius: 4,
                    endRadius: 300
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            VStack(spacing: 14) {
                ProgressView()
                    .tint(readerForeground.opacity(0.7))
                Text("Loading chapter")
                    .font(.asterionReading(13.5))
                    .foregroundStyle(readerForeground.opacity(0.6))
            }
            .accessibilityElement(children: .combine)
        }
        .ignoresSafeArea()
    }

    // MARK: - Top Control Bar

    private var topControlBar: some View {
        AsterionDetailBar(onBack: { dismiss() }, topPadding: topBarTopPadding) {
            HStack(spacing: 8) {
                Button {
                    if speech.isActive { speech.stop() } else { startListening() }
                } label: {
                    Image(systemName: "headphones")
                        .font(.system(size: 14, weight: .semibold))
                        .modifier(ReaderListenCircle(isLit: speech.isActive))
                }
                .buttonStyle(ReaderFloatingButtonStyle())
                .disabled(loadingChapter && !speech.isActive)
                .accessibilityLabel(speech.isActive ? "Stop listening" : "Listen")
                .accessibilityHint(speech.isActive ? "" : "Reads the chapter aloud from where you are")

                Button { fontSize = max(14, fontSize - 1) } label: {
                    Text("A−")
                        .font(.asterionReading(13, weight: .semibold))
                        .modifier(ReaderChromeCircle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Smaller text")

                Button { fontSize = min(28, fontSize + 1) } label: {
                    Text("A+")
                        .font(.asterionReading(15, weight: .semibold))
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
        .padding(.bottom, 18)
        .background {
            LinearGradient(
                stops: [
                    .init(color: readerBackground, location: 0),
                    .init(color: readerBackground.opacity(0.94), location: 0.6),
                    .init(color: readerBackground.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            // Reach past the buttons so text never sits directly behind them.
            .padding(.bottom, -36)
            .ignoresSafeArea(edges: .top)
        }
        .opacity(showControls ? 1 : 0)
        .animation(.easeInOut(duration: 0.35), value: showControls)
        .allowsHitTesting(showControls)
    }

    // MARK: - Bottom Control Bar

    /// How far through the current chapter the reader is, 0...1.
    private var chapterFraction: Double {
        let lineCount = paragraphs.count
        return lineCount > 1 ? min(1, max(0, Double(currentLine) / Double(lineCount - 1))) : 0
    }

    /// One smoked capsule: previous, the chapter (tap to choose another),
    /// next. Progress lives on the line around the Dynamic Island instead.
    private var bottomControlBar: some View {
        let percent = Int((chapterFraction * 100).rounded())
        let number = currentChapter.chapterNumber

        return VStack(spacing: 12) {
            if speech.isActive {
                listeningControls
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(spacing: 0) {
                Button { navigateChapter(direction: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 50, height: 50)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ReaderFloatingButtonStyle())
                .disabled(!canNavigatePrev || !shouldShowPrevButton)
                .accessibilityLabel("Previous chapter")

                ReaderBarDivider()

                Button {
                    showChapterPicker = true
                } label: {
                    VStack(spacing: 2) {
                        Text(verbatim: number > 0 ? "CHAPTER \(number)" : "CHAPTER")
                            .font(.asterionMono(9.5, weight: .semibold))
                            .tracking(1.1)
                            .foregroundStyle(Color.white.opacity(0.5))
                            .contentTransition(.numericText())
                        Text(currentChapter.displayTitle)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.95))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ReaderFloatingButtonStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Choose chapter")
                .accessibilityValue(
                    number > 0
                        ? "Chapter \(number), \(currentChapter.displayTitle), \(percent) percent read"
                        : "\(percent) percent read"
                )

                ReaderBarDivider()

                Button { navigateChapter(direction: 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 50, height: 50)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ReaderFloatingButtonStyle())
                .disabled(!canNavigateNext)
                .accessibilityLabel("Next chapter")
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: 360)
            .modifier(ReaderSmokedBackground(shape: Capsule()))
            .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
            .padding(.horizontal, 28)
        }
        .animation(.easeInOut(duration: 0.25), value: speech.isActive)
        .padding(.bottom, bottomBarBottomPadding)
        .padding(.top, 24)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [readerBackground.opacity(0), readerBackground.opacity(0.9), readerBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .opacity(showControls ? 1 : 0)
        .animation(.easeInOut(duration: 0.35), value: showControls)
        .allowsHitTesting(showControls)
    }

    // MARK: - Listening Controls

    private var listenRateLabel: String {
        listenRate.formatted(.number.precision(.fractionLength(1))) + "×"
    }

    /// Smoked transport shown above the dock while the chapter is read aloud.
    private var listeningControls: some View {
        HStack(spacing: 0) {
            Button { speech.skipParagraph(by: -1) } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Previous paragraph")

            Button { speech.togglePlayback() } label: {
                Image(systemName: speech.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(speech.isPlaying ? "Pause" : "Resume")

            Button { speech.skipParagraph(by: 1) } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Next paragraph")

            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 1, height: 18)
                .padding(.horizontal, 4)
                .accessibilityHidden(true)

            Menu {
                Picker("Speed", selection: $listenRate) {
                    ForEach(ReaderSpeechController.rateSteps, id: \.self) { step in
                        Text(step.formatted(.number.precision(.fractionLength(1))) + "×").tag(step)
                    }
                }
            } label: {
                Text(listenRateLabel)
                    .font(.asterionMono(11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .contentTransition(.numericText())
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Speed")
            .accessibilityValue(listenRateLabel)

            Button { speech.stop() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Stop listening")
        }
        .buttonStyle(ReaderFloatingButtonStyle())
        .foregroundStyle(Color.white)
        .padding(.horizontal, 6)
        .modifier(ReaderSmokedBackground(shape: Capsule()))
    }

    // MARK: - Settings Sheet

    private var readerSettingsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    settingsGroup("Page") {
                        HStack(spacing: 10) {
                            ForEach(ReaderThemePreference.allCases, id: \.rawValue) { theme in
                                themeSwatch(theme)
                            }
                        }
                    }

                    settingsGroup("Typeface") {
                        HStack(spacing: 8) {
                            ForEach(ReaderTypefacePreference.allCases, id: \.rawValue) { typeface in
                                let selected = readerTypeface == typeface
                                Button {
                                    readerTypefaceRaw = typeface.rawValue
                                } label: {
                                    Text(typeface.rawValue)
                                        .font(.asterionReading(13, weight: .semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity)
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .asterionGlassPill(isSelected: selected)
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                    }

                    settingsGroup("Text") {
                        VStack(spacing: 0) {
                            settingsSliderRow(title: "Size", value: "\(Int(fontSize)) pt") {
                                Slider(value: $fontSize, in: 14...30, step: 1)
                                    .tint(Color.asterionInk)
                                    .accessibilityLabel("Text size")
                            }
                            Rectangle()
                                .fill(Color.asterionHairline)
                                .frame(height: 1)
                                .padding(.leading, 16)
                            settingsSliderRow(
                                title: "Line spacing",
                                value: savedLineSpacing.formatted(.number.precision(.fractionLength(1)))
                            ) {
                                Slider(value: $savedLineSpacing, in: 0.5...1.4, step: 0.1)
                                    .tint(Color.asterionInk)
                                    .accessibilityLabel("Line spacing")
                            }
                        }
                        .asterionPanel(cornerRadius: 14)
                    }

                    settingsGroup("Listen") {
                        VStack(alignment: .leading, spacing: 10) {
                            settingsSliderRow(title: "Speed", value: listenRateLabel) {
                                Slider(
                                    value: $listenRate,
                                    in: ReaderSpeechController.rateRange,
                                    step: 0.1
                                )
                                .tint(Color.asterionInk)
                                .accessibilityLabel("Listening speed")
                                .accessibilityValue(listenRateLabel)
                            }
                            .asterionPanel(cornerRadius: 14)

                            Text(ReaderSpeechController.voiceSummary)
                                .font(.asterionReading(12.5))
                                .foregroundStyle(Color.asterionMuted)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 4)
                        }
                    }

                    settingsGroup("Preview") {
                        Text("A good reader disappears, leaving only the world on the page.")
                            .font(readerFont)
                            .lineSpacing(fontSize * savedLineSpacing)
                            .foregroundStyle(readerForeground)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(readerBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.asterionBorder)
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Color.asterionBackground)
            .navigationTitle("Reading settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showReaderSettings = false }
                }
            }
        }
    }

    private func settingsGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AsterionEyebrow(text: title)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func settingsSliderRow<Control: View>(
        title: String,
        value: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.asterionReading(14.5, weight: .medium))
                    .foregroundStyle(Color.asterionText)
                Spacer()
                Text(value)
                    .font(.asterionMono(12, weight: .medium))
                    .foregroundStyle(Color.asterionMuted)
            }
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func themeSwatch(_ theme: ReaderThemePreference) -> some View {
        let selected = readerTheme == theme
        return Button {
            readerThemeRaw = theme.rawValue
        } label: {
            VStack(spacing: 8) {
                Text("Aa")
                    .font(.asterionReading(18, weight: .semibold))
                    .foregroundStyle(Self.ink(for: theme))
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Self.paper(for: theme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                selected ? Color.asterionInk : Color.asterionBorder,
                                lineWidth: selected ? 2 : 1
                            )
                    }
                Text(theme.rawValue)
                    .font(.asterionReading(12.5, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Color.asterionText : Color.asterionMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.rawValue) page")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Chapter Picker Sheet

    private var chapterPickerSheet: some View {
        ReaderChapterPickerSheet(
            chapters: navigationChapters,
            currentChapterID: currentChapter.id,
            onSelect: { chapter in
                showChapterPicker = false
                Task { await openChapter(chapter) }
            },
            onClose: { showChapterPicker = false }
        )
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
            guard let loaded = loadOfflineChapter(chapter) else { speech.chapterUnavailable(); return }
            currentLine = 0
            currentChapter = loaded
            syncReadingPosition()
            continueListening(in: loaded)
            scheduleHideControls()
            return
        }
        currentLine = 0
        loadingChapter = true
        defer { loadingChapter = false; lastReadingTick = .now }
        let loaded: Chapter
        do {
            loaded = try await apiClient.fetchChapter(id: chapter.id)
            await OfflineChapterStore.shared.cacheChapter(loaded)
        } catch {
            loaded = await OfflineChapterStore.shared.chapter(id: chapter.id) ?? chapter
        }
        currentChapter = loaded
        syncReadingPosition()
        continueListening(in: loaded)
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
                Haptics.tap()
            } else {
                currentBookmarkID = try await apiClient.createBookmark(
                    novelId: novel.id,
                    chapterId: currentChapter.id
                ).id
                Haptics.success()
            }
        } catch {
            Haptics.error()
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
        // Listen mode turns chapters on its own; only a manual turn taps.
        if !speech.isActive { Haptics.selection() }
        recordReadingTime()
        loadingChapter = true
        Task {
            defer { loadingChapter = false; lastReadingTick = .now }

            // The list only holds the chapters the reader was opened with plus
            // the current one, so after reading 4 → 10 it is [4, 10]. Its
            // neighbour by position is only trusted when it really is the next
            // chapter number; otherwise fetch that chapter by number.
            let nextIdx = currentIndex + direction
            let listed = navigationChapters.indices.contains(nextIdx) ? navigationChapters[nextIdx] : nil
            let target: Chapter?
            if let listed, Self.isAdjacent(listed, to: currentChapter, direction: direction) {
                target = listed
            } else {
                target = await fetchAdjacentChapterFallback(direction: direction) ?? listed
            }

            guard let target else { speech.chapterUnavailable(); return }
            if offlineOnly {
                guard let loaded = loadOfflineChapter(target) else { speech.chapterUnavailable(); return }
                currentLine = 0
                currentChapter = loaded
                syncReadingPosition()
                continueListening(in: loaded)
                scheduleHideControls()
                return
            }
            currentLine = 0

            let loaded: Chapter
            do {
                let full = try await apiClient.fetchChapter(id: target.id)
                loaded = full
                await OfflineChapterStore.shared.cacheChapter(full)
            } catch {
                if let cached = await OfflineChapterStore.shared.chapter(id: target.id) {
                    loaded = cached
                } else {
                    loaded = target
                }
            }
            currentChapter = loaded
            syncReadingPosition()
            continueListening(in: loaded)
            scheduleHideControls()
        }
    }

    /// True when `candidate` is the chapter straight after (or before) `current`.
    /// Unnumbered chapters can't be checked, so their list order is trusted.
    static func isAdjacent(_ candidate: Chapter, to current: Chapter, direction: Int) -> Bool {
        guard candidate.chapterNumber > 0, current.chapterNumber > 0 else { return true }
        return candidate.chapterNumber == current.chapterNumber + direction
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
            applyInitialLineIfNeeded()
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
        applyInitialLineIfNeeded()
        await loadInitialChapter()
        await MainActor.run {
            restoreScrollPositionIfNeeded()
        }
    }

    private func updateCurrentLineFromOffsets(_ offsets: [Int: CGFloat]) {
        // While listening, the spoken paragraph is the reading position.
        guard !speech.isActive else { return }
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
        let lines = paragraphs
        // Wait for the chapter text; starting on an empty chapter shows 0%.
        guard !lines.isEmpty else { return }
        let start = max(0, min(currentLine, lines.count - 1))
        let wordsLeft = lines[start...].reduce(0) { $0 + $1.split(whereSeparator: \.isWhitespace).count }
        await ReadingLiveActivityManager.shared.startOrUpdate(
            novelTitle: novel.title,
            chapterTitle: currentChapter.title,
            currentLine: currentLine,
            totalLines: lines.count,
            minutesLeft: max(1, Int((Double(wordsLeft) / 230).rounded(.up)))
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

        let novelProgress = NovelProgress(
            chapterNumber: currentChapter.chapterNumber,
            totalChapters: totalChapterCountHint,
            chapterPercentage: NovelProgress.chapterPercentage(
                currentLine: currentLine,
                totalLines: totalLines,
                saved: percentage * 100
            )
        )
        ContinueReadingStore.saveSnapshot(
            ContinueReadingSnapshot(
                novelId: novel.id,
                novelTitle: novel.title,
                chapterId: currentChapter.id,
                chapterTitle: currentChapter.title,
                chapterNumber: currentChapter.chapterNumber,
                progress: novelProgress.fraction,
                chapterProgress: novelProgress.chapterFraction,
                totalChapters: totalChapterCountHint,
                updatedAt: Date(),
                coverURL: novel.imageUrl
            )
        )

        if reloadWidget {
            WidgetCenter.shared.reloadTimelines(ofKind: "ReadingWidget")
        }
        updateHandoffPosition()
    }

    // MARK: - Handoff

    private var canAdvertiseHandoff: Bool {
        !novel.id.hasPrefix("offline-")
            && !handoffPosition.chapterID.isEmpty
            && !handoffPosition.chapterID.hasPrefix("offline-")
    }

    /// Moves the advertised position, at most every few seconds; a chapter
    /// change is published straight away so chapter and line never disagree.
    private func updateHandoffPosition() {
        let next = currentHandoffPosition()
        guard next != handoffPosition else { return }
        handoffUpdateTask?.cancel()
        let elapsed = Date().timeIntervalSince(lastHandoffUpdate)
        if next.chapterID != handoffPosition.chapterID || elapsed >= ReaderHandoff.minimumUpdateInterval {
            handoffPosition = next
            lastHandoffUpdate = .now
            return
        }
        handoffUpdateTask = Task {
            try? await Task.sleep(for: .seconds(ReaderHandoff.minimumUpdateInterval - elapsed))
            guard !Task.isCancelled else { return }
            handoffPosition = currentHandoffPosition()
            lastHandoffUpdate = .now
        }
    }

    private func currentHandoffPosition() -> ReaderHandoffPosition {
        let lineCount = paragraphs.count
        return ReaderHandoffPosition(
            chapterID: currentChapter.id,
            chapterTitle: currentChapter.title,
            line: lineCount > 0 ? min(currentLine, lineCount - 1) : 0,
            lineCount: lineCount
        )
    }

    private func applyInitialLineIfNeeded() {
        guard let initialLine, currentChapter.id == initialChapter.id else { return }
        let line = ReaderHandoff.resolveLine(
            line: initialLine,
            lineCount: initialLineCount,
            progress: initialLineProgress,
            paragraphCount: paragraphs.count
        )
        currentLine = line
        pendingRestoreLine = line
    }

    // MARK: - Listening

    private func connectSpeechCallbacks() {
        speech.onParagraphStart = { index in handleSpokenParagraph(index) }
        speech.onChapterFinished = { handleListeningChapterFinished() }
        speech.onRequestChapter = { direction in handleListeningChapterRequest(direction) }
    }

    private func startListening() {
        let lines = paragraphs
        guard !lines.isEmpty else {
            alertTitle = "Nothing to read aloud"
            downloadAlertMessage = "This chapter has no text yet. Try again once it has loaded."
            showDownloadAlert = true
            return
        }
        connectSpeechCallbacks()
        let start = max(0, min(currentLine, lines.count - 1))
        speech.start(
            paragraphs: lines,
            from: start,
            heading: start == 0 ? currentChapter.labeledTitle : nil,
            novelTitle: novel.title,
            chapterTitle: currentChapter.labeledTitle,
            rate: listenRate,
            artworkURL: novel.imageUrl.flatMap(URL.init(string:))
        )
        scheduleHideControls()
    }

    /// Keeps line tracking, progress sync and the Live Activity moving exactly
    /// as scrolling would, and keeps the spoken paragraph on screen.
    private func handleSpokenParagraph(_ index: Int) {
        guard index >= 0, index < paragraphs.count else { return }
        if index != currentLine {
            currentLine = index
            scheduleProgressSync()
            scheduleReadingLiveActivityUpdate()
        }
        withAnimation(.easeInOut(duration: 0.45)) {
            scrollProxy?.scrollTo(lineAnchorId(for: index), anchor: UnitPoint(x: 0.5, y: 0.22))
        }
    }

    private func handleListeningChapterFinished() {
        guard canNavigateNext else {
            speech.stop()
            return
        }
        navigateChapter(direction: 1)
    }

    private func handleListeningChapterRequest(_ direction: Int) {
        if direction > 0, canNavigateNext {
            navigateChapter(direction: 1)
        } else if direction < 0, canNavigatePrev, shouldShowPrevButton {
            navigateChapter(direction: -1)
        } else {
            speech.chapterUnavailable()
        }
    }

    /// When a chapter opens during a listening session, read it from the top.
    private func continueListening(in chapter: Chapter) {
        guard speech.isActive else { return }
        speech.loadChapter(
            paragraphs: paragraphs(for: chapter),
            heading: chapter.labeledTitle,
            chapterTitle: chapter.labeledTitle
        )
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
            Haptics.success()
        } catch {
            downloadAlertMessage = "Couldn't save chapter to local folder."
            showDownloadAlert = true
            Haptics.error()
        }
    }

    private func refreshCurrentChapterDownloadState() async {
        isCurrentChapterDownloaded = await OfflineChapterStore.shared.isChapterDownloaded(
            novelTitle: novel.title,
            chapterNumber: currentChapter.chapterNumber,
            chapterTitle: currentChapter.title
        )
    }

    private func shouldFilterMetadataLine(_ line: String, chapter: Chapter) -> Bool {
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
        if lowered == chapter.title.lowercased()
            || lowered == chapter.displayTitle.lowercased() {
            return true
        }

        if lowered.range(of: #"^chapter\s*\d+(\s*[:\-].*)?$"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }
}

// MARK: - Listen mode

/// Reads a chapter aloud paragraph by paragraph with AVSpeechSynthesizer.
///
/// Every remaining paragraph of the chapter is queued up front so speech keeps
/// flowing with the screen locked. The lock screen shows the novel and chapter,
/// and remote commands map as follows:
/// - play / pause / toggle: pause and resume at the next word boundary.
/// - next / previous track: next / previous paragraph. At the end (or start)
///   of a chapter they roll into the next (or previous) chapter, so headphone
///   double/triple-clicks behave like skipping a passage in an audiobook.
@MainActor
private final class ReaderSpeechController: NSObject, ObservableObject {
    static let rateRange: ClosedRange<Double> = 0.8...1.6
    static let rateSteps: [Double] = [0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6]

    /// A listening session exists (playing or paused).
    @Published private(set) var isActive = false
    @Published private(set) var isPlaying = false
    @Published private(set) var spokenParagraph: Int?

    var onParagraphStart: ((Int) -> Void)?
    var onChapterFinished: (() -> Void)?
    /// -1 for the previous chapter, +1 for the next.
    var onRequestChapter: ((Int) -> Void)?

    private var synthesizer = AVSpeechSynthesizer()
    private var paragraphs: [String] = []
    private var novelTitle = ""
    private var chapterTitle = ""
    private var rateMultiplier: Float = 1
    private var voice: AVSpeechSynthesisVoice?
    /// Utterances currently queued, keyed to their paragraph (-1 = chapter heading).
    private var queued: [ObjectIdentifier: Int] = [:]
    private var queuedUtterances: [AVSpeechUtterance] = []
    private var lastQueuedParagraph = -1
    private var needsRequeueOnResume = false
    private var awaitingChapter = false
    private var resumeAfterInterruption = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var observers: [NSObjectProtocol] = []
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var artwork: MPMediaItemArtwork?
    private var artworkURL: URL?

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    // MARK: Session

    func start(
        paragraphs: [String],
        from index: Int,
        heading: String?,
        novelTitle: String,
        chapterTitle: String,
        rate: Double,
        artworkURL: URL?
    ) {
        self.paragraphs = paragraphs
        self.novelTitle = novelTitle
        self.chapterTitle = chapterTitle
        rateMultiplier = Float(min(Self.rateRange.upperBound, max(Self.rateRange.lowerBound, rate)))
        voice = Self.preferredVoice(sample: paragraphs.prefix(6).joined(separator: " "))
        if !isActive {
            activateAudioSession()
            observeAudioSession()
            registerRemoteCommands()
        }
        isActive = true
        loadArtwork(artworkURL)
        enqueue(from: index, heading: heading)
    }

    /// Swap in a newly opened chapter. Keeps playing if the session was playing.
    func loadChapter(paragraphs: [String], heading: String?, chapterTitle: String) {
        guard isActive else { return }
        let shouldPlay = isPlaying || awaitingChapter
        awaitingChapter = false
        self.paragraphs = paragraphs
        self.chapterTitle = chapterTitle
        defer { releaseBackgroundTime() }
        guard !paragraphs.isEmpty else { stop(); return }
        if shouldPlay {
            enqueue(from: 0, heading: heading)
        } else {
            clearQueue()
            spokenParagraph = 0
            needsRequeueOnResume = true
            updateNowPlaying()
        }
    }

    /// The reader could not open the chapter that was asked for.
    func chapterUnavailable() {
        guard awaitingChapter else { return }
        stop()
    }

    func stop() {
        guard isActive else { return }
        clearQueue()
        isActive = false
        isPlaying = false
        spokenParagraph = nil
        awaitingChapter = false
        needsRequeueOnResume = false
        resumeAfterInterruption = false
        onParagraphStart = nil
        onChapterFinished = nil
        onRequestChapter = nil
        for (command, target) in commandTargets { command.removeTarget(target) }
        commandTargets.removeAll()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        releaseBackgroundTime()
    }

    // MARK: Transport

    func togglePlayback() {
        isPlaying ? pause() : resume()
    }

    func pause() {
        guard isActive, isPlaying else { return }
        if synthesizer.isSpeaking { synthesizer.pauseSpeaking(at: .word) }
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        guard isActive, !isPlaying else { return }
        activateAudioSession()
        if synthesizer.isPaused, !needsRequeueOnResume {
            synthesizer.continueSpeaking()
            isPlaying = true
            updateNowPlaying()
        } else {
            enqueue(from: spokenParagraph ?? 0, heading: nil)
        }
    }

    /// Steps a paragraph; past either end of the chapter it asks for the adjacent one.
    func skipParagraph(by delta: Int) {
        guard isActive else { return }
        let target = (spokenParagraph ?? 0) + delta
        if target < 0 {
            onRequestChapter?(-1)
        } else if target >= paragraphs.count {
            onRequestChapter?(1)
        } else if isPlaying {
            enqueue(from: target, heading: nil)
        } else {
            clearQueue()
            spokenParagraph = target
            needsRequeueOnResume = true
            onParagraphStart?(target)
            updateNowPlaying()
        }
    }

    func setRate(_ rate: Double) {
        let clamped = Float(min(Self.rateRange.upperBound, max(Self.rateRange.lowerBound, rate)))
        guard clamped != rateMultiplier else { return }
        rateMultiplier = clamped
        guard isActive else { return }
        // Queued utterances keep their rate, so restart the current paragraph.
        if isPlaying {
            enqueue(from: spokenParagraph ?? 0, heading: nil)
        } else {
            needsRequeueOnResume = true
        }
    }

    // MARK: Queue

    private func enqueue(from index: Int, heading: String?) {
        clearQueue()
        guard !paragraphs.isEmpty else { stop(); return }
        let start = max(0, min(index, paragraphs.count - 1))
        spokenParagraph = start
        needsRequeueOnResume = false
        if let heading, !heading.isEmpty, start == 0 {
            let utterance = makeUtterance(heading)
            utterance.postUtteranceDelay = 0.5
            queue(utterance, paragraph: -1)
        }
        for index in start..<paragraphs.count {
            queue(makeUtterance(paragraphs[index]), paragraph: index)
        }
        lastQueuedParagraph = paragraphs.count - 1
        isPlaying = true
        updateNowPlaying()
    }

    private func queue(_ utterance: AVSpeechUtterance, paragraph: Int) {
        queued[ObjectIdentifier(utterance)] = paragraph
        queuedUtterances.append(utterance)
        synthesizer.speak(utterance)
    }

    private func clearQueue() {
        queued.removeAll()
        queuedUtterances.removeAll()
        lastQueuedParagraph = -1
        guard synthesizer.isSpeaking || synthesizer.isPaused else { return }
        // A fresh synthesizer avoids speak() racing the old one's asynchronous stop.
        let old = synthesizer
        old.delegate = nil
        old.stopSpeaking(at: .immediate)
        synthesizer = AVSpeechSynthesizer()
        synthesizer.usesApplicationAudioSession = true
        synthesizer.delegate = self
    }

    private func makeUtterance(_ text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = min(
            AVSpeechUtteranceMaximumSpeechRate,
            max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * rateMultiplier)
        )
        utterance.postUtteranceDelay = 0.15
        return utterance
    }

    fileprivate func utteranceStarted(_ id: ObjectIdentifier) {
        guard let paragraph = queued[id], paragraph >= 0 else { return }
        spokenParagraph = paragraph
        onParagraphStart?(paragraph)
        updateNowPlaying()
    }

    fileprivate func utteranceFinished(_ id: ObjectIdentifier) {
        guard let paragraph = queued.removeValue(forKey: id) else { return }
        queuedUtterances.removeAll { ObjectIdentifier($0) == id }
        guard paragraph == lastQueuedParagraph, queued.isEmpty else { return }
        // Chapter done. Hold a little background time so the next chapter can
        // load with the screen locked, then hand over to the reader.
        awaitingChapter = true
        holdBackgroundTime()
        onChapterFinished?()
    }

    // MARK: Background time

    private func holdBackgroundTime() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Asterion.listen.next-chapter") { [weak self] in
            MainActor.assumeIsolated { self?.releaseBackgroundTime() }
        }
    }

    private func releaseBackgroundTime() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: Audio session

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = AVAudioSession.InterruptionOptions(
                rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            )
            MainActor.assumeIsolated { self?.handleInterruption(type, options: options) }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
        ) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            // Headphones unplugged or disconnected: pause, as every audio app does.
            guard reason == .oldDeviceUnavailable else { return }
            MainActor.assumeIsolated { self?.pause() }
        })
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType?, options: AVAudioSession.InterruptionOptions) {
        switch type {
        case .began:
            resumeAfterInterruption = isPlaying
            pause()
            // The system may have torn down the synthesizer's audio; restart the paragraph on resume.
            needsRequeueOnResume = true
        case .ended:
            if resumeAfterInterruption, options.contains(.shouldResume) { resume() }
            resumeAfterInterruption = false
        default:
            break
        }
    }

    // MARK: Lock screen

    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        let bindings: [(MPRemoteCommand, @MainActor (ReaderSpeechController) -> Void)] = [
            (center.playCommand, { $0.resume() }),
            (center.pauseCommand, { $0.pause() }),
            (center.togglePlayPauseCommand, { $0.togglePlayback() }),
            (center.nextTrackCommand, { $0.skipParagraph(by: 1) }),
            (center.previousTrackCommand, { $0.skipParagraph(by: -1) }),
        ]
        for (command, action) in bindings {
            command.isEnabled = true
            commandTargets.append((command, command.addTarget(handler: Self.remoteHandler(self, action))))
        }
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
    }

    private nonisolated static func remoteHandler(
        _ owner: ReaderSpeechController,
        _ action: @escaping @MainActor (ReaderSpeechController) -> Void
    ) -> (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        { [weak owner] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let owner, owner.isActive else { return }
                    action(owner)
                }
            }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard isActive else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: chapterTitle,
            MPMediaItemPropertyAlbumTitle: novelTitle,
            MPMediaItemPropertyArtist: novelTitle,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        if paragraphs.count > 1, let spokenParagraph {
            info[MPNowPlayingInfoPropertyPlaybackProgress] = Float(spokenParagraph) / Float(paragraphs.count - 1)
        }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(_ url: URL?) {
        guard let url, url != artworkURL else { return }
        artworkURL = url
        artwork = nil
        Task { [weak self] in
            guard let result = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: result.0) else { return }
            guard let self, self.artworkURL == url else { return }
            self.artwork = Self.makeArtwork(image)
            self.updateNowPlaying()
        }
    }

    /// Built outside the main actor: MediaPlayer calls the handler on its own queue.
    private nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    // MARK: Voice

    /// Best installed voice for the text's language, preferring the device's
    /// region and premium or enhanced voices; novelty and personal voices are skipped.
    private static func preferredVoice(sample: String) -> AVSpeechSynthesisVoice? {
        let device = Locale.preferredLanguages.first ?? AVSpeechSynthesisVoice.currentLanguageCode()
        let deviceLocale = Locale(identifier: device)
        var languageCode = deviceLocale.language.languageCode?.identifier ?? String(device.prefix(2))

        // Read novels in the language they are written in when it differs from the device.
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        if let detected = recognizer.dominantLanguage, detected != .undetermined {
            let detectedCode = Locale(identifier: detected.rawValue).language.languageCode?.identifier
                ?? detected.rawValue
            if detectedCode != languageCode { languageCode = detectedCode }
        }

        let region = deviceLocale.region?.identifier ?? Locale.current.region?.identifier
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            !voice.voiceTraits.contains(.isNoveltyVoice)
                && !voice.voiceTraits.contains(.isPersonalVoice)
                && Locale(identifier: voice.language).language.languageCode?.identifier == languageCode
        }
        func score(_ voice: AVSpeechSynthesisVoice) -> Int {
            var value: Int
            switch voice.quality {
            case .premium: value = 300
            case .enhanced: value = 200
            default: value = 100
            }
            let voiceRegion = Locale(identifier: voice.language).region?.identifier
            if let region, voiceRegion == region { value += 20 }
            if voice.language == AVSpeechSynthesisVoice.currentLanguageCode() { value += 10 }
            if voiceRegion == "US" || voiceRegion == "GB" { value += 1 }
            return value
        }
        if let best = candidates.max(by: { score($0) < score($1) }) { return best }
        return AVSpeechSynthesisVoice(language: languageCode) ?? AVSpeechSynthesisVoice(language: device)
    }

    /// One line for the settings sheet describing the voice that will be used.
    static let voiceSummary: String = {
        let device = Locale.preferredLanguages.first ?? AVSpeechSynthesisVoice.currentLanguageCode()
        guard let voice = ReaderSpeechController.preferredVoice(sample: "") ?? AVSpeechSynthesisVoice(language: device) else {
            return "Reads the chapter aloud from where you are, and carries on into the next chapter."
        }
        let quality: String
        switch voice.quality {
        case .premium: quality = "premium"
        case .enhanced: quality = "enhanced"
        default: quality = "standard"
        }
        let base = "Reads aloud with \(voice.name) (\(quality)) and carries on into the next chapter."
        guard voice.quality == .default else { return base }
        return base + " Download an enhanced voice in Settings › Accessibility › Spoken Content for a more natural read."
    }()
}

extension ReaderSpeechController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        DispatchQueue.main.async { MainActor.assumeIsolated { self.utteranceStarted(id) } }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        DispatchQueue.main.async { MainActor.assumeIsolated { self.utteranceFinished(id) } }
    }
}

/// Reader chrome circle that lights up (white disc, dark glyph) while active.
private struct ReaderListenCircle: ViewModifier {
    let isLit: Bool

    func body(content: Content) -> some View {
        if isLit {
            content
                .foregroundStyle(Color.black)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.white))
                .shadow(color: .white.opacity(0.35), radius: 6)
                .contentShape(Circle())
        } else {
            content.modifier(ReaderChromeCircle())
        }
    }
}

/// Smoked glass for controls that float over the page: material, a dark wash,
/// and a hairline, so white icons stay legible on paper, parchment, or night.
private struct ReaderSmokedBackground<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(Color.black.opacity(0.32)))
            }
            .overlay(shape.strokeBorder(Color.white.opacity(0.16)))
            .environment(\.colorScheme, .dark)
    }
}

/// White icon on a smoked circle.
private struct ReaderChromeCircle: ViewModifier {
    var size: CGFloat = 38

    func body(content: Content) -> some View {
        content
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .modifier(ReaderSmokedBackground(shape: Circle()))
            .contentShape(Circle())
    }
}

/// Press and disabled feedback for floating reader controls.
private struct ReaderFloatingButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Capsule drawn in the page's own ink, for controls that sit on the page.
/// The prominent variant inverts: ink fill with paper-coloured text.
private struct ReaderPageCapsuleStyle: ButtonStyle {
    let ink: Color
    let paper: Color
    var isProminent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.asterionReading(14.5, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(isProminent ? paper : ink)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background {
                Capsule().fill(
                    isProminent
                        ? ink.opacity(configuration.isPressed ? 0.8 : 1)
                        : ink.opacity(configuration.isPressed ? 0.12 : 0.05)
                )
            }
            .overlay(Capsule().strokeBorder(ink.opacity(isProminent ? 0 : 0.16)))
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Chapter list on the dark canvas: mono numbers, the open chapter lit.
private struct ReaderChapterPickerSheet: View {
    let chapters: [Chapter]
    let currentChapterID: String
    let onSelect: (Chapter) -> Void
    let onClose: () -> Void

    @State private var query = ""

    private var filteredChapters: [Chapter] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return chapters }
        return chapters.filter {
            String($0.chapterNumber).localizedCaseInsensitiveContains(search)
                || $0.displayTitle.localizedCaseInsensitiveContains(search)
                || $0.title.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    if filteredChapters.isEmpty {
                        AsterionEmptyState(
                            symbol: "magnifyingglass",
                            title: "No chapters found",
                            message: "Try a chapter number or a word from its title."
                        )
                    } else {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredChapters) { chapter in
                                row(chapter)
                                    .id(chapter.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    Task { @MainActor in
                        await Task.yield()
                        proxy.scrollTo(currentChapterID, anchor: .center)
                    }
                }
            }
            .background(Color.asterionBackground)
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Find a chapter")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
                ToolbarItem(placement: .primaryAction) {
                    Text(chapters.count.formatted())
                        .font(.asterionMono(12, weight: .medium))
                        .foregroundStyle(Color.asterionFaint)
                        .accessibilityLabel("\(chapters.count) chapters")
                }
            }
        }
    }

    private func row(_ chapter: Chapter) -> some View {
        let isCurrent = chapter.id == currentChapterID
        let title = chapter.displayTitle.isEmpty ? chapter.labeledTitle : chapter.displayTitle
        return Button {
            onSelect(chapter)
        } label: {
            HStack(spacing: 12) {
                Text(chapter.chapterNumber > 0 ? "\(chapter.chapterNumber)" : "•")
                    .font(.asterionMono(12, weight: .medium))
                    .foregroundStyle(isCurrent ? Color.asterionText : Color.asterionFaint)
                    .frame(width: 44, alignment: .trailing)

                Text(title)
                    .font(.asterionReading(14.5, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.asterionText : Color.asterionText.opacity(0.8))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isCurrent {
                    Circle()
                        .fill(Color.asterionText)
                        .frame(width: 6, height: 6)
                        .shadow(color: .white.opacity(0.7), radius: 3)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isCurrent ? 0.08 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chapter \(chapter.chapterNumber), \(title)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

private struct ParagraphOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}


/// Hairline between the segments of the reader's chapter capsule.
private struct ReaderBarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(width: 1, height: 22)
            .accessibilityHidden(true)
    }
}

/// Chapter progress drawn as a line of light tracing the Dynamic Island.
/// iOS hides the app's own Live Activity while the app is open, so the
/// reader draws it itself. Without an island it is a hairline under the
/// status bar.
private struct ReaderIslandProgress: View {
    let fraction: Double
    let ink: Color

    var body: some View {
        GeometryReader { proxy in
            let topInset = Self.windowTopInset
            let isPortrait = proxy.size.height > proxy.size.width
            if UIDevice.current.userInterfaceIdiom == .phone, isPortrait, topInset >= 54 {
                let rect = Self.islandOutline(width: proxy.size.width, topInset: topInset)
                ZStack {
                    IslandTrace(rect: rect)
                        .stroke(ink.opacity(0.12), lineWidth: 2)
                    IslandTrace(rect: rect)
                        .trim(from: 0, to: max(0.002, fraction))
                        .stroke(ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .shadow(color: ink.opacity(0.55), radius: 4)
                }
            } else {
                Capsule()
                    .fill(ink.opacity(0.85))
                    .frame(width: proxy.size.width * fraction, height: 2)
                    .shadow(color: ink.opacity(0.5), radius: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, max(0, topInset - 2))
            }
        }
        .animation(.easeOut(duration: 0.35), value: fraction)
        .accessibilityHidden(true)
    }

    private static var windowTopInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.top ?? 0
    }

    /// The island is about 126 x 37 pt, centred in the top safe area; the
    /// line runs 3 pt outside it.
    private static func islandOutline(width: CGFloat, topInset: CGFloat) -> CGRect {
        let size = CGSize(width: 126 + 6, height: 37 + 6)
        let centerY = topInset * 0.508
        return CGRect(
            x: (width - size.width) / 2,
            y: centerY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

/// A capsule path that starts at the bottom centre and runs clockwise, so
/// progress grows from beneath the island, up the right and across the top.
private struct IslandTrace: Shape {
    let rect: CGRect

    func path(in _: CGRect) -> Path {
        let radius = rect.height / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.midY),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(-90),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.midY),
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(90),
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}
