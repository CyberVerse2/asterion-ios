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
}
