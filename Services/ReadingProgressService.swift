import Foundation
import Combine

@MainActor
final class ReadingProgressService: ObservableObject {
    @Published var currentProgress: ReadingProgress?
    @Published private(set) var pendingSyncCount = 0

    private weak var apiClient: APIClient?
    private let queueKey = "asterion.pending.progress.queue"

    private struct PendingProgressPayload: Codable, Hashable {
        let novelId: String
        let chapterId: String
        let currentLine: Int
        let totalLines: Int
        let percentage: Double
        let queuedAt: Date
    }

    init() {
        pendingSyncCount = loadQueue().count
    }

    func configure(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func refreshRemoteProgress(novelId: String) async {
        guard let apiClient else { return }
        do {
            currentProgress = try await apiClient.fetchReadingProgress(novelId: novelId)
        } catch {
            // Keep existing local state if remote load fails.
        }
    }

    func updateProgress(novelId: String, chapterId: String, currentLine: Int, totalLines: Int) {
        let percentage = totalLines > 0 ? (Double(currentLine) / Double(totalLines)) * 100 : 0
        currentProgress = ReadingProgress(
            id: UUID().uuidString,
            userId: "local",
            novelId: novelId,
            chapterId: chapterId,
            currentLine: currentLine,
            totalLines: totalLines,
            percentage: percentage,
            updatedAt: Date()
        )

        let payload = PendingProgressPayload(
            novelId: novelId,
            chapterId: chapterId,
            currentLine: currentLine,
            totalLines: totalLines,
            percentage: percentage,
            queuedAt: Date()
        )
        enqueue(payload)
        Task { await flushQueue() }
    }

    func flushQueue() async {
        guard let apiClient else { return }
        var queue = loadQueue()
        guard !queue.isEmpty else { return }

        while let item = queue.first {
            do {
                currentProgress = try await apiClient.upsertReadingProgress(
                    novelId: item.novelId,
                    chapterId: item.chapterId,
                    currentLine: item.currentLine,
                    totalLines: item.totalLines,
                    percentage: item.percentage
                )
                queue.removeFirst()
                saveQueue(queue)
            } catch {
                break
            }
        }
    }

    private func enqueue(_ payload: PendingProgressPayload) {
        var queue = loadQueue()
        queue.removeAll { $0.novelId == payload.novelId }
        queue.append(payload)
        saveQueue(queue)
    }

    private func loadQueue() -> [PendingProgressPayload] {
        guard let data = UserDefaults.standard.data(forKey: queueKey) else {
            return []
        }
        return (try? JSONDecoder().decode([PendingProgressPayload].self, from: data)) ?? []
    }

    private func saveQueue(_ queue: [PendingProgressPayload]) {
        pendingSyncCount = queue.count
        if let data = try? JSONEncoder().encode(queue) {
            UserDefaults.standard.set(data, forKey: queueKey)
        } else {
            UserDefaults.standard.removeObject(forKey: queueKey)
        }
    }
}
