import SwiftUI

struct UnifiedBookmarksView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    let query: String
    let selectNovel: (Novel) -> Void
    let selectMedia: (MediaBookmark) -> Void

    @State private var filter: BookmarkFilter = .all

    private let columns = [
        GridItem(
            .adaptive(minimum: AsterionCardMetrics.posterWidth, maximum: AsterionCardMetrics.posterWidth),
            spacing: 20,
            alignment: .top
        ),
    ]

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var novels: [Novel] {
        model.novels
            .filter { model.libraryNovelIDs.contains($0.id) }
            .filter { novel in
                normalizedQuery.isEmpty
                    || novel.title.localizedCaseInsensitiveContains(normalizedQuery)
                    || novel.authorDisplayName.localizedCaseInsensitiveContains(normalizedQuery)
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var media: [MediaBookmark] {
        model.mediaBookmarks.filter { bookmark in
            normalizedQuery.isEmpty
                || bookmark.title.localizedCaseInsensitiveContains(normalizedQuery)
                || bookmark.subtitle?.localizedCaseInsensitiveContains(normalizedQuery) == true
        }
    }

    private var filterOptions: [BookmarkFilter] {
        let base: [BookmarkFilter] = [.all, .novels, .anime, .films]
        return media.contains { $0.mediaType == .football } ? base + [.matches] : base
    }

    private var effectiveFilter: BookmarkFilter {
        filterOptions.contains(filter) ? filter : .all
    }

    var body: some View {
        let novels = novels
        let media = media
        let filter = effectiveFilter
        let visibleNovels = filter == .all || filter == .novels ? novels : []
        let visibleMedia = media.filter { filter.includes($0.mediaType) }

        Group {
            if novels.isEmpty, media.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    header(novels: novels, media: media, showsFilter: false)
                    emptyState
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else if visibleNovels.isEmpty, visibleMedia.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    header(novels: novels, media: media, showsFilter: true)
                    AsterionEmptyState(
                        systemImage: "bookmark",
                        title: "No \(filter.title.lowercased()) saved",
                        message: "Bookmark \(filter.noun) and it will be kept here, ready when you are."
                    ) {
                        Button("Show everything") { self.filter = .all }
                            .buttonStyle(.asterionSecondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header(novels: novels, media: media, showsFilter: true)

                        LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                            ForEach(visibleNovels) { novel in
                                AsterionPosterCard(
                                    imageURL: novel.imageURL.flatMap(URL.init(string:)),
                                    badge: filter == .all ? "Novel" : nil,
                                    title: novel.title,
                                    subtitle: novel.authorDisplayName,
                                    fallbackSystemImage: "book.closed"
                                ) {
                                    selectNovel(novel)
                                }
                            }

                            ForEach(visibleMedia) { bookmark in
                                AsterionPosterCard(
                                    imageURL: bookmark.imageURL,
                                    badge: filter == .all ? BookmarkFilter.badge(for: bookmark.mediaType) : nil,
                                    title: bookmark.title,
                                    subtitle: bookmark.subtitle ?? BookmarkFilter.badge(for: bookmark.mediaType),
                                    fallbackSystemImage: bookmark.mediaType.systemImage
                                ) {
                                    selectMedia(bookmark)
                                }
                            }
                        }
                        .padding(.horizontal, AsterionLayout.pageInset)
                        .padding(.top, 30)
                        .padding(.bottom, 56)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .hidingScrollIndicators()
            }
        }
        .background(Color.asterionMediaCanvas)
    }

    private func header(novels: [Novel], media: [MediaBookmark], showsFilter: Bool) -> some View {
        AsterionPageHeader("Bookmarks", subtitle: subtitle(novels: novels, media: media)) {
            if showsFilter {
                Picker("Show", selection: $filter) {
                    ForEach(filterOptions) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Filter by type")
            }
        }
    }

    private func subtitle(novels: [Novel], media: [MediaBookmark]) -> String {
        // Per-type counts live in the filter beside the title; keep this to one line.
        let total = novels.count + media.count
        guard total > 0 else { return "Everything you save appears here." }
        return total == 1 ? "1 saved title" : "\(total) saved titles"
    }

    @ViewBuilder
    private var emptyState: some View {
        if !normalizedQuery.isEmpty {
            AsterionEmptyState(
                systemImage: "magnifyingglass",
                title: "No matches",
                message: "Nothing you saved matches “\(normalizedQuery)”. Try a different title or author."
            )
        } else if model.isSignedIn {
            AsterionEmptyState(
                systemImage: "bookmark",
                title: "Nothing saved yet",
                message: "Use the bookmark button on any novel, anime, film, series, or match and it will wait for you here."
            )
        } else {
            AsterionEmptyState(
                systemImage: "bookmark",
                title: "Sign in to see your bookmarks",
                message: "Your bookmarks follow your Asterion account, so everything you save is here on every Mac."
            ) {
                Button {
                    openWindow(id: "authentication")
                } label: {
                    Label("Sign in", systemImage: "person.crop.circle")
                }
                .buttonStyle(.asterionPrimary)
            }
        }
    }
}

private enum BookmarkFilter: String, CaseIterable, Identifiable {
    case all
    case novels
    case anime
    case films
    case matches

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .novels: "Novels"
        case .anime: "Anime"
        case .films: "Films"
        case .matches: "Matches"
        }
    }

    var noun: String {
        switch self {
        case .all: "anything"
        case .novels: "a novel"
        case .anime: "an anime"
        case .films: "a film or series"
        case .matches: "a match"
        }
    }

    func includes(_ mediaType: MediaAccountType) -> Bool {
        switch self {
        case .all: true
        case .novels: false
        case .anime: mediaType == .anime
        case .films: mediaType == .movie
        case .matches: mediaType == .football
        }
    }

    static func badge(for mediaType: MediaAccountType) -> String {
        switch mediaType {
        case .anime: "Anime"
        case .movie: "Film"
        case .football: "Match"
        }
    }
}
