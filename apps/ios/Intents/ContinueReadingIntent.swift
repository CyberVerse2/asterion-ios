import AppIntents
import Foundation
import ImageIO
import UIKit
import WidgetKit

/// Where a reader is in a whole novel.
///
/// Saved reading progress only records the position inside the current
/// chapter. Combined with the chapter's number and the novel's chapter count
/// it gives the whole-novel fraction, the "Ch. 1929 of 3171" label every
/// novel surface shows, and whether the novel is finished. It lives here
/// because the widget extension compiles this file too.
nonisolated struct NovelProgress: Equatable, Sendable {
    /// How far into the last chapter counts as having finished the novel.
    static let finishedChapterPercentage = 95.0

    /// The current chapter's number, when it is known.
    let chapterNumber: Int?
    /// How many chapters the novel has, when it is known.
    let totalChapters: Int?
    /// Position inside the current chapter, 0–100.
    let chapterPercentage: Double

    init(chapterNumber: Int?, totalChapters: Int?, chapterPercentage: Double) {
        self.chapterNumber = chapterNumber.flatMap { $0 > 0 ? $0 : nil }
        self.totalChapters = totalChapters.flatMap { $0 > 0 ? $0 : nil }
        self.chapterPercentage = chapterPercentage.isFinite
            ? min(100, max(0, chapterPercentage))
            : 0
    }

    /// The best known chapter count: a loaded count wins because the
    /// catalog's can lag, then the catalog's text ("3171", "3,171").
    static func totalChapters(loaded: Int? = nil, catalog: String?) -> Int? {
        if let loaded, loaded > 0 { return loaded }
        guard let catalog else { return nil }
        let digits = catalog.filter(\.isASCII).filter(\.isNumber)
        guard let count = Int(digits), count > 0 else { return nil }
        return count
    }

    /// The in-chapter percentage for a saved line. Reaching the chapter's
    /// last paragraph counts as reading all of it: the reader saves the
    /// paragraph at the top of the page, whose index never reaches the count.
    static func chapterPercentage(currentLine: Int, totalLines: Int, saved: Double? = nil) -> Double {
        if totalLines > 1, currentLine >= totalLines - 1 { return 100 }
        if let saved { return saved }
        return totalLines > 0 ? Double(currentLine) / Double(totalLines) * 100 : 0
    }

    /// Position inside the current chapter, 0–1.
    var chapterFraction: Double { chapterPercentage / 100 }

    /// The chapter count used for arithmetic. A chapter beyond the reported
    /// count means the count lags, so the chapter itself bounds it.
    private var effectiveTotal: Int? {
        guard let totalChapters else { return nil }
        guard let chapterNumber else { return totalChapters }
        return max(totalChapters, chapterNumber)
    }

    /// Whether the whole-novel position is known (chapter and count).
    var knowsWholeNovel: Bool { chapterNumber != nil && effectiveTotal != nil }

    /// How far through the whole novel, 0–1. Until the chapter number and the
    /// chapter count are both known it falls back to the in-chapter position.
    var fraction: Double {
        guard let chapterNumber, let total = effectiveTotal else { return chapterFraction }
        if isFinished { return 1 }
        return min(1, max(0, (Double(chapterNumber - 1) + chapterFraction) / Double(total)))
    }

    /// `fraction` as a whole percentage, rounded down so an unfinished novel
    /// never reads 100%.
    var displayPercentage: Int {
        isFinished ? 100 : min(99, Int((fraction * 100).rounded(.down)))
    }

    /// "Ch. 1929 of 3171", "Ch. 1929" without a count, or nil without a
    /// chapter. Numbers are never grouped with separators.
    var label: String? {
        guard let chapterNumber else { return nil }
        guard let total = effectiveTotal else { return "Ch. " + String(chapterNumber) }
        return "Ch. " + String(chapterNumber) + " of " + String(total)
    }

    /// "Chapter 1929 of 3171" for VoiceOver and roomier captions.
    var longLabel: String? {
        guard let chapterNumber else { return nil }
        guard let total = effectiveTotal else { return "Chapter " + String(chapterNumber) }
        return "Chapter " + String(chapterNumber) + " of " + String(total)
    }

    /// On the last chapter and at least 95% through it.
    var isFinished: Bool {
        guard let chapterNumber, let total = effectiveTotal else { return false }
        return chapterNumber >= total && chapterPercentage >= Self.finishedChapterPercentage
    }
}

struct ContinueReadingSnapshot: Codable, Hashable {
    let novelId: String
    let novelTitle: String
    let chapterId: String
    let chapterTitle: String
    let chapterNumber: Int
    /// Whole-novel progress, 0–1. Snapshots written before `chapterProgress`
    /// existed stored the in-chapter position here instead.
    let progress: Double
    /// Position inside the current chapter, 0–1.
    let chapterProgress: Double?
    /// The novel's chapter count when the snapshot was written.
    let totalChapters: Int?
    let updatedAt: Date
    /// Remote cover, used to fetch `coverImageData` for the widgets.
    let coverURL: String?
    /// Small downsampled JPEG (< 60 KB). Widgets cannot load remote images
    /// reliably, so the cover rides along with the snapshot.
    let coverImageData: Data?

    init(
        novelId: String,
        novelTitle: String,
        chapterId: String,
        chapterTitle: String,
        chapterNumber: Int,
        progress: Double,
        chapterProgress: Double? = nil,
        totalChapters: Int? = nil,
        updatedAt: Date,
        coverURL: String? = nil,
        coverImageData: Data? = nil
    ) {
        self.novelId = novelId
        self.novelTitle = novelTitle
        self.chapterId = chapterId
        self.chapterTitle = chapterTitle
        self.chapterNumber = chapterNumber
        self.progress = progress
        self.chapterProgress = chapterProgress
        self.totalChapters = totalChapters
        self.updatedAt = updatedAt
        self.coverURL = coverURL
        self.coverImageData = coverImageData
    }

    private enum CodingKeys: String, CodingKey {
        case novelId, novelTitle, chapterId, chapterTitle, chapterNumber, progress, updatedAt
        case chapterProgress, totalChapters
        case coverURL, coverImageData
    }

    /// Snapshots stored before covers existed still decode.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        novelId = try values.decode(String.self, forKey: .novelId)
        novelTitle = try values.decode(String.self, forKey: .novelTitle)
        chapterId = try values.decode(String.self, forKey: .chapterId)
        chapterTitle = try values.decode(String.self, forKey: .chapterTitle)
        chapterNumber = try values.decodeIfPresent(Int.self, forKey: .chapterNumber) ?? 0
        progress = try values.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        chapterProgress = try values.decodeIfPresent(Double.self, forKey: .chapterProgress)
        totalChapters = try values.decodeIfPresent(Int.self, forKey: .totalChapters)
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        coverURL = try values.decodeIfPresent(String.self, forKey: .coverURL)
        coverImageData = try values.decodeIfPresent(Data.self, forKey: .coverImageData)
    }

    func with(coverImageData data: Data?) -> ContinueReadingSnapshot {
        ContinueReadingSnapshot(
            novelId: novelId,
            novelTitle: novelTitle,
            chapterId: chapterId,
            chapterTitle: chapterTitle,
            chapterNumber: chapterNumber,
            progress: progress,
            chapterProgress: chapterProgress,
            totalChapters: totalChapters,
            updatedAt: updatedAt,
            coverURL: coverURL,
            coverImageData: data
        )
    }

    /// Position inside the current chapter, 0–1, for snapshots old and new.
    var inChapterFraction: Double { chapterProgress ?? progress }

    /// The snapshot's place in the whole novel. Snapshots from before the
    /// chapter count was recorded fall back to the in-chapter position.
    var novelProgress: NovelProgress {
        NovelProgress(
            chapterNumber: chapterNumber,
            totalChapters: totalChapters,
            chapterPercentage: inChapterFraction * 100
        )
    }
}

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
