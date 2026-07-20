import SwiftUI

struct NovelDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let novel: Novel

    @State private var chapters: [Chapter] = []
    @State private var progress: ReadingProgress?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var downloadRequestError: String?
    @State private var scrollPosition: String?
    @State private var showsFullSynopsis = false

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

    private var visibleChapters: [Chapter] {
        Array(chapters.suffix(5).reversed())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                hero
                    .id("detail-top")
                sourceNotices
                actions
                Divider()

                detailSection(title: "Chapters", trailing: chapterCountLabel) {
                    chapterList
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.top, 24)
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .hidingScrollIndicators()
        .scrollPosition(id: $scrollPosition, anchor: .top)
        .background(Color.asterionMediaCanvas)
        .safeAreaInset(edge: .bottom) { accountErrorBar }
        .task(id: novel.id) {
            showsFullSynopsis = false
            scrollPosition = nil
            await load()
            await Task.yield()
            scrollPosition = "detail-top"
        }
    }

    private var hero: some View {
        AsterionDetailHero(
            imageURL: novel.imageURL.flatMap(URL.init(string:)),
            title: novel.title,
            subtitle: novel.authorDisplayName,
            metadata: [
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
            ],
            summary: cleanSummary,
            showsFullSummary: $showsFullSynopsis
        )
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
                .frame(maxWidth: .infinity)
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
        .tint(isDownloaded ? .asterionAccent : nil)
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
                icon: "arrow.down.circle.fill"
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
            LazyVStack(spacing: 0) {
                ForEach(visibleChapters) { chapter in
                    Button {
                        open(chapter)
                    } label: {
                        HStack(spacing: 14) {
                            Text(String(chapter.chapterNumber))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Color.asterionMuted)
                                .frame(width: 34, alignment: .trailing)
                            Text(chapter.title)
                                .font(.asterionDisplay(14, weight: .medium))
                                .foregroundStyle(Color.asterionText)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(Color.asterionMuted)
                        }
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
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
        return "arrow.down.circle"
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

    private func detailSection<Content: View>(
        title: String,
        trailing: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.asterionDisplay(20, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.caption)
                        .foregroundStyle(Color.asterionAccent)
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
