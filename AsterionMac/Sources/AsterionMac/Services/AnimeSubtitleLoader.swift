import Foundation

enum AnimeSubtitleLoadError: LocalizedError, Equatable {
    case http(label: String, statusCode: Int)
    case invalidSource(label: String)
    case localFileUnavailable(label: String)
    case invalidPayload(label: String)
    case payloadTooLarge(label: String)

    var errorDescription: String? {
        switch self {
        case .http(let label, let statusCode):
            "The \(label) subtitle track returned HTTP \(statusCode)."
        case .invalidSource(let label):
            "The \(label) subtitle track does not use a secure web address."
        case .localFileUnavailable(let label):
            "The downloaded \(label) subtitle file is missing or cannot be read."
        case .invalidPayload(let label):
            "The \(label) subtitle track is not a valid WebVTT file."
        case .payloadTooLarge(let label):
            "The \(label) subtitle track is too large to load safely."
        }
    }
}

struct AnimeSubtitleLoadResult: Sendable {
    let tracks: [AnimeSubtitleTrack]
    let failures: [String]
}

enum AnimeSubtitleLoader {
    private static let maximumTrackSize = 5 * 1_024 * 1_024

    private enum TrackLoadOutcome: Sendable {
        case loaded(index: Int, track: AnimeSubtitleTrack)
        case failed(index: Int, message: String)
    }

    static func load(
        _ tracks: [AnimeSubtitleTrack],
        allowsLocalFiles: Bool = false,
        session: URLSession = .shared
    ) async throws -> [AnimeSubtitleTrack] {
        try await withThrowingTaskGroup(
            of: (Int, AnimeSubtitleTrack).self,
            returning: [AnimeSubtitleTrack].self
        ) { group in
            for (index, track) in tracks.enumerated() {
                group.addTask {
                    (
                        index,
                        try await load(
                            track,
                            allowsLocalFiles: allowsLocalFiles,
                            session: session
                        )
                    )
                }
            }

            var loaded: [(Int, AnimeSubtitleTrack)] = []
            for try await track in group {
                loaded.append(track)
            }
            return loaded.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    static func dataURL(for data: Data, label: String) throws -> URL {
        guard data.count <= maximumTrackSize else {
            throw AnimeSubtitleLoadError.payloadTooLarge(label: label)
        }
        guard let text = String(data: data, encoding: .utf8),
              text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("WEBVTT") else {
            throw AnimeSubtitleLoadError.invalidPayload(label: label)
        }
        guard let url = URL(string: "data:text/vtt;base64,\(data.base64EncodedString())") else {
            throw AnimeSubtitleLoadError.invalidPayload(label: label)
        }
        return url
    }

    static func loadAvailable(
        _ tracks: [AnimeSubtitleTrack],
        allowsLocalFiles: Bool = false,
        session: URLSession = .shared
    ) async -> AnimeSubtitleLoadResult {
        await withTaskGroup(
            of: TrackLoadOutcome.self,
            returning: AnimeSubtitleLoadResult.self
        ) { group in
            for (index, track) in tracks.enumerated() {
                group.addTask {
                    do {
                        return .loaded(
                            index: index,
                            track: try await load(
                                track,
                                allowsLocalFiles: allowsLocalFiles,
                                session: session
                            )
                        )
                    } catch is CancellationError {
                        return .failed(index: index, message: "")
                    } catch {
                        return .failed(
                            index: index,
                            message: error.localizedDescription
                        )
                    }
                }
            }

            var loaded: [(Int, AnimeSubtitleTrack)] = []
            var failures: [(Int, String)] = []
            for await outcome in group {
                switch outcome {
                case .loaded(let index, let track):
                    loaded.append((index, track))
                case .failed(let index, let message) where !message.isEmpty:
                    failures.append((index, message))
                case .failed:
                    break
                }
            }
            return AnimeSubtitleLoadResult(
                tracks: loaded.sorted { $0.0 < $1.0 }.map(\.1),
                failures: failures.sorted { $0.0 < $1.0 }.map(\.1)
            )
        }
    }

    private static func load(
        _ track: AnimeSubtitleTrack,
        allowsLocalFiles: Bool,
        session: URLSession
    ) async throws -> AnimeSubtitleTrack {
        if track.fileURL.isFileURL {
            guard allowsLocalFiles else {
                throw AnimeSubtitleLoadError.invalidSource(label: track.label)
            }
            return try loadLocal(track)
        }

        guard isSecureTrackURL(track.fileURL) else {
            throw AnimeSubtitleLoadError.invalidSource(label: track.label)
        }

        var request = URLRequest(url: track.fileURL)
        request.setValue("text/vtt,text/plain;q=0.9,*/*;q=0.1", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let redirectDelegate = AnimeSubtitleRedirectDelegate()
        let (bytes, response) = try await session.bytes(
            for: request,
            delegate: redirectDelegate
        )
        guard let response = response as? HTTPURLResponse else {
            throw AnimeSubtitleLoadError.invalidPayload(label: track.label)
        }
        guard !redirectDelegate.blockedRedirect else {
            throw AnimeSubtitleLoadError.invalidSource(label: track.label)
        }
        guard let responseURL = response.url, isSecureTrackURL(responseURL) else {
            throw AnimeSubtitleLoadError.invalidSource(label: track.label)
        }
        guard 200..<300 ~= response.statusCode else {
            throw AnimeSubtitleLoadError.http(
                label: track.label,
                statusCode: response.statusCode
            )
        }
        guard response.expectedContentLength <= maximumTrackSize else {
            throw AnimeSubtitleLoadError.payloadTooLarge(label: track.label)
        }

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(Int(response.expectedContentLength))
        }
        for try await byte in bytes {
            guard data.count < maximumTrackSize else {
                throw AnimeSubtitleLoadError.payloadTooLarge(label: track.label)
            }
            data.append(byte)
        }

        return AnimeSubtitleTrack(
            fileURL: try dataURL(for: data, label: track.label),
            label: track.label,
            kind: track.kind,
            languageCode: track.languageCode,
            isDefault: track.isDefault
        )
    }

    private static func loadLocal(_ track: AnimeSubtitleTrack) throws -> AnimeSubtitleTrack {
        let values: URLResourceValues
        do {
            values = try track.fileURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
        } catch {
            throw AnimeSubtitleLoadError.localFileUnavailable(label: track.label)
        }

        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize else {
            throw AnimeSubtitleLoadError.localFileUnavailable(label: track.label)
        }
        guard fileSize <= maximumTrackSize else {
            throw AnimeSubtitleLoadError.payloadTooLarge(label: track.label)
        }

        let data: Data
        do {
            data = try Data(contentsOf: track.fileURL, options: .mappedIfSafe)
        } catch {
            throw AnimeSubtitleLoadError.localFileUnavailable(label: track.label)
        }

        return AnimeSubtitleTrack(
            fileURL: try dataURL(for: data, label: track.label),
            label: track.label,
            kind: track.kind,
            languageCode: track.languageCode,
            isDefault: track.isDefault
        )
    }

    static func isSecureTrackURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host != nil
            && url.user == nil
            && url.password == nil
    }
}

final class AnimeSubtitleRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var didBlockRedirect = false

    var blockedRedirect: Bool {
        lock.withLock { didBlockRedirect }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let url = request.url, AnimeSubtitleLoader.isSecureTrackURL(url) else {
            lock.withLock { didBlockRedirect = true }
            return nil
        }
        return request
    }
}
