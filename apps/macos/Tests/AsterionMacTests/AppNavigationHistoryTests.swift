import Testing
@testable import AsterionMac

struct AppNavigationHistoryTests {
    @Test func backReturnsThroughVisitedSections() {
        var history = AppNavigationHistory()

        history.recordNavigation(from: .home, to: .novels)
        history.recordNavigation(from: .novels, to: .anime)

        #expect(history.destinationForBack(from: .anime) == .novels)
        #expect(history.destinationForBack(from: .novels) == .home)
    }

    @Test func everyTopLevelSectionCanFallBackHome() {
        for destination in AppDestination.allCases where destination != .home {
            var history = AppNavigationHistory()
            #expect(history.destinationForBack(from: destination) == .home)
        }
    }

    @Test func choosingHomeResetsEarlierHistory() {
        var history = AppNavigationHistory()

        history.recordNavigation(from: .home, to: .movies)
        history.recordNavigation(from: .movies, to: .football)
        history.recordNavigation(from: .football, to: .home)
        history.recordNavigation(from: .home, to: .downloads)

        #expect(history.destinationForBack(from: .downloads) == .home)
        #expect(history.destinationForBack(from: .home) == nil)
    }

    @Test func repeatedSelectionDoesNotAddAHistoryEntry() {
        var history = AppNavigationHistory()

        history.recordNavigation(from: .bookmarks, to: .bookmarks)

        #expect(history.previousDestination == nil)
    }
}
