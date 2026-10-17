import Foundation
import Testing
@testable import AsterionMac

struct FootballScoreTests {
    @Test
    func decodesTheServiceShapeAndLabelsTheClock() throws {
        let json = #"{"home":2,"away":1,"status":"live","minute":90,"injuryTime":3,"competition":"Premier League","delayed":true,"updatedAt":null}"#
        let score = try JSONDecoder().decode(FootballScore.self, from: Data(json.utf8))
        #expect(score.scoreline == "2 – 1")
        #expect(score.clockLabel == "90+3'")
        #expect(score.isInPlay)
    }

    @Test
    func unknownStatusesReadAsScheduledInsteadOfFailingTheList() throws {
        let json = #"{"home":null,"away":null,"status":"extra_time_soon","minute":null,"injuryTime":null,"competition":null,"delayed":true}"#
        let score = try JSONDecoder().decode(FootballScore.self, from: Data(json.utf8))
        #expect(score.status == .scheduled)
        #expect(score.scoreline == nil)
        #expect(score.clockLabel == nil)
    }

    @Test
    func halfAndFullTime() {
        #expect(FootballScore(home: 0, away: 0, status: .halftime).clockLabel == "HT")
        #expect(FootballScore(home: 3, away: 2, status: .finished).accessibilityText(home: "Arsenal", away: "Chelsea")
            == "Arsenal 3, Chelsea 2, full time")
    }
}
