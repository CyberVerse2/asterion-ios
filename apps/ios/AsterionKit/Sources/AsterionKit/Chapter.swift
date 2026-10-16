import Foundation

public struct Chapter: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let chapterNumber: Int
    public let title: String
    public let content: String?
    public let url: String?

    public init(id: String, chapterNumber: Int, title: String, content: String?, url: String?) {
        self.id = id
        self.chapterNumber = chapterNumber
        self.title = title
        self.content = content
        self.url = url
    }

    /// Title with a leading "Chapter 12" / "Ch. 12" prefix removed.
    /// The number already lives in `chapterNumber`, so the name should not repeat it.
    public var displayTitle: String {
        Self.strippedChapterPrefix(from: title)
    }

    public var labeledTitle: String {
        if chapterNumber > 0 {
            return displayTitle.isEmpty
                ? "Chapter \(chapterNumber)"
                : "Chapter \(chapterNumber): \(displayTitle)"
        }
        return displayTitle.isEmpty ? title : displayTitle
    }

    public var plainContent: String {
        (content ?? "")
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func strippedChapterPrefix(from title: String) -> String {
        let pattern = #"^(?:chapter|ch)\.?\s*\d+\s*[:.\-–—]?\s*"#
        guard let match = title.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return title
        }
        return String(title[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when `candidate` is the chapter straight after (or before) `current`.
    /// Unnumbered chapters can't be checked, so their list order is trusted.
    public static func isAdjacent(_ candidate: Chapter, to current: Chapter, direction: Int) -> Bool {
        guard candidate.chapterNumber > 0, current.chapterNumber > 0 else { return true }
        return candidate.chapterNumber == current.chapterNumber + direction
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case chapterNumber, title, content, url
    }
}

/// Read state for chapter lists.
public enum ChapterReadState {
    /// A chapter counts as read when it comes before the chapter being read,
    /// or when the whole novel is finished.
    public static func isRead(chapterNumber: Int, readingChapterNumber: Int?, novelFinished: Bool = false) -> Bool {
        guard chapterNumber > 0 else { return false }
        if novelFinished { return true }
        guard let readingChapterNumber, readingChapterNumber > 0 else { return false }
        return chapterNumber < readingChapterNumber
    }
}

/// Where a short chapter preview starts so `number` sits in its middle.
public enum ChapterPreviewWindow {
    public static func offset(around number: Int, size: Int, total: Int?) -> Int {
        let centered = max(0, number - 1 - size / 2)
        guard let total, total > 0 else { return centered }
        return max(0, min(centered, total - size))
    }
}
