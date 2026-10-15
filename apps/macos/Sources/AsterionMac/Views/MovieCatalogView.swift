import SwiftUI

struct MovieCatalogView: View {
    @Environment(\.asterionTopInset) private var topInset
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: MovieStore
    let section: MovieSection
    let query: String
    let selectTitle: (MovieTitle) -> Void

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
                    message: "Search needs at least two characters to look through films and series."
                )
            } else if (store.isLoadingCatalog
                || !store.hasLoadedCatalog(section: section, query: normalizedQuery)),
                store.titles.isEmpty {
                if showsHero {
                    AsterionCatalogSkeleton()
                } else {
                    gridSkeleton
                }
            } else if let error = store.catalogError, store.titles.isEmpty {
                AsterionEmptyState(
                    systemImage: "wifi.exclamationmark",
                    title: "Films and series didn’t load",
                    message: error
                ) {
                    Button("Try again") {
                        Task { await store.refresh(section: section, query: query) }
                    }
                    .buttonStyle(.asterionSecondary)
                }
            } else if store.titles.isEmpty {
                AsterionEmptyState(
                    systemImage: "magnifyingglass",
                    title: normalizedQuery.isEmpty ? "Nothing here yet" : "Nothing matches “\(normalizedQuery)”",
                    message: normalizedQuery.isEmpty
                        ? "This shelf is empty right now. Try another section."
                        : "Try a shorter title or another section."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AsterionLayout.sectionSpacing) {
                        if showsHero {
                            featuredBanner

                            if !movieContinueWatching.isEmpty {
                                continueWatchingShelf
                            }
                        }

                        shelf
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
            await store.loadCatalog(section: section, query: normalizedQuery)
        }
        .onChange(of: store.titles) {
            featuredIndex = min(featuredIndex, max(0, min(6, store.titles.count) - 1))
        }
    }

    private var showsHero: Bool {
        section == .discover && normalizedQuery.isEmpty
    }

    private var gridSkeleton: some View {
        AsterionGridSkeleton()
    }


    private var movieContinueWatching: [MediaPlaybackProgress] {
        model.continueWatching.filter { $0.mediaType == .movie }
    }

    private var continueWatchingShelf: some View {
        HomeSection(title: "Continue watching", subtitle: "Pick up where you left off") {
            HomeHorizontalShelf(
                items: movieContinueWatching,
                itemWidth: AsterionCardMetrics.landscapeWidth,
                spacing: 16,
                height: AsterionCardMetrics.landscapeShelfHeight
            ) { progress in
                HomeContinueCard(item: .watching(progress)) {
                    openWindow(
                        value: MoviePlayerRoute(
                            slug: progress.contentId,
                            title: progress.title,
                            initialEpisodeID: progress.unitId
                        )
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var featuredBanner: some View {
        let titles = Array(store.titles.prefix(6))
        if !titles.isEmpty {
            let safeIndex = min(featuredIndex, titles.count - 1)
            let title = titles[safeIndex]

            AsterionHero(
                imageURL: title.imageURL,
                fallbackSystemImage: title.isSeries ? "tv" : "film",
                eyebrow: title.isSeries ? "Trending series" : "Trending film",
                title: title.displayTitle,
                summary: featuredSynopsis(for: title),
                index: safeIndex,
                count: titles.count,
                select: { selectFeatured($0, titles: titles) }
            ) {
                featuredMetadataRow(title)
            } actions: {
                Button { openPlayer(title) } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.asterionPrimary)

                Button { selectTitle(title) } label: {
                    Label("Details", systemImage: "info.circle")
                }
                .buttonStyle(.asterionSecondary)

                featuredBookmarkButton(title)
            }
        }
    }

    @ViewBuilder
    private func featuredMetadataRow(_ title: MovieTitle) -> some View {
        HStack(spacing: 8) {
            Text(title.isSeries ? "Series" : "Film")

            if let year = title.year, !year.isEmpty {
                Text("·")
                Text(year)
            }

            if let rating = title.imdbRating, !rating.isEmpty {
                Text("·")
                Label(rating, systemImage: "star.fill")
                    .labelStyle(.titleAndIcon)
            }

            if let quality = title.quality, !quality.isEmpty {
                Text(quality.uppercased())
                    .font(.system(size: 9.5, weight: .bold).width(.expanded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.5)))
                    .padding(.leading, 4)
            }
        }
    }

    private func featuredBookmarkButton(_ title: MovieTitle) -> some View {
        let item = MediaItemDescriptor(
            mediaType: .movie,
            contentID: title.slug,
            title: title.displayTitle,
            subtitle: title.isSeries ? "TV Series" : "Movie",
            imageURL: title.imageURL
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
            } else {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
            }
        }
        .buttonStyle(.asterionSecondary)
        .disabled(isUpdating)
        .help(isSaved ? "Remove from saved" : "Save to your account")
        .accessibilityLabel(isSaved ? "Remove from saved" : "Save")
    }

    private func selectFeatured(_ index: Int, titles: [MovieTitle]) {
        guard titles.indices.contains(index) else { return }
        featuredIndex = index
        Task { await store.select(titles[index]) }
    }

    private var genreBinding: Binding<MovieGenre> {
        Binding(
            get: { store.selectedGenre ?? store.genres[0] },
            set: { genre in Task { await store.selectGenre(genre, query: normalizedQuery) } }
        )
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSection(title: shelfTitle, subtitle: shelfSubtitle) {
                if section == .genres, normalizedQuery.isEmpty, !store.genres.isEmpty {
                    Picker("Genre", selection: genreBinding) {
                        ForEach(store.genres) { genre in
                            Text(genre.title).tag(genre)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            } content: {
                if showsHero {
                    HomeHorizontalShelf(
                        items: store.titles,
                        itemWidth: AsterionCardMetrics.posterWidth,
                        spacing: 18,
                        height: AsterionCardMetrics.posterShelfHeight
                    ) { title in
                        movieTile(title)
                    }
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: AsterionCardMetrics.posterWidth, maximum: AsterionCardMetrics.posterWidth), spacing: 20)],
                        alignment: .leading,
                        spacing: 28
                    ) {
                        ForEach(store.titles) { title in
                            movieTile(title)
                        }
                    }
                    .padding(.horizontal, AsterionLayout.pageInset)
                }
            }

            Group {
                if store.isLoadingNextPage {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .accessibilityLabel("Loading more titles")
                } else if let error = store.paginationError {
                    HStack {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Color.asterionMuted)
                        Spacer()
                        Button("Try again") {
                            Task { await store.retryNextPage(section: section, query: normalizedQuery) }
                        }
                    }
                }
            }
            .padding(.horizontal, AsterionLayout.pageInset)
        }
    }

    private func movieTile(_ title: MovieTitle) -> some View {
        MovieTitleTile(
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

    private var shelfTitle: String {
        if !normalizedQuery.isEmpty { return "Results" }
        if section == .genres, let genre = store.selectedGenre { return genre.title }
        return section.catalogTitle
    }

    private var shelfSubtitle: String {
        normalizedQuery.isEmpty ? section.catalogDescription : "Matching “\(normalizedQuery)”"
    }

    private func featuredSynopsis(for title: MovieTitle) -> String? {
        guard store.selectedTitleID == title.id else { return nil }
        let synopsis = store.show?.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return synopsis.flatMap { $0.isEmpty ? nil : $0 }
    }

    private func openPlayer(_ title: MovieTitle) {
        openWindow(
            value: MoviePlayerRoute(
                slug: title.slug,
                title: title.displayTitle,
                initialEpisodeID: nil
            )
        )
    }
}

private struct MovieTitleTile: View {
    let title: MovieTitle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        AsterionPosterCard(
            imageURL: title.imageURL,
            title: title.displayTitle,
            subtitle: [title.isSeries ? "Series" : "Film", title.year]
                .compactMap { $0 }
                .joined(separator: " · "),
            fallbackSystemImage: title.isSeries ? "tv" : "film",
            isSelected: isSelected,
            action: action
        )
    }
}
