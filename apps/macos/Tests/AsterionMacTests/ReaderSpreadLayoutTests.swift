import Testing
@testable import AsterionMac

struct ReaderSpreadLayoutTests {
    @Test func oddColumnCountsPadSoTheLastSpreadDoesNotReuseThePreviousRightPage() {
        for columnCount in 1...9 {
            let turnCount = ReaderSpreadLayout.turnCount(columnCount: columnCount)
            var seen = Set<Int>()

            for turn in 0..<turnCount {
                let columns = ReaderSpreadLayout.contentColumns(
                    forTurn: turn,
                    contentColumnCount: columnCount
                )
                for column in columns {
                    #expect(
                        seen.insert(column).inserted,
                        "Column \(column) repeated at turn \(turn) of \(columnCount) columns"
                    )
                }
            }

            #expect(seen == Set(0..<columnCount))
            #expect(ReaderSpreadLayout.needsTrailingColumnPad(columnCount) == (columnCount % 2 == 1))
        }
    }

    @Test func laterTurnsSnapToWholeSpreadsWithoutAnInsetShift() {
        let viewportWidth = 1_440.0
        let gap = ReaderSpreadLayout.gap(viewportWidth: viewportWidth)
        let pageWidth = ReaderSpreadLayout.pageWidth(viewportWidth: viewportWidth, gap: gap)
        let pageUnit = ReaderSpreadLayout.pageUnit(pageWidth: pageWidth, gap: gap)
        let turnUnit = ReaderSpreadLayout.turnUnit(pageUnit: pageUnit)
        let columnCount = ReaderSpreadLayout.paddedColumnCount(5)
        let turnCount = ReaderSpreadLayout.turnCount(columnCount: columnCount)
        let maxX = Double(columnCount - 2) * pageUnit

        #expect(turnCount == 3)
        #expect(ReaderSpreadLayout.scrollX(turn: 0, turnUnit: turnUnit, maxX: maxX) == 0)
        #expect(ReaderSpreadLayout.scrollX(turn: 1, turnUnit: turnUnit, maxX: maxX) == turnUnit)
        #expect(ReaderSpreadLayout.scrollX(turn: 2, turnUnit: turnUnit, maxX: maxX) == turnUnit * 2)
        #expect(ReaderSpreadLayout.turnIndex(scrollX: turnUnit, turnUnit: turnUnit, turnCount: turnCount) == 1)
    }
}

struct ReaderSpreadKeyboardTests {
    @Test func unmodifiedArrowsAndPagingKeysTurnTheSpread() {
        #expect(
            ReaderSpreadKeyboardCommand.resolve(keyCode: 123, modifiers: []) == .turn(-1)
        )
        #expect(
            ReaderSpreadKeyboardCommand.resolve(keyCode: 124, modifiers: []) == .turn(1)
        )
        #expect(
            ReaderSpreadKeyboardCommand.resolve(keyCode: 116, modifiers: []) == .turn(-1)
        )
        #expect(
            ReaderSpreadKeyboardCommand.resolve(keyCode: 121, modifiers: []) == .turn(1)
        )
        #expect(
            ReaderSpreadKeyboardCommand.resolve(keyCode: 49, modifiers: []) == .turn(1)
        )
    }

    @Test func commandArrowsStayAvailableForChapterShortcuts() {
        #expect(
            ReaderSpreadKeyboardCommand.resolve(keyCode: 124, modifiers: [.command]) == nil
        )
    }
}
