import SwiftUI

struct MovieDetailView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var mediaDownloads: MediaDownloadManager
    @ObservedObject var store: MovieStore

    @State private var selectedSeason: Int?
    @State private var showsFullSynopsis = false
    @State private var downloadError: String?
    @State private var downloadPlan: MovieDownloadPlan?

    var body: some View {
        Group {
            if store.isLoadingDetail {
                ProgressView("Opening title…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.detailError {
                ContentUnavailableView {
                    Label("Couldn’t open this title", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await store.retryDetail() } }
                }
            } else if let show = store.show {
                detail(show)
            } else {
                ContentUnavailableView(
                    "Choose a title",
                    systemImage: "film",
                    description: Text("Select a movie or TV show to see its details.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .sheet(item: $downloadPlan) { plan in
            MediaDownloadPlannerView(
                title: plan.title,
                groups: plannerGroups(for: plan),
                initiallySelectedItemIDs: plan.initialSelection
            ) { quality, selectedIDs in
                Task { await startDownloads(plan, selectedIDs: selectedIDs, quality: quality) }
            }
        }
    }

    private func detail(_ show: MovieShow) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                hero(show)
                watchAction(show)

                if let synopsis = show.description, !synopsis.isEmpty {
                    Divider()
                    detailSection(title: "Synopsis") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(showsFullSynopsis ? synopsis : synopsisPreview(synopsis))
                                .font(.asterionReading(15))
                                .foregroundStyle(Color.asterionReaderText)
                                .lineSpacing(5)
                                .textSelection(.enabled)
                            if synopsisPreview(synopsis) != synopsis {
                                Button(showsFullSynopsis ? "Show less" : "Read full synopsis") {
                                    showsFullSynopsis.toggle()
                                }
                                .buttonStyle(.link)
                                .tint(.asterionAccent)
                            }
                        }
                    }
                }

                if show.isSeries {
                    Divider()
                    detailSection(title: "Episodes", trailing: "\(store.episodes.count) available") {
                        episodeBrowser(show)
                    }
                }

                if !show.actors.isEmpty {
                    Divider()
                    detailSection(title: "Cast") {
                        Text(show.actors.prefix(8).joined(separator: " · "))
                            .font(.callout)
                            .foregroundStyle(Color.asterionMuted)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .hidingScrollIndicators()
        .navigationTitle(show.displayTitle)
        .task(id: show.id) {
            showsFullSynopsis = false
            downloadError = nil
            selectedSeason = preferredEpisode(for: show)?.season ?? availableSeasons.first
        }
        .onChange(of: activeProgress(for: show)?.unitId) { _, unitID in
            guard let unitID,
                  let episode = store.episodes.first(where: { $0.id == unitID }) else {
                return
            }
            selectedSeason = episode.season
        }
    }

    private func hero(_ show: MovieShow) -> some View {
        HStack(alignment: .top, spacing: 20) {
            MediaCoverView(url: show.imageURL, width: 138, height: 198)

            VStack(alignment: .leading, spacing: 10) {
                Text(show.displayTitle)
                    .asterionDetailTitleStyle()

                if !show.genres.isEmpty {
                    Text(show.genres.prefix(3).joined(separator: " · "))
                        .font(.asterionDisplay(14, weight: .medium))
                        .foregroundStyle(Color.asterionText)
                        .lineLimit(2)
                }

                VStack(alignment: .leading, spacing: 8) {
                    metadataLine(
                        icon: show.isSeries ? "tv" : "film",
                        value: show.isSeries ? "TV Series" : "Movie"
                    )
                    if let year = show.releaseYear {
                        metadataLine(icon: "calendar", value: year)
                    }
                    if let duration = show.duration, !duration.isEmpty {
                        metadataLine(icon: "clock", value: duration)
                    }
                    if let director = show.director, !director.isEmpty {
                        metadataLine(icon: "person.fill", value: director)
                    }
                    if let rating = show.imdbRating {
                        metadataLine(icon: "star.fill", value: "IMDb \(rating)")
                    }
                }
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func watchAction(_ show: MovieShow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    openPlayer(show: show, episode: preferredEpisode(for: show))
                } label: {
                    Label(watchButtonTitle(show), systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 10))
                .controlSize(.large)
                .tint(.asterionAccent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(show.isSeries ? store.episodes.isEmpty : false)
                .help("Open in Asterion Player")

                mediaBookmarkButton(show)

                movieCollectionDownloadButton(show)
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

    private func mediaBookmarkButton(_ show: MovieShow) -> some View {
        let item = MediaItemDescriptor(
            mediaType: .movie,
            contentID: show.slug,
            title: show.displayTitle,
            subtitle: show.isSeries ? "TV Series" : "Movie",
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
        .disabled(isUpdating)
        .help(isSaved ? "Remove from saved movies" : "Save this title to your account")
        .accessibilityLabel(isSaved ? "Remove from saved movies" : "Save this title")
    }

    private func episodeBrowser(_ show: MovieShow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if availableSeasons.count > 1 {
                Picker("Season", selection: seasonBinding) {
                    ForEach(availableSeasons, id: \.self) { season in
                        Text("Season \(season)").tag(season)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if episodesForSelectedSeason.isEmpty {
                ContentUnavailableView("No episodes", systemImage: "film.stack")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(episodesForSelectedSeason) { episode in
                        let progress = episodeProgress(for: episode, in: show)

                        HStack(spacing: 10) {
                            Button {
                                openPlayer(show: show, episode: episode)
                            } label: {
                                HStack(spacing: 14) {
                                    Text(String(episode.number))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Color.asterionMuted)
                                        .frame(width: 30, alignment: .trailing)
                                    Text(episode.title)
                                        .font(.asterionDisplay(14, weight: .medium))
                                        .foregroundStyle(Color.asterionText)
                                        .lineLimit(1)
                                    Spacer()
                                    episodeProgressAccessory(progress)
                                }
                                .padding(.vertical, 11)
                                .padding(.horizontal, 8)
                                .background(
                                    progress?.isCurrent == true
                                        ? Color.asterionAccent.opacity(0.08)
                                        : .clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(episodeProgressHelp(progress, episode: episode))

                            movieDownloadButton(show: show, episode: episode, showsLabel: false)
                        }
                        Divider()
                    }
                }
            }
        }
    }

    private func movieDownloadButton(
        show: MovieShow,
        episode: MovieEpisode?,
        showsLabel: Bool
    ) -> some View {
        let unitID = episode?.id ?? show.slug
        let record = mediaDownloads.record(
            mediaType: .movie,
            contentID: show.slug,
            unitID: unitID
        )
        let label = downloadLabel(for: record, isEpisode: episode != nil)

        return Button {
            presentMovieDownload(show: show, selectedEpisode: episode)
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
        .disabled(
            record?.isActive == true
                || record?.phase == .completed
                || (show.isSeries && episode == nil)
        )
        .help(label.help)
        .accessibilityLabel(label.help)
    }

    private func movieCollectionDownloadButton(_ show: MovieShow) -> some View {
        let help = show.isSeries
            ? "Choose episodes and quality across every season"
            : "Choose download quality"

        return Button {
            presentMovieDownload(show: show, selectedEpisode: nil)
        } label: {
            Label("Download", systemImage: "arrow.down.circle")
                .labelStyle(.iconOnly)
                .frame(width: 20)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(show.isSeries && store.episodes.isEmpty)
        .help(help)
        .accessibilityLabel(help)
    }

    private func presentMovieDownload(show: MovieShow, selectedEpisode: MovieEpisode?) {
        let units: [MovieDownloadUnit]
        if let selectedEpisode {
            units = [MovieDownloadUnit(show: show, episode: selectedEpisode)]
        } else if show.isSeries {
            units = store.episodes.map { MovieDownloadUnit(show: show, episode: $0) }
        } else {
            units = [MovieDownloadUnit(show: show, episode: nil)]
        }

        let selection = Set(units.compactMap { unit in
            plannerItemIsUnavailable(unit) ? nil : unit.id
        })
        downloadPlan = MovieDownloadPlan(
            title: "Download \(show.displayTitle)",
            units: units,
            initialSelection: selection
        )
    }

    private func startDownloads(
        _ plan: MovieDownloadPlan,
        selectedIDs: Set<String>,
        quality: MediaDownloadQuality
    ) async {
        downloadError = nil
        var failures: [String] = []
        for unit in plan.units where selectedIDs.contains(unit.id) {
            do {
                try await mediaDownloads.downloadMovie(
                    show: unit.show,
                    episode: unit.episode,
                    quality: quality
                )
            } catch {
                failures.append("\(unit.title): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            let summary = failures.prefix(3).joined(separator: "\n")
            let remainder = failures.count - min(3, failures.count)
            downloadError = remainder > 0 ? "\(summary)\n…and \(remainder) more." : summary
        }
    }

    private func plannerGroups(for plan: MovieDownloadPlan) -> [MediaDownloadPlannerGroup] {
        let grouped = Dictionary(grouping: plan.units) { unit in
            unit.episode?.season
        }
        let seasonKeys = grouped.keys.sorted { left, right in
            switch (left, right) {
            case (.some(let lhs), .some(let rhs)): lhs < rhs
            case (.none, .some): true
            case (.some, .none): false
            case (.none, .none): false
            }
        }

        return seasonKeys.compactMap { season in
            guard let units = grouped[season] else { return nil }
            let title = season.map { "Season \($0)" } ?? plan.units.first?.show.displayTitle ?? "Movie"
            let countLabel = season == nil
                ? "1 movie"
                : (units.count == 1 ? "1 episode" : "\(units.count) episodes")
            return MediaDownloadPlannerGroup(
                id: season.map { "season-\($0)" } ?? "movie",
                title: title,
                countLabel: countLabel,
                items: units.map { unit in
                    let record = record(for: unit)
                    return MediaDownloadPlannerItem(
                        id: unit.id,
                        title: unit.title,
                        detail: nil,
                        isUnavailable: record?.isActive == true || record?.phase == .completed,
                        status: plannerStatus(for: record)
                    )
                }
            )
        }
    }

    private func record(for unit: MovieDownloadUnit) -> MediaDownloadRecord? {
        mediaDownloads.record(
            mediaType: .movie,
            contentID: unit.show.slug,
            unitID: unit.episode?.id ?? unit.show.slug
        )
    }

    private func plannerItemIsUnavailable(_ unit: MovieDownloadUnit) -> Bool {
        let record = record(for: unit)
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

    private func downloadLabel(
        for record: MediaDownloadRecord?,
        isEpisode: Bool
    ) -> (title: String, icon: String, help: String) {
        let subject = isEpisode ? "episode" : "movie"
        return switch record?.phase {
        case .preparing, .downloading:
            ("Loading", "arrow.down.circle.fill", "Downloading \(subject)")
        case .completed:
            ("Offline", "checkmark.circle.fill", "Available offline. Manage it in Downloads")
        case .failed:
            ("Retry", "arrow.clockwise", "Retry \(subject) download")
        case nil:
            ("Download", "arrow.down.circle", "Download \(subject) for offline viewing")
        }
    }

    private var availableSeasons: [Int] {
        Array(Set(store.episodes.map(\.season))).sorted(by: >)
    }

    private var seasonBinding: Binding<Int> {
        Binding(
            get: { selectedSeason ?? availableSeasons.first ?? 0 },
            set: { selectedSeason = $0 }
        )
    }

    private var episodesForSelectedSeason: [MovieEpisode] {
        guard let season = selectedSeason ?? availableSeasons.first else { return [] }
        return store.episodes.filter { $0.season == season }
    }

    private func preferredEpisode(for show: MovieShow) -> MovieEpisode? {
        guard show.isSeries, let target = watchTarget(for: show) else { return nil }
        return store.episodes.first { $0.id == target.unitID }
    }

    private func watchButtonTitle(_ show: MovieShow) -> String {
        guard let target = watchTarget(for: show) else {
            return show.isSeries ? "No episodes available" : "Watch movie"
        }
        if !show.isSeries {
            return switch target.action {
            case .start, .next: "Watch movie"
            case let .resume(percentage):
                Int(percentage.rounded()) > 0
                    ? "Continue movie · \(Int(percentage.rounded()))%"
                    : "Continue movie"
            case .rewatch: "Watch movie again"
            }
        }
        guard let episode = store.episodes.first(where: { $0.id == target.unitID }) else {
            return "No episodes available"
        }
        return switch target.action {
        case .start: "Watch S\(episode.season) E\(episode.number)"
        case let .resume(percentage):
            Int(percentage.rounded()) > 0
                ? "Continue S\(episode.season) E\(episode.number) · \(Int(percentage.rounded()))%"
                : "Continue S\(episode.season) E\(episode.number)"
        case .next: "Watch next · S\(episode.season) E\(episode.number)"
        case .rewatch: "Watch S\(episode.season) E\(episode.number) again"
        }
    }

    private func watchTarget(for show: MovieShow) -> MediaWatchTarget? {
        let orderedUnitIDs = show.isSeries
            ? store.episodes.sorted {
                ($0.season, $0.number) < ($1.season, $1.number)
            }.map(\.id)
            : [show.slug]
        return model.mediaWatchTarget(
            mediaType: .movie,
            contentID: show.slug,
            orderedUnitIDs: orderedUnitIDs
        )
    }

    private func activeProgress(for show: MovieShow) -> MediaPlaybackProgress? {
        model.continueWatching.first {
            $0.mediaType == .movie && $0.contentId == show.slug
        }
    }

    private func episodeProgress(
        for episode: MovieEpisode,
        in show: MovieShow
    ) -> MovieEpisodeProgress? {
        let active = activeProgress(for: show).flatMap {
            $0.unitId == episode.id ? $0 : nil
        }
        let history = model.mediaHistory.first {
            $0.mediaType == .movie
                && $0.contentId == show.slug
                && $0.unitId == episode.id
        }
        if let active {
            return MovieEpisodeProgress(
                percentage: min(100, max(0, active.percentage)),
                isCompleted: active.completed,
                isCurrent: true
            )
        }
        guard let history else { return nil }

        return MovieEpisodeProgress(
            percentage: history.completed ? 100 : min(100, max(0, history.percentage)),
            isCompleted: history.completed,
            isCurrent: false
        )
    }

    @ViewBuilder
    private func episodeProgressAccessory(_ progress: MovieEpisodeProgress?) -> some View {
        if let progress {
            if progress.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(Color.asterionAccent)
                    .accessibilityLabel("Watched")
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        if progress.isCurrent {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8, weight: .bold))
                        }
                        Text("\(Int(progress.percentage.rounded()))%")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                    }
                    .foregroundStyle(
                        progress.isCurrent ? Color.asterionAccent : Color.asterionMuted
                    )

                    ProgressView(value: progress.percentage, total: 100)
                        .progressViewStyle(.linear)
                        .tint(progress.isCurrent ? Color.asterionAccent : Color.asterionMuted)
                        .frame(width: 72)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(Int(progress.percentage.rounded())) percent watched")
            }
        } else {
            Image(systemName: "arrow.up.right.square")
                .font(.caption)
                .foregroundStyle(Color.asterionMuted)
        }
    }

    private func episodeProgressHelp(
        _ progress: MovieEpisodeProgress?,
        episode: MovieEpisode
    ) -> String {
        guard let progress else { return "Watch \(episode.title)" }
        if progress.isCompleted { return "Watch \(episode.title) again" }
        if progress.isCurrent {
            return "Continue \(episode.title) from \(Int(progress.percentage.rounded()))%"
        }
        return "Resume \(episode.title)"
    }

    private func openPlayer(show: MovieShow, episode: MovieEpisode?) {
        openWindow(
            value: MoviePlayerRoute(
                slug: show.slug,
                title: show.displayTitle,
                initialEpisodeID: episode?.id
            )
        )
    }

    private func metadataLine(icon: String, value: String) -> some View {
        Label {
            Text(value).lineLimit(1)
        } icon: {
            Image(systemName: icon).frame(width: 16)
        }
        .font(.caption)
        .foregroundStyle(Color.asterionMuted)
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

    private func synopsisPreview(_ synopsis: String) -> String {
        guard synopsis.count > 300 else { return synopsis }
        let prefix = String(synopsis.prefix(300))
        if let boundary = prefix.lastIndex(where: { $0.isWhitespace }) {
            return String(prefix[..<boundary]) + "…"
        }
        return prefix + "…"
    }
}

private struct MovieDownloadUnit: Identifiable {
    let show: MovieShow
    let episode: MovieEpisode?

    var id: String { "\(show.slug)|\(episode?.id ?? show.slug)" }
    var title: String {
        episode.map { "Episode \($0.number)" } ?? "Movie"
    }
}

private struct MovieDownloadPlan: Identifiable {
    let id = UUID()
    let title: String
    let units: [MovieDownloadUnit]
    let initialSelection: Set<String>
}

private struct MovieEpisodeProgress {
    let percentage: Double
    let isCompleted: Bool
    let isCurrent: Bool
}
