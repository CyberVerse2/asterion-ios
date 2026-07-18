import Foundation

enum AppMode: String, CaseIterable, Codable, Hashable, Sendable {
    case novels
    case anime

    var title: String {
        switch self {
        case .novels: "Novels"
        case .anime: "Anime"
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
    case trending
    case topRated
    case recentlyAdded
    case genres

    var title: String {
        switch self {
        case .discover: "Discover"
        case .popular: "Popular"
        case .trending: "Trending"
        case .topRated: "Top Rated"
        case .recentlyAdded: "Recently Added"
        case .genres: "Genres"
        }
    }

    var systemImage: String {
        switch self {
        case .discover: "sparkles.tv"
        case .popular: "flame"
        case .trending: "chart.line.uptrend.xyaxis"
        case .topRated: "star"
        case .recentlyAdded: "clock.badge.plus"
        case .genres: "square.grid.2x2"
        }
    }

    var catalogTitle: String {
        switch self {
        case .discover: "Recently updated"
        case .popular: "Most popular"
        case .trending: "Trending now"
        case .topRated: "Top rated"
        case .recentlyAdded: "Recently added"
        case .genres: "Browse by genre"
        }
    }

    var catalogDescription: String {
        switch self {
        case .discover: "Fresh episodes, ready when you are."
        case .popular: "The shows drawing the biggest audience."
        case .trending: "What anime fans are watching right now."
        case .topRated: "The highest-rated stories in the catalog."
        case .recentlyAdded: "New arrivals across series, films, and specials."
        case .genres: "Choose a genre to shape your next watch."
        }
    }
}

struct ReaderRoute: Codable, Hashable, Sendable {
    let novelID: String
    let chapterID: String
}

struct AnimePlayerRoute: Codable, Hashable, Sendable {
    let showID: String
    let slug: String
    let title: String
    let initialEpisodeID: String?
}
