import SwiftUI

struct AnimeCatalogView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: AnimeStore
    let section: AnimeSection
    let query: String
    let selectTitle: (AnimeTitle) -> Void

    @State private var featuredIndex = 0

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if normalizedQuery.count == 1 {
                ContentUnavailableView(
                    "Keep typing",
                    systemImage: "character.cursor.ibeam",
                    description: Text("Enter at least two characters to search anime.")
                )
            } else if section == .schedule, normalizedQuery.isEmpty {
                scheduleContent
            } else if (store.isLoadingCatalog
                || !store.hasLoadedCatalog(section: section, query: normalizedQuery)),
                store.titles.isEmpty {
                ProgressView(normalizedQuery.isEmpty ? "Curating your shelves…" : "Searching anime…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.catalogError, store.titles.isEmpty {
                ContentUnavailableView {
                    Label("Anime unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") {
                        Task { await store.refresh(section: section, query: query) }
                    }
                }
            } else if store.titles.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 34) {
                        if section == .discover, normalizedQuery.isEmpty {
                            featuredBanner
                                .padding(.horizontal, 32)

                            if !animeContinueWatching.isEmpty {
                                continueWatchingShelf
                            }

                            seasonalShelf
                            recentlyUpdatedShelf
                            newReleasesShelf
                        } else {
                            if section == .genres, normalizedQuery.isEmpty, !store.genres.isEmpty {
                                genreSelection
                                    .padding(.horizontal, 32)
                            }

                            if section == .types, normalizedQuery.isEmpty {
                                typeSelection
                                    .padding(.horizontal, 32)
                            }

                            shelf
                        }
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 64)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .hidingScrollIndicators()
            }
        }
        .background(Color.asterionMediaCanvas)
        .task(id: "\(section.rawValue):\(normalizedQuery)") {
            featuredIndex = 0
            if !normalizedQuery.isEmpty {
                try? await Task.sleep(for: .milliseconds(350))
            }
            guard !Task.isCancelled else { return }
            if section == .discover, normalizedQuery.isEmpty {
                async let catalog: Void = store.loadCatalog(section: section, query: normalizedQuery)
                async let currentSeason: Void = store.loadCurrentSeason()
                async let newReleases: Void = store.loadDiscoverNewReleases()
                _ = await (catalog, currentSeason, newReleases)
            } else {
                await store.loadCatalog(section: section, query: normalizedQuery)
            }
        }
        .onChange(of: store.titles) {
            let lastFeaturedIndex = max(0, min(8, store.titles.count) - 1)
            featuredIndex = min(featuredIndex, lastFeaturedIndex)
        }
    }

    private var animeContinueWatching: [MediaPlaybackProgress] {
        model.continueWatching.filter { $0.mediaType == .anime }
    }

    private var continueWatchingShelf: some View {
        HomeSection(title: "Continue Watching", subtitle: "Pick up where you left off.") {
            HomeHorizontalShelf(
                items: animeContinueWatching,
                itemWidth: AsterionCardMetrics.landscapeWidth,
                spacing: 18,
                height: AsterionCardMetrics.landscapeShelfHeight
            ) { progress in
                HomeContinueCard(item: .watching(progress)) {
                    openWindow(
                        value: AnimePlayerRoute(
                            slug: progress.contentId,
                            title: progress.title,
                            initialEpisodeID: progress.unitId
                        )
                    )
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var seasonalShelf: some View {
        HomeSection(
            title: store.season.title,
            subtitle: "Anime airing in the current season."
        ) {

            if store.isLoadingSeason, store.seasonalTitles.isEmpty {
                ProgressView("Loading \(store.season.title)…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else if let error = store.seasonError {
                HStack(spacing: 12) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.asterionMuted)
                    Spacer()
                    Button("Try Again") {
                        Task { await store.retryCurrentSeason() }
                    }
                }
                .padding(.vertical, 12)
            } else if store.seasonalTitles.isEmpty {
                Text("The anime service returned no titles for \(store.season.title).")
                    .font(.callout)
                    .foregroundStyle(Color.asterionMuted)
                    .padding(.vertical, 12)
            } else {
                horizontalTitleRow(store.seasonalTitles, loadsNextPage: false)
            }
        }
    }

    private var recentlyUpdatedShelf: some View {
        HomeSection(
            title: "Recently Updated",
            subtitle: "Fresh episodes, ready when you are."
        ) {
            horizontalTitleRow(store.titles, loadsNextPage: true)
        }
    }

    private var newReleasesShelf: some View {
        HomeSection(
            title: "New Releases",
            subtitle: "New arrivals across series, films, and specials."
        ) {

            if store.isLoadingNewReleases, store.newReleaseTitles.isEmpty {
                ProgressView("Loading new releases…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else if let error = store.newReleasesError {
                HStack(spacing: 12) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.asterionMuted)
                    Spacer()
                    Button("Try Again") {
                        Task { await store.retryDiscoverNewReleases() }
                    }
                }
                .padding(.vertical, 12)
            } else if store.newReleaseTitles.isEmpty {
                Text("The anime service returned no new releases.")
                    .font(.callout)
                    .foregroundStyle(Color.asterionMuted)
                    .padding(.vertical, 12)
            } else {
                horizontalTitleRow(store.newReleaseTitles, loadsNextPage: false)
            }
        }
    }

    private func horizontalTitleRow(
        _ titles: [AnimeTitle],
        loadsNextPage: Bool
    ) -> some View {
        HomeHorizontalShelf(
            items: titles,
            itemWidth: AsterionCardMetrics.posterWidth,
            spacing: 18,
            height: AsterionCardMetrics.posterShelfHeight
        ) { title in
            AnimeTitleTile(
                title: title,
                isSelected: store.selectedTitleID == title.id
            ) {
                selectTitle(title)
            }
            .padding(.vertical, 3)
            .task {
                guard loadsNextPage else { return }
                await store.loadNextPageIfNeeded(
                    section: section,
                    query: normalizedQuery,
                    currentTitle: title
                )
            }
        }
    }

    @ViewBuilder
    private var featuredBanner: some View {
        let featuredTitles = Array(store.titles.prefix(8))

        if !featuredTitles.isEmpty {
            let safeIndex = min(featuredIndex, featuredTitles.count - 1)
            let featuredTitle = featuredTitles[safeIndex]

            AsterionFeatureCard(
                imageURL: featuredTitle.imageURL,
                fallbackSystemImage: "play.rectangle.fill",
                eyebrow: "FEATURED ANIME",
                title: featuredTitle.displayTitle,
                summary: featuredSynopsis(for: featuredTitle),
                previous: { moveFeatured(by: -1, titles: featuredTitles, selectedIndex: safeIndex) },
                next: { moveFeatured(by: 1, titles: featuredTitles, selectedIndex: safeIndex) }
            ) {
                HStack(spacing: 14) {
                    Label(featuredTitle.type ?? "Anime", systemImage: "play.fill")
                    if let episodeLabel = featuredTitle.episodeLabel {
                        Label(episodeLabel, systemImage: "text.page")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
            } actions: {
                Button {
                    openWindow(
                        value: AnimePlayerRoute(
                            slug: featuredTitle.slug,
                            title: featuredTitle.displayTitle,
                            initialEpisodeID: nil
                        )
                    )
                } label: {
                    Label("Watch now", systemImage: "play.fill")
                        .font(.headline)
                        .frame(width: 132)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 8))
                .controlSize(.large)
                .tint(.asterionAccent)
            }
        }
    }

    private func moveFeatured(by offset: Int, titles: [AnimeTitle], selectedIndex: Int) {
        guard !titles.isEmpty else { return }
        let destination = (selectedIndex + offset + titles.count) % titles.count
        featuredIndex = destination
        Task { await store.select(titles[destination]) }
    }

    private func featuredSynopsis(for title: AnimeTitle) -> String {
        guard store.selectedTitleID == title.id else { return "Loading synopsis…" }
        if let synopsis = store.show?.displayDescription,
           !synopsis.isEmpty {
            return synopsis
        }
        if store.isLoadingDetail { return "Loading synopsis…" }
        return "Synopsis unavailable for this title."
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSection(title: shelfTitle, subtitle: shelfSubtitle) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: AsterionCardMetrics.posterWidth, maximum: AsterionCardMetrics.posterWidth), spacing: 18)],
                    alignment: .leading,
                    spacing: 18
                ) {
                    ForEach(store.titles) { title in
                        AnimeTitleTile(
                            title: title,
                            isSelected: store.selectedTitleID == title.id
                        ) {
                            selectTitle(title)
                        }
                        .task {
                            await store.loadNextPageIfNeeded(
                                section: section,
                                query: normalizedQuery,
                                currentTitle: title
                            )
                        }
                    }
                }
                .padding(.horizontal, 32)
            }
            paginationStatus
                .padding(.horizontal, 32)
        }
    }

    @ViewBuilder
    private var paginationStatus: some View {
        if store.isLoadingNextPage {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading more anime…")
                    .font(.caption)
                    .foregroundStyle(Color.asterionMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else if let error = store.paginationError {
            HStack(spacing: 10) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(2)
                Spacer()
                Button("Try Again") {
                    Task { await store.retryNextPage(section: section, query: normalizedQuery) }
                }
            }
            .padding(.vertical, 10)
        }
    }

    private var genreSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnimeShelfHeader(
                title: "Choose a Genre",
                subtitle: "Select a shelf to explore."
            )

            Picker("Genre", selection: genreBinding) {
                ForEach(store.genres, id: \.self) { genre in
                    Text(displayName(for: genre)).tag(genre)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 220, alignment: .leading)
        }
    }

    private var typeSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnimeShelfHeader(
                title: "Choose a Type",
                subtitle: "Narrow the catalog to a release format."
            )

            Picker("Type", selection: typeBinding) {
                ForEach(AnimeStore.types, id: \.self) { type in
                    Text(displayName(for: type)).tag(type)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 220, alignment: .leading)
        }
    }

    private var genreBinding: Binding<String> {
        Binding(
            get: { store.selectedGenre ?? store.genres.first ?? "" },
            set: { genre in
                Task { await store.selectGenre(genre, query: normalizedQuery) }
            }
        )
    }

    private var typeBinding: Binding<String> {
        Binding(
            get: { store.selectedType },
            set: { type in
                Task { await store.selectType(type, query: normalizedQuery) }
            }
        )
    }

    private var shelfTitle: String {
        if !normalizedQuery.isEmpty { return "Search Results" }
        if section == .genres, let genre = store.selectedGenre { return displayName(for: genre) }
        if section == .types { return displayName(for: store.selectedType) }
        return section.catalogTitle
    }

    private var shelfSubtitle: String {
        if !normalizedQuery.isEmpty { return "Titles matching your search." }
        return section.catalogDescription
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No anime found", systemImage: "magnifyingglass")
        } description: {
            Text("Try a different title or category.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.asterionMediaCanvas)
    }

    private var scheduleContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                AnimeShelfHeader(
                    title: "Release Schedule",
                    subtitle: "Times are shown in \(TimeZone.current.localizedName(for: .standard, locale: .current) ?? TimeZone.current.identifier)."
                )

                if store.isLoadingSchedule, store.scheduleDays.isEmpty {
                    ProgressView("Loading this week's schedule…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 28)
                } else if let error = store.scheduleError, store.scheduleDays.isEmpty {
                    ContentUnavailableView {
                        Label("Schedule unavailable", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") {
                            Task { await store.retrySchedule() }
                        }
                    }
                } else if store.scheduleDays.isEmpty {
                    ContentUnavailableView(
                        "No releases scheduled",
                        systemImage: "calendar",
                        description: Text("The anime service has no releases listed for this week.")
                    )
                } else {
                    ForEach(store.scheduleDays) { day in
                        scheduleDay(day)
                    }
                }
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .hidingScrollIndicators()
    }

    private func scheduleDay(_ day: AnimeScheduleDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(day.label)
                .font(.asterionDisplay(18, weight: .semibold))
                .foregroundStyle(Color.asterionText)

            LazyVStack(spacing: 8) {
                ForEach(day.entries) { entry in
                    Button {
                        Task { await store.select(entry) }
                    } label: {
                        HStack(spacing: 16) {
                            Text(entry.time)
                                .font(.callout.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Color.asterionAccent)
                                .frame(width: 58, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.displayTitle)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Color.asterionText)
                                    .lineLimit(1)
                                if let japaneseTitle = entry.japaneseTitle, !japaneseTitle.isEmpty {
                                    Text(japaneseTitle)
                                        .font(.caption)
                                        .foregroundStyle(Color.asterionMuted)
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 12)

                            if let episode = entry.episodeNumber {
                                Text("Episode \(episode)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.asterionMuted)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Color.asterionCard, in: Capsule())
                            }

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.asterionMuted)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color.asterionSurface.opacity(0.68), in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    store.selectedTitleID == entry.slug
                                        ? Color.asterionAccent
                                        : Color.white.opacity(0.06),
                                    lineWidth: 1
                                )
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.displayTitle)
                    .accessibilityValue(
                        [entry.time, entry.episodeNumber.map { "Episode \($0)" }]
                            .compactMap { $0 }
                            .joined(separator: ", ")
                    )
                }
            }
        }
    }

    private func displayName(for genre: String) -> String {
        genre.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

private struct AnimeShelfHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.asterionDisplay(22, weight: .semibold))
                .foregroundStyle(Color.asterionText)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(Color.asterionMuted)
        }
    }
}

private struct AnimeTitleTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: AnimeTitle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        AsterionPosterCard(
            imageURL: title.imageURL,
            badge: "ANIME",
            title: title.displayTitle,
            subtitle: title.episodeLabel ?? title.type ?? "Anime",
            isSelected: isSelected,
            action: action
        )
        .animation(reduceMotion ? nil : AsterionMotion.reveal, value: isSelected)
        .accessibilityValue(title.episodeLabel ?? title.type ?? "Anime")
    }
}
