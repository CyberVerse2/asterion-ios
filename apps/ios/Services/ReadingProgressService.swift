import Foundation
import Combine

@MainActor
protocol ReadingProgressAPI: AnyObject {
    func fetchReadingProgress(novelId: String) async throws -> ReadingProgress?
    func upsertReadingProgress(novelId: String, chapterId: String, currentLine: Int,
                              totalLines: Int, percentage: Double?) async throws -> ReadingProgress
}

extension APIClient: ReadingProgressAPI {}

@MainActor
final class ReadingProgressService: ObservableObject {
    @Published var currentProgress: ReadingProgress?
    @Published private(set) var pendingSyncCount = 0
    @Published private(set) var localProgress: [ReadingProgress] = []

    private weak var apiClient: (any ReadingProgressAPI)?
    private let defaults: UserDefaults
    private let queueKey = "asterion.pending.progress.queue"
    private let activityKey = "asterion.local.reading.progress"
    private let syncedKey = "asterion.synced.reading.progress"
    private var syncedProgress: [ReadingProgress] = []
    private var isFlushing = false

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[ReadingProgressSync] \(message)")
        #endif
    }

    private struct PendingProgressPayload: Codable, Hashable {
        let novelId: String
        let chapterId: String
        let currentLine: Int
        let totalLines: Int
        let percentage: Double
        let queuedAt: Date
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: activityKey) {
            localProgress = (try? JSONDecoder().decode([ReadingProgress].self, from: data)) ?? []
        }
        if let data = defaults.data(forKey: syncedKey) {
            syncedProgress = (try? JSONDecoder().decode([ReadingProgress].self, from: data)) ?? []
        }
        localProgress = mergedProgress(with: queuedProgressList())
        if let data = try? JSONEncoder().encode(localProgress) {
            defaults.set(data, forKey: activityKey)
        }
        pendingSyncCount = loadQueue().count
    }

    func configure(apiClient: any ReadingProgressAPI) {
        self.apiClient = apiClient
        debugLog("Configured API client.")
    }

    func refreshRemoteProgress(novelId: String) async {
        guard let apiClient else { return }
        do {
            let remote = try await apiClient.fetchReadingProgress(novelId: novelId)
            currentProgress = mergedProgress(with: remote.map { [$0] } ?? [])
                .first { $0.novelId == novelId }
            debugLog("Remote progress refreshed for novelId=\(novelId)")
        } catch {
            if let local = localProgress.first(where: { $0.novelId == novelId }) {
                currentProgress = local
                debugLog("Using queued local progress for novelId=\(novelId) after remote refresh failure.")
            }
            debugLog("Remote progress refresh failed for novelId=\(novelId): \(error.localizedDescription)")
        }
    }

    func updateProgress(novelId: String, chapterId: String, currentLine: Int, totalLines: Int, syncToCloud: Bool = true) {
        let percentage = totalLines > 0 ? (Double(currentLine) / Double(totalLines)) * 100 : 0
        let now = Date()
        let progress = ReadingProgress(
            id: UUID().uuidString,
            userId: "local",
            novelId: novelId,
            chapterId: chapterId,
            currentLine: currentLine,
            totalLines: totalLines,
            percentage: percentage,
            updatedAt: now
        )
        currentProgress = progress
        localProgress = ReadingProgress.latestByNovel(localProgress + [progress])
        if let data = try? JSONEncoder().encode(localProgress) {
            defaults.set(data, forKey: activityKey)
        }

        guard syncToCloud else { return }
        let payload = PendingProgressPayload(
            novelId: novelId,
            chapterId: chapterId,
            currentLine: currentLine,
            totalLines: totalLines,
            percentage: percentage,
            queuedAt: now
        )
        enqueue(payload)
        debugLog("Queued progress novelId=\(novelId) chapterId=\(chapterId) line=\(currentLine)/\(totalLines)")
        Task { await flushQueue() }
    }

    func flushQueue() async {
        guard let apiClient, !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }
        debugLog("Starting queue flush. pending=\(loadQueue().count)")

        while let item = loadQueue().first {
            do {
                let response = try await apiClient.upsertReadingProgress(
                    novelId: item.novelId,
                    chapterId: item.chapterId,
                    currentLine: item.currentLine,
                    totalLines: item.totalLines,
                    percentage: item.percentage
                )
                syncedProgress.removeAll { $0.novelId == response.novelId }
                syncedProgress.append(response)
                if let data = try? JSONEncoder().encode(syncedProgress) {
                    defaults.set(data, forKey: syncedKey)
                }
                // Reading can enqueue a newer position while the request is in flight.
                // Remove only the payload that was actually acknowledged.
                var queue = loadQueue()
                queue.removeAll { $0 == item }
                saveQueue(queue)
                debugLog("Synced queued progress novelId=\(item.novelId) chapterId=\(item.chapterId). remaining=\(queue.count)")
            } catch {
                debugLog("Queue flush paused after sync failure: \(error.localizedDescription)")
                break
            }
        }
    }

    func mergedProgress(with remote: [ReadingProgress]) -> [ReadingProgress] {
        let normalized = ReadingProgress.latestByNovel(remote).map { entry in
            // A server acknowledgment records sync time. Keep the actual reading
            // time when this is the unchanged response to this device's upload.
            if syncedProgress.contains(entry),
               let local = localProgress.first(where: { $0.novelId == entry.novelId }) {
                return local
            }
            return entry
        }
        return ReadingProgress.latestByNovel(normalized + localProgress)
    }

    func lastReadAt(for novelId: String, remote: Date?) -> Date? {
        let local = localProgress.first { $0.novelId == novelId }?.updatedAt
        let remoteDate = syncedProgress.contains { $0.novelId == novelId && $0.updatedAt == remote }
            && local != nil ? local : remote
        let snapshot = ContinueReadingStore.loadSnapshot()
        let snapshotDate = snapshot?.novelId == novelId ? snapshot?.updatedAt : nil
        return [remoteDate, local, snapshotDate].compactMap { $0 }.max()
    }

    private func enqueue(_ payload: PendingProgressPayload) {
        var queue = loadQueue()
        queue.removeAll { $0.novelId == payload.novelId }
        queue.append(payload)
        saveQueue(queue)
    }

    func queuedProgress(for novelId: String) -> ReadingProgress? {
        guard let payload = loadQueue().last(where: { $0.novelId == novelId }) else {
            return nil
        }
        return ReadingProgress(
            id: "queued-\(novelId)-\(payload.chapterId)",
            userId: "local",
            novelId: payload.novelId,
            chapterId: payload.chapterId,
            currentLine: payload.currentLine,
            totalLines: payload.totalLines,
            percentage: payload.percentage,
            updatedAt: payload.queuedAt
        )
    }

    func queuedProgressList() -> [ReadingProgress] {
        loadQueue()
            .sorted { $0.queuedAt > $1.queuedAt }
            .map { payload in
                ReadingProgress(
                    id: "queued-\(payload.novelId)-\(payload.chapterId)",
                    userId: "local",
                    novelId: payload.novelId,
                    chapterId: payload.chapterId,
                    currentLine: payload.currentLine,
                    totalLines: payload.totalLines,
                    percentage: payload.percentage,
                    updatedAt: payload.queuedAt
                )
            }
    }

    private func loadQueue() -> [PendingProgressPayload] {
        guard let data = defaults.data(forKey: queueKey) else {
            return []
        }
        return (try? JSONDecoder().decode([PendingProgressPayload].self, from: data)) ?? []
    }

    private func saveQueue(_ queue: [PendingProgressPayload]) {
        pendingSyncCount = queue.count
        if let data = try? JSONEncoder().encode(queue) {
            defaults.set(data, forKey: queueKey)
        } else {
            defaults.removeObject(forKey: queueKey)
        }
    }
}
