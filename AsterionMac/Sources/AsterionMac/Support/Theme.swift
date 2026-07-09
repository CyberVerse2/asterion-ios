import SwiftUI

extension Color {
    static let asterionBackground = Color(red: 0.051, green: 0.047, blue: 0.043)
    static let asterionCard = Color(red: 0.102, green: 0.094, blue: 0.086)
    static let asterionText = Color(red: 0.91, green: 0.863, blue: 0.784)
    static let asterionGold = Color(red: 0.769, green: 0.643, blue: 0.29)
    static let asterionMuted = Color(red: 0.42, green: 0.392, blue: 0.349)
    static let asterionBorder = Color(red: 0.165, green: 0.153, blue: 0.133)
    static let asterionReaderText = Color(red: 0.784, green: 0.722, blue: 0.627)
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
