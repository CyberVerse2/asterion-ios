import Foundation
import UIKit

#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
import ActivityKit

@MainActor
final class DownloadLiveActivityManager {
    static let shared = DownloadLiveActivityManager()

    private var activity: Activity<ChapterDownloadActivityAttributes>?

    func start(novelTitle: String, novelImageURL: String?, total: Int) async {
        guard #available(iOS 16.1, *) else {
            debugLog("Live Activities unavailable on this iOS version.")
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            debugLog("Live Activities are disabled by system/user settings.")
            return
        }

        if let existing = activity {
            Task {
                await existing.end(
                    ActivityContent(
                        state: .init(completed: 0, total: max(total, 1), statusText: "Restarting"),
                        staleDate: nil
                    ),
                    dismissalPolicy: .immediate
                )
            }
            debugLog("Ended existing live activity before starting a new one.")
        }

        let normalizedURL = normalizedImageURLString(novelImageURL)
        let imageData = await fetchTinyThumbnailData(from: normalizedURL, maxBytes: 3500)
        let state = ChapterDownloadActivityAttributes.ContentState(
            completed: 0,
            total: max(total, 1),
            statusText: "Preparing"
        )

        do {
            let attrs = ChapterDownloadActivityAttributes(
                novelTitle: novelTitle,
                novelImageURL: normalizedURL,
                novelImageData: imageData
            )
            activity = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            debugLog("Started live activity. imageDataBytes=\(imageData?.count ?? 0)")
        } catch {
            debugLog("Live activity start failed with image payload: \(String(describing: error))")
            do {
                let fallbackAttrs = ChapterDownloadActivityAttributes(
                    novelTitle: novelTitle,
                    novelImageURL: normalizedURL,
                    novelImageData: nil
                )
                activity = try Activity.request(
                    attributes: fallbackAttrs,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
                debugLog("Started live activity using URL-only fallback.")
            } catch {
                activity = nil
                debugLog("Live activity fallback start also failed: \(String(describing: error))")
            }
        }
    }

    private func normalizedImageURLString(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("//") {
            value = "https:\(value)"
        } else if !value.contains("://") {
            value = "https://\(value)"
        } else if value.hasPrefix("http://") {
            value = value.replacingOccurrences(of: "http://", with: "https://")
        }

        if let components = URLComponents(string: value), let url = components.url {
            return url.absoluteString
        }

        let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        return encoded
    }

    private func fetchTinyThumbnailData(from normalizedURL: String?, maxBytes: Int) async -> Data? {
        guard let normalizedURL, let url = URL(string: normalizedURL) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
            guard !data.isEmpty else { return nil }

            guard let image = UIImage(data: data) else { return nil }
            let maxSide: CGFloat = 64
            let scale = min(maxSide / max(image.size.width, 1), maxSide / max(image.size.height, 1), 1)
            let targetSize = CGSize(
                width: max(1, floor(image.size.width * scale)),
                height: max(1, floor(image.size.height * scale))
            )

            let renderer = UIGraphicsImageRenderer(size: targetSize)
            let reduced = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }

            for quality in [0.65, 0.45, 0.3, 0.2, 0.12] {
                if let candidate = reduced.jpegData(compressionQuality: quality), candidate.count <= maxBytes {
                    return candidate
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    func update(completed: Int, total: Int) {
        guard #available(iOS 16.1, *) else { return }
        guard let activity else { return }
        let clampedCompleted = max(0, min(completed, max(total, 1)))
        let state = ChapterDownloadActivityAttributes.ContentState(
            completed: clampedCompleted,
            total: max(total, 1),
            statusText: "Downloading"
        )
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end(success: Bool, completed: Int, total: Int) {
        guard #available(iOS 16.1, *) else {
            activity = nil
            return
        }
        guard let activity else { return }
        let clampedCompleted = max(0, min(completed, max(total, 1)))
        let finalState = ChapterDownloadActivityAttributes.ContentState(
            completed: clampedCompleted,
            total: max(total, 1),
            statusText: success ? "Complete" : "Failed"
        )
        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .default
            )
        }
        self.activity = nil
    }

    private func debugLog(_ message: String) {
        print("[LiveActivity] \(message)")
    }
}

@MainActor
final class ReadingLiveActivityManager {
    static let shared = ReadingLiveActivityManager()

    private var activity: Activity<ReadingSessionActivityAttributes>?

    func startOrUpdate(
        novelTitle: String,
        chapterTitle: String,
        currentLine: Int,
        totalLines: Int
    ) async {
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = ReadingSessionActivityAttributes.ContentState(
            chapterTitle: chapterTitle,
            currentLine: max(0, currentLine),
            totalLines: max(totalLines, 1)
        )

        if let activity {
            await activity.update(ActivityContent(state: state, staleDate: nil))
            return
        }

        do {
            let attributes = ReadingSessionActivityAttributes(novelTitle: novelTitle)
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            #if DEBUG
            print("[ReadingLiveActivity] Failed to start: \(error.localizedDescription)")
            #endif
        }
    }

    func end() async {
        guard #available(iOS 16.1, *) else {
            activity = nil
            return
        }
        guard let activity else { return }
        let finalState = activity.content.state
        await activity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: .immediate
        )
        self.activity = nil
    }
}
#else
@MainActor
final class DownloadLiveActivityManager {
    static let shared = DownloadLiveActivityManager()

    func start(novelTitle: String, novelImageURL: String?, total: Int) async {}
    func update(completed: Int, total: Int) {}
    func end(success: Bool, completed: Int, total: Int) {}
}

@MainActor
final class ReadingLiveActivityManager {
    static let shared = ReadingLiveActivityManager()

    func startOrUpdate(
        novelTitle: String,
        chapterTitle: String,
        currentLine: Int,
        totalLines: Int
    ) async {}

    func end() async {}
}
#endif
