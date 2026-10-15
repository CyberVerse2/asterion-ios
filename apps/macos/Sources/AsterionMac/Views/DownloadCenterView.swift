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

    private var isLibrary: Bool { presentation == .library }

    private var activeCount: Int {
        model.offlineDownloads.count(where: { $0.isDownloading }) + mediaDownloads.activeCount
    }

    private var completedCount: Int {
        model.offlineDownloads.count(where: { $0.phase == .completed })
            + mediaDownloads.completedCount
    }

    private var failedCount: Int {
        model.offlineDownloads.count(where: { $0.phase == .failed })
            + mediaDownloads.downloads.count(where: { $0.phase == .failed })
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

    private var metrics: DownloadRowMetrics {
        isLibrary ? .library : .compact
    }

    var body: some View {
        Group {
            if isLibrary {
                libraryBody
            } else {
                popoverBody
            }
        }
        .background(Color.asterionMediaCanvas)
    }

    // MARK: Presentations

    private var libraryBody: some View {
        Group {
            if isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    AsterionPageHeader("Downloads", subtitle: downloadSummary)
                    emptyState
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        AsterionPageHeader("Downloads", subtitle: downloadSummary)
                        downloadSections
                            .frame(maxWidth: 920, alignment: .leading)
                            .padding(.horizontal, AsterionLayout.pageInset)
                            .padding(.top, 30)
                            .padding(.bottom, 56)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .hidingScrollIndicators()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var popoverBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Downloads")
                        .font(.asterionTitle(18, weight: .bold))
                        .foregroundStyle(Color.asterionText)
                        .accessibilityAddTraits(.isHeader)
                    Text(downloadSummary)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.asterionMuted)
                }
                Spacer()
                if activeCount > 0 {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.asterionText)
                }
            }
            .padding(16)

            Rectangle()
                .fill(Color.asterionHairline)
                .frame(height: 1)

            if isEmpty {
                emptyState
                    .frame(minHeight: 220)
            } else {
                ScrollView {
                    downloadSections
                        .padding(16)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 480)
            }
        }
        .frame(width: 360, alignment: .topLeading)
    }

    private var emptyState: some View {
        AsterionEmptyState(
            systemImage: "arrow.down.circle",
            title: "No downloads",
            message: "Download a novel, film, or episode and it will be here to enjoy offline."
        )
    }

    // MARK: Sections

    private var downloadSections: some View {
        let activeNovels = novelDownloads.filter(\.isDownloading)
        let activeMedia = mediaDownloads.downloads.filter(\.isActive)
        let settledNovels = novelDownloads.filter { !$0.isDownloading }
        let settledAnime = animeDownloads.filter { !$0.isActive }
        let settledMovies = movieDownloads.filter { !$0.isActive }

        return VStack(alignment: .leading, spacing: isLibrary ? 36 : 22) {
            if let storageError = mediaDownloads.storageError {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(storageError)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.asterionWarning)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .asterionPanel(cornerRadius: 12)
                .accessibilityElement(children: .combine)
            }

            if !activeNovels.isEmpty || !activeMedia.isEmpty {
                section(title: "Downloading", count: activeNovels.count + activeMedia.count) {
                    panel(prominent: true) {
                        ForEach(Array(activeNovels.enumerated()), id: \.element.id) { index, download in
                            if index > 0 { ActivityRowSeparator(leadingInset: metrics.separatorInset) }
                            DownloadRow(download: download, metrics: metrics)
                        }
                        ForEach(Array(activeMedia.enumerated()), id: \.element.id) { index, download in
                            if index > 0 || !activeNovels.isEmpty {
                                ActivityRowSeparator(leadingInset: metrics.separatorInset)
                            }
                            MediaDownloadRow(download: download, metrics: metrics)
                        }
                    }
                }
            }

            if !settledNovels.isEmpty {
                section(title: "Novels", count: settledNovels.count) {
                    panel {
                        ForEach(Array(settledNovels.enumerated()), id: \.element.id) { index, download in
                            if index > 0 { ActivityRowSeparator(leadingInset: metrics.separatorInset) }
                            DownloadRow(download: download, metrics: metrics)
                        }
                    }
                }
            }

            if !settledAnime.isEmpty {
                section(title: "Anime", count: settledAnime.count) {
                    mediaPanel(settledAnime)
                }
            }

            if !settledMovies.isEmpty {
                section(title: "Films & series", count: settledMovies.count) {
                    mediaPanel(settledMovies)
                }
            }
        }
    }

    private func mediaPanel(_ downloads: [MediaDownloadRecord]) -> some View {
        let groups = groupedBySeries(downloads)
        return panel {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 { ActivityRowSeparator(leadingInset: metrics.separatorInset) }
                if group.downloads.count == 1, let download = group.downloads.first {
                    MediaDownloadRow(download: download, metrics: metrics)
                } else {
                    DownloadSeriesGroup(group: group, metrics: metrics)
                }
            }
        }
    }

    /// Keeps the newest-first order while collecting episodes of one series.
    private func groupedBySeries(_ downloads: [MediaDownloadRecord]) -> [DownloadSeries] {
        var order: [String] = []
        var buckets: [String: [MediaDownloadRecord]] = [:]
        for download in downloads {
            let key = "\(download.mediaType.rawValue):\(download.contentID)"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(download)
        }
        return order.map { DownloadSeries(id: $0, downloads: buckets[$0] ?? []) }
    }

    private func section<Content: View>(
        title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: isLibrary ? 14 : 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if isLibrary {
                    Text(title)
                        .font(.asterionTitle(18, weight: .bold))
                        .foregroundStyle(Color.asterionText)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    AsterionEyebrow(text: title)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 8)
                Text(count, format: .number)
                    .font(.asterionMono(11.5, weight: .medium))
                    .foregroundStyle(Color.asterionFaint)
                    .accessibilityLabel(count == 1 ? "1 item" : "\(count) items")
            }
            .padding(.horizontal, 4)

            content()
        }
    }

    private func panel<Content: View>(
        prominent: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .clipShape(RoundedRectangle(cornerRadius: prominent ? 16 : 14, style: .continuous))
        .asterionPanel(cornerRadius: prominent ? 16 : 14, fill: prominent ? .asterionCard : .asterionSurface)
        .shadow(color: .black.opacity(prominent ? 0.28 : 0), radius: 18, y: 8)
    }

    private var downloadSummary: String {
        var parts: [String]
        if activeCount > 0 {
            parts = ["\(activeCount) downloading", "\(completedCount) available offline"]
        } else {
            parts = [completedCount == 1 ? "1 item available offline" : "\(completedCount) items available offline"]
        }
        if failedCount > 0 {
            parts.append("\(failedCount) failed")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Rows

private struct DownloadSeries: Identifiable {
    let id: String
    let downloads: [MediaDownloadRecord]

    var title: String { downloads.first?.contentTitle ?? "" }
    var imageURL: URL? { downloads.first(where: { $0.imageURL != nil })?.imageURL }
    var failedCount: Int { downloads.count(where: { $0.phase == .failed }) }
}

/// One series with several downloaded episodes: a summary row that expands
/// to the individual episodes.
private struct DownloadSeriesGroup: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    @State private var isHovering = false

    let group: DownloadSeries
    let metrics: DownloadRowMetrics

    private var summary: String {
        let qualities = Set(group.downloads.compactMap(\.downloadQuality?.title))
        var parts = ["\(group.downloads.count) episodes"]
        if qualities.count == 1, let quality = qualities.first {
            parts.append(quality)
        }
        if group.failedCount > 0 {
            parts.append("\(group.failedCount) failed")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: metrics.spacing) {
                    ActivityThumbnail(
                        url: group.imageURL,
                        fallbackSystemImage: group.downloads.first?.mediaType.systemImage ?? "play.rectangle",
                        width: metrics.thumbnailWidth,
                        height: metrics.thumbnailHeight
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.title)
                            .font(.asterionDisplay(metrics.isCompact ? 13 : 14, weight: .semibold))
                            .foregroundStyle(Color.asterionText)
                            .lineLimit(1)
                        Text(summary)
                            .font(.system(size: metrics.isCompact ? 11.5 : 12.5))
                            .foregroundStyle(group.failedCount > 0 ? Color.asterionWarning : Color.asterionMuted)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.asterionMuted)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .frame(width: 38, height: 38)
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, metrics.verticalPadding)
                .background(Color.white.opacity(isHovering ? 0.035 : 0))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .accessibilityLabel(group.title)
            .accessibilityValue(summary)
            .accessibilityHint(isExpanded ? "Hides episodes" : "Shows episodes")

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(group.downloads) { download in
                        ActivityRowSeparator(leadingInset: metrics.separatorInset)
                        MediaDownloadRow(download: download, metrics: metrics, isNested: true)
                    }
                }
                .background(Color.black.opacity(0.14))
                .transition(.opacity)
            }
        }
    }
}

private struct DownloadRowMetrics {
    let thumbnailWidth: CGFloat
    let thumbnailHeight: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let spacing: CGFloat
    let isCompact: Bool

    var separatorInset: CGFloat { horizontalPadding + thumbnailWidth + spacing }

    static let library = DownloadRowMetrics(
        thumbnailWidth: 44,
        thumbnailHeight: 66,
        horizontalPadding: 16,
        verticalPadding: 12,
        spacing: 16,
        isCompact: false
    )

    static let compact = DownloadRowMetrics(
        thumbnailWidth: 30,
        thumbnailHeight: 45,
        horizontalPadding: 12,
        verticalPadding: 10,
        spacing: 12,
        isCompact: true
    )
}

/// Shared layout for a download row: thumbnail, title, detail, optional
/// light-line progress, trailing actions, and an inline error.
private struct DownloadRowLayout<Actions: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let metrics: DownloadRowMetrics
    let imageURL: URL?
    let fallbackSystemImage: String
    let title: String
    let detail: String
    var hidesThumbnail = false
    let isFailed: Bool
    let progress: Double?
    let actionError: String?
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: metrics.spacing) {
                if hidesThumbnail {
                    Color.clear.frame(width: metrics.thumbnailWidth, height: 1)
                } else {
                    ActivityThumbnail(
                        url: imageURL,
                        fallbackSystemImage: fallbackSystemImage,
                        width: metrics.thumbnailWidth,
                        height: metrics.thumbnailHeight
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.asterionDisplay(metrics.isCompact ? 13 : 14, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: metrics.isCompact ? 11.5 : 12.5))
                        .foregroundStyle(isFailed ? Color.asterionWarning : Color.asterionMuted)
                        .lineLimit(2)

                    if let progress {
                        HStack(spacing: 10) {
                            AsterionLightLine(fraction: progress, height: 3)
                            Text(progress, format: .percent.precision(.fractionLength(0)))
                                .font(.asterionMono(11, weight: .medium))
                                .foregroundStyle(Color.asterionText)
                                .frame(minWidth: 34, alignment: .trailing)
                        }
                        .padding(.top, 6)
                    }
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    actions()
                }
                .controlSize(metrics.isCompact ? .small : .regular)
            }

            if let actionError {
                Label(actionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.asterionWarning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, metrics.thumbnailWidth + metrics.spacing)
            }
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
        .background(Color.white.opacity(isHovering ? 0.035 : 0))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : AsterionMotion.hover, value: isHovering)
    }
}

/// Smoked, icon-only capsule for row actions (cancel, remove).
private struct DownloadIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var isWorking = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isWorking {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .buttonStyle(.asterionSecondary)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct MediaDownloadRow: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var mediaDownloads: MediaDownloadManager
    let download: MediaDownloadRecord
    let metrics: DownloadRowMetrics
    var isNested = false
    @State private var actionError: String?
    @State private var isWorking = false

    var body: some View {
        DownloadRowLayout(
            metrics: metrics,
            imageURL: download.imageURL,
            fallbackSystemImage: download.mediaType.systemImage,
            title: isNested ? unitLabel : download.contentTitle,
            detail: isNested ? nestedDetailText : downloadDetailText,
            hidesThumbnail: isNested,
            isFailed: download.phase == .failed,
            progress: download.isActive ? download.progress : nil,
            actionError: actionError
        ) {
            if download.isActive {
                DownloadIconButton(systemImage: "xmark", accessibilityLabel: "Cancel download", isWorking: isWorking) {
                    Task { await remove() }
                }
                .help("Cancel download")
                .disabled(isWorking)
            } else if download.phase == .failed {
                Button {
                    Task { await retry() }
                } label: {
                    if metrics.isCompact {
                        Image(systemName: "arrow.clockwise")
                            .accessibilityLabel("Retry")
                    } else {
                        Text("Retry")
                    }
                }
                .buttonStyle(.asterionSecondary)
                .help("Retry download")
                .disabled(isWorking)

                DownloadIconButton(systemImage: "trash", accessibilityLabel: "Remove failed download", isWorking: isWorking) {
                    Task { await remove() }
                }
                .help("Remove failed download")
                .disabled(isWorking)
            } else {
                Button {
                    openDownloadedItem()
                } label: {
                    if metrics.isCompact {
                        Image(systemName: "play.fill")
                            .accessibilityLabel("Play")
                    } else {
                        Label("Play", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.asterionSecondary)
                .help("Play downloaded copy")
                .disabled(isWorking)

                DownloadIconButton(systemImage: "trash", accessibilityLabel: "Remove downloaded copy", isWorking: isWorking) {
                    Task { await remove() }
                }
                .help("Remove downloaded copy")
                .disabled(isWorking)
            }
        }
    }

    private var unitLabel: String {
        if download.mediaType == .movie, download.movieEpisode == nil {
            return "Film"
        }
        return download.detailLabel
    }

    private var nestedDetailText: String {
        switch download.phase {
        case .failed: download.errorMessage ?? "Download failed"
        case .preparing: "Preparing…"
        default: download.downloadQuality?.title ?? "Available offline"
        }
    }

    private var downloadDetailText: String {
        switch download.phase {
        case .preparing:
            [unitLabel, download.downloadQuality?.title, "Preparing…"].compactMap { $0 }.joined(separator: " · ")
        case .downloading:
            [unitLabel, download.downloadQuality?.title].compactMap { $0 }.joined(separator: " · ")
        case .completed:
            [unitLabel, download.downloadQuality?.title].compactMap { $0 }.joined(separator: " · ")
        case .failed:
            [unitLabel, download.errorMessage ?? "Download failed"].joined(separator: " · ")
        }
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
    let metrics: DownloadRowMetrics
    @State private var actionError: String?
    @State private var isRemoving = false
    @State private var isOpening = false

    var body: some View {
        DownloadRowLayout(
            metrics: metrics,
            imageURL: model.novel(id: download.novelID)?.imageURL.flatMap(URL.init(string:)),
            fallbackSystemImage: "book.closed",
            title: download.novelTitle,
            detail: statusText,
            isFailed: download.phase == .failed,
            progress: download.phase == .downloading && download.totalChapters > 0 ? download.progress : nil,
            actionError: actionError
        ) {
            if download.phase == .downloading, download.totalChapters == 0 {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.asterionText)
            } else if download.phase == .failed,
                      let novel = model.novel(id: download.novelID) {
                Button {
                    Task { await retry(novel: novel) }
                } label: {
                    if metrics.isCompact {
                        Image(systemName: "arrow.clockwise")
                            .accessibilityLabel("Retry")
                    } else {
                        Text("Retry")
                    }
                }
                .buttonStyle(.asterionSecondary)
                .help("Retry download")
            } else if download.phase == .completed {
                Button {
                    Task { await openDownload() }
                } label: {
                    if isOpening {
                        ProgressView().controlSize(.small)
                    } else if metrics.isCompact {
                        Image(systemName: "book.fill")
                            .accessibilityLabel("Read")
                    } else {
                        Label("Read", systemImage: "book.fill")
                    }
                }
                .buttonStyle(.asterionSecondary)
                .help("Read downloaded novel")
                .disabled(isRemoving || isOpening)

                DownloadIconButton(systemImage: "trash", accessibilityLabel: "Remove downloaded copy", isWorking: isRemoving) {
                    Task { await removeDownload() }
                }
                .help("Remove downloaded copy")
                .disabled(isRemoving || isOpening)
            }
        }
    }

    private var statusText: String {
        switch download.phase {
        case .downloading:
            if download.totalChapters == 0 { return "Preparing chapters…" }
            return "\(download.completedChapters) of \(download.totalChapters) chapters"
        case .completed:
            if download.totalChapters > 0 {
                return download.totalChapters == 1 ? "1 chapter" : "\(download.totalChapters) chapters"
            }
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
