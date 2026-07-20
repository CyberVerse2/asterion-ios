import SwiftUI

struct MovieCatalogView: View {
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
                ContentUnavailableView(
                    "Keep typing",
                    systemImage: "character.cursor.ibeam",
                    description: Text("Enter at least two characters to search movies and TV shows.")
                )
            } else if (store.isLoadingCatalog
                || !store.hasLoadedCatalog(section: section, query: normalizedQuery)),
                store.titles.isEmpty {
                ProgressView(normalizedQuery.isEmpty ? "Curating your screen…" : "Searching…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.catalogError, store.titles.isEmpty {
                ContentUnavailableView {
                    Label("Movies unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") {
                        Task { await store.refresh(section: section, query: query) }
                    }
                }
            } else if store.titles.isEmpty {
                ContentUnavailableView(
                    "No titles found",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different title or category.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 34) {
                        if section == .discover, normalizedQuery.isEmpty {
                            featuredBanner
                                .padding(.horizontal, 32)

                            if !movieContinueWatching.isEmpty {
                                continueWatchingShelf
                            }
                        }

                        if section == .genres, normalizedQuery.isEmpty, !store.genres.isEmpty {
                            genreSelection
                                .padding(.horizontal, 32)
                        }

                        shelf
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
            await store.loadCatalog(section: section, query: normalizedQuery)
        }
        .onChange(of: store.titles) {
            featuredIndex = min(featuredIndex, max(0, min(8, store.titles.count) - 1))
        }
    }

    private var movieContinueWatching: [MediaPlaybackProgress] {
        model.continueWatching.filter { $0.mediaType == .movie }
    }

    private var continueWatchingShelf: some View {
        HomeSection(title: "Continue Watching", subtitle: "Pick up where you left off.") {
            HomeHorizontalShelf(
                items: movieContinueWatching,
                itemWidth: 294,
                spacing: 18,
                height: 172
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
                .padding(.vertical, 3)
            }
        }
    }

    @ViewBuilder
    private var featuredBanner: some View {
        let titles = Array(store.titles.prefix(8))
        if !titles.isEmpty {
            let safeIndex = min(featuredIndex, titles.count - 1)
            let title = titles[safeIndex]
            let synopsis = featuredSynopsis(for: title)

            AsterionFeatureCard(
                imageURL: title.imageURL,
                fallbackSystemImage: "play.rectangle.fill",
                eyebrow: "NOW TRENDING",
                title: title.displayTitle,
                summary: synopsis,
                previous: { moveFeatured(by: -1, titles: titles, selectedIndex: safeIndex) },
                next: { moveFeatured(by: 1, titles: titles, selectedIndex: safeIndex) }
            ) {
                featuredMetadataRow(title)
            } actions: {
                Button { openPlayer(title) } label: {
                    Label("Watch now", systemImage: "play.fill")
                        .font(.headline)
                        .frame(width: 132)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 8))
                .controlSize(.large)
                .tint(.asterionAccent)

                featuredBookmarkButton(title)
            }
        }
    }

    @ViewBuilder
    private func featuredMetadataRow(_ title: MovieTitle) -> some View {
        HStack(spacing: 14) {
            if let rating = title.imdbRating, !rating.isEmpty {
                Label(rating, systemImage: "star.fill")
            }

            Label(title.isSeries ? "TV Series" : "Movie", systemImage: "play.fill")

            if let year = title.year, !year.isEmpty {
                Label(year, systemImage: "calendar")
            }

            if let quality = title.quality, !quality.isEmpty {
                Text(quality.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.black.opacity(0.82))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 3))
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white.opacity(0.68))
        .lineLimit(1)
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
                    .frame(width: 86)
            } else {
                Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                    .frame(width: 86)
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 8))
        .controlSize(.large)
        .disabled(isUpdating)
        .help(isSaved ? "Remove from saved movies" : "Save this title to your account")
    }

    private func moveFeatured(
        by offset: Int,
        titles: [MovieTitle],
        selectedIndex: Int
    ) {
        guard !titles.isEmpty else { return }
        let destination = (selectedIndex + offset + titles.count) % titles.count
        featuredIndex = destination
        Task {
            await store.select(titles[destination])
        }
    }

    private var genreSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            shelfHeader(title: "Choose a Genre", subtitle: "Select a shelf to explore.")
            Picker("Genre", selection: genreBinding) {
                ForEach(store.genres) { genre in
                    Text(genre.title).tag(genre)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 240, alignment: .leading)
        }
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
                HomeHorizontalShelf(
                    items: store.titles,
                    itemWidth: 168,
                    spacing: 18,
                    height: 258
                ) { title in
                    MovieTitleTile(
                        title: title,
                        isSelected: store.selectedTitleID == title.id
                    ) {
                        selectTitle(title)
                    }
                    .padding(.vertical, 3)
                    .task {
                        await store.loadNextPageIfNeeded(
                            section: section,
                            query: normalizedQuery,
                            currentTitle: title
                        )
                    }
                }
            }

            Group {
                if store.isLoadingNextPage {
                    ProgressView("Loading more titles…")
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else if let error = store.paginationError {
                    HStack {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Color.asterionMuted)
                        Spacer()
                        Button("Try Again") {
                            Task { await store.retryNextPage(section: section, query: normalizedQuery) }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
        }
    }

    private func shelfHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.asterionDisplay(22, weight: .semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(Color.asterionMuted)
        }
    }

    private var shelfTitle: String {
        if !normalizedQuery.isEmpty { return "Search Results" }
        if section == .genres, let genre = store.selectedGenre { return genre.title }
        return section.catalogTitle
    }

    private var shelfSubtitle: String {
        normalizedQuery.isEmpty ? section.catalogDescription : "Titles matching your search."
    }

    private func featuredMetadata(_ title: MovieTitle) -> String {
        [title.year, title.isSeries ? "TV Series" : "Movie", title.imdbRating.map { "IMDb \($0)" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func featuredSynopsis(for title: MovieTitle) -> String {
        guard store.selectedTitleID == title.id else { return "Loading synopsis…" }

        let synopsis = store.show?.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let synopsis, !synopsis.isEmpty {
            return synopsis
        }
        if store.isLoadingDetail {
            return "Loading synopsis…"
        }
        return "Synopsis unavailable for this title."
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
            badge: title.isSeries ? "SERIES" : "MOVIE",
            title: title.displayTitle,
            subtitle: [title.isSeries ? "TV Series" : "Movie", title.year]
                .compactMap { $0 }
                .joined(separator: " · "),
            isSelected: isSelected,
            action: action
        )
    }
}
