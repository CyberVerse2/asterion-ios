import Foundation
import Combine
import ClerkKit

struct AsterionUserProfile: Identifiable, Codable, Hashable {
    let id: String
    let clerkUserId: String
    let email: String?
    let username: String?
    let avatarUrl: String?
    let createdAt: Date?
    let updatedAt: Date?
}

struct AsterionBookmark: Identifiable, Codable, Hashable {
    let id: String
    let userId: String
    let novelId: String
    let chapterId: String
    let note: String?
    let createdAt: Date?
    let updatedAt: Date?
}

struct AsterionReadingHistoryEntry: Identifiable, Codable, Hashable {
    let id: String
    let userId: String
    let novelId: String
    let chapterId: String
    let visitedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?
}

struct AsterionLibraryNovel: Identifiable, Codable, Hashable {
    let id: String
    let userId: String
    let novelId: String
    let createdAt: Date?
    let updatedAt: Date?
}

struct AsterionUserPreferences: Identifiable, Codable, Hashable {
    let id: String
    let userId: String
    let readingGoal: Int
    let darkMode: Bool
    let notificationsOn: Bool
    let fontSizePref: String
    let createdAt: Date?
    let updatedAt: Date?
}

struct PaginatedResponse<T: Decodable>: Decodable {
    let data: [T]
    let meta: Meta?

    struct Meta: Decodable {
        let count: Int?
        let total: Int?
        let page: Int?
        let pageSize: Int?
        let totalPages: Int?
        let hasNextPage: Bool?
        let hasPreviousPage: Bool?
        let limit: Int?
        let offset: Int?
    }
}

@MainActor
final class APIClient: ObservableObject {
    private let contentBaseURL = URL(string: "https://scraper-production-8f07.up.railway.app")!
    private let userBaseURL: URL = {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "USER_API_BASE_URL") as? String,
           !configured.isEmpty,
           let url = URL(string: configured)
        {
            return url
        }
        return URL(string: "http://127.0.0.1:3001")!
    }()
    private var sessionToken: String?

    func setSessionToken(_ token: String?) {
        self.sessionToken = token
    }

    // MARK: - Novels

    func fetchNovels(limit: Int = 30, offset: Int = 0, search: String = "") async throws -> [Novel] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ]
        if !search.isEmpty {
            items.append(URLQueryItem(name: "search", value: search))
        }
        let url = contentBaseURL.appending(path: "/novels").appending(queryItems: items)
        let wrapper: DataWrapper<[Novel]> = try await request(url: url)
        return wrapper.data
    }

    func fetchNovel(id: String) async throws -> Novel {
        let url = contentBaseURL.appending(path: "/novels/\(id)")
        let wrapper: DataWrapper<Novel> = try await request(url: url)
        return wrapper.data
    }

    // MARK: - Chapters

    func fetchChapters(novelId: String, limit: Int = 100, offset: Int = 0) async throws -> PaginatedResponse<Chapter> {
        let url = contentBaseURL.appending(path: "/novels/\(novelId)/chapters").appending(queryItems: [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ])
        return try await request(url: url)
    }

    func fetchChapter(id: String) async throws -> Chapter {
        let url = contentBaseURL.appending(path: "/chapters/\(id)")
        let wrapper: DataWrapper<Chapter> = try await request(url: url)
        return wrapper.data
    }

    // MARK: - Auth

    func authenticateWithApple(identityToken: String, appleUserId: String, email: String?) async throws -> (String, User) {
        let url = contentBaseURL.appending(path: "/auth/apple")
        struct RequestBody: Encodable {
            let identityToken: String
            let appleUserId: String
            let email: String?
        }
        struct ResponseBody: Decodable {
            let sessionToken: String
            let user: User
        }
        let response: ResponseBody = try await request(
            url: url,
            method: "POST",
            body: RequestBody(identityToken: identityToken, appleUserId: appleUserId, email: email)
        )
        return (response.sessionToken, response.user)
    }

    // MARK: - User Data

    struct UserStats: Decodable {
        let chaptersRead: Int
        let novelsInProgress: Int
        let bookmarks: Int
    }

    func fetchMyStats() async throws -> UserStats {
        let url = userBaseURL.appending(path: "/me/stats")
        let wrapper: DataWrapper<UserStats> = try await request(url: url)
        return wrapper.data
    }

    func fetchMyProfile() async throws -> AsterionUserProfile {
        let url = userBaseURL.appending(path: "/me")
        let wrapper: DataWrapper<AsterionUserProfile> = try await request(url: url)
        return wrapper.data
    }

    func updateMyProfile(email: String? = nil, username: String? = nil, avatarUrl: String? = nil) async throws -> AsterionUserProfile {
        let url = userBaseURL.appending(path: "/me")
        struct RequestBody: Encodable {
            let email: String?
            let username: String?
            let avatarUrl: String?
        }
        let wrapper: DataWrapper<AsterionUserProfile> = try await request(
            url: url,
            method: "PATCH",
            body: RequestBody(email: email, username: username, avatarUrl: avatarUrl)
        )
        return wrapper.data
    }

    func fetchReadingProgress(novelId: String) async throws -> ReadingProgress? {
        let url = userBaseURL.appending(path: "/me/progress").appending(queryItems: [
            URLQueryItem(name: "novelId", value: novelId),
        ])
        let wrapper: DataWrapper<ReadingProgress?> = try await request(url: url)
        return wrapper.data
    }

    func fetchAllReadingProgress() async throws -> [ReadingProgress] {
        let url = userBaseURL.appending(path: "/me/progress")
        let wrapper: DataWrapper<[ReadingProgress]> = try await request(url: url)
        return wrapper.data
    }

    func upsertReadingProgress(
        novelId: String,
        chapterId: String,
        currentLine: Int,
        totalLines: Int,
        percentage: Double? = nil
    ) async throws -> ReadingProgress {
        let url = userBaseURL.appending(path: "/me/progress")
        struct RequestBody: Encodable {
            let novelId: String
            let chapterId: String
            let currentLine: Int
            let totalLines: Int
            let percentage: Double?
        }
        let wrapper: DataWrapper<ReadingProgress> = try await request(
            url: url,
            method: "PUT",
            body: RequestBody(
                novelId: novelId,
                chapterId: chapterId,
                currentLine: currentLine,
                totalLines: totalLines,
                percentage: percentage
            )
        )
        return wrapper.data
    }

    func fetchBookmarks() async throws -> [AsterionBookmark] {
        let url = userBaseURL.appending(path: "/me/bookmarks")
        let wrapper: DataWrapper<[AsterionBookmark]> = try await request(url: url)
        return wrapper.data
    }

    func fetchMyLibrary() async throws -> [AsterionLibraryNovel] {
        let url = userBaseURL.appending(path: "/me/library")
        let wrapper: DataWrapper<[AsterionLibraryNovel]> = try await request(url: url)
        return wrapper.data
    }

    func addNovelToLibrary(novelId: String) async throws -> AsterionLibraryNovel {
        let url = userBaseURL.appending(path: "/me/library")
        struct RequestBody: Encodable {
            let novelId: String
        }
        let wrapper: DataWrapper<AsterionLibraryNovel> = try await request(
            url: url,
            method: "POST",
            body: RequestBody(novelId: novelId)
        )
        return wrapper.data
    }

    @discardableResult
    func removeNovelFromLibrary(novelId: String) async throws -> Bool {
        let url = userBaseURL.appending(path: "/me/library/\(novelId)")
        struct DeleteResponse: Decodable {
            let deleted: Bool
        }
        let wrapper: DataWrapper<DeleteResponse> = try await requestNoBody(
            url: url,
            method: "DELETE"
        )
        return wrapper.data.deleted
    }

    func fetchReadingHistory(limit: Int = 20) async throws -> [AsterionReadingHistoryEntry] {
        let url = userBaseURL.appending(path: "/me/history").appending(queryItems: [
            URLQueryItem(name: "limit", value: "\(limit)"),
        ])
        let wrapper: DataWrapper<[AsterionReadingHistoryEntry]> = try await request(url: url)
        return wrapper.data
    }

    func fetchMyPreferences() async throws -> AsterionUserPreferences {
        let url = userBaseURL.appending(path: "/me/preferences")
        let wrapper: DataWrapper<AsterionUserPreferences> = try await request(url: url)
        return wrapper.data
    }

    func updateMyPreferences(
        readingGoal: Int? = nil,
        darkMode: Bool? = nil,
        notificationsOn: Bool? = nil,
        fontSizePref: String? = nil
    ) async throws -> AsterionUserPreferences {
        let url = userBaseURL.appending(path: "/me/preferences")
        struct RequestBody: Encodable {
            let readingGoal: Int?
            let darkMode: Bool?
            let notificationsOn: Bool?
            let fontSizePref: String?
        }
        let wrapper: DataWrapper<AsterionUserPreferences> = try await request(
            url: url,
            method: "PATCH",
            body: RequestBody(
                readingGoal: readingGoal,
                darkMode: darkMode,
                notificationsOn: notificationsOn,
                fontSizePref: fontSizePref
            )
        )
        return wrapper.data
    }

    func createBookmark(novelId: String, chapterId: String, note: String? = nil) async throws -> AsterionBookmark {
        let url = userBaseURL.appending(path: "/me/bookmarks")
        struct RequestBody: Encodable {
            let novelId: String
            let chapterId: String
            let note: String?
        }
        let wrapper: DataWrapper<AsterionBookmark> = try await request(
            url: url,
            method: "POST",
            body: RequestBody(novelId: novelId, chapterId: chapterId, note: note)
        )
        return wrapper.data
    }

    @discardableResult
    func deleteBookmark(id: String) async throws -> Bool {
        let url = userBaseURL.appending(path: "/me/bookmarks/\(id)")
        struct DeleteResponse: Decodable {
            let deleted: Bool
        }
        let wrapper: DataWrapper<DeleteResponse> = try await requestNoBody(
            url: url,
            method: "DELETE"
        )
        return wrapper.data.deleted
    }

    // MARK: - Networking

    private struct DataWrapper<T: Decodable>: Decodable {
        let data: T
    }

    private func request<T: Decodable, B: Encodable>(
        url: URL,
        method: String = "GET",
        body: B? = nil,
        retryOnUnauthorized: Bool = true
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let sessionToken {
            request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if httpResponse.statusCode == 401, retryOnUnauthorized {
            let refreshed = await refreshSessionTokenIfPossible()
            if refreshed {
                return try await self.request(
                    url: url,
                    method: method,
                    body: body,
                    retryOnUnauthorized: false
                )
            }
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw NSError(domain: "APIClient", code: httpResponse.statusCode)
        }
        return try Self.makeDecoder().decode(T.self, from: data)
    }

    private func request<T: Decodable>(url: URL) async throws -> T {
        try await request(url: url, method: "GET", body: Optional<String>.none)
    }

    private func requestNoBody<T: Decodable>(
        url: URL,
        method: String,
        retryOnUnauthorized: Bool = true
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let sessionToken {
            request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if httpResponse.statusCode == 401, retryOnUnauthorized {
            let refreshed = await refreshSessionTokenIfPossible()
            if refreshed {
                return try await requestNoBody(
                    url: url,
                    method: method,
                    retryOnUnauthorized: false
                )
            }
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw NSError(domain: "APIClient", code: httpResponse.statusCode)
        }
        return try Self.makeDecoder().decode(T.self, from: data)
    }

    private func refreshSessionTokenIfPossible() async -> Bool {
        do {
            let token = try await Clerk.shared.auth.getToken()
            guard let token, !token.isEmpty else { return false }
            sessionToken = token
            return true
        } catch {
            return false
        }
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: value) {
                return date
            }
            let fallbackFormatter = ISO8601DateFormatter()
            fallbackFormatter.formatOptions = [.withInternetDateTime]
            if let date = fallbackFormatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(value)")
        }
        return decoder
    }
}
