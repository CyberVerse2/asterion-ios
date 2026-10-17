import AsterionKit
import BackgroundTasks
import Combine
import Foundation
import UserNotifications

@MainActor
final class ContentNotificationService: ObservableObject {
    static let shared = ContentNotificationService()
    static let refreshIdentifier = "cyberverse.Asterion.content-refresh"
    @Published var openTarget: ContentWatchTarget?
    @Published private(set) var chapterAlerts: Bool
    @Published private(set) var episodeAlerts: Bool
    @Published private(set) var permissionDenied = false
    @Published private(set) var statusMessage: String?
    private let defaults = UserDefaults.standard
    private let center = UNUserNotificationCenter.current()
    private var targets: [ContentWatchTarget] = []
    private var baselines: [String: Int] = [:]
    private var checking = false
    private var lastCheck: Date?

    private init() {
        chapterAlerts = defaults.object(forKey: "asterion.alerts.chapters") as? Bool ?? true
        episodeAlerts = defaults.object(forKey: "asterion.alerts.episodes") as? Bool ?? true
        targets = defaults.data(forKey: "asterion.alerts.targets").flatMap {
            try? JSONDecoder().decode([ContentWatchTarget].self, from: $0)
        } ?? []
        baselines = defaults.dictionary(forKey: "asterion.alerts.baselines") as? [String: Int] ?? [:]
    }

    func setUser(_ userID: String?) {
        let user = userID ?? "guest"
        guard defaults.string(forKey: "asterion.alerts.user") != user else { return }
        defaults.set(user, forKey: "asterion.alerts.user")
        targets = []
        baselines = [:]
        lastCheck = nil
        persist()
    }

    func replaceTargets(kind: ContentWatchTarget.Kind, with replacements: [ContentWatchTarget]) {
        let oldIDs = Set(targets.filter { $0.kind == kind }.map(\.id))
        let newIDs = Set(replacements.map(\.id))
        if oldIDs != newIDs { lastCheck = nil }
        for id in oldIDs.subtracting(newIDs) {
            baselines.removeValue(forKey: id)
            center.removePendingNotificationRequests(withIdentifiers: ["content-\(id)"])
        }
        targets.removeAll { $0.kind == kind }
        var seen = Set<String>()
        targets.append(contentsOf: replacements.filter { seen.insert($0.id).inserted })
        persist()
    }

    func setEnabled(_ enabled: Bool, kind: ContentWatchTarget.Kind, askPermission: Bool = true) async {
        if kind == .novel {
            chapterAlerts = enabled
            defaults.set(enabled, forKey: "asterion.alerts.chapters")
        } else {
            episodeAlerts = enabled
            defaults.set(enabled, forKey: "asterion.alerts.episodes")
        }
        if !enabled {
            center.removePendingNotificationRequests(withIdentifiers:
                targets.filter { $0.kind == kind }.map { "content-\($0.id)" })
        } else if askPermission {
            await requestPermissionIfNeeded()
            await checkForUpdates(force: true)
        }
        scheduleRefresh()
    }

    func requestPermissionIfNeeded() async {
        guard chapterAlerts || episodeAlerts else { return }
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined, !targets.isEmpty {
            do { _ = try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
            catch { statusMessage = "Notification permission could not be requested." }
            settings = await center.notificationSettings()
        }
        permissionDenied = settings.authorizationStatus == .denied
        statusMessage = permissionDenied ? "Allow notifications in Settings to receive new-content alerts." : nil
    }

    func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshIdentifier, using: .main) { task in
            let work = Task { @MainActor in
                Self.shared.scheduleRefresh()
                await Self.shared.checkForUpdates(force: true)
                task.setTaskCompleted(success: !Task.isCancelled)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    func scheduleRefresh() {
        guard !targets.isEmpty, chapterAlerts || episodeAlerts else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshIdentifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { /* Background refresh may be disabled by the device. Foreground checks still run. */ }
    }

    func checkForUpdates(force: Bool = false) async {
        guard !checking else { return }
        if !force, let lastCheck, Date().timeIntervalSince(lastCheck) < 15 * 60 { return }
        checking = true
        defer { checking = false }
        let settings = await center.notificationSettings()
        let permitted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        let api = APIClient()
        for target in targets {
            guard !Task.isCancelled else { return }
            let enabled = target.kind == .novel ? chapterAlerts : episodeAlerts
            guard enabled else { continue }
            let count: Int
            do {
                if target.kind == .novel {
                    let novel = try await api.fetchNovel(id: target.contentID)
                    guard let value = Int(novel.totalChapters?.filter(\.isNumber) ?? "") else { continue }
                    count = value
                } else {
                    let show = try await EntertainmentAPI.shared.fetchAnimeShow(slug: target.contentID)
                    let episodes = try await EntertainmentAPI.shared.fetchAnimeEpisodes(showID: show.id)
                    count = episodes.count
                }
            } catch { continue }
            guard !Task.isCancelled, targets.contains(where: { $0.id == target.id }) else { continue }
            if permitted, let added = ContentUpdatePolicy.newCount(current: count, previous: baselines[target.id]) {
                let content = UNMutableNotificationContent()
                content.title = target.title
                let unit = target.kind == .novel ? "chapter" : "episode"
                content.body = "\(added) new \(unit)\(added == 1 ? "" : "s") available."
                content.sound = .default
                content.userInfo = ["asterionContentKind": target.kind.rawValue,
                                    "asterionContentID": target.contentID, "asterionContentTitle": target.title]
                do {
                    try await center.add(UNNotificationRequest(identifier: "content-\(target.id)", content: content, trigger: nil))
                } catch { continue }
            }
            baselines[target.id] = ContentUpdatePolicy.nextBaseline(current: count, previous: baselines[target.id])
            persist()
        }
        lastCheck = .now
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(targets) { defaults.set(data, forKey: "asterion.alerts.targets") }
        defaults.set(baselines, forKey: "asterion.alerts.baselines")
    }
}

/// Local kickoff reminders for football matches, scheduled from the fixture time.
@MainActor
enum KickoffReminderService {
    enum Outcome { case scheduled, denied, tooLate }

    private static var center: UNUserNotificationCenter { .current() }

    static func isScheduled(matchID: String) async -> Bool {
        await pending(matchID: matchID) != nil
    }

    static func schedule(matchID: String, title: String, kickoff: Date) async throws -> Outcome {
        guard let fireDate = KickoffReminder.fireDate(kickoff: kickoff) else { return .tooLate }
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
            settings = await center.notificationSettings()
        }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return .denied
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = KickoffReminder.body(kickoff: kickoff, fireDate: fireDate)
        content.sound = .default
        content.userInfo = [KickoffReminder.matchIDKey: matchID,
                            KickoffReminder.kickoffKey: kickoff.timeIntervalSince1970]
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, fireDate.timeIntervalSinceNow), repeats: false)
        try await center.add(UNNotificationRequest(
            identifier: KickoffReminder.identifier(matchID: matchID), content: content, trigger: trigger))
        return .scheduled
    }

    static func cancel(matchID: String) {
        center.removePendingNotificationRequests(withIdentifiers: [KickoffReminder.identifier(matchID: matchID)])
    }

    /// Moves a pending reminder when the fixture's kickoff changed, and drops it once it is too late.
    static func refresh(matchID: String, title: String, kickoff: Date) async {
        guard let request = await pending(matchID: matchID) else { return }
        let scheduled = (request.content.userInfo[KickoffReminder.kickoffKey] as? TimeInterval)
            .map(Date.init(timeIntervalSince1970:))
        guard KickoffReminder.needsReschedule(scheduledKickoff: scheduled, kickoff: kickoff) else { return }
        cancel(matchID: matchID)
        _ = try? await schedule(matchID: matchID, title: title, kickoff: kickoff)
    }

    private static func pending(matchID: String) async -> UNNotificationRequest? {
        let identifier = KickoffReminder.identifier(matchID: matchID)
        return await center.pendingNotificationRequests().first { $0.identifier == identifier }
    }
}
