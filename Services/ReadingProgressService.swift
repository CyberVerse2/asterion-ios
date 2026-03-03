import Foundation
import Combine

@MainActor
final class ReadingProgressService: ObservableObject {
    @Published var currentProgress: ReadingProgress?

    func updateProgress(chapterId: String, currentLine: Int, totalLines: Int) {
        let percentage = totalLines > 0 ? (Double(currentLine) / Double(totalLines)) * 100 : 0
        currentProgress = ReadingProgress(
            id: UUID().uuidString,
            userId: "local",
            chapterId: chapterId,
            currentLine: currentLine,
            totalLines: totalLines,
            progressPercentage: percentage,
            lastReadAt: Date()
        )
    }
}
