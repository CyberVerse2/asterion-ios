import Foundation
import UserNotifications

/// Local kickoff reminders for football matches, scheduled from the fixture time.
@MainActor
enum KickoffReminderService {
    enum Outcome { case scheduled, denied, tooLate, unavailable }

    /// Notification Center needs a bundled app; `swift run` and test hosts have none.
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    private static var center: UNUserNotificationCenter { .current() }

    static func isScheduled(matchID: String) async -> Bool {
        await pending(matchID: matchID) != nil
    }

    static func schedule(matchID: String, title: String, kickoff: Date) async throws -> Outcome {
        guard isAvailable else { return .unavailable }
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
        guard isAvailable else { return }
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
        guard isAvailable else { return nil }
        let identifier = KickoffReminder.identifier(matchID: matchID)
        return await center.pendingNotificationRequests().first { $0.identifier == identifier }
    }
}
