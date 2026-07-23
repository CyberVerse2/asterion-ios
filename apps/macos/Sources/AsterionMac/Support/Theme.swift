import AppKit
import SwiftUI

extension Color {
    static let asterionBackground = Color(nsColor: .windowBackgroundColor)
    static let asterionMediaCanvas = Color(red: 0.165, green: 0.165, blue: 0.185)
    static let asterionSidebar = Color(nsColor: .windowBackgroundColor)
    static let asterionSurface = Color(nsColor: .controlBackgroundColor)
    static let asterionCard = Color(nsColor: .underPageBackgroundColor)
    static let asterionText = Color.primary
    static let asterionAccent = Color.accentColor
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
        .system(size: size, weight: weight, design: .default)
    }

    static func asterionReading(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func asterionMono(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

private struct AsterionDetailTitleStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.asterionDisplay(22, weight: .semibold))
            .foregroundStyle(Color.asterionText)
            .lineLimit(3)
            .minimumScaleFactor(0.78)
            .allowsTightening(true)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .layoutPriority(1)
    }
}

extension View {
    func asterionDetailTitleStyle() -> some View {
        modifier(AsterionDetailTitleStyle())
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
