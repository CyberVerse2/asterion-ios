import Foundation

enum ReaderSpreadLayout {
    static func gap(viewportWidth: Double) -> Double {
        min(48, max(20, (viewportWidth * 0.025).rounded()))
    }

    static func pageWidth(viewportWidth: Double, gap: Double) -> Double {
        max(320, floor((viewportWidth - gap) / 2))
    }

    static func pageUnit(pageWidth: Double, gap: Double) -> Double {
        pageWidth + gap
    }

    static func turnUnit(pageUnit: Double) -> Double {
        pageUnit * 2
    }

    static func columnCount(scrollWidth: Double, pageUnit: Double, gap: Double) -> Int {
        guard pageUnit > 0 else { return 1 }
        return max(1, Int(((scrollWidth + gap) / pageUnit).rounded()))
    }

    static func paddedColumnCount(_ contentColumnCount: Int) -> Int {
        max(1, contentColumnCount + contentColumnCount % 2)
    }

    static func turnCount(columnCount: Int) -> Int {
        max(1, paddedColumnCount(columnCount) / 2)
    }

    static func needsTrailingColumnPad(_ contentColumnCount: Int) -> Bool {
        contentColumnCount % 2 == 1
    }

    static func scrollX(turn: Int, turnUnit: Double, maxX: Double) -> Double {
        min(maxX, max(0, Double(max(0, turn)) * turnUnit))
    }

    static func turnIndex(scrollX: Double, turnUnit: Double, turnCount: Int) -> Int {
        guard turnUnit > 0, turnCount > 0 else { return 0 }
        return max(0, min(turnCount - 1, Int((scrollX / turnUnit).rounded())))
    }

    static func contentColumns(forTurn turn: Int, contentColumnCount: Int) -> [Int] {
        let padded = paddedColumnCount(contentColumnCount)
        let start = turn * 2
        return [start, start + 1].filter { $0 < contentColumnCount && $0 < padded }
    }
}
