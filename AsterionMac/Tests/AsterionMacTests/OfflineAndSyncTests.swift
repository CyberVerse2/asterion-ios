import Foundation
import Testing
@testable import AsterionMac

@Suite(.serialized)
struct OfflineAndSyncTests {
    @Test func offlineLibraryUsesSafeSplitStorageAndDirectChapterLookup() async throws {
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: testDirectory) }

        let novelID = "../unsafe/novel"
        let chapterID = "../../unsafe/chapter"
        let novel = Novel(
            id: novelID,
            title: "Safely Stored",
            author: "Asterion",
            rank: nil,
            totalChapters: "1",
            views: nil,
            bookmarks: nil,
            status: nil,
            genres: nil,
            summary: nil,
            imageURL: nil,
            rating: nil
        )
        let chapter = Chapter(
            id: chapterID,
            chapterNumber: 1,
            title: "One",
            content: "<p>Stored separately.</p>",
            url: nil
        )

        let store = OfflineLibraryStore(directory: testDirectory)
        try await store.save(novel: novel, chapters: [chapter])

        let novelStorageKey = OfflineLibraryStore.storageKey(for: novelID)
        let chapterStorageKey = OfflineLibraryStore.storageKey(for: chapterID)
        let libraryDirectory = testDirectory
            .appendingPathComponent("Asterion", isDirectory: true)
            .appendingPathComponent("OfflineLibrary", isDirectory: true)
        let novelDirectory = libraryDirectory
            .appendingPathComponent(novelStorageKey, isDirectory: true)
        let chapterURL = novelDirectory
            .appendingPathComponent("chapters", isDirectory: true)
            .appendingPathComponent(chapterStorageKey, conformingTo: .json)

        #expect(novelStorageKey.count == 64)
        #expect(chapterStorageKey.count == 64)
        #expect(FileManager.default.fileExists(atPath: chapterURL.path))
        #expect(!chapterURL.path.contains(chapterID))
        #expect(try await store.downloadedNovelIDs() == [novelID])
        #expect(try await store.chapters(for: novelID)?.first?.content == nil)
        #expect(try await store.chapter(id: chapterID)?.paragraphs == ["Stored separately."])

        try await store.remove(novelID: novelID)

        #expect(try await store.downloadedNovelIDs().isEmpty)
        #expect(try await store.chapter(id: chapterID) == nil)
        #expect(!FileManager.default.fileExists(atPath: novelDirectory.path))
    }

    @Test func progressUploadsAreSerializedAndPendingUpdatesAreCoalesced() async throws {
        let probe = ProgressUploadProbe()
        let queue = ReadingProgressUploadQueue { request in
            await probe.upload(request)
        }

        let first = Task {
            try await queue.submit(Self.request(line: 1))
        }
        await probe.waitUntilStarted(line: 1)

        let second = Task {
            try await queue.submit(Self.request(line: 2))
        }
        try await Task.sleep(for: .milliseconds(20))
        let third = Task {
            try await queue.submit(Self.request(line: 3))
        }
        try await Task.sleep(for: .milliseconds(20))

        await probe.release(line: 1)
        _ = try await first.value

        do {
            _ = try await second.value
            Issue.record("Expected the pending second upload to be replaced by the newer update.")
        } catch let error as ReadingProgressUploadQueueError {
            #expect(error == .superseded)
        } catch {
            Issue.record("Unexpected coalescing error: \(error)")
        }

        await probe.waitUntilStarted(line: 3)
        await probe.release(line: 3)
        _ = try await third.value

        let result = await probe.result()
        #expect(result.startedLines == [1, 3])
        #expect(result.maximumActiveUploads == 1)
    }

    private static func request(line: Int) -> ReadingProgressUploadQueue.Request {
        ReadingProgressUploadQueue.Request(
            ownerID: "account-1",
            novelID: "novel-1",
            chapterID: "chapter-1",
            currentLine: line,
            totalLines: 100
        )
    }
}

private actor ProgressUploadProbe {
    struct Result: Sendable {
        let startedLines: [Int]
        let maximumActiveUploads: Int
    }

    private var startedLines: [Int] = []
    private var activeUploads = 0
    private var maximumActiveUploads = 0
    private var releaseContinuationByLine: [Int: CheckedContinuation<Void, Never>] = [:]

    func upload(_ request: ReadingProgressUploadQueue.Request) async -> ReadingProgress {
        startedLines.append(request.currentLine)
        activeUploads += 1
        maximumActiveUploads = max(maximumActiveUploads, activeUploads)

        await withCheckedContinuation { continuation in
            releaseContinuationByLine[request.currentLine] = continuation
        }

        activeUploads -= 1
        return ReadingProgress(
            id: "progress-\(request.currentLine)",
            userId: request.ownerID,
            novelId: request.novelID,
            chapterId: request.chapterID,
            currentLine: request.currentLine,
            totalLines: request.totalLines,
            percentage: Double(request.currentLine),
            updatedAt: Date(timeIntervalSince1970: Double(request.currentLine))
        )
    }

    func waitUntilStarted(line: Int) async {
        while !startedLines.contains(line) {
            await Task.yield()
        }
    }

    func release(line: Int) {
        releaseContinuationByLine.removeValue(forKey: line)?.resume()
    }

    func result() -> Result {
        Result(
            startedLines: startedLines,
            maximumActiveUploads: maximumActiveUploads
        )
    }
}
