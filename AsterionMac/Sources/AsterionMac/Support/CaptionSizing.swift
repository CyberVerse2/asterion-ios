import Foundation
import MediaAccessibility

enum CaptionSizing {
    static let settingsDidChangeNotification = Notification.Name(
        rawValue: kMACaptionAppearanceSettingsChangedNotification as String
    )

    static var systemRelativeCharacterSize: CGFloat {
        normalizedScale(
            MACaptionAppearanceGetRelativeCharacterSize(.user, nil)
        )
    }

    static func fontSize(
        containerSize: CGSize,
        relativeCharacterSize: CGFloat
    ) -> CGFloat {
        let baseSize = min(max(containerSize.height * 0.034, 20), 44)
        return min(max(baseSize * normalizedScale(relativeCharacterSize), 18), 72)
    }

    static func normalizedScale(_ value: CGFloat) -> CGFloat {
        guard value.isFinite, value > 0 else { return 1 }
        return min(max(value, 0.5), 2)
    }
}
