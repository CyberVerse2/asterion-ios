import AppIntents
import Foundation

struct ContinueReadingSnapshot: Codable, Hashable {
    let novelId: String
    let novelTitle: String
    let chapterId: String
    let chapterTitle: String
    let chapterNumber: Int
    let progress: Double
    let updatedAt: Date
}

enum ContinueReadingStore {
    static let appGroupIdentifier = "group.cyberverse.Asterion"
    private static let snapshotKey = "continueReading.snapshot"
    private static let pendingLaunchKey = "continueReading.pendingLaunch"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static func loadSnapshot() -> ContinueReadingSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(ContinueReadingSnapshot.self, from: data)
    }

    static func saveSnapshot(_ snapshot: ContinueReadingSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: snapshotKey)
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
