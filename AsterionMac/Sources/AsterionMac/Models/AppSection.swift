import Foundation

enum AppDestination: String, CaseIterable, Codable, Hashable, Sendable {
    case home
    case novels
    case anime
    case movies
    case football
    case continueActivity
    case bookmarks
    case downloads
    case history
    case account

    var title: String {
        switch self {
        case .home: "Home"
        case .novels: "Novels"
        case .anime: "Anime"
        case .movies: "Movies"
        case .football: "Football"
        case .continueActivity: "Continue"
        case .bookmarks: "Bookmarks"
        case .downloads: "Downloads"
        case .history: "History"
        case .account: "Account"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .novels: "books.vertical"
        case .anime: "sparkles.tv"
        case .movies: "film.stack"
        case .football: "soccerball"
        case .continueActivity: "play.circle"
        case .bookmarks: "bookmark"
        case .downloads: "arrow.down.circle"
        case .history: "clock.arrow.circlepath"
        case .account: "person.crop.circle"
        }
    }
}

enum MovieSection: String, CaseIterable, Codable, Hashable, Sendable {
    case discover
    case movies
    case tvShows
    case popular
    case genres

    var title: String {
        switch self {
        case .discover: "Discover"
        case .movies: "Movies"
        case .tvShows: "TV Shows"
        case .popular: "Popular"
        case .genres: "Genres"
        }
    }

    var systemImage: String {
        switch self {
        case .discover: "sparkles.tv"
        case .movies: "film"
        case .tvShows: "tv"
        case .popular: "flame"
        case .genres: "square.grid.2x2"
        }
    }

    var catalogTitle: String {
        switch self {
        case .discover: "Trending now"
        case .movies: "All movies"
        case .tvShows: "TV shows"
        case .popular: "Most popular"
        case .genres: "Browse by genre"
        }
    }

    var catalogDescription: String {
        switch self {
        case .discover: "Films drawing attention right now."
        case .movies: "Explore the full movie catalog."
        case .tvShows: "Series organized by season and episode."
        case .popular: "The movies audiences return to most."
        case .genres: "Choose a shelf for your next watch."
        }
    }
}

enum AppSection: String, CaseIterable, Codable, Hashable, Sendable {
    case discover
    case rankings

    var title: String {
        switch self {
        case .discover: "Discover"
        case .rankings: "Rankings"
        }
    }

    var systemImage: String {
        switch self {
        case .discover: "sparkles"
        case .rankings: "crown"
        }
    }
}

enum AnimeSection: String, CaseIterable, Codable, Hashable, Sendable {
    case discover
    case genres
    case types
    case updated
    case added
    case popular
    case upcoming
    case ongoing
    case completed
    case schedule

    var title: String {
        switch self {
        case .discover: "Discover"
        case .genres: "Genres"
        case .types: "Types"
        case .updated: "Updated"
        case .added: "Added"
        case .popular: "Popular"
        case .upcoming: "Upcoming"
        case .ongoing: "Ongoing"
        case .completed: "Completed"
        case .schedule: "Schedule"
        }
    }

    var systemImage: String {
        switch self {
        case .discover: "sparkles.tv"
        case .genres: "square.grid.2x2"
        case .types: "rectangle.stack"
        case .updated: "clock.arrow.circlepath"
        case .added: "plus.rectangle.on.rectangle"
        case .popular: "flame"
        case .upcoming: "calendar.badge.clock"
        case .ongoing: "dot.radiowaves.left.and.right"
        case .completed: "checkmark.circle"
        case .schedule: "calendar"
        }
    }

    var catalogTitle: String {
        switch self {
        case .discover: "Recently updated"
        case .genres: "Browse by genre"
        case .types: "Browse by type"
        case .updated: "Recently updated"
        case .added: "Recently added"
        case .popular: "Most popular"
        case .upcoming: "Upcoming anime"
        case .ongoing: "Currently airing"
        case .completed: "Completed anime"
        case .schedule: "Release schedule"
        }
    }

    var catalogDescription: String {
        switch self {
        case .discover: "Fresh episodes, ready when you are."
        case .genres: "Choose a genre to shape your next watch."
        case .types: "Choose TV, movies, OVA, ONA, specials, or music."
        case .updated: "Anime with the latest episode updates."
        case .added: "New arrivals across series, films, and specials."
        case .popular: "The shows drawing the biggest audience."
        case .upcoming: "Announced titles that have not started airing yet."
        case .ongoing: "Anime currently releasing new episodes."
        case .completed: "Finished series and films ready to watch through."
        case .schedule: "This week's release times in your timezone."
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
