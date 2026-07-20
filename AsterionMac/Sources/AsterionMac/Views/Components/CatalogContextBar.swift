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
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
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
                        animeFilterMenus

                    case .movies:
                        sectionButton("Discover", value: MovieSection.discover, selection: $movieSection)
                        sectionButton("Movies", value: MovieSection.movies, selection: $movieSection)
                        sectionButton("TV Shows", value: MovieSection.tvShows, selection: $movieSection)
                        sectionButton("Popular", value: MovieSection.popular, selection: $movieSection)
                        movieGenreMenu

                    case .football:
                        sectionButton("Live", value: FootballSection.live, selection: $footballSection)
                        sectionButton("Schedule", value: FootballSection.schedule, selection: $footballSection)
                        sectionButton("Popular", value: FootballSection.popular, selection: $footballSection)

                    default:
                        EmptyView()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .padding(.top, 10)
            }
        }
        .scrollIndicators(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var animeFilterMenus: some View {
        Menu {
            Button("Browse Genres") { animeSection = .genres }
            if !animeStore.genres.isEmpty {
                Divider()
                ForEach(animeStore.genres, id: \.self) { genre in
                    Button(genre) {
                        animeSection = .genres
                        Task { await animeStore.selectGenre(genre, query: "") }
                    }
                }
            }
        } label: {
            Label("Genres", systemImage: "square.grid.2x2")
        }
        .controlSize(.small)
        .help("Filter anime by genre")

        Menu {
            ForEach(AnimeStore.types, id: \.self) { type in
                Button(type.replacingOccurrences(of: "-", with: " ").capitalized) {
                    animeSection = .types
                    Task { await animeStore.selectType(type, query: "") }
                }
            }
        } label: {
            Label("Types", systemImage: "rectangle.stack")
        }
        .controlSize(.small)
        .help("Filter anime by type")
    }

    private var movieGenreMenu: some View {
        Menu {
            Button("Browse Genres") { movieSection = .genres }
            if !movieStore.genres.isEmpty {
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
        }
        .controlSize(.small)
        .help("Filter movies and TV shows by genre")
    }

    private func sectionButton<Value: Hashable>(
        _ title: String,
        value: Value,
        selection: Binding<Value>
    ) -> some View {
        Button {
            selection.wrappedValue = value
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selection.wrappedValue == value ? .primary : .secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .modifier(
                    ContextSelectionGlass(
                        isSelected: selection.wrappedValue == value,
                        namespace: selectionNamespace
                    )
                )
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityAddTraits(selection.wrappedValue == value ? .isSelected : [])
    }
}

private struct ContextSelectionGlass: ViewModifier {
    let isSelected: Bool
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            content
                .glassEffect(.regular.interactive(), in: Capsule())
                .glassEffectID("catalog-selection", in: namespace)
                .glassEffectTransition(.matchedGeometry)
        } else {
            content
        }
    }
}
