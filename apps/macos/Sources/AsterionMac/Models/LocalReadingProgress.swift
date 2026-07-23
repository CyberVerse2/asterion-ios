import Foundation

struct LocalReadingProgress: Codable, Equatable, Sendable {
    let ownerID: String
    let novelID: String
    let chapterID: String
    let currentLine: Int
    let totalLines: Int
    let updatedAt: Date
    let revision: String
    let needsSync: Bool

    var percentage: Double {
        guard totalLines > 0 else { return 0 }
        return min(max(Double(currentLine) / Double(totalLines) * 100, 0), 100)
    }

    var readingProgress: ReadingProgress {
        ReadingProgress(
            id: "local:\(ownerID):\(novelID)",
            userId: ownerID,
            novelId: novelID,
            chapterId: chapterID,
            currentLine: currentLine,
            totalLines: totalLines,
            percentage: percentage,
            updatedAt: updatedAt
        )
    }

    func shouldUpload(over server: ReadingProgress?) -> Bool {
        guard needsSync else { return false }
        guard let server else { return true }
        return updatedAt > (server.updatedAt ?? .distantPast)
    }

    static func pending(
        ownerID: String,
        novelID: String,
        chapterID: String,
        currentLine: Int,
        totalLines: Int,
        now: Date = Date()
    ) -> LocalReadingProgress {
        LocalReadingProgress(
            ownerID: ownerID,
            novelID: novelID,
            chapterID: chapterID,
            currentLine: currentLine,
            totalLines: totalLines,
            updatedAt: now,
            revision: UUID().uuidString,
            needsSync: true
        )
    }

    static func synced(
        ownerID: String,
        server: ReadingProgress
    ) -> LocalReadingProgress {
        LocalReadingProgress(
            ownerID: ownerID,
            novelID: server.novelId,
            chapterID: server.chapterId,
            currentLine: server.currentLine,
            totalLines: server.totalLines,
            updatedAt: server.updatedAt ?? Date(),
            revision: UUID().uuidString,
            needsSync: false
        )
    }
}
