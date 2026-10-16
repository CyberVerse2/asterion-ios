import Foundation
import Testing
@testable import AsterionKit

struct NovelLibraryLedgerTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func remote(_ ids: String..., at date: Date? = nil) -> [NovelLibraryEntry] {
        ids.map { NovelLibraryEntry(novelId: $0, addedAt: date ?? t0) }
    }

    @Test
    func guestSavesJoinTheAccountOnSignIn() {
        var guest = NovelLibraryLedger()
        guest.add("guest-a", novel: catalogNovel("guest-a"), at: t0.addingTimeInterval(10))
        guest.add("shared", at: t0.addingTimeInterval(20))

        var account = NovelLibraryLedger()
        account.adopt(guest: guest)
        // The account's list arrives before the queued adds are sent.
        account.applyAccount(remote("shared", "account-only"))

        #expect(Set(account.novelIds) == ["guest-a", "shared", "account-only"])
        #expect(Set(account.pending.map(\.novelId)) == ["guest-a", "shared"])
        #expect(account.pending.allSatisfy { $0.kind == .add })
        // The guest's catalog snapshot travels with the save.
        #expect(account.entry(for: "guest-a")?.novel?.id == "guest-a")
    }

    @Test
    func anOfflineRemovalSurvivesARefreshUntilTheAccountConfirmsIt() {
        var ledger = NovelLibraryLedger()
        ledger.applyAccount(remote("a", "b"))
        ledger.remove("a", at: t0.addingTimeInterval(5))

        ledger.applyAccount(remote("a", "b"))
        #expect(ledger.novelIds == ["b"])

        let removal = ledger.pending[0]
        ledger.acknowledge(removal)
        ledger.applyAccount(remote("b"))
        #expect(ledger.novelIds == ["b"])
        #expect(ledger.pending.isEmpty)
    }

    @Test
    func savingAgainWhileARemovalIsInFlightKeepsTheNewerSave() {
        var ledger = NovelLibraryLedger()
        ledger.applyAccount(remote("a"))
        ledger.remove("a", at: t0.addingTimeInterval(5))
        let inFlight = ledger.pending[0]
        ledger.add("a", at: t0.addingTimeInterval(6))

        // The removal's confirmation lands after the user saved it again.
        ledger.acknowledge(inFlight)
        ledger.applyAccount([])

        #expect(ledger.contains("a"))
        #expect(ledger.pending.map(\.kind) == [.add])
    }

    @Test
    func aLaterAccountRemovalBeatsAnOlderGuestSave() {
        var guest = NovelLibraryLedger()
        guest.add("a", at: t0.addingTimeInterval(1))

        var account = NovelLibraryLedger()
        account.applyAccount(remote("a"))
        account.remove("a", at: t0.addingTimeInterval(50))
        account.adopt(guest: guest)

        #expect(!account.contains("a"))
        #expect(account.pending.map(\.kind) == [.remove])
    }

    @Test
    func refreshingKeepsStoredCoversForNovelsTheAccountSendsBare() {
        var ledger = NovelLibraryLedger()
        ledger.add("a", novel: catalogNovel("a"), at: t0)
        ledger.acknowledge(ledger.pending[0])
        ledger.applyAccount(remote("a"))

        #expect(ledger.entry(for: "a")?.novel != nil)
    }

    @Test
    func newestSavesComeFirst() {
        var ledger = NovelLibraryLedger()
        ledger.add("old", at: t0)
        ledger.add("new", at: t0.addingTimeInterval(60))
        #expect(ledger.novelIds == ["new", "old"])
    }
}

struct FollowUpPassQueueTests {
    @Test
    func aRequestDuringAPassRunsOnceItEndsWithTheNewestInputs() {
        var queue = FollowUpPassQueue<String>()
        #expect(queue.request("episodes only") == "episodes only")
        #expect(queue.request("with novels") == nil)
        #expect(queue.request("with novels, newer") == nil)

        #expect(queue.finish() == "with novels, newer")
        #expect(queue.isRunning)
        #expect(queue.finish() == nil)
        #expect(!queue.isRunning)
        // Idle again: the next request starts straight away.
        #expect(queue.request("later") == "later")
    }

    @Test
    func waitingRequestsMergeSoAForcedRefreshIsNotLost() {
        var queue = FollowUpPassQueue<(name: String, force: Bool)>()
        _ = queue.request(("first", false))
        let merge: ((name: String, force: Bool), (name: String, force: Bool)) -> (name: String, force: Bool) = {
            ($1.name, $0.force || $1.force)
        }
        _ = queue.request(("pulled to refresh", true), merge: merge)
        _ = queue.request(("newest", false), merge: merge)

        let next = queue.finish()
        #expect(next?.name == "newest")
        #expect(next?.force == true)
    }
}

struct ListenSleepScheduleTests {
    private let start = Date(timeIntervalSince1970: 10_000)

    @Test
    func aTimedScheduleEndsTheChosenMinutesAfterItStarts() {
        let schedule = ListenSleepSchedule(.minutes(30), startingAt: start)
        #expect(schedule.endsAt == start.addingTimeInterval(30 * 60))
        #expect(!schedule.isDue(at: start.addingTimeInterval(30 * 60 - 1)))
        #expect(schedule.isDue(at: start.addingTimeInterval(30 * 60)))
        #expect(!schedule.stopsAtChapterEnd)
    }

    @Test
    func endOfChapterHasNoDeadline() {
        let schedule = ListenSleepSchedule(.endOfChapter, startingAt: start)
        #expect(schedule.endsAt == nil)
        #expect(schedule.remaining(at: start.addingTimeInterval(1e6)) == nil)
        #expect(!schedule.isDue(at: start.addingTimeInterval(1e6)))
        #expect(schedule.stopsAtChapterEnd)
    }

    @Test
    func theCountdownRoundsUpAndNeverGoesNegative() {
        let schedule = ListenSleepSchedule(.minutes(15), startingAt: start)
        #expect(schedule.shortLabel(at: start) == "15m")
        #expect(schedule.shortLabel(at: start.addingTimeInterval(14 * 60 + 30)) == "1m")
        #expect(schedule.remaining(at: start.addingTimeInterval(20 * 60)) == 0)
        #expect(ListenSleepSchedule(.endOfChapter, startingAt: start).shortLabel(at: start) == nil)
    }
}
