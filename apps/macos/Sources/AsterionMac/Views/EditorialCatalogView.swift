import SwiftUI

/// The novels catalog: Discover's editorial shelves, the ranked and filtered
/// section grids, and the genre index.
struct EditorialCatalogView: View {
    @Environment(\.asterionTopInset) private var topInset
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    let section: AppSection
    let query: String
    @Binding var genre: String
    @Binding var selectedNovelID: String
    let selectNovel: (Novel) -> Void
    /// Opens another novels section, optionally choosing a genre.
    let showSection: (AppSection, String?) -> Void

    @State private var featuredIndex = 0
    @State private var sort: NovelSort?
    @State private var openingNovelID: String?

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !normalizedQuery.isEmpty }

    private var isLoadingCatalog: Bool {
        (model.isLoadingCatalog || model.catalogState == .idle) && model.novels.isEmpty
    }

    private var catalogFailure: String? {
        guard model.novels.isEmpty, case .failed(let message) = model.catalogState else { return nil }
        return message
    }

    private var showsHero: Bool {
        section == .discover && !isSearching
    }

    private var selectedGenre: String? {
        let trimmed = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        Group {
            if isLoadingCatalog {
                if showsHero {
                    AsterionCatalogSkeleton()
                } else {
                    AsterionGridSkeleton()
                }
            } else if let catalogFailure {
                AsterionEmptyState(
                    systemImage: "wifi.exclamationmark",
                    title: "Novels didn’t load",
                    message: catalogFailure
                ) {
                    Button("Try again") {
                        Task { await model.loadCatalog() }
                    }
                    .buttonStyle(.asterionSecondary)
                }
            } else if model.novels.isEmpty {
                AsterionEmptyState(
                    systemImage: "books.vertical",
                    title: "No novels yet",
                    message: "The novel catalog is empty right now. Check your connection and reopen this page."
                )
            } else if isSearching {
                searchResults
            } else if section == .discover {
                discoverPage
            } else if section == .genres, selectedGenre == nil {
                genreIndexPage
            } else {
                sectionPage
            }
        }
        .background(Color.asterionMediaCanvas)
        .onChange(of: model.heroNovels) {
            featuredIndex = min(featuredIndex, max(0, model.heroNovels.count - 1))
        }
    }

    // MARK: Discover

    private var discoverPage: some View {
        let layout = model.novelDiscover
        return ScrollView {
            VStack(alignment: .leading, spacing: AsterionLayout.sectionSpacing) {
                featuredCard

                if !model.continueReadingEntries.isEmpty {
                    continueReadingShelf
                }

                if !layout.featured.isEmpty {
                    shelf(
                        title: "Featured",
                        subtitle: "Chosen for this week",
                        novels: layout.featured,
                        seeAll: (.topRated, nil)
                    )
                }

                if !layout.trending.isEmpty {
                    shelf(
                        title: "Trending",
                        subtitle: "What readers keep returning to",
                        novels: layout.trending,
                        seeAll: (.rankings, nil)
                    )
                }

                ForEach(Array(layout.shelves.enumerated()), id: \.element.id) { index, discoverShelf in
                    shelf(
                        title: discoverShelf.title,
                        subtitle: discoverShelf.subtitle,
                        novels: discoverShelf.novels,
                        metric: discoverShelf.kind == .mostRead ? .views : .rating,
                        seeAll: discoverShelf.destination
                    )

                    // Genres sit midway, once the page has shown its range.
                    if index == 1, !model.novelGenres.isEmpty {
                        genreStrip
                    }
                }

                if layout.shelves.count < 2, !model.novelGenres.isEmpty {
                    genreStrip
                }
            }
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .hidingScrollIndicators()
    }

    @ViewBuilder
    private var featuredCard: some View {
        let novels = model.heroNovels
        if !novels.isEmpty {
            let safeIndex = min(featuredIndex, novels.count - 1)
            let novel = novels[safeIndex]
            AsterionHero(
                imageURL: novel.imageURL.flatMap(URL.init(string:)),
                fallbackSystemImage: "book.closed",
                eyebrow: heroEyebrow(for: novel, position: safeIndex + 1),
                title: novel.title,
                summary: novel.summary
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .flatMap { $0.isEmpty ? nil : $0 },
                index: safeIndex,
                count: novels.count,
                select: {
                    featuredIndex = $0
                    if novels.indices.contains($0) { selectedNovelID = novels[$0].id }
                }
            ) {
                heroMetadata(novel)
            } actions: {
                Button { read(novel) } label: {
                    if openingNovelID == novel.id {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Opening…")
                        }
                    } else {
                        Label(readTitle(for: novel), systemImage: readSymbol(for: novel))
                    }
                }
                .buttonStyle(.asterionPrimary)
                .disabled(openingNovelID != nil)
                .help("Open in the reader")

                Button { open(novel) } label: {
                    Label("Details", systemImage: "info.circle")
                }
                .buttonStyle(.asterionSecondary)

                libraryButton(novel)
            }
        }
    }

    private func heroEyebrow(for novel: Novel, position: Int) -> String {
        let lead = "No. " + String(position) + " on Asterion"
        guard let genre = novel.displayGenres.first else { return lead }
        return lead + " · " + genre
    }

    private func heroMetadata(_ novel: Novel) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: novel.authorDisplayName)
            if let rating = novel.ratingLabel {
                Text("·")
                Label {
                    Text(verbatim: rating).font(.asterionMono(12.5, weight: .medium))
                } icon: {
                    Image(systemName: "star.fill")
                }
            }
            if let count = novel.chapterCount {
                Text("·")
                Text(verbatim: String(count) + " chapters")
            }
            if let status = novel.catalogStatus {
                Text("·")
                Text(status.title)
            }
        }
    }

    private func libraryButton(_ novel: Novel) -> some View {
        let isSaved = model.libraryNovelIDs.contains(novel.id)
        return Button {
            guard model.isSignedIn else {
                openWindow(id: "authentication")
                return
            }
            Task { await model.toggleLibrary(novelID: novel.id) }
        } label: {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.asterionSecondary)
        .disabled(model.isUpdatingLibrary)
        .help(isSaved ? "Remove from Library" : (model.isSignedIn ? "Add to Library" : "Sign in to keep a library"))
        .accessibilityLabel(isSaved ? "Remove from Library" : "Add to Library")
    }

    private var genreStrip: some View {
        HomeSection(title: "Browse by genre", subtitle: "Find your next shelf") {
            seeAllButton { showSection(.genres, "") }
        } content: {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.novelGenres) { entry in
                        Button {
                            showSection(.genres, entry.genre)
                        } label: {
                            HStack(spacing: 8) {
                                Text(verbatim: entry.genre)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.asterionText.opacity(0.9))
                                Text(verbatim: String(entry.count))
                                    .font(.asterionMono(11, weight: .medium))
                                    .foregroundStyle(Color.asterionFaint)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 34)
                            .background(Capsule().fill(Color.asterionSurface))
                            .overlay { Capsule().strokeBorder(Color.asterionBorder) }
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(entry.genre)
                        .accessibilityValue(String(entry.count) + " novels")
                    }
                }
                .padding(.horizontal, AsterionLayout.pageInset)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never, axes: .horizontal)
        }
    }

    private var continueReadingShelf: some View {
        HomeSection(title: "Continue reading", subtitle: "Pick up where you left off") {
            HomeHorizontalShelf(
                items: model.continueReadingEntries,
                itemWidth: AsterionCardMetrics.landscapeWidth,
                spacing: 16,
                height: AsterionCardMetrics.landscapeShelfHeight
            ) { entry in
                HomeContinueCard(
                    item: .reading(entry),
                    isSelected: selectedNovelID == entry.novel.id
                ) {
                    selectedNovelID = entry.novel.id
                    openWindow(
                        value: ReaderRoute(
                            novelID: entry.novel.id,
                            chapterID: entry.progress.chapterId
                        )
                    )
                }
                .contextMenu {
                    Button("Show Details") {
                        selectedNovelID = entry.novel.id
                        selectNovel(entry.novel)
                    }
                    Divider()
                    libraryContextMenu(for: entry.novel)
                }
            }
        }
    }

    private func shelf(
        title: String,
        subtitle: String,
        novels: [Novel],
        metric: EditorialBookTile.Metric = .rating,
        seeAll: (section: AppSection, genre: String?)?
    ) -> some View {
        HomeSection(title: title, subtitle: subtitle) {
            if let seeAll {
                seeAllButton { showSection(seeAll.section, seeAll.genre) }
            }
        } content: {
            HomeHorizontalShelf(
                items: novels,
                itemWidth: AsterionCardMetrics.posterWidth,
                spacing: 18,
                height: AsterionCardMetrics.posterShelfHeight
            ) { novel in
                bookTile(novel, rank: nil, metric: metric)
            }
        }
    }

    private func seeAllButton(action: @escaping () -> Void) -> some View {
        NovelSeeAllButton(action: action)
    }

    // MARK: Sections

    private var sectionNovels: [Novel] {
        model.novels(for: section, genre: selectedGenre, sort: sort)
    }

    private var activeSort: NovelSort {
        section.hasFixedOrder ? section.defaultSort : (sort ?? section.defaultSort)
    }

    private var tileMetric: EditorialBookTile.Metric {
        activeSort == .views ? .views : .rating
    }

    private var sectionPage: some View {
        let novels = sectionNovels
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HomeSection(title: sectionTitle, subtitle: sectionSubtitle) {
                    sectionControls(count: novels.count)
                } content: {
                    if novels.isEmpty {
                        sectionEmptyState
                            .frame(minHeight: 320)
                    } else {
                        grid(novels, ranked: section.showsRank)
                    }
                }
            }
            .padding(.top, AsterionLayout.catalogContentTop(topInset))
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .hidingScrollIndicators()
    }

    private var sectionTitle: String {
        if section == .genres, let selectedGenre { return selectedGenre }
        return section.catalogTitle
    }

    private var sectionSubtitle: String {
        if section == .genres, let selectedGenre {
            return "Novels shelved under " + selectedGenre.lowercased() + "."
        }
        return section.catalogDescription
    }

    @ViewBuilder
    private func sectionControls(count: Int) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: String(count) + (count == 1 ? " novel" : " novels"))
                .font(.asterionMono(11.5, weight: .medium))
                .foregroundStyle(Color.asterionFaint)

            if section == .genres, !model.novelGenres.isEmpty {
                Picker("Genre", selection: $genre) {
                    Text("All genres").tag("")
                    Divider()
                    ForEach(model.novelGenres) { entry in
                        Text(verbatim: entry.genre).tag(entry.genre)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityLabel("Genre")
            }

            if !section.hasFixedOrder {
                Picker("Sort", selection: sortBinding) {
                    ForEach(NovelSort.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityLabel("Sort novels")
            }
        }
    }

    private var sortBinding: Binding<NovelSort> {
        Binding(
            get: { activeSort },
            set: { sort = $0 }
        )
    }

    private var sectionEmptyState: some View {
        AsterionEmptyState(
            systemImage: "books.vertical",
            title: "Nothing here yet",
            message: section == .genres
                ? "No novels are shelved under this genre right now."
                : "No novels fit this shelf right now. Try another section."
        ) {
            Button("Browse all novels") { showSection(.all, nil) }
                .buttonStyle(.asterionSecondary)
        }
    }

    private func grid(_ novels: [Novel], ranked: Bool) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: AsterionCardMetrics.posterWidth, maximum: AsterionCardMetrics.posterWidth), spacing: 20)],
            alignment: .leading,
            spacing: 28
        ) {
            ForEach(Array(novels.enumerated()), id: \.element.id) { index, novel in
                bookTile(novel, rank: ranked ? index + 1 : nil, metric: tileMetric)
            }
        }
        .padding(.horizontal, AsterionLayout.pageInset)
    }

    // MARK: Genre index

    private var genreIndexPage: some View {
        ScrollView {
            HomeSection(title: AppSection.genres.catalogTitle, subtitle: AppSection.genres.catalogDescription) {
                Text(verbatim: String(model.novelGenres.count) + " genres")
                    .font(.asterionMono(11.5, weight: .medium))
                    .foregroundStyle(Color.asterionFaint)
            } content: {
                if model.novelGenres.isEmpty {
                    AsterionEmptyState(
                        systemImage: "square.grid.2x2",
                        title: "No genres yet",
                        message: "These novels haven’t been shelved by genre. Browse the full catalog instead."
                    ) {
                        Button("Browse all novels") { showSection(.all, nil) }
                            .buttonStyle(.asterionSecondary)
                    }
                    .frame(minHeight: 320)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 236, maximum: 320), spacing: 16)],
                        alignment: .leading,
                        spacing: 16
                    ) {
                        ForEach(model.novelGenres) { entry in
                            NovelGenreCard(
                                genre: entry.genre,
                                count: entry.count,
                                coverURL: coverURL(forGenre: entry.genre)
                            ) {
                                genre = entry.genre
                            }
                        }
                    }
                    .padding(.horizontal, AsterionLayout.pageInset)
                }
            }
            .padding(.top, AsterionLayout.catalogContentTop(topInset))
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .hidingScrollIndicators()
    }

    private func coverURL(forGenre genre: String) -> URL? {
        model.novels(for: .genres, genre: genre, sort: .popular)
            .lazy
            .compactMap { $0.imageURL.flatMap(URL.init(string:)) }
            .first
    }

    // MARK: Search

    private var searchResults: some View {
        let results = model.novels(for: section, search: normalizedQuery)
        return Group {
            if results.isEmpty {
                AsterionEmptyState(
                    systemImage: "magnifyingglass",
                    title: "No novels match “\(normalizedQuery)”",
                    message: "Try a shorter title, an author, or a genre."
                )
            } else {
                ScrollView {
                    HomeSection(
                        title: "Results",
                        subtitle: "Matching “\(normalizedQuery)”"
                    ) {
                        Text(verbatim: String(results.count) + (results.count == 1 ? " novel" : " novels"))
                            .font(.asterionMono(11.5, weight: .medium))
                            .foregroundStyle(Color.asterionFaint)
                    } content: {
                        grid(results, ranked: false)
                    }
                    .padding(.top, AsterionLayout.catalogContentTop(topInset))
                    .padding(.bottom, 64)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .hidingScrollIndicators()
            }
        }
    }

    // MARK: Tiles and actions

    private func bookTile(_ novel: Novel, rank: Int?, metric: EditorialBookTile.Metric) -> some View {
        EditorialBookTile(
            novel: novel,
            isSelected: selectedNovelID == novel.id,
            rank: rank,
            metric: metric
        ) {
            open(novel)
        }
        .contextMenu {
            Button(readTitle(for: novel)) { read(novel) }
            Button("Show Details") { open(novel) }
            Divider()
            libraryContextMenu(for: novel)
        }
    }

    private func open(_ novel: Novel) {
        selectedNovelID = novel.id
        selectNovel(novel)
    }

    /// Opens the reader at the saved chapter, or the first one. Falls back
    /// to the details page when no chapter can be resolved.
    private func read(_ novel: Novel) {
        guard openingNovelID == nil else { return }
        selectedNovelID = novel.id
        openingNovelID = novel.id
        Task {
            let chapterID = await model.readingStartChapterID(for: novel)
            openingNovelID = nil
            if let chapterID {
                openWindow(value: ReaderRoute(novelID: novel.id, chapterID: chapterID))
            } else {
                selectNovel(novel)
            }
        }
    }

    private func readingProgress(for novel: Novel) -> NovelProgress? {
        model.progressByNovelID[novel.id].map { model.novelProgress(for: novel, progress: $0) }
    }

    private func readTitle(for novel: Novel) -> String {
        guard let progress = readingProgress(for: novel) else { return "Read" }
        if progress.isFinished { return "Read again" }
        guard let chapter = progress.chapterNumber else { return "Continue reading" }
        return "Continue chapter " + String(chapter)
    }

    private func readSymbol(for novel: Novel) -> String {
        guard let progress = readingProgress(for: novel) else { return "book.pages.fill" }
        return progress.isFinished ? "arrow.counterclockwise" : "book.fill"
    }

    @ViewBuilder
    private func libraryContextMenu(for novel: Novel) -> some View {
        Button(model.libraryNovelIDs.contains(novel.id) ? "Remove from Library" : "Add to Library") {
            Task { await model.toggleLibrary(novelID: novel.id) }
        }
        .disabled(!model.isSignedIn)
    }
}

/// "See all" beside a shelf title.
private struct NovelSeeAllButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("See all")
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .bold))
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(isHovering ? Color.asterionText : Color.asterionMuted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : AsterionMotion.hover, value: isHovering)
    }
}

/// A genre in the genre index: its best-known cover bleeding in from the
/// right, the name in the title face, and the count in mono.
private struct NovelGenreCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    let genre: String
    let count: Int
    let coverURL: URL?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                GeometryReader { geometry in
                    ArtworkImage(url: coverURL, fallbackSystemImage: "book.closed")
                        .frame(width: geometry.size.width * 0.62, height: geometry.size.height)
                        .clipped()
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black.opacity(0.75), location: 0.5),
                                    .init(color: .black, location: 1),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        }
                        .opacity(isHovering ? 0.85 : 0.6)
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .trailing)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: genre)
                        .font(.asterionTitle(17, weight: .bold))
                        .foregroundStyle(Color.asterionText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(verbatim: String(count) + (count == 1 ? " novel" : " novels"))
                        .font(.asterionMono(11, weight: .medium))
                        .foregroundStyle(Color.asterionMuted)
                }
                .padding(16)
            }
            .frame(height: 104)
            .frame(maxWidth: .infinity)
            .background(Color.asterionSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovering ? 0.24 : 0.08))
            }
            .background {
                if isHovering {
                    ArtworkToneReader(url: coverURL) { tone in
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(tone.opacity(0.45))
                            .blur(radius: 22)
                            .offset(y: 8)
                    }
                    .transition(.opacity)
                }
            }
            .scaleEffect(isHovering && !reduceMotion ? 1.02 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : AsterionMotion.hover, value: isHovering)
        .asterionReveal()
        .accessibilityLabel(genre)
        .accessibilityValue(String(count) + " novels")
    }
}

struct EditorialBookTile: View {
    /// The figure at the end of the caption line.
    enum Metric {
        case rating
        case views
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let novel: Novel
    let isSelected: Bool
    let rank: Int?
    var metric: Metric = .rating
    let action: () -> Void

    var body: some View {
        AsterionPosterCard(
            imageURL: novel.imageURL.flatMap(URL.init(string:)),
            title: novel.title,
            subtitle: novel.catalogMetadata,
            detail: detail,
            detailSystemImage: detail == nil ? nil : (metric == .views ? "eye.fill" : "star.fill"),
            rank: rank,
            fallbackSystemImage: "book.closed",
            isSelected: isSelected,
            action: action
        )
        .animation(reduceMotion ? nil : AsterionMotion.reveal, value: isSelected)
    }

    private var detail: String? {
        switch metric {
        case .rating:
            novel.ratingLabel
        case .views:
            novel.views
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }
        }
    }
}
