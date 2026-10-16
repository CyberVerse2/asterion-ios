import Foundation

/// Where a reader is in a whole novel.
///
/// Saved reading progress only records the position inside the current
/// chapter. Combined with the chapter's number and the novel's chapter count
/// it gives the whole-novel fraction, the "Ch. 1929 of 3171" label every
/// novel surface shows, and whether the novel is finished.
public struct NovelProgress: Equatable, Sendable {
    /// How far into the last chapter counts as having finished the novel.
    public static let finishedChapterPercentage = 95.0

    /// The current chapter's number, when it is known.
    public let chapterNumber: Int?
    /// How many chapters the novel has, when it is known.
    public let totalChapters: Int?
    /// Position inside the current chapter, 0–100.
    public let chapterPercentage: Double

    public init(chapterNumber: Int?, totalChapters: Int?, chapterPercentage: Double) {
        self.chapterNumber = chapterNumber.flatMap { $0 > 0 ? $0 : nil }
        self.totalChapters = totalChapters.flatMap { $0 > 0 ? $0 : nil }
        self.chapterPercentage = chapterPercentage.isFinite
            ? min(100, max(0, chapterPercentage))
            : 0
    }

    /// The best known chapter count: a loaded count wins because the
    /// catalog's can lag, then the catalog's text ("3171", "3,171").
    public static func totalChapters(loaded: Int? = nil, catalog: String?) -> Int? {
        if let loaded, loaded > 0 { return loaded }
        guard let catalog else { return nil }
        let digits = catalog.filter(\.isASCII).filter(\.isNumber)
        guard let count = Int(digits), count > 0 else { return nil }
        return count
    }

    /// The in-chapter percentage for a saved line. Reaching the chapter's
    /// last paragraph counts as reading all of it: the reader saves the
    /// paragraph at the top of the page, whose index never reaches the count.
    public static func chapterPercentage(currentLine: Int, totalLines: Int, saved: Double? = nil) -> Double {
        if totalLines > 1, currentLine >= totalLines - 1 { return 100 }
        if let saved { return saved }
        return totalLines > 0 ? Double(currentLine) / Double(totalLines) * 100 : 0
    }

    /// Position inside the current chapter, 0–1.
    public var chapterFraction: Double { chapterPercentage / 100 }

    /// The chapter count used for arithmetic. A chapter beyond the reported
    /// count means the count lags, so the chapter itself bounds it.
    private var effectiveTotal: Int? {
        guard let totalChapters else { return nil }
        guard let chapterNumber else { return totalChapters }
        return max(totalChapters, chapterNumber)
    }

    /// Whether the whole-novel position is known (chapter and count).
    public var knowsWholeNovel: Bool { chapterNumber != nil && effectiveTotal != nil }

    /// How far through the whole novel, 0–1. Until the chapter number and the
    /// chapter count are both known it falls back to the in-chapter position.
    public var fraction: Double {
        guard let chapterNumber, let total = effectiveTotal else { return chapterFraction }
        if isFinished { return 1 }
        return min(1, max(0, (Double(chapterNumber - 1) + chapterFraction) / Double(total)))
    }

    /// `fraction` as a whole percentage, rounded down so an unfinished novel
    /// never reads 100%.
    public var displayPercentage: Int {
        isFinished ? 100 : min(99, Int((fraction * 100).rounded(.down)))
    }

    /// "Ch. 1929 of 3171", "Ch. 1929" without a count, or nil without a
    /// chapter. Numbers are never grouped with separators.
    public var label: String? {
        guard let chapterNumber else { return nil }
        guard let total = effectiveTotal else { return "Ch. " + String(chapterNumber) }
        return "Ch. " + String(chapterNumber) + " of " + String(total)
    }

    /// "Chapter 1929 of 3171" for VoiceOver and roomier captions.
    public var longLabel: String? {
        guard let chapterNumber else { return nil }
        guard let total = effectiveTotal else { return "Chapter " + String(chapterNumber) }
        return "Chapter " + String(chapterNumber) + " of " + String(total)
    }

    /// On the last chapter and at least 95% through it.
    public var isFinished: Bool {
        guard let chapterNumber, let total = effectiveTotal else { return false }
        return chapterNumber >= total && chapterPercentage >= Self.finishedChapterPercentage
    }
}

public struct ContinueReadingSnapshot: Codable, Hashable, Sendable {
    public let novelId: String
    public let novelTitle: String
    public let chapterId: String
    public let chapterTitle: String
    public let chapterNumber: Int
    /// Whole-novel progress, 0–1. Snapshots written before `chapterProgress`
    /// existed stored the in-chapter position here instead.
    public let progress: Double
    /// Position inside the current chapter, 0–1.
    public let chapterProgress: Double?
    /// The novel's chapter count when the snapshot was written.
    public let totalChapters: Int?
    public let updatedAt: Date
    /// Remote cover, used to fetch `coverImageData` for the widgets.
    public let coverURL: String?
    /// Small downsampled JPEG (< 60 KB). Widgets cannot load remote images
    /// reliably, so the cover rides along with the snapshot.
    public let coverImageData: Data?

    public init(
        novelId: String,
        novelTitle: String,
        chapterId: String,
        chapterTitle: String,
        chapterNumber: Int,
        progress: Double,
        chapterProgress: Double? = nil,
        totalChapters: Int? = nil,
        updatedAt: Date,
        coverURL: String? = nil,
        coverImageData: Data? = nil
    ) {
        self.novelId = novelId
        self.novelTitle = novelTitle
        self.chapterId = chapterId
        self.chapterTitle = chapterTitle
        self.chapterNumber = chapterNumber
        self.progress = progress
        self.chapterProgress = chapterProgress
        self.totalChapters = totalChapters
        self.updatedAt = updatedAt
        self.coverURL = coverURL
        self.coverImageData = coverImageData
    }

    private enum CodingKeys: String, CodingKey {
        case novelId, novelTitle, chapterId, chapterTitle, chapterNumber, progress, updatedAt
        case chapterProgress, totalChapters
        case coverURL, coverImageData
    }

    /// Snapshots stored before covers existed still decode.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        novelId = try values.decode(String.self, forKey: .novelId)
        novelTitle = try values.decode(String.self, forKey: .novelTitle)
        chapterId = try values.decode(String.self, forKey: .chapterId)
        chapterTitle = try values.decode(String.self, forKey: .chapterTitle)
        chapterNumber = try values.decodeIfPresent(Int.self, forKey: .chapterNumber) ?? 0
        progress = try values.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        chapterProgress = try values.decodeIfPresent(Double.self, forKey: .chapterProgress)
        totalChapters = try values.decodeIfPresent(Int.self, forKey: .totalChapters)
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        coverURL = try values.decodeIfPresent(String.self, forKey: .coverURL)
        coverImageData = try values.decodeIfPresent(Data.self, forKey: .coverImageData)
    }

    public func with(coverImageData data: Data?) -> ContinueReadingSnapshot {
        ContinueReadingSnapshot(
            novelId: novelId,
            novelTitle: novelTitle,
            chapterId: chapterId,
            chapterTitle: chapterTitle,
            chapterNumber: chapterNumber,
            progress: progress,
            chapterProgress: chapterProgress,
            totalChapters: totalChapters,
            updatedAt: updatedAt,
            coverURL: coverURL,
            coverImageData: data
        )
    }

    /// Position inside the current chapter, 0–1, for snapshots old and new.
    public var inChapterFraction: Double { chapterProgress ?? progress }

    /// The snapshot's place in the whole novel. Snapshots from before the
    /// chapter count was recorded fall back to the in-chapter position.
    public var novelProgress: NovelProgress {
        NovelProgress(
            chapterNumber: chapterNumber,
            totalChapters: totalChapters,
            chapterPercentage: inChapterFraction * 100
        )
    }
}
