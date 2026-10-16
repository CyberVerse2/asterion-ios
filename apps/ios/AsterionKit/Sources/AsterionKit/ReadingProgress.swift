import Foundation

public struct ReadingProgress: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let userId: String
    public let novelId: String
    public let chapterId: String
    public let currentLine: Int
    public let totalLines: Int
    public let percentage: Double
    public let updatedAt: Date?

    public init(
        id: String,
        userId: String,
        novelId: String,
        chapterId: String,
        currentLine: Int,
        totalLines: Int,
        percentage: Double,
        updatedAt: Date?
    ) {
        self.id = id
        self.userId = userId
        self.novelId = novelId
        self.chapterId = chapterId
        self.currentLine = currentLine
        self.totalLines = totalLines
        self.percentage = percentage
        self.updatedAt = updatedAt
    }

    public var progressPercentage: Double { percentage }
    public var lastReadAt: Date? { updatedAt }

    public static func latestByNovel(_ entries: [ReadingProgress]) -> [ReadingProgress] {
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
    public init(progress: ReadingProgress, chapterNumber: Int?, totalChapters: Int?) {
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

/// When Home's Continue shelf must be rebuilt.
public enum HomeContinueReload {
    /// Changes when the API gains or loses its session, or when the newest
    /// reading position for any novel moves to another chapter. Line-by-line
    /// progress inside a chapter does not change it.
    public static func key(isAuthorized: Bool, progress: [ReadingProgress]) -> String {
        let positions = ReadingProgress.latestByNovel(progress)
            .prefix(16)
            .map { "\($0.novelId):\($0.chapterId)" }
            .joined(separator: ",")
        return (isAuthorized ? "auth|" : "guest|") + positions
    }
}

/// Where a novel's "Read" action opens: the saved chapter (resuming at the
/// saved line) or, for a new or finished novel, chapter 1. The app resolves
/// it from synced and local progress.
public struct NovelReadTarget: Sendable {
    public let chapter: Chapter
    public let chapters: [Chapter]
    public let progress: NovelProgress?
    public let resumesSavedPosition: Bool

    public init(chapter: Chapter, chapters: [Chapter], progress: NovelProgress?, resumesSavedPosition: Bool) {
        self.chapter = chapter
        self.chapters = chapters
        self.progress = progress
        self.resumesSavedPosition = resumesSavedPosition
    }

    public var title: String { Self.title(for: progress) }

    /// "Read", "Continue chapter 1929", "Continue reading" or "Read again".
    public static func title(for progress: NovelProgress?) -> String {
        guard let progress else { return "Read" }
        if progress.isFinished { return "Read again" }
        if let chapter = progress.chapterNumber { return "Continue chapter " + String(chapter) }
        return "Continue reading"
    }

    public static func symbol(for progress: NovelProgress?) -> String {
        progress?.isFinished == true ? "book.closed.fill" : "book.fill"
    }
}
