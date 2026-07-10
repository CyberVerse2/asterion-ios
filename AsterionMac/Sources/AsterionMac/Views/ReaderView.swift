import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct ReaderView: View {
    @EnvironmentObject private var model: AppModel
    let route: ReaderRoute

    @AppStorage("readerFontSize") private var fontSize = 19.0
    @AppStorage("readerLineSpacing") private var lineSpacing = 8.0
    @AppStorage("readerColumnWidth") private var columnWidth = 640.0

    @State private var novel: Novel?
    @State private var chapters: [Chapter] = []
    @State private var chapter: Chapter?
    @State private var currentIndex = 0
    @State private var currentLine = 0
    @State private var restoredLine: Int?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var progressTask: Task<Void, Never>?
    @State private var exportsChapter = false

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
        .background(Color.asterionBackground)
        .preferredColorScheme(.light)
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
        .toolbar { readerToolbar }
        .task(id: route) { await load() }
        .onDisappear {
            progressTask?.cancel()
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
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                let usesSplitPages = geometry.size.width >= 980

                VStack(spacing: 0) {
                    if usesSplitPages {
                        ReaderWebSpreadView(
                            novelTitle: novel?.title ?? "Asterion",
                            chapter: chapter,
                            fontSize: fontSize,
                            lineSpacing: lineSpacing,
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
                    }

                    if !usesSplitPages {
                        Divider()
                            .overlay(Color.asterionBorder)

                        readerNavigation
                            .padding(.horizontal, 48)
                            .padding(.vertical, 18)
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

    private func readerHeader(_ chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(novel?.title.uppercased() ?? "ASTERION")
                .font(.caption.weight(.medium))
                .tracking(1.5)
                .foregroundStyle(Color.asterionAccent)
            Text(chapter.title)
                .font(.asterionReading(32, weight: .semibold))
                .foregroundStyle(Color.asterionText)
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
            .foregroundStyle(Color.asterionReaderText)
            .lineSpacing(lineSpacing)
            .textSelection(.enabled)
            .id(index)
            .onAppear { recordVisibleLine(index) }
    }

    private var readerNavigation: some View {
        HStack {
            Button("Previous Chapter", systemImage: "chevron.left") { navigate(by: -1) }
                .disabled(currentIndex == 0)
            Spacer()
            Button("Next Chapter", systemImage: "chevron.right") { navigate(by: 1) }
                .labelStyle(.titleAndIcon)
                .disabled(currentIndex >= chapters.count - 1)
        }
    }

    @ToolbarContentBuilder
    private var readerToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("Previous Chapter", systemImage: "chevron.left") { navigate(by: -1) }
                .disabled(currentIndex == 0 || isLoading)
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("Next Chapter", systemImage: "chevron.right") { navigate(by: 1) }
                .disabled(currentIndex >= chapters.count - 1 || isLoading)
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
        }

        ToolbarItemGroup {
            Button("Smaller Text", systemImage: "textformat.size.smaller") {
                fontSize = max(14, fontSize - 1)
            }
            Button("Larger Text", systemImage: "textformat.size.larger") {
                fontSize = min(30, fontSize + 1)
            }
            Button("Save Chapter…", systemImage: "square.and.arrow.down") {
                exportsChapter = true
            }
            .disabled(chapter == nil)
        }
    }

    private var exportFilename: String {
        guard let chapter else { return "Asterion Chapter" }
        return "\(chapter.chapterNumber) - \(chapter.title)"
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
        guard chapters.indices.contains(targetIndex) else { return }
        syncProgress()
        progressTask?.cancel()
        currentIndex = targetIndex
        currentLine = offset < 0 ? .max : 0
        restoredLine = currentLine
        Task {
            do {
                let loadedChapter = try await model.chapter(id: chapters[targetIndex].id)
                if offset < 0 {
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
        guard let chapter else { return }
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

private struct ReaderWebSpreadView: NSViewRepresentable {
    let novelTitle: String
    let chapter: Chapter
    let fontSize: Double
    let lineSpacing: Double
    let initialLine: Int
    let onVisibleLineChange: (Int) -> Void
    let onChapterTurn: (Int) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "asterionProgress")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
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
              --asterion-accent: #9C2335;
              --asterion-bg: #F2F3F5;
              --asterion-text: #202126;
              --asterion-muted: #555C66;
              --asterion-page-gap: clamp(96px, 7vw, 160px);
              --asterion-page-width: calc((100vw - var(--asterion-page-gap)) / 2);
              --asterion-page-inset: clamp(56px, 4.6vw, 104px);
            }
            html, body {
              width: 100%;
              height: 100%;
              margin: 0;
              background: var(--asterion-bg);
              color: var(--asterion-text);
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
              scrollbar-width: none;
            }
            body::-webkit-scrollbar {
              width: 0;
              height: 0;
              display: none;
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
              color: var(--asterion-accent);
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
            <h1>\(chapter.title.htmlEscaped)</h1>
          </header>
          \(paragraphs)
          <script>
            (() => {
              const pageMetrics = () => {
                const gap = Math.min(160, Math.max(96, window.innerWidth * 0.07));
                const width = Math.max(320, (window.innerWidth - gap) / 2);
                const pageUnit = width + gap;
                const turnUnit = window.innerWidth + gap;
                const maxX = Math.max(0, document.body.scrollWidth - window.innerWidth);
                const turnCount = Math.max(1, Math.ceil((maxX + turnUnit) / turnUnit));
                return { pageUnit, turnUnit, maxX, turnCount };
              };

              const currentTurn = () => {
                const { turnUnit, turnCount } = pageMetrics();
                return Math.max(0, Math.min(turnCount - 1, Math.round(window.scrollX / turnUnit)));
              };

              const scrollToTurn = (turn, behavior = 'smooth') => {
                const { turnUnit, maxX, turnCount } = pageMetrics();
                const target = Math.max(0, Math.min(turnCount - 1, Math.round(turn)));
                window.scrollTo({ left: Math.min(maxX, target * turnUnit), top: 0, behavior });
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
        text = "\(chapter.title)\n\n\(chapter.plainContent)"
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
