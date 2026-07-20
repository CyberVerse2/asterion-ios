import SwiftUI

struct AnimeCatalogView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: AnimeStore
    let section: AnimeSection
    let query: String

    @State private var featuredIndex = 0

    private let columns = [
        GridItem(.adaptive(minimum: 118, maximum: 154), spacing: 22, alignment: .top),
    ]

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
            } else if store.isLoadingCatalog, store.titles.isEmpty {
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

                            if !animeContinueWatching.isEmpty {
                                ContinueWatchingShelf(entries: animeContinueWatching) { progress in
                                    openWindow(
                                        value: AnimePlayerRoute(
                                            slug: progress.contentId,
                                            title: progress.title,
                                            initialEpisodeID: progress.unitId
                                        )
                                    )
                                }
                            }

                            seasonalShelf
                            recentlyUpdatedShelf
                            newReleasesShelf
                        } else {
                            if section == .genres, normalizedQuery.isEmpty, !store.genres.isEmpty {
                                genreSelection
                            }

                            if section == .types, normalizedQuery.isEmpty {
                                typeSelection
                            }

                            shelf
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

    private var seasonalShelf: some View {
        VStack(alignment: .leading, spacing: 18) {
            AnimeShelfHeader(
                title: store.season.title,
                subtitle: "Anime airing in the current season."
            )

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
        VStack(alignment: .leading, spacing: 18) {
            AnimeShelfHeader(
                title: "Recently Updated",
                subtitle: "Fresh episodes, ready when you are."
            )
            horizontalTitleRow(store.titles, loadsNextPage: true)
            paginationStatus
        }
    }

    private var newReleasesShelf: some View {
        VStack(alignment: .leading, spacing: 18) {
            AnimeShelfHeader(
                title: "New Releases",
                subtitle: "New arrivals across series, films, and specials."
            )

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
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 22) {
                ForEach(titles) { title in
                    AnimeTitleTile(
                        title: title,
                        isSelected: store.selectedTitleID == title.id,
                        usesDiscoverBadges: true
                    ) {
                        Task { await store.select(title) }
                    }
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
            .padding(.vertical, 2)
        }
        .hidingScrollIndicators()
    }

    @ViewBuilder
    private var featuredBanner: some View {
        let featuredTitles = Array(store.titles.prefix(8))

        if !featuredTitles.isEmpty {
            let safeIndex = min(featuredIndex, featuredTitles.count - 1)
            let featuredTitle = featuredTitles[safeIndex]

            AnimeFeaturedBanner(
                title: featuredTitle,
                synopsis: featuredSynopsis(for: featuredTitle),
                titles: featuredTitles,
                selectedIndex: safeIndex,
                selectIndex: { index in
                    featuredIndex = index
                    Task { await store.select(featuredTitles[index]) }
                },
                watch: {
                    openWindow(
                        value: AnimePlayerRoute(
                            slug: featuredTitle.slug,
                            title: featuredTitle.displayTitle,
                            initialEpisodeID: nil
                        )
                    )
                }
            )
        }
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
        VStack(alignment: .leading, spacing: 18) {
            AnimeShelfHeader(title: shelfTitle, subtitle: shelfSubtitle)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                ForEach(store.titles) { title in
                    AnimeTitleTile(
                        title: title,
                        isSelected: store.selectedTitleID == title.id,
                        usesDiscoverBadges: section == .discover && normalizedQuery.isEmpty
                    ) {
                        Task { await store.select(title) }
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

            paginationStatus
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
                                .foregroundStyle(entry.passed ? Color.asterionMuted : Color.asterionAccent)
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
                        .opacity(entry.passed ? 0.72 : 1)
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

private struct AnimeFeaturedBanner: View {
    let title: AnimeTitle
    let synopsis: String
    let titles: [AnimeTitle]
    let selectedIndex: Int
    let selectIndex: (Int) -> Void
    let watch: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AnimeFeaturedBackdrop(url: title.imageURL)

                LinearGradient(
                    colors: [.black.opacity(0.88), .black.opacity(0.28)],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                featureContent(posterWidth: 104)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: 252)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.12))
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 9)
    }

    private func featureContent(posterWidth: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            MediaCoverView(
                url: title.imageURL,
                width: posterWidth,
                height: posterWidth * 1.43
            )
            .padding(.trailing, 20)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Text("FEATURED")
                        .font(.asterionMono(10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Color.asterionAccent)

                    Spacer()

                    carouselControls
                }

                Text(title.displayTitle)
                    .font(.asterionDisplay(23, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                HStack(spacing: 7) {
                    if let episodeLabel = title.episodeLabel {
                        featureBadge(episodeLabel, color: Color.asterionAccent)
                    }
                    if let type = title.type {
                        featureBadge(type, color: .white.opacity(0.16))
                    }
                }

                Text(synopsis)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(2)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Synopsis")
                    .accessibilityValue(synopsis)

                Spacer(minLength: 0)

                Button(action: watch) {
                    Label("Watch now", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 10))
                .controlSize(.large)
                .tint(.asterionAccent)
                .accessibilityLabel("Watch \(title.displayTitle)")
            }
            .padding(.leading, 20)
            .padding(.trailing, posterWidth + 38)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var carouselControls: some View {
        HStack(spacing: 6) {
            ForEach(titles.indices, id: \.self) { index in
                Button {
                    selectIndex(index)
                } label: {
                    Circle()
                        .fill(index == selectedIndex ? Color.asterionAccent : Color.white.opacity(0.42))
                        .frame(width: index == selectedIndex ? 8 : 6, height: index == selectedIndex ? 8 : 6)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(titles[index].displayTitle)")
                .accessibilityValue("Feature \(index + 1) of \(titles.count)")
                .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])
                .help(titles[index].displayTitle)
            }
        }
    }

    private func featureBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color, in: Capsule())
    }
}

private struct AnimeFeaturedBackdrop: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 24)
                    .scaleEffect(1.18)
            case .empty:
                Color.asterionCard
                    .overlay { ProgressView().controlSize(.small) }
            case .failure:
                Color.asterionCard
            @unknown default:
                Color.asterionCard
            }
        }
        .clipped()
    }
}

private struct AnimeTitleTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: AnimeTitle
    let isSelected: Bool
    let usesDiscoverBadges: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    MediaCoverView(url: title.imageURL, width: 128, height: 184)

                    LinearGradient(
                        colors: [.clear, .clear, .black.opacity(0.88)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    if let episodeLabel = title.episodeLabel {
                        Text(episodeLabel)
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.asterionAccent, in: Capsule())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(7)
                    }

                    if usesDiscoverBadges, let type = title.type {
                        Text(type)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.orange, in: Capsule())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(7)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title.displayTitle)
                            .font(.asterionDisplay(14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        if !usesDiscoverBadges {
                            Text(title.type ?? "Anime")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white.opacity(0.78))
                                .lineLimit(1)
                        }
                    }
                    .padding(10)
                }
                .padding(4)
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(isSelected ? Color.asterionAccent : .clear, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .asterionHoverLift()
        .animation(reduceMotion ? nil : AsterionMotion.reveal, value: isSelected)
        .accessibilityLabel(title.displayTitle)
        .accessibilityValue(title.episodeLabel ?? title.type ?? "Anime")
    }
}
