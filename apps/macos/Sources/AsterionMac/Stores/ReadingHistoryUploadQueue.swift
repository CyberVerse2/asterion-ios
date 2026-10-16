import Foundation

/// Sends the chapters read on this Mac to the account (`POST /me/history`)
/// in batches. The history store is the queue: an entry stays pending until
/// an upload that covers its latest read succeeds, so reading offline, a
/// failed request or quitting mid-upload loses nothing. One flush runs per
/// owner at a time; asking again while one runs makes it take another pass
/// rather than sending the same rows twice.
actor ReadingHistoryUploadQueue {
    enum Outcome: Equatable, Sendable {
        /// Everything pending reached the account (`uploaded` may be 0).
        case finished(uploaded: Int)
        /// Stopped at a failure worth retrying (offline, 5xx, rate limited).
        case retryLater
        /// Stopped because the account rejected the session token.
        case unauthorized
        /// Stopped because the owner signed out or the flush was cancelled.
        case cancelled
    }

    typealias Upload = @Sendable (_ ownerID: String, _ batch: [ReadingHistory.Upload]) async throws -> Void

    /// More than any history can need (2,000 rows / 200 per batch), so a
    /// row that somehow never clears can't spin the loop forever.
    private static let maximumBatchesPerPass = 20

    private let store: ReadingHistoryStore
    private let upload: Upload
    private var flushByOwner: [String: Task<Outcome, Never>] = [:]
    private var rerunOwners: Set<String> = []

    init(store: ReadingHistoryStore, upload: @escaping Upload) {
        self.store = store
        self.upload = upload
    }

    init(store: ReadingHistoryStore, api: APIClient) {
        self.init(store: store) { _, batch in
            try await api.uploadReadingHistory(batch)
        }
    }

    /// Sends everything pending for `ownerID`. Joins a flush already
    /// running for the owner, which then takes one more pass.
    @discardableResult
    func flush(ownerID: String) async -> Outcome {
        if let running = flushByOwner[ownerID] {
            rerunOwners.insert(ownerID)
            return await running.value
        }
        let task = Task { await self.drain(ownerID: ownerID) }
        flushByOwner[ownerID] = task
        return await task.value
    }

    /// Stops flushes for every other owner, e.g. after an account switch.
    func cancelAll(exceptOwnerID retainedOwnerID: String? = nil) {
        for (ownerID, task) in flushByOwner where ownerID != retainedOwnerID {
            task.cancel()
            rerunOwners.remove(ownerID)
        }
    }

    private func drain(ownerID: String) async -> Outcome {
        // Cleared on the actor right after the last check for another pass,
        // so a flush asked for after that starts a fresh drain.
        defer { flushByOwner[ownerID] = nil }
        var uploaded = 0
        repeat {
            rerunOwners.remove(ownerID)
            var batches = 0
            while batches < Self.maximumBatchesPerPass {
                if Task.isCancelled { return .cancelled }
                guard let batch = try? await store.pendingUploads(ownerID: ownerID),
                      !batch.isEmpty else { break }
                batches += 1
                do {
                    try await upload(ownerID, batch)
                } catch {
                    switch Self.classify(error) {
                    case .rejected:
                        // The account will never take this batch; don't
                        // resend it forever. Its rows stay in local History.
                        break
                    case .retry:
                        return .retryLater
                    case .unauthorized:
                        return .unauthorized
                    case .cancelled:
                        return .cancelled
                    }
                }
                if Task.isCancelled { return .cancelled }
                guard (try? await store.markUploaded(ownerID: ownerID, batch)) != nil else {
                    return .retryLater
                }
                uploaded += batch.count
            }
        } while rerunOwners.contains(ownerID) && !Task.isCancelled
        return Task.isCancelled ? .cancelled : .finished(uploaded: uploaded)
    }

    private enum FailureKind {
        case rejected
        case retry
        case unauthorized
        case cancelled
    }

    private static func classify(_ error: any Error) -> FailureKind {
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled ? .cancelled : .retry
        }
        guard let apiError = error as? APIError else { return .retry }
        switch apiError {
        case .unauthorized:
            return .unauthorized
        case .invalidResponse:
            return .retry
        case .http(let statusCode, _):
            // 404 means the API hasn't shipped the endpoint yet: keep the
            // rows until it has. Other 4xx are this batch's own fault.
            if [400, 413, 422].contains(statusCode) { return .rejected }
            return .retry
        }
    }
}
