import SwiftUI

struct AnimeDetailView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: AnimeStore

    @State private var scrollPosition: String?
    @State private var showsFullSynopsis = false

    var body: some View {
        Group {
            if store.isLoadingDetail {
                ProgressView("Opening anime…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.detailError {
                ContentUnavailableView {
                    Label("Couldn’t open this anime", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await store.retryDetail() } }
                }
            } else if let show = store.show {
                detail(show)
            } else {
                ContentUnavailableView(
                    "Choose an anime",
                    systemImage: "play.rectangle.on.rectangle",
                    description: Text("Select a title to see its story and episodes.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func detail(_ show: AnimeShow) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                hero(show)
                    .id("detail-top")

                watchAction(show)
                Divider()

                if let synopsis = show.displayDescription, !synopsis.isEmpty {
                    detailSection(title: "Synopsis") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(showsFullSynopsis ? synopsis : synopsisPreview(synopsis))
                                .font(.asterionReading(15))
                                .foregroundStyle(Color.asterionReaderText)
                                .lineSpacing(5)
                                .textSelection(.enabled)

                            if synopsisPreview(synopsis) != synopsis {
                                Button {
                                    showsFullSynopsis.toggle()
                                } label: {
                                    Label(
                                        showsFullSynopsis ? "Show less" : "Read full synopsis",
                                        systemImage: showsFullSynopsis ? "chevron.up" : "chevron.down"
                                    )
                                    .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.link)
                                .tint(.asterionAccent)
                            }
                        }
                    }

                    Divider()
                }

                detailSection(title: "Episodes", trailing: episodeCountLabel) {
                    episodeList(show)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .hidingScrollIndicators()
        .scrollPosition(id: $scrollPosition, anchor: .top)
        .background(.background)
        .navigationTitle(show.displayTitle)
        .task(id: show.id) {
            showsFullSynopsis = false
            scrollPosition = nil
            await Task.yield()
            scrollPosition = "detail-top"
        }
    }

    private func hero(_ show: AnimeShow) -> some View {
        HStack(alignment: .top, spacing: 20) {
            MediaCoverView(url: show.imageURL, width: 138, height: 198)

            VStack(alignment: .leading, spacing: 10) {
                Text(show.displayTitle)
                    .font(.asterionDisplay(22, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .layoutPriority(1)

                if let byline = byline(for: show) {
                    Text(byline)
                        .font(.asterionDisplay(14, weight: .medium))
                        .foregroundStyle(Color.asterionText)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    let mediaSummary = [show.type, show.status]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                    if !mediaSummary.isEmpty {
                        AnimeMetadataLine(icon: "play.rectangle", value: mediaSummary)
                    }

                    if let season = show.season, !season.isEmpty {
                        AnimeMetadataLine(icon: "calendar", value: season)
                    } else if let dateAired = show.dateAired, !dateAired.isEmpty {
                        AnimeMetadataLine(icon: "calendar", value: dateAired)
                    }

                    if let studio = show.displayStudio, !studio.isEmpty {
                        AnimeMetadataLine(icon: "building.2", value: studio)
                    }

                    AnimeMetadataLine(
                        icon: "film.stack",
                        value: "\(max(show.episodesCount, store.episodes.count)) episodes"
                    )
                }
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func watchAction(_ show: AnimeShow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    guard let episode = preferredEpisode else { return }
                    openPlayer(show: show, episode: episode)
                } label: {
                    Label(watchButtonTitle, systemImage: "play.fill")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 10))
                .controlSize(.large)
                .tint(.asterionAccent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(store.episodes.isEmpty)
                .help("Open in Anime Player")

                mediaBookmarkButton(show)
            }

            if let error = model.mediaBookmarkError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.asterionAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func mediaBookmarkButton(_ show: AnimeShow) -> some View {
        let item = MediaItemDescriptor(
            mediaType: .anime,
            contentID: show.slug,
            title: show.displayTitle,
            subtitle: show.season ?? show.type,
            imageURL: show.imageURL
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
                    .frame(width: 72)
            } else {
                Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                    .frame(width: 72)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isUpdating)
        .help(isSaved ? "Remove from saved anime" : "Save anime to your account")
    }

    @ViewBuilder
    private func episodeList(_ show: AnimeShow) -> some View {
        if store.episodes.isEmpty {
            ContentUnavailableView("No episodes", systemImage: "film.stack")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(store.episodes) { episode in
                    Button {
                        openPlayer(show: show, episode: episode)
                    } label: {
                        HStack(spacing: 14) {
                            Text(String(episode.number))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Color.asterionMuted)
                                .frame(width: 34, alignment: .trailing)

                            Text("Episode \(episode.number)")
                                .font(.asterionDisplay(14, weight: .medium))
                                .foregroundStyle(Color.asterionText)
                                .lineLimit(1)

                            Spacer()

                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(Color.asterionMuted)
                        }
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open episode \(episode.number) in Anime Player")

                    Divider()
                }
            }
        }
    }

    private var preferredEpisode: AnimeEpisode? {
        store.episodes.max { $0.number < $1.number }
    }

    private var watchButtonTitle: String {
        guard let episode = preferredEpisode else { return "No episodes available" }
        return "Watch episode \(episode.number)"
    }

    private var episodeCountLabel: String? {
        store.episodes.isEmpty ? nil : "\(store.episodes.count) episodes"
    }

    private func openPlayer(show: AnimeShow, episode: AnimeEpisode) {
        openWindow(
            value: AnimePlayerRoute(
                slug: show.slug,
                title: show.displayTitle,
                initialEpisodeID: episode.id
            )
        )
    }

    private func byline(for show: AnimeShow) -> String? {
        if let japaneseTitle = show.displayJapaneseTitle, !japaneseTitle.isEmpty {
            return japaneseTitle
        }
        return show.genres.first?
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func synopsisPreview(_ synopsis: String) -> String {
        guard synopsis.count > 280 else { return synopsis }
        let prefix = String(synopsis.prefix(280))
        if let sentenceEnd = prefix.lastIndex(where: { ".!?".contains($0) }) {
            return String(prefix[...sentenceEnd])
        }
        if let wordBoundary = prefix.lastIndex(where: { $0.isWhitespace }) {
            return String(prefix[..<wordBoundary]) + "…"
        }
        return prefix + "…"
    }

    private func detailSection<Content: View>(
        title: String,
        trailing: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.asterionDisplay(20, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.caption)
                        .foregroundStyle(Color.asterionAccent)
                }
            }
            content()
        }
    }
}

private struct AnimeMetadataLine: View {
    let icon: String
    let value: String

    var body: some View {
        Label {
            Text(value)
                .lineLimit(1)
        } icon: {
            Image(systemName: icon)
                .frame(width: 16)
        }
        .font(.caption)
        .foregroundStyle(Color.asterionMuted)
    }
}
