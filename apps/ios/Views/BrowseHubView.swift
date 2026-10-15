import SwiftUI
import UserNotifications

struct BrowseHubView: View {
    @State private var selection: BrowseContent = .novels

    var body: some View {
        selectedContent
            .environment(\.browseSelection, $selection)
            .background { AsterionBackdrop() }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selection {
        case .novels:
            HomeView(mode: .browse)
        case .anime:
            AnimeCatalogView()
        case .moviesTV:
            MovieCatalogView()
        case .football:
            FootballCatalogView()
        }
    }
}

enum BrowseContent: String, CaseIterable, Identifiable {
    case novels
    case anime
    case moviesTV
    case football

    var id: String { rawValue }

    var title: String {
        switch self {
        case .novels: "Novels"
        case .anime: "Anime"
        case .moviesTV: "Movies & TV"
        case .football: "Football"
        }
    }

    var symbol: String {
        switch self {
        case .novels: "book.closed"
        case .anime: "play.tv"
        case .moviesTV: "film"
        case .football: "soccerball"
        }
    }
}

private struct BrowseSelectionKey: EnvironmentKey {
    static let defaultValue: Binding<BrowseContent>? = nil
}

extension EnvironmentValues {
    var browseSelection: Binding<BrowseContent>? {
        get { self[BrowseSelectionKey.self] }
        set { self[BrowseSelectionKey.self] = newValue }
    }
}

struct BrowseContentPicker: View {
    @Binding var selection: BrowseContent

    var body: some View {
        AsterionIndexTabs(
            items: BrowseContent.allCases,
            title: { $0.title },
            selection: $selection
        )
    }
}

struct BrowseCatalogChrome<Content: View>: View {
    @Environment(\.browseSelection) private var browseSelection
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            if let browseSelection {
                BrowseContentPicker(selection: browseSelection)
            }
            content
        }
    }
}

struct AnimeCatalogView: View {
    private static let types = ["tv", "movie", "ova", "ona", "special", "music"]

    @State private var section: AnimeBrowseSection = .discover
    @State private var titles: [AnimeTitle] = []
    @State private var genres: [String] = []
    @State private var selectedGenre: String?
    @State private var selectedType = "tv"
    @State private var query = ""
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            BrowseCatalogChrome {
                VStack(spacing: 0) {
                    AsterionIndexTabs(
                        items: AnimeBrowseSection.allCases,
                        title: { $0.rawValue },
                        rank: .subheader,
                        selection: $section
                    )

                    CatalogScrollView(
                        query: $query,
                        isLoading: isLoading,
                        error: error,
                        isEmpty: titles.isEmpty,
                        retry: { await load() }
                    ) {
                        if section == .genres, !genres.isEmpty, let selectedGenre {
                            CatalogFilterChips(
                                items: genres,
                                title: Self.displayName,
                                selection: Binding(
                                    get: { selectedGenre },
                                    set: { self.selectedGenre = $0 }
                                )
                            )
                        }

                        if section == .types {
                            CatalogFilterChips(
                                items: Self.types,
                                title: Self.displayName,
                                selection: $selectedType
                            )
                        }

                        catalogPosterGrid
                    }
                }
                .navigationDestination(for: AnimeTitle.self) { title in
                    AnimeDetailView(title: title)
                }
                .toolbar(.hidden, for: .navigationBar)
                .task(id: catalogTaskID) {
                    if !query.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
                    guard !Task.isCancelled else { return }
                    await load()
                }
            }
        }
    }

    private var catalogTaskID: String {
        "\(section.rawValue)-\(query)-\(selectedGenre ?? "")-\(selectedType)"
    }

    private var catalogPosterGrid: some View {
        LazyVGrid(columns: catalogColumns, spacing: 16) {
            ForEach(titles) { title in
                NavigationLink(value: title) {
                    EntertainmentPosterCard(
                        title: title.title,
                        imageURL: title.imageURL,
                        eyebrow: [title.type, title.episodeLabel]
                            .compactMap { $0 }
                            .joined(separator: " · ")
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        isLoading = titles.isEmpty
        defer { isLoading = false }
        do {
            titles = try await fetchTitles()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func fetchTitles() async throws -> [AnimeTitle] {
        let api = EntertainmentAPI.shared
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { return try await api.fetchAnime(query: q) }

        switch section {
        case .discover, .updated:
            return try await api.fetchAnime()
        case .added:
            return try await api.fetchAnimeReleases()
        case .popular:
            return try await api.fetchPopularAnime()
        case .airing:
            return try await api.fetchAnimeStatus("currently-airing")
        case .upcoming:
            return try await api.fetchAnimeStatus("not-yet-aired")
        case .completed:
            return try await api.fetchAnimeStatus("finished-airing")
        case .schedule:
            return try await api.fetchAnimeSchedule()
        case .genres:
            if genres.isEmpty {
                genres = try await api.fetchAnimeGenres()
                selectedGenre = genres.first
            }
            guard let selectedGenre else { return [] }
            return try await api.fetchAnimeGenre(selectedGenre)
        case .types:
            return try await api.fetchAnimeType(selectedType)
        }
    }

    private static func displayName(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

struct MovieCatalogView: View {
    @State private var section: MovieBrowseSection = .discover
    @State private var titles: [MovieTitle] = []
    @State private var genres: [MovieGenre] = []
    @State private var selectedGenre: MovieGenre?
    @State private var query = ""
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            BrowseCatalogChrome {
                VStack(spacing: 0) {
                    AsterionIndexTabs(
                        items: MovieBrowseSection.allCases,
                        title: { $0.rawValue },
                        rank: .subheader,
                        selection: $section
                    )

                    CatalogScrollView(
                        query: $query,
                        isLoading: isLoading,
                        error: error,
                        isEmpty: titles.isEmpty,
                        retry: { await load() }
                    ) {
                        if section == .genres, !genres.isEmpty, let selectedGenre {
                            CatalogFilterChips(
                                items: genres,
                                title: \.title,
                                selection: Binding(
                                    get: { selectedGenre },
                                    set: { self.selectedGenre = $0 }
                                )
                            )
                        }

                        LazyVGrid(columns: catalogColumns, spacing: 16) {
                            ForEach(titles) { title in
                                NavigationLink(value: title) {
                                    EntertainmentPosterCard(
                                        title: title.title,
                                        imageURL: title.imageURL,
                                        eyebrow: [title.year, title.imdbRating.map { "★ \($0)" }]
                                            .compactMap { $0 }
                                            .joined(separator: " · ")
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .navigationDestination(for: MovieTitle.self) { title in
                    MovieDetailView(title: title)
                }
                .toolbar(.hidden, for: .navigationBar)
                .task(id: "\(section.rawValue)-\(query)-\(selectedGenre?.slug ?? "")") {
                    if !query.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
                    guard !Task.isCancelled else { return }
                    await load()
                }
            }
        }
    }

    private func load() async {
        isLoading = titles.isEmpty
        defer { isLoading = false }
        do {
            titles = try await fetchTitles()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func fetchTitles() async throws -> [MovieTitle] {
        let api = EntertainmentAPI.shared
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { return try await api.fetchMovies(kind: .movies, query: q) }

        switch section {
        case .discover:
            return try await api.fetchTrendingMovies()
        case .movies:
            return try await api.fetchMovies(kind: .movies)
        case .tvShows:
            return try await api.fetchMovies(kind: .tv)
        case .popular:
            return try await api.fetchPopularMovies()
        case .genres:
            if genres.isEmpty {
                genres = try await api.fetchMovieGenres()
                selectedGenre = genres.first
            }
            guard let selectedGenre else { return [] }
            return try await api.fetchMovies(genreSlug: selectedGenre.slug)
        }
    }
}

private struct CatalogScrollView<Content: View>: View {
    @Binding var query: String
    let isLoading: Bool
    let error: String?
    let isEmpty: Bool
    let retry: () async -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SearchInputView(text: $query)

                if isLoading && isEmpty {
                    ProgressView()
                        .tint(Color.asterionInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else if let error, isEmpty {
                    CatalogErrorView(message: error, retry: retry)
                } else if isEmpty {
                    Text("No results")
                        .font(.asterionSerif(18))
                        .foregroundStyle(Color.asterionMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else {
                    content
                }
            }
            .frame(maxWidth: 1100, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
        }
        .background { AsterionBackdrop() }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await retry() }
    }
}

private struct CatalogErrorView: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.asterionMuted)
            Text(message)
                .font(.asterionReading(16))
                .foregroundStyle(Color.asterionMuted)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await retry() } }
                .font(.asterionReading(15, weight: .semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .buttonStyle(AsterionFilledButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
    }
}

private struct EntertainmentPosterCard: View {
    let title: String
    let imageURL: URL?
    let eyebrow: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: imageURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.asterionCard)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(Color.asterionMuted)
                        }
                }
            }
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(title)
                .font(.asterionDisplay(17, weight: .medium))
                .foregroundStyle(Color.asterionText)
                .lineLimit(2)

            if !eyebrow.isEmpty {
                Text(eyebrow)
                    .font(.asterionMono(9))
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private enum MediaDetailShelf: String, CaseIterable, Hashable {
    case episodes = "Episodes"
    case moreLikeThis = "More like this"
}

private func emptyShelfMessage(_ text: String) -> some View {
    Text(text)
        .font(.asterionReading(15))
        .foregroundStyle(Color.asterionMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
}

private struct SimilarPosterGrid<Item: Identifiable, Destination: View>: View {
    let items: [Item]
    let title: (Item) -> String
    let imageURL: (Item) -> URL?
    let eyebrow: (Item) -> String
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ViewBuilder let destination: (Item) -> Destination

    var body: some View {
        if items.isEmpty {
            emptyShelfMessage("Nothing similar yet")
        } else {
            LazyVGrid(
                columns: AsterionLayout.posterColumns(horizontalSizeClass),
                spacing: 14
            ) {
                ForEach(items) { item in
                    NavigationLink {
                        destination(item)
                    } label: {
                        EntertainmentPosterCard(
                            title: title(item),
                            imageURL: imageURL(item),
                            eyebrow: eyebrow(item)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
        }
    }
}

private func similarAnimeTitles(to show: AnimeShow) async -> [AnimeTitle] {
    let api = EntertainmentAPI.shared
    var pool: [AnimeTitle] = []
    if let first = show.genres.first {
        let candidates = [
            first,
            first.lowercased(),
            first.lowercased().replacingOccurrences(of: " ", with: "-"),
        ]
        for candidate in candidates {
            if let fetched = try? await api.fetchAnimeGenre(candidate), !fetched.isEmpty {
                pool = fetched
                break
            }
        }
    }
    if pool.isEmpty {
        pool = (try? await api.fetchPopularAnime()) ?? []
    }
    var seen = Set<String>()
    return pool
        .filter { $0.slug != show.slug && seen.insert($0.slug).inserted }
        .prefix(12)
        .map { $0 }
}

private func similarMovieTitles(to show: MovieShow) async -> [MovieTitle] {
    let api = EntertainmentAPI.shared
    var pool: [MovieTitle] = []
    if let genres = try? await api.fetchMovieGenres(),
       let match = genres.first(where: { genre in
           show.genres.contains { $0.caseInsensitiveCompare(genre.title) == .orderedSame }
       })
    {
        pool = (try? await api.fetchMovies(genreSlug: match.slug)) ?? []
    }
    if pool.isEmpty {
        pool = (try? await api.fetchPopularMovies()) ?? []
    }
    var seen = Set<String>()
    return pool
        .filter { $0.slug != show.slug && seen.insert($0.slug).inserted }
        .prefix(12)
        .map { $0 }
}

private let catalogColumns = [
    GridItem(.adaptive(minimum: 142, maximum: 210), spacing: 16, alignment: .top),
]

private struct CatalogFilterChips<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(items, id: \.self) { item in
                    let selected = selection == item
                    Button {
                        selection = item
                    } label: {
                        Text(title(item))
                            .font(.asterionReading(14, weight: .medium))
                            .foregroundStyle(selected ? Color.asterionOnInk : Color.asterionText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(selected ? Color.asterionInk : Color.asterionCard, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 10)
    }
}

struct AnimeDetailView: View {
    let title: AnimeTitle

    @EnvironmentObject private var tabBarState: TabBarState
    @EnvironmentObject private var mediaAccountService: MediaAccountService
    @EnvironmentObject private var offlineVideoDownloadService: OfflineVideoDownloadService
    @Environment(\.dismiss) private var dismiss
    @State private var show: AnimeShow?
    @State private var episodes: [AnimeEpisode] = []
    @State private var playback: PlaybackRequest?
    @State private var isLoading = true
    @State private var playbackEpisodeID: String?
    @State private var isMassDownloading = false
    @State private var massDownloadCompleted = 0
    @State private var massDownloadTotal = 0
    @State private var episodePage = 0
    @State private var error: String?
    @State private var playbackError: String?
    @State private var synopsisExpanded = false
    @State private var detailShelf: MediaDetailShelf = .episodes
    @State private var similarTitles: [AnimeTitle] = []
    private let episodePageSize = 50

    private var stats: [AsterionDetailStat] {
        [
            show?.type.map { AsterionDetailStat(label: "Type", value: $0) },
            show?.status.map { AsterionDetailStat(label: "Status", value: $0) },
            show?.malScore.map { AsterionDetailStat(label: "Score", value: "★ \($0)") },
            episodes.isEmpty ? nil : AsterionDetailStat(label: "Episodes", value: "\(episodes.count)"),
        ].compactMap { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AsterionDetailHero(
                    title: show?.title ?? title.title,
                    subtitle: [show?.type, title.episodeLabel].compactMap { $0 }.joined(separator: " · ")
                ) {
                    AsterionDetailPoster(url: show?.imageURL ?? title.imageURL)
                }

                if !stats.isEmpty {
                    AsterionDetailStatsRow(items: stats)
                }

                HStack(spacing: 10) {
                    if let episode = nextAnimeEpisode {
                        Button {
                            Task { await play(episode) }
                        } label: {
                            AsterionPrimaryActionLabel(
                                title: playbackEpisodeID == episode.id
                                    ? "Finding stream…"
                                    : animePlayTitle(for: episode)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(playbackEpisodeID != nil)
                    }

                    MediaSaveButton(item: mediaItem)
                    if !episodes.isEmpty {
                        MediaMassDownloadButton(
                            isComplete: pendingAnimeDownloads.isEmpty,
                            isBusy: isMassDownloading,
                            progress: massDownloadProgress,
                            accessibilityLabel: massDownloadLabel
                        ) {
                            Task { await downloadAllEpisodes() }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

                if let playbackError {
                    Text(playbackError)
                        .font(.asterionSerif(15))
                        .foregroundStyle(Color.asterionMuted)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }

                if let summary = show?.description, !summary.isEmpty {
                    AsterionSynopsisBlock(text: summary, genres: show?.genres ?? [], expanded: $synopsisExpanded)
                }

                if isLoading {
                    ProgressView().tint(Color.asterionInk).frame(maxWidth: .infinity).padding(.vertical, 28)
                } else if let error {
                    CatalogErrorView(message: error) { await load() }
                } else {
                    detailShelfSection
                }
            }
            .padding(.bottom, 48)
            .background(alignment: .top) {
                AsterionCoverBleed(url: show?.imageURL ?? title.imageURL)
            }
        }
        .background(Color.asterionBackground)
        .overlay(alignment: .top) {
            AsterionDetailBar(onBack: { dismiss() }) { EmptyView() }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .onAppear { tabBarState.isVisible = false }
        .onDisappear { tabBarState.isVisible = true }
        .edgeSwipeToDismiss { dismiss() }
        .task { await load() }
        .fullScreenCover(item: $playback, onDismiss: PlaybackOrientationLock.endVideo) { request in
            NativeMediaPlayerView(request: request)
        }
    }

    private var episodePages: [[AnimeEpisode]] {
        stride(from: 0, to: episodes.count, by: episodePageSize).map { start in
            Array(episodes[start..<min(start + episodePageSize, episodes.count)])
        }
    }

    private var visibleEpisodes: [AnimeEpisode] {
        guard episodePages.indices.contains(episodePage) else { return episodes }
        return episodePages[episodePage]
    }

    private var detailShelfSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AsterionIndexTabs(
                items: MediaDetailShelf.allCases,
                title: { $0.rawValue },
                rank: .section,
                selection: $detailShelf
            )

            switch detailShelf {
            case .episodes:
                if episodes.isEmpty {
                    emptyShelfMessage("No episodes yet")
                } else {
                    episodeSection
                }
            case .moreLikeThis:
                SimilarPosterGrid(
                    items: similarTitles,
                    title: { $0.title },
                    imageURL: { $0.imageURL },
                    eyebrow: {
                        [$0.type, $0.episodeLabel].compactMap { $0 }.joined(separator: " · ")
                    }
                ) { title in
                    AnimeDetailView(title: title)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if episodePages.count > 1 {
                AsterionFilterPills(
                    titles: episodePages.map { page in
                        "\(page.first?.number ?? 0)–\(page.last?.number ?? 0)"
                    },
                    selectedIndex: episodePage,
                    onSelect: { episodePage = $0 }
                )
            }

            AsterionEpisodeShelf(title: nil, items: visibleEpisodes) { episode in
                let requestID = "anime-\(episode.animeID)-\(episode.number)"
                AsterionEpisodeCard(
                    number: episode.number,
                    title: "Episode \(episode.number)",
                    subtitle: animeEpisodeStatus(episode),
                    imageURL: show?.imageURL ?? title.imageURL,
                    isBusy: playbackEpisodeID == episode.id,
                    downloadProgress: offlineVideoDownloadService.progress(forID: requestID),
                    isDownloaded: offlineVideoDownloadService.isDownloaded(id: requestID),
                    onPlay: { Task { await play(episode) } },
                    onDownload: { Task { await download(episode) } }
                )
            }
        }
    }

    private var nextAnimeEpisode: AnimeEpisode? {
        MediaContinuePolicy.resumeUnit(
            from: episodes,
            progress: mediaAccountService.snapshot.progress,
            matches: matchesAnimeProgress
        )
    }

    private func matchesAnimeProgress(_ episode: AnimeEpisode, _ item: MediaPlaybackProgress) -> Bool {
        item.mediaType == .anime && item.contentId == title.slug && item.episodeNumber == episode.number
    }

    private func animePlayTitle(for episode: AnimeEpisode) -> String {
        if MediaContinuePolicy.isInProgress(episode, progress: mediaAccountService.snapshot.progress, matches: matchesAnimeProgress) {
            return "Continue Episode \(episode.number)"
        }
        return "Play Episode \(episode.number)"
    }

    private func animeEpisodeStatus(_ episode: AnimeEpisode) -> String {
        let progress = mediaAccountService.snapshot.progress.first {
            $0.mediaType == .anime && $0.contentId == title.slug && $0.episodeNumber == episode.number
        }
        if progress?.completed == true { return "Watched" }
        if let progress, progress.percentage > 0 {
            return "Continue · \(Int(progress.percentage.rounded()))%"
        }
        if nextAnimeEpisode?.id == episode.id { return "Up next" }
        return "Available"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedShow = try await EntertainmentAPI.shared.fetchAnimeShow(slug: title.slug)
            show = loadedShow
            async let episodesFetch = EntertainmentAPI.shared.fetchAnimeEpisodes(showID: loadedShow.id)
            async let similarFetch = similarAnimeTitles(to: loadedShow)
            episodes = try await episodesFetch.sorted { $0.number < $1.number }
            similarTitles = await similarFetch
            episodePage = 0
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func play(_ episode: AnimeEpisode) async {
        playbackEpisodeID = episode.id
        playbackError = nil
        defer { playbackEpisodeID = nil }
        do {
            playback = try await animePlayback(for: episode)
        } catch {
            playbackError = error.localizedDescription
        }
    }

    private var pendingAnimeDownloads: [AnimeEpisode] {
        episodes.filter { episode in
            !offlineVideoDownloadService.isDownloaded(id: "anime-\(episode.animeID)-\(episode.number)")
        }
    }

    private var massDownloadProgress: CGFloat {
        guard massDownloadTotal > 0 else { return 0 }
        return min(1, CGFloat(massDownloadCompleted) / CGFloat(massDownloadTotal))
    }

    private var massDownloadLabel: String {
        if isMassDownloading {
            return "Downloading \(massDownloadCompleted)/\(max(massDownloadTotal, 1))"
        }
        if pendingAnimeDownloads.isEmpty {
            return "Available offline"
        }
        return "Download all episodes"
    }

    private func download(_ episode: AnimeEpisode) async {
        do {
            let request = try await animePlayback(for: episode)
            offlineVideoDownloadService.start(request)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func downloadAllEpisodes() async {
        let pending = pendingAnimeDownloads
        guard !pending.isEmpty, !isMassDownloading else { return }
        isMassDownloading = true
        massDownloadTotal = pending.count
        massDownloadCompleted = 0
        defer { isMassDownloading = false }
        for episode in pending {
            do {
                let request = try await animePlayback(for: episode)
                offlineVideoDownloadService.start(request)
            } catch {
                self.error = error.localizedDescription
            }
            massDownloadCompleted += 1
        }
    }

    private func animePlayback(for episode: AnimeEpisode) async throws -> PlaybackRequest {
        let request = try await EntertainmentAPI.shared.fetchAnimePlayback(
            animeID: episode.animeID,
            episodeNumber: episode.number,
            title: "\(show?.title ?? title.title) · Episode \(episode.number)",
            item: mediaItem
        )
        return request.withQueue(animePlaybackQueue)
    }

    private var animePlaybackQueue: PlaybackQueue? {
        guard episodes.count > 1 else { return nil }
        let showTitle = show?.title ?? title.title
        return PlaybackQueue(
            sources: episodes.map { episode in
                .anime(
                    animeID: episode.animeID,
                    episodeNumber: episode.number,
                    title: "\(showTitle) · Episode \(episode.number)",
                    item: mediaItem
                )
            }
        )
    }

    private var mediaItem: MediaItemDescriptor {
        MediaItemDescriptor(
            mediaType: .anime,
            contentID: title.slug,
            title: show?.title ?? title.title,
            subtitle: show?.type ?? title.type,
            imageURL: show?.imageURL ?? title.imageURL
        )
    }
}

struct MovieDetailView: View {
    let title: MovieTitle

    @EnvironmentObject private var tabBarState: TabBarState
    @EnvironmentObject private var mediaAccountService: MediaAccountService
    @EnvironmentObject private var offlineVideoDownloadService: OfflineVideoDownloadService
    @Environment(\.dismiss) private var dismiss
    @State private var show: MovieShow?
    @State private var episodes: [MovieEpisode] = []
    @State private var playback: PlaybackRequest?
    @State private var isLoading = true
    @State private var playbackID: String?
    @State private var isMassDownloading = false
    @State private var massDownloadCompleted = 0
    @State private var massDownloadTotal = 0
    @State private var selectedSeason: Int?
    @State private var error: String?
    @State private var playbackError: String?
    @State private var synopsisExpanded = false
    @State private var detailShelf: MediaDetailShelf = .episodes
    @State private var similarTitles: [MovieTitle] = []

    private var isSeries: Bool { show?.isSeries == true }

    private var movieShelves: [MediaDetailShelf] {
        isSeries ? MediaDetailShelf.allCases : [.moreLikeThis]
    }

    private var stats: [AsterionDetailStat] {
        var items: [AsterionDetailStat] = []
        if let year = show?.releaseYear ?? title.year {
            items.append(AsterionDetailStat(label: "Year", value: year))
        }
        if let runtime = show?.duration ?? title.runtime {
            items.append(AsterionDetailStat(label: "Runtime", value: runtime))
        }
        if let rating = show?.imdbRating ?? title.imdbRating {
            items.append(AsterionDetailStat(label: "IMDb", value: "★ \(rating)"))
        }
        if isSeries, !episodes.isEmpty {
            items.append(AsterionDetailStat(label: "Episodes", value: "\(episodes.count)"))
        } else {
            items.append(AsterionDetailStat(label: "Kind", value: isSeries ? "Series" : "Movie"))
        }
        return items
    }

    private var seasons: [Int] {
        Array(Set(episodes.map(\.season))).sorted()
    }

    private var activeSeason: Int {
        selectedSeason ?? seasons.first ?? 1
    }

    private var episodesForActiveSeason: [MovieEpisode] {
        episodes.filter { $0.season == activeSeason }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AsterionDetailHero(
                    title: show?.title ?? title.title,
                    subtitle: [show?.releaseYear ?? title.year, isSeries ? "Series" : "Movie"]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                ) {
                    AsterionDetailPoster(url: show?.imageURL ?? title.imageURL)
                }

                if !stats.isEmpty {
                    AsterionDetailStatsRow(items: stats)
                }

                HStack(spacing: 10) {
                    primaryPlay
                    MediaSaveButton(item: mediaItem)
                    if canMassDownloadMovies {
                        MediaMassDownloadButton(
                            isComplete: pendingMovieDownloads.isEmpty && movieAlreadyDownloaded,
                            isBusy: isMassDownloading,
                            progress: movieMassDownloadProgress,
                            accessibilityLabel: movieMassDownloadLabel
                        ) {
                            Task { await downloadAllMovies() }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 8)

                if let playbackError {
                    Text(playbackError)
                        .font(.asterionSerif(15))
                        .foregroundStyle(Color.asterionMuted)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }

                if let summary = show?.description, !summary.isEmpty {
                    AsterionSynopsisBlock(text: summary, genres: show?.genres ?? [], expanded: $synopsisExpanded)
                }

                if isLoading {
                    ProgressView().tint(Color.asterionInk).frame(maxWidth: .infinity).padding(.vertical, 28)
                } else if let error {
                    CatalogErrorView(message: error) { await load() }
                } else {
                    movieDetailShelf
                }
            }
            .padding(.bottom, 48)
            .background(alignment: .top) {
                AsterionCoverBleed(url: show?.imageURL ?? title.imageURL)
            }
        }
        .background(Color.asterionBackground)
        .overlay(alignment: .top) {
            AsterionDetailBar(onBack: { dismiss() }) { EmptyView() }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .onAppear { tabBarState.isVisible = false }
        .onDisappear { tabBarState.isVisible = true }
        .edgeSwipeToDismiss { dismiss() }
        .task { await load() }
        .fullScreenCover(item: $playback, onDismiss: PlaybackOrientationLock.endVideo) { request in
            NativeMediaPlayerView(request: request)
        }
    }

    @ViewBuilder
    private var primaryPlay: some View {
        if isSeries, let episode = nextMovieEpisode {
            let unitTitle = episode.title.isEmpty ? "Episode \(episode.number)" : episode.title
            playControl(
                slug: episode.id,
                label: playbackID == episode.id ? "Finding stream…" : moviePlayTitle(for: episode),
                playbackLabel: unitTitle
            )
        } else if !isSeries {
            playControl(
                slug: title.slug,
                label: playbackID == title.slug ? "Finding stream…" : "Play Movie",
                playbackLabel: title.title
            )
        }
    }

    private var movieDetailShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            AsterionIndexTabs(
                items: movieShelves,
                title: { $0.rawValue },
                rank: .section,
                selection: $detailShelf
            )

            switch detailShelf {
            case .episodes:
                if episodes.isEmpty {
                    emptyShelfMessage("No episodes yet")
                } else {
                    episodeLists
                }
            case .moreLikeThis:
                SimilarPosterGrid(
                    items: similarTitles,
                    title: { $0.title },
                    imageURL: { $0.imageURL },
                    eyebrow: {
                        [$0.year, $0.imdbRating.map { "★ \($0)" }]
                            .compactMap { $0 }
                            .joined(separator: " · ")
                    }
                ) { title in
                    MovieDetailView(title: title)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var episodeLists: some View {
        VStack(alignment: .leading, spacing: 12) {
            if seasons.count > 1 {
                AsterionFilterPills(
                    titles: seasons.map { "Season \($0)" },
                    selectedIndex: seasons.firstIndex(of: activeSeason) ?? 0,
                    onSelect: { selectedSeason = seasons[$0] }
                )
            }

            AsterionEpisodeShelf(title: nil, items: episodesForActiveSeason) { episode in
                let requestID = "movie-\(episode.id)"
                AsterionEpisodeCard(
                    number: episode.number,
                    title: episode.title.isEmpty ? "Episode \(episode.number)" : episode.title,
                    subtitle: movieEpisodeStatus(episode),
                    imageURL: show?.imageURL ?? title.imageURL,
                    isBusy: playbackID == episode.id,
                    downloadProgress: offlineVideoDownloadService.progress(forID: requestID),
                    isDownloaded: offlineVideoDownloadService.isDownloaded(id: requestID),
                    onPlay: { Task { await play(slug: episode.id, label: episode.title) } },
                    onDownload: { Task { await download(episode) } }
                )
            }
        }
    }

    private var nextMovieEpisode: MovieEpisode? {
        MediaContinuePolicy.resumeUnit(
            from: episodes,
            progress: mediaAccountService.snapshot.progress,
            matches: matchesMovieProgress
        )
    }

    private func matchesMovieProgress(_ episode: MovieEpisode, _ item: MediaPlaybackProgress) -> Bool {
        item.mediaType == .movie && item.contentId == title.slug && item.unitId == episode.id
    }

    private func moviePlayTitle(for episode: MovieEpisode) -> String {
        let unit = "S\(episode.season) E\(episode.number)"
        if MediaContinuePolicy.isInProgress(episode, progress: mediaAccountService.snapshot.progress, matches: matchesMovieProgress) {
            return "Continue \(unit)"
        }
        return "Play \(unit)"
    }

    private func movieEpisodeStatus(_ episode: MovieEpisode) -> String {
        let progress = mediaAccountService.snapshot.progress.first {
            $0.mediaType == .movie && $0.contentId == title.slug && $0.unitId == episode.id
        }
        if progress?.completed == true { return "Watched" }
        if let progress, progress.percentage > 0 {
            return "Continue · \(Int(progress.percentage.rounded()))%"
        }
        if nextMovieEpisode?.id == episode.id { return "Up next" }
        return "Available"
    }

    private func playControl(slug: String, label: String, playbackLabel: String) -> some View {
        Button {
            Task { await play(slug: slug, label: playbackLabel) }
        } label: {
            AsterionPrimaryActionLabel(title: label)
        }
        .buttonStyle(.plain)
        .disabled(playbackID != nil)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedShow = try await EntertainmentAPI.shared.fetchMovieShow(slug: title.slug)
            show = loadedShow
            async let similarFetch = similarMovieTitles(to: loadedShow)
            if loadedShow.isSeries {
                episodes = try await EntertainmentAPI.shared.fetchMovieEpisodes(slug: title.slug)
                    .sorted { ($0.season, $0.number) < ($1.season, $1.number) }
                selectedSeason = nextMovieEpisode?.season ?? episodes.first?.season
                detailShelf = .episodes
            } else {
                detailShelf = .moreLikeThis
            }
            similarTitles = await similarFetch
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func play(slug: String, label: String) async {
        playbackID = slug
        playbackError = nil
        defer { playbackID = nil }
        do {
            playback = try await moviePlayback(slug: slug, label: label)
        } catch {
            playbackError = error.localizedDescription
        }
    }

    private var canMassDownloadMovies: Bool {
        isSeries ? !episodes.isEmpty : !isLoading
    }

    private var pendingMovieDownloads: [MovieEpisode] {
        episodes.filter { episode in
            !offlineVideoDownloadService.isDownloaded(id: "movie-\(episode.id)")
        }
    }

    private var movieAlreadyDownloaded: Bool {
        if isSeries { return pendingMovieDownloads.isEmpty && !episodes.isEmpty }
        return offlineVideoDownloadService.isDownloaded(id: "movie-\(title.slug)")
    }

    private var movieMassDownloadProgress: CGFloat {
        guard massDownloadTotal > 0 else { return 0 }
        return min(1, CGFloat(massDownloadCompleted) / CGFloat(massDownloadTotal))
    }

    private var movieMassDownloadLabel: String {
        if isMassDownloading {
            return "Downloading \(massDownloadCompleted)/\(max(massDownloadTotal, 1))"
        }
        if movieAlreadyDownloaded {
            return "Available offline"
        }
        return isSeries ? "Download all episodes" : "Download movie"
    }

    private func download(_ episode: MovieEpisode) async {
        do {
            let request = try await moviePlayback(slug: episode.id, label: episode.title)
            offlineVideoDownloadService.start(request)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func downloadAllMovies() async {
        guard !isMassDownloading else { return }
        isMassDownloading = true
        defer { isMassDownloading = false }

        if isSeries {
            let pending = pendingMovieDownloads
            guard !pending.isEmpty else { return }
            massDownloadTotal = pending.count
            massDownloadCompleted = 0
            for episode in pending {
                do {
                    let request = try await moviePlayback(slug: episode.id, label: episode.title)
                    offlineVideoDownloadService.start(request)
                } catch {
                    self.error = error.localizedDescription
                }
                massDownloadCompleted += 1
            }
            return
        }

        guard !movieAlreadyDownloaded else { return }
        massDownloadTotal = 1
        massDownloadCompleted = 0
        do {
            let request = try await moviePlayback(slug: title.slug, label: title.title)
            offlineVideoDownloadService.start(request)
        } catch {
            self.error = error.localizedDescription
        }
        massDownloadCompleted = 1
    }

    private func moviePlayback(slug: String, label: String) async throws -> PlaybackRequest {
        let episode = episodes.first { $0.id == slug }
        let request = try await EntertainmentAPI.shared.fetchMoviePlayback(
            slug: slug,
            title: show?.isSeries == true ? "\(show?.title ?? title.title) · \(label)" : title.title,
            item: mediaItem,
            unitTitle: show?.isSeries == true ? label : "Movie",
            seasonNumber: episode?.season,
            episodeNumber: episode?.number
        )
        return request.withQueue(moviePlaybackQueue)
    }

    private var moviePlaybackQueue: PlaybackQueue? {
        guard isSeries, episodes.count > 1 else { return nil }
        let showTitle = show?.title ?? title.title
        return PlaybackQueue(
            sources: episodes.map { episode in
                let unitTitle = episode.title.isEmpty ? "Episode \(episode.number)" : episode.title
                return .movie(
                    slug: episode.id,
                    title: "\(showTitle) · \(unitTitle)",
                    item: mediaItem,
                    unitTitle: unitTitle,
                    seasonNumber: episode.season,
                    episodeNumber: episode.number
                )
            }
        )
    }

    private var mediaItem: MediaItemDescriptor {
        MediaItemDescriptor(
            mediaType: .movie,
            contentID: title.slug,
            title: show?.title ?? title.title,
            subtitle: show?.isSeries == true ? "TV Series" : "Movie",
            imageURL: show?.imageURL ?? title.imageURL
        )
    }
}


struct FootballCatalogView: View {
    @State private var section: FootballCatalogSection = .live
    @State private var matches: [FootballMatch] = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var error: String?

    private var filteredMatches: [FootballMatch] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return matches }
        return matches.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(normalized)
                || $0.category.localizedCaseInsensitiveContains(normalized)
        }
    }

    var body: some View {
        NavigationStack {
            BrowseCatalogChrome {
                VStack(spacing: 0) {
                    AsterionIndexTabs(
                        items: FootballCatalogSection.allCases,
                        title: { $0.rawValue },
                        rank: .subheader,
                        selection: $section
                    )

                    CatalogScrollView(
                        query: $query,
                        isLoading: isLoading,
                        error: error,
                        isEmpty: filteredMatches.isEmpty,
                        retry: { await load() }
                    ) {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredMatches) { match in
                                NavigationLink(value: match) {
                                    FootballMatchCard(match: match)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .navigationDestination(for: FootballMatch.self) { match in
                        FootballDetailView(match: match)
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .task(id: section) { await load() }
                }
            }
        }
    }

    private func load() async {
        isLoading = matches.isEmpty
        defer { isLoading = false }
        do {
            matches = try await EntertainmentAPI.shared.fetchFootball(section: section)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct FootballMatchCard: View {
    let match: FootballMatch

    var body: some View {
        HStack(spacing: 14) {
            teamBadge(match.teams?.home)

            VStack(spacing: 5) {
                if match.isLive {
                    Text("Live")
                        .font(.asterionReading(12, weight: .semibold))
                        .foregroundStyle(.red)
                } else {
                    Text(match.kickoff, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .font(.asterionReading(12, weight: .medium))
                        .foregroundStyle(Color.asterionMuted)
                }

                Text(match.displayTitle)
                    .font(.asterionSerif(17, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(match.category.capitalized)
                    .font(.asterionMono(9))
                    .foregroundStyle(Color.asterionMuted)
            }
            .frame(maxWidth: .infinity)

            teamBadge(match.teams?.away)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.asterionDim)
        }
        .padding(15)
        .asterionGlassSurface(cornerRadius: 18, interactive: true)
    }

    private func teamBadge(_ team: FootballTeam?) -> some View {
        AsyncImage(url: team?.badgeURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
            } else {
                Image(systemName: "shield")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.asterionMuted)
                    .padding(8)
            }
        }
        .frame(width: 42, height: 42)
        .accessibilityLabel(team?.name ?? "Team")
    }
}

struct FootballDetailView: View {
    let match: FootballMatch

    @State private var playback: PlaybackRequest?
    @State private var isLoadingPlayback = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let posterURL = match.posterURL {
                    AsyncImage(url: posterURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Rectangle().fill(Color.asterionCard)
                        }
                    }
                    .frame(maxWidth: 760)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                }

                VStack(spacing: 10) {
                    Text(match.isLive ? "Live now" : match.kickoff.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute()))
                        .font(.asterionReading(14, weight: .medium))
                        .foregroundStyle(match.isLive ? Color.red : Color.asterionMuted)

                    Text(match.displayTitle)
                        .font(.asterionDisplay(32, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                        .multilineTextAlignment(.center)

                    Text(match.category.capitalized)
                        .font(.asterionSerif(16))
                        .foregroundStyle(Color.asterionMuted)
                }


                HStack(spacing: 10) {
                    if match.isLive {
                        Button {
                            Task { await watch() }
                        } label: {
                            Label(isLoadingPlayback ? "Finding stream…" : "Watch live", systemImage: "play.fill")
                                .font(.asterionReading(17, weight: .semibold))
                                .padding(.horizontal, 22)
                                .padding(.vertical, 13)
                        }
                        .buttonStyle(AsterionFilledButtonStyle())
                        .disabled(isLoadingPlayback)
                    } else {
                        Button {
                            Task { await scheduleReminder() }
                        } label: {
                            Label("Remind me", systemImage: "bell")
                                .font(.asterionReading(17, weight: .semibold))
                                .padding(.horizontal, 22)
                                .padding(.vertical, 13)
                        }
                        .buttonStyle(AsterionFilledButtonStyle())
                    }

                    MediaSaveButton(item: mediaItem)
                }

                if let message {
                    Text(message)
                        .font(.asterionSerif(15))
                        .foregroundStyle(Color.asterionMuted)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: 900)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background { AsterionBackdrop() }
        .navigationTitle(match.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playback, onDismiss: PlaybackOrientationLock.endVideo) { request in
            NativeMediaPlayerView(request: request)
        }
    }

    private func watch() async {
        isLoadingPlayback = true
        defer { isLoadingPlayback = false }
        do {
            playback = try await EntertainmentAPI.shared.fetchFootballPlayback(match: match)
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func scheduleReminder() async {
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else {
                message = "Notifications are off. You can enable them in Settings."
                return
            }
            let reminderDate = max(Date().addingTimeInterval(5), match.kickoff.addingTimeInterval(-15 * 60))
            let content = UNMutableNotificationContent()
            content.title = "Match starts soon"
            content.body = match.displayTitle
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: reminderDate
                ),
                repeats: false
            )
            try await center.add(
                UNNotificationRequest(
                    identifier: "asterion.match.\(match.id)",
                    content: content,
                    trigger: trigger
                )
            )
            message = "Reminder set for 15 minutes before kickoff."
        } catch {
            message = error.localizedDescription
        }
    }

    private var mediaItem: MediaItemDescriptor {
        MediaItemDescriptor(
            mediaType: .football,
            contentID: match.id,
            title: match.displayTitle,
            subtitle: match.category.capitalized,
            imageURL: match.posterURL
        )
    }
}

private struct MediaSaveButton: View {
    let item: MediaItemDescriptor

    @EnvironmentObject private var mediaAccountService: MediaAccountService
    @State private var isWorking = false

    private var isSaved: Bool { mediaAccountService.isBookmarked(item) }

    var body: some View {
        AsterionCircleIconButton(
            systemName: isSaved ? "bookmark.fill" : "bookmark",
            isBusy: isWorking,
            accessibilityLabel: isSaved ? "Remove from library" : "Save to library"
        ) {
            Task {
                isWorking = true
                await mediaAccountService.toggleBookmark(item)
                isWorking = false
            }
        }
        .disabled(isWorking)
    }
}
