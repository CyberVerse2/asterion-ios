import AsterionKit
import Combine
import Foundation

@MainActor
protocol ReadingHistoryAPI: AnyObject {
    func uploadReadingHistory(_ entries: [ReadingHistoryUpload]) async throws
    func fetchReadingHistory(limit: Int, offset: Int) async throws -> [AsterionReadingHistoryEntry]
}

extension APIClient: ReadingHistoryAPI {}

/// Reading time per day, plus the chapters read (History), per account.
/// History is recorded here on every chapter opened or read further, kept
/// on the device, and sent to the account in batches (`POST /me/history`),
/// so chapters read offline or in a quick run reach other devices one by
/// one rather than only as the latest position.
@MainActor
final class ReadingActivityService: ObservableObject {
    @Published private(set) var days: [ReadingDayActivity] = []
    @Published private(set) var history = ReadingHistoryLedger()
    private let defaults: UserDefaults
    private let historyStore: ReadingHistoryFileStore
    private let historySync = ReadingHistorySync()
    private var storageKey = "asterion.reading.activity.guest"
    private var userID: String?
    private weak var apiClient: (any ReadingHistoryAPI)?
    private var uploadTask: Task<Void, Never>?
    private var uploadGeneration = 0

    /// Pages of account history merged per sync (50 rows each).
    private static let remotePageCount = 4
    private static let guestOwnerID = "guest"

    init(defaults: UserDefaults = .standard, historyDirectory: URL? = nil) {
        self.defaults = defaults
        self.historyStore = ReadingHistoryFileStore(
            directory: historyDirectory ?? ReadingHistoryFileStore.defaultDirectory()
        )
        historySync.onChange = { [weak self] ledger in self?.historyChanged(ledger) }
        restore()
        loadHistory()
    }

    func configure(apiClient: any ReadingHistoryAPI) {
        self.apiClient = apiClient
    }

    func setUser(_ userID: String?) {
        let key = "asterion.reading.activity.\(userID ?? "guest")"
        guard key != storageKey else { return }
        storageKey = key
        self.userID = userID
        restore()
        loadHistory()
        if userID != nil { scheduleUpload(after: 0) }
    }

    func record(novelID: String, chapterID: String, seconds: Double, endingAt date: Date = .now) {
        guard seconds > 0, seconds.isFinite else { return }
        // Divide intervals at local midnight so today's time and streak stay accurate.
        let calendar = Calendar.current
        var start = date.addingTimeInterval(-min(seconds, 60))
        while start < date {
            let day = calendar.startOfDay(for: start)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
            let end = min(date, nextDay)
            if let index = days.firstIndex(where: { $0.date == day }) {
                days[index].seconds += end.timeIntervalSince(start)
                days[index].chapterIDs.insert("\(novelID)/\(chapterID)")
            } else {
                days.append(ReadingDayActivity(date: day, seconds: end.timeIntervalSince(start),
                                               chapterIDs: ["\(novelID)/\(chapterID)"]))
            }
            start = end
        }
        if let data = try? JSONEncoder().encode(days) { defaults.set(data, forKey: storageKey) }
    }

    // MARK: History

    /// Records the chapter in History: on opening it and as reading moves
    /// through it. Signed in, it is sent to the account a moment later,
    /// together with whatever else was read meanwhile.
    func recordChapterVisit(novelID: String, chapterID: String, chapterNumber: Int?, chapterTitle: String?,
                            progress: Double, at date: Date = .now) {
        historySync.update {
            $0.record(novelId: novelID, chapterId: chapterID, chapterNumber: chapterNumber,
                      chapterTitle: chapterTitle, progress: progress, at: date)
        }
        // An upload already waiting (or backing off) will carry it.
        if userID != nil, uploadTask == nil, history.pendingCount > 0 { scheduleUpload(after: 4) }
    }

    /// Folds the account's history (e.g. every page Profile loaded) in.
    func mergeRemoteHistory(_ rows: [AsterionReadingHistoryEntry]) {
        let records = rows.compactMap(\.record)
        guard userID != nil, !records.isEmpty else { return }
        historySync.update { $0.merge(remote: records) }
    }

    /// Sends what this device read that the account hasn't seen, then
    /// merges the account's recent history. Safe to call often: with
    /// nothing pending it sends nothing.
    func syncHistory(pullRemote: Bool = true) async {
        guard let userID, let apiClient else { return }
        let outcome = await uploadPending()
        switch outcome {
        case .retryLater, .unauthorized: scheduleUpload(after: ReadingHistoryLedger.uploadRetryDelay(afterFailures: 0))
        case .finished, .cancelled: break
        }
        guard pullRemote else { return }
        var rows: [AsterionReadingHistoryEntry] = []
        for page in 0..<Self.remotePageCount {
            guard let chunk = try? await apiClient.fetchReadingHistory(limit: 50, offset: page * 50) else { break }
            rows.append(contentsOf: chunk)
            if chunk.count < 50 { break }
        }
        guard self.userID == userID else { return }
        mergeRemoteHistory(rows)
    }

    func summary(goal: Int, now: Date = .now) -> ReadingStatistics {
        ReadingStatistics.calculate(days: days, visits: history.visits, goal: goal, now: now)
    }

    private func uploadPending() async -> ReadingHistorySync.Outcome {
        guard let userID, let apiClient else { return .cancelled }
        return await historySync.flush { [weak self] batch in
            // Never send one account's reading under another's session.
            guard self?.userID == userID else { throw CancellationError() }
            try await apiClient.uploadReadingHistory(batch)
        }
    }

    /// Uploads after `delay` seconds, retrying with backoff while offline or
    /// the API is down. A new request replaces the waiting one; an upload
    /// already in flight finishes either way.
    private func scheduleUpload(after delay: TimeInterval) {
        uploadTask?.cancel()
        uploadGeneration &+= 1
        let generation = uploadGeneration
        let userID = userID
        uploadTask = Task { [weak self] in
            defer {
                if self?.uploadGeneration == generation { self?.uploadTask = nil }
            }
            var delay = delay
            var failures = 0
            while true {
                if delay > 0 {
                    do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                }
                guard let self, self.userID == userID, userID != nil else { return }
                switch await self.uploadPending() {
                case .finished, .cancelled: return
                case .retryLater, .unauthorized: break
                }
                delay = ReadingHistoryLedger.uploadRetryDelay(afterFailures: failures)
                failures += 1
            }
        }
    }

    private func loadHistory() {
        uploadTask?.cancel()
        uploadTask = nil
        uploadGeneration &+= 1
        var ledger = historyStore.load(ownerID: userID ?? Self.guestOwnerID)
        if userID != nil {
            // Chapters read before signing in join the account.
            let guest = historyStore.load(ownerID: Self.guestOwnerID)
            if !guest.isEmpty {
                ledger.adopt(guest: guest)
                historyStore.save(ledger, ownerID: userID!)
                historyStore.remove(ownerID: Self.guestOwnerID)
            }
        }
        historySync.load(ledger)
        history = ledger
    }

    private func historyChanged(_ ledger: ReadingHistoryLedger) {
        history = ledger
        historyStore.save(ledger, ownerID: userID ?? Self.guestOwnerID)
    }

    private func restore() {
        days = defaults.data(forKey: storageKey).flatMap {
            try? JSONDecoder().decode([ReadingDayActivity].self, from: $0)
        } ?? []
    }
}
