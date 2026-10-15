import Foundation

struct Novel: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let author: String?
    let rank: String?
    let totalChapters: String?
    let views: String?
    let bookmarks: String?
    let status: String?
    let genres: [String]?
    let summary: String?
    let imageUrl: String?
    let rating: Double?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case title, author, rank, totalChapters, views, bookmarks
        case status, genres, summary, imageUrl, rating
    }

    var rankPosition: Int {
        Self.rankPosition(from: rank)
    }

    static func ranked(_ novels: [Novel]) -> [Novel] {
        novels.sorted { lhs, rhs in
            if lhs.rankPosition != rhs.rankPosition {
                return lhs.rankPosition < rhs.rankPosition
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    static func rankPosition(from raw: String?) -> Int {
        Int(raw?.filter(\.isNumber) ?? "") ?? .max
    }
}
