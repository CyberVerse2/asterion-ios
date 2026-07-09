import Foundation

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
}

struct ReaderRoute: Codable, Hashable, Sendable {
    let novelID: String
    let chapterID: String
}
