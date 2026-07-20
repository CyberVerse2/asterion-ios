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
        .background(Color.asterionMediaCanvas)
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
        ZStack(alignment: .top) {
            ambientBackdrop(show)

            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    hero(show)
                        .id("detail-top")

                    detailSection(title: "Episodes", trailing: episodeCountLabel) {
                        episodeShelf(show)
                    }
                }
                .frame(maxWidth: 1_180, alignment: .leading)
                .padding(.horizontal, 46)
                .padding(.top, 30)
                .padding(.bottom, 64)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .hidingScrollIndicators()
            .scrollPosition(id: $scrollPosition, anchor: .top)
        }
        .background(Color.asterionMediaCanvas)
        .task(id: show.id) {
            showsFullSynopsis = false
            downloadError = nil
            scrollPosition = nil
            await Task.yield()
            scrollPosition = "detail-top"
        }
    }

    private func ambientBackdrop(_ show: AnimeShow) -> some View {
        AsyncImage(url: show.imageURL) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 42)
                    .saturation(0.82)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 590)
        .clipped()
        .opacity(0.42)
        .overlay(Color.black.opacity(0.34))
        .mask {
            LinearGradient(
                colors: [.black, .black.opacity(0.82), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func hero(_ show: AnimeShow) -> some View {
        HStack(alignment: .center, spacing: 38) {
            AsyncImage(url: show.imageURL) { phase in
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
                Text("ANIME")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.blue)

                Text(show.displayTitle)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)
                    .textSelection(.enabled)

                if let byline = byline(for: show), !byline.isEmpty {
                    Text(byline)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.asterionText.opacity(0.76))
                        .lineLimit(2)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { metadataItems(for: show) }
                    VStack(alignment: .leading, spacing: 8) { metadataItems(for: show) }
                }

                if let summary = show.displayDescription, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.asterionText.opacity(0.84))
                        .lineSpacing(4)
                        .lineLimit(showsFullSynopsis ? nil : 3)
                        .frame(maxWidth: 650, alignment: .leading)
                        .textSelection(.enabled)

                    if summary.count > 240 {
                        Button(showsFullSynopsis ? "Show less" : "More") {
                            showsFullSynopsis.toggle()
                        }
                        .buttonStyle(.link)
                        .font(.caption.weight(.semibold))
                        .tint(.asterionAccent)
                    }
                }

                watchAction(show)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 390)
    }

    @ViewBuilder
    private func metadataItems(for show: AnimeShow) -> some View {
        ForEach(animeMetadata(for: show)) { item in
            Label(item.value, systemImage: item.icon)
                .font(.callout)
                .foregroundStyle(Color.asterionText.opacity(0.68))
                .lineLimit(1)
        }
    }

    private func animeMetadata(for show: AnimeShow) -> [AsterionDetailMetadata] {
        let mediaSummary = [show.type, show.status]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let date = [show.season, show.dateAired]
            .compactMap { $0 }
            .first { !$0.isEmpty }

        return [
            mediaSummary.isEmpty ? nil : AsterionDetailMetadata(icon: "play.rectangle", value: mediaSummary),
            date.map { AsterionDetailMetadata(icon: "calendar", value: $0) },
            show.displayStudio.flatMap { $0.isEmpty ? nil : AsterionDetailMetadata(icon: "building.2", value: $0) },
            AsterionDetailMetadata(
                icon: "film.stack",
                value: "\(max(show.episodesCount, store.episodes.count)) episodes"
            ),
        ].compactMap { $0 }
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
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 12))
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
                    .frame(width: 20)
            } else {
                Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                    .labelStyle(.iconOnly)
                    .frame(width: 20)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(Color.asterionText)
        .disabled(isUpdating)
        .help(isSaved ? "Remove from saved anime" : "Save anime to your account")
        .accessibilityLabel(isSaved ? "Remove from saved anime" : "Save anime")
    }

    @ViewBuilder
    private func episodeShelf(_ show: AnimeShow) -> some View {
        if store.episodes.isEmpty {
            ContentUnavailableView("No episodes", systemImage: "film.stack")
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 15) {
                        ForEach(store.episodes) { episode in
                            episodeCard(show: show, episode: episode)
                                .id(episode.id)
                        }
                    }
                    .padding(.vertical, 2)
                    .scrollTargetLayout()
                }
                .hidingScrollIndicators()
                .scrollTargetBehavior(.viewAligned)
                .task(id: show.id) {
                    try? await Task.sleep(for: .milliseconds(120))
                    if let firstEpisodeID = store.episodes.first?.id {
                        proxy.scrollTo(firstEpisodeID, anchor: .leading)
                    }
                }
            }
        }
    }

    private func episodeCard(show: AnimeShow, episode: AnimeEpisode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                openPlayer(show: show, episode: episode)
            } label: {
                ZStack(alignment: .topLeading) {
                    AsyncImage(url: show.imageURL) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                                .scaleEffect(1.08 + CGFloat(episode.number % 3) * 0.05)
                                .offset(x: CGFloat((episode.number % 3) - 1) * 10)
                        } else {
                            Color.asterionCard
                        }
                    }
                    .frame(width: 246, height: 138)
                    .clipped()

                    Text(String(episode.number))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(10)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open episode \(episode.number) in Anime Player")

            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Episode \(episode.number)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                    Text(episodeStatus(show: show, episode: episode))
                        .font(.caption)
                        .foregroundStyle(Color.asterionMuted)
                }

                Spacer(minLength: 4)
                animeDownloadButton(show: show, episode: episode)
            }
            .padding(11)
        }
        .frame(width: 246)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.09))
        }
    }

    private func episodeStatus(show: AnimeShow, episode: AnimeEpisode) -> String {
        let target = watchTarget(for: show)
        if target?.unitID == episode.id {
            return "Up next"
        }
        return "Available to watch"
    }

    private func animeDownloadButton(
        show: AnimeShow,
        episode: AnimeEpisode
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
                    .frame(width: 30, height: 30)
            } else {
                Image(systemName: label.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.asterionText.opacity(0.82))
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.08))
                    }
            }
        }
        .buttonStyle(.plain)
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
                    .frame(width: 20)
            } else {
                Label("Download", systemImage: "arrow.down.circle")
                    .labelStyle(.iconOnly)
                    .frame(width: 20)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(Color.asterionText)
        .disabled(isPreparingDownloadPlan || store.episodes.isEmpty)
        .help("Choose episodes and quality across every season")
        .accessibilityLabel("Choose episodes and quality to download")
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
    ) -> (icon: String, help: String) {
        switch record?.phase {
        case .preparing, .downloading:
            ("arrow.down.circle.fill", "Downloading episode")
        case .completed:
            ("checkmark.circle.fill", "Available offline. Manage it in Downloads")
        case .failed:
            ("arrow.clockwise", "Retry episode download")
        case nil:
            ("arrow.down.circle", "Download episode for offline viewing")
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
