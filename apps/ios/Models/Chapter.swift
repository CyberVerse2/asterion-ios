import Foundation

struct Chapter: Identifiable, Codable, Hashable {
    let id: String
    let chapterNumber: Int
    let title: String
    let content: String?
    let url: String?

    /// Title with a leading "Chapter 12" / "Ch. 12" prefix removed.
    /// The number already lives in `chapterNumber`, so the name should not repeat it.
    var displayTitle: String {
        Self.strippedChapterPrefix(from: title)
    }

    var labeledTitle: String {
        if chapterNumber > 0 {
            return displayTitle.isEmpty
                ? "Chapter \(chapterNumber)"
                : "Chapter \(chapterNumber): \(displayTitle)"
        }
        return displayTitle.isEmpty ? title : displayTitle
    }

    var plainContent: String {
        (content ?? "")
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func strippedChapterPrefix(from title: String) -> String {
        let pattern = #"^(?:chapter|ch)\.?\s*\d+\s*[:.\-–—]?\s*"#
        guard let match = title.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return title
        }
        return String(title[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case chapterNumber, title, content, url
    }
}
