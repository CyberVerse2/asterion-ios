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

    /// The reader's paragraph list. Paragraph indices are shared with the iOS
    /// reader (Handoff `line` and synced `currentLine`), so this must split,
    /// trim and filter exactly like iOS `ReaderView.paragraphs(for:)`: same
    /// HTML flattening, collapsed whitespace, no empty lines, and the same
    /// metadata/promo/heading filter. Entities are decoded only afterwards,
    /// per paragraph, so decoding can never add or remove a paragraph.
    var paragraphs: [String] {
        let flattened = (content ?? "")
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredTitle = title.lowercased()
        let loweredHeading = Self.strippedChapterPrefix(from: title).lowercased()
        return flattened
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }
            .filter { !$0.isEmpty }
            .filter {
                !Self.isReaderMetadataLine($0, loweredTitle: loweredTitle, loweredHeading: loweredHeading)
            }
            .map(Self.decodingEntities)
    }

    private static func decodingEntities(_ line: String) -> String {
        line
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// iOS `Chapter.strippedChapterPrefix(from:)`; the iOS reader drops a line
    /// equal to this heading. (macOS `displayTitle` differs, so it can't be used.)
    private static func strippedChapterPrefix(from title: String) -> String {
        let pattern = #"^(?:chapter|ch)\.?\s*\d+\s*[:.\-–—]?\s*"#
        guard let match = title.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return title
        }
        return String(title[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Mirror of iOS `ReaderView.shouldFilterMetadataLine`. Keep in step.
    private static func isReaderMetadataLine(
        _ line: String,
        loweredTitle: String,
        loweredHeading: String
    ) -> Bool {
        let lowered = line.lowercased()
        let compact = lowered.replacingOccurrences(of: " ", with: "")

        let promoKeywords = [
            "discord", "patreon", "ko-fi", "kofi", "buymeacoffee", "buy me a coffee",
            "telegram", "facebook", "twitter", "x.com", "instagram",
        ]
        let sourcePlugs = [
            "http://", "https://", "www.", ".com", ".net", ".org",
            "read at ", "read on ", "published on ",
        ]
        let creditPrefixes = [
            "translator:", "editor:", "edited by", "proofreader:", "raw provider:",
            "source:", "author note:", "a/n:", "note:", "tl:", "t/l:", "edit:", "credits:",
        ]

        if creditPrefixes.contains(where: { lowered.hasPrefix($0) }) { return true }
        if promoKeywords.contains(where: { lowered.contains($0) })
            || sourcePlugs.contains(where: { lowered.contains($0) }) {
            return true
        }
        if compact == "atlasstudios" || compact.contains("atlasstudioseditor") { return true }
        // The reader renders its own chapter heading.
        if lowered == loweredTitle || lowered == loweredHeading { return true }
        if lowered.range(of: #"^chapter\s*\d+(\s*[:\-].*)?$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case chapterNumber, title, content, url
    }
}

struct ChapterPage: Equatable, Sendable {
    let chapters: [Chapter]
    let total: Int
    let limit: Int
    let offset: Int

    var pageIndex: Int { limit > 0 ? offset / limit : 0 }
    var pageCount: Int { total == 0 ? 0 : Int(ceil(Double(total) / Double(limit))) }
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
