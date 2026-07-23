import Testing
@testable import AsterionMac

struct ChapterOverscrollGateTests {
    @Test func reachingBottomDoesNotImmediatelyAdvance() {
        var gate = ChapterOverscrollGate()
        gate.update(isAtBottom: true, timestamp: 10)

        let shouldAdvance = gate.shouldAdvance(
            isScrollingDown: true,
            beganGesture: false,
            isMomentum: false,
            timestamp: 10.1
        )
        #expect(!shouldAdvance)
    }

    @Test func aNewDownwardGestureAtBottomAdvances() {
        var gate = ChapterOverscrollGate()
        gate.update(isAtBottom: true, timestamp: 10)

        let shouldAdvance = gate.shouldAdvance(
            isScrollingDown: true,
            beganGesture: true,
            isMomentum: false,
            timestamp: 10.1
        )
        #expect(shouldAdvance)
    }

    @Test func momentumAndUpwardScrollingNeverAdvance() {
        var gate = ChapterOverscrollGate()
        gate.update(isAtBottom: true, timestamp: 10)

        let momentumAdvance = gate.shouldAdvance(
            isScrollingDown: true,
            beganGesture: false,
            isMomentum: true,
            timestamp: 11
        )
        let upwardAdvance = gate.shouldAdvance(
            isScrollingDown: false,
            beganGesture: true,
            isMomentum: false,
            timestamp: 11
        )
        #expect(!momentumAdvance)
        #expect(!upwardAdvance)
    }

    @Test func leavingTheBottomDisarmsNavigation() {
        var gate = ChapterOverscrollGate()
        gate.update(isAtBottom: true, timestamp: 10)
        gate.update(isAtBottom: false, timestamp: 10.1)

        let shouldAdvance = gate.shouldAdvance(
            isScrollingDown: true,
            beganGesture: true,
            isMomentum: false,
            timestamp: 10.2
        )
        #expect(!shouldAdvance)
    }
}
