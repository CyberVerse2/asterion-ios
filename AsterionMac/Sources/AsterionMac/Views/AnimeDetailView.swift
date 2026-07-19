import SwiftUI

struct AnimeDetailView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var mediaDownloads: MediaDownloadManager
    @ObservedObject var store: AnimeStore

    @State private var scrollPosition: String?
    @State private var showsFullSynopsis = false
    @State private var downloadError: String?
    @State private var downloadPlan: AnimeDownloadPlan?
    @State private var isPreparingDownloadPlan = false

    var body: some View {
        Group {
            if store.isLoadingDetail {
                ProgressView("Opening anime…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.detailError {
                ContentUnavailableView {
                    Label("Couldn’t open this anime", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await store.retryDetail() } }
                }
            } else if let show = store.show {
                detail(show)
            } else {
                ContentUnavailableView(
                    "Choose an anime",
                    systemImage: "play.rectangle.on.rectangle",
                    description: Text("Select a title to see its story and episodes.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .sheet(item: $downloadPlan) { plan in
            MediaDownloadPlannerView(
                title: plan.title,
                groups: plannerGroups(for: plan.groups),
                initiallySelectedItemIDs: plan.initialSelection
            ) { quality, selectedIDs in
                Task { await startDownloads(plan, selectedIDs: selectedIDs, quality: quality) }
            }
        }
    }

    private func detail(_ show: AnimeShow) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                hero(show)
                    .id("detail-top")

                watchAction(show)
                Divider()

                if let synopsis = show.displayDescription, !synopsis.isEmpty {
                    detailSection(title: "Synopsis") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(showsFullSynopsis ? synopsis : synopsisPreview(synopsis))
                                .font(.asterionReading(15))
                                .foregroundStyle(Color.asterionReaderText)
                                .lineSpacing(5)
                                .textSelection(.enabled)

                            if synopsisPreview(synopsis) != synopsis {
                                Button {
                                    showsFullSynopsis.toggle()
                                } label: {
                                    Label(
                                        showsFullSynopsis ? "Show less" : "Read full synopsis",
                                        systemImage: showsFullSynopsis ? "chevron.up" : "chevron.down"
                                    )
                                    .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.link)
                                .tint(.asterionAccent)
                            }
                        }
                    }

                    Divider()
                }

                detailSection(title: "Episodes", trailing: episodeCountLabel) {
                    episodeList(show)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .hidingScrollIndicators()
        .scrollPosition(id: $scrollPosition, anchor: .top)
        .background(.background)
        .navigationTitle(show.displayTitle)
        .task(id: show.id) {
            showsFullSynopsis = false
            downloadError = nil
            scrollPosition = nil
            await Task.yield()
            scrollPosition = "detail-top"
        }
    }

    private func hero(_ show: AnimeShow) -> some View {
        HStack(alignment: .top, spacing: 20) {
            MediaCoverView(url: show.imageURL, width: 138, height: 198)

            VStack(alignment: .leading, spacing: 10) {
                Text(show.displayTitle)
                    .asterionDetailTitleStyle()

                if let byline = byline(for: show) {
                    Text(byline)
                        .font(.asterionDisplay(14, weight: .medium))
                        .foregroundStyle(Color.asterionText)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    let mediaSummary = [show.type, show.status]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                    if !mediaSummary.isEmpty {
                        AnimeMetadataLine(icon: "play.rectangle", value: mediaSummary)
                    }

                    if let season = show.season, !season.isEmpty {
                        AnimeMetadataLine(icon: "calendar", value: season)
                    } else if let dateAired = show.dateAired, !dateAired.isEmpty {
                        AnimeMetadataLine(icon: "calendar", value: dateAired)
                    }

                    if let studio = show.displayStudio, !studio.isEmpty {
                        AnimeMetadataLine(icon: "building.2", value: studio)
                    }

                    AnimeMetadataLine(
                        icon: "film.stack",
                        value: "\(max(show.episodesCount, store.episodes.count)) episodes"
                    )
                }
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func watchAction(_ show: AnimeShow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    guard let episode = preferredEpisode(for: show) else { return }
                    openPlayer(show: show, episode: episode)
                } label: {
                    Label(watchButtonTitle(for: show), systemImage: "play.fill")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 10))
                .controlSize(.large)
                .tint(.asterionAccent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(store.episodes.isEmpty)
                .help("Open in Anime Player")

                mediaBookmarkButton(show)

                animeCollectionDownloadButton(show)
            }

            if let error = model.mediaBookmarkError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.asterionAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let downloadError {
                Label(downloadError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.asterionAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func mediaBookmarkButton(_ show: AnimeShow) -> some View {
        let item = MediaItemDescriptor(
            mediaType: .anime,
            contentID: show.slug,
            title: show.displayTitle,
            subtitle: show.season ?? show.type,
            imageURL: show.imageURL
        )
        let isSaved = model.isMediaBookmarked(item.key)
        let isUpdating = model.isUpdatingMediaBookmark(item.key)

        return Button {
            guard model.isSignedIn else {
                openWindow(id: "authentication")
                return
            }
            Task { await model.toggleMediaBookmark(item) }
        } label: {
            if isUpdating {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 72)
            } else {
                Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                    .frame(width: 72)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isUpdating)
        .help(isSaved ? "Remove from saved anime" : "Save anime to your account")
    }

    @ViewBuilder
    private func episodeList(_ show: AnimeShow) -> some View {
        if store.episodes.isEmpty {
            ContentUnavailableView("No episodes", systemImage: "film.stack")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(store.episodes) { episode in
                    HStack(spacing: 10) {
                        Button {
                            openPlayer(show: show, episode: episode)
                        } label: {
                            HStack(spacing: 14) {
                                Text(String(episode.number))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Color.asterionMuted)
                                    .frame(width: 34, alignment: .trailing)

                                Text("Episode \(episode.number)")
                                    .font(.asterionDisplay(14, weight: .medium))
                                    .foregroundStyle(Color.asterionText)
                                    .lineLimit(1)

                                Spacer()

                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption)
                                    .foregroundStyle(Color.asterionMuted)
                            }
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open episode \(episode.number) in Anime Player")

                        animeDownloadButton(show: show, episode: episode, showsLabel: false)
                    }

                    Divider()
                }
            }
        }
    }

    private func animeDownloadButton(
        show: AnimeShow,
        episode: AnimeEpisode,
        showsLabel: Bool
    ) -> some View {
        let record = mediaDownloads.record(
            mediaType: .anime,
            contentID: show.slug,
            unitID: episode.id
        )
        let label = downloadLabel(for: record)

        return Button {
            presentEpisodeDownload(show: show, episode: episode)
        } label: {
            if record?.isActive == true {
                ProgressView(value: record?.progress ?? 0)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .frame(width: showsLabel ? 84 : 28)
            } else if showsLabel {
                Label(label.title, systemImage: label.icon)
                    .frame(width: 84)
            } else {
                Image(systemName: label.icon)
                    .frame(width: 28, height: 28)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(showsLabel ? .large : .small)
        .disabled(record?.isActive == true || record?.phase == .completed)
        .help(label.help)
        .accessibilityLabel(label.help)
    }

    private func animeCollectionDownloadButton(_ show: AnimeShow) -> some View {
        Button {
            Task { await prepareSeriesDownload(show) }
        } label: {
            if isPreparingDownloadPlan {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 84)
            } else {
                Label("Download", systemImage: "arrow.down.circle")
                    .frame(width: 84)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isPreparingDownloadPlan || store.episodes.isEmpty)
        .help("Choose episodes and quality across every season")
    }

    private func presentEpisodeDownload(show: AnimeShow, episode: AnimeEpisode) {
        let group = AnimeDownloadGroup(show: show, episodes: [episode])
        let itemID = plannerItemID(show: show, episode: episode)
        downloadPlan = AnimeDownloadPlan(
            title: "Download \(show.displayTitle)",
            groups: [group],
            initialSelection: plannerItemIsUnavailable(show: show, episode: episode) ? [] : [itemID]
        )
    }

    private func prepareSeriesDownload(_ show: AnimeShow) async {
        downloadError = nil
        isPreparingDownloadPlan = true
        defer { isPreparingDownloadPlan = false }
        do {
            let groups = try await store.downloadGroups(for: show)
            let selection = Set(
                groups.flatMap { group in
                    group.episodes.compactMap { episode in
                        plannerItemIsUnavailable(show: group.show, episode: episode)
                            ? nil
                            : plannerItemID(show: group.show, episode: episode)
                    }
                }
            )
            downloadPlan = AnimeDownloadPlan(
                title: "Download \(show.displayTitle)",
                groups: groups,
                initialSelection: selection
            )
        } catch {
            downloadError = error.localizedDescription
        }
    }

    private func startDownloads(
        _ plan: AnimeDownloadPlan,
        selectedIDs: Set<String>,
        quality: MediaDownloadQuality
    ) async {
        downloadError = nil
        var failures: [String] = []
        for group in plan.groups {
            for episode in group.episodes
            where selectedIDs.contains(plannerItemID(show: group.show, episode: episode)) {
                do {
                    try await mediaDownloads.downloadAnime(
                        show: group.show,
                        episode: episode,
                        quality: quality
                    )
                } catch {
                    failures.append("\(group.show.displayTitle), episode \(episode.number): \(error.localizedDescription)")
                }
            }
        }
        if !failures.isEmpty {
            downloadError = downloadFailureMessage(failures)
        }
    }

    private func plannerGroups(for groups: [AnimeDownloadGroup]) -> [MediaDownloadPlannerGroup] {
        groups.map { group in
            MediaDownloadPlannerGroup(
                id: group.id,
                title: group.show.displayTitle,
                countLabel: group.episodes.count == 1 ? "1 episode" : "\(group.episodes.count) episodes",
                items: group.episodes.map { episode in
                    let record = mediaDownloads.record(
                        mediaType: .anime,
                        contentID: group.show.slug,
                        unitID: episode.id
                    )
                    return MediaDownloadPlannerItem(
                        id: plannerItemID(show: group.show, episode: episode),
                        title: "Episode \(episode.number)",
                        detail: nil,
                        isUnavailable: record?.isActive == true || record?.phase == .completed,
                        status: plannerStatus(for: record)
                    )
                }
            )
        }
    }

    private func plannerItemID(show: AnimeShow, episode: AnimeEpisode) -> String {
        "\(show.slug)|\(episode.id)"
    }

    private func plannerItemIsUnavailable(show: AnimeShow, episode: AnimeEpisode) -> Bool {
        let record = mediaDownloads.record(
            mediaType: .anime,
            contentID: show.slug,
            unitID: episode.id
        )
        return record?.isActive == true || record?.phase == .completed
    }

    private func plannerStatus(for record: MediaDownloadRecord?) -> String? {
        switch record?.phase {
        case .preparing, .downloading: "Downloading"
        case .completed: "Downloaded"
        case .failed: "Retry"
        case nil: nil
        }
    }

    private func downloadFailureMessage(_ failures: [String]) -> String {
        let summary = failures.prefix(3).joined(separator: "\n")
        let remainder = failures.count - min(3, failures.count)
        return remainder > 0 ? "\(summary)\n…and \(remainder) more." : summary
    }

    private func downloadLabel(
        for record: MediaDownloadRecord?
    ) -> (title: String, icon: String, help: String) {
        switch record?.phase {
        case .preparing, .downloading:
            ("Loading", "arrow.down.circle.fill", "Downloading episode")
        case .completed:
            ("Offline", "checkmark.circle.fill", "Available offline. Manage it in Downloads")
        case .failed:
            ("Retry", "arrow.clockwise", "Retry episode download")
        case nil:
            ("Download", "arrow.down.circle", "Download episode for offline viewing")
        }
    }

    private func preferredEpisode(for show: AnimeShow) -> AnimeEpisode? {
        guard let target = watchTarget(for: show) else { return nil }
        return store.episodes.first { $0.id == target.unitID }
    }

    private func watchButtonTitle(for show: AnimeShow) -> String {
        guard let target = watchTarget(for: show),
              let episode = store.episodes.first(where: { $0.id == target.unitID }) else {
            return "No episodes available"
        }
        switch target.action {
        case .start:
            return "Watch episode \(episode.number)"
        case let .resume(percentage):
            let roundedPercentage = Int(percentage.rounded())
            return roundedPercentage > 0
                ? "Continue episode \(episode.number) · \(roundedPercentage)%"
                : "Continue episode \(episode.number)"
        case .next:
            return "Watch next · Episode \(episode.number)"
        case .rewatch:
            return "Watch episode \(episode.number) again"
        }
    }

    private func watchTarget(for show: AnimeShow) -> MediaWatchTarget? {
        let orderedEpisodeIDs = store.episodes
            .sorted { $0.number < $1.number }
            .map(\.id)
        return model.mediaWatchTarget(
            mediaType: .anime,
            contentID: show.slug,
            orderedUnitIDs: orderedEpisodeIDs
        )
    }

    private var episodeCountLabel: String? {
        store.episodes.isEmpty ? nil : "\(store.episodes.count) episodes"
    }

    private func openPlayer(show: AnimeShow, episode: AnimeEpisode) {
        openWindow(
            value: AnimePlayerRoute(
                slug: show.slug,
                title: show.displayTitle,
                initialEpisodeID: episode.id
            )
        )
    }

    private func byline(for show: AnimeShow) -> String? {
        if let japaneseTitle = show.displayJapaneseTitle, !japaneseTitle.isEmpty {
            return japaneseTitle
        }
        return show.genres.first?
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func synopsisPreview(_ synopsis: String) -> String {
        guard synopsis.count > 280 else { return synopsis }
        let prefix = String(synopsis.prefix(280))
        if let sentenceEnd = prefix.lastIndex(where: { ".!?".contains($0) }) {
            return String(prefix[...sentenceEnd])
        }
        if let wordBoundary = prefix.lastIndex(where: { $0.isWhitespace }) {
            return String(prefix[..<wordBoundary]) + "…"
        }
        return prefix + "…"
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

private struct AnimeDownloadPlan: Identifiable {
    let id = UUID()
    let title: String
    let groups: [AnimeDownloadGroup]
    let initialSelection: Set<String>
}

private struct AnimeMetadataLine: View {
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
