import Foundation

struct Novel: Identifiable, Codable, Hashable, Sendable {
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
    let imageURL: String?
    let rating: Double?

    var numericRank: Int {
        Int(rank?.filter(\.isNumber) ?? "") ?? .max
    }

    var authorDisplayName: String {
        var cleaned = author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let titleRange = cleaned.range(of: "title=\"") {
            let remainder = cleaned[titleRange.upperBound...]
            if let closingQuote = remainder.firstIndex(of: "\"") {
                cleaned = String(remainder[..<closingQuote])
            }
        }
        if let editorRange = cleaned.range(of: "Editor:", options: .caseInsensitive) {
            cleaned = String(cleaned[..<editorRange.lowerBound])
        }
        cleaned = cleaned
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&gt;", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned == "Latest Release：" ? "Unknown author" : cleaned
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case title, author, rank, totalChapters, views, bookmarks, status, genres, summary, rating
        case imageURL = "imageUrl"
    }
}
