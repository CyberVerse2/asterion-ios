import ActivityKit
import Foundation
import UIKit

@MainActor
final class DownloadLiveActivityManager {
    static let shared = DownloadLiveActivityManager()

    private var activity: Activity<ChapterDownloadActivityAttributes>?

    func start(novelTitle: String, novelImageURL: String?, total: Int) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard #available(iOS 16.1, *) else { return }

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
        }

        do {
            let normalizedURL = normalizedImageURLString(novelImageURL)
            let imageData = await fetchThumbnailData(from: normalizedURL)
            let attrs = ChapterDownloadActivityAttributes(
                novelTitle: novelTitle,
                novelImageURL: normalizedURL,
                novelImageData: imageData
            )
            let state = ChapterDownloadActivityAttributes.ContentState(
                completed: 0,
                total: max(total, 1),
                statusText: "Preparing"
            )
            activity = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            activity = nil
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

    private func fetchThumbnailData(from normalizedURL: String?) async -> Data? {
        guard let normalizedURL, let url = URL(string: normalizedURL) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
            guard !data.isEmpty else { return nil }

            // Keep payload modest for Activity attributes.
            if data.count <= 240_000 {
                return data
            }

            guard let image = UIImage(data: data),
                  let compressed = image.jpegData(compressionQuality: 0.5)
            else {
                return nil
            }
            return compressed.count <= 240_000 ? compressed : nil
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
}
