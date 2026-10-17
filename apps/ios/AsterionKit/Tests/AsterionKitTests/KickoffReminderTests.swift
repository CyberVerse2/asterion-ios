import Foundation
import Testing
@testable import AsterionKit

struct KickoffReminderTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func remindsFifteenMinutesBeforeAFutureKickoff() {
        let kickoff = now.addingTimeInterval(3 * 60 * 60)
        let fire = KickoffReminder.fireDate(kickoff: kickoff, now: now)
        #expect(fire == kickoff.addingTimeInterval(-15 * 60))
        #expect(KickoffReminder.body(kickoff: kickoff, fireDate: fire!) == "Kicks off in 15 minutes")
    }

    @Test
    func insideTheLeadTimeItRemindsAlmostAtOnce() {
        let kickoff = now.addingTimeInterval(6 * 60)
        let fire = KickoffReminder.fireDate(kickoff: kickoff, now: now)
        #expect(fire == now.addingTimeInterval(5))
        #expect(KickoffReminder.body(kickoff: kickoff, fireDate: fire!) == "Kicks off in 6 minutes")
    }

    @Test
    func startedOrImminentMatchesGetNoReminder() {
        #expect(KickoffReminder.fireDate(kickoff: now.addingTimeInterval(-60), now: now) == nil)
        #expect(KickoffReminder.fireDate(kickoff: now.addingTimeInterval(30), now: now) == nil)
    }

    @Test
    func aMovedKickoffNeedsANewReminder() {
        let kickoff = now.addingTimeInterval(60 * 60)
        #expect(!KickoffReminder.needsReschedule(scheduledKickoff: kickoff, kickoff: kickoff.addingTimeInterval(20)))
        #expect(KickoffReminder.needsReschedule(scheduledKickoff: kickoff, kickoff: kickoff.addingTimeInterval(30 * 60)))
        #expect(KickoffReminder.needsReschedule(scheduledKickoff: nil, kickoff: kickoff))
    }
}
