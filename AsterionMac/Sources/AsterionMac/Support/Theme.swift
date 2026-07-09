import SwiftUI

extension Color {
    static let asterionBackground = Color(red: 0.988, green: 0.976, blue: 0.956)
    static let asterionSidebar = Color(red: 0.973, green: 0.957, blue: 0.929)
    static let asterionSurface = Color(red: 0.998, green: 0.993, blue: 0.982)
    static let asterionCard = Color(red: 0.965, green: 0.941, blue: 0.913)
    static let asterionText = Color(red: 0.145, green: 0.122, blue: 0.102)
    static let asterionGold = Color(red: 0.612, green: 0.169, blue: 0.161)
    static let asterionAccentSoft = Color(red: 0.969, green: 0.910, blue: 0.894)
    static let asterionMuted = Color(red: 0.455, green: 0.408, blue: 0.365)
    static let asterionBorder = Color(red: 0.890, green: 0.855, blue: 0.812)
    static let asterionReaderText = Color(red: 0.190, green: 0.157, blue: 0.129)
    static let asterionProgressTrack = Color(red: 0.898, green: 0.866, blue: 0.828)
}

extension Font {
    static func asterionSerif(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func asterionMono(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
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
