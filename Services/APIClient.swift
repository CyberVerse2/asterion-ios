import Foundation
import Combine

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
    private let baseURL = URL(string: "https://scraper-production-8f07.up.railway.app")!
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
        let url = baseURL.appending(path: "/novels").appending(queryItems: items)
        let wrapper: DataWrapper<[Novel]> = try await request(url: url)
        return wrapper.data
    }

    func fetchNovel(id: String) async throws -> Novel {
        let url = baseURL.appending(path: "/novels/\(id)")
        let wrapper: DataWrapper<Novel> = try await request(url: url)
        return wrapper.data
    }

    // MARK: - Chapters

    func fetchChapters(novelId: String, limit: Int = 100, offset: Int = 0) async throws -> PaginatedResponse<Chapter> {
        let url = baseURL.appending(path: "/novels/\(novelId)/chapters").appending(queryItems: [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ])
        return try await request(url: url)
    }

    func fetchChapter(id: String) async throws -> Chapter {
        let url = baseURL.appending(path: "/chapters/\(id)")
        let wrapper: DataWrapper<Chapter> = try await request(url: url)
        return wrapper.data
    }

    // MARK: - Auth

    func authenticateWithApple(identityToken: String, appleUserId: String, email: String?) async throws -> (String, User) {
        let url = baseURL.appending(path: "/auth/apple")
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

    // MARK: - Networking

    private struct DataWrapper<T: Decodable>: Decodable {
        let data: T
    }

    private func request<T: Decodable, B: Encodable>(
        url: URL,
        method: String = "GET",
        body: B? = nil
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
        guard 200..<300 ~= httpResponse.statusCode else {
            throw NSError(domain: "APIClient", code: httpResponse.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func request<T: Decodable>(url: URL) async throws -> T {
        try await request(url: url, method: "GET", body: Optional<String>.none)
    }
}
