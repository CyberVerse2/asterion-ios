import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import AppKit

private enum ReaderTheme: String, CaseIterable, Identifiable {
    case paper
    case sepia
    case ink

    var id: String { rawValue }

    var label: String {
        switch self {
        case .paper: "Paper"
        case .sepia: "Sepia"
        case .ink: "Ink"
        }
    }

    var icon: String {
        switch self {
        case .paper: "sun.max"
        case .sepia: "book.closed"
        case .ink: "moon.fill"
        }
    }

    var preferredColorScheme: ColorScheme { self == .ink ? .dark : .light }

    var palette: ReaderPalette {
        switch self {
        case .paper:
            ReaderPalette(
                background: Color(red: 0.961, green: 0.945, blue: 0.910),
                text: Color(red: 0.122, green: 0.106, blue: 0.086),
                muted: Color(red: 0.420, green: 0.396, blue: 0.357),
                faint: Color(red: 0.659, green: 0.627, blue: 0.584),
                border: Color(red: 0.122, green: 0.106, blue: 0.086).opacity(0.10),
                backgroundHex: "#F5F1E8",
                textHex: "#1F1B16",
                mutedHex: "#6B655B"
            )
        case .sepia:
            ReaderPalette(
                background: Color(red: 0.937, green: 0.890, blue: 0.800),
                text: Color(red: 0.227, green: 0.165, blue: 0.094),
                muted: Color(red: 0.478, green: 0.353, blue: 0.251),
                faint: Color(red: 0.659, green: 0.565, blue: 0.439),
                border: Color(red: 0.227, green: 0.165, blue: 0.094).opacity(0.14),
                backgroundHex: "#EFE3CC",
                textHex: "#3A2A18",
                mutedHex: "#7A5A40"
            )
        case .ink:
            ReaderPalette(
                background: Color(red: 0.059, green: 0.059, blue: 0.063),
                text: Color(red: 0.910, green: 0.902, blue: 0.882),
                muted: Color(red: 0.604, green: 0.588, blue: 0.553),
                faint: Color(red: 0.353, green: 0.345, blue: 0.318),
                border: Color.white.opacity(0.08),
                backgroundHex: "#0F0F10",
                textHex: "#E8E6E1",
                mutedHex: "#5A5851"
            )
        }
    }
}

struct ReaderPalette {
    let background: Color
    let text: Color
    let muted: Color
    let faint: Color
    let border: Color
    let backgroundHex: String
    let textHex: String
    let mutedHex: String
}

struct ReaderView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive
    let route: ReaderRoute

    @AppStorage("readerFontSize") private var fontSize = 19.0
    @AppStorage("readerLineSpacing") private var lineSpacing = 8.0
    @AppStorage("readerColumnWidth") private var columnWidth = 640.0
    @AppStorage("readerTheme") private var readerThemeRawValue = ReaderTheme.ink.rawValue

    @State private var novel: Novel?
    @State private var chapters: [Chapter] = []
    @State private var chapter: Chapter?
    @State private var currentIndex = 0
    @State private var currentLine = 0
    @State private var restoredLine: Int?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var progressTask: Task<Void, Never>?
    @State private var chapterLoadTask: Task<Void, Never>?
    @State private var exportsChapter = false
    @State private var showsChapterPicker = false
    @State private var handoffLine = 0
    @State private var handoffThrottle = AsterionHandoffThrottle()
    @State private var keepsWindowOnTop = false

    private var readerTheme: ReaderTheme {
        ReaderTheme(rawValue: readerThemeRawValue) ?? .ink
    }

    private var palette: ReaderPalette { readerTheme.palette }

    private static let fontSizeRange = 14.0...30.0

    private var canGoToPreviousChapter: Bool { chapter != nil && currentIndex > 0 }
    private var canGoToNextChapter: Bool { chapter != nil && currentIndex < chapters.count - 1 }

    /// What the Reader menu can do in this window.
    private var commandActions: ReaderCommandActions {
        ReaderCommandActions(
            canGoToPreviousChapter: canGoToPreviousChapter,
            canGoToNextChapter: canGoToNextChapter,
            canEnlargeText: fontSize < Self.fontSizeRange.upperBound,
            canShrinkText: fontSize > Self.fontSizeRange.lowerBound,
            showsChapters: showsChapterPicker,
            keepsWindowOnTop: keepsWindowOnTop,
            previousChapter: { navigate(by: -1) },
            nextChapter: { navigate(by: 1) },
            enlargeText: enlargeText,
            shrinkText: shrinkText,
            toggleChapters: { showsChapterPicker.toggle() },
            toggleKeepOnTop: { keepsWindowOnTop.toggle() }
        )
    }

    private func enlargeText() {
        fontSize = min(Self.fontSizeRange.upperBound, fontSize + 1)
    }

    private func shrinkText() {
        fontSize = max(Self.fontSizeRange.lowerBound, fontSize - 1)
    }

    var body: some View {
        Group {
            if isLoading {
                ReaderLoadingView(
                    message: "Opening chapter…",
                    artworkURL: (novel ?? model.novel(id: route.novelID))?.imageURL
                        .flatMap(URL.init(string:)),
                    palette: palette,
                    glowOpacity: readerTheme == .ink ? 0.22 : 0.10
                )
            } else if let errorMessage {
                ReaderMessageView(
                    systemImage: "exclamationmark.triangle",
                    title: "Chapter unavailable",
                    message: errorMessage,
                    palette: palette
                ) {
                    Button {
                        Task { await load() }
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(ReaderCapsuleButtonStyle(palette: palette))
                }
            } else if let chapter {
                reader(chapter)
            }
        }
        .frame(minWidth: 560, minHeight: 560)
        .background(palette.background)
        .mediaWindowPinning(isPinned: keepsWindowOnTop)
        .focusedSceneValue(\.asterionReader, commandActions)
        .preferredColorScheme(readerTheme.preferredColorScheme)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: readerTheme)
        .navigationTitle(chapter?.title ?? "Reader")
        .toolbar { readerToolbar }
        // The centre pill names the novel and chapter; the window title stays
        // for the Window menu but would repeat it in the toolbar.
        .toolbar(removing: .title)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if case .offline = model.chapterListState(for: route.novelID),
                   let notice = model.chapterListState(for: route.novelID).notice {
                    Label(notice, systemImage: "arrow.down.circle.fill")
                        .font(.callout)
                        .foregroundStyle(palette.text)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(.regularMaterial)
                }

                if let error = model.accountError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(Color.asterionWarning)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
        }
        .task(id: route) { await load() }
        .onDisappear {
            progressTask?.cancel()
            chapterLoadTask?.cancel()
            handoffThrottle.cancel()
            syncProgress()
        }
        .userActivity(
            AsterionHandoff.readingActivityType,
            isActive: appearsActive && !isLoading && chapter != nil
        ) { activity in
            guard let chapter else { return }
            let lineCount = chapter.paragraphs.count
            AsterionHandoff.configureReading(
                activity,
                novelID: route.novelID,
                chapterID: chapter.id,
                line: min(handoffLine, max(0, lineCount - 1)),
                lineCount: lineCount,
                novelTitle: novel?.title ?? model.novel(id: route.novelID)?.title ?? "",
                chapterTitle: chapter.displayTitle
            )
        }
        .onChange(of: chapter?.id) { _, _ in
            // A new chapter is a coarse change: advertise it right away.
            handoffThrottle.cancel()
            handoffLine = currentLine
        }
        .onChange(of: AsterionHandoffInbox.shared.readingRequest?.id) { _, requestID in
            // A Handoff for this exact route while the window is already open:
            // reload so the handed-off line is restored.
            guard requestID != nil,
                  AsterionHandoffInbox.shared.readingRequest?.route == route else { return }
            Task { await load() }
        }
        .fileExporter(
            isPresented: $exportsChapter,
            document: chapter.map(PlainTextDocument.init),
            contentType: .plainText,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func reader(_ chapter: Chapter) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if showsChapterPicker {
                    ReaderChapterPicker(
                        chapters: chapters,
                        selectedIndex: currentIndex,
                        palette: palette,
                        onSelect: openChapter,
                        onClose: { showsChapterPicker = false }
                    )
                    .frame(width: 300)
                    .transition(chapterPickerTransition)
                }

                ScrollViewReader { proxy in
                    GeometryReader { geometry in
                        let usesSplitPages = geometry.size.width >= 980

                        if usesSplitPages {
                            ReaderWebSpreadView(
                                novelTitle: novel?.title ?? "Asterion",
                                chapter: chapter,
                                fontSize: fontSize,
                                lineSpacing: lineSpacing,
                                palette: palette,
                                reduceMotion: reduceMotion,
                                initialLine: restoredLine ?? currentLine,
                                onVisibleLineChange: recordVisibleLine,
                                onChapterTurn: navigate
                            )
                        } else {
                            ScrollView {
                                // Paragraph gaps match the two-page spread, so they read as
                                // breaks rather than another wrapped line.
                                LazyVStack(alignment: .leading, spacing: lineSpacing + 14) {
                                    readerHeader(chapter)
                                        .padding(.bottom, 24)

                                    singlePageParagraphs(chapter.paragraphs)

                                    singlePageChapterNavigation
                                        .padding(.top, 28)
                                }
                                .frame(maxWidth: columnWidth, alignment: .leading)
                                .padding(.horizontal, 48)
                                .padding(.top, 52)
                                .padding(.bottom, 32)
                                .frame(maxWidth: .infinity)
                            }
                            .hidingScrollIndicators()
                            .coordinateSpace(name: ReaderScrollCoordinateSpace.name)
                            .onPreferenceChange(ReaderLineFramePreferenceKey.self) {
                                recordVisibleLine(from: $0)
                            }
                            .background(palette.background)
                            .background {
                                SinglePageChapterOverscrollBridge(
                                    canAdvance: currentIndex < chapters.count - 1,
                                    onAdvance: { navigate(by: 1) }
                                )
                            }
                        }
                    }
                    .onChange(of: chapter.id) {
                        proxy.scrollTo(restoredLine ?? 0, anchor: .top)
                        restoredLine = nil
                    }
                    .onAppear {
                        if let restoredLine {
                            proxy.scrollTo(restoredLine, anchor: .top)
                            self.restoredLine = nil
                        }
                    }
                }
            }
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.18),
                value: showsChapterPicker
            )

            ReaderBottomBar(
                progress: chapterProgress,
                label: "\(Int(chapterProgress * 100))% of chapter",
                palette: palette
            )
        }
    }

    @ToolbarContentBuilder
    private var readerToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                navigate(by: -1)
            } label: {
                Label("Previous chapter", systemImage: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(!canGoToPreviousChapter)
            .help("Previous chapter (⌘←)")

            Button {
                navigate(by: 1)
            } label: {
                Label("Next chapter", systemImage: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(!canGoToNextChapter)
            .help("Next chapter (⌘→)")

            Button {
                showsChapterPicker.toggle()
            } label: {
                Label(
                    showsChapterPicker ? "Hide chapters" : "Browse chapters",
                    systemImage: "list.bullet"
                )
            }
            .help(showsChapterPicker ? "Hide chapters" : "Browse chapters")
        }

        if let chapter {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(novel?.title ?? "Asterion")
                        .font(.asterionDisplay(13, weight: .semibold))
                        .foregroundStyle(palette.text)
                    HStack(spacing: 5) {
                        Text(verbatim: "Ch. \(chapter.chapterNumber)")
                            .font(.asterionMono(10.5, weight: .medium))
                        Text("·")
                        Text(Self.toolbarChapterTitle(chapter.displayTitle))
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(palette.muted)
                }
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                // The system capsule sized itself to the novel title and
                // clipped the longer chapter line, so draw our own.
                .glassEffect(.regular, in: .capsule)
                .accessibilityElement(children: .combine)
            }
            .sharedBackgroundVisibility(.hidden)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: shrinkText) {
                Label("Smaller text", systemImage: "textformat.size.smaller")
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(fontSize <= Self.fontSizeRange.lowerBound)
            .help("Smaller text (⌘−)")

            Button(action: enlargeText) {
                Label("Larger text", systemImage: "textformat.size.larger")
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(fontSize >= Self.fontSizeRange.upperBound)
            .help("Larger text (⌘+)")
        }

        ToolbarSpacer(.fixed)

        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: $keepsWindowOnTop) {
                Label(
                    keepsWindowOnTop ? "Stop keeping window on top" : "Keep window on top",
                    systemImage: keepsWindowOnTop ? "pin.fill" : "pin"
                )
            }
            .toggleStyle(.button)
            .help(keepsWindowOnTop ? "Stop keeping window on top" : "Keep window on top")

            ReaderThemeMenu(
                theme: readerTheme,
                onSelect: { readerThemeRawValue = $0.rawValue }
            )

            Button {
                exportsChapter = true
            } label: {
                Label("Save chapter", systemImage: "square.and.arrow.down")
            }
            .help("Save chapter")
        }
    }

    private func readerHeader(_ chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "Chapter \(chapter.chapterNumber)")
                .font(.asterionMono(12, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(palette.faint)
            Text(chapter.displayTitle)
                .font(.asterionReading(32, weight: .semibold))
                .foregroundStyle(palette.text)
                .textSelection(.enabled)
        }
    }

    /// Keeps the toolbar pill a sensible width for very long chapter titles.
    static func toolbarChapterTitle(_ title: String) -> String {
        let limit = 44
        guard title.count > limit else { return title }
        return String(title.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func singlePageParagraphs(_ paragraphs: [String]) -> some View {
        ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
            paragraphText(paragraph, index: index)
        }
    }

    private var singlePageChapterNavigation: some View {
        VStack(spacing: 18) {
            Rectangle()
                .fill(palette.border)
                .frame(height: 1)

            HStack(spacing: 14) {
                Button {
                    navigate(by: -1)
                } label: {
                    Label("Previous chapter", systemImage: "chevron.left")
                }
                .disabled(currentIndex <= 0)

                Spacer(minLength: 20)

                VStack(spacing: 3) {
                    Text("End of chapter")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.faint)
                    if !chapters.isEmpty {
                        Text("\(currentIndex + 1) of \(chapters.count)")
                            .font(.asterionMono(11, weight: .medium))
                            .foregroundStyle(palette.faint)
                    }
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 20)

                Button {
                    navigate(by: 1)
                } label: {
                    HStack(spacing: 7) {
                        Text("Next chapter")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                }
                .disabled(currentIndex >= chapters.count - 1)
                .accessibilityLabel("Next chapter")
            }
            .buttonStyle(ReaderCapsuleButtonStyle(palette: palette))
        }
        .accessibilityElement(children: .contain)
    }

    private func paragraphText(_ paragraph: String, index: Int) -> some View {
        Text(paragraph)
            .font(.asterionReading(fontSize))
            .foregroundStyle(palette.text)
            .lineSpacing(lineSpacing)
            .textSelection(.enabled)
            .id(index)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ReaderLineFramePreferenceKey.self,
                        value: [
                            index: geometry.frame(
                                in: .named(ReaderScrollCoordinateSpace.name)
                            ),
                        ]
                    )
                }
            }
    }

    private var chapterPickerTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity)
    }

    private var chapterProgress: Double {
        guard let chapter else { return 0 }
        let total = max(chapter.paragraphs.count - 1, 1)
        return min(1, max(0, Double(currentLine) / Double(total)))
    }

    private var exportFilename: String {
        guard let chapter else { return "Asterion Chapter" }
        return "\(chapter.chapterNumber) - \(chapter.displayTitle)"
            .replacingOccurrences(of: "[/\\:]", with: "-", options: .regularExpression)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let loadedNovel = resolvedNovel()
            async let loadedChapter = model.chapter(id: route.chapterID)
            async let loadedProgress = optionalProgress()

            let chapter = try await loadedChapter
            novel = try await loadedNovel
            self.chapter = chapter
            let paragraphCount = chapter.paragraphs.count
            let lastLine = max(0, paragraphCount - 1)
            if let handoffLine = AsterionHandoffInbox.shared.takeReaderLine(
                for: route,
                paragraphCount: paragraphCount
            ) {
                restoredLine = min(handoffLine, lastLine)
                currentLine = restoredLine ?? 0
            } else if let progress = await loadedProgress, progress.chapterId == route.chapterID {
                restoredLine = min(progress.currentLine, lastLine)
                currentLine = restoredLine ?? 0
            }
            handoffLine = currentLine
            isLoading = false
            preloadNeighborChapters(around: chapter)

            await loadChapterList(selecting: chapter.id)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func resolvedNovel() async throws -> Novel? {
        if let cached = model.novel(id: route.novelID) {
            return cached
        }
        return try await model.api.fetchNovel(id: route.novelID)
    }

    private func optionalProgress() async -> ReadingProgress? {
        try? await model.fetchProgress(novelID: route.novelID)
    }

    private func loadChapterList(selecting chapterID: String) async {
        guard let loadedChapters = try? await model.chapters(for: route.novelID) else { return }
        chapters = loadedChapters
        if let index = loadedChapters.firstIndex(where: { $0.id == chapterID }) {
            currentIndex = index
        }
        preloadNeighborChapters()
    }

    private func navigate(by offset: Int) {
        let targetIndex = currentIndex + offset
        openChapter(at: targetIndex, startsAtEnd: offset < 0)
    }

    private func openChapter(at index: Int) {
        openChapter(at: index, startsAtEnd: false)
    }

    private func openChapter(at targetIndex: Int, startsAtEnd: Bool) {
        guard chapters.indices.contains(targetIndex), targetIndex != currentIndex else { return }
        syncProgress()
        progressTask?.cancel()
        chapterLoadTask?.cancel()
        currentIndex = targetIndex
        currentLine = startsAtEnd ? .max : 0
        restoredLine = currentLine
        chapterLoadTask = Task {
            do {
                let loadedChapter = try await model.chapter(id: chapters[targetIndex].id)
                guard !Task.isCancelled, currentIndex == targetIndex else { return }
                if startsAtEnd {
                    let lastLine = max(0, loadedChapter.paragraphs.count - 1)
                    currentLine = lastLine
                    restoredLine = lastLine
                }
                chapter = loadedChapter
                errorMessage = nil
                preloadNeighborChapters()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func recordVisibleLine(_ line: Int) {
        guard line != currentLine else { return }
        currentLine = line
        handoffThrottle.submit { handoffLine = line }
        progressTask?.cancel()
        progressTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            syncProgress()
        }
    }

    private func recordVisibleLine(from frames: [Int: CGRect]) {
        let viewportTop: CGFloat = 1
        let intersectingLine = frames
            .filter { $0.value.minY <= viewportTop && $0.value.maxY > viewportTop }
            .min { $0.key < $1.key }?.key
        let nextLine = frames
            .filter { $0.value.minY > viewportTop }
            .min { $0.value.minY < $1.value.minY }?.key

        if let visibleLine = intersectingLine ?? nextLine {
            recordVisibleLine(visibleLine)
        }
    }

    private func syncProgress() {
        guard let chapter,
              chapters.indices.contains(currentIndex),
              chapter.id == chapters[currentIndex].id
        else { return }
        let line = currentLine
        let total = max(chapter.paragraphs.count, 1)
        Task {
            await model.saveProgress(
                novelID: route.novelID,
                chapterID: chapter.id,
                currentLine: line,
                totalLines: total
            )
        }
    }

    private func preloadNeighborChapters(around chapter: Chapter? = nil) {
        if chapters.isEmpty, let chapter {
            let previousNumber = chapter.chapterNumber - 1
            let nextNumber = chapter.chapterNumber + 1
            model.prefetchChapter(novelID: route.novelID, number: nextNumber)
            if previousNumber >= 1 {
                model.prefetchChapter(novelID: route.novelID, number: previousNumber)
            }
            return
        }

        if chapters.indices.contains(currentIndex + 1) {
            model.prefetchChapter(id: chapters[currentIndex + 1].id)
        }
        if chapters.indices.contains(currentIndex - 1) {
            model.prefetchChapter(id: chapters[currentIndex - 1].id)
        }
    }
}

private enum ReaderScrollCoordinateSpace {
    static let name = "reader-scroll"
}

private struct ReaderLineFramePreferenceKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct ReaderThemeMenu: View {
    let theme: ReaderTheme
    let onSelect: (ReaderTheme) -> Void

    var body: some View {
        Menu {
            ForEach(ReaderTheme.allCases) { option in
                Button {
                    onSelect(option)
                } label: {
                    Label(option.label, systemImage: option == theme ? "checkmark" : option.icon)
                }
            }
        } label: {
            Label("Reading theme", systemImage: theme.icon)
        }
        .help("Theme: \(theme.label)")
    }
}

/// Calm loading state drawn in the reader's own palette, faintly lit by the
/// novel's cover when one is known.
private struct ReaderLoadingView: View {
    let message: String
    let artworkURL: URL?
    let palette: ReaderPalette
    let glowOpacity: Double

    var body: some View {
        ZStack {
            palette.background

            if artworkURL != nil {
                ArtworkToneReader(url: artworkURL) { tone in
                    RadialGradient(
                        colors: [tone.opacity(glowOpacity), tone.opacity(glowOpacity * 0.2), .clear],
                        center: .center,
                        startRadius: 4,
                        endRadius: 320
                    )
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.muted)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Empty or error state that follows the reader palette rather than the
/// dark media canvas.
private struct ReaderMessageView<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    let palette: ReaderPalette
    @ViewBuilder var actions: () -> Actions

    init(
        systemImage: String,
        title: String,
        message: String,
        palette: ReaderPalette,
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.palette = palette
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(palette.muted)
                .frame(width: 72, height: 72)
                .background(palette.text.opacity(0.05), in: Circle())
                .padding(.bottom, 2)

            Text(title)
                .font(.asterionTitle(19))
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 13.5))
                .foregroundStyle(palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .fixedSize(horizontal: false, vertical: true)

            actions()
                .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The reader's take on the smoked capsule: tinted from the active palette
/// so it sits naturally on paper, sepia, or ink.
private struct ReaderCapsuleButtonStyle: ButtonStyle {
    let palette: ReaderPalette

    func makeBody(configuration: Configuration) -> some View {
        ReaderCapsuleButtonBody(configuration: configuration, palette: palette)
    }
}

private struct ReaderCapsuleButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let palette: ReaderPalette
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .labelStyle(ReaderCapsuleLabelStyle())
            .foregroundStyle(palette.text.opacity(isEnabled ? 1 : 0.35))
            .padding(.horizontal, 16)
            .frame(minHeight: 36)
            .background {
                Capsule()
                    .fill(
                        palette.text.opacity(
                            configuration.isPressed ? 0.12 : (isHovering && isEnabled ? 0.08 : 0.045)
                        )
                    )
            }
            .overlay(Capsule().strokeBorder(palette.border))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovering)
            .contentShape(Capsule())
            .onHover { isHovering = $0 }
    }
}

private struct ReaderCapsuleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.icon
                .font(.system(size: 11, weight: .bold))
            configuration.title
        }
    }
}

private struct ReaderBottomBar: View {
    let progress: Double
    let label: String
    let palette: ReaderPalette

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(palette.border)
                    Rectangle()
                        .fill(palette.muted)
                        .frame(width: geometry.size.width * min(1, max(0, progress)))
                }
            }
            .frame(height: 2)

            HStack {
                Text(label)
                    .font(.asterionMono(10.5, weight: .medium))
                    .foregroundStyle(palette.faint)
                Spacer()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            palette.background
                .overlay(alignment: .top) {
                    Rectangle().fill(palette.border).frame(height: 0.5)
                }
        )
    }
}

private struct ReaderWebSpreadView: View {
    let novelTitle: String
    let chapter: Chapter
    let fontSize: Double
    let lineSpacing: Double
    let palette: ReaderPalette
    let reduceMotion: Bool
    let initialLine: Int
    let onVisibleLineChange: (Int) -> Void
    let onChapterTurn: (Int) -> Void

    @State private var model = ReaderWebSpreadModel()

    var body: some View {
        let html = makeHTML()

        ZStack {
            WebView(model.page)

            if let loadError = model.loadError {
                ReaderMessageView(
                    systemImage: "exclamationmark.triangle",
                    title: "Reader unavailable",
                    message: loadError,
                    palette: palette
                )
                .background(palette.background)
            }
        }
        .background {
            ReaderSpreadKeyMonitor { direction in
                Task { await model.turnPage(direction) }
            }
        }
        .task(id: html) {
            model.configure(
                onVisibleLineChange: onVisibleLineChange,
                onChapterTurn: onChapterTurn
            )
            await model.load(html: html, initialLine: initialLine)
        }
    }

    private func makeHTML() -> String {
        let effectiveFontSize = max(fontSize + 2, fontSize * 1.12)
        let effectiveLineHeight = max(1.35, (effectiveFontSize + lineSpacing) / effectiveFontSize)
        let paragraphs = chapter.paragraphs.enumerated().map { index, paragraph in
            "<p data-line=\"\(index)\">\(paragraph.htmlEscaped)</p>"
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root {
              --asterion-accent: #9A968D;
              --asterion-bg: \(palette.backgroundHex);
              --asterion-text: \(palette.textHex);
              --asterion-muted: \(palette.mutedHex);
              --asterion-page-gap: 32px;
              --asterion-page-width: 50%;
              --asterion-page-inset: 40px;
            }
            html, body {
              width: 100%;
              height: 100%;
              margin: 0;
              background: var(--asterion-bg);
              color: var(--asterion-text);
              scrollbar-color: transparent transparent;
              scrollbar-width: none;
            }
            body {
              box-sizing: border-box;
              padding: 52px 0 36px;
              font-family: Georgia, "Times New Roman", serif;
              font-size: \(effectiveFontSize)px;
              line-height: \(String(format: "%.2f", effectiveLineHeight));
              column-width: var(--asterion-page-width);
              column-gap: var(--asterion-page-gap);
              column-fill: auto;
              height: 100%;
              overflow-x: auto;
              overflow-y: hidden;
              overscroll-behavior-x: none;
            }
            html::-webkit-scrollbar,
            body::-webkit-scrollbar,
            *::-webkit-scrollbar {
              width: 0 !important;
              height: 0 !important;
              display: none;
              background: transparent;
            }
            html::-webkit-scrollbar-thumb,
            body::-webkit-scrollbar-thumb,
            *::-webkit-scrollbar-thumb {
              background: transparent;
            }
            header, p {
              box-sizing: border-box;
              padding-left: var(--asterion-page-inset);
              padding-right: var(--asterion-page-inset);
              -webkit-box-decoration-break: clone;
              box-decoration-break: clone;
            }
            header {
              break-inside: avoid-column;
              margin-bottom: 28px;
            }
            .novel {
              margin: 0 0 16px;
              color: var(--asterion-muted);
              font: 700 12px -apple-system, BlinkMacSystemFont, sans-serif;
              letter-spacing: 0.22em;
              text-transform: uppercase;
            }
            h1 {
              margin: 0;
              max-width: 820px;
              font-size: 38px;
              line-height: 1.15;
              font-weight: 700;
            }
            p {
              margin: 0 0 \(Int(lineSpacing + 14))px;
              overflow-wrap: break-word;
              word-break: normal;
              text-align: justify;
              hyphens: auto;
              -webkit-hyphens: auto;
              widows: 2;
              orphans: 2;
            }
            #asterion-column-pad {
              display: none;
              break-before: column;
              -webkit-column-break-before: always;
              height: 100%;
              visibility: hidden;
              pointer-events: none;
            }
          </style>
        </head>
        <body>
          <header>
            <p class="novel">\(novelTitle.htmlEscaped)</p>
            <h1>\(chapter.displayTitle.htmlEscaped)</h1>
          </header>
          \(paragraphs)
          <div id="asterion-column-pad" aria-hidden="true"></div>
          <script>
            (() => {
              const scroller = document.body;
              const pad = document.getElementById('asterion-column-pad');
              const preferredScrollBehavior = '\(reduceMotion ? "instant" : "smooth")';

              const applyMetrics = () => {
                const viewport = scroller.clientWidth || window.innerWidth;
                const gap = Math.round(Math.min(48, Math.max(20, viewport * 0.025)));
                const inset = Math.round(Math.min(64, Math.max(24, viewport * 0.03)));
                const pageWidth = Math.max(320, Math.floor((viewport - gap) / 2));
                const pageUnit = pageWidth + gap;
                const root = document.documentElement;
                root.style.setProperty('--asterion-page-gap', gap + 'px');
                root.style.setProperty('--asterion-page-width', pageWidth + 'px');
                root.style.setProperty('--asterion-page-inset', inset + 'px');
                return { viewport, gap, pageWidth, pageUnit, turnUnit: pageUnit * 2 };
              };

              const columnCount = (metrics) => {
                return Math.max(1, Math.round((scroller.scrollWidth + metrics.gap) / metrics.pageUnit));
              };

              const syncColumnPad = () => {
                pad.style.display = 'none';
                void scroller.offsetWidth;
                const before = applyMetrics();
                pad.style.display = columnCount(before) % 2 === 1 ? 'block' : 'none';
                void scroller.offsetWidth;
                return applyMetrics();
              };

              const pageMetrics = () => {
                const metrics = applyMetrics();
                const columns = columnCount(metrics);
                return {
                  ...metrics,
                  turnCount: Math.max(1, Math.round(columns / 2)),
                  maxX: Math.max(0, scroller.scrollWidth - metrics.viewport),
                };
              };

              const currentTurn = () => {
                const { turnUnit, turnCount } = pageMetrics();
                return Math.max(0, Math.min(turnCount - 1, Math.round(scroller.scrollLeft / turnUnit)));
              };

              const scrollToTurn = (turn, behavior = preferredScrollBehavior) => {
                const { turnUnit, maxX, turnCount } = pageMetrics();
                const target = Math.max(0, Math.min(turnCount - 1, Math.round(turn)));
                scroller.scrollTo({
                  left: Math.min(maxX, target * turnUnit),
                  top: 0,
                  behavior,
                });
              };

              const turnPage = (direction) => {
                syncColumnPad();
                const { turnCount } = pageMetrics();
                const turn = currentTurn();
                if (direction > 0 && turn >= turnCount - 1) {
                  window.webkit.messageHandlers.asterionProgress.postMessage({ type: 'turn', offset: 1 });
                  return;
                }
                if (direction < 0 && turn <= 0) {
                  window.webkit.messageHandlers.asterionProgress.postMessage({ type: 'turn', offset: -1 });
                  return;
                }
                scrollToTurn(turn + direction);
              };

              const reportProgress = () => {
                const probeX = Math.max(48, (scroller.clientWidth || window.innerWidth) * 0.08);
                const probeY = 96;
                let bestLine = 0;
                let bestDistance = Infinity;
                document.querySelectorAll('[data-line]').forEach((node) => {
                  const rect = node.getBoundingClientRect();
                  const dx = Math.max(rect.left - probeX, 0, probeX - rect.right);
                  const dy = Math.max(rect.top - probeY, 0, probeY - rect.bottom);
                  const distance = dx + dy;
                  if (distance < bestDistance) {
                    bestDistance = distance;
                    bestLine = Number(node.dataset.line) || 0;
                  }
                });
                window.webkit.messageHandlers.asterionProgress.postMessage({ type: 'progress', line: bestLine });
              };

              const restoreLine = (line) => {
                syncColumnPad();
                const target = document.querySelector('[data-line="' + String(line) + '"]');
                if (!target) {
                  scrollToTurn(0, 'instant');
                  reportProgress();
                  return;
                }
                const { turnUnit, turnCount } = pageMetrics();
                const left = target.getBoundingClientRect().left + scroller.scrollLeft;
                scrollToTurn(
                  Math.max(0, Math.min(turnCount - 1, Math.round(left / turnUnit))),
                  'instant'
                );
                reportProgress();
              };

              window.__asterionRestoreLine = (line) => {
                const run = () => restoreLine(line);
                const afterLayout = () => requestAnimationFrame(() => requestAnimationFrame(run));
                if (document.fonts && document.fonts.ready) {
                  document.fonts.ready.then(afterLayout, afterLayout);
                } else {
                  afterLayout();
                }
              };
              window.__asterionTurnPage = turnPage;

              window.addEventListener('wheel', (event) => {
                if (Math.abs(event.deltaY) <= Math.abs(event.deltaX)) return;
                event.preventDefault();
                turnPage(event.deltaY > 0 ? 1 : -1);
              }, { passive: false });

              window.addEventListener('keydown', (event) => {
                if (event.key === 'ArrowRight' || event.key === 'PageDown' || event.key === ' ') {
                  event.preventDefault();
                  turnPage(1);
                }
                if (event.key === 'ArrowLeft' || event.key === 'PageUp') {
                  event.preventDefault();
                  turnPage(-1);
                }
              });

              window.addEventListener('scroll', () => window.requestAnimationFrame(reportProgress), { passive: true });
              window.addEventListener('resize', () => {
                syncColumnPad();
                scrollToTurn(currentTurn(), 'instant');
              });
              syncColumnPad();
              reportProgress();
            })();
          </script>
        </body>
        </html>
        """
    }
}

@MainActor
@Observable
private final class ReaderWebSpreadModel {
    let page: WebPage
    private let messageHandler: ReaderScriptMessageHandler
    private(set) var loadError: String?

    init() {
        let messageHandler = ReaderScriptMessageHandler()
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(
            messageHandler,
            name: ReaderScriptMessageHandler.name
        )
        self.messageHandler = messageHandler
        page = WebPage(configuration: configuration)
    }

    func configure(
        onVisibleLineChange: @escaping (Int) -> Void,
        onChapterTurn: @escaping (Int) -> Void
    ) {
        messageHandler.onVisibleLineChange = onVisibleLineChange
        messageHandler.onChapterTurn = onChapterTurn
    }

    func load(html: String, initialLine: Int) async {
        loadError = nil
        do {
            for try await event in page.load(html: html) {
                guard event == .finished else { continue }
                _ = try await page.callJavaScript(
                    "window.__asterionRestoreLine(line);",
                    arguments: ["line": initialLine]
                )
            }
        } catch {
            guard !Task.isCancelled else { return }
            loadError = error.localizedDescription
        }
    }

    func turnPage(_ direction: Int) async {
        _ = try? await page.callJavaScript(
            "window.__asterionTurnPage(direction);",
            arguments: ["direction": direction]
        )
    }
}

@MainActor
private final class ReaderScriptMessageHandler: NSObject, WKScriptMessageHandler {
    static let name = "asterionProgress"

    var onVisibleLineChange: ((Int) -> Void)?
    var onChapterTurn: ((Int) -> Void)?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.name else { return }
        if let line = message.body as? Int {
            onVisibleLineChange?(line)
            return
        }
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String
        else { return }

        if type == "progress", let line = body["line"] as? Int {
            onVisibleLineChange?(line)
        } else if type == "turn", let offset = body["offset"] as? Int {
            onChapterTurn?(offset)
        }
    }
}

private extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

private struct ReaderSpreadKeyMonitor: NSViewRepresentable {
    var turn: (Int) -> Void

    func makeNSView(context: Context) -> ReaderSpreadKeyView {
        let view = ReaderSpreadKeyView()
        view.turn = turn
        return view
    }

    func updateNSView(_ view: ReaderSpreadKeyView, context: Context) {
        view.turn = turn
    }
}

private final class ReaderSpreadKeyView: NSView {
    var turn: ((Int) -> Void)?
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        window?.makeFirstResponder(self)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.shouldHandle(event) else { return event }
            return nil
        }
    }

    override func keyDown(with event: NSEvent) {
        if shouldHandle(event) { return }
        super.keyDown(with: event)
    }

    private func shouldHandle(_ event: NSEvent) -> Bool {
        guard let window, event.windowNumber == window.windowNumber, window.isKeyWindow else {
            return false
        }
        if Self.isEditingText(in: window) { return false }
        guard case .turn(let direction) = ReaderSpreadKeyboardCommand.resolve(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags
        ) else {
            return false
        }
        turn?(direction)
        return true
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private static func isEditingText(in window: NSWindow) -> Bool {
        guard let responder = window.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }
}

private struct PlainTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    let text: String

    init(chapter: Chapter) {
        text = "\(chapter.displayTitle)\n\n\(chapter.plainContent)"
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// The reader window's commands, published to the Reader menu while its
/// window is key.
struct ReaderCommandActions {
    var canGoToPreviousChapter: Bool
    var canGoToNextChapter: Bool
    var canEnlargeText: Bool
    var canShrinkText: Bool
    var showsChapters: Bool
    var keepsWindowOnTop: Bool
    var previousChapter: () -> Void
    var nextChapter: () -> Void
    var enlargeText: () -> Void
    var shrinkText: () -> Void
    var toggleChapters: () -> Void
    var toggleKeepOnTop: () -> Void
}

extension FocusedValues {
    @Entry var asterionReader: ReaderCommandActions?
}

/// The Reader menu: chapter turns, text size and window pinning, with the
/// same shortcuts as the reader's toolbar. Disabled outside a reader window.
struct AsterionReaderCommands: Commands {
    @FocusedValue(\.asterionReader) private var reader

    var body: some Commands {
        CommandMenu("Reader") {
            Button("Previous Chapter") { reader?.previousChapter() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(reader?.canGoToPreviousChapter != true)
            Button("Next Chapter") { reader?.nextChapter() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(reader?.canGoToNextChapter != true)

            Divider()

            Button("Larger Text") { reader?.enlargeText() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(reader?.canEnlargeText != true)
            Button("Smaller Text") { reader?.shrinkText() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(reader?.canShrinkText != true)

            Divider()

            Button(reader?.showsChapters == true ? "Hide Chapters" : "Show Chapters") {
                reader?.toggleChapters()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(reader == nil)
            Button(reader?.keepsWindowOnTop == true ? "Stop Keeping Window on Top" : "Keep Window on Top") {
                reader?.toggleKeepOnTop()
            }
            .disabled(reader == nil)
        }
    }
}
