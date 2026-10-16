import Foundation

struct ReadingProgress: Identifiable, Codable, Hashable {
    let id: String
    let userId: String
    let novelId: String
    let chapterId: String
    let currentLine: Int
    let totalLines: Int
    let percentage: Double
    let updatedAt: Date?

    var progressPercentage: Double { percentage }
    var lastReadAt: Date? { updatedAt }

    static func latestByNovel(_ entries: [ReadingProgress]) -> [ReadingProgress] {
        var latest: [String: ReadingProgress] = [:]
        for entry in entries {
            if let existing = latest[entry.novelId],
               (existing.updatedAt ?? .distantPast) > (entry.updatedAt ?? .distantPast) {
                continue
            }
            latest[entry.novelId] = entry
        }
        return latest.values.sorted {
            if $0.updatedAt == $1.updatedAt { return $0.novelId < $1.novelId }
            return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }
    }
}

extension NovelProgress {
    /// Builds progress from saved reading progress.
    init(progress: ReadingProgress, chapterNumber: Int?, totalChapters: Int?) {
        self.init(
            chapterNumber: chapterNumber,
            totalChapters: totalChapters,
            chapterPercentage: Self.chapterPercentage(
                currentLine: progress.currentLine,
                totalLines: progress.totalLines,
                saved: progress.percentage
            )
        )
    }
}
