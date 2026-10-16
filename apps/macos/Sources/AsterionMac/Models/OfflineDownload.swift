import Foundation

/// A novel's offline download: the job in progress, or how it last ended, and
/// which chapters are on this Mac.
struct OfflineDownload: Identifiable, Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case downloading
        case completed
        case failed
        /// Stopped by the reader; any chapters already saved stay.
        case cancelled
    }

    let novelID: String
    let novelTitle: String
    /// Chapters of the current job already on this Mac.
    var completedChapters: Int
    /// Chapters the current job covers.
    var totalChapters: Int
    var phase: Phase
    var errorMessage: String?
    var updatedAt: Date
    /// The chapter numbers the job asked for; nil for the whole novel.
    var requestedRange: ClosedRange<Int>? = nil
    /// Every chapter of the novel on this Mac, across downloads.
    var saved = OfflineChapterSet()
    /// Whether the saved chapters were the whole novel at the last download.
    var coversWholeNovel = false

    var id: String { novelID }

    var progress: Double {
        guard totalChapters > 0 else { return 0 }
        return min(max(Double(completedChapters) / Double(totalChapters), 0), 1)
    }

    var isDownloading: Bool { phase == .downloading }

    var hasSavedChapters: Bool { !saved.isEmpty }

    /// Some chapters are offline, but not the whole novel.
    var isPartial: Bool { hasSavedChapters && !coversWholeNovel }
}

/// The chapters of one novel saved on this Mac.
struct OfflineChapterSet: Equatable, Sendable {
    private(set) var ids: Set<String> = []
    private(set) var numbers = IndexSet()

    init() {}

    init(_ chapters: [Chapter]) {
        insert(chapters)
    }

    var count: Int { ids.count }
    var isEmpty: Bool { ids.isEmpty }

    mutating func insert(_ chapters: [Chapter]) {
        for chapter in chapters {
            ids.insert(chapter.id)
            if chapter.chapterNumber >= 0 {
                numbers.insert(chapter.chapterNumber)
            }
        }
    }

    func contains(_ chapterID: String) -> Bool { ids.contains(chapterID) }

    /// How many saved chapters fall within `range`.
    func count(in range: ClosedRange<Int>) -> Int {
        numbers.count(in: range.lowerBound..<(range.upperBound + 1))
    }

    /// "Chapters 1–340" when the saved chapters run without gaps, otherwise
    /// "52 chapters · 1–340". Numbers are never grouped with separators.
    var summary: String {
        guard let first = numbers.first, let last = numbers.last else {
            return count == 1 ? "1 chapter" : String(count) + " chapters"
        }
        if first == last { return "Chapter " + String(first) }
        let span = String(first) + "–" + String(last)
        if numbers.rangeView.count == 1 { return "Chapters " + span }
        return String(count) + " chapters · " + span
    }
}

enum OfflineDownloadError: LocalizedError, Equatable {
    case alreadyInProgress(novelTitle: String)
    case emptyRange

    var errorDescription: String? {
        switch self {
        case .alreadyInProgress(let novelTitle):
            "\(novelTitle) is already downloading."
        case .emptyRange:
            "There are no chapters in that range."
        }
    }
}

/// Which chapters a novel download covers.
enum NovelDownloadRange {
    enum Preset: String, CaseIterable, Identifiable, Sendable {
        case next10
        case next50
        case next100
        case rest
        case all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .next10: "Next 10"
            case .next50: "Next 50"
            case .next100: "Next 100"
            case .rest: "To the end"
            case .all: "All"
            }
        }

        fileprivate var length: Int? {
            switch self {
            case .next10: 10
            case .next50: 50
            case .next100: 100
            case .rest, .all: nil
            }
        }
    }

    /// The chapters a preset covers. "Next" presets and "To the end" start
    /// at the chapter being read, which may be only part read, or at chapter
    /// 1 before someone starts; "All" is the whole novel.
    static func range(
        for preset: Preset,
        currentChapter: Int?,
        totalChapters: Int
    ) -> ClosedRange<Int>? {
        guard totalChapters > 0 else { return nil }
        if preset == .all { return 1...totalChapters }
        let start = min(max(currentChapter ?? 1, 1), totalChapters)
        guard let length = preset.length else { return start...totalChapters }
        return start...min(totalChapters, start + length - 1)
    }

    /// A typed range, in either order, clamped to the novel's chapters.
    static func custom(from: Int, to: Int, totalChapters: Int) -> ClosedRange<Int>? {
        guard totalChapters > 0 else { return nil }
        let lower = max(1, min(from, to))
        let upper = min(totalChapters, max(from, to))
        guard lower <= upper else { return nil }
        return lower...upper
    }

    /// The chapters to fetch: those in `range` (every chapter when nil) not
    /// already saved, in reading order.
    static func chaptersToFetch(
        from chapters: [Chapter],
        in range: ClosedRange<Int>?,
        excluding saved: OfflineChapterSet
    ) -> [Chapter] {
        chapters
            .filter { range?.contains($0.chapterNumber) ?? true }
            .filter { !saved.contains($0.id) }
            .sorted { $0.chapterNumber < $1.chapterNumber }
    }

    /// The chapters a download covers, saved or not.
    static func chapters(_ chapters: [Chapter], in range: ClosedRange<Int>?) -> [Chapter] {
        guard let range else { return chapters }
        return chapters.filter { range.contains($0.chapterNumber) }
    }
}
