import AsterionKit
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
    private let contentBaseURL = URL(string: "https://asterion-api.cyberverse.cloud")!
    private let userBaseURL: URL = APIClient.resolveUserBaseURL()
    private var sessionToken: String?
    /// Whether requests carry a session token. Views that show synced data
    /// (Home's Continue shelf) reload when this flips, since the token
    /// arrives only after Clerk restores the session on launch.
    @Published private(set) var isAuthorized = false

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[APIClient] \(message)")
        #endif
    }

    init() {
        debugLog("Resolved user API base URL: \(userBaseURL.absoluteString)")
    }

    func setSessionToken(_ token: String?) {
        self.sessionToken = token
        if isAuthorized != (token != nil) { isAuthorized = token != nil }
        debugLog("Session token updated. tokenPresent=\(token != nil)")
    }

    // MARK: - Novels

    func fetchNovels(limit: Int = 30, offset: Int = 0, search: String = "") async throws -> [Novel] {
        try await fetchNovelsPage(limit: limit, offset: offset, search: search).data
    }

    func fetchNovelsPage(limit: Int = 30, offset: Int = 0, search: String = "") async throws -> PaginatedResponse<Novel> {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ]
        if !search.isEmpty {
            items.append(URLQueryItem(name: "search", value: search))
        }
        let url = contentBaseURL.appending(path: "/novels").appending(queryItems: items)
        return try await request(url: url)
    }

    func fetchAllNovels(pageSize: Int = 100, search: String = "") async throws -> [Novel] {
        let normalizedPageSize = max(1, pageSize)
        var offset = 0
        var novels: [Novel] = []

        while true {
            let page = try await fetchNovelsPage(
                limit: normalizedPageSize,
                offset: offset,
                search: search
            )
            if page.data.isEmpty {
                break
            }

            novels.append(contentsOf: page.data)

            let total = page.meta?.total ?? page.meta?.count ?? 0
            if total > 0, novels.count >= total {
                break
            }
            if page.meta?.hasNextPage == false || page.data.count < normalizedPageSize {
                break
            }

            offset += normalizedPageSize
        }

        return novels
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

    func fetchAllChapters(novelId: String, pageSize: Int = 100) async throws -> [Chapter] {
        let normalizedPageSize = max(1, pageSize)
        var offset = 0
        var chapters: [Chapter] = []

        while true {
            let response = try await fetchChapters(
                novelId: novelId,
                limit: normalizedPageSize,
                offset: offset
            )
            if response.data.isEmpty {
                break
            }

            chapters.append(contentsOf: response.data)

            let total = response.meta?.total ?? response.meta?.count ?? 0
            if total > 0, chapters.count >= total {
                break
            }
            if response.data.count < normalizedPageSize {
                break
            }

            offset += normalizedPageSize
        }

        return chapters
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

    func fetchReadingHistory(limit: Int = 20, offset: Int = 0) async throws -> [AsterionReadingHistoryEntry] {
        let url = userBaseURL.appending(path: "/me/history").appending(queryItems: [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)"),
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

    // MARK: - Media Account

    func fetchMediaAccount() async throws -> MediaAccountSnapshot {
        let url = userBaseURL.appending(path: "/me/media")
        let wrapper: DataWrapper<MediaAccountSnapshot> = try await request(url: url)
        return wrapper.data
    }

    func saveMediaBookmark(
        _ item: MediaItemDescriptor,
        clientEventAt: Date = Date()
    ) async throws -> MediaBookmarkMutationResult {
        let url = userBaseURL.appending(path: "/me/media/bookmarks")
        let wrapper: DataWrapper<MediaBookmarkMutationResult?> = try await request(
            url: url,
            method: "PUT",
            body: MediaBookmarkBody(item: item, clientEventAt: clientEventAt)
        )
        guard let result = wrapper.data else { throw URLError(.cannotParseResponse) }
        return result
    }

    func deleteMediaBookmark(
        _ item: MediaItemDescriptor,
        clientEventAt: Date = Date()
    ) async throws -> MediaBookmarkMutationResult {
        let url = userBaseURL.appending(path: "/me/media/bookmarks")
        let wrapper: DataWrapper<MediaBookmarkMutationResult?> = try await request(
            url: url,
            method: "DELETE",
            body: MediaBookmarkBody(item: item, clientEventAt: clientEventAt)
        )
        guard let result = wrapper.data else { throw URLError(.cannotParseResponse) }
        return result
    }

    func saveMediaProgress(
        _ playback: MediaPlaybackDescriptor,
        positionSeconds: Double,
        durationSeconds: Double,
        completed: Bool? = nil,
        started: Bool,
        sessionID: UUID,
        clientEventAt: Date = Date()
    ) async throws -> MediaProgressSaveResult {
        let url = userBaseURL.appending(path: "/me/media/progress")
        struct RequestBody: Encodable {
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
        let wrapper: DataWrapper<MediaProgressSaveResult> = try await request(
            url: url,
            method: "PUT",
            body: RequestBody(
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
                sessionId: sessionID.uuidString,
                clientEventAt: Self.iso8601String(clientEventAt)
            )
        )
        return wrapper.data
    }

    private struct MediaBookmarkBody: Encodable {
        let mediaType: MediaAccountType
        let contentId: String
        let title: String
        let subtitle: String?
        let imageUrl: String?
        let clientEventAt: String

        init(item: MediaItemDescriptor, clientEventAt: Date) {
            mediaType = item.mediaType
            contentId = item.contentID
            title = item.title
            subtitle = item.subtitle
            imageUrl = item.imageURL?.absoluteString
            self.clientEventAt = APIClient.iso8601String(clientEventAt)
        }
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
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if let urlError = error as? URLError {
                debugLog(
                    "Transport failure \(method) \(url.absoluteString): code=\(urlError.code.rawValue) reason=\(urlError.localizedDescription)"
                )
            } else {
                debugLog("Transport failure \(method) \(url.absoluteString): \(error.localizedDescription)")
            }
            throw error
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if httpResponse.statusCode == 401, retryOnUnauthorized {
            debugLog("Received 401 for \(method) \(url.absoluteString). Attempting token refresh.")
            let refreshed = await refreshSessionTokenIfPossible()
            if refreshed {
                debugLog("Token refresh succeeded. Retrying request \(method) \(url.absoluteString).")
                return try await self.request(
                    url: url,
                    method: method,
                    body: body,
                    retryOnUnauthorized: false
                )
            }
            debugLog("Token refresh failed for \(method) \(url.absoluteString).")
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw makeHTTPError(
                statusCode: httpResponse.statusCode,
                data: data,
                url: url,
                method: method
            )
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
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if let urlError = error as? URLError {
                debugLog(
                    "Transport failure \(method) \(url.absoluteString): code=\(urlError.code.rawValue) reason=\(urlError.localizedDescription)"
                )
            } else {
                debugLog("Transport failure \(method) \(url.absoluteString): \(error.localizedDescription)")
            }
            throw error
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if httpResponse.statusCode == 401, retryOnUnauthorized {
            debugLog("Received 401 for \(method) \(url.absoluteString). Attempting token refresh.")
            let refreshed = await refreshSessionTokenIfPossible()
            if refreshed {
                debugLog("Token refresh succeeded. Retrying request \(method) \(url.absoluteString).")
                return try await requestNoBody(
                    url: url,
                    method: method,
                    retryOnUnauthorized: false
                )
            }
            debugLog("Token refresh failed for \(method) \(url.absoluteString).")
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw makeHTTPError(
                statusCode: httpResponse.statusCode,
                data: data,
                url: url,
                method: method
            )
        }
        return try Self.makeDecoder().decode(T.self, from: data)
    }

    private func makeHTTPError(statusCode: Int, data: Data, url: URL, method: String) -> NSError {
        let responseBody = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        #if DEBUG
        if !responseBody.isEmpty {
            print("[APIClient] \(method) \(url.absoluteString) -> \(statusCode): \(responseBody)")
        } else {
            print("[APIClient] \(method) \(url.absoluteString) -> \(statusCode)")
        }
        #endif

        var userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: "HTTP \(statusCode) for \(method) \(url.path())",
        ]
        if !responseBody.isEmpty {
            userInfo[NSLocalizedFailureReasonErrorKey] = responseBody
            userInfo["responseBody"] = responseBody
        }
        return NSError(domain: "APIClient", code: statusCode, userInfo: userInfo)
    }

    private func refreshSessionTokenIfPossible() async -> Bool {
        do {
            debugLog("Attempting Clerk token refresh.")
            let token = try await Clerk.shared.auth.getToken()
            guard let token, !token.isEmpty else { return false }
            sessionToken = token
            debugLog("Clerk token refresh returned a token.")
            return true
        } catch {
            debugLog("Clerk token refresh threw error: \(error.localizedDescription)")
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

    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func resolveUserBaseURL() -> URL {
        let rawConfigured: String? = {
            if let stableKey = Bundle.main.object(forInfoDictionaryKey: "AsterionUserAPIBaseURL") as? String {
                return stableKey
            }
            if let direct = Bundle.main.object(forInfoDictionaryKey: "USER_API_BASE_URL") as? String {
                return direct
            }

            // Some generated Info.plist variants can nest custom keys by underscores:
            // USER_API_BASE_URL -> USER -> API -> BASE -> URL
            if let user = Bundle.main.infoDictionary?["USER"] as? [String: Any],
               let api = user["API"] as? [String: Any],
               let base = api["BASE"] as? [String: Any],
               let nested = base["URL"] as? String
            {
                return nested
            }
            return nil
        }()

        if let rawConfigured {
            let configured = rawConfigured.trimmingCharacters(in: .whitespacesAndNewlines)
            if !configured.isEmpty {
                if let directURL = URL(string: configured), directURL.scheme != nil {
                    return directURL
                }
                if let httpsURL = URL(string: "https://\(configured)") {
                    return httpsURL
                }
                #if DEBUG
                print("[APIClient] Invalid USER_API_BASE_URL value: \(configured). Falling back to production.")
                #endif
            }
        }

        #if DEBUG
        print("[APIClient] USER_API_BASE_URL not found. Falling back to default API host.")
        #endif
        return URL(string: "https://asterion-api.cyberverse.cloud/")!
    }
}

@MainActor
final class MediaAccountService: ObservableObject {
    @Published private(set) var snapshot: MediaAccountSnapshot
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private static let guestStorageKey = "asterion.guest.media-account.v1"
    private weak var apiClient: APIClient?
    private var isSignedIn = false

    init() {
        snapshot = Self.loadGuestSnapshot()
    }

    func configure(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func handleAuthenticationChange(isSignedIn: Bool) async {
        self.isSignedIn = isSignedIn
        if isSignedIn {
            await mergeGuestActivityAndRefresh()
        } else {
            snapshot = Self.loadGuestSnapshot()
            errorMessage = nil
        }
    }

    func refresh() async {
        guard isSignedIn, let apiClient else {
            snapshot = Self.loadGuestSnapshot()
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await apiClient.fetchMediaAccount()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func isBookmarked(_ item: MediaItemDescriptor) -> Bool {
        snapshot.bookmarks.contains { $0.key == item.key }
    }

    func toggleBookmark(_ item: MediaItemDescriptor) async {
        let wasSaved = isBookmarked(item)
        if isSignedIn, let apiClient {
            do {
                let result = wasSaved
                    ? try await apiClient.deleteMediaBookmark(item)
                    : try await apiClient.saveMediaBookmark(item)
                applyBookmarkResult(result, item: item)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        var bookmarks = snapshot.bookmarks.filter { $0.key != item.key }
        if !wasSaved {
            let now = Date()
            bookmarks.insert(
                MediaBookmark(
                    id: UUID().uuidString,
                    userId: "guest",
                    mediaType: item.mediaType,
                    contentId: item.contentID,
                    title: item.title,
                    subtitle: item.subtitle,
                    imageURL: item.imageURL,
                    createdAt: now,
                    updatedAt: now
                ),
                at: 0
            )
        }
        snapshot = rebuiltSnapshot(bookmarks: bookmarks)
        saveGuestSnapshot()
    }

    func resumePosition(for playback: MediaPlaybackDescriptor) -> Double? {
        snapshot.progress.first {
            $0.mediaType == playback.item.mediaType
                && $0.contentId == playback.item.contentID
                && $0.unitId == playback.unitID
                && !$0.completed
        }?.positionSeconds
    }

    func record(
        _ playback: MediaPlaybackDescriptor,
        positionSeconds: Double,
        durationSeconds: Double,
        started: Bool,
        sessionID: UUID
    ) async {
        guard playback.item.mediaType != .football else { return }
        let normalized = MediaProgressPolicy.normalize(
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds
        )

        if isSignedIn, let apiClient {
            do {
                let result = try await apiClient.saveMediaProgress(
                    playback,
                    positionSeconds: normalized.positionSeconds,
                    durationSeconds: normalized.durationSeconds,
                    completed: normalized.completed,
                    started: started,
                    sessionID: sessionID
                )
                applyProgressResult(result)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        applyGuestProgress(
            playback,
            positionSeconds: normalized.positionSeconds,
            durationSeconds: normalized.durationSeconds,
            completed: normalized.completed,
            started: started
        )
        saveGuestSnapshot()
    }

    private func mergeGuestActivityAndRefresh() async {
        guard let apiClient else { return }
        let guest = Self.loadGuestSnapshot()
        guard !guest.bookmarks.isEmpty || !guest.progress.isEmpty else {
            await refresh()
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            for bookmark in guest.bookmarks {
                _ = try await apiClient.saveMediaBookmark(
                    MediaItemDescriptor(
                        mediaType: bookmark.mediaType,
                        contentID: bookmark.contentId,
                        title: bookmark.title,
                        subtitle: bookmark.subtitle,
                        imageURL: bookmark.imageURL
                    ),
                    clientEventAt: bookmark.updatedAt
                )
            }
            for progress in guest.progress {
                _ = try await apiClient.saveMediaProgress(
                    MediaPlaybackDescriptor(
                        item: MediaItemDescriptor(
                            mediaType: progress.mediaType,
                            contentID: progress.contentId,
                            title: progress.title,
                            subtitle: nil,
                            imageURL: progress.imageURL
                        ),
                        unitID: progress.unitId,
                        unitTitle: progress.unitTitle,
                        seasonNumber: progress.seasonNumber,
                        episodeNumber: progress.episodeNumber
                    ),
                    positionSeconds: progress.positionSeconds,
                    durationSeconds: progress.durationSeconds,
                    completed: progress.completed,
                    started: false,
                    sessionID: UUID(),
                    clientEventAt: progress.clientUpdatedAt
                )
            }
            UserDefaults.standard.removeObject(forKey: Self.guestStorageKey)
            snapshot = try await apiClient.fetchMediaAccount()
            errorMessage = nil
        } catch {
            snapshot = guest
            errorMessage = "Your guest activity is safe on this device and will sync when the connection recovers."
        }
    }

    private func applyBookmarkResult(_ result: MediaBookmarkMutationResult, item: MediaItemDescriptor) {
        var bookmarks = snapshot.bookmarks.filter { $0.key != item.key }
        if result.isSaved, let bookmark = result.bookmark {
            bookmarks.insert(bookmark, at: 0)
        }
        snapshot = rebuiltSnapshot(bookmarks: bookmarks)
    }

    private func applyProgressResult(_ result: MediaProgressSaveResult) {
        var progress = snapshot.progress
        var history = snapshot.history
        if let saved = result.progress {
            progress.removeAll { $0.id == saved.id || ($0.key == saved.key && $0.unitId == saved.unitId) }
            progress.insert(saved, at: 0)
        }
        if let saved = result.history {
            history.removeAll { $0.id == saved.id || ($0.mediaType == saved.mediaType && $0.contentId == saved.contentId && $0.unitId == saved.unitId) }
            history.insert(saved, at: 0)
        }
        snapshot = rebuiltSnapshot(progress: progress, history: history)
    }

    private func applyGuestProgress(
        _ playback: MediaPlaybackDescriptor,
        positionSeconds: Double,
        durationSeconds: Double,
        completed: Bool,
        started: Bool
    ) {
        let now = Date()
        let percentage = durationSeconds > 0 ? min(100, positionSeconds / durationSeconds * 100) : 0
        let existingProgress = snapshot.progress.first {
            $0.mediaType == playback.item.mediaType
                && $0.contentId == playback.item.contentID
                && $0.unitId == playback.unitID
        }
        let savedProgress = MediaPlaybackProgress(
            id: existingProgress?.id ?? UUID().uuidString,
            userId: "guest",
            mediaType: playback.item.mediaType,
            contentId: playback.item.contentID,
            title: playback.item.title,
            imageURL: playback.item.imageURL,
            unitId: playback.unitID,
            unitTitle: playback.unitTitle,
            seasonNumber: playback.seasonNumber,
            episodeNumber: playback.episodeNumber,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            percentage: percentage,
            completed: completed,
            clientUpdatedAt: now,
            createdAt: existingProgress?.createdAt ?? now,
            updatedAt: now
        )
        var progress = snapshot.progress.filter { $0.id != savedProgress.id }
        progress.insert(savedProgress, at: 0)

        let existingHistory = snapshot.history.first {
            $0.mediaType == playback.item.mediaType
                && $0.contentId == playback.item.contentID
                && $0.unitId == playback.unitID
        }
        let savedHistory = MediaHistoryEntry(
            id: existingHistory?.id ?? UUID().uuidString,
            userId: "guest",
            mediaType: playback.item.mediaType,
            contentId: playback.item.contentID,
            title: playback.item.title,
            imageURL: playback.item.imageURL,
            unitId: playback.unitID,
            unitTitle: playback.unitTitle,
            seasonNumber: playback.seasonNumber,
            episodeNumber: playback.episodeNumber,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            percentage: percentage,
            completed: completed,
            visitCount: (existingHistory?.visitCount ?? 0) + (started ? 1 : 0),
            clientUpdatedAt: now,
            firstViewedAt: existingHistory?.firstViewedAt ?? now,
            lastViewedAt: now,
            createdAt: existingHistory?.createdAt ?? now,
            updatedAt: now
        )
        var history = snapshot.history.filter { $0.id != savedHistory.id }
        history.insert(savedHistory, at: 0)
        snapshot = rebuiltSnapshot(progress: progress, history: history)
    }

    private func rebuiltSnapshot(
        bookmarks: [MediaBookmark]? = nil,
        progress: [MediaPlaybackProgress]? = nil,
        history: [MediaHistoryEntry]? = nil
    ) -> MediaAccountSnapshot {
        let nextBookmarks = bookmarks ?? snapshot.bookmarks
        let nextProgress = progress ?? snapshot.progress
        let nextHistory = history ?? snapshot.history
        return MediaAccountSnapshot(
            bookmarks: nextBookmarks,
            progress: nextProgress,
            history: nextHistory,
            stats: MediaAccountStats(
                savedAnime: nextBookmarks.filter { $0.mediaType == .anime }.count,
                savedMovies: nextBookmarks.filter { $0.mediaType == .movie }.count,
                savedMatches: nextBookmarks.filter { $0.mediaType == .football }.count,
                animeEpisodesCompleted: nextHistory.filter { $0.mediaType == .anime && $0.completed }.count,
                movieUnitsCompleted: nextHistory.filter { $0.mediaType == .movie && $0.completed }.count,
                titlesInProgress: nextProgress.filter { !$0.completed }.count,
                historyEntries: nextHistory.count,
                activityLast30Days: nextHistory.filter { $0.lastViewedAt >= Date().addingTimeInterval(-30 * 24 * 60 * 60) }.count
            )
        )
    }

    private func saveGuestSnapshot() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.guestStorageKey)
    }

    private static func loadGuestSnapshot() -> MediaAccountSnapshot {
        guard let data = UserDefaults.standard.data(forKey: guestStorageKey),
              let value = try? JSONDecoder().decode(MediaAccountSnapshot.self, from: data) else {
            return .empty
        }
        return value
    }
}

// MARK: - Novel library

/// The novels the user saved. Works signed out: a guest's saves live on this
/// device and join the account at sign-in. Signed in, every save or removal
/// lands here at once and is queued for the account, so the library button
/// works offline and the queue drains when the connection returns.
@MainActor
final class NovelLibraryService: ObservableObject {
    @Published private(set) var ledger: NovelLibraryLedger
    @Published private(set) var isRefreshing = false
    /// The last account fetch failed (offline, or the server is struggling).
    @Published private(set) var refreshFailed = false

    private static let guestKey = "asterion.novel-library.guest.v1"
    private static func accountKey(_ userID: String) -> String { "asterion.novel-library.account.v1.\(userID)" }

    private weak var apiClient: APIClient?
    private let defaults: UserDefaults
    private(set) var userID: String?
    private var isFlushing = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ledger = Self.load(Self.guestKey, from: defaults)
    }

    var isSignedIn: Bool { userID != nil }
    var entries: [NovelLibraryEntry] { ledger.entries }

    /// The account's list has been fetched at least once, so `entries` is
    /// more than the queued changes.
    var hasAccountCopy: Bool { ledger.accountSyncedAt != nil }

    func contains(_ novelID: String) -> Bool { ledger.contains(novelID) }

    func configure(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    /// Switches to the signed-in account's library (adopting anything saved
    /// as a guest) or back to the guest library.
    func handleAuthenticationChange(userID: String?) async {
        guard userID != self.userID else {
            await refresh()
            return
        }
        self.userID = userID
        refreshFailed = false
        guard let userID else {
            ledger = Self.load(Self.guestKey, from: defaults)
            return
        }
        var account = Self.load(Self.accountKey(userID), from: defaults)
        if defaults.data(forKey: Self.accountKey(userID)) == nil {
            // First run of this build: start from the shelf earlier builds
            // cached, so an offline launch isn't empty until the first fetch.
            let cached = await OfflineChapterStore.shared.loadLibrarySnapshot()
            account = NovelLibraryLedger(entries: cached.map {
                NovelLibraryEntry(
                    novelId: $0.novel.id,
                    addedAt: $0.addedAt ?? .distantPast,
                    updatedAt: $0.updatedAt,
                    novel: $0.novel
                )
            })
            guard self.userID == userID else { return }
        }
        let guest = Self.load(Self.guestKey, from: defaults)
        if !guest.entries.isEmpty {
            account.adopt(guest: guest)
            Self.save(account, key: Self.accountKey(userID), to: defaults)
            defaults.removeObject(forKey: Self.guestKey)
        }
        ledger = account
        notifyChanged()
        await refresh()
    }

    /// Saves or removes the novel. Returns whether it is now saved.
    @discardableResult
    func toggle(_ novel: Novel) -> Bool {
        let saved: Bool
        if ledger.contains(novel.id) {
            ledger.remove(novel.id)
            saved = false
        } else {
            ledger.add(novel.id, novel: novel)
            saved = true
        }
        persist()
        notifyChanged()
        if isSignedIn { Task { await flush() } }
        return saved
    }

    /// Keeps the stored titles and covers current for offline shelves.
    func remember(_ novels: [Novel]) {
        let before = ledger
        ledger.remember(novels)
        if ledger != before { persist() }
    }

    /// Sends queued changes, then reloads the account's list. Guests have
    /// nothing to fetch.
    func refresh() async {
        guard let userID, let apiClient else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await flush()
        do {
            let remote = try await apiClient.fetchMyLibrary()
            guard self.userID == userID else { return }
            let before = ledger.novelIds
            ledger.applyAccount(remote.map {
                NovelLibraryEntry(novelId: $0.novelId, addedAt: $0.createdAt ?? .distantPast, updatedAt: $0.updatedAt)
            })
            persist()
            refreshFailed = false
            if ledger.novelIds != before { notifyChanged() }
        } catch {
            guard self.userID == userID else { return }
            refreshFailed = true
        }
    }

    /// Sends the queued changes in order, stopping at the first that can't
    /// reach the account. A change the server rejects outright is dropped.
    func flush() async {
        guard let userID, let apiClient, !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }
        while let change = ledger.pending.first {
            do {
                switch change.kind {
                case .add: _ = try await apiClient.addNovelToLibrary(novelId: change.novelId)
                case .remove: try await apiClient.removeNovelFromLibrary(novelId: change.novelId)
                }
            } catch let error as NSError where error.domain == "APIClient"
                && (400..<500).contains(error.code) && error.code != 401 && error.code != 408 && error.code != 429 {
                // Rejected (e.g. an unknown novel): retrying won't help.
            } catch {
                return
            }
            // The account may have changed while the request was in flight.
            guard self.userID == userID else { return }
            ledger.acknowledge(change)
            persist()
        }
    }

    private func persist() {
        Self.save(ledger, key: userID.map(Self.accountKey) ?? Self.guestKey, to: defaults)
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .asterionSavedNovelsChanged, object: nil)
    }

    private static func load(_ key: String, from defaults: UserDefaults) -> NovelLibraryLedger {
        guard let data = defaults.data(forKey: key),
              let ledger = try? JSONDecoder().decode(NovelLibraryLedger.self, from: data) else {
            return NovelLibraryLedger()
        }
        return ledger
    }

    private static func save(_ ledger: NovelLibraryLedger, key: String, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: key)
    }
}
