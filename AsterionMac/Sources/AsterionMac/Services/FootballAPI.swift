import Foundation

enum FootballAPIError: LocalizedError {
    case invalidResponse
    case http(statusCode: Int, message: String)
    case invalidPayload
    case noPlaybackSource

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The football service returned an invalid response."
        case .http(let statusCode, let message):
            message.isEmpty ? "The football service returned HTTP \(statusCode)." : message
        case .invalidPayload:
            "The football service returned data Asterion could not read."
        case .noPlaybackSource:
            "No playable source is available for this match."
        }
    }
}

actor FootballAPI {
    private struct Envelope<Value: Decodable & Sendable>: Decodable, Sendable {
        let success: Bool
        let data: Value
    }

    private struct ErrorEnvelope: Decodable {
        let error: String?
    }

    private struct StreamRequest: Encodable {
        let matchId: String
        let sources: [FootballStreamSource]
        let homeTeam: String?
        let awayTeam: String?
    }

    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = URL(string: "https://asterion-football.cyberverse.cloud")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchMatches(section: FootballSection) async throws -> [FootballMatch] {
        let path = switch section {
        case .live: "/api/matches/live"
        case .schedule: "/api/matches"
        case .popular: "/api/matches/popular"
        }
        let envelope: Envelope<[FootballMatch]> = try await request(path: path)
        return envelope.data
    }

    func fetchStreams(for match: FootballMatch) async throws -> [FootballStream] {
        let body = StreamRequest(
            matchId: match.id,
            sources: match.sources,
            homeTeam: match.homeTeam?.name,
            awayTeam: match.awayTeam?.name
        )
        let envelope: Envelope<FootballStreamCollection> = try await request(
            path: "/api/streams",
            method: "POST",
            body: try Self.encoder.encode(body)
        )
        guard !envelope.data.streams.isEmpty else {
            throw FootballAPIError.noPlaybackSource
        }
        return envelope.data.streams
    }

    private func request<Response: Decodable & Sendable>(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> Response {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw FootballAPIError.invalidResponse
        }
        guard 200..<300 ~= response.statusCode else {
            let envelope = try? Self.decoder.decode(ErrorEnvelope.self, from: data)
            throw FootballAPIError.http(
                statusCode: response.statusCode,
                message: envelope?.error ?? ""
            )
        }

        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw FootballAPIError.invalidPayload
        }
    }

    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()
}
