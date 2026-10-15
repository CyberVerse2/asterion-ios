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
    @State private var selectedEpisodeRange = 0
    @State private var episodeSearch = ""
    @State private var episodeSearchError: String?

    private let longEpisodeThreshold = 24
    private let episodeRangeSize = 50

    var body: some View {
        Group {
            if store.isLoadingDetail {
                AsterionDetailSkeleton(accessibilityLabel: "Opening anime…")
            } else if let error = store.detailError {
                AsterionEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "Couldn’t open this anime",
                    message: error
                ) {
                    Button("Try again") { Task { await store.retryDetail() } }
                        .buttonStyle(.asterionSecondary)
                }
            } else if let show = store.show {
                detail(show)
            } else {
                AsterionEmptyState(
                    systemImage: "play.rectangle.on.rectangle",
                    title: "Choose an anime",
                    message: "Select a title to see its story and episodes."
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
        ScrollView {
            VStack(alignment: .leading, spacing: AsterionLayout.sectionSpacing) {
                hero(show)
                    .asterionDetailInset()

                AsterionDetailSection(
                    title: "Episodes",
                    count: episodeCountLabel,
                    bleedsContent: usesEpisodeShelf
                ) {
                    episodeShelf(show)
                }

                if !recommendations(for: show).isEmpty {
                    AsterionDetailSection(
                        title: "More like this",
                        count: String(recommendations(for: show).count),
                        bleedsContent: true
                    ) {
                        recommendationShelf(show)
                    }
                }
            }
            .asterionDetailPageFrame()
            .background(alignment: .top) {
                AsterionDetailBackdrop(url: show.imageURL)
            }
            .id("detail-top")
        }
        .hidingScrollIndicators()
        .scrollPosition(id: $scrollPosition, anchor: .top)
        .background(Color.asterionMediaCanvas)
        .task(id: show.id) {
            showsFullSynopsis = false
            downloadError = nil
            scrollPosition = nil
            await Task.yield()
            scrollPosition = "detail-top"
        }
    }

    private func hero(_ show: AnimeShow) -> some View {
        let target = watchTarget(for: show)
        let targetEpisode = target.flatMap { target in
            store.episodes.first { $0.id == target.unitID }
        }

        return AsterionDetailHero(
            imageURL: show.imageURL,
            fallbackSystemImage: "play.rectangle",
            eyebrow: eyebrow(for: show),
            title: show.displayTitle,
            byline: byline(for: show),
            metadata: animeMetadata(for: show),
            secondaryMetadata: animeScores(for: show),
            summary: show.displayDescription,
            showsFullSummary: $showsFullSynopsis
        ) {
            watchActions(show)
        } footer: {
            if case let .resume(percentage) = target?.action, percentage > 0 {
                AsterionDetailProgress(
                    fraction: percentage / 100,
                    caption: targetEpisode.map { "Episode \($0.number)" }
                )
            }

            if let error = model.mediaBookmarkError {
                AsterionDetailNotice(message: error)
            }

            if let downloadError {
                AsterionDetailNotice(message: downloadError)
            }
        }
    }

    private func eyebrow(for show: AnimeShow) -> String {
        (["Anime"] + [show.type, show.status].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        })
        .joined(separator: " · ")
    }

    private func animeMetadata(for show: AnimeShow) -> [String] {
        let date = [show.season, show.dateAired]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        let studio = show.displayStudio.flatMap { $0.isEmpty ? nil : $0 }
        let genres = show.genres
            .prefix(2)
            .map { $0.replacingOccurrences(of: "-", with: " ").capitalized }
            .joined(separator: ", ")

        return [
            date,
            studio == byline(for: show) ? nil : studio,
            "\(max(show.episodesCount, store.episodes.count)) episodes",
            genres.isEmpty ? nil : genres,
        ].compactMap { $0 }
    }

    private func animeScores(for show: AnimeShow) -> [String] {
        [
            show.malScore.flatMap { score in
                let trimmed = score.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty || trimmed == "?" ? nil : "MAL \(trimmed)"
            },
            show.subEpisodes > 0 ? "SUB \(show.subEpisodes)" : nil,
            show.dubEpisodes > 0 ? "DUB \(show.dubEpisodes)" : nil,
        ].compactMap { $0 }
    }

    @ViewBuilder
    private func watchActions(_ show: AnimeShow) -> some View {
        Button {
            guard let episode = preferredEpisode(for: show) else { return }
            openPlayer(show: show, episode: episode)
        } label: {
            Label(watchButtonTitle(for: show), systemImage: "play.fill")
                .lineLimit(1)
        }
        .layoutPriority(1)
        .buttonStyle(.asterionPrimary)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(store.episodes.isEmpty)
        .help("Open in Anime Player")

        mediaBookmarkButton(show)

        animeCollectionDownloadButton(show)
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
                    .frame(width: 16)
            } else {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .frame(width: 16)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(.asterionSecondary)
        .disabled(isUpdating)
        .help(isSaved ? "Remove from saved anime" : "Save anime to your account")
        .accessibilityLabel(isSaved ? "Remove from saved anime" : "Save anime")
    }

    private var usesEpisodeShelf: Bool {
        !store.episodes.isEmpty && store.episodes.count <= longEpisodeThreshold
    }

    @ViewBuilder
    private func episodeShelf(_ show: AnimeShow) -> some View {
        if store.episodes.isEmpty {
            AsterionEmptyState(
                systemImage: "film.stack",
                title: "No episodes yet",
                message: "Episodes appear here as soon as they’re released."
            )
            .frame(minHeight: 220)
            .asterionPanel(cornerRadius: 14)
        } else if store.episodes.count > longEpisodeThreshold {
            longEpisodeBrowser(show)
        } else {
            shortEpisodeShelf(show)
        }
    }

    private func shortEpisodeShelf(_ show: AnimeShow) -> some View {
        let target = watchTarget(for: show)
        let activity = episodeActivity(for: show)

        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(store.episodes) { episode in
                        episodeCard(show: show, episode: episode, target: target, activity: activity[episode.id])
                            .id(episode.id)
                    }
                }
                .padding(.vertical, 6)
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, AsterionLayout.pageInset, for: .scrollContent)
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

    private func longEpisodeBrowser(_ show: AnimeShow) -> some View {
        let target = watchTarget(for: show)
        let activity = episodeActivity(for: show)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(Array(episodeRanges.enumerated()), id: \.element.id) { index, range in
                        Button(range.label) {
                            selectedEpisodeRange = index
                            episodeSearchError = nil
                        }
                    }
                } label: {
                    Text(currentEpisodeRange.map { "Episodes \($0.label)" } ?? "Episodes")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 16)
                .asterionSmokedCapsule()
                .accessibilityLabel("Episode range")
                .accessibilityValue(currentEpisodeRange?.label ?? "Episodes")

                Button {
                    selectedEpisodeRange -= 1
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.asterionSecondary)
                .disabled(selectedEpisodeRange == 0)
                .help("Previous \(episodeRangeSize) episodes")
                .accessibilityLabel("Previous \(episodeRangeSize) episodes")

                Button {
                    selectedEpisodeRange += 1
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.asterionSecondary)
                .disabled(selectedEpisodeRange >= episodeRanges.count - 1)
                .help("Next \(episodeRangeSize) episodes")
                .accessibilityLabel("Next \(episodeRangeSize) episodes")

                Spacer()

                AsterionDetailSearchField(
                    prompt: "Find episode",
                    text: $episodeSearch,
                    monospacedDigits: true,
                    accessibilityLabel: "Find episode number",
                    onSubmit: { findEpisode(show) }
                )
                .frame(width: 160)
            }

            if let episodeSearchError {
                AsterionDetailNotice(message: episodeSearchError)
            }

            ScrollViewReader { proxy in
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 168, maximum: 230), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(currentEpisodeRange?.episodes ?? []) { episode in
                        compactEpisodeCard(show: show, episode: episode, target: target, activity: activity[episode.id])
                            .id(episode.id)
                    }
                }
                .onChange(of: selectedEpisodeRange) { _, _ in
                    if let firstEpisodeID = currentEpisodeRange?.episodes.first?.id {
                        withAnimation(.snappy) {
                            proxy.scrollTo(firstEpisodeID, anchor: .top)
                        }
                    }
                }
            }
        }
        .onChange(of: show.id, initial: true) {
            selectedEpisodeRange = 0
            episodeSearch = ""
            episodeSearchError = nil
        }
    }

    private func compactEpisodeCard(
        show: AnimeShow,
        episode: AnimeEpisode,
        target: MediaWatchTarget?,
        activity: AnimeEpisodeActivity?
    ) -> some View {
        let state = episodeState(episode: episode, target: target, activity: activity)

        return AsterionEpisodeTile(
            number: episode.number,
            status: state.status ?? "Episode",
            progress: state.progress,
            isCurrent: state.isCurrent,
            isWatched: state.isWatched,
            help: "Watch episode \(episode.number)",
            accessibilityLabel: "Open episode \(episode.number) in Anime Player"
        ) {
            openPlayer(show: show, episode: episode)
        } accessory: {
            animeDownloadButton(show: show, episode: episode)
        }
    }

    private var episodeRanges: [AnimeEpisodeRange] {
        AnimeEpisodeRange.pages(for: store.episodes, pageSize: episodeRangeSize)
    }

    private var currentEpisodeRange: AnimeEpisodeRange? {
        guard episodeRanges.indices.contains(selectedEpisodeRange) else { return episodeRanges.first }
        return episodeRanges[selectedEpisodeRange]
    }

    private func findEpisode(_ show: AnimeShow) {
        let query = episodeSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(query),
              let episode = store.episodes.first(where: { $0.number == number }) else {
            episodeSearchError = "Episode not found"
            return
        }

        episodeSearchError = nil
        if let rangeIndex = episodeRanges.firstIndex(where: { $0.contains(episodeID: episode.id) }) {
            selectedEpisodeRange = rangeIndex
        }
        openPlayer(show: show, episode: episode)
    }

    private func episodeCard(
        show: AnimeShow,
        episode: AnimeEpisode,
        target: MediaWatchTarget?,
        activity: AnimeEpisodeActivity?
    ) -> some View {
        let state = episodeState(episode: episode, target: target, activity: activity)

        return AsterionEpisodeCard(
            imageURL: show.imageURL,
            numberLabel: String(format: "EP %02d", episode.number),
            artworkVariant: episode.number,
            title: "Episode \(episode.number)",
            status: state.status ?? "Available to watch",
            progress: state.progress,
            isCurrent: state.isCurrent,
            isWatched: state.isWatched,
            help: "Watch episode \(episode.number)",
            accessibilityLabel: "Open episode \(episode.number) in Anime Player"
        ) {
            openPlayer(show: show, episode: episode)
        } accessory: {
            animeDownloadButton(show: show, episode: episode)
        }
    }

    /// Watched, partially watched, and up-next state for one episode, read
    /// from the account's playback progress and history.
    private func episodeState(
        episode: AnimeEpisode,
        target: MediaWatchTarget?,
        activity: AnimeEpisodeActivity?
    ) -> (status: String?, progress: Double?, isCurrent: Bool, isWatched: Bool) {
        let isWatched = activity?.completed == true
        let percentage = activity.map { min(100, max(0, $0.percentage)) } ?? 0
        let progress: Double? = !isWatched && percentage > 0 ? percentage / 100 : nil

        if target?.unitID == episode.id {
            let status: String = switch target?.action {
            case let .resume(value) where Int(value.rounded()) > 0:
                "Continue · \(Int(value.rounded()))%"
            case .rewatch:
                "Watch again"
            default:
                "Up next"
            }
            return (status, progress, true, isWatched)
        }
        if isWatched {
            return ("Watched", nil, false, true)
        }
        if let progress {
            return ("\(Int((progress * 100).rounded()))% watched", progress, false, false)
        }
        return (nil, nil, false, false)
    }

    private func episodeActivity(for show: AnimeShow) -> [String: AnimeEpisodeActivity] {
        var activity: [String: AnimeEpisodeActivity] = [:]
        for entry in model.mediaHistory where entry.mediaType == .anime && entry.contentId == show.slug {
            guard activity[entry.unitId] == nil else { continue }
            activity[entry.unitId] = AnimeEpisodeActivity(
                percentage: entry.completed ? 100 : entry.percentage,
                completed: entry.completed
            )
        }
        for progress in model.continueWatching where progress.mediaType == .anime && progress.contentId == show.slug {
            activity[progress.unitId] = AnimeEpisodeActivity(
                percentage: progress.percentage,
                completed: progress.completed
            )
        }
        return activity
    }

    private func recommendationShelf(_ show: AnimeShow) -> some View {
        HomeHorizontalShelf(
            items: recommendations(for: show),
            itemWidth: AsterionCardMetrics.posterWidth,
            spacing: 18,
            height: AsterionCardMetrics.posterShelfHeight
        ) { title in
            AsterionPosterCard(
                imageURL: title.imageURL,
                title: title.displayTitle,
                subtitle: title.episodeLabel ?? title.type ?? "Anime",
                fallbackSystemImage: "play.rectangle"
            ) {
                Task { await store.select(title, force: true) }
            }
        }
    }

    private func recommendations(for show: AnimeShow) -> [AnimeTitle] {
        var seen = Set<String>()
        return (store.titles + store.seasonalTitles + store.newReleaseTitles)
            .filter { title in
                title.slug != show.slug && seen.insert(title.slug).inserted
            }
            .prefix(10)
            .map { $0 }
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
                    .tint(Color.asterionText)
                    .frame(width: 30, height: 30)
            } else {
                AsterionDetailCircleIcon(
                    systemImage: label.icon,
                    tint: record?.phase == .completed ? .asterionSuccess : .asterionText
                )
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
                    .frame(width: 16)
            } else {
                Image(systemName: "arrow.down.to.line")
                    .frame(width: 16)
            }
        }
        .buttonStyle(.asterionSecondary)
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
        let selections = plan.groups.flatMap { group in
            group.episodes.compactMap { episode in
                selectedIDs.contains(plannerItemID(show: group.show, episode: episode))
                    ? AnimeDownloadSelection(show: group.show, episode: episode)
                    : nil
            }
        }
        let failures = await ConcurrentBatch.run(
            selections,
            maximumConcurrentTasks: 12
        ) { selection -> String? in
            do {
                try await mediaDownloads.downloadAnime(
                    show: selection.show,
                    episode: selection.episode,
                    quality: quality
                )
                return nil
            } catch {
                return "\(selection.show.displayTitle), episode \(selection.episode.number): \(error.localizedDescription)"
            }
        }
        .compactMap { $0 }
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
            ("arrow.down.to.line", "Downloading episode")
        case .completed:
            ("checkmark.circle.fill", "Available offline. Manage it in Downloads")
        case .failed:
            ("arrow.clockwise", "Retry episode download")
        case nil:
            ("arrow.down.to.line", "Download episode for offline viewing")
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
        case .resume:
            return "Continue episode \(episode.number)"
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
}

private struct AnimeDownloadSelection: Sendable {
    let show: AnimeShow
    let episode: AnimeEpisode
}

private struct AnimeDownloadPlan: Identifiable {
    let id = UUID()
    let title: String
    let groups: [AnimeDownloadGroup]
    let initialSelection: Set<String>
}

private struct AnimeEpisodeActivity {
    let percentage: Double
    let completed: Bool
}
