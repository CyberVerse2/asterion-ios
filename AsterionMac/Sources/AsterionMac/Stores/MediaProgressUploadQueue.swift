import Foundation

enum MediaProgressUploadQueueError: Error, Equatable {
    case superseded
}

actor MediaProgressUploadQueue {
    struct Request: Equatable, Sendable {
        let ownerID: String
        let playback: MediaPlaybackDescriptor
        let positionSeconds: Double
        let durationSeconds: Double
        let completed: Bool?
        let started: Bool
        let sessionID: String
        let clientEventAt: Date

        func mergingEarlier(_ earlier: Request) -> Request {
            let latest = clientEventAt >= earlier.clientEventAt ? self : earlier
            let mergedCompleted = completed == true || earlier.completed == true
                ? true
                : latest.completed
            return Request(
                ownerID: latest.ownerID,
                playback: latest.playback,
                positionSeconds: latest.positionSeconds,
                durationSeconds: latest.durationSeconds,
                completed: mergedCompleted,
                started: started || earlier.started,
                sessionID: latest.sessionID,
                clientEventAt: latest.clientEventAt
            )
        }
    }

    typealias Upload = @Sendable (Request) async throws -> MediaProgressSaveResult

    private struct Key: Hashable, Sendable {
        let ownerID: String
        let mediaKey: MediaAccountKey
    }

    private struct PendingUpload {
        let request: Request
        let continuation: CheckedContinuation<MediaProgressSaveResult, any Error>
    }

    private let upload: Upload
    private var pendingByKey: [Key: [PendingUpload]] = [:]
    private var workerByKey: [Key: Task<Void, Never>] = [:]

    init(api: APIClient) {
        upload = { request in
            try await api.saveMediaProgress(
                request.playback,
                positionSeconds: request.positionSeconds,
                durationSeconds: request.durationSeconds,
                completed: request.completed,
                started: request.started,
                sessionID: request.sessionID,
                clientEventAt: request.clientEventAt
            )
        }
    }

    init(upload: @escaping Upload) {
        self.upload = upload
    }

    func submit(_ request: Request) async throws -> MediaProgressSaveResult {
        try await withCheckedThrowingContinuation { continuation in
            let key = Key(ownerID: request.ownerID, mediaKey: request.playback.item.key)
            var pending = pendingByKey[key] ?? []
            if let last = pending.last,
               last.request.playback.historyUnitID == request.playback.historyUnitID,
               last.request.sessionID == request.sessionID {
                let mergedRequest = request.mergingEarlier(last.request)
                pending[pending.count - 1] = PendingUpload(
                    request: mergedRequest,
                    continuation: continuation
                )
                last.continuation.resume(throwing: MediaProgressUploadQueueError.superseded)
            } else {
                pending.append(PendingUpload(request: request, continuation: continuation))
            }
            pendingByKey[key] = pending
            startWorkerIfNeeded(for: key)
        }
    }

    func cancelAll(exceptOwnerID retainedOwnerID: String? = nil) {
        let cancelledKeys = Set(pendingByKey.keys)
            .union(workerByKey.keys)
            .filter { $0.ownerID != retainedOwnerID }

        for key in cancelledKeys {
            pendingByKey.removeValue(forKey: key)?.forEach {
                $0.continuation.resume(throwing: CancellationError())
            }
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
        while !Task.isCancelled, let pending = popFirst(for: key) {
            do {
                let saved = try await upload(pending.request)
                pending.continuation.resume(returning: saved)
            } catch {
                pending.continuation.resume(throwing: error)
            }
        }
        pendingByKey.removeValue(forKey: key)?.forEach {
            $0.continuation.resume(throwing: CancellationError())
        }
        workerByKey[key] = nil
    }

    private func popFirst(for key: Key) -> PendingUpload? {
        guard var pending = pendingByKey[key], !pending.isEmpty else { return nil }
        let first = pending.removeFirst()
        if pending.isEmpty {
            pendingByKey.removeValue(forKey: key)
        } else {
            pendingByKey[key] = pending
        }
        return first
    }
}
