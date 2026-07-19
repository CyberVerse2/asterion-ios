import Foundation
import Testing
@testable import AsterionMac

struct CaptionSizingTests {
    @Test func subtitleSizeScalesWithPlayerHeight() {
        let windowedSize = CaptionSizing.fontSize(
            containerSize: CGSize(width: 1_200, height: 700),
            relativeCharacterSize: 1
        )
        let largeScreenSize = CaptionSizing.fontSize(
            containerSize: CGSize(width: 3_440, height: 1_440),
            relativeCharacterSize: 1
        )

        #expect(abs(windowedSize - 23.8) < 0.001)
        #expect(abs(largeScreenSize - 44) < 0.001)
    }

    @Test func systemLargeTextPreferenceIncreasesSubtitleSize() {
        let standard = CaptionSizing.fontSize(
            containerSize: CGSize(width: 3_440, height: 1_440),
            relativeCharacterSize: 1
        )
        let large = CaptionSizing.fontSize(
            containerSize: CGSize(width: 3_440, height: 1_440),
            relativeCharacterSize: 1.5
        )

        #expect(abs(standard - 44) < 0.001)
        #expect(abs(large - 66) < 0.001)
    }

    @Test func subtitleSizeStaysWithinReadableBounds() {
        let smallest = CaptionSizing.fontSize(
            containerSize: .zero,
            relativeCharacterSize: 0.5
        )
        let largest = CaptionSizing.fontSize(
            containerSize: CGSize(width: 5_120, height: 2_880),
            relativeCharacterSize: 2
        )
        let invalidPreference = CaptionSizing.normalizedScale(.nan)

        #expect(smallest == 18)
        #expect(largest == 72)
        #expect(invalidPreference == 1)
    }
}
