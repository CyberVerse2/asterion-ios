import SwiftUI

struct NovelDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let novel: Novel
    let selectNovel: (Novel) -> Void

    @State private var chapters: [Chapter] = []
    @State private var progress: ReadingProgress?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var downloadRequestError: String?
    @State private var scrollPosition: String?
    @State private var showsFullSynopsis = false
    @State private var selectedChapterRange = 0
    @State private var chapterSearch = ""

    private var isInLibrary: Bool {
        model.libraryNovelIDs.contains(novel.id)
    }

    private var isDownloaded: Bool {
        model.downloadedNovelIDs.contains(novel.id)
    }

    private var isDownloading: Bool {
        offlineDownload?.isDownloading == true
    }

    private var offlineDownload: OfflineDownload? { model.offlineDownload(for: novel.id) }

    var body: some View {
        ZStack(alignment: .top) {
            ambientBackdrop

            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    hero
                    sourceNotices

                    detailSection(title: "Chapters", trailing: chapterCountLabel) {
                        chapterList
                    }

                    if !recommendations.isEmpty {
                        detailSection(title: "You Might Like") {
                            recommendationShelf
                        }
                    }
                }
                .asterionDetailPageFrame()
                .id("detail-top")
            }
            .hidingScrollIndicators()
            .scrollPosition(id: $scrollPosition, anchor: .top)
        }
        .background(Color.asterionMediaCanvas)
        .safeAreaInset(edge: .bottom) { accountErrorBar }
        .task(id: novel.id) {
            showsFullSynopsis = false
            chapterSearch = ""
            selectedChapterRange = 0
            scrollPosition = nil
            await load()
            await Task.yield()
            scrollPosition = "detail-top"
        }
    }

    private var coverURL: URL? {
        novel.imageURL.flatMap(URL.init(string:))
    }

    private var ambientBackdrop: some View {
        AsyncImage(url: coverURL) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 42)
                    .saturation(0.78)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 590)
        .clipped()
        .opacity(0.38)
        .overlay(Color.black.opacity(0.38))
        .mask {
            LinearGradient(
                colors: [.black, .black.opacity(0.82), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .backgroundExtensionEffect()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 38) {
            AsyncImage(url: coverURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Color.asterionCard
                }
            }
            .frame(width: 258, height: 370)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(.white.opacity(0.13))
            }
            .shadow(color: .black.opacity(0.34), radius: 24, y: 14)

            VStack(alignment: .leading, spacing: 17) {
                Text("NOVEL")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.asterionText.opacity(0.72))

                Text(novel.title)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)
                    .textSelection(.enabled)

                Text(novel.authorDisplayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.asterionText.opacity(0.76))
                    .lineLimit(1)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { metadataItems }
                    VStack(alignment: .leading, spacing: 8) { metadataItems }
                }

                if !cleanSummary.isEmpty {
                    Text(cleanSummary)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.asterionText.opacity(0.84))
                        .lineSpacing(4)
                        .lineLimit(showsFullSynopsis ? nil : 3)
                        .frame(maxWidth: 650, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    if cleanSummary.count > 240 {
                        Button(showsFullSynopsis ? "Show less" : "More") {
                            showsFullSynopsis.toggle()
                        }
                        .buttonStyle(.link)
                        .font(.caption.weight(.semibold))
                        .tint(.asterionText)
                    }
                }

                actions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 390)
    }

    @ViewBuilder
    private var metadataItems: some View {
        ForEach(novelMetadata) { item in
            Label(item.value, systemImage: item.icon)
                .font(.callout)
                .foregroundStyle(Color.asterionText.opacity(0.68))
                .lineLimit(1)
        }
    }

    private var novelMetadata: [AsterionDetailMetadata] {
        [
            AsterionDetailMetadata(icon: "book.closed", value: novel.genres?.first ?? "Fiction"),
            AsterionDetailMetadata(
                icon: "text.page",
                value: "\(novel.totalChapters ?? String(chapters.count)) chapters"
            ),
            AsterionDetailMetadata(icon: "eye", value: "\(novel.views ?? "—") views"),
            AsterionDetailMetadata(
                icon: "star.fill",
                value: novel.rating.map { String(format: "%.1f rating", $0) } ?? "Not yet rated"
            ),
        ]
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                readAction
                saveAction
                downloadAction
            }

            downloadStatus

            if let progress {
                HStack(spacing: 10) {
                    ProgressView(value: min(1, max(0, progress.percentage / 100)))
                        .tint(Color.asterionAccent)
                        .animation(reduceMotion ? nil : AsterionMotion.reveal, value: progress.percentage)
                    Text("\(Int(progress.percentage))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.asterionMuted)
                }
            }
        }
    }

    private var readAction: some View {
        Button {
            openPreferredChapter()
        } label: {
            Label(readButtonTitle, systemImage: "book.pages")
                .lineLimit(1)
                .padding(.horizontal, 12)
        }
        .layoutPriority(1)
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .controlSize(.large)
        .tint(.asterionAccent)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(chapters.isEmpty)
    }

    private var saveAction: some View {
        Button {
            Task { await model.toggleLibrary(novelID: novel.id) }
        } label: {
            Image(systemName: isInLibrary ? "bookmark.fill" : "bookmark")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .controlSize(.large)
        .tint(Color.asterionText)
        .help(isInLibrary ? "Saved" : "Save to Library")
        .accessibilityLabel(isInLibrary ? "Saved" : "Save to Library")
        .disabled(!model.isSignedIn || model.isUpdatingLibrary)
        .animation(reduceMotion ? nil : AsterionMotion.hover, value: isInLibrary)
    }

    private var downloadAction: some View {
        Button {
            Task { await updateOfflineDownload() }
        } label: {
            Image(systemName: downloadButtonIcon)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .controlSize(.large)
        .tint(Color.asterionText)
        .help(downloadButtonTitle)
        .accessibilityLabel(downloadButtonTitle)
        .disabled(isDownloading || (!isDownloaded && chapters.isEmpty))
        .animation(reduceMotion ? nil : AsterionMotion.hover, value: isDownloaded)
    }

    @ViewBuilder
    private var sourceNotices: some View {
        if let notice = model.catalogState.notice {
            sourceNotice(
                message: notice,
                icon: "wifi.exclamationmark"
            )
        }

        if case .offline = model.chapterListState(for: novel.id),
           let notice = model.chapterListState(for: novel.id).notice {
            sourceNotice(
                message: notice,
                icon: "arrow.down.to.line"
            )
        }
    }

    private func sourceNotice(message: String, icon: String) -> some View {
        Label(message, systemImage: icon)
            .font(.callout)
            .foregroundStyle(Color.asterionText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel(message)
    }

    @ViewBuilder
    private var downloadStatus: some View {
        if let download = offlineDownload, download.phase == .downloading {
            HStack(spacing: 10) {
                if download.totalChapters == 0 {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing offline download…")
                } else {
                    ProgressView(value: download.progress)
                        .tint(Color.asterionAccent)
                    Text("\(download.completedChapters)/\(download.totalChapters) · \(download.progress, format: .percent.precision(.fractionLength(0)))")
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(Color.asterionMuted)
        } else if let message = offlineDownload?.errorMessage ?? downloadRequestError {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Color.red)
        }
    }

    @ViewBuilder
    private var chapterList: some View {
        if isLoading {
            ProgressView("Loading chapters…")
                .frame(maxWidth: .infinity, minHeight: 100)
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Chapters unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        } else if chapters.isEmpty {
            ContentUnavailableView("No chapters", systemImage: "text.page")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                chapterBrowserControls

                if displayedChapters.isEmpty {
                    ContentUnavailableView.search(text: chapterSearch)
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 250, maximum: 420), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(displayedChapters) { chapter in
                            chapterCard(chapter)
                        }
                    }
                }
            }
        }
    }

    private var chapterBrowserControls: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(Array(chapterRanges.enumerated()), id: \.element.id) { index, range in
                    Button("Chapters \(range.label)") {
                        selectedChapterRange = index
                        chapterSearch = ""
                    }
                }
            } label: {
                Label(currentChapterRange.map { "Chapters \($0.label)" } ?? "Chapters", systemImage: "rectangle.grid.2x2")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .frame(minWidth: 152)
            }
            .menuStyle(.borderlessButton)

            Button {
                selectedChapterRange -= 1
                chapterSearch = ""
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(selectedChapterRange == 0)
            .help("Previous \(NovelChapterRange.pageSize) chapters")

            Button {
                selectedChapterRange += 1
                chapterSearch = ""
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(selectedChapterRange >= chapterRanges.count - 1)
            .help("Next \(NovelChapterRange.pageSize) chapters")

            Button {
                selectedChapterRange = max(chapterRanges.count - 1, 0)
                chapterSearch = ""
            } label: {
                Label("Latest", systemImage: "arrow.up.to.line")
            }
            .disabled(selectedChapterRange == chapterRanges.count - 1 && chapterSearch.isEmpty)

            Spacer(minLength: 12)

            TextField("Find chapter or title", text: $chapterSearch)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, idealWidth: 240, maxWidth: 300)
                .onSubmit(openExactChapterMatch)
                .accessibilityLabel("Find chapter number or title")
        }
        .buttonStyle(.borderless)
        .controlSize(.regular)
    }

    private func chapterCard(_ chapter: Chapter) -> some View {
        Button {
            open(chapter)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: progress?.chapterId == chapter.id ? "book.fill" : "book.closed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(progress?.chapterId == chapter.id ? Color.asterionAccent : Color.asterionMuted)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Chapter \(chapter.chapterNumber)")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.asterionText)
                    Text(chapter.displayTitle)
                        .font(.caption)
                        .foregroundStyle(Color.asterionMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.asterionMuted)
            }
            .padding(.horizontal, 13)
            .frame(height: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.08))
        }
    }

    private var chapterRanges: [NovelChapterRange] {
        NovelChapterRange.pages(for: chapters)
    }

    private var currentChapterRange: NovelChapterRange? {
        guard chapterRanges.indices.contains(selectedChapterRange) else { return chapterRanges.last }
        return chapterRanges[selectedChapterRange]
    }

    private var displayedChapters: [Chapter] {
        let query = chapterSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches: [Chapter]
        if query.isEmpty {
            matches = currentChapterRange?.chapters ?? []
        } else if let number = Int(query) {
            matches = chapters.filter { String($0.chapterNumber).contains(String(number)) }
        } else {
            matches = chapters.filter {
                $0.displayTitle.localizedCaseInsensitiveContains(query)
                    || $0.title.localizedCaseInsensitiveContains(query)
            }
        }
        return matches.sorted { $0.chapterNumber > $1.chapterNumber }
    }

    private func openExactChapterMatch() {
        let query = chapterSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(query),
              let chapter = chapters.first(where: { $0.chapterNumber == number }) else {
            return
        }
        open(chapter)
    }

    @ViewBuilder
    private var accountErrorBar: some View {
        if let error = model.accountError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(Color.asterionAccent)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
        }
    }

    private var cleanSummary: String {
        let cleaned = (novel.summary ?? "")
            .replacingOccurrences(of: "Show More", with: "")
            .replacingOccurrences(
                of: "\\s+on [A-Z][a-z]+ \\d{1,2}, \\d{4}.*$",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "([.!?])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }

    private var readButtonTitle: String {
        guard let progress else { return "Start Reading" }
        guard let chapter = chapters.first(where: { $0.id == progress.chapterId }) else {
            return "Continue Reading"
        }
        return "Continue Reading · Chapter \(chapter.chapterNumber)"
    }

    private var downloadButtonTitle: String {
        if isDownloaded { return "Remove Download" }
        if let download = offlineDownload, download.isDownloading {
            guard download.totalChapters > 0 else { return "Preparing…" }
            return "Downloading \(Int(download.progress * 100))%"
        }
        if offlineDownload?.phase == .failed { return "Retry Download" }
        return "Download"
    }

    private var downloadButtonIcon: String {
        if isDownloaded { return "trash" }
        if offlineDownload?.phase == .failed { return "arrow.clockwise.circle" }
        return "arrow.down.to.line"
    }

    private var chapterCountLabel: String? {
        chapters.isEmpty ? nil : "\(chapters.count) chapters"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let chapterRequest = model.chapters(for: novel.id)
            async let progressRequest = model.fetchProgress(novelID: novel.id)
            chapters = try await chapterRequest
            progress = try await progressRequest
            selectInitialChapterRange()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateOfflineDownload() async {
        downloadRequestError = nil
        do {
            if isDownloaded {
                try await model.removeOfflineDownload(novelID: novel.id)
                await load()
            } else {
                try await model.downloadForOffline(novel: novel)
            }
        } catch {
            downloadRequestError = error.localizedDescription
        }
    }

    private func openPreferredChapter() {
        let preferred = progress.flatMap { saved in
            chapters.first { $0.id == saved.chapterId }
        } ?? chapters.first
        if let preferred { open(preferred) }
    }

    private func open(_ chapter: Chapter) {
        openWindow(value: ReaderRoute(novelID: novel.id, chapterID: chapter.id))
    }

    private func selectInitialChapterRange() {
        if let progress,
           let progressRange = chapterRanges.firstIndex(where: { $0.contains(chapterID: progress.chapterId) }) {
            selectedChapterRange = progressRange
        } else {
            selectedChapterRange = max(chapterRanges.count - 1, 0)
        }
    }

    private var recommendationShelf: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 15) {
                ForEach(recommendations) { recommendation in
                    AsterionPosterCard(
                        imageURL: recommendation.imageURL.flatMap(URL.init(string:)),
                        badge: "NOVEL",
                        title: recommendation.title,
                        subtitle: recommendation.authorDisplayName
                    ) {
                        selectNovel(recommendation)
                    }
                }
            }
            .padding(.vertical, 2)
            .scrollTargetLayout()
        }
        .hidingScrollIndicators()
        .scrollTargetBehavior(.viewAligned)
    }

    private var recommendations: [Novel] {
        Array(model.novels.lazy.filter { $0.id != novel.id }.prefix(10))
    }

    private func detailSection<Content: View>(
        title: String,
        trailing: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.asterionText)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.caption)
                        .foregroundStyle(Color.asterionMuted)
                }
            }
            content()
        }
    }
}

private struct MetadataLine: View {
    let icon: String
    let value: String

    var body: some View {
        Label {
            Text(value)
                .lineLimit(1)
        } icon: {
            Image(systemName: icon)
                .frame(width: 16)
        }
        .font(.caption)
        .foregroundStyle(Color.asterionMuted)
    }
}
