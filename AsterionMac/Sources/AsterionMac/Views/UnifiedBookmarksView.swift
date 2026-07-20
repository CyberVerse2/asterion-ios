import SwiftUI

struct UnifiedBookmarksView: View {
    @EnvironmentObject private var model: AppModel
    let query: String
    let selectNovel: (Novel) -> Void
    let selectMedia: (MediaBookmark) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 168, maximum: 168), spacing: 22, alignment: .top),
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

    var body: some View {
        Group {
            if novels.isEmpty, media.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Bookmarks")
                                .font(.asterionDisplay(28, weight: .semibold))
                            Text("Everything you saved, across Asterion.")
                                .font(.callout)
                                .foregroundStyle(Color.asterionMuted)
                        }

                        LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                            ForEach(novels) { novel in
                                BookmarkTile(
                                    title: novel.title,
                                    subtitle: novel.authorDisplayName,
                                    badge: "NOVEL",
                                    imageURL: novel.imageURL.flatMap(URL.init(string:))
                                ) {
                                    selectNovel(novel)
                                }
                            }

                            ForEach(media) { bookmark in
                                BookmarkTile(
                                    title: bookmark.title,
                                    subtitle: bookmark.subtitle ?? bookmark.mediaType.title,
                                    badge: bookmark.mediaType.title.uppercased(),
                                    imageURL: bookmark.imageURL
                                ) {
                                    selectMedia(bookmark)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 980, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 48)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .hidingScrollIndicators()
            }
        }
        .background(Color.asterionMediaCanvas)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            model.isSignedIn ? "No bookmarks yet" : "Sign in to view bookmarks",
            systemImage: model.isSignedIn ? "bookmark" : "person.crop.circle.badge.questionmark",
            description: Text(
                model.isSignedIn
                    ? "Save a novel, anime, movie, series, or match and it will appear here."
                    : "Your bookmarks follow your Asterion account."
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BookmarkTile: View {
    let title: String
    let subtitle: String
    let badge: String
    let imageURL: URL?
    let action: () -> Void

    var body: some View {
        AsterionPosterCard(
            imageURL: imageURL,
            badge: badge,
            title: title,
            subtitle: subtitle,
            action: action
        )
    }
}
