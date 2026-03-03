import Foundation

struct ReadingProgress: Identifiable, Codable, Hashable {
    let id: String
    let userId: String
    let chapterId: String
    let currentLine: Int
    let totalLines: Int
    let progressPercentage: Double
    let lastReadAt: Date?
}
