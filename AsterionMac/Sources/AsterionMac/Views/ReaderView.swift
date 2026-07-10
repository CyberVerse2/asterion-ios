import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

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

    private var readerTheme: ReaderTheme {
        ReaderTheme(rawValue: readerThemeRawValue) ?? .ink
    }

    private var palette: ReaderPalette { readerTheme.palette }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Opening chapter…")
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Chapter unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else if let chapter {
                reader(chapter)
            }
        }
        .frame(minWidth: 560, minHeight: 560)
        .background(palette.background)
        .preferredColorScheme(readerTheme.preferredColorScheme)
        .animation(.easeInOut(duration: 0.3), value: readerTheme)
        .navigationTitle(chapter?.title ?? "Reader")
        .safeAreaInset(edge: .bottom) {
            if let error = model.accountError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Color.asterionAccent)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .task(id: route) { await load() }
        .onDisappear {
            progressTask?.cancel()
            chapterLoadTask?.cancel()
            syncProgress()
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
            ReaderTopBar(
                novelTitle: novel?.title ?? "Asterion",
                chapterTitle: chapter.displayTitle,
                chapterNumber: chapter.chapterNumber,
                canGoBack: currentIndex > 0,
                canGoForward: currentIndex < chapters.count - 1,
                onBack: { navigate(by: -1) },
                onForward: { navigate(by: 1) },
                showsChapterPicker: showsChapterPicker,
                onToggleChapterPicker: { showsChapterPicker.toggle() },
                onSmallerText: { fontSize = max(14, fontSize - 1) },
                onLargerText: { fontSize = min(30, fontSize + 1) },
                theme: readerTheme,
                palette: palette,
                onThemeChange: { readerThemeRawValue = $0.rawValue },
                onExport: { exportsChapter = true }
            )

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
                    .transition(.move(edge: .leading).combined(with: .opacity))
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
                                initialLine: restoredLine ?? currentLine,
                                onVisibleLineChange: recordVisibleLine,
                                onChapterTurn: navigate
                            )
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: lineSpacing) {
                                    readerHeader(chapter)
                                        .padding(.bottom, 24)

                                    singlePageParagraphs(chapter.paragraphs)
                                }
                                .frame(maxWidth: columnWidth, alignment: .leading)
                                .padding(.horizontal, 48)
                                .padding(.top, 52)
                                .padding(.bottom, 32)
                                .frame(maxWidth: .infinity)
                            }
                            .hidingScrollIndicators()
                            .background(palette.background)
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
            .animation(.easeInOut(duration: 0.18), value: showsChapterPicker)

            ReaderBottomBar(
                progress: chapterProgress,
                label: "\(Int(chapterProgress * 100))% of chapter",
                palette: palette
            )
        }
    }

    private func readerHeader(_ chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(novel?.title.uppercased() ?? "ASTERION")
                .font(.caption.weight(.medium))
                .tracking(1.5)
                .foregroundStyle(palette.faint)
            Text(chapter.displayTitle)
                .font(.asterionReading(32, weight: .semibold))
                .foregroundStyle(palette.text)
                .textSelection(.enabled)
        }
    }

    private func singlePageParagraphs(_ paragraphs: [String]) -> some View {
        ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
            paragraphText(paragraph, index: index)
        }
    }

    private func paragraphText(_ paragraph: String, index: Int) -> some View {
        Text(paragraph)
            .font(.asterionReading(fontSize))
            .foregroundStyle(palette.text)
            .lineSpacing(lineSpacing)
            .textSelection(.enabled)
            .id(index)
            .onAppear { recordVisibleLine(index) }
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
        defer { isLoading = false }
        do {
            if let cachedNovel = model.novel(id: route.novelID) {
                novel = cachedNovel
            } else {
                novel = try await model.api.fetchNovel(id: route.novelID)
            }
            chapters = try await model.chapters(for: route.novelID)
            guard let index = chapters.firstIndex(where: { $0.id == route.chapterID }) else {
                throw APIError.invalidResponse
            }
            currentIndex = index
            chapter = try await model.chapter(id: route.chapterID)
            if let progress = try await model.fetchProgress(novelID: route.novelID), progress.chapterId == route.chapterID {
                restoredLine = min(progress.currentLine, max(0, chapter?.paragraphs.count ?? 1) - 1)
                currentLine = restoredLine ?? 0
            }
            errorMessage = nil
            preloadNeighborChapters()
        } catch {
            errorMessage = error.localizedDescription
        }
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
        currentLine = line
        progressTask?.cancel()
        progressTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            syncProgress()
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

    private func preloadNeighborChapters() {
        let neighborIDs = [currentIndex - 1, currentIndex + 1]
            .filter { chapters.indices.contains($0) }
            .map { chapters[$0].id }
        guard !neighborIDs.isEmpty else { return }
        Task {
            for id in neighborIDs {
                _ = try? await model.chapter(id: id)
            }
        }
    }
}

private struct ReaderTopBar: View {
    let novelTitle: String
    let chapterTitle: String
    let chapterNumber: Int
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let showsChapterPicker: Bool
    let onToggleChapterPicker: () -> Void
    let onSmallerText: () -> Void
    let onLargerText: () -> Void
    let theme: ReaderTheme
    let palette: ReaderPalette
    let onThemeChange: (ReaderTheme) -> Void
    let onExport: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(novelTitle)
                    .font(.asterionDisplay(14, weight: .medium))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Text("Chapter \(chapterNumber) · \(chapterTitle)")
                    .font(.system(size: 11, weight: .regular))
                    .tracking(0.4)
                    .foregroundStyle(palette.faint)
                    .lineLimit(1)
            }
            .frame(maxWidth: 560)

            HStack(spacing: 8) {
                ReaderChromeButton(systemImage: "chevron.left", help: "Previous chapter", palette: palette, action: onBack)
                    .disabled(!canGoBack)
                ReaderChromeButton(systemImage: "chevron.right", help: "Next chapter", palette: palette, action: onForward)
                    .disabled(!canGoForward)
                ReaderChromeButton(
                    systemImage: "list.bullet",
                    help: showsChapterPicker ? "Hide chapters" : "Browse chapters",
                    palette: palette,
                    isSelected: showsChapterPicker,
                    action: onToggleChapterPicker
                )

                Spacer(minLength: 0)

                ReaderChromeButton(systemImage: "textformat.size.smaller", help: "Smaller text", palette: palette, action: onSmallerText)
                ReaderChromeButton(systemImage: "textformat.size.larger", help: "Larger text", palette: palette, action: onLargerText)
                ReaderThemeMenu(theme: theme, palette: palette, onSelect: onThemeChange)
                ReaderChromeButton(systemImage: "square.and.arrow.down", help: "Save chapter", palette: palette, action: onExport)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            palette.background
                .overlay(alignment: .bottom) {
                    Rectangle().fill(palette.border).frame(height: 0.5)
                }
        )
    }
}

private struct ReaderChromeButton: View {
    let systemImage: String
    let help: String
    let palette: ReaderPalette
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? palette.text : palette.muted)
                .frame(width: 30, height: 30)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(palette.text.opacity(0.10))
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(palette.text.opacity(0.22), lineWidth: 0.75)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct ReaderThemeMenu: View {
    let theme: ReaderTheme
    let palette: ReaderPalette
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
            Image(systemName: theme.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.text)
                .frame(width: 32, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.text.opacity(0.10))
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(palette.text.opacity(0.24), lineWidth: 0.75)
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Theme: \(theme.label)")
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
                    .font(.system(size: 11, weight: .regular))
                    .tracking(0.4)
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

private struct ReaderWebSpreadView: NSViewRepresentable {
    let novelTitle: String
    let chapter: Chapter
    let fontSize: Double
    let lineSpacing: Double
    let palette: ReaderPalette
    let initialLine: Int
    let onVisibleLineChange: (Int) -> Void
    let onChapterTurn: (Int) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "asterionProgress")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        Self.hideScrollers(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        Self.hideScrollers(in: webView)
        let html = makeHTML()
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "asterionProgress")
        webView.navigationDelegate = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: ReaderWebSpreadView
        var lastHTML: String?

        init(parent: ReaderWebSpreadView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { [weak webView] in
                guard let webView, let window = webView.window else { return }
                ReaderWebSpreadView.hideScrollers(in: webView)
                window.makeFirstResponder(webView)
            }
            webView.evaluateJavaScript("window.__asterionRestoreLine(\(parent.initialLine));", completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "asterionProgress" else { return }
            if let line = message.body as? Int {
                parent.onVisibleLineChange(line)
                return
            }
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String
            else { return }

            if type == "progress", let line = body["line"] as? Int {
                parent.onVisibleLineChange(line)
            } else if type == "turn", let offset = body["offset"] as? Int {
                parent.onChapterTurn(offset)
            }
        }
    }

    private static func hideScrollers(in view: NSView) {
        if let scroller = view as? NSScroller {
            scroller.alphaValue = 0
            scroller.isHidden = true
        }
        if let scrollView = view as? NSScrollView {
            scrollView.hasHorizontalScroller = false
            scrollView.hasVerticalScroller = false
            scrollView.autohidesScrollers = true
        }
        view.subviews.forEach(hideScrollers)
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
              --asterion-page-gap: clamp(20px, 2.5vw, 48px);
              --asterion-page-width: calc((100vw - var(--asterion-page-gap)) / 2);
              --asterion-page-inset: clamp(24px, 3vw, 64px);
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
              height: calc(100vh - 88px);
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
          </style>
        </head>
        <body>
          <header>
            <p class="novel">\(novelTitle.htmlEscaped)</p>
            <h1>\(chapter.displayTitle.htmlEscaped)</h1>
          </header>
          \(paragraphs)
          <script>
            (() => {
              const pageMetrics = () => {
                const gap = Math.min(48, Math.max(20, window.innerWidth * 0.025));
                const inset = Math.min(64, Math.max(24, window.innerWidth * 0.03));
                const width = Math.max(320, (window.innerWidth - gap) / 2);
                const pageUnit = width + gap;
                const turnUnit = window.innerWidth + gap;
                const maxX = Math.max(0, document.body.scrollWidth - window.innerWidth);
                const turnCount = Math.max(1, Math.ceil((maxX + turnUnit) / turnUnit));
                return { pageUnit, turnUnit, maxX, turnCount, inset };
              };

              const currentTurn = () => {
                const { turnUnit, turnCount } = pageMetrics();
                return Math.max(0, Math.min(turnCount - 1, Math.round(window.scrollX / turnUnit)));
              };

              const scrollToTurn = (turn, behavior = 'smooth') => {
                const { turnUnit, maxX, turnCount, inset } = pageMetrics();
                const target = Math.max(0, Math.min(turnCount - 1, Math.round(turn)));
                const targetX = Math.max(0, target * turnUnit - (target > 0 ? inset : 0));
                window.scrollTo({ left: Math.min(maxX, targetX), top: 0, behavior });
              };

              const turnPage = (direction) => {
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
                const probeX = window.scrollX + Math.max(48, window.innerWidth * 0.08);
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

              window.__asterionRestoreLine = (line) => {
                const target = document.querySelector(`[data-line="${line}"]`);
                if (target) target.scrollIntoView({ behavior: 'instant', block: 'nearest', inline: 'start' });
                reportProgress();
              };

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
              window.addEventListener('resize', () => scrollToTurn(currentTurn(), 'instant'));
              reportProgress();
            })();
          </script>
        </body>
        </html>
        """
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
