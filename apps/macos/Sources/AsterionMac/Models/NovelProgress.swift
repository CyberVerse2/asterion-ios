import Foundation

/// Where a reader is in a whole novel.
///
/// Saved reading progress only records the position inside the current
/// chapter. Combined with the chapter's number and the novel's chapter count
/// it gives the whole-novel fraction, the "Ch. 1929 of 3171" label every
/// novel surface shows, and whether the novel is finished.
struct NovelProgress: Equatable, Sendable {
    /// How far into the last chapter counts as having finished the novel.
    static let finishedChapterPercentage = 95.0

    /// The current chapter's number, when it is known.
    let chapterNumber: Int?
    /// How many chapters the novel has, when it is known.
    let totalChapters: Int?
    /// Position inside the current chapter, 0–100.
    let chapterPercentage: Double

    init(chapterNumber: Int?, totalChapters: Int?, chapterPercentage: Double) {
        self.chapterNumber = chapterNumber.flatMap { $0 > 0 ? $0 : nil }
        self.totalChapters = totalChapters.flatMap { $0 > 0 ? $0 : nil }
        self.chapterPercentage = chapterPercentage.isFinite
            ? min(100, max(0, chapterPercentage))
            : 0
    }

    /// Builds progress from saved reading progress. Reaching the chapter's last
    /// paragraph counts as reading all of it: the reader saves the index of
    /// the paragraph at the top of the page, which never reaches the count.
    init(progress: ReadingProgress, chapterNumber: Int?, totalChapters: Int?) {
        let reachedLastLine = progress.totalLines > 0
            && progress.currentLine >= progress.totalLines - 1
        self.init(
            chapterNumber: chapterNumber,
            totalChapters: totalChapters,
            chapterPercentage: reachedLastLine ? 100 : progress.percentage
        )
    }

    /// The best known chapter count: the loaded chapter list wins because the
    /// catalog's count can lag, then the catalog's text ("3171", "3,171").
    static func totalChapters(loaded: Int?, catalog: String?) -> Int? {
        if let loaded, loaded > 0 { return loaded }
        guard let catalog else { return nil }
        let digits = catalog.filter(\.isASCII).filter(\.isNumber)
        guard let count = Int(digits), count > 0 else { return nil }
        return count
    }

    /// Position inside the current chapter, 0–1.
    var chapterFraction: Double { chapterPercentage / 100 }

    /// The chapter count used for arithmetic. A chapter beyond the reported
    /// count means the count lags, so the chapter itself bounds it.
    private var effectiveTotal: Int? {
        guard let totalChapters else { return nil }
        guard let chapterNumber else { return totalChapters }
        return max(totalChapters, chapterNumber)
    }

    /// How far through the whole novel, 0–1, or nil until the chapter number
    /// and chapter count are both known.
    var fraction: Double? {
        guard let chapterNumber, let total = effectiveTotal else { return nil }
        if isFinished { return 1 }
        return min(1, max(0, (Double(chapterNumber - 1) + chapterFraction) / Double(total)))
    }

    /// Whole-novel percentage, 0–100, rounded for display.
    var displayPercentage: Int? {
        fraction.map { Int(($0 * 100).rounded(.down)) }
    }

    /// "Ch. 1929 of 3171", "Ch. 1929" without a count, or nil without a
    /// chapter. Numbers are never grouped with separators.
    var label: String? {
        guard let chapterNumber else { return nil }
        guard let total = effectiveTotal else { return "Ch. " + String(chapterNumber) }
        return "Ch. " + String(chapterNumber) + " of " + String(total)
    }

    /// "Chapter 1929 of 3171" for VoiceOver and roomier captions.
    var longLabel: String? {
        guard let chapterNumber else { return nil }
        guard let total = effectiveTotal else { return "Chapter " + String(chapterNumber) }
        return "Chapter " + String(chapterNumber) + " of " + String(total)
    }

    /// On the last chapter and at least 95% through it.
    var isFinished: Bool {
        guard let chapterNumber, let total = effectiveTotal else { return false }
        return chapterNumber >= total && chapterPercentage >= Self.finishedChapterPercentage
    }
}
