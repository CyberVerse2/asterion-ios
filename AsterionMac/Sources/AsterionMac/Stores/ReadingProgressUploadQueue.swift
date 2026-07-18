import Foundation

enum ReadingProgressUploadQueueError: Error, Equatable {
    case superseded
}

actor ReadingProgressUploadQueue {
    struct Request: Equatable, Sendable {
        let ownerID: String
        let novelID: String
        let chapterID: String
        let currentLine: Int
        let totalLines: Int
    }

    typealias Upload = @Sendable (Request) async throws -> ReadingProgress

    private struct Key: Hashable, Sendable {
        let ownerID: String
        let novelID: String
    }

    private struct PendingUpload {
        let request: Request
        let continuation: CheckedContinuation<ReadingProgress, any Error>
    }

    private let upload: Upload
    private var pendingByKey: [Key: PendingUpload] = [:]
    private var workerByKey: [Key: Task<Void, Never>] = [:]

    init(api: APIClient) {
        self.upload = { request in
            try await api.saveProgress(
                novelID: request.novelID,
                chapterID: request.chapterID,
                currentLine: request.currentLine,
                totalLines: request.totalLines
            )
        }
    }

    init(upload: @escaping Upload) {
        self.upload = upload
    }

    func submit(_ request: Request) async throws -> ReadingProgress {
        try await withCheckedThrowingContinuation { continuation in
            let key = Key(ownerID: request.ownerID, novelID: request.novelID)
            if let superseded = pendingByKey.updateValue(
                PendingUpload(request: request, continuation: continuation),
                forKey: key
            ) {
                superseded.continuation.resume(
                    throwing: ReadingProgressUploadQueueError.superseded
                )
            }
            startWorkerIfNeeded(for: key)
        }
    }

    func cancelAll(exceptOwnerID retainedOwnerID: String? = nil) {
        let cancelledKeys = Set(pendingByKey.keys)
            .union(workerByKey.keys)
            .filter { $0.ownerID != retainedOwnerID }

        for key in cancelledKeys {
            pendingByKey.removeValue(forKey: key)?.continuation.resume(
                throwing: CancellationError()
            )
            workerByKey[key]?.cancel()
        }
    }

    private func startWorkerIfNeeded(for key: Key) {
        guard workerByKey[key] == nil else { return }
        workerByKey[key] = Task { [weak self] in
            await self?.drain(key: key)
        }
    }

    private func drain(key: Key) async {
        while !Task.isCancelled, let pending = pendingByKey.removeValue(forKey: key) {
            do {
                let saved = try await upload(pending.request)
                pending.continuation.resume(returning: saved)
            } catch {
                pending.continuation.resume(throwing: error)
            }
        }
        if let pending = pendingByKey.removeValue(forKey: key) {
            pending.continuation.resume(throwing: CancellationError())
        }
        workerByKey[key] = nil
    }
}
