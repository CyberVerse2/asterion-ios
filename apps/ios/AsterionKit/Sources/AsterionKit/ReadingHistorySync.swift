import Foundation

/// Why an upload of reading history failed, as far as retrying goes.
public enum ReadingHistoryUploadError: Error, Equatable, Sendable {
    /// The account will never take this batch (400, 413, 422): drop it
    /// rather than resend it forever. Its rows stay in local History.
    case rejected
    /// The session token was refused even after a refresh.
    case unauthorized
    /// Offline, a timeout, a 5xx, rate limiting, or an API that hasn't
    /// shipped the endpoint yet (404): keep the rows and try later.
    case retryLater

    public init(httpStatus statusCode: Int) {
        switch statusCode {
        case 400, 413, 422: self = .rejected
        case 401, 403: self = .unauthorized
        default: self = .retryLater
        }
    }
}

/// Owns one owner's reading history ledger and sends what the account
/// hasn't seen to `POST /me/history` in batches. One flush runs at a time;
/// asking again while one runs makes it take another pass rather than
/// sending the same rows twice. Switching owner (`load`) drops any marks
/// from a flush still in flight for the previous one.
@MainActor
public final class ReadingHistorySync {
    public enum Outcome: Equatable, Sendable {
        /// Everything pending reached the account (`uploaded` may be 0).
        case finished(uploaded: Int)
        case retryLater
        case unauthorized
        /// The owner changed or the flush was cancelled.
        case cancelled
    }

    public typealias Upload = @MainActor ([ReadingHistoryUpload]) async throws -> Void

    /// More than any ledger can need, so a row that somehow never clears
    /// can't spin a flush forever.
    private static let maximumBatchesPerPass = 60

    public private(set) var ledger: ReadingHistoryLedger
    /// Called after every change, to persist and publish the ledger.
    public var onChange: ((ReadingHistoryLedger) -> Void)?

    private var generation = 0
    private var flushTask: Task<Outcome, Never>?
    private var needsAnotherPass = false

    public init(ledger: ReadingHistoryLedger = ReadingHistoryLedger()) {
        self.ledger = ledger
    }

    public var isFlushing: Bool { flushTask != nil }

    /// Switches to another owner's ledger.
    public func load(_ ledger: ReadingHistoryLedger) {
        generation &+= 1
        flushTask?.cancel()
        flushTask = nil
        needsAnotherPass = false
        self.ledger = ledger
    }

    public func update(_ transform: (inout ReadingHistoryLedger) -> Void) {
        var next = ledger
        transform(&next)
        guard next != ledger else { return }
        ledger = next
        onChange?(ledger)
    }

    /// Sends everything pending. Joins a flush already running, which then
    /// takes one more pass.
    @discardableResult
    public func flush(using upload: @escaping Upload) async -> Outcome {
        if let flushTask {
            needsAnotherPass = true
            return await flushTask.value
        }
        let generation = generation
        let task = Task { await self.drain(generation: generation, upload: upload) }
        flushTask = task
        return await task.value
    }

    private func drain(generation: Int, upload: Upload) async -> Outcome {
        defer {
            if self.generation == generation { flushTask = nil }
        }
        var uploaded = 0
        repeat {
            needsAnotherPass = false
            for _ in 0..<Self.maximumBatchesPerPass {
                guard self.generation == generation, !Task.isCancelled else { return .cancelled }
                let batch = ledger.pendingUploads()
                guard !batch.isEmpty else { break }
                do {
                    try await upload(batch)
                } catch let error as ReadingHistoryUploadError {
                    switch error {
                    case .rejected: break
                    case .unauthorized: return .unauthorized
                    case .retryLater: return .retryLater
                    }
                } catch is CancellationError {
                    return .cancelled
                } catch let error as URLError where error.code == .cancelled {
                    return .cancelled
                } catch {
                    return .retryLater
                }
                guard self.generation == generation, !Task.isCancelled else { return .cancelled }
                update { $0.markUploaded(batch) }
                uploaded += batch.count
            }
        } while needsAnotherPass && self.generation == generation
        return .finished(uploaded: uploaded)
    }
}

/// Reads and writes each owner's ledger as a JSON file.
public struct ReadingHistoryFileStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Application Support/Asterion/ReadingHistory.
    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Asterion", isDirectory: true)
            .appendingPathComponent("ReadingHistory", isDirectory: true)
    }

    public func load(ownerID: String) -> ReadingHistoryLedger {
        guard let data = try? Data(contentsOf: fileURL(ownerID: ownerID)),
              let ledger = try? Self.decoder.decode(ReadingHistoryLedger.self, from: data) else {
            return ReadingHistoryLedger()
        }
        return ledger
    }

    public func save(_ ledger: ReadingHistoryLedger, ownerID: String) {
        guard let data = try? Self.encoder.encode(ledger) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(ownerID: ownerID), options: [.atomic])
    }

    public func remove(ownerID: String) {
        try? FileManager.default.removeItem(at: fileURL(ownerID: ownerID))
    }

    func fileURL(ownerID: String) -> URL {
        // Owner ids are Clerk ids or "guest"; keep the name filesystem-safe anyway.
        let safe = String(ownerID.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" ? $0 : "_" })
        return directory.appendingPathComponent("\(safe.isEmpty ? "guest" : safe).json")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}
