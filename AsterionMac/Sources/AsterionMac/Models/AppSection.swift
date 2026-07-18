import Foundation

enum AppMode: String, CaseIterable, Codable, Hashable, Sendable {
    case novels
    case anime
    case movies
    case football

    var title: String {
        switch self {
        case .novels: "Novels"
        case .anime: "Anime"
        case .movies: "Movies"
        case .football: "Football"
        }
    }
}

enum MovieSection: String, CaseIterable, Codable, Hashable, Sendable {
    case discover
    case movies
    case tvShows
    case popular
    case genres
    case bookmarks

    var title: String {
        switch self {
        case .discover: "Discover"
        case .movies: "Movies"
        case .tvShows: "TV Shows"
        case .popular: "Popular"
        case .genres: "Genres"
        case .bookmarks: "Bookmarks"
        }
    }

    var systemImage: String {
        switch self {
        case .discover: "sparkles.tv"
        case .movies: "film"
        case .tvShows: "tv"
        case .popular: "flame"
        case .genres: "square.grid.2x2"
        case .bookmarks: "bookmark.fill"
        }
    }

    var catalogTitle: String {
        switch self {
        case .discover: "Trending now"
        case .movies: "All movies"
        case .tvShows: "TV shows"
        case .popular: "Most popular"
        case .genres: "Browse by genre"
        case .bookmarks: "Your bookmarks"
        }
    }

    var catalogDescription: String {
        switch self {
        case .discover: "Films drawing attention right now."
        case .movies: "Explore the full movie catalog."
        case .tvShows: "Series organized by season and episode."
        case .popular: "The movies audiences return to most."
        case .genres: "Choose a shelf for your next watch."
        case .bookmarks: "Movies and TV shows saved to your account."
        }
    }
}

enum AppSection: String, CaseIterable, Codable, Hashable, Sendable {
    case discover
    case rankings
    case library
    case account

    var title: String {
        switch self {
        case .discover: "Discover"
        case .rankings: "Rankings"
        case .library: "Library"
        case .account: "Account"
        }
    }

    var systemImage: String {
        switch self {
        case .discover: "sparkles"
        case .rankings: "crown"
        case .library: "books.vertical"
        case .account: "person.crop.circle"
        }
    }

    var showsNovelCatalog: Bool {
        switch self {
        case .discover, .rankings, .library:
            true
        case .account:
            false
        }
    }
}

enum AnimeSection: String, CaseIterable, Codable, Hashable, Sendable {
    case discover
    case popular
    case newReleases
    case genres
    case bookmarks

    var title: String {
        switch self {
        case .discover: "Discover"
        case .popular: "Popular"
        case .newReleases: "New Releases"
        case .genres: "Genres"
        case .bookmarks: "Bookmarks"
        }
    }

    var systemImage: String {
        switch self {
        case .discover: "sparkles.tv"
        case .popular: "flame"
        case .newReleases: "clock.badge.plus"
        case .genres: "square.grid.2x2"
        case .bookmarks: "bookmark.fill"
        }
    }

    var catalogTitle: String {
        switch self {
        case .discover: "Recently updated"
        case .popular: "Most popular"
        case .newReleases: "New releases"
        case .genres: "Browse by genre"
        case .bookmarks: "Your bookmarks"
        }
    }

    var catalogDescription: String {
        switch self {
        case .discover: "Fresh episodes, ready when you are."
        case .popular: "The shows drawing the biggest audience."
        case .newReleases: "New arrivals across series, films, and specials."
        case .genres: "Choose a genre to shape your next watch."
        case .bookmarks: "Anime saved to your account."
        }
    }
}

struct ReaderRoute: Codable, Hashable, Sendable {
    let novelID: String
    let chapterID: String
}

struct AnimePlayerRoute: Codable, Hashable, Sendable {
    let slug: String
    let title: String
    let initialEpisodeID: String?
}
