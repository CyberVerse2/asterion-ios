import Foundation
import Testing
@testable import AsterionMac

@Suite(.serialized)
struct ReadingHistorySyncTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: What needs uploading

    @Test func chaptersReadHereUploadNewestFirstButSyncedRowsDoNot() {
        var entries = ReadingHistory.recording(Self.visit("c1", percentage: 40, at: Self.now), into: [])
        entries = ReadingHistory.recording(Self.visit("c2", percentage: 10, at: Self.now + 60), into: entries)
        entries = ReadingHistory.merging(remote: [Self.row("c9", at: Self.now + 30, progress: 100)], into: entries)

        let pending = ReadingHistory.pendingUploads(in: entries)
        #expect(pending.map(\.chapterId) == ["c2", "c1"])
        #expect(pending[1] == ReadingHistory.Upload(
            novelId: "n",
            chapterId: "c1",
            chapterNumber: 1,
            chapterTitle: "Chapter c1",
            readAt: Self.now,
            progress: 40
        ))
        #expect(ReadingHistory.pendingUploads(in: entries, limit: 1).map(\.chapterId) == ["c2"])
    }

    @Test func uploadedChaptersClearButReadingThemAgainQueuesThemAgain() {
        var entries = ReadingHistory.recording(Self.visit("c1", percentage: 40, at: Self.now), into: [])
        let sent = ReadingHistory.pendingUploads(in: entries)
        // Read further while the batch was in flight.
        entries = ReadingHistory.recording(Self.visit("c1", percentage: 70, at: Self.now + 10), into: entries)
        entries = ReadingHistory.markingUploaded(sent, in: entries)
        #expect(ReadingHistory.pendingUploads(in: entries).map(\.readAt) == [Self.now + 10])

        entries = ReadingHistory.markingUploaded(ReadingHistory.pendingUploads(in: entries), in: entries)
        #expect(ReadingHistory.pendingUploads(in: entries).isEmpty)

        // More progress in the same chapter, with no newer read time, still uploads.
        entries = ReadingHistory.recording(Self.visit("c1", percentage: 90, at: Self.now), into: entries)
        #expect(ReadingHistory.pendingUploads(in: entries).map(\.progress) == [90])
    }

    @Test func accountRowsFillDetailsAndOnlyLocalProgressAheadOfThemUploads() throws {
        var entries = ReadingHistory.recording(Self.visit("c1", percentage: 80, at: Self.now, number: nil), into: [])
        entries = ReadingHistory.merging(remote: [
            Self.row("c1", at: Self.now + 100, firstReadAt: Self.now - 500, progress: 30, number: 12, title: "Twelve"),
            Self.row("c2", at: Self.now + 50, progress: 55, number: 13, title: "Thirteen"),
        ], into: entries)

        let first = try #require(entries.first { $0.chapterID == "c1" })
        #expect(first.lastReadAt == Self.now + 100)
        #expect(first.firstReadAt == Self.now - 500)
        #expect(first.chapterNumber == 12)
        #expect(first.chapterTitle == "Chapter c1")
        #expect(first.percentage == 80)
        let second = try #require(entries.first { $0.chapterID == "c2" })
        #expect(second.chapterNumber == 13)
        #expect(second.chapterTitle == "Thirteen")
        #expect(second.percentage == 55)

        // The account already has c1's newer read, but not this Mac's 80%.
        #expect(ReadingHistory.pendingUploads(in: entries).map { "\($0.chapterId):\($0.progress)" } == ["c1:80.0"])
    }

    @Test func rowsTheAccountWouldRejectNeverUpload() {
        let entries = [
            Self.entry(novelID: "", chapterID: "c1"),
            Self.entry(novelID: "n", chapterID: " c2"),
            Self.entry(novelID: "n", chapterID: String(repeating: "x", count: 501)),
            Self.entry(novelID: "n", chapterID: "old", at: Date(timeIntervalSince1970: 0)),
            Self.entry(novelID: "n", chapterID: "ok"),
        ]
        #expect(ReadingHistory.pendingUploads(in: entries).map(\.chapterId) == ["ok"])
    }

    @Test func historyRecordedBeforeSyncShippedDecodesAndUploadsOnce() throws {
        let legacy = """
        {"chapterID":"c1","chapterNumber":3,"firstReadAt":1800000000000,"lastReadAt":1800000000000,\
        "novelID":"n","percentage":50}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let entry = try decoder.decode(ReadingHistoryEntry.self, from: Data(legacy.utf8))
        #expect(entry.syncedReadAt == nil)
        #expect(ReadingHistory.needsUpload(entry))
        let marked = ReadingHistory.markingUploaded(ReadingHistory.pendingUploads(in: [entry]), in: [entry])
        #expect(!ReadingHistory.needsUpload(marked[0]))
    }

    @Test func uploadsEncodeTheContractTheAPIValidates() throws {
        let upload = ReadingHistory.Upload(
            novelId: "n",
            chapterId: "c",
            chapterNumber: nil,
            chapterTitle: nil,
            readAt: Date(timeIntervalSince1970: 1_800_000_000.25),
            progress: 42.5
        )
        let object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(upload)) as? [String: Any]
        )
        #expect(object["readAt"] as? String == "2027-01-15T08:00:00.250Z")
        #expect(object["progress"] as? Double == 42.5)
        #expect(object["chapterNumber"] == nil)
        #expect(object["chapterTitle"] == nil)
        #expect(Set(object.keys) == ["novelId", "chapterId", "readAt", "progress"])
    }

    @Test func retriesBackOffToFiveMinutes() {
        #expect(ReadingHistory.uploadRetryDelay(afterFailures: 0) == .seconds(5))
        #expect(ReadingHistory.uploadRetryDelay(afterFailures: 1) == .seconds(10))
        #expect(ReadingHistory.uploadRetryDelay(afterFailures: 3) == .seconds(40))
        #expect(ReadingHistory.uploadRetryDelay(afterFailures: 50) == .seconds(300))
    }

    // MARK: Upload queue

    @Test func theQueueSendsEverythingInBatchesAndMarksItSynced() async throws {
        let (store, cleanup) = Self.store()
        defer { cleanup() }
        for index in 0..<450 {
            try await store.record(ownerID: "user", visit: Self.visit("c\(index)", percentage: 10, at: Self.now + Double(index)))
        }
        try await store.record(ownerID: "other", visit: Self.visit("theirs", percentage: 10, at: Self.now))
        let recorder = UploadRecorder()
        let queue = ReadingHistoryUploadQueue(store: store) { ownerID, batch in
            await recorder.record(ownerID, batch)
        }

        #expect(await queue.flush(ownerID: "user") == .finished(uploaded: 450))
        let calls = await recorder.calls
        #expect(calls.map(\.batch.count) == [200, 200, 50])
        #expect(calls.allSatisfy { $0.ownerID == "user" })
        #expect(Set(calls.flatMap { $0.batch.map(\.chapterId) }).count == 450)
        #expect(try await store.pendingUploads(ownerID: "user").isEmpty)
        // Another owner's history is never sent with this one's.
        #expect(try await store.pendingUploads(ownerID: "other").map(\.chapterId) == ["theirs"])

        // Nothing new: nothing sent.
        #expect(await queue.flush(ownerID: "user") == .finished(uploaded: 0))
        #expect(await recorder.calls.count == 3)
    }

    @Test func offlineAndServerFailuresKeepRowsForTheNextFlush() async throws {
        let (store, cleanup) = Self.store()
        defer { cleanup() }
        try await store.record(ownerID: "user", visit: Self.visit("c1", percentage: 10, at: Self.now))
        let failures = FailureScript([
            URLError(.notConnectedToInternet),
            APIError.http(statusCode: 503, message: ""),
            APIError.http(statusCode: 404, message: "Route POST:/me/history not found"),
            APIError.unauthorized,
        ])
        let recorder = UploadRecorder()
        let queue = ReadingHistoryUploadQueue(store: store) { ownerID, batch in
            if let failure = await failures.next() { throw failure }
            await recorder.record(ownerID, batch)
        }

        #expect(await queue.flush(ownerID: "user") == .retryLater)
        #expect(await queue.flush(ownerID: "user") == .retryLater)
        // An API that hasn't shipped the endpoint yet keeps the rows too.
        #expect(await queue.flush(ownerID: "user") == .retryLater)
        #expect(await queue.flush(ownerID: "user") == .unauthorized)
        #expect(try await store.pendingUploads(ownerID: "user").map(\.chapterId) == ["c1"])

        #expect(await queue.flush(ownerID: "user") == .finished(uploaded: 1))
        #expect(await recorder.calls.map { $0.batch.map(\.chapterId) } == [["c1"]])
    }

    @Test func aBatchTheAccountRejectsIsDroppedInsteadOfResentForever() async throws {
        let (store, cleanup) = Self.store()
        defer { cleanup() }
        try await store.record(ownerID: "user", visit: Self.visit("c1", percentage: 10, at: Self.now))
        let attempts = UploadRecorder()
        let queue = ReadingHistoryUploadQueue(store: store) { ownerID, batch in
            await attempts.record(ownerID, batch)
            throw APIError.http(statusCode: 400, message: "Invalid history payload.")
        }

        #expect(await queue.flush(ownerID: "user") == .finished(uploaded: 1))
        #expect(await queue.flush(ownerID: "user") == .finished(uploaded: 0))
        #expect(await attempts.calls.count == 1)
        // The chapter stays in this Mac's History.
        #expect(try await store.entries(ownerID: "user").map(\.chapterID) == ["c1"])
    }

    @Test func overlappingFlushesNeverSendARowTwiceAndPickUpNewReading() async throws {
        let (store, cleanup) = Self.store()
        defer { cleanup() }
        try await store.record(ownerID: "user", visit: Self.visit("c1", percentage: 10, at: Self.now))
        let gate = Gate()
        let recorder = UploadRecorder()
        let queue = ReadingHistoryUploadQueue(store: store) { ownerID, batch in
            await recorder.record(ownerID, batch)
            if await recorder.calls.count == 1 { await gate.wait() }
        }

        let first = Task { await queue.flush(ownerID: "user") }
        await recorder.waitForCalls(1)
        // Read another chapter and ask again while the first upload is in flight.
        try await store.record(ownerID: "user", visit: Self.visit("c2", percentage: 10, at: Self.now + 1))
        let second = Task { await queue.flush(ownerID: "user") }
        let third = Task { await queue.flush(ownerID: "user") }
        try await Task.sleep(for: .milliseconds(50))
        await gate.open()

        let outcomes = [await first.value, await second.value, await third.value]
        #expect(outcomes.allSatisfy { $0 == .finished(uploaded: 2) })
        #expect(await recorder.calls.map { $0.batch.map(\.chapterId) } == [["c1"], ["c2"]])
        #expect(try await store.pendingUploads(ownerID: "user").isEmpty)
    }

    @Test func signingOutStopsAFlushBeforeItsNextBatch() async throws {
        let (store, cleanup) = Self.store()
        defer { cleanup() }
        for index in 0..<250 {
            try await store.record(ownerID: "user", visit: Self.visit("c\(index)", percentage: 10, at: Self.now + Double(index)))
        }
        let gate = Gate()
        let recorder = UploadRecorder()
        let queue = ReadingHistoryUploadQueue(store: store) { ownerID, batch in
            await recorder.record(ownerID, batch)
            await gate.wait()
        }

        let flush = Task { await queue.flush(ownerID: "user") }
        await recorder.waitForCalls(1)
        await queue.cancelAll()
        await gate.open()

        #expect(await flush.value == .cancelled)
        #expect(await recorder.calls.count == 1)
        #expect(try await store.pendingUploads(ownerID: "user", limit: 500).count == 250)
    }

    // MARK: API client

    @Test func theClientPostsBatchesAndReadsTheNewHistoryShape() async throws {
        HistoryURLProtocol.install { request in
            let url = try #require(request.url)
            if request.httpMethod == "POST" {
                let body = try #require(HistoryURLProtocol.body(of: request))
                let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
                let entries = try #require(object["entries"] as? [[String: Any]])
                #expect(url.path == "/me/history")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
                #expect(entries.first?["chapterId"] as? String == "c1")
                return (Self.response(url, 200), Data(#"{"data":[]}"#.utf8))
            }
            let rows = """
            {"data":[
              {"id":"r1","userId":"u","novelId":"n","chapterId":"c1","chapterNumber":4,"chapterTitle":"Four",
               "progress":75.5,"visitedAt":"2027-01-15T08:00:00.123Z","createdAt":"2027-01-15T08:00:00.123Z",
               "updatedAt":"2027-01-15T08:00:00.123Z"},
              {"id":"r2","userId":"u","novelId":"n","chapterId":"c2","visitedAt":"2027-01-15T07:00:00Z"}
            ]}
            """
            return (Self.response(url, 200), Data(rows.utf8))
        }
        defer { HistoryURLProtocol.reset() }
        let client = APIClient(
            baseURL: URL(string: "https://history.test")!,
            session: Self.stubbedSession(),
            retryDelays: []
        )
        await client.setToken("token")

        try await client.uploadReadingHistory([
            ReadingHistory.Upload(novelId: "n", chapterId: "c1", chapterNumber: 4, chapterTitle: nil, readAt: Self.now, progress: 10),
        ])
        let rows = try await client.fetchReadingHistory()
        #expect(rows.map(\.chapterId) == ["c1", "c2"])
        #expect(rows[0].chapterNumber == 4)
        #expect(rows[0].chapterTitle == "Four")
        #expect(rows[0].progress == 75.5)
        #expect(rows[0].createdAt != nil)
        #expect(rows[1].progress == nil)
    }

    // MARK: Helpers

    private static func visit(
        _ chapterID: String,
        percentage: Double,
        at date: Date,
        number: Int? = 1
    ) -> ReadingHistory.Visit {
        ReadingHistory.Visit(
            novelID: "n",
            chapterID: chapterID,
            chapterNumber: number,
            chapterTitle: "Chapter \(chapterID)",
            novelTitle: "Novel",
            coverURL: nil,
            percentage: percentage,
            readAt: date
        )
    }

    private static func row(
        _ chapterID: String,
        at date: Date,
        firstReadAt: Date? = nil,
        progress: Double? = nil,
        number: Int? = nil,
        title: String? = nil
    ) -> RemoteReadingHistoryRow {
        RemoteReadingHistoryRow(
            id: UUID().uuidString,
            novelId: "n",
            chapterId: chapterID,
            visitedAt: date,
            createdAt: firstReadAt,
            chapterNumber: number,
            chapterTitle: title,
            progress: progress
        )
    }

    private static func entry(novelID: String, chapterID: String, at date: Date = now) -> ReadingHistoryEntry {
        ReadingHistoryEntry(
            novelID: novelID,
            chapterID: chapterID,
            chapterNumber: nil,
            chapterTitle: nil,
            novelTitle: nil,
            coverURL: nil,
            percentage: 10,
            firstReadAt: date,
            lastReadAt: date
        )
    }

    private static func store() -> (ReadingHistoryStore, () -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ReadingHistoryStore(fileURL: directory.appendingPathComponent("history.json"))
        return (store, { try? FileManager.default.removeItem(at: directory) })
    }

    private static func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HistoryURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(_ url: URL, _ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    }
}

private actor UploadRecorder {
    struct Call: Sendable {
        let ownerID: String
        let batch: [ReadingHistory.Upload]
    }

    private(set) var calls: [Call] = []

    func record(_ ownerID: String, _ batch: [ReadingHistory.Upload]) {
        calls.append(Call(ownerID: ownerID, batch: batch))
    }

    func waitForCalls(_ count: Int) async {
        while calls.count < count {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

private actor FailureScript {
    private var failures: [any Error]

    init(_ failures: [any Error]) {
        self.failures = failures
    }

    func next() -> (any Error)? {
        failures.isEmpty ? nil : failures.removeFirst()
    }
}

private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

private final class HistoryURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?

    static func install(_ handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    /// URLSession moves bodies into a stream before protocols see them.
    static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
