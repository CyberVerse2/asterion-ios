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
            let lastFeaturedIndex = max(0, min(8, store.titles.count) - 1)
            featuredIndex = min(featuredIndex, lastFeaturedIndex)
        }
    }

    private var animeContinueWatching: [MediaPlaybackProgress] {
        model.continueWatching.filter { $0.mediaType == .anime }
    }

    @ViewBuilder
    private var featuredBanner: some View {
        let featuredTitles = Array(store.titles.prefix(8))

        if !featuredTitles.isEmpty {
            let safeIndex = min(featuredIndex, featuredTitles.count - 1)
            let featuredTitle = featuredTitles[safeIndex]

            AnimeFeaturedBanner(
                title: featuredTitle,
                titles: featuredTitles,
                selectedIndex: safeIndex,
                selectIndex: { featuredIndex = $0 },
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

    private var genreBinding: Binding<String> {
        Binding(
            get: { store.selectedGenre ?? store.genres.first ?? "" },
            set: { genre in
                Task { await store.selectGenre(genre, query: normalizedQuery) }
            }
        )
    }

    private var shelfTitle: String {
        if !normalizedQuery.isEmpty { return "Search Results" }
        if section == .genres, let genre = store.selectedGenre { return displayName(for: genre) }
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
        .background(.background)
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

                featureContent(posterWidth: 118)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: 250)
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

            VStack(alignment: .leading, spacing: 13) {
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
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)

                HStack(spacing: 7) {
                    if let episodeLabel = title.episodeLabel {
                        featureBadge(episodeLabel, color: Color.asterionAccent)
                    }
                    if let type = title.type {
                        featureBadge(type, color: .white.opacity(0.16))
                    }
                }

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
            .padding(.vertical, 20)
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
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    MediaCoverView(url: title.imageURL, width: 128, height: 184)

                    if let episodeLabel = title.episodeLabel {
                        Text(episodeLabel)
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.asterionAccent, in: Capsule())
                            .padding(7)
                    }

                    if usesDiscoverBadges, let type = title.type {
                        Text(type)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.orange, in: Capsule())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(7)
                    }
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

                if !usesDiscoverBadges {
                    Text(title.type ?? "Anime")
                        .font(.caption)
                        .foregroundStyle(Color.asterionMuted)
                        .lineLimit(1)
                        .frame(maxWidth: 136, alignment: .leading)
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
