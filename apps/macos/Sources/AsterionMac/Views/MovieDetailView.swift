import SwiftUI

struct MovieDetailView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var mediaDownloads: MediaDownloadManager
    @ObservedObject var store: MovieStore

    @State private var selectedSeason: Int?
    @State private var showsFullSynopsis = false
    @State private var showsFullCast = false
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var downloadError: String?
    @State private var downloadPlan: MovieDownloadPlan?

    var body: some View {
        Group {
            if store.isLoadingDetail {
                AsterionDetailSkeleton(accessibilityLabel: "Opening title…")
            } else if let error = store.detailError {
                AsterionEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "Couldn’t open this title",
                    message: error
                ) {
                    Button("Try again") { Task { await store.retryDetail() } }
                        .buttonStyle(.asterionSecondary)
                }
            } else if let show = store.show {
                detail(show)
            } else {
                AsterionEmptyState(
                    systemImage: "film",
                    title: "Choose a title",
                    message: "Select a movie or TV show to see its details."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.asterionMediaCanvas)
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
            VStack(alignment: .leading, spacing: AsterionLayout.sectionSpacing) {
                hero(show)
                    .asterionDetailInset()

                if show.isSeries {
                    AsterionDetailSection(
                        title: "Episodes",
                        count: "\(store.episodes.count) available",
                        bleedsContent: !episodesForSelectedSeason.isEmpty
                    ) {
                        seasonMenu
                    } content: {
                        episodeBrowser(show)
                    }
                }

                if !show.actors.isEmpty {
                    AsterionDetailSection(
                        title: "Cast",
                        count: show.actors.count == 1 ? "1 person" : "\(show.actors.count) people",
                        bleedsContent: true
                    ) {
                        castShelf(show)
                    }
                }

                if !factDetails(for: show).isEmpty {
                    AsterionDetailSection(title: "Details") {
                        movieCredits(show)
                    }
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
        .scrollPosition($scrollPosition)
        .background(Color.asterionMediaCanvas)
        .task(id: show.id) {
            showsFullSynopsis = false
            showsFullCast = false
            downloadError = nil
            selectedSeason = preferredEpisode(for: show)?.season ?? availableSeasons.first
            await Task.yield()
            // Scroll to the true top edge; an id anchor lined the page up
            // under the toolbar instead, so it jumped once loaded.
            scrollPosition.scrollTo(edge: .top)
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
        let target = watchTarget(for: show)
        let targetEpisode = target.flatMap { target in
            store.episodes.first { $0.id == target.unitID }
        }

        return AsterionDetailHero(
            imageURL: show.imageURL,
            fallbackSystemImage: show.isSeries ? "tv" : "film",
            eyebrow: eyebrow(for: show),
            title: show.displayTitle,
            byline: show.director.flatMap(detailValue).map { "Directed by \($0)" },
            metadata: heroMetadata(for: show),
            secondaryMetadata: ratingDetails(for: show).map { "\($0.source) \($0.value)" },
            summary: show.description,
            showsFullSummary: $showsFullSynopsis
        ) {
            watchActions(show)
        } footer: {
            if case let .resume(percentage) = target?.action, percentage > 0 {
                AsterionDetailProgress(
                    fraction: percentage / 100,
                    caption: show.isSeries
                        ? targetEpisode.map { episode in
                            episode.title.isEmpty
                                ? "S\(episode.season) E\(episode.number)"
                                : "S\(episode.season) E\(episode.number) · \(episode.title)"
                        }
                        : nil
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

    private func eyebrow(for show: MovieShow) -> String {
        let year = show.releaseYear.flatMap(detailValue)
            ?? show.releaseDate.flatMap(detailValue).map { String($0.prefix(4)) }
        return [show.isSeries ? "Series" : "Film", year]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func heroMetadata(for show: MovieShow) -> [String] {
        let seasonCount = Set(store.episodes.map(\.season)).count
        let genres = show.genres.prefix(3).joined(separator: ", ")
        return [
            show.isSeries && seasonCount > 0
                ? "\(seasonCount) \(seasonCount == 1 ? "season" : "seasons")"
                : nil,
            show.isSeries && !store.episodes.isEmpty ? "\(store.episodes.count) episodes" : nil,
            show.duration.flatMap(detailValue),
            genres.isEmpty ? nil : genres,
            show.country.flatMap(detailValue),
        ].compactMap { $0 }
    }

    private func movieCredits(_ show: MovieShow) -> some View {
        let facts = factDetails(for: show)
        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 0, alignment: .leading),
                GridItem(.flexible(), spacing: 0, alignment: .leading),
            ],
            alignment: .leading,
            spacing: 0
        ) {
            ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                AsterionDetailFactRow(label: fact.label, value: fact.value)
                    .overlay(alignment: .top) {
                        if index >= 2 {
                            Rectangle()
                                .fill(Color.asterionHairline)
                                .frame(height: 1)
                        }
                    }
            }
        }
        .padding(.vertical, 4)
        .asterionPanel(cornerRadius: 14)
    }

    private func ratingDetails(for show: MovieShow) -> [MovieDetailRating] {
        [
            show.imdbRating.flatMap { detailValue($0).map { MovieDetailRating(source: "IMDb", value: $0) } },
            show.tmdbRating.flatMap { detailValue($0).map { MovieDetailRating(source: "TMDB", value: $0) } },
            show.rottenTomatoes.flatMap { detailValue($0).map { MovieDetailRating(source: "Rotten Tomatoes", value: $0) } },
            show.metacritic.flatMap { detailValue($0).map { MovieDetailRating(source: "Metacritic", value: $0) } },
        ].compactMap { $0 }
    }

    private func factDetails(for show: MovieShow) -> [MovieDetailFact] {
        let seasonCount = Set(store.episodes.map(\.season)).count
        return [
            MovieDetailFact(label: "Format", value: show.isSeries ? "TV Series" : "Movie"),
            show.releaseDate.flatMap { detailValue($0).map { MovieDetailFact(label: "Release date", value: $0) } },
            show.country.flatMap { detailValue($0).map { MovieDetailFact(label: "Country", value: $0) } },
            show.duration.flatMap { detailValue($0).map { MovieDetailFact(label: "Runtime", value: $0) } },
            show.director.flatMap { detailValue($0).map { MovieDetailFact(label: "Director", value: $0) } },
            show.genres.isEmpty ? nil : MovieDetailFact(label: "Genres", value: show.genres.joined(separator: " · ")),
            show.isSeries && seasonCount > 0
                ? MovieDetailFact(label: "Series", value: "\(seasonCount) \(seasonCount == 1 ? "season" : "seasons") · \(store.episodes.count) episodes")
                : nil,
        ].compactMap { $0 }
    }

    private func detailValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func visibleCast(for show: MovieShow) -> ArraySlice<String> {
        showsFullCast ? show.actors[...] : show.actors.prefix(8)
    }

    private func castShelf(_ show: MovieShow) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(Array(visibleCast(for: show)), id: \.self) { actor in
                        Text(actor)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.asterionText.opacity(0.9))
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .frame(height: 34)
                            .background(Capsule().fill(Color.asterionSurface))
                            .overlay { Capsule().strokeBorder(Color.asterionBorder) }
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 2)
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, AsterionLayout.pageInset, for: .scrollContent)
            .hidingScrollIndicators()
            .scrollTargetBehavior(.viewAligned)

            if show.actors.count > 8 {
                Button(showsFullCast ? "Show less" : "Show all cast") {
                    showsFullCast.toggle()
                }
                .buttonStyle(AsterionDetailTextButtonStyle())
                .asterionDetailInset()
            }
        }
    }

    private func recommendationShelf(_ show: MovieShow) -> some View {
        HomeHorizontalShelf(
            items: recommendations(for: show),
            itemWidth: AsterionCardMetrics.posterWidth,
            spacing: 18,
            height: AsterionCardMetrics.posterShelfHeight
        ) { title in
            AsterionPosterCard(
                imageURL: title.imageURL,
                title: title.displayTitle,
                subtitle: [title.isSeries ? "TV Series" : "Movie", title.year]
                    .compactMap { $0 }
                    .joined(separator: " · "),
                fallbackSystemImage: title.isSeries ? "tv" : "film"
            ) {
                Task { await store.select(title, force: true) }
            }
        }
    }

    private func recommendations(for show: MovieShow) -> [MovieTitle] {
        Array(store.titles.lazy.filter { $0.slug != show.slug }.prefix(10))
    }

    @ViewBuilder
    private func watchActions(_ show: MovieShow) -> some View {
        Button {
            openPlayer(show: show, episode: preferredEpisode(for: show))
        } label: {
            Label(watchButtonTitle(show), systemImage: "play.fill")
                .lineLimit(1)
        }
        .layoutPriority(1)
        .buttonStyle(.asterionPrimary)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(show.isSeries ? store.episodes.isEmpty : false)
        .help("Open in Asterion Player")

        mediaBookmarkButton(show)

        movieCollectionDownloadButton(show)
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
                    .frame(width: 16)
            } else {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .frame(width: 16)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(.asterionSecondary)
        .disabled(isUpdating)
        .help(isSaved ? "Remove from saved movies" : "Save this title to your account")
        .accessibilityLabel(isSaved ? "Remove from saved movies" : "Save this title")
    }

    @ViewBuilder
    private var seasonMenu: some View {
        if availableSeasons.count > 1 {
            Menu {
                Picker("Season", selection: seasonBinding) {
                    ForEach(availableSeasons, id: \.self) { season in
                        Text("Season \(season)").tag(season)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text("Season \(seasonBinding.wrappedValue)")
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 14)
            .asterionSmokedCapsule(height: 30)
            .accessibilityLabel("Season")
            .accessibilityValue("Season \(seasonBinding.wrappedValue)")
        }
    }

    @ViewBuilder
    private func episodeBrowser(_ show: MovieShow) -> some View {
        if episodesForSelectedSeason.isEmpty {
            AsterionEmptyState(
                systemImage: "film.stack",
                title: "No episodes yet",
                message: "Episodes appear here as soon as they’re released."
            )
            .frame(minHeight: 220)
            .asterionPanel(cornerRadius: 14)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(episodesForSelectedSeason) { episode in
                        movieEpisodeCard(show: show, episode: episode)
                    }
                }
                .padding(.vertical, 6)
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, AsterionLayout.pageInset, for: .scrollContent)
            .hidingScrollIndicators()
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private func movieEpisodeCard(show: MovieShow, episode: MovieEpisode) -> some View {
        let progress = episodeProgress(for: episode, in: show)
        let fraction: Double? = progress.flatMap { progress in
            progress.isCompleted ? nil : progress.percentage / 100
        }

        return AsterionEpisodeCard(
            imageURL: show.imageURL,
            numberLabel: String(format: "S%d · E%02d", episode.season, episode.number),
            artworkVariant: episode.number,
            title: episode.title.isEmpty ? "Episode \(episode.number)" : episode.title,
            status: movieEpisodeStatus(progress),
            progress: fraction,
            isCurrent: progress?.isCurrent == true,
            isWatched: progress?.isCompleted == true,
            help: episodeProgressHelp(progress, episode: episode),
            accessibilityLabel: episodeProgressHelp(progress, episode: episode)
        ) {
            openPlayer(show: show, episode: episode)
        } accessory: {
            movieDownloadButton(show: show, episode: episode)
        }
    }

    private func movieEpisodeStatus(_ progress: MovieEpisodeProgress?) -> String {
        guard let progress else { return "Available to watch" }
        if progress.isCompleted { return "Watched" }
        if progress.isCurrent { return "Continue · \(Int(progress.percentage.rounded()))%" }
        return "\(Int(progress.percentage.rounded()))% watched"
    }

    private func movieDownloadButton(
        show: MovieShow,
        episode: MovieEpisode?
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
            Image(systemName: "arrow.down.to.line")
                .frame(width: 16)
        }
        .buttonStyle(.asterionSecondary)
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
        let selections = plan.units.filter { selectedIDs.contains($0.id) }
        let failures = await ConcurrentBatch.run(
            selections,
            maximumConcurrentTasks: 12
        ) { unit -> String? in
            do {
                try await mediaDownloads.downloadMovie(
                    show: unit.show,
                    episode: unit.episode,
                    quality: quality
                )
                return nil
            } catch {
                return "\(unit.title): \(error.localizedDescription)"
            }
        }
        .compactMap { $0 }
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
    ) -> (icon: String, help: String) {
        let subject = isEpisode ? "episode" : "movie"
        return switch record?.phase {
        case .preparing, .downloading:
            ("arrow.down.to.line", "Downloading \(subject)")
        case .completed:
            ("checkmark.circle.fill", "Available offline. Manage it in Downloads")
        case .failed:
            ("arrow.clockwise", "Retry \(subject) download")
        case nil:
            ("arrow.down.to.line", "Download \(subject) for offline viewing")
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
            case .resume: "Resume movie"
            case .rewatch: "Watch movie again"
            }
        }
        guard let episode = store.episodes.first(where: { $0.id == target.unitID }) else {
            return "No episodes available"
        }
        return switch target.action {
        case .start: "Watch S\(episode.season) E\(episode.number)"
        case .resume: "Resume S\(episode.season) E\(episode.number)"
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
}

private struct MovieDownloadUnit: Identifiable, Sendable {
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

private struct MovieDetailRating: Identifiable {
    let source: String
    let value: String

    var id: String { source }
}

private struct MovieDetailFact: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}
