import SwiftUI

struct MovieCatalogView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: MovieStore
    let section: MovieSection
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
        .background(.background)
        .navigationTitle(section.title)
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

                MediaCoverView(url: title.imageURL, width: 118, height: 169)
                    .fixedSize()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 20)
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 13) {
                    Text("NOW TRENDING")
                        .font(.asterionMono(10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Color.asterionAccent)

                    Text(title.displayTitle)
                        .font(.asterionDisplay(23, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(3)

                    Text(featuredMetadata(title))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)

                    Spacer(minLength: 10)

                    Text(synopsis)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.76))
                        .lineSpacing(2)
                        .lineLimit(3)
                        .accessibilityLabel("Synopsis")
                        .accessibilityValue(synopsis)

                    Spacer(minLength: 10)

                    Button {
                        openPlayer(title)
                    } label: {
                        Label("Watch now", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 10))
                    .controlSize(.large)
                    .tint(.asterionAccent)
                }
                .padding(.leading, 20)
                .padding(.trailing, 158)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.12))
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 2) {
                    ForEach(titles.indices, id: \.self) { index in
                        Button {
                            featuredIndex = index
                            Task { await store.select(titles[index]) }
                        } label: {
                            Circle()
                                .fill(index == safeIndex ? Color.asterionAccent : .white.opacity(0.42))
                                .frame(
                                    width: index == safeIndex ? 8 : 6,
                                    height: index == safeIndex ? 8 : 6
                                )
                                .frame(width: 14, height: 14)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show \(titles[index].displayTitle)")
                        .accessibilityValue("Feature \(index + 1) of \(titles.count)")
                        .accessibilityAddTraits(index == safeIndex ? .isSelected : [])
                        .help(titles[index].displayTitle)
                    }
                }
                .padding(10)
            }
            .shadow(color: .black.opacity(0.18), radius: 18, y: 9)
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
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    MediaCoverView(url: title.imageURL, width: 128, height: 184)

                    if let rating = title.imdbRating {
                        Text("★ \(rating)")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.72), in: Capsule())
                            .padding(7)
                    }

                    Text(title.isSeries ? "TV" : "MOVIE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.asterionAccent, in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(7)
                }
                .padding(4)
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(isSelected ? Color.asterionAccent : .clear, lineWidth: 2)
                }

                Text(title.displayTitle)
                    .font(.asterionDisplay(15, weight: .medium))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(2)
                    .frame(maxWidth: 136, alignment: .leading)

                Text([title.year, title.runtime].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
                    .frame(maxWidth: 136, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .asterionHoverLift()
        .accessibilityLabel(title.displayTitle)
    }
}
