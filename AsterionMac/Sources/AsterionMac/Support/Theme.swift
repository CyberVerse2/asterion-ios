import AppKit
import CoreText
import SwiftUI

extension Color {
    static let asterionBackground = Color(nsColor: .windowBackgroundColor)
    static let asterionSidebar = Color(nsColor: .windowBackgroundColor)
    static let asterionSurface = Color(nsColor: .controlBackgroundColor)
    static let asterionCard = Color(nsColor: .underPageBackgroundColor)
    static let asterionText = Color.primary
    static let asterionAccent = Color(red: 0.612, green: 0.137, blue: 0.208)
    static let asterionAccentSoft = asterionAccent.opacity(0.14)
    static let asterionMuted = Color.secondary
    static let asterionBorder = Color(nsColor: .separatorColor)
    static let asterionReaderText = Color.primary
    static let asterionProgressTrack = Color(nsColor: .separatorColor)
    static let asterionSidebarText = Color.primary
    static let asterionSidebarMuted = Color.secondary
    static let asterionSidebarSelection = Color(nsColor: .selectedContentBackgroundColor)
    static let asterionSidebarAccent = asterionAccent
}

extension Font {
    static func asterionDisplay(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .custom("Literata", size: size)
            .weight(weight)
    }

    static func asterionReading(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .custom("Literata", size: size)
            .weight(weight)
    }

    static func asterionMono(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

enum AsterionFontRegistry {
    private static let fontResources = [
        "Literata-Variable",
        "Literata-Italic-Variable",
    ]

    static func registerBundledFonts() {
        for resource in fontResources {
            guard let url = Bundle.module.url(
                forResource: resource,
                withExtension: "ttf",
                subdirectory: "Fonts"
            ) else {
                preconditionFailure("Missing bundled font: \(resource).ttf")
            }

            var registrationError: Unmanaged<CFError>?
            guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registrationError) else {
                let message = registrationError?.takeRetainedValue().localizedDescription
                    ?? "Unknown Core Text registration error"
                preconditionFailure("Could not register \(resource).ttf: \(message)")
            }
        }
    }
}

enum GenreStyle {
    static func color(for genres: [String]?) -> Color {
        guard let genre = genres?.first?.lowercased() else { return .asterionMuted }
        if genre.contains("fantasy") || genre.contains("xianxia") { return Color(red: 0.55, green: 0.41, blue: 0.08) }
        if genre.contains("action") || genre.contains("martial") { return Color(red: 0.63, green: 0.32, blue: 0.18) }
        if genre.contains("romance") { return Color(red: 0.55, green: 0.23, blue: 0.38) }
        if genre.contains("sci") { return Color(red: 0.29, green: 0.42, blue: 0.54) }
        if genre.contains("horror") { return Color(red: 0.42, green: 0.23, blue: 0.23) }
        return Color(red: 0.23, green: 0.42, blue: 0.35)
    }
}
