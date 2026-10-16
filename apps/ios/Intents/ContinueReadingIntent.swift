import AppIntents
import AsterionKit
import Foundation
import ImageIO
import UIKit
import WidgetKit

enum ContinueReadingStore {
    static let appGroupIdentifier = "group.cyberverse.Asterion"
    private static let snapshotKey = "continueReading.snapshot"
    private static let pendingLaunchKey = "continueReading.pendingLaunch"
    private static let coverAttemptKey = "continueReading.coverAttempt"
    private static let coverMaxBytes = 60_000

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static func loadSnapshot() -> ContinueReadingSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(ContinueReadingSnapshot.self, from: data)
    }

    /// Saves the snapshot. When it names a `coverURL` but carries no image,
    /// the previously stored cover for the same novel is kept; if there is
    /// none, a small thumbnail is fetched once in the background and the
    /// widget timelines are reloaded when it lands.
    static func saveSnapshot(_ snapshot: ContinueReadingSnapshot) {
        var resolved = snapshot
        if resolved.coverImageData == nil, let coverURL = resolved.coverURL, !coverURL.isEmpty,
           let previous = loadSnapshot(),
           previous.novelId == resolved.novelId,
           previous.coverURL == coverURL,
           let previousData = previous.coverImageData {
            resolved = resolved.with(coverImageData: previousData)
        }
        if let data = resolved.coverImageData, data.count > coverMaxBytes {
            resolved = resolved.with(coverImageData: nil)
        }
        write(resolved)

        if resolved.coverImageData == nil, let coverURL = resolved.coverURL, !coverURL.isEmpty {
            fetchCoverIfNeeded(novelId: resolved.novelId, coverURL: coverURL)
        }
    }

    private static func write(_ snapshot: ContinueReadingSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: snapshotKey)
    }

    /// One attempt per cover every ten minutes, so a failing host does not
    /// get hit on every scroll tick.
    private static func fetchCoverIfNeeded(novelId: String, coverURL: String) {
        let attempt = defaults?.dictionary(forKey: coverAttemptKey)
        if let last = attempt?["url"] as? String, last == coverURL,
           let at = attempt?["at"] as? Double,
           Date().timeIntervalSince1970 - at < 600 {
            return
        }
        defaults?.set(["url": coverURL, "at": Date().timeIntervalSince1970], forKey: coverAttemptKey)

        Task { @MainActor in
            guard let data = await downloadCoverThumbnail(from: coverURL) else { return }
            guard let current = loadSnapshot(),
                  current.novelId == novelId,
                  current.coverURL == coverURL,
                  current.coverImageData == nil else { return }
            write(current.with(coverImageData: data))
            WidgetCenter.shared.reloadTimelines(ofKind: "ReadingWidget")
        }
    }

    /// Downloads and downsamples a cover to a JPEG under 60 KB (longest side
    /// 360 px, enough for a 2:3 cover in the medium widget at 3x).
    nonisolated static func downloadCoverThumbnail(from rawURL: String) async -> Data? {
        guard let url = normalizedCoverURL(rawURL) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              !data.isEmpty else {
            return nil
        }
        return coverThumbnailData(from: data)
    }

    nonisolated static func coverThumbnailData(from imageData: Data, maxPixelSize: Int = 360) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = UIImage(cgImage: cgImage)
        for quality in [0.75, 0.6, 0.45, 0.3] {
            if let jpeg = image.jpegData(compressionQuality: quality), jpeg.count <= 60_000 {
                return jpeg
            }
        }
        return maxPixelSize > 180 ? coverThumbnailData(from: imageData, maxPixelSize: 180) : nil
    }

    nonisolated private static func normalizedCoverURL(_ raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("//") {
            value = "https:\(value)"
        } else if !value.contains("://") {
            value = "https://\(value)"
        } else if value.hasPrefix("http://") {
            value = "https://" + value.dropFirst("http://".count)
        }
        if let url = URL(string: value) { return url }
        return value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(URL.init(string:))
    }

    static func requestLaunch() {
        defaults?.set(Date().timeIntervalSince1970, forKey: pendingLaunchKey)
    }

    static func consumePendingLaunchRequest() -> Bool {
        guard defaults?.object(forKey: pendingLaunchKey) != nil else { return false }
        defaults?.removeObject(forKey: pendingLaunchKey)
        return true
    }
}

extension Notification.Name {
    static let asterionContinueReadingRequested = Notification.Name("AsterionContinueReadingRequested")
}

struct ContinueReadingIntent: AppIntent {
    static var title: LocalizedStringResource = "Continue Reading"
    static var description = IntentDescription("Open Asterion and continue your latest chapter.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        let hasSnapshot = await MainActor.run {
            ContinueReadingStore.loadSnapshot() != nil
        }
        if hasSnapshot {
            await MainActor.run {
                ContinueReadingStore.requestLaunch()
            }
        }
        return .result()
    }
}

struct ReadingWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Reading Widget"
    static var description = IntentDescription("Configure your reading progress widget.")
}
