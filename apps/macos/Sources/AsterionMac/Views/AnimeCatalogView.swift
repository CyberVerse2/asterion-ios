import SwiftUI

struct AnimeCatalogView: View {
    @Environment(\.asterionTopInset) private var topInset
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
                AsterionEmptyState(
                    systemImage: "character.cursor.ibeam",
                    title: "Keep typing",
                    message: "Search needs at least two characters to look through anime."
                )
            } else if section == .schedule, normalizedQuery.isEmpty {
                scheduleContent
            } else if (store.isLoadingCatalog
                || !store.hasLoadedCatalog(section: section, query: normalizedQuery)),
                store.titles.isEmpty {
                if showsHero {
                    AsterionCatalogSkeleton()
                } else {
                    AsterionGridSkeleton()
                }
            } else if let error = store.catalogError, store.titles.isEmpty {
                AsterionEmptyState(
                    systemImage: "wifi.exclamationmark",
                    title: "Anime didn’t load",
                    message: error
                ) {
                    Button("Try again") {
                        Task { await store.refresh(section: section, query: query) }
                    }
                    .buttonStyle(.asterionSecondary)
                }
            } else if store.titles.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AsterionLayout.sectionSpacing) {
                        if showsHero {
                            featuredBanner

                            if !animeContinueWatching.isEmpty {
                                continueWatchingShelf
                            }

                            seasonalShelf
                            recentlyUpdatedShelf
                            newReleasesShelf
                        } else {
                            shelf
                        }
                    }
                    .padding(.top, showsHero ? 0 : AsterionLayout.catalogContentTop(topInset))
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
            let lastFeaturedIndex = max(0, min(6, store.titles.count) - 1)
            featuredIndex = min(featuredIndex, lastFeaturedIndex)
        }
    }

    private var showsHero: Bool {
        section == .discover && normalizedQuery.isEmpty
    }

    private var animeContinueWatching: [MediaPlaybackProgress] {
        model.continueWatching.filter { $0.mediaType == .anime }
    }

    private var continueWatchingShelf: some View {
        HomeSection(title: "Continue watching", subtitle: "Pick up where you left off") {
            HomeHorizontalShelf(
                items: animeContinueWatching,
                itemWidth: AsterionCardMetrics.landscapeWidth,
                spacing: 16,
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
            }
        }
    }

    private var seasonalShelf: some View {
        HomeSection(
            title: store.season.title,
            subtitle: "Airing this season"
        ) {

            if store.isLoadingSeason, store.seasonalTitles.isEmpty {
                AsterionSkeletonShelf()
            } else if let error = store.seasonError {
                shelfNotice(error) {
                    Task { await store.retryCurrentSeason() }
                }
            } else if store.seasonalTitles.isEmpty {
                shelfNotice("No titles are listed for \(store.season.title) yet.", retry: nil)
            } else {
                horizontalTitleRow(store.seasonalTitles, loadsNextPage: false)
            }
        }
    }

    private var recentlyUpdatedShelf: some View {
        HomeSection(
            title: "Recently updated",
            subtitle: "New episodes"
        ) {
            horizontalTitleRow(store.titles, loadsNextPage: true)
        }
    }

    private var newReleasesShelf: some View {
        HomeSection(
            title: "New releases",
            subtitle: "Series, films, and specials"
        ) {
            if store.isLoadingNewReleases, store.newReleaseTitles.isEmpty {
                AsterionSkeletonShelf()
            } else if let error = store.newReleasesError {
                shelfNotice(error) {
                    Task { await store.retryDiscoverNewReleases() }
                }
            } else if store.newReleaseTitles.isEmpty {
                shelfNotice("No new releases are listed right now.", retry: nil)
            } else {
                horizontalTitleRow(store.newReleaseTitles, loadsNextPage: false)
            }
        }
    }

    private func shelfNotice(_ message: String, retry: (() -> Void)?) -> some View {
        HStack(spacing: 12) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.asterionMuted)
                .lineLimit(2)
            Spacer()
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(.asterionSecondary)
                    .controlSize(.small)
            }
        }
        .padding(16)
        .asterionPanel(cornerRadius: 12)
        .padding(.horizontal, AsterionLayout.pageInset)
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
        let featuredTitles = Array(store.titles.prefix(6))

        if !featuredTitles.isEmpty {
            let safeIndex = min(featuredIndex, featuredTitles.count - 1)
            let featuredTitle = featuredTitles[safeIndex]

            AsterionHero(
                imageURL: featuredTitle.imageURL,
                fallbackSystemImage: "play.tv",
                eyebrow: "Just updated",
                title: featuredTitle.displayTitle,
                summary: featuredSynopsis(for: featuredTitle),
                index: safeIndex,
                count: featuredTitles.count,
                select: { selectFeatured($0, titles: featuredTitles) }
            ) {
                HStack(spacing: 8) {
                    Text(featuredTitle.type ?? "Anime")
                    if let episodeLabel = featuredTitle.episodeLabel {
                        Text("·")
                        Text(episodeLabel)
                    }
                }
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
                }
                .buttonStyle(.asterionPrimary)

                Button { selectTitle(featuredTitle) } label: {
                    Label("Episodes", systemImage: "list.bullet")
                }
                .buttonStyle(.asterionSecondary)
            }
        }
    }

    private func selectFeatured(_ index: Int, titles: [AnimeTitle]) {
        guard titles.indices.contains(index) else { return }
        featuredIndex = index
        Task { await store.select(titles[index]) }
    }

    private func featuredSynopsis(for title: AnimeTitle) -> String? {
        guard store.selectedTitleID == title.id else { return nil }
        return store.show?.displayDescription.flatMap { $0.isEmpty ? nil : $0 }
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSection(title: shelfTitle, subtitle: shelfSubtitle) {
                if section == .genres, normalizedQuery.isEmpty, !store.genres.isEmpty {
                    Picker("Genre", selection: genreBinding) {
                        ForEach(store.genres, id: \.self) { genre in
                            Text(displayName(for: genre)).tag(genre)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                } else if section == .types, normalizedQuery.isEmpty {
                    Picker("Type", selection: typeBinding) {
                        ForEach(AnimeStore.types, id: \.self) { type in
                            Text(displayName(for: type)).tag(type)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            } content: {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: AsterionCardMetrics.posterWidth, maximum: AsterionCardMetrics.posterWidth), spacing: 20)],
                    alignment: .leading,
                    spacing: 28
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
                .padding(.horizontal, AsterionLayout.pageInset)
            }
            paginationStatus
                .padding(.horizontal, AsterionLayout.pageInset)
        }
    }

    @ViewBuilder
    private var paginationStatus: some View {
        if store.isLoadingNextPage {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .accessibilityLabel("Loading more anime")
        } else if let error = store.paginationError {
            HStack(spacing: 10) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(2)
                Spacer()
                Button("Try again") {
                    Task { await store.retryNextPage(section: section, query: normalizedQuery) }
                }
            }
            .padding(.vertical, 10)
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
        if !normalizedQuery.isEmpty { return "Results" }
        if section == .genres, let genre = store.selectedGenre { return displayName(for: genre) }
        if section == .types { return displayName(for: store.selectedType) }
        return section.catalogTitle
    }

    private var shelfSubtitle: String {
        if !normalizedQuery.isEmpty { return "Matching “\(normalizedQuery)”" }
        return section.catalogDescription
    }

    private var emptyState: some View {
        AsterionEmptyState(
            systemImage: "magnifyingglass",
            title: normalizedQuery.isEmpty ? "Nothing here yet" : "Nothing matches “\(normalizedQuery)”",
            message: normalizedQuery.isEmpty
                ? "This shelf is empty right now. Try another section."
                : "Try a shorter title or the Japanese name."
        )
        .background(Color.asterionMediaCanvas)
    }

    private var scheduleContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 34) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This week")
                        .font(.asterionTitle(30, weight: .heavy))
                        .foregroundStyle(Color.asterionText)
                    Text("Release times in \(TimeZone.current.localizedName(for: .standard, locale: .current) ?? TimeZone.current.identifier)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.asterionMuted)
                }

                if store.isLoadingSchedule, store.scheduleDays.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(0..<6, id: \.self) { _ in
                            AsterionSkeleton(cornerRadius: 12).frame(height: 54)
                        }
                    }
                } else if let error = store.scheduleError, store.scheduleDays.isEmpty {
                    AsterionEmptyState(
                        systemImage: "calendar.badge.exclamationmark",
                        title: "The schedule didn’t load",
                        message: error
                    ) {
                        Button("Try again") {
                            Task { await store.retrySchedule() }
                        }
                        .buttonStyle(.asterionSecondary)
                    }
                    .frame(height: 360)
                } else if store.scheduleDays.isEmpty {
                    AsterionEmptyState(
                        systemImage: "calendar",
                        title: "Nothing scheduled",
                        message: "No releases are listed for this week yet."
                    )
                    .frame(height: 360)
                } else {
                    ForEach(store.scheduleDays) { day in
                        scheduleDay(day)
                    }
                }
            }
            .frame(maxWidth: 940, alignment: .leading)
            .padding(.horizontal, AsterionLayout.pageInset)
            .padding(.top, AsterionLayout.catalogContentTop(topInset))
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .hidingScrollIndicators()
    }

    private func scheduleDay(_ day: AnimeScheduleDay) -> some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 4) {
                Text(day.label)
                    .font(.asterionTitle(15, weight: .bold))
                    .foregroundStyle(Color.asterionText)
                Text("\(day.entries.count) \(day.entries.count == 1 ? "release" : "releases")")
                    .font(.asterionMono(11))
                    .foregroundStyle(Color.asterionFaint)
            }
            .frame(width: 128, alignment: .leading)
            .padding(.top, 14)

            VStack(spacing: 0) {
                ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in
                    scheduleRow(entry)
                    if index < day.entries.count - 1 {
                        Rectangle()
                            .fill(Color.asterionHairline)
                            .frame(height: 1)
                            .padding(.leading, 86)
                    }
                }
            }
            .asterionPanel(cornerRadius: 14)
        }
    }

    private func scheduleRow(_ entry: AnimeScheduleEntry) -> some View {
        let isSelected = store.selectedTitleID == entry.slug
        return Button {
            Task { await store.select(entry) }
        } label: {
            HStack(spacing: 16) {
                Text(entry.time)
                    .font(.asterionMono(14, weight: .semibold))
                    .foregroundStyle(entry.passed ? Color.asterionFaint : Color.asterionText)
                    .frame(width: 54, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(entry.passed ? Color.asterionMuted : Color.asterionText)
                        .lineLimit(1)
                    if let japaneseTitle = entry.japaneseTitle, !japaneseTitle.isEmpty {
                        Text(japaneseTitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.asterionFaint)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 12)

                if let episode = entry.episodeNumber {
                    Text(verbatim: "EP \(episode)")
                        .font(.asterionMono(11, weight: .semibold))
                        .foregroundStyle(Color.asterionMuted)
                }

                Text(entry.passed ? "Aired" : "Upcoming")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(entry.passed ? Color.asterionFaint : Color.asterionMediaCanvas)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        entry.passed ? Color.clear : Color.asterionText,
                        in: Capsule()
                    )
                    .overlay {
                        if entry.passed {
                            Capsule().strokeBorder(Color.asterionBorder)
                        }
                    }
                    .frame(width: 74, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.white.opacity(0.06) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.displayTitle)
        .accessibilityValue(
            [entry.time, entry.episodeNumber.map { "Episode \($0)" }, entry.passed ? "Aired" : "Upcoming"]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
    }

    private func displayName(for genre: String) -> String {
        genre.replacingOccurrences(of: "-", with: " ").capitalized
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
            title: title.displayTitle,
            subtitle: title.episodeLabel ?? title.type ?? "Anime",
            fallbackSystemImage: "play.tv",
            isSelected: isSelected,
            action: action
        )
        .animation(reduceMotion ? nil : AsterionMotion.reveal, value: isSelected)
        .accessibilityValue(title.episodeLabel ?? title.type ?? "Anime")
    }
}
