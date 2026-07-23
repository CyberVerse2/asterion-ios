import Foundation

struct Chapter: Identifiable, Codable, Hashable {
    let id: String
    let chapterNumber: Int
    let title: String
    let content: String?
    let url: String?

    var plainContent: String {
        (content ?? "")
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case chapterNumber, title, content, url
    }
}
