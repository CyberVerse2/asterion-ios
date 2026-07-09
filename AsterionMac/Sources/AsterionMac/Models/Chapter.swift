import Foundation

struct Chapter: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let chapterNumber: Int
    let title: String
    let content: String?
    let url: String?

    var plainContent: String {
        (content ?? "")
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var paragraphs: [String] {
        plainContent
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case chapterNumber, title, content, url
    }
}
