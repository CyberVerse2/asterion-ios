import SwiftUI

struct MovieCatalogView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: MovieStore
    let section: MovieSection
    let query: String

    @State private var featuredIndex = 0

    private let columns = [
        GridItem(.adaptive(minimum: 168, maximum: 168), spacing: 22, alignment: .top),
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
                    description: Text("Enter at least two characters to search movies and TV shows.")
                )
            } else if store.isLoadingCatalog, store.titles.isEmpty {
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

                            if !movieContinueWatching.isEmpty {
                                ContinueWatchingShelf(entries: movieContinueWatching) { progress in
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

                        if section == .genres, normalizedQuery.isEmpty, !store.genres.isEmpty {
                            genreSelection
                        }

                        shelf
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
            await store.loadCatalog(section: section, query: normalizedQuery)
        }
        .onChange(of: store.titles) {
            featuredIndex = min(featuredIndex, max(0, min(8, store.titles.count) - 1))
        }
    }

    private var movieContinueWatching: [MediaPlaybackProgress] {
        model.continueWatching.filter { $0.mediaType == .movie }
    }

    @ViewBuilder
    private var featuredBanner: some View {
        let titles = Array(store.titles.prefix(8))
        if !titles.isEmpty {
            let safeIndex = min(featuredIndex, titles.count - 1)
            let title = titles[safeIndex]
            let synopsis = featuredSynopsis(for: title)

            GeometryReader { geometry in
                ZStack {
                    AsyncImage(url: title.imageURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill().blur(radius: 24).scaleEffect(1.18)
                        } else {
                            Color.asterionCard
                        }
                    }
                    .clipped()

                    LinearGradient(
                        colors: [.black.opacity(0.90), .black.opacity(0.24)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )

                    HStack(spacing: 0) {
                        featuredPoster(title)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("NOW TRENDING")
                                .font(.asterionMono(10, weight: .semibold))
                                .tracking(1.4)
                                .foregroundStyle(Color.asterionAccent)

                            Text(title.displayTitle)
                                .font(.asterionDisplay(23, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.82)

                            featuredMetadataRow(title)

                            Text(synopsis)
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.76))
                                .lineSpacing(2)
                                .lineLimit(2)
                                .padding(.top, 3)
                                .accessibilityLabel("Synopsis")
                                .accessibilityValue(synopsis)

                            Spacer(minLength: 6)

                            HStack(spacing: 10) {
                                Button {
                                    openPlayer(title)
                                } label: {
                                    Label("Watch now", systemImage: "play.fill")
                                        .font(.headline)
                                        .frame(width: 132)
                                }
                                .buttonStyle(.glassProminent)
                                .buttonBorderShape(.roundedRectangle(radius: 8))
                                .controlSize(.large)
                                .tint(.asterionAccent)

                                featuredBookmarkButton(title)

                                Spacer()

                                featuredNavigationButton(
                                    systemImage: "chevron.left",
                                    help: "Previous featured title"
                                ) {
                                    moveFeatured(by: -1, titles: titles, selectedIndex: safeIndex)
                                }

                                featuredNavigationButton(
                                    systemImage: "chevron.right",
                                    help: "Next featured title"
                                ) {
                                    moveFeatured(by: 1, titles: titles, selectedIndex: safeIndex)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.12))
            }
            .shadow(color: .black.opacity(0.18), radius: 18, y: 9)
        }
    }

    private func featuredPoster(_ title: MovieTitle) -> some View {
        AsyncImage(url: title.imageURL) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Color.asterionCard
                    .overlay {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(Color.asterionAccent.opacity(0.72))
                    }
            }
        }
        .frame(width: 156, height: 220)
        .clipped()
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.34)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 30)
        }
        .accessibilityHidden(true)
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

    private func featuredNavigationButton(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.70))
        .help(help)
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
        VStack(alignment: .leading, spacing: 18) {
            shelfHeader(title: shelfTitle, subtitle: shelfSubtitle)

            if section == .discover, normalizedQuery.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 22) {
                        movieTiles
                    }
                    .padding(.vertical, 2)
                }
                .hidingScrollIndicators()
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                    movieTiles
                }
            }

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
    }

    @ViewBuilder
    private var movieTiles: some View {
        ForEach(store.titles) { title in
            MovieTitleTile(
                title: title,
                isSelected: store.selectedTitleID == title.id
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
