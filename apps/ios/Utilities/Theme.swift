import SwiftUI
import UIKit

extension Color {
    static let asterionBackground = Color.family(light: 0xFBFAF9, dark: 0x121212)
    static let asterionCard = Color.family(light: 0xF2F0ED, dark: 0x1C1B19)
    static let asterionText = Color.family(light: 0x121212, dark: 0xFBFAF9)
    static let goldAccent = Color.family(light: 0x121212, dark: 0xFBFAF9)
    static let asterionMuted = Color.family(light: 0x7E7E7D, dark: 0x9A9894)
    static let asterionDim = Color.family(light: 0x474645, dark: 0x8A8884)
    static let asterionBorder = Color.family(light: 0xE6E4E1, dark: 0x3A3834)
    static let asterionCardHover = Color.family(light: 0xF6F4EF, dark: 0x242220)
    static let asterionBorderHover = Color.family(light: 0xD4D2CE, dark: 0x4A4742)
    static let asterionReaderText = Color.family(light: 0x343433, dark: 0xF2F0ED)
    static let asterionSynopsis = Color.family(light: 0x474645, dark: 0x9A9894)
    static let asterionInk = Color.family(light: 0x121212, dark: 0xFBFAF9)
    static let asterionOnInk = Color.family(light: 0xFBFAF9, dark: 0x121212)
    static let asterionHighlight = Color(red: 0.831, green: 0.561, blue: 0.0)

    fileprivate static func family(light: UInt32, dark: UInt32) -> Color {
        Color(
            uiColor: UIColor { traits in
                UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
            }
        )
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Font {
    static func asterionDisplay(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        let name: String
        switch weight {
        case .light: name = "CormorantGaramond-Light"
        case .semibold, .bold, .heavy, .black: name = "CormorantGaramond-SemiBold"
        default: name = "CormorantGaramond-Medium"
        }
        return .custom(name, size: size)
    }

    static func asterionReading(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func asterionSerif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func asterionLiterary(_ size: CGFloat) -> Font {
        .custom("CormorantGaramond-Regular", size: size)
    }

    static func asterionMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

enum AsterionLayout {
    static func isWide(_ sizeClass: UserInterfaceSizeClass?) -> Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        UIDevice.current.userInterfaceIdiom == .pad && sizeClass == .regular
        #endif
    }

    static func pageMaxWidth(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        #if targetEnvironment(macCatalyst)
        1460
        #else
        isWide(sizeClass) ? 1180 : .infinity
        #endif
    }

    static func pagePadding(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        #if targetEnvironment(macCatalyst)
        46
        #else
        isWide(sizeClass) ? 32 : 24
        #endif
    }

    static func posterColumns(_ sizeClass: UserInterfaceSizeClass?) -> [GridItem] {
        if isWide(sizeClass) {
            return [GridItem(.adaptive(minimum: 158, maximum: 210), spacing: 16, alignment: .top)]
        }
        return [
            GridItem(.flexible(minimum: 0), spacing: 14),
            GridItem(.flexible(minimum: 0)),
        ]
    }

    static func episodeColumns(_ sizeClass: UserInterfaceSizeClass?) -> [GridItem] {
        if isWide(sizeClass) {
            return [GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 16, alignment: .top)]
        }
        return [GridItem(.flexible(minimum: 0))]
    }

    static func continueCardSize(_ sizeClass: UserInterfaceSizeClass?) -> CGSize {
        isWide(sizeClass) ? CGSize(width: 360, height: 216) : CGSize(width: 280, height: 168)
    }

    static func shelfPosterSize(_ sizeClass: UserInterfaceSizeClass?) -> CGSize {
        isWide(sizeClass) ? CGSize(width: 176, height: 254) : CGSize(width: 148, height: 214)
    }
}

struct AsterionBackdrop: View {
    var body: some View {
        Color.asterionBackground.ignoresSafeArea()
    }
}

extension View {
    func asterionGlassSurface(
        cornerRadius: CGFloat = 32,
        interactive: Bool = false
    ) -> some View {
        self.asterionInsetSurface(cornerRadius: cornerRadius)
    }

    func asterionGlassPill(isSelected: Bool, interactive: Bool = true) -> some View {
        self.background(
            isSelected ? Color.asterionInk : Color.asterionCard,
            in: Capsule()
        )
        .foregroundStyle(isSelected ? Color.asterionOnInk : Color.asterionText)
    }

    func asterionInsetSurface(cornerRadius: CGFloat = 32) -> some View {
        self.background(
            Color.asterionCard,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}

struct AsterionFilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.asterionOnInk)
            .background(
                Color.asterionInk.opacity(configuration.isPressed ? 0.82 : 1),
                in: Capsule()
            )
    }
}

struct AsterionOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.asterionText)
            .background(
                Color.asterionCard.opacity(configuration.isPressed ? 0.7 : 1),
                in: Capsule()
            )
    }
}
