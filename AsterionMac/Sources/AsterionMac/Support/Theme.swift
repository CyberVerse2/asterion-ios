import CoreText
import SwiftUI

extension Color {
    static let asterionCanvas = Color(red: 0.867, green: 0.882, blue: 0.906)
    static let asterionBackground = Color(red: 0.949, green: 0.953, blue: 0.961)
    static let asterionSidebar = Color(red: 0.925, green: 0.933, blue: 0.945)
    static let asterionSurface = Color.white
    static let asterionCard = Color(red: 0.910, green: 0.918, blue: 0.929)
    static let asterionText = Color(red: 0.102, green: 0.106, blue: 0.122)
    static let asterionAccent = Color(red: 0.612, green: 0.137, blue: 0.208)
    static let asterionAccentSoft = Color(red: 0.953, green: 0.867, blue: 0.886)
    static let asterionMuted = Color(red: 0.333, green: 0.361, blue: 0.400)
    static let asterionBorder = Color(red: 0.788, green: 0.808, blue: 0.835)
    static let asterionReaderText = Color(red: 0.125, green: 0.129, blue: 0.149)
    static let asterionProgressTrack = Color(red: 0.843, green: 0.859, blue: 0.878)
    static let asterionSidebarText = Color(red: 0.133, green: 0.137, blue: 0.153)
    static let asterionSidebarMuted = Color(red: 0.392, green: 0.416, blue: 0.451)
    static let asterionSidebarSelection = Color.white
    static let asterionSidebarAccent = Color(red: 0.612, green: 0.137, blue: 0.208)
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
