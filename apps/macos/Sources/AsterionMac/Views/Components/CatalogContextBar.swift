import SwiftUI

struct CatalogContextBar: View {
    @ObservedObject var animeStore: AnimeStore
    @ObservedObject var movieStore: MovieStore
    let destination: AppDestination
    @Binding var novelSection: AppSection
    @Binding var animeSection: AnimeSection
    @Binding var movieSection: MovieSection
    @Binding var footballSection: FootballSection

    @Namespace private var selectionNamespace

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    switch destination {
                    case .novels:
                        sectionButton("Discover", value: AppSection.discover, selection: $novelSection)
                        sectionButton("Rankings", value: AppSection.rankings, selection: $novelSection)

                    case .anime:
                        sectionButton("Discover", value: AnimeSection.discover, selection: $animeSection)
                        sectionButton("Updated", value: AnimeSection.updated, selection: $animeSection)
                        sectionButton("Added", value: AnimeSection.added, selection: $animeSection)
                        sectionButton("Popular", value: AnimeSection.popular, selection: $animeSection)
                        sectionButton("Airing", value: AnimeSection.ongoing, selection: $animeSection)
                        sectionButton("Upcoming", value: AnimeSection.upcoming, selection: $animeSection)
                        sectionButton("Completed", value: AnimeSection.completed, selection: $animeSection)
                        sectionButton("Schedule", value: AnimeSection.schedule, selection: $animeSection)

                    case .movies:
                        sectionButton("Discover", value: MovieSection.discover, selection: $movieSection)
                        sectionButton("Movies", value: MovieSection.movies, selection: $movieSection)
                        sectionButton("TV Shows", value: MovieSection.tvShows, selection: $movieSection)
                        sectionButton("Popular", value: MovieSection.popular, selection: $movieSection)

                    case .football:
                        sectionButton("Live", value: FootballSection.live, selection: $footballSection)
                        sectionButton("Schedule", value: FootballSection.schedule, selection: $footballSection)
                        sectionButton("Popular", value: FootballSection.popular, selection: $footballSection)

                    default:
                        EmptyView()
                    }
                }
                .padding(3)
                .glassEffect(.regular, in: Capsule())

                switch destination {
                case .anime:
                    animeFilterMenus
                case .movies:
                    movieGenreMenu
                default:
                    EmptyView()
                }
            }
            .padding(.horizontal, AsterionLayout.pageInset)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.never, axes: .horizontal)
        .frame(height: AsterionLayout.sectionBarHeight)
        .animation(.spring(duration: 0.32, bounce: 0.12), value: selectionKey)
    }

    private var selectionKey: String {
        switch destination {
        case .novels: novelSection.rawValue
        case .anime: animeSection.rawValue
        case .movies: movieSection.rawValue
        case .football: footballSection.rawValue
        default: ""
        }
    }

    @ViewBuilder
    private var animeFilterMenus: some View {
        Menu {
            Button("Browse Genres") { animeSection = .genres }
            if animeStore.isLoadingGenres, animeStore.genres.isEmpty {
                Divider()
                Button("Loading Genres…") {}
                    .disabled(true)
            } else if let error = animeStore.genreError, animeStore.genres.isEmpty {
                Divider()
                Button("Try Loading Genres Again") {
                    Task { await animeStore.loadGenresIfNeeded() }
                }
                .help(error)
            } else if !animeStore.genres.isEmpty {
                Divider()
                ForEach(animeStore.genres, id: \.self) { genre in
                    Button(displayName(forGenre: genre)) {
                        animeSection = .genres
                        Task { await animeStore.selectGenre(genre, query: "") }
                    }
                }
            }
        } label: {
            Label("Genres", systemImage: "square.grid.2x2")
                .font(.system(size: 12.5, weight: .semibold))
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .fixedSize()
        .help("Filter anime by genre")
        .task {
            await animeStore.loadGenresIfNeeded()
        }

        Menu {
            ForEach(AnimeStore.types, id: \.self) { type in
                Button(type.replacingOccurrences(of: "-", with: " ").capitalized) {
                    animeSection = .types
                    Task { await animeStore.selectType(type, query: "") }
                }
            }
        } label: {
            Label("Types", systemImage: "rectangle.stack")
                .font(.system(size: 12.5, weight: .semibold))
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .fixedSize()
        .help("Filter anime by type")
    }

    private var movieGenreMenu: some View {
        Menu {
            Button("Browse Genres") { movieSection = .genres }
            if movieStore.isLoadingGenres, movieStore.genres.isEmpty {
                Divider()
                Button("Loading Genres…") {}
                    .disabled(true)
            } else if let error = movieStore.genreError, movieStore.genres.isEmpty {
                Divider()
                Button("Try Loading Genres Again") {
                    Task { await movieStore.loadGenresIfNeeded() }
                }
                .help(error)
            } else if !movieStore.genres.isEmpty {
                Divider()
                ForEach(movieStore.genres) { genre in
                    Button(genre.title) {
                        movieSection = .genres
                        Task { await movieStore.selectGenre(genre, query: "") }
                    }
                }
            }
        } label: {
            Label("Genres", systemImage: "square.grid.2x2")
                .font(.system(size: 12.5, weight: .semibold))
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .fixedSize()
        .help("Filter movies and TV shows by genre")
        .task {
            await movieStore.loadGenresIfNeeded()
        }
    }

    private func displayName(forGenre genre: String) -> String {
        genre.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func sectionButton<Value: Hashable>(
        _ title: String,
        value: Value,
        selection: Binding<Value>
    ) -> some View {
        let isSelected = selection.wrappedValue == value
        return Button {
            selection.wrappedValue = value
        } label: {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isSelected ? Color.asterionMediaCanvas : Color.asterionText.opacity(0.78))
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.asterionText)
                            .matchedGeometryEffect(id: "catalog-selection", in: selectionNamespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
