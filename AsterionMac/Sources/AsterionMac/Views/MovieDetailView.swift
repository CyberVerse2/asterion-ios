import SwiftUI

struct MovieDetailView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: MovieStore

    @State private var selectedSeason: Int?
    @State private var showsFullSynopsis = false

    var body: some View {
        Group {
            if store.isLoadingDetail {
                ProgressView("Opening title…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.detailError {
                ContentUnavailableView {
                    Label("Couldn’t open this title", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await store.retryDetail() } }
                }
            } else if let show = store.show {
                detail(show)
            } else {
                ContentUnavailableView(
                    "Choose a title",
                    systemImage: "film",
                    description: Text("Select a movie or TV show to see its details.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func detail(_ show: MovieShow) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                hero(show)
                watchAction(show)

                if let synopsis = show.description, !synopsis.isEmpty {
                    Divider()
                    detailSection(title: "Synopsis") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(showsFullSynopsis ? synopsis : synopsisPreview(synopsis))
                                .font(.asterionReading(15))
                                .foregroundStyle(Color.asterionReaderText)
                                .lineSpacing(5)
                                .textSelection(.enabled)
                            if synopsisPreview(synopsis) != synopsis {
                                Button(showsFullSynopsis ? "Show less" : "Read full synopsis") {
                                    showsFullSynopsis.toggle()
                                }
                                .buttonStyle(.link)
                                .tint(.asterionAccent)
                            }
                        }
                    }
                }

                if show.isSeries {
                    Divider()
                    detailSection(title: "Episodes", trailing: "\(store.episodes.count) available") {
                        episodeBrowser(show)
                    }
                }

                if !show.actors.isEmpty {
                    Divider()
                    detailSection(title: "Cast") {
                        Text(show.actors.prefix(8).joined(separator: " · "))
                            .font(.callout)
                            .foregroundStyle(Color.asterionMuted)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .hidingScrollIndicators()
        .navigationTitle(show.displayTitle)
        .task(id: show.id) {
            showsFullSynopsis = false
            selectedSeason = availableSeasons.first
        }
    }

    private func hero(_ show: MovieShow) -> some View {
        HStack(alignment: .top, spacing: 20) {
            MediaCoverView(url: show.imageURL, width: 138, height: 198)

            VStack(alignment: .leading, spacing: 10) {
                Text(show.displayTitle)
                    .font(.asterionDisplay(22, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if !show.genres.isEmpty {
                    Text(show.genres.prefix(3).joined(separator: " · "))
                        .font(.asterionDisplay(14, weight: .medium))
                        .foregroundStyle(Color.asterionText)
                        .lineLimit(2)
                }

                VStack(alignment: .leading, spacing: 8) {
                    metadataLine(
                        icon: show.isSeries ? "tv" : "film",
                        value: show.isSeries ? "TV Series" : "Movie"
                    )
                    if let year = show.releaseYear {
                        metadataLine(icon: "calendar", value: year)
                    }
                    if let duration = show.duration, !duration.isEmpty {
                        metadataLine(icon: "clock", value: duration)
                    }
                    if let director = show.director, !director.isEmpty {
                        metadataLine(icon: "person.fill", value: director)
                    }
                    if let rating = show.imdbRating {
                        metadataLine(icon: "star.fill", value: "IMDb \(rating)")
                    }
                }
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func watchAction(_ show: MovieShow) -> some View {
        Button {
            openPlayer(show: show, episode: preferredEpisode)
        } label: {
            Label(watchButtonTitle(show), systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .controlSize(.large)
        .tint(.asterionAccent)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(show.isSeries ? store.episodes.isEmpty : show.streams.isEmpty)
        .help("Open in Asterion Player")
    }

    private func episodeBrowser(_ show: MovieShow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if availableSeasons.count > 1 {
                Picker("Season", selection: seasonBinding) {
                    ForEach(availableSeasons, id: \.self) { season in
                        Text("Season \(season)").tag(season)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if episodesForSelectedSeason.isEmpty {
                ContentUnavailableView("No episodes", systemImage: "film.stack")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(episodesForSelectedSeason) { episode in
                        Button {
                            openPlayer(show: show, episode: episode)
                        } label: {
                            HStack(spacing: 14) {
                                Text(String(episode.number))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Color.asterionMuted)
                                    .frame(width: 30, alignment: .trailing)
                                Text(episode.title)
                                    .font(.asterionDisplay(14, weight: .medium))
                                    .foregroundStyle(Color.asterionText)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption)
                                    .foregroundStyle(Color.asterionMuted)
                            }
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }

    private var availableSeasons: [Int] {
        Array(Set(store.episodes.map(\.season))).sorted(by: >)
    }

    private var seasonBinding: Binding<Int> {
        Binding(
            get: { selectedSeason ?? availableSeasons.first ?? 0 },
            set: { selectedSeason = $0 }
        )
    }

    private var episodesForSelectedSeason: [MovieEpisode] {
        guard let season = selectedSeason ?? availableSeasons.first else { return [] }
        return store.episodes.filter { $0.season == season }
    }

    private var preferredEpisode: MovieEpisode? {
        store.episodes.last
    }

    private func watchButtonTitle(_ show: MovieShow) -> String {
        guard show.isSeries else { return "Watch movie" }
        guard let episode = preferredEpisode else { return "No episodes available" }
        return "Watch S\(episode.season) E\(episode.number)"
    }

    private func openPlayer(show: MovieShow, episode: MovieEpisode?) {
        openWindow(
            value: MoviePlayerRoute(
                slug: show.slug,
                title: show.displayTitle,
                initialEpisodeID: episode?.id
            )
        )
    }

    private func metadataLine(icon: String, value: String) -> some View {
        Label {
            Text(value).lineLimit(1)
        } icon: {
            Image(systemName: icon).frame(width: 16)
        }
        .font(.caption)
        .foregroundStyle(Color.asterionMuted)
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

    private func synopsisPreview(_ synopsis: String) -> String {
        guard synopsis.count > 300 else { return synopsis }
        let prefix = String(synopsis.prefix(300))
        if let boundary = prefix.lastIndex(where: { $0.isWhitespace }) {
            return String(prefix[..<boundary]) + "…"
        }
        return prefix + "…"
    }
}
