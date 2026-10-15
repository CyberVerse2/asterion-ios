import Foundation
import Testing
@testable import Asterion

@MainActor
struct ReadingRecencyTests {
    @Test
    func latestActivitySurvivesAnOfflineRelaunch() {
        let suite = "ReadingRecencyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = ReadingProgressService(defaults: defaults)
        service.updateProgress(novelId: "first", chapterId: "one", currentLine: 1, totalLines: 10)
        service.updateProgress(novelId: "latest", chapterId: "two", currentLine: 2, totalLines: 10)

        let restored = ReadingProgressService(defaults: defaults)
        #expect(restored.localProgress.map(\.novelId) == ["latest", "first"])
        #expect(restored.pendingSyncCount == 2)
    }

    @Test
    func syncingAnOlderPositionPreservesNewReadingAndActualRecency() async {
        let suite = "ReadingRecencyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = ReadingProgressService(defaults: defaults)
        let api = RecencyAPI()
        service.configure(apiClient: api)
        api.duringFirstUpload = {
            service.updateProgress(novelId: "first", chapterId: "new-chapter", currentLine: 8, totalLines: 10)
            service.updateProgress(novelId: "latest", chapterId: "two", currentLine: 3, totalLines: 10)
            await service.flushQueue()
        }
        service.updateProgress(novelId: "first", chapterId: "old-chapter", currentLine: 1, totalLines: 10)
        await service.flushQueue()

        #expect(api.uploads.map(\.chapterId) == ["old-chapter", "new-chapter", "two"])
        #expect(service.pendingSyncCount == 0)
        #expect(service.currentProgress?.novelId == "latest")
        #expect(service.localProgress.first(where: { $0.novelId == "first" })?.currentLine == 8)
        let merged = service.mergedProgress(with: api.uploads)
        #expect(merged.map(\.novelId) == ["latest", "first"])
        #expect(merged.first?.updatedAt == service.localProgress.first?.updatedAt)

        let restored = ReadingProgressService(defaults: defaults)
        #expect(restored.pendingSyncCount == 0)
        #expect(restored.mergedProgress(with: api.uploads).map(\.novelId) == ["latest", "first"])
    }

    @Test
    func newerReadingFromAnotherDeviceWinsOverLocalActivity() async {
        let suite = "ReadingRecencyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = ReadingProgressService(defaults: defaults)
        service.updateProgress(novelId: "novel", chapterId: "local-chapter", currentLine: 1, totalLines: 10)
        let remote = ReadingProgress(id: "remote", userId: "user", novelId: "novel",
                                     chapterId: "remote-chapter", currentLine: 8, totalLines: 10,
                                     percentage: 80, updatedAt: Date(timeIntervalSinceNow: 120))
        let api = RecencyAPI()
        api.remote = remote
        service.configure(apiClient: api)
        await service.refreshRemoteProgress(novelId: "novel")

        #expect(service.currentProgress?.chapterId == "remote-chapter")
        #expect(service.mergedProgress(with: [remote]).first == remote)
    }

    @Test
    func mergingProgressKeepsOnlyTheNewestRecordPerNovel() {
        let old = ReadingProgress(id: "old", userId: "user", novelId: "novel", chapterId: "one",
                                  currentLine: 1, totalLines: 10, percentage: 10,
                                  updatedAt: Date(timeIntervalSince1970: 100))
        let new = ReadingProgress(id: "new", userId: "user", novelId: "novel", chapterId: "two",
                                  currentLine: 2, totalLines: 10, percentage: 20,
                                  updatedAt: Date(timeIntervalSince1970: 200))
        #expect(ReadingProgress.latestByNovel([new, old]) == [new])
    }
}

@MainActor
private final class RecencyAPI: ReadingProgressAPI {
    var uploads: [ReadingProgress] = []
    var duringFirstUpload: (() async -> Void)?
    var remote: ReadingProgress?

    func fetchReadingProgress(novelId: String) async throws -> ReadingProgress? { remote }

    func upsertReadingProgress(novelId: String, chapterId: String, currentLine: Int,
                              totalLines: Int, percentage: Double?) async throws -> ReadingProgress {
        let response = ReadingProgress(id: "server-\(novelId)", userId: "user", novelId: novelId,
                                       chapterId: chapterId, currentLine: currentLine, totalLines: totalLines,
                                       percentage: percentage ?? 0, updatedAt: Date(timeIntervalSinceNow: 60))
        uploads.append(response)
        if uploads.count == 1 { await duringFirstUpload?() }
        return response
    }
}
