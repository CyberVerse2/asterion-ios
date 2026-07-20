import SwiftUI

enum DownloadCenterPresentation: Equatable {
    case popover
    case library
}

struct DownloadCenterView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var mediaDownloads: MediaDownloadManager
    let presentation: DownloadCenterPresentation

    init(presentation: DownloadCenterPresentation = .popover) {
        self.presentation = presentation
    }

    private var activeCount: Int {
        model.offlineDownloads.count(where: { $0.isDownloading }) + mediaDownloads.activeCount
    }

    private var completedCount: Int {
        model.offlineDownloads.count(where: { $0.phase == .completed })
            + mediaDownloads.completedCount
    }

    private var novelDownloads: [OfflineDownload] {
        model.offlineDownloads
    }

    private var animeDownloads: [MediaDownloadRecord] {
        mediaDownloads.downloads.filter { $0.mediaType == .anime }
    }

    private var movieDownloads: [MediaDownloadRecord] {
        mediaDownloads.downloads.filter { $0.mediaType == .movie }
    }

    private var isEmpty: Bool {
        novelDownloads.isEmpty && animeDownloads.isEmpty && movieDownloads.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Downloads")
                        .font(.asterionDisplay(presentation == .library ? 24 : 18, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                    Text(downloadSummary)
                        .font(.caption)
                        .foregroundStyle(Color.asterionMuted)
                }
                Spacer()
                if activeCount > 0 {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.asterionAccent)
                }
            }
            .padding(presentation == .library ? 22 : 18)

            Divider()

            if isEmpty {
                ContentUnavailableView {
                    Label("No downloads", systemImage: "arrow.down.circle")
                } description: {
                    Text("Download a novel, movie, or episode to enjoy it offline.")
                }
                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let storageError = mediaDownloads.storageError {
                            Label(storageError, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(18)
                            Divider()
                        }

                        downloadGroup(
                            title: "Novels",
                            systemImage: "books.vertical.fill",
                            count: novelDownloads.count
                        ) {
                            ForEach(novelDownloads) { download in
                                DownloadRow(download: download)
                                if download.id != novelDownloads.last?.id {
                                    Divider()
                                }
                            }
                        }

                        downloadGroup(
                            title: "Anime",
                            systemImage: "sparkles.tv.fill",
                            count: animeDownloads.count
                        ) {
                            ForEach(animeDownloads) { download in
                                MediaDownloadRow(download: download)
                                if download.id != animeDownloads.last?.id {
                                    Divider()
                                }
                            }
                        }

                        downloadGroup(
                            title: "Movies & TV",
                            systemImage: "film.stack.fill",
                            count: movieDownloads.count
                        ) {
                            ForEach(movieDownloads) { download in
                                MediaDownloadRow(download: download)
                                if download.id != movieDownloads.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: presentation == .popover ? 480 : .infinity)
            }
        }
        .frame(
            maxWidth: presentation == .library ? .infinity : nil,
            maxHeight: presentation == .library ? .infinity : nil,
            alignment: .topLeading
        )
        .frame(width: presentation == .popover ? 360 : nil)
        .background(Color.asterionMediaCanvas)
    }

    private func downloadGroup<Content: View>(
        title: String,
        systemImage: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                Spacer()
                Text(count, format: .number)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(Color.asterionMuted)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color.asterionSurface.opacity(0.72))

            if count == 0 {
                Text("No downloaded \(title.lowercased())")
                    .font(.caption)
                    .foregroundStyle(Color.asterionMuted)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            } else {
                content()
            }
            Divider()
        }
    }

    private var downloadSummary: String {
        if activeCount > 0 {
            return "\(activeCount) downloading · \(completedCount) available offline"
        }
        return completedCount == 1 ? "1 item available offline" : "\(completedCount) items available offline"
    }
}

private struct MediaDownloadRow: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var mediaDownloads: MediaDownloadManager
    let download: MediaDownloadRecord
    @State private var actionError: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: phaseIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(phaseColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(download.contentTitle)
                        .font(.asterionDisplay(14, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                        .lineLimit(1)
                    Text(downloadDetailText)
                        .font(.caption)
                        .foregroundStyle(download.phase == .failed ? Color.red : Color.asterionMuted)
                        .lineLimit(2)
                }

                Spacer()

                if download.isActive {
                    HStack(spacing: 6) {
                        Text(download.progress, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Color.asterionAccent)
                        removeButton(icon: "xmark")
                            .help("Cancel download")
                    }
                } else if download.phase == .failed {
                    HStack(spacing: 6) {
                        Button("Retry") {
                            Task { await retry() }
                        }
                        removeButton(icon: "trash")
                            .help("Remove failed download")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isWorking)
                } else {
                    HStack(spacing: 6) {
                        Button {
                            openDownloadedItem()
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .help("Play downloaded copy")

                        Button {
                            Task { await remove() }
                        } label: {
                            if isWorking {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "trash")
                            }
                        }
                        .help("Remove downloaded copy")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isWorking)
                }
            }

            if download.isActive {
                ProgressView(value: download.progress)
                    .tint(Color.asterionAccent)
            }

            if let actionError {
                Label(actionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var phaseIcon: String {
        switch download.phase {
        case .preparing, .downloading: "arrow.down.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var phaseColor: Color {
        switch download.phase {
        case .preparing, .downloading: Color.asterionAccent
        case .completed: Color.green
        case .failed: Color.red
        }
    }

    private var statusText: String {
        switch download.phase {
        case .preparing: "Preparing…"
        case .downloading: "Downloading"
        case .completed: "Available offline"
        case .failed: download.errorMessage ?? "Download failed"
        }
    }

    private var downloadDetailText: String {
        [download.detailLabel, download.downloadQuality?.title, statusText]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func retry() async {
        isWorking = true
        actionError = nil
        defer { isWorking = false }
        do {
            try await mediaDownloads.retry(download)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func remove() async {
        isWorking = true
        actionError = nil
        defer { isWorking = false }
        do {
            try await mediaDownloads.remove(download)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func removeButton(icon: String) -> some View {
        Button {
            Task { await remove() }
        } label: {
            if isWorking {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: icon)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isWorking)
    }

    private func openDownloadedItem() {
        switch download.mediaType {
        case .anime:
            openWindow(
                value: AnimePlayerRoute(
                    slug: download.contentID,
                    title: download.contentTitle,
                    initialEpisodeID: download.unitID
                )
            )
        case .movie:
            openWindow(
                value: MoviePlayerRoute(
                    slug: download.contentID,
                    title: download.contentTitle,
                    initialEpisodeID: download.movieEpisode == nil ? nil : download.unitID
                )
            )
        case .football:
            break
        }
    }
}

private struct DownloadRow: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    let download: OfflineDownload
    @State private var actionError: String?
    @State private var isRemoving = false
    @State private var isOpening = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: phaseIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(phaseColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(download.novelTitle)
                        .font(.asterionDisplay(14, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                        .lineLimit(1)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(download.phase == .failed ? Color.red : Color.asterionMuted)
                        .lineLimit(2)
                }

                Spacer()

                if download.phase == .downloading, download.totalChapters > 0 {
                    Text(download.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.asterionAccent)
                } else if download.phase == .failed,
                          let novel = model.novel(id: download.novelID) {
                    Button("Retry") {
                        Task { await retry(novel: novel) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if download.phase == .completed {
                    HStack(spacing: 6) {
                        Button {
                            Task { await openDownload() }
                        } label: {
                            if isOpening {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Read", systemImage: "book.fill")
                            }
                        }
                        .help("Read downloaded novel")

                        Button {
                            Task { await removeDownload() }
                        } label: {
                            if isRemoving {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "trash")
                            }
                        }
                        .help("Remove downloaded copy")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRemoving || isOpening)
                }
            }

            if download.phase == .downloading {
                ProgressView(value: download.progress)
                    .tint(Color.asterionAccent)
            }

            if let actionError {
                Label(actionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var phaseIcon: String {
        switch download.phase {
        case .downloading: "arrow.down.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var phaseColor: Color {
        switch download.phase {
        case .downloading: Color.asterionAccent
        case .completed: Color.green
        case .failed: Color.red
        }
    }

    private var statusText: String {
        switch download.phase {
        case .downloading:
            if download.totalChapters == 0 { return "Preparing chapters…" }
            return "\(download.completedChapters) of \(download.totalChapters) chapters"
        case .completed:
            return "Available offline"
        case .failed:
            return download.errorMessage ?? "Download failed"
        }
    }

    private func retry(novel: Novel) async {
        actionError = nil
        do {
            try await model.downloadForOffline(novel: novel)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func removeDownload() async {
        isRemoving = true
        actionError = nil
        defer { isRemoving = false }
        do {
            try await model.removeOfflineDownload(novelID: download.novelID)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func openDownload() async {
        isOpening = true
        actionError = nil
        defer { isOpening = false }
        do {
            async let chapterRequest = model.chapters(for: download.novelID)
            async let progressRequest = model.fetchProgress(novelID: download.novelID)
            let chapters = try await chapterRequest
            let sortedChapters = chapters.sorted { $0.chapterNumber < $1.chapterNumber }
            let progress = try await progressRequest
            guard let chapter = progress.flatMap({ saved in
                sortedChapters.first { $0.id == saved.chapterId }
            }) ?? sortedChapters.first else {
                actionError = "This downloaded novel does not contain any chapters."
                return
            }
            openWindow(
                value: ReaderRoute(
                    novelID: download.novelID,
                    chapterID: chapter.id
                )
            )
        } catch {
            actionError = error.localizedDescription
        }
    }
}
