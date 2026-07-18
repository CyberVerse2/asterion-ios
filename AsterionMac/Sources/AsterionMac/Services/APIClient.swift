import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case http(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The server returned an invalid response."
        case .unauthorized:
            "Sign in to use this feature."
        case .http(let statusCode, let message):
            message.isEmpty ? "The server returned HTTP \(statusCode)." : message
        }
    }
}

enum CatalogPaginationError: LocalizedError {
    case repeatedPage(resource: String)

    var errorDescription: String? {
        switch self {
        case .repeatedPage(let resource):
            "The \(resource) service repeated the previous page, so Asterion stopped loading duplicate results. Try again."
        }
    }
}

extension Sequence where Element: Identifiable, Element.ID: Hashable {
    func deduplicatedByID() -> [Element] {
        var seen = Set<Element.ID>()
        return filter { seen.insert($0.id).inserted }
    }
}

struct UserProfile: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let clerkUserId: String
    let email: String?
    let username: String?
    let avatarURL: String?

    private enum CodingKeys: String, CodingKey {
        case id, clerkUserId, email, username
        case avatarURL = "avatarUrl"
    }
}

struct LibraryRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let userId: String
    let novelId: String
}

struct ReadingProgress: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let userId: String
    let novelId: String
    let chapterId: String
    let currentLine: Int
    let totalLines: Int
    let percentage: Double
    let updatedAt: Date?
}

actor APIClient {
    private struct ErrorEnvelope: Decodable {
        let error: String?
        let message: String?
    }

    private struct DataEnvelope<Value: Decodable & Sendable>: Decodable, Sendable {
        let data: Value
    }

    private struct Page<Value: Decodable & Sendable>: Decodable, Sendable {
        let data: [Value]
        let meta: Metadata?

        struct Metadata: Decodable, Sendable {
            let total: Int?
            let count: Int?
        }
    }

    private let baseURL = URL(string: "https://asterion-api.cyberverse.cloud")!
    private let session: URLSession
    private var token: String?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func setToken(_ token: String?) {
        self.token = token
    }

    func fetchAllNovels(search: String = "") async throws -> [Novel] {
        var offset = 0
        let pageSize = 100
        var result: [Novel] = []
        var seenIDs = Set<Novel.ID>()

        while true {
            var query = [
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset)),
            ]
            if !search.isEmpty {
                query.append(URLQueryItem(name: "search", value: search))
            }

            let page: Page<Novel> = try await request(path: "/novels", query: query)
            let newNovels = page.data
                .deduplicatedByID()
                .filter { seenIDs.insert($0.id).inserted }
            result.append(contentsOf: newNovels)
            let total = page.meta?.total ?? page.meta?.count
            if page.data.count < pageSize || total.map({ result.count >= $0 }) == true {
                return result
            }
            guard !newNovels.isEmpty else {
                throw CatalogPaginationError.repeatedPage(resource: "novel")
            }
            offset += pageSize
        }
    }

    func fetchNovel(id: String) async throws -> Novel {
        let envelope: DataEnvelope<Novel> = try await request(path: "/novels/\(id)")
        return envelope.data
    }

    func fetchAllChapters(novelID: String) async throws -> [Chapter] {
        var offset = 0
        let pageSize = 100
        var result: [Chapter] = []
        var seenIDs = Set<Chapter.ID>()

        while true {
            let page: Page<Chapter> = try await request(
                path: "/novels/\(novelID)/chapters",
                query: [
                    URLQueryItem(name: "limit", value: String(pageSize)),
                    URLQueryItem(name: "offset", value: String(offset)),
                ]
            )
            let newChapters = page.data
                .deduplicatedByID()
                .filter { seenIDs.insert($0.id).inserted }
            result.append(contentsOf: newChapters)
            let total = page.meta?.total ?? page.meta?.count
            if page.data.count < pageSize || total.map({ result.count >= $0 }) == true {
                return result.sorted { $0.chapterNumber < $1.chapterNumber }
            }
            guard !newChapters.isEmpty else {
                throw CatalogPaginationError.repeatedPage(resource: "chapter")
            }
            offset += pageSize
        }
    }

    func fetchChapter(id: String) async throws -> Chapter {
        let envelope: DataEnvelope<Chapter> = try await request(path: "/chapters/\(id)")
        return envelope.data
    }

    func fetchProfile() async throws -> UserProfile {
        let envelope: DataEnvelope<UserProfile> = try await request(path: "/me")
        return envelope.data
    }

    func updateProfile(email: String?, username: String?, avatarURL: String?) async throws -> UserProfile {
        struct Body: Encodable, Sendable {
            let email: String?
            let username: String?
            let avatarUrl: String?
        }
        let envelope: DataEnvelope<UserProfile> = try await request(
            path: "/me",
            method: "PATCH",
            body: Body(email: email, username: username, avatarUrl: avatarURL)
        )
        return envelope.data
    }

    func fetchLibrary() async throws -> [LibraryRecord] {
        let envelope: DataEnvelope<[LibraryRecord]> = try await request(path: "/me/library")
        return envelope.data
    }

    func addToLibrary(novelID: String) async throws -> LibraryRecord {
        struct Body: Encodable, Sendable { let novelId: String }
        let envelope: DataEnvelope<LibraryRecord> = try await request(
            path: "/me/library",
            method: "POST",
            body: Body(novelId: novelID)
        )
        return envelope.data
    }

    func removeFromLibrary(novelID: String) async throws {
        struct Deleted: Decodable, Sendable { let deleted: Bool }
        let envelope: DataEnvelope<Deleted> = try await request(
            path: "/me/library/\(novelID)",
            method: "DELETE"
        )
        guard envelope.data.deleted else {
            throw APIError.invalidResponse
        }
    }

    func fetchProgress(novelID: String) async throws -> ReadingProgress? {
        let envelope: DataEnvelope<ReadingProgress?> = try await request(
            path: "/me/progress",
            query: [URLQueryItem(name: "novelId", value: novelID)]
        )
        return envelope.data
    }

    func fetchAllProgress() async throws -> [ReadingProgress] {
        let envelope: DataEnvelope<[ReadingProgress]> = try await request(path: "/me/progress")
        return envelope.data
    }

    func saveProgress(
        novelID: String,
        chapterID: String,
        currentLine: Int,
        totalLines: Int
    ) async throws -> ReadingProgress {
        struct Body: Encodable, Sendable {
            let novelId: String
            let chapterId: String
            let currentLine: Int
            let totalLines: Int
            let percentage: Double
        }
        let percentage = totalLines > 0 ? Double(currentLine) / Double(totalLines) * 100 : 0
        let envelope: DataEnvelope<ReadingProgress> = try await request(
            path: "/me/progress",
            method: "PUT",
            body: Body(
                novelId: novelID,
                chapterId: chapterID,
                currentLine: currentLine,
                totalLines: totalLines,
                percentage: percentage
            )
        )
        return envelope.data
    }

    func fetchMediaAccount() async throws -> MediaAccountSnapshot {
        let envelope: DataEnvelope<MediaAccountSnapshot> = try await request(path: "/me/media")
        return envelope.data
    }

    func saveMediaBookmark(
        _ item: MediaItemDescriptor,
        clientEventAt: Date
    ) async throws -> MediaBookmarkMutationResult {
        struct Body: Encodable, Sendable {
            let mediaType: MediaAccountType
            let contentId: String
            let title: String
            let subtitle: String?
            let imageUrl: String?
            let clientEventAt: String
        }
        let envelope: DataEnvelope<MediaBookmarkMutationResult?> = try await request(
            path: "/me/media/bookmarks",
            method: "PUT",
            body: Body(
                mediaType: item.mediaType,
                contentId: item.contentID,
                title: item.title,
                subtitle: item.subtitle,
                imageUrl: item.imageURL?.absoluteString,
                clientEventAt: Self.iso8601String(clientEventAt)
            )
        )
        guard let result = envelope.data,
              !result.isSaved || result.bookmark != nil else { throw APIError.invalidResponse }
        return result
    }

    func deleteMediaBookmark(
        _ item: MediaItemDescriptor,
        clientEventAt: Date
    ) async throws -> MediaBookmarkMutationResult {
        struct Body: Encodable, Sendable {
            let mediaType: MediaAccountType
            let contentId: String
            let title: String
            let subtitle: String?
            let imageUrl: String?
            let clientEventAt: String
        }
        let envelope: DataEnvelope<MediaBookmarkMutationResult?> = try await request(
            path: "/me/media/bookmarks",
            method: "DELETE",
            body: Body(
                mediaType: item.mediaType,
                contentId: item.contentID,
                title: item.title,
                subtitle: item.subtitle,
                imageUrl: item.imageURL?.absoluteString,
                clientEventAt: Self.iso8601String(clientEventAt)
            )
        )
        guard let result = envelope.data,
              !result.isSaved || result.bookmark != nil else { throw APIError.invalidResponse }
        return result
    }

    func saveMediaProgress(
        _ playback: MediaPlaybackDescriptor,
        positionSeconds: Double,
        durationSeconds: Double,
        completed: Bool?,
        started: Bool,
        sessionID: String,
        clientEventAt: Date
    ) async throws -> MediaProgressSaveResult {
        struct Body: Encodable, Sendable {
            let mediaType: MediaAccountType
            let contentId: String
            let title: String
            let imageUrl: String?
            let unitId: String
            let unitTitle: String?
            let seasonNumber: Int?
            let episodeNumber: Int?
            let positionSeconds: Double
            let durationSeconds: Double
            let completed: Bool?
            let started: Bool
            let sessionId: String
            let clientEventAt: String
        }
        let envelope: DataEnvelope<MediaProgressSaveResult> = try await request(
            path: "/me/media/progress",
            method: "PUT",
            body: Body(
                mediaType: playback.item.mediaType,
                contentId: playback.item.contentID,
                title: playback.item.title,
                imageUrl: playback.item.imageURL?.absoluteString,
                unitId: playback.unitID,
                unitTitle: playback.unitTitle,
                seasonNumber: playback.seasonNumber,
                episodeNumber: playback.episodeNumber,
                positionSeconds: max(0, positionSeconds),
                durationSeconds: max(0, durationSeconds),
                completed: completed,
                started: started,
                sessionId: sessionID,
                clientEventAt: Self.iso8601String(clientEventAt)
            )
        )
        return envelope.data
    }

    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func request<Response: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem] = [],
        method: String = "GET"
    ) async throws -> Response {
        try await request(path: path, query: query, method: method, body: Optional<String>.none)
    }

    private func request<Response: Decodable & Sendable, Body: Encodable & Sendable>(
        path: String,
        query: [URLQueryItem] = [],
        method: String = "GET",
        body: Body?
    ) async throws -> Response {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard 200..<300 ~= response.statusCode else {
            if response.statusCode == 401 { throw APIError.unauthorized }
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            let message = envelope?.message
                ?? envelope?.error
                ?? String(data: data, encoding: .utf8)
                ?? ""
            throw APIError.http(statusCode: response.statusCode, message: message)
        }
        return try Self.decoder.decode(Response.self, from: data)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 8601 date: \(value)"
            )
        }
        return decoder
    }()
}
