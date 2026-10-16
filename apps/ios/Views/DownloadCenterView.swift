import AsterionKit
import SwiftUI

struct DownloadCenterView: View {
    @EnvironmentObject private var offlineVideoDownloadService: OfflineVideoDownloadService
    @EnvironmentObject private var tabBarState: TabBarState
    @ObservedObject private var novelDownloads = NovelDownloadManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var collections: [DownloadedNovelCollection] = OfflineChapterStore.shared.cachedCollections ?? []
    @State private var isLoading = OfflineChapterStore.shared.cachedCollections == nil
    @State private var selectedPlayback: PlaybackRequest?
    @State private var novelPendingRemoval: DownloadedNovelCollection?

    private var activeNovelDownloads: [NovelDownloadManager.Snapshot] { novelDownloads.activeDownloads }

    private var activeCount: Int {
        offlineVideoDownloadService.transfers.count + activeNovelDownloads.count
    }

    private var hasDownloads: Bool {
        !collections.isEmpty
            || !offlineVideoDownloadService.records.isEmpty
            || activeCount > 0
    }

    private var pageHorizontalPadding: CGFloat { AsterionLayout.pagePadding(horizontalSizeClass) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    AsterionPageHeader(title: "Downloads", subtitle: downloadSummary)

                    if let error = offlineVideoDownloadService.lastError {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.asterionReading(13, weight: .medium))
                        .foregroundStyle(Color.asterionWarning)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .asterionPanel(cornerRadius: 12)
                        .accessibilityElement(children: .combine)
                    }

                    if isLoading && !hasDownloads {
                        loadingState
                    } else if !hasDownloads {
                        emptyState
                    } else {
                        downloadedContent
                    }
                }
                .frame(maxWidth: 920, alignment: .leading)
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
            .asterionStatusBarScrim()
            .background { AsterionBackdrop() }
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await loadDownloads() }
            .task { await loadDownloads() }
            .navigationDestination(for: DownloadedNovelCollection.self) { collection in
                DownloadedNovelView(collection: collection)
            }
            .fullScreenCover(item: $selectedPlayback, onDismiss: PlaybackOrientationLock.endVideo) { request in
                NativeMediaPlayerView(request: request)
            }
            // A novel download finished or stopped: its folder changed.
            .onChange(of: activeNovelDownloads.map(\.id)) { _, _ in
                Task { await loadDownloads() }
            }
            .confirmationDialog(
                novelPendingRemoval.map { "Remove \($0.title) from this device?" } ?? "",
                isPresented: Binding(
                    get: { novelPendingRemoval != nil },
                    set: { if !$0 { novelPendingRemoval = nil } }
                ),
                titleVisibility: .visible,
                presenting: novelPendingRemoval
            ) { collection in
                Button("Remove download", role: .destructive) {
                    Task { await remove(collection) }
                }
            } message: { collection in
                Text("All \(collection.chapterCount) downloaded chapters are deleted. Reading progress is kept.")
            }
        }
    }

    // MARK: - Summary

    private var downloadSummary: String {
        let active = activeCount
        let offline = offlineVideoDownloadService.records.count + collections.count
        let parts: [String]
        if active > 0 {
            parts = ["\(active) downloading", "\(offline) available offline"]
        } else if offline > 0 {
            parts = [offline == 1 ? "1 item available offline" : "\(offline) items available offline"]
        } else {
            parts = ["Chapters, episodes, and films you save for offline"]
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 14) {
                    AsterionSkeleton(cornerRadius: 8).frame(width: 44, height: 66)
                    VStack(alignment: .leading, spacing: 8) {
                        AsterionSkeleton(cornerRadius: 4).frame(width: 170, height: 12)
                        AsterionSkeleton(cornerRadius: 4).frame(width: 110, height: 10)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .asterionPanel(cornerRadius: 14)
        .accessibilityElement()
        .accessibilityLabel("Loading downloads")
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            AsterionEmptyState(
                symbol: "arrow.down.circle",
                title: "No downloads yet",
                message: "Download chapters of a novel, an episode, or a film and it will be here to enjoy offline."
            )

            Button {
                tabBarState.selectedTab = .browse
            } label: {
                Text("Browse the catalog")
                    .font(.asterionReading(15, weight: .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
            }
            .buttonStyle(AsterionFilledButtonStyle())
            .padding(.top, -24)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sections

    private var downloadedContent: some View {
        let groups = videoGroupsByKind

        return VStack(alignment: .leading, spacing: 30) {
            if activeCount > 0 {
                transfersSection
            }

            if !collections.isEmpty {
                chapterDownloadsSection
            }

            ForEach(groups) { kind in
                section(title: kind.title, count: kind.recordCount) {
                    panel {
                        ForEach(Array(kind.series.enumerated()), id: \.element.id) { index, series in
                            if index > 0 { DownloadSeparator() }
                            if series.records.count == 1, let record = series.records.first {
                                videoRow(record, title: record.title, imageURL: series.imageURL, isNested: false)
                            } else {
                                DownloadSeriesGroup(series: series) { record in
                                    videoRow(record, title: series.episodeTitle(for: record), imageURL: nil, isNested: true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Novels and videos still downloading, each with its progress and a cancel button.
    private var transfersSection: some View {
        section(title: "Downloading", count: activeCount) {
            panel(prominent: true) {
                ForEach(Array(activeNovelDownloads.enumerated()), id: \.element.id) { index, download in
                    if index > 0 { DownloadSeparator() }
                    novelTransferRow(download)
                }
                ForEach(Array(offlineVideoDownloadService.transfers.enumerated()), id: \.element.id) { index, transfer in
                    if index > 0 || !activeNovelDownloads.isEmpty { DownloadSeparator() }
                    HStack(spacing: 14) {
                        DownloadThumbnail(url: nil, fallbackSystemImage: "arrow.down")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(transfer.title)
                                .font(.asterionReading(14.5, weight: .semibold))
                                .foregroundStyle(Color.asterionText)
                                .lineLimit(2)
                            HStack(spacing: 10) {
                                AsterionLightLine(fraction: transfer.progress, height: 3)
                                Text("\(Int((transfer.progress * 100).rounded()))%")
                                    .font(.asterionMono(11, weight: .medium))
                                    .foregroundStyle(Color.asterionText)
                                    .frame(minWidth: 36, alignment: .trailing)
                            }
                            .padding(.top, 6)
                        }
                        .accessibilityElement(children: .combine)

                        DownloadIconButton(systemImage: "xmark", accessibilityLabel: "Cancel download") {
                            offlineVideoDownloadService.cancel(requestID: transfer.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private var chapterDownloadsSection: some View {
        section(title: "Novels", count: collections.count) {
            panel {
                ForEach(Array(collections.enumerated()), id: \.element.id) { index, collection in
                    if index > 0 { DownloadSeparator() }
                    HStack(spacing: 14) {
                        NavigationLink(value: collection) {
                            HStack(spacing: 14) {
                                NovelPosterArt(novel: collection.novel)
                                    .frame(width: 44, height: 66)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(Color.asterionBorder)
                                    }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(collection.title)
                                        .font(.asterionReading(14.5, weight: .semibold))
                                        .foregroundStyle(Color.asterionText)
                                        .lineLimit(2)

                                    Text(chapterDetail(for: collection))
                                        .font(.asterionMono(11, weight: .medium))
                                        .foregroundStyle(Color.asterionMuted)
                                }

                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the downloaded chapters")
                        .contextMenu {
                            Button(role: .destructive) {
                                novelPendingRemoval = collection
                            } label: {
                                Label("Remove download", systemImage: "trash")
                            }
                        }

                        removeButton {
                            novelPendingRemoval = collection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private func novelTransferRow(_ download: NovelDownloadManager.Snapshot) -> some View {
        HStack(spacing: 14) {
            NovelPosterArt(novel: download.novel)
                .frame(width: 44, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.asterionBorder)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(download.novel.title)
                    .font(.asterionReading(14.5, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(2)
                if download.phase == .preparing {
                    Text("Preparing chapters…")
                        .font(.asterionReading(12))
                        .foregroundStyle(Color.asterionMuted)
                        .padding(.top, 2)
                } else {
                    HStack(spacing: 10) {
                        AsterionLightLine(fraction: download.fraction, height: 3)
                        Text(verbatim: String(download.completed) + "/" + String(download.total))
                            .font(.asterionMono(11, weight: .medium))
                            .foregroundStyle(Color.asterionText)
                            .fixedSize()
                    }
                    .padding(.top, 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Downloading " + download.novel.title)
            .accessibilityValue(
                download.phase == .preparing
                    ? "Preparing"
                    : String(download.completed) + " of " + String(download.total) + " chapters"
            )

            DownloadIconButton(systemImage: "xmark", accessibilityLabel: "Cancel download") {
                novelDownloads.cancel(novelID: download.id)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.asterionMuted)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.06), in: Circle())
                .overlay(Circle().strokeBorder(Color.asterionBorder))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove download")
    }

    private func videoRow(_ record: OfflineVideoRecord, title: String, imageURL: URL?, isNested: Bool) -> some View {
        HStack(spacing: 14) {
            Button {
                selectedPlayback = offlineVideoDownloadService.playbackRequest(for: record)
            } label: {
                HStack(spacing: 14) {
                    if isNested {
                        Color.clear.frame(width: 44, height: 1)
                    } else {
                        DownloadThumbnail(
                            url: imageURL,
                            fallbackSystemImage: record.playback?.item.mediaType.systemImage ?? "play.rectangle"
                        )
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.asterionReading(isNested ? 13.5 : 14.5, weight: .semibold))
                            .foregroundStyle(Color.asterionText)
                            .lineLimit(2)
                        Text(videoDetail(for: record))
                            .font(.asterionReading(12))
                            .foregroundStyle(Color.asterionMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Plays offline")

            removeButton {
                offlineVideoDownloadService.remove(record)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isNested ? 10 : 12)
    }

    private func videoDetail(for record: OfflineVideoRecord) -> String {
        var parts: [String] = []
        if let playback = record.playback {
            switch (playback.seasonNumber, playback.episodeNumber) {
            case let (season?, episode?): parts.append("S\(season) · E\(episode)")
            case let (nil, episode?): parts.append("Episode \(episode)")
            default: break
            }
        }
        if offlineVideoDownloadService.isDownloadedAhead(id: record.id) {
            parts.append("Downloaded ahead")
        } else {
            parts.append("Downloaded \(record.downloadedAt.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }

    private func chapterDetail(for collection: DownloadedNovelCollection) -> String {
        let count = collection.chapterCount
        var parts = ["\(count) \(count == 1 ? "chapter" : "chapters")"]
        let ahead = collection.downloadedAheadCount
        if ahead == count {
            parts.append("Downloaded ahead")
        } else if ahead > 0 {
            parts.append("\(ahead) downloaded ahead")
        }
        parts.append(collection.formattedSize)
        return parts.joined(separator: " · ")
    }

    // MARK: - Grouping

    /// Groups finished videos by kind, then by series, keeping newest first.
    private var videoGroupsByKind: [DownloadKind] {
        let records = offlineVideoDownloadService.records.sorted { $0.downloadedAt > $1.downloadedAt }
        var kindOrder: [String] = []
        var seriesOrder: [String: [String]] = [:]
        var buckets: [String: [OfflineVideoRecord]] = [:]

        for record in records {
            let kindKey = record.playback?.item.mediaType.rawValue ?? "other"
            let seriesKey = record.playback.map { "\($0.item.mediaType.rawValue):\($0.item.contentID)" }
                ?? "record:\(record.id)"
            if seriesOrder[kindKey] == nil { kindOrder.append(kindKey) }
            if buckets[seriesKey] == nil { seriesOrder[kindKey, default: []].append(seriesKey) }
            buckets[seriesKey, default: []].append(record)
        }

        let preferred = [MediaAccountType.anime.rawValue, MediaAccountType.movie.rawValue, MediaAccountType.football.rawValue, "other"]
        return kindOrder
            .sorted { (preferred.firstIndex(of: $0) ?? 99) < (preferred.firstIndex(of: $1) ?? 99) }
            .map { kindKey in
                DownloadKind(
                    id: kindKey,
                    series: (seriesOrder[kindKey] ?? []).map { DownloadSeries(id: $0, records: buckets[$0] ?? []) }
                )
            }
    }

    // MARK: - Layout helpers

    private func section<Content: View>(
        title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.asterionTitle(17, weight: .bold))
                    .foregroundStyle(Color.asterionText)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(count, format: .number)
                    .font(.asterionMono(11.5, weight: .medium))
                    .foregroundStyle(Color.asterionFaint)
                    .accessibilityLabel(count == 1 ? "1 item" : "\(count) items")
            }
            .padding(.horizontal, 2)

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

    private func remove(_ collection: DownloadedNovelCollection) async {
        await novelDownloads.cancelAndWait(novelID: collection.novel.id)
        await OfflineChapterStore.shared.removeDownloadedNovel(collection)
        withAnimation(.snappy(duration: 0.25)) {
            collections.removeAll { $0.id == collection.id }
        }
        Haptics.tap()
    }

    private func loadDownloads() async {
        // A cached list stays on screen while the folders are rescanned.
        if collections.isEmpty { isLoading = true }
        defer { isLoading = false }

        let fresh = await OfflineChapterStore.shared.downloadedCollections()
        if fresh != collections { collections = fresh }
    }
}

// MARK: - Grouping models

private struct DownloadKind: Identifiable {
    let id: String
    let series: [DownloadSeries]

    var recordCount: Int { series.reduce(0) { $0 + $1.records.count } }

    var title: String {
        switch id {
        case MediaAccountType.anime.rawValue: "Anime"
        case MediaAccountType.movie.rawValue: "Films & series"
        case MediaAccountType.football.rawValue: "Football"
        default: "Videos"
        }
    }
}

private struct DownloadSeries: Identifiable {
    let id: String
    let records: [OfflineVideoRecord]

    var title: String { records.first?.playback?.item.title ?? records.first?.title ?? "" }
    var imageURL: URL? { records.first(where: { $0.playback?.item.imageURL != nil })?.playback?.item.imageURL }
    var systemImage: String { records.first?.playback?.item.mediaType.systemImage ?? "play.rectangle" }

    func episodeTitle(for record: OfflineVideoRecord) -> String {
        if let unit = record.playback?.unitTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty {
            return unit
        }
        if let episode = record.playback?.episodeNumber {
            return "Episode \(episode)"
        }
        return record.title
    }
}

// MARK: - Rows

/// One series with several downloaded episodes: a summary row that expands
/// to the individual episodes.
private struct DownloadSeriesGroup<EpisodeRow: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    let series: DownloadSeries
    @ViewBuilder let episodeRow: (OfflineVideoRecord) -> EpisodeRow

    private var summary: String {
        let count = series.records.count
        var parts = ["\(count) \(count == 1 ? "episode" : "episodes")"]
        if let latest = series.records.map(\.downloadedAt).max() {
            parts.append(latest.formatted(.relative(presentation: .named)))
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
                HStack(spacing: 14) {
                    DownloadThumbnail(url: series.imageURL, fallbackSystemImage: series.systemImage)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(series.title)
                            .font(.asterionReading(14.5, weight: .semibold))
                            .foregroundStyle(Color.asterionText)
                            .lineLimit(2)
                        Text(summary)
                            .font(.asterionReading(12))
                            .foregroundStyle(Color.asterionMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.asterionMuted)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .frame(width: 34, height: 34)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(series.title)
            .accessibilityValue(summary)
            .accessibilityHint(isExpanded ? "Hides episodes" : "Shows episodes")

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(series.records) { record in
                        DownloadSeparator()
                        episodeRow(record)
                    }
                }
                .background(Color.black.opacity(0.14))
                .transition(.opacity)
            }
        }
    }
}

private struct DownloadThumbnail: View {
    let url: URL?
    let fallbackSystemImage: String

    var body: some View {
        Color.asterionCard
            .overlay {
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.asterionMuted)
            }
            .overlay {
                if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        }
                    }
                }
            }
            .frame(width: 44, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.asterionBorder)
            }
            .accessibilityHidden(true)
    }
}

/// Smoked, icon-only circle for row actions.
private struct DownloadIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.asterionText)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.06), in: Circle())
                .overlay(Circle().strokeBorder(Color.asterionBorder))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct DownloadSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.asterionHairline)
            .frame(height: 1)
            .padding(.leading, 16 + 44 + 14)
    }
}
