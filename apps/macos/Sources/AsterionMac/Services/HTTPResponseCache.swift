import Foundation

struct CachedHTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
}

actor HTTPResponseCache {
    private struct Key: Hashable, Sendable {
        let namespace: String
        let method: String
        let url: URL
    }

    private struct Entry: Sendable {
        let response: CachedHTTPResponse
        let expiresAt: Date
    }

    private struct InFlight: Sendable {
        let id: UUID
        let task: Task<CachedHTTPResponse, Error>
    }

    private let maximumEntryCount: Int
    private var entries: [Key: Entry] = [:]
    private var inFlight: [Key: InFlight] = [:]

    init(maximumEntryCount: Int = 160) {
        self.maximumEntryCount = maximumEntryCount
    }

    func response(
        for request: URLRequest,
        session: URLSession,
        namespace: String,
        lifetime: TimeInterval
    ) async throws -> CachedHTTPResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        let key = Key(
            namespace: namespace,
            method: request.httpMethod ?? "GET",
            url: url
        )
        let now = Date()

        if let entry = entries[key], entry.expiresAt > now {
            return entry.response
        }
        entries.removeValue(forKey: key)

        if let pending = inFlight[key] {
            return try await pending.task.value
        }

        let requestID = UUID()
        let task = Task<CachedHTTPResponse, Error> {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return CachedHTTPResponse(data: data, statusCode: response.statusCode)
        }
        inFlight[key] = InFlight(id: requestID, task: task)

        do {
            let response = try await task.value
            removeInFlightRequest(key: key, requestID: requestID)
            if lifetime > 0, 200..<300 ~= response.statusCode {
                entries[key] = Entry(
                    response: response,
                    expiresAt: now.addingTimeInterval(lifetime)
                )
                trimIfNeeded(now: now)
            }
            return response
        } catch {
            removeInFlightRequest(key: key, requestID: requestID)
            throw error
        }
    }

    func invalidate(namespace: String) {
        entries = entries.filter { $0.key.namespace != namespace }
        let matchingTasks = inFlight.filter { $0.key.namespace == namespace }
        matchingTasks.values.forEach { $0.task.cancel() }
        inFlight = inFlight.filter { $0.key.namespace != namespace }
    }

    private func removeInFlightRequest(key: Key, requestID: UUID) {
        guard inFlight[key]?.id == requestID else { return }
        inFlight.removeValue(forKey: key)
    }

    private func trimIfNeeded(now: Date) {
        entries = entries.filter { $0.value.expiresAt > now }
        guard entries.count > maximumEntryCount else { return }
        let overflow = entries.count - maximumEntryCount
        let oldestKeys = entries
            .sorted { $0.value.expiresAt < $1.value.expiresAt }
            .prefix(overflow)
            .map(\.key)
        oldestKeys.forEach { entries.removeValue(forKey: $0) }
    }
}
