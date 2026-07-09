import SwiftUI
import UniformTypeIdentifiers

struct ReaderView: View {
    @EnvironmentObject private var model: AppModel
    let route: ReaderRoute

    @AppStorage("readerFontSize") private var fontSize = 19.0
    @AppStorage("readerLineSpacing") private var lineSpacing = 8.0
    @AppStorage("readerColumnWidth") private var columnWidth = 700.0

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
        .navigationTitle(chapter?.title ?? "Reader")
        .safeAreaInset(edge: .bottom) {
            if let error = model.accountError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: lineSpacing) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(novel?.title.uppercased() ?? "ASTERION")
                            .font(.asterionMono(10, weight: .medium))
                            .tracking(2)
                            .foregroundStyle(Color.asterionGold)
                        Text(chapter.title)
                            .font(.asterionSerif(34, weight: .semibold))
                            .foregroundStyle(Color.asterionText)
                            .textSelection(.enabled)
                    }
                    .padding(.bottom, 24)

                    ForEach(Array(chapter.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                        Text(paragraph)
                            .font(.asterionSerif(fontSize))
                            .foregroundStyle(Color.asterionReaderText)
                            .lineSpacing(lineSpacing)
                            .textSelection(.enabled)
                            .id(index)
                            .onAppear { recordVisibleLine(index) }
                    }

                    Divider()
                        .overlay(Color.asterionBorder)
                        .padding(.top, 32)

                    HStack {
                        Button("Previous Chapter", systemImage: "chevron.left") { navigate(by: -1) }
                            .disabled(currentIndex == 0)
                        Spacer()
                        Button("Next Chapter", systemImage: "chevron.right") { navigate(by: 1) }
                            .labelStyle(.titleAndIcon)
                            .disabled(currentIndex >= chapters.count - 1)
                    }
                    .padding(.vertical, 24)
                }
                .frame(maxWidth: columnWidth, alignment: .leading)
                .padding(.horizontal, 48)
                .padding(.vertical, 44)
                .frame(maxWidth: .infinity)
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
        currentLine = 0
        restoredLine = 0
        Task {
            do {
                chapter = try await model.chapter(id: chapters[targetIndex].id)
                errorMessage = nil
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
