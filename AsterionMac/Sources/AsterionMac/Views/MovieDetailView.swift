import SwiftUI

struct MovieDetailView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var mediaDownloads: MediaDownloadManager
    @ObservedObject var store: MovieStore

    @State private var selectedSeason: Int?
    @State private var showsFullSynopsis = false
    @State private var showsFullCast = false
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
        ZStack(alignment: .top) {
            ambientBackdrop(show)

            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    hero(show)

                    if hasAdditionalDetails(show) {
                        detailSection(title: "Details") {
                            additionalDetails(show)
                        }
                    }

                    if show.isSeries {
                        detailSection(title: "Episodes", trailing: "\(store.episodes.count) available") {
                            episodeBrowser(show)
                        }
                    }

                    if !show.actors.isEmpty {
                        detailSection(
                            title: "Cast",
                            trailing: show.actors.count == 1 ? "1 person" : "\(show.actors.count) people"
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(visibleCast(for: show).joined(separator: " · "))
                                    .font(.callout)
                                    .foregroundStyle(Color.asterionText.opacity(0.78))
                                    .textSelection(.enabled)

                                if show.actors.count > 8 {
                                    Button(showsFullCast ? "Show less" : "Show all cast") {
                                        showsFullCast.toggle()
                                    }
                                    .buttonStyle(.link)
                                    .font(.caption.weight(.semibold))
                                    .tint(.asterionText)
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                .thinMaterial,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        }
                    }
                }
                .frame(maxWidth: 1_180, alignment: .leading)
                .padding(.horizontal, 46)
                .padding(.top, 30)
                .padding(.bottom, 64)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .hidingScrollIndicators()
        }
        .background(Color.asterionMediaCanvas)
        .task(id: show.id) {
            showsFullSynopsis = false
            showsFullCast = false
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

    private func ambientBackdrop(_ show: MovieShow) -> some View {
        AsyncImage(url: show.imageURL) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 42)
                    .saturation(0.8)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 590)
        .clipped()
        .opacity(0.4)
        .overlay(Color.black.opacity(0.36))
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

    private func hero(_ show: MovieShow) -> some View {
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
                Text(show.isSeries ? "TV SERIES" : "MOVIE")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.asterionText.opacity(0.72))

                Text(show.displayTitle)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)
                    .textSelection(.enabled)

                if !show.genres.isEmpty {
                    Text(show.genres.prefix(3).joined(separator: " · "))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.asterionText.opacity(0.76))
                        .lineLimit(1)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { metadataItems(for: show) }
                    VStack(alignment: .leading, spacing: 8) { metadataItems(for: show) }
                }

                if let summary = show.description, !summary.isEmpty {
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
                        .tint(.asterionText)
                    }
                }

                watchAction(show)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 390)
    }

    @ViewBuilder
    private func metadataItems(for show: MovieShow) -> some View {
        ForEach(movieMetadata(for: show)) { item in
            Label(item.value, systemImage: item.icon)
                .font(.callout)
                .foregroundStyle(Color.asterionText.opacity(0.68))
                .lineLimit(1)
        }
    }

    private func movieMetadata(for show: MovieShow) -> [AsterionDetailMetadata] {
        [
            AsterionDetailMetadata(
                icon: show.isSeries ? "tv" : "film",
                value: show.isSeries ? "TV Series" : "Movie"
            ),
            show.releaseYear.map { AsterionDetailMetadata(icon: "calendar", value: $0) },
            show.duration.flatMap { $0.isEmpty ? nil : AsterionDetailMetadata(icon: "clock", value: $0) },
            show.director.flatMap { $0.isEmpty ? nil : AsterionDetailMetadata(icon: "person.fill", value: $0) },
            show.imdbRating.map { AsterionDetailMetadata(icon: "star.fill", value: "IMDb \($0)") },
        ].compactMap { $0 }
    }

    private func hasAdditionalDetails(_ show: MovieShow) -> Bool {
        !ratingDetails(for: show).isEmpty || !factDetails(for: show).isEmpty
    }

    private func additionalDetails(_ show: MovieShow) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            let ratings = ratingDetails(for: show)
            if !ratings.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        ForEach(ratings) { ratingBadge($0) }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(ratings) { ratingBadge($0) }
                    }
                }
            }

            let facts = factDetails(for: show)
            if !facts.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), alignment: .leading)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(facts) { fact in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fact.label.uppercased())
                                .font(.caption2.weight(.bold))
                                .tracking(0.7)
                                .foregroundStyle(Color.asterionMuted)
                            Text(fact.value)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(Color.asterionText.opacity(0.86))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.08))
        }
    }

    private func ratingBadge(_ rating: MovieDetailRating) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "star.fill")
                .font(.caption)
                .foregroundStyle(Color.asterionText.opacity(0.72))
            Text(rating.source)
                .foregroundStyle(Color.asterionMuted)
            Text(rating.value)
                .fontWeight(.semibold)
                .foregroundStyle(Color.asterionText)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.08)) }
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
            show.releaseDate.flatMap { detailValue($0).map { MovieDetailFact(label: "Release date", value: $0) } },
            show.country.flatMap { detailValue($0).map { MovieDetailFact(label: "Country", value: $0) } },
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

    private func watchAction(_ show: MovieShow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    openPlayer(show: show, episode: preferredEpisode(for: show))
                } label: {
                    Label(watchButtonTitle(show), systemImage: "play.fill")
                        .lineLimit(1)
                        .padding(.horizontal, 12)
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
        .tint(Color.asterionText)
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
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 150, alignment: .leading)
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
                                        .font(.system(size: 14, weight: .medium))
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

                            movieDownloadButton(show: show, episode: episode)
                        }
                        Divider()
                    }
                }
                .padding(.horizontal, 14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.08))
                }
            }
        }
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
                    .frame(width: 30, height: 30)
            } else {
                Image(systemName: label.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.asterionText.opacity(0.82))
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay { Circle().stroke(.white.opacity(0.08)) }
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
            Label("Download", systemImage: "arrow.down.circle")
                .labelStyle(.iconOnly)
                .frame(width: 20)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(Color.asterionText)
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
    ) -> (icon: String, help: String) {
        let subject = isEpisode ? "episode" : "movie"
        return switch record?.phase {
        case .preparing, .downloading:
            ("arrow.down.circle.fill", "Downloading \(subject)")
        case .completed:
            ("checkmark.circle.fill", "Available offline. Manage it in Downloads")
        case .failed:
            ("arrow.clockwise", "Retry \(subject) download")
        case nil:
            ("arrow.down.circle", "Download \(subject) for offline viewing")
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
                    .foregroundStyle(Color.asterionText.opacity(0.72))
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
                        progress.isCurrent ? Color.asterionText : Color.asterionMuted
                    )

                    ProgressView(value: progress.percentage, total: 100)
                        .progressViewStyle(.linear)
                        .tint(progress.isCurrent ? Color.asterionText : Color.asterionMuted)
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
                    .font(.system(size: 22, weight: .bold))
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
