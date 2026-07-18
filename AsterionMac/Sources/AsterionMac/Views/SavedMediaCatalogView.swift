import SwiftUI

struct SavedMediaCatalogView: View {
    @Environment(\.openWindow) private var openWindow

    let mediaType: MediaAccountType
    let bookmarks: [MediaBookmark]
    let query: String
    let isSignedIn: Bool
    let selectedContentID: String?
    let select: @MainActor (MediaBookmark) async -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 118, maximum: 154), spacing: 22, alignment: .top),
    ]

    private var visibleBookmarks: [MediaBookmark] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return bookmarks }
        return bookmarks.filter {
            $0.title.localizedCaseInsensitiveContains(normalizedQuery)
                || $0.subtitle?.localizedCaseInsensitiveContains(normalizedQuery) == true
        }
    }

    var body: some View {
        Group {
            if !isSignedIn {
                signedOutState
            } else if visibleBookmarks.isEmpty {
                emptyState
            } else {
                bookmarkGrid
            }
        }
        .background(.background)
        .navigationTitle("Bookmarks")
    }

    private var bookmarkGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your Bookmarks")
                        .font(.asterionDisplay(22, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                    Text(bookmarkDescription)
                        .font(.callout)
                        .foregroundStyle(Color.asterionMuted)
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                    ForEach(visibleBookmarks) { bookmark in
                        Button {
                            Task { await select(bookmark) }
                        } label: {
                            SavedMediaTile(
                                bookmark: bookmark,
                                isSelected: selectedContentID == bookmark.contentId
                            )
                        }
                        .buttonStyle(.plain)
                        .asterionHoverLift()
                        .accessibilityLabel(bookmark.title)
                        .accessibilityValue(bookmark.subtitle ?? mediaType.title)
                    }
                }
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .hidingScrollIndicators()
    }

    private var signedOutState: some View {
        ContentUnavailableView {
            Label("Sign in to view bookmarks", systemImage: "person.crop.circle.badge.questionmark")
        } description: {
            Text("Your saved \(mediaType.title.lowercased()) follow your Asterion account.")
        } actions: {
            Button("Sign In") { openWindow(id: "authentication") }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "No bookmarks yet"
                    : "No bookmarks found",
                systemImage: "bookmark"
            )
        } description: {
            Text(emptyDescription)
        }
    }

    private var bookmarkDescription: String {
        switch mediaType {
        case .anime: "Anime saved across your Asterion devices."
        case .movie: "Movies and TV shows saved across your Asterion devices."
        case .football: "Matches saved across your Asterion devices."
        }
    }

    private var emptyDescription: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try a different title."
        }
        return mediaType == .anime
            ? "Save an anime from its detail page and it will appear here."
            : "Save a movie or TV show from its detail page and it will appear here."
    }
}

private struct SavedMediaTile: View {
    let bookmark: MediaBookmark
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                MediaCoverView(url: bookmark.imageURL, width: 128, height: 184)

                Image(systemName: "bookmark.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(Color.asterionAccent, in: Circle())
                    .padding(8)
            }
            .padding(4)
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isSelected ? Color.asterionAccent : .clear, lineWidth: 2)
            }

            Text(bookmark.title)
                .font(.asterionDisplay(15, weight: .medium))
                .foregroundStyle(Color.asterionText)
                .lineLimit(2)
                .frame(maxWidth: 136, alignment: .leading)

            Text(bookmark.subtitle ?? bookmark.mediaType.title)
                .font(.caption)
                .foregroundStyle(Color.asterionMuted)
                .lineLimit(1)
                .frame(maxWidth: 136, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}
