import Foundation

struct Chapter: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let chapterNumber: Int
    let title: String
    let content: String?
    let url: String?

    var displayTitle: String {
        let pattern = "^\\s*(?:chapter\\s+)?\(chapterNumber)\\s*(?:[-:·]\\s*)?(?:\(chapterNumber)\\s*[-:]\\s*)?"
        let cleaned = title
            .replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Chapter \(chapterNumber)" : cleaned
    }

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

struct NovelChapterRange: Identifiable, Equatable, Sendable {
    static let pageSize = 100

    let chapters: [Chapter]

    var id: String {
        guard let first = chapters.first, let last = chapters.last else { return "empty" }
        return "\(first.id)-\(last.id)"
    }

    var label: String {
        guard let first = chapters.first, let last = chapters.last else { return "Chapters" }
        return "\(first.chapterNumber)–\(last.chapterNumber)"
    }

    func contains(chapterID: Chapter.ID?) -> Bool {
        guard let chapterID else { return false }
        return chapters.contains { $0.id == chapterID }
    }

    static func pages(for chapters: [Chapter], pageSize: Int = pageSize) -> [NovelChapterRange] {
        precondition(pageSize > 0)

        let ordered = chapters.sorted {
            if $0.chapterNumber == $1.chapterNumber {
                return $0.id < $1.id
            }
            return $0.chapterNumber < $1.chapterNumber
        }

        return stride(from: 0, to: ordered.count, by: pageSize).map { startIndex in
            let endIndex = min(startIndex + pageSize, ordered.count)
            return NovelChapterRange(chapters: Array(ordered[startIndex..<endIndex]))
        }
    }
}
